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
## Upper bound on transition probes. Intermediate poses come from the shared
## quantized hull cache, so a step is one intersect query with no rebuild. Four
## steps let a follower clip a gate lip (harness phase 9), so the density that
## follows vertex displacement is kept intact.
const MAX_PROBE_STEPS := 12
## Horizontal motion is split into at most this many equal budgeted substeps. The
## old loop re-accumulated slide leftovers up to 64 times, turning a corner grind
## into hundreds of casts per tick.
const MAX_MOVE_SUBSTEPS := 6

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
var _query_params: PhysicsShapeQueryParameters3D
var _exclude: Array[RID] = []

## Process-wide instrumentation (F3 overlay). Totals; the HUD derives per-tick rates.
static var debug_cast_count := 0
static var debug_intersect_count := 0
static var debug_rest_count := 0
static var debug_set_points_count := 0

func _apply_probe(pts: PackedVector3Array) -> void:
	debug_set_points_count += 1
	_probe_shape.set_points(pts)


## Reusable shape for one-off hull queries (ceiling probes, spawn/merge preflight) so
## they do not allocate and rebuild a fresh ConvexPolygonShape3D on every call.
func adhoc_probe(pts: PackedVector3Array) -> ConvexPolygonShape3D:
	debug_set_points_count += 1
	_adhoc_shape.set_points(pts)
	return _adhoc_shape


func setup(node: Node3D, shape_model: SlimeShapeModel, t: SlimeTuning) -> void:
	owner_node = node
	model = shape_model
	tuning = t
	support_y = t.floor_y
	_probe_shape = ConvexPolygonShape3D.new()
	_adhoc_shape = ConvexPolygonShape3D.new()
	_query_params = PhysicsShapeQueryParameters3D.new()
	_core_sphere_shape = SphereShape3D.new()


var _core_sphere_shape: SphereShape3D

func core_sphere_shape(radius := -1.0) -> SphereShape3D:
	if _core_sphere_shape == null:
		_core_sphere_shape = SphereShape3D.new()
	var r := radius if radius > 0.0 else model.core_sphere_radius()
	_core_sphere_shape.radius = r
	return _core_sphere_shape


## True when the invisible core sphere clears level geometry at `at_center`.
func core_sphere_clear(at_center: Vector3, radius := -1.0) -> bool:
	var q := _query(at_center, core_sphere_shape(radius), true, LAYER_OBSTACLES)
	q.transform = Transform3D(Basis.IDENTITY, at_center)
	debug_intersect_count += 1
	return _space().intersect_shape(q, 1).is_empty()


## Sweeps the invisible core sphere along `motion`; returns [safe, unsafe] fractions.
func cast_core_sphere(from_center: Vector3, motion: Vector3, radius := -1.0) -> Array:
	debug_cast_count += 1
	var shape := core_sphere_shape(radius)
	var q := _query_params
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, from_center)
	q.motion = motion
	q.collision_mask = LAYER_OBSTACLES
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = _exclude
	return _space().cast_motion(q)


## True when the invisible inner core fits past the obstacle that blocks the outer hull ahead.
func core_can_pass_ahead(fwd: Vector3) -> bool:
	_sync_foot()
	var r_outer := model.rest_max_radius * model.scale * model.spread
	var probe_dist := r_outer + 0.45
	var core := model.core_shape(1)
	var fr := _cast(model.foot, fwd * probe_dist, true, core, LAYER_OBSTACLES)
	return float(fr[1]) >= 0.99


func set_exclude(rids: Array[RID]) -> void:
	_exclude = rids


func _space() -> PhysicsDirectSpaceState3D:
	return owner_node.get_world_3d().direct_space_state


func _sync_foot() -> void:
	model.set_foot(owner_node.global_position + Vector3(0, -model.rest_half_height * model.scale, 0))


## Reuses one parameters object: every query path configures the fields it reads
## and consumes the result synchronously, so a shared instance is safe and avoids
## an allocation per probe.
func _query(at_foot: Vector3, probe: Shape3D = null, use_exclude := true, mask := LAYER_SOLID) -> PhysicsShapeQueryParameters3D:
	var q := _query_params
	q.shape = probe if probe != null else model.shape
	q.transform = Transform3D(Basis.IDENTITY, at_foot)
	q.motion = Vector3.ZERO
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
			debug_rest_count += 1
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
	debug_cast_count += 1
	var q := _query(from_foot, probe, use_exclude, mask)
	q.motion = motion
	return _space().cast_motion(q)


func _contact_rest(at_foot: Vector3, probe: Shape3D = null) -> Dictionary:
	debug_rest_count += 1
	return _space().get_rest_info(_query(at_foot, probe))


## Horizontal sweep + slide. When the outer hull touches an opening that the Core Sphere
## clears, the Core Sphere immediately carries the body through; against solid walls,
## it slides smoothly without sticky position reverts.
func move_horizontal(motion: Vector3) -> void:
	contact_normals.clear()
	contact_bodies.clear()
	impact_speed = 0.0
	last_sweep_fraction = 1.0
	_sync_foot()
	var space := _space()
	var core_probe := model.core_shape(1)
	var started_clear := _probe_shape_at(space, core_probe)
	var start_pos := owner_node.global_position
	var max_step := maxf(model.rest_max_radius * model.scale * tuning.max_step_fraction, 0.12)
	var steps := clampi(int(ceil(motion.length() / maxf(max_step, 1e-3))), 1, MAX_MOVE_SUBSTEPS)
	var chunk := motion / float(steps)
	for _s in steps:
		if chunk.length_squared() < 1e-10:
			break
		var stalled := 0
		var slid := chunk
		for _i in tuning.slide_iterations:
			if slid.length_squared() < 1e-10:
				break
			var active_shape: Shape3D = model.shape
			var fr := _cast(model.foot, slid, true, active_shape)
			var safe: float = fr[0]
			var unsafe: float = fr[1]
			if unsafe < 0.999999 and model.squeeze > model.min_squeeze() + 1e-3:
				var dir_n := slid.normalized()
				if core_can_pass_ahead(dir_n):
					active_shape = model.core_shape(0)
					fr = _cast(model.foot, slid, true, active_shape)
					safe = fr[0]
					unsafe = fr[1]
			if unsafe >= 0.999999:
				owner_node.global_position += slid
				_sync_foot()
				last_sweep_fraction = minf(last_sweep_fraction, safe)
				break
			owner_node.global_position += slid * safe
			_sync_foot()
			last_sweep_fraction = minf(last_sweep_fraction, safe)

			if safe <= 1e-5:
				stalled += 1
				if stalled >= 2:
					break
			else:
				stalled = 0
			var rest := _contact_rest(model.foot + slid * unsafe, active_shape)
			if rest.is_empty():
				break
			var n: Vector3 = rest.normal
			n = Vector3(n.x, 0.0, n.z)
			if n.length_squared() < 1e-6:
				break
			n = n.normalized()
			if not contact_normals.has(n):
				contact_normals.append(n)
			if rest.get("collider") != null:
				contact_bodies.append(rest.get("collider"))
			# Tiny skin separation along normal so the next slide cast never starts in overlap
			owner_node.global_position += n * 0.0015
			_sync_foot()
			var into := velocity.dot(n)
			if into < 0.0:
				impact_speed = maxf(impact_speed, -into)
				velocity = velocity.slide(n)
			slid = slid.slide(n) * (1.0 - safe)
	if started_clear and not _probe_shape_at(space, core_probe):
		owner_node.global_position = start_pos
		_sync_foot()
		contact_normals.clear()
		contact_bodies.clear()
		last_sweep_fraction = 0.0


## Apply a caller-computed slime-vs-slime correction. The push only has to clear
## level geometry: the partner hull is deliberately not swept against, otherwise the
## correction would veto itself. Returns the fraction of `push` actually traversed so
## the caller can hand a blocked share to the other body.
func apply_slime_separation(push: Vector3, normal: Vector3) -> float:
	if push.length_squared() < 1e-10:
		return 0.0
	var n := Vector3(normal.x, 0.0, normal.z)
	if n.length_squared() > 1e-8:
		n = n.normalized()
		if velocity.dot(n) < 0.0:
			velocity = velocity.slide(n)
	_sync_foot()
	var fr := _cast(model.foot, push, true, null, LAYER_OBSTACLES)
	var safe: float = fr[0]
	var unsafe: float = fr[1]
	# A clear path reports 1/1. A cast that begins inside geometry reports 0/0, which
	# must NOT be read as "free": separating deeper into a wall the body already grazes
	# makes it worse, so the caller hands the blocked share to the other body instead.
	if unsafe >= 0.999999:
		safe = 1.0
	safe = clampf(safe, 0.0, 1.0)
	if safe > 1e-5:
		owner_node.global_position += push * safe
		_sync_foot()
	return safe


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
		debug_rest_count += 1
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
	_sync_foot()
	return ceiling_clearance_from(model.foot, max_rise, probe)


func ceiling_clearance_from(from_foot: Vector3, max_rise: float, probe: Shape3D = null) -> float:
	if max_rise <= 0.0:
		return 0.0
	var fr := _cast(from_foot, Vector3(0.0, max_rise, 0.0), false, probe, LAYER_OBSTACLES)
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
	# Probe the target first: geometry that forbids it rejects the transition on the
	# first query instead of walking the whole path. The current pose is skipped: it
	# is the body's actual state, so a sub-skin graze must not veto the escape.
	# A posture that grows radially is tested with the tight-erosion hull: the soft
	# envelope may only reach tuning.skin * 0.5 into geometry while expanding, instead
	# of the 2 * skin slack a shrink may tolerate.
	var variant := _probe_variant_for(p_scale, p_liquid, p_squeeze)
	if not _probe_shape_at(space, model.cached_shape(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis, variant)):
		return false
	# Cached hulls are quantized: an unchanged resource is the same hull, so it only
	# needs to be tested once.
	var last_shape: ConvexPolygonShape3D = null
	for s in range(1, steps):
		var t := float(s) / float(steps)
		var shape := model.cached_shape(
			lerpf(model.scale, p_scale, t), lerpf(model.liquid, p_liquid, t),
			lerpf(model.height_ratio, p_height_ratio, t), lerpf(model.squeeze, p_squeeze, t),
			model.axis.lerp(p_axis, t), variant)
		if shape == last_shape:
			continue
		last_shape = shape
		if not _probe_shape_at(space, shape):
			return false
	return true


## Hull erosion variant for a candidate posture: 2 (skin * 0.5) while the body
## grows, 1 (skin * 2) while it narrows or holds.
func _probe_variant_for(p_scale: float, p_liquid: float, p_squeeze: float) -> int:
	if p_scale > model.scale + 1e-4 or p_liquid > model.liquid + 1e-4 or p_squeeze > model.squeeze + 1e-4:
		return 2
	return 1


## Convex shapes carry a collision margin, so transition probes use an envelope
## eroded by it: only deeper penetration may veto. Posture is a soft deformation,
## and partners are resolved by the pairwise pass, so a tail touching another slime
## must never deadlock a legal squeeze.
func _probe_shape_at(space: PhysicsDirectSpaceState3D, shape: Shape3D) -> bool:
	debug_intersect_count += 1
	return space.intersect_shape(_query(model.foot, shape, true, LAYER_OBSTACLES), 1).is_empty()


## True when the candidate posture alone (no intermediate path) clears geometry.
## Used for an instantaneous snap: the committed state is what the physics and the
## per-tick invariants ever see, and intermediate hulls of a narrowing transition
## are larger than both endpoints, so a full-path probe can veto a legal target.
func posture_target_is_legal(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> bool:
	if p_axis.length_squared() > 1e-8 and model.axis.length_squared() > 1e-8 \
			and p_axis.dot(model.axis) < 0.0:
		p_axis = -p_axis
	_sync_foot()
	var shape := model.cached_shape(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis,
		_probe_variant_for(p_scale, p_liquid, p_squeeze))
	debug_intersect_count += 1
	return _space().intersect_shape(_query(model.foot, shape, true, LAYER_OBSTACLES), 1).is_empty()


## True when the committed hull, eroded by `margin`, touches no level geometry.
## Partner overlap is the pairwise separation pass's job, not a locomotion veto.
func hull_clear(margin: float) -> bool:
	return hull_clear_mask(margin, LAYER_OBSTACLES)


## Layer-limited variant: level geometry only, ignoring slime proxies.
func hull_clear_mask(margin: float, mask: int) -> bool:
	_sync_foot()
	var shape: Shape3D
	if absf(margin - tuning.skin * 0.5) < 1e-5:
		shape = model.cached_shape(model.scale, model.liquid, model.height_ratio, model.squeeze, model.axis, 2)
	elif absf(margin - tuning.skin * 2.0) < 1e-5:
		shape = model.cached_shape(model.scale, model.liquid, model.height_ratio, model.squeeze, model.axis, 1)
	else:
		_apply_probe(SlimeShapeModel.erode_points(model.resolved_points().duplicate(), margin))
		shape = _probe_shape
	debug_intersect_count += 1
	return _space().intersect_shape(_query(model.foot, shape, true, mask), 1).is_empty()


## Spawn preflight: does a clone's target hull at `at_foot` clear geometry and other
## slimes? The spawner stays excluded through this body's own exclusion list.
func spawn_is_clear(at_foot: Vector3, p_scale: float) -> bool:
	var shape := model.cached_shape(p_scale, 0.0, 1.0, 1.0, Vector3.RIGHT, 1)
	debug_intersect_count += 1
	return _space().intersect_shape(_query(at_foot, shape, true, LAYER_SOLID), 1).is_empty()


## Sweep a hull of `p_scale` from `from_foot` to `to_foot`. True when level geometry
## never blocks the whole path, not merely its endpoints.
func sweep_is_clear(from_foot: Vector3, to_foot: Vector3, p_scale: float) -> bool:
	var shape := model.cached_shape(p_scale, 0.0, 1.0, 1.0, Vector3.RIGHT, 1)
	var fr := _cast(from_foot, to_foot - from_foot, true, shape, LAYER_OBSTACLES)
	return fr[1] >= 0.999999


## Free distance a hull of `p_scale` can travel along `motion` before touching level
## geometry, capped at `motion.length()`. Used by the split preflight to decide how
## much of the separation each half must provide.
func sweep_clear_distance(p_scale: float, motion: Vector3) -> float:
	var len := motion.length()
	if len <= 1e-6:
		return 0.0
	var shape := model.cached_shape(p_scale, 0.0, 1.0, 1.0, Vector3.RIGHT, 1)
	_sync_foot()
	var fr := _cast(model.foot, motion, true, shape, LAYER_OBSTACLES)
	var unsafe: float = fr[1]
	if unsafe >= 0.999999:
		return len
	return clampf(unsafe, 0.0, 1.0) * len


func describe_block(p_height_ratio: float, p_squeeze: float) -> String:
	if p_height_ratio > model.height_ratio + 1e-4:
		return "overhead/ceiling blocks standing"
	if p_squeeze < model.squeeze - 1e-4:
		return "side walls block narrowing"
	return "expansion blocked by geometry"