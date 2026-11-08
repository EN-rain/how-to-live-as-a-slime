class_name SlimeMotor
extends RefCounted
## Single owner of a slime's physical transform, velocity, support and posture.
##
## Movement is sweep-then-slide against real obstacle geometry: advance to the safe
## fraction, preserve the remainder along the contact tangent, and keep EVERY
## blocking contact as a constraint (a dead end stops motion even between side
## walls). Posture/expansion changes are collision-tested over the whole footprint
## before being committed. Nothing else may write the actor's position.

const LAYER_OBSTACLES := 1
## Other slimes publish a baked-hull proxy on this layer. Horizontal sweeps,
## posture probes and recovery see them; support/ceiling do not (a slime is not
## ground and must not be climbed).
const LAYER_SLIMES := 2
const LAYER_SOLID := LAYER_OBSTACLES | LAYER_SLIMES
## Minimum intermediate probes between the resolved and the candidate posture.
## Actual density is derived from vertex displacement so a thin wall can never slip
## between samples at low tick rates.
const PROBE_STEPS := 2
const MAX_PROBE_STEPS := 12

var owner_node: Node3D
var model: SlimeShapeModel
var tuning: SlimeTuning

var velocity := Vector3.ZERO
var vertical_vel := 0.0
var support_y := -1.2
var on_ground := true
var ground_body: Object = null

## Why the requested posture could not be reached ("" when unrestricted).
var expansion_blocked := ""
var last_sweep_fraction := 1.0
var contact_normals: Array[Vector3] = []
var contact_bodies: Array[Object] = []
## Largest normal velocity removed by a contact during the last horizontal move.
var impact_speed := 0.0

var _probe_shape: ConvexPolygonShape3D
var _adhoc_shape: ConvexPolygonShape3D
var _exclude: Array[RID] = []

func _apply_probe(pts: PackedVector3Array) -> void:
	_probe_shape.set_points(pts)


## Reusable shape for one-off hull queries (ceiling probes, spawn/merge preflight) so
## they do not allocate and rebuild a fresh ConvexPolygonShape3D on every call.
func adhoc_probe(pts: PackedVector3Array) -> ConvexPolygonShape3D:
	_adhoc_shape.set_points(pts)
	return _adhoc_shape


func setup(node: Node3D, shape_model: SlimeShapeModel, t: SlimeTuning) -> void:
	owner_node = node
	model = shape_model
	tuning = t
	support_y = t.floor_y
	_probe_shape = ConvexPolygonShape3D.new()
	_adhoc_shape = ConvexPolygonShape3D.new()


func set_exclude(rids: Array[RID]) -> void:
	_exclude = rids


func _space() -> PhysicsDirectSpaceState3D:
	return owner_node.get_world_3d().direct_space_state


func _sync_foot() -> void:
	model.set_foot(owner_node.global_position + Vector3(0, -model.rest_half_height * model.scale, 0))


func _query(at_foot: Vector3, probe: Shape3D = null, use_exclude := true, mask := LAYER_SOLID) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe if probe != null else model.shape
	q.transform = Transform3D(Basis.IDENTITY, at_foot)
	q.collision_mask = mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = _exclude if use_exclude else []
	return q


## Push out of any initial overlap along the AVERAGE of up to 8 contact normals.
## A corner or corridor produces opposing normals; following them one at a time
## ping-pongs and can leave the body inside. Averaging finds the real escape.
func recover_overlap() -> void:
	_sync_foot()
	var space := _space()
	for _i in tuning.recovery_iterations:
		var q := _query(model.foot)
		q.exclude = _exclude.duplicate()
		var sum := Vector3.ZERO
		var first := Vector3.ZERO
		var count := 0
		for _h in 8:
			var rest := space.get_rest_info(q)
			if rest.is_empty():
				break
			var n: Vector3 = rest.normal
			if n.length_squared() < 1e-6:
				break
			n = n.normalized()
			if count == 0:
				first = n
			sum += n
			count += 1
			var rid = rest.get("rid")
			if rid is RID:
				q.exclude.append(rid)
		if count == 0:
			return
		var avg := sum.normalized() if sum.length_squared() > 1e-6 else first
		var want := tuning.skin * 2.0 + 0.01
		var fr := _cast(model.foot, avg * want)
		var safe: float = fr[0]
		var unsafe: float = fr[1]
		var step := want
		if not (safe <= 0.0 and unsafe <= 0.0):
			# Clear sweep (or partial): never force past whatever lies in the way.
			step = want * clampf(safe, 0.0, 1.0)
			if step <= 1e-4:
				return
		# A start-in-collision cast reports 0/0; the averaged contact normal is the
		# only escape direction, so allow the single bounded skin push.
		owner_node.global_position += avg * step
		var into := velocity.dot(avg)
		if into < 0.0:
			velocity = velocity.slide(avg)
		_sync_foot()


## Swept inward correction keeping the body inside the arena disc.
func clamp_to_arena(center: Vector3, radius: float) -> void:
	var flat := Vector2(owner_node.global_position.x - center.x, owner_node.global_position.z - center.z)
	var dist := flat.length()
	if dist <= radius:
		return
	_sync_foot()
	var inward := Vector3(-flat.x, 0.0, -flat.y) / maxf(dist, 1e-4) * (dist - radius)
	var fr := _cast(model.foot, inward)
	var safe: float = fr[0]
	var unsafe: float = fr[1]
	if unsafe >= 0.999999:
		safe = 1.0
	owner_node.global_position += inward * clampf(safe, 0.0, 1.0)
	_sync_foot()


## Sweep the current envelope (or `probe`); returns [safe, unsafe] fractions.
func _cast(from_foot: Vector3, motion: Vector3, use_exclude := true, probe: Shape3D = null, mask := LAYER_SOLID) -> Array:
	var q := _query(from_foot, probe, use_exclude, mask)
	q.motion = motion
	return _space().cast_motion(q)


func _contact_rest(at_foot: Vector3) -> Dictionary:
	return _space().get_rest_info(_query(at_foot))


## Horizontal sweep + slide, subdivided into chunks no larger than the sweep budget
## so the full requested displacement is always attempted. Sliding leftovers of a
## chunk rejoin the pending motion. Every accumulated contact stays a constraint.
func move_horizontal(motion: Vector3) -> void:
	contact_normals.clear()
	contact_bodies.clear()
	impact_speed = 0.0
	last_sweep_fraction = 1.0
	var max_step := model.rest_max_radius * model.scale * tuning.max_step_fraction
	_sync_foot()
	# A cast that begins inside geometry reports no blocking hit (Jolt ignores initial
	# overlap), which would let the hull creep through a face it already grazes. Motion
	# is allowed while a graze does not deepen, so a flush shoulder can slide clear,
	# but the hull may never be pushed further into geometry.
	var depth_before := overlap_depth(LAYER_OBSTACLES) if not hull_clear(tuning.skin * 0.5) else 0.0
	var start_pos := owner_node.global_position
	var pending := motion
	var guard := 0
	while pending.length_squared() > 1e-10 and guard < 64:
		guard += 1
		var plen := pending.length()
		var chunk := pending if plen <= max_step else pending * (max_step / plen)
		pending -= chunk
		for _i in tuning.slide_iterations:
			if chunk.length_squared() < 1e-10:
				break
			var fr := _cast(model.foot, chunk)
			var safe: float = fr[0]
			var unsafe: float = fr[1]
			if unsafe >= 0.999999:
				owner_node.global_position += chunk
				_sync_foot()
				last_sweep_fraction = minf(last_sweep_fraction, safe)
				chunk = Vector3.ZERO
				break
			owner_node.global_position += chunk * safe
			_sync_foot()
			last_sweep_fraction = minf(last_sweep_fraction, safe)
			var rest := _contact_rest(model.foot + chunk * unsafe)
			if rest.is_empty():
				chunk = Vector3.ZERO
				break
			var n: Vector3 = rest.normal
			n = Vector3(n.x, 0.0, n.z)
			if n.length_squared() < 1e-6:
				chunk = Vector3.ZERO
				break
			n = n.normalized()
			if not contact_normals.has(n):
				contact_normals.append(n)
			if rest.get("collider") != null:
				contact_bodies.append(rest.get("collider"))
			var into := velocity.dot(n)
			if into < 0.0:
				impact_speed = maxf(impact_speed, -into)
				velocity = velocity.slide(n)
			var slid := chunk.slide(n) * (1.0 - safe)
			# Project against every wall met this move: two alternating normals must
			# not let the remainder sneak diagonally between them.
			for cn in contact_normals:
				if slid.dot(cn) < 0.0:
					slid = slid.slide(cn)
			chunk = slid
		# Whatever the sweep/slide could not use stays in the budget for the next
		# substep instead of being dropped on the floor.
		pending += chunk
	# Deeper-than-before is a single erosion probe: if the hull still penetrates after
	# eroding by the old depth plus the tolerance, the move deepened it and is reverted.
	if depth_before > 0.0 and not hull_clear_mask(depth_before + 1e-3, LAYER_OBSTACLES):
		owner_node.global_position = start_pos
		_sync_foot()
		contact_normals.clear()
		contact_bodies.clear()
		last_sweep_fraction = 0.0


## Downward support query; raises support when stepping onto reachable geometry.
## Food still supports weight, so support queries ignore the edible exclusion.
func update_support() -> void:
	_sync_foot()
	# Reach blends continuously with liquid so crossing a posture threshold never
	# makes the body jump onto (or off) a ledge.
	var reach := lerpf(tuning.climb_reach, tuning.liquid_climb_reach, model.liquid) * model.scale
	var start := model.foot + Vector3(0, reach, 0)
	var fr := _cast(start, Vector3(0, -(reach + 2.0 * model.scale), 0), false, null, LAYER_OBSTACLES)
	var unsafe: float = fr[1]
	var best := tuning.floor_y
	var body: Object = null
	if unsafe < 0.999999:
		var at := start + Vector3(0, -(reach + 2.0 * model.scale), 0) * unsafe
		var rest := _space().get_rest_info(_query(at, null, false, LAYER_OBSTACLES))
		if not rest.is_empty() and rest.normal.y > 0.5:
			var top: float = rest.point.y
			if top <= model.foot.y + reach + tuning.skin and top > best:
				# Do not accept a step-up the body cannot physically rise onto
				# (low roof above the ledge), otherwise support lifts it into the ceiling.
				var rise := top + tuning.skin - model.foot.y
				if rise <= 1e-4 or ceiling_clearance_up(rise) >= rise - 1e-4:
					best = top
					body = rest.get("collider")
	support_y = best
	ground_body = body


## Free rise above the current envelope top, up to max_rise. INF when the corridor
## above the whole footprint is clear. Obstacles are included (food blocks a stand-up
## just like a wall does). `probe` lets the caller measure a candidate posture.
func ceiling_clearance_up(max_rise: float, probe: Shape3D = null) -> float:
	if max_rise <= 0.0:
		return 0.0
	_sync_foot()
	var fr := _cast(model.foot, Vector3(0.0, max_rise, 0.0), false, probe, LAYER_OBSTACLES)
	var unsafe: float = fr[1]
	if unsafe >= 0.999999:
		return INF
	return maxf(0.0, unsafe * max_rise - tuning.skin)


## Vertical integration anchored to support; never sinks below the floor, and every
## position change is the result of a downward/upward sweep.
func move_vertical(dt: float, target_scale: float) -> void:
	var target_foot := support_y + tuning.skin
	var foot_y := owner_node.global_position.y - model.rest_half_height * model.scale
	var shrinking := target_scale < model.scale - 0.01
	var desired := 0.0
	if foot_y > target_foot + 0.02 and not shrinking:
		on_ground = false
		vertical_vel -= tuning.gravity * dt
		desired = vertical_vel * dt
	else:
		vertical_vel = 0.0
		on_ground = true
		desired = (target_foot - foot_y) * (1.0 - exp(-16.0 * dt))
	if absf(desired) <= 1e-7:
		_sync_foot()
		return
	var safe := _sweep_vertical(desired)
	var next_foot := foot_y + desired * safe
	if desired < 0.0 and next_foot < target_foot:
		next_foot = target_foot
	if safe < 0.999999:
		vertical_vel = 0.0
		on_ground = true
	owner_node.global_position.y = next_foot + model.rest_half_height * model.scale
	_sync_foot()


## Safe fraction of a vertical hull sweep (1.0 when the corridor is clear).
func _sweep_vertical(delta: float) -> float:
	_sync_foot()
	var fr := _cast(model.foot, Vector3(0.0, delta, 0.0))
	var safe: float = fr[0]
	var unsafe: float = fr[1]
	if unsafe >= 0.999999:
		return 1.0
	return clampf(safe, 0.0, 1.0)


## Collision-test a posture transition over the whole footprint (current + proposed
## + intermediate bounds). Returns true when the target posture is legal.
func posture_is_legal(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> bool:
	# Opposite directions describe the same ellipse. Canonicalise before comparing
	# or interpolating so a sign flip never lerps the axis through zero.
	if p_axis.length_squared() > 1e-8 and model.axis.length_squared() > 1e-8 \
			and p_axis.dot(model.axis) < 0.0:
		p_axis = -p_axis

	# Unchanged posture is trivially legal; skip rebuilding the convex hull.
	if absf(p_scale - model.scale) < 1e-4 and absf(p_liquid - model.liquid) < 1e-4 \
			and absf(p_height_ratio - model.height_ratio) < 1e-4 \
			and absf(p_squeeze - model.squeeze) < 1e-4 \
			and p_axis.distance_squared_to(model.axis) < 1e-4:
		return true

	_sync_foot()
	var space := _space()

	# Probe density follows the largest vertex movement: consecutive hulls differ by
	# at most half a skin, so activation is never missed between two samples.
	var cur_pts := model.resolved_points()
	var dst_pts := model.baked_points(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis)
	var max_disp_sq := 0.0
	for i in mini(cur_pts.size(), dst_pts.size()):
		max_disp_sq = maxf(max_disp_sq, cur_pts[i].distance_squared_to(dst_pts[i]))
	var steps := clampi(int(ceil(sqrt(max_disp_sq) / maxf(tuning.skin * 0.5, 1e-4))), PROBE_STEPS, MAX_PROBE_STEPS)
	# Convex shapes carry a collision margin, so a hull sliding along a face reads as
	# intersecting. Probe an envelope eroded by that margin: only penetration deeper
	# than it (the harness tolerance) may veto a transition.
	var margin := tuning.skin * 2.0
	# Start at the first *new* pose: the current pose is the body's actual state, so
	# re-testing it only lets a sub-skin graze veto the transition it needs to escape.
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var sc := lerpf(model.scale, p_scale, t)
		var lq := lerpf(model.liquid, p_liquid, t)
		var hr := lerpf(model.height_ratio, p_height_ratio, t)
		var sq := lerpf(model.squeeze, p_squeeze, t)
		var ax := model.axis.lerp(p_axis, t)
		var pts := _erode(model.baked_points(sc, lq, hr, sq, ax), margin)
		_apply_probe(pts)
		# Posture is a soft deformation: partners are resolved by the pairwise pass,
		# so a tail touching another slime must never deadlock a legal squeeze.
		var q := _query(model.foot, _probe_shape, true, LAYER_OBSTACLES)
		if not space.intersect_shape(q, 1).is_empty():
			return false
	return true


## Shrink a baked envelope radially and from the top by `margin`. The top is taken
## from the points themselves so a candidate posture is clipped to ITS height, not
## to the currently resolved one.
func _erode(pts: PackedVector3Array, margin: float) -> PackedVector3Array:
	var n := pts.size()
	var top := 0.0
	for i in n:
		top = maxf(top, pts[i].y)
	top = maxf(0.0, top - margin)
	for i in n:
		var p := pts[i]
		var r := sqrt(p.x * p.x + p.z * p.z)
		var f := maxf(0.0, r - margin) / maxf(r, 1e-5)
		pts[i] = Vector3(p.x * f, minf(p.y, top), p.z * f)
	return pts


## True when the candidate posture alone (no intermediate path) clears geometry.
## Used for an instantaneous snap: the committed state is what the physics and the
## per-tick invariants ever see, and intermediate hulls of a narrowing transition
## are larger than both endpoints, so a full-path probe can veto a legal target.
func posture_target_is_legal(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> bool:
	if p_axis.length_squared() > 1e-8 and model.axis.length_squared() > 1e-8 \
			and p_axis.dot(model.axis) < 0.0:
		p_axis = -p_axis
	_sync_foot()
	_apply_probe(_erode(model.baked_points(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis), tuning.skin * 2.0))
	return _space().intersect_shape(_query(model.foot, _probe_shape, true, LAYER_OBSTACLES), 1).is_empty()


## True when the committed hull, eroded by `margin`, touches no level geometry.
## Partner overlap is the pairwise separation pass's job, not a locomotion veto.
func hull_clear(margin: float) -> bool:
	return hull_clear_mask(margin, LAYER_OBSTACLES)


## Layer-limited variant: level geometry only, ignoring slime proxies.
func hull_clear_mask(margin: float, mask: int) -> bool:
	_sync_foot()
	var pts := _erode(model.resolved_points().duplicate(), margin)
	_apply_probe(pts)
	return _space().intersect_shape(_query(model.foot, _probe_shape, true, mask), 1).is_empty()


## Spawn preflight: does a clone's target hull at `at_foot` clear geometry and other
## slimes? The spawner stays excluded through this body's own exclusion list.
func spawn_is_clear(at_foot: Vector3, p_scale: float) -> bool:
	var shape := adhoc_probe(_erode(model.baked_points(p_scale, 0.0, 1.0, 1.0, Vector3.RIGHT), tuning.skin * 2.0))
	return _space().intersect_shape(_query(at_foot, shape, true, LAYER_SOLID), 1).is_empty()


## Sweep a hull of `p_scale` from `from_foot` to `to_foot`. True when level geometry
## never blocks the whole path, not merely its endpoints.
func sweep_is_clear(from_foot: Vector3, to_foot: Vector3, p_scale: float) -> bool:
	var shape := adhoc_probe(_erode(model.baked_points(p_scale, 0.0, 1.0, 1.0, Vector3.RIGHT), tuning.skin * 2.0))
	var fr := _cast(from_foot, to_foot - from_foot, true, shape, LAYER_OBSTACLES)
	return fr[1] >= 0.999999


## Penetration depth beyond the collision margin, measured as the smallest radial
## erosion of the committed hull that clears `mask`. Zero when already clear.
func overlap_depth(mask: int, cap := 0.2) -> float:
	if hull_clear_mask(cap, mask):
		var lo := 0.0
		var hi := cap
		for _i in 5:
			var mid := (lo + hi) * 0.5
			if hull_clear_mask(mid, mask):
				hi = mid
			else:
				lo = mid
		return hi
	return cap


func describe_block(p_height_ratio: float, p_squeeze: float) -> String:
	if p_height_ratio > model.height_ratio + 1e-4:
		return "overhead/ceiling blocks standing"
	if p_squeeze < model.squeeze - 1e-4:
		return "side walls block narrowing"
	return "expansion blocked by geometry"