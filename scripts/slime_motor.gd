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
## Intermediate probes between the resolved posture and the candidate posture.
const PROBE_STEPS := 2

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
var _exclude: Array[RID] = []


func setup(node: Node3D, shape_model: SlimeShapeModel, t: SlimeTuning) -> void:
	owner_node = node
	model = shape_model
	tuning = t
	support_y = t.floor_y
	_probe_shape = ConvexPolygonShape3D.new()


func set_exclude(rids: Array[RID]) -> void:
	_exclude = rids


func _space() -> PhysicsDirectSpaceState3D:
	return owner_node.get_world_3d().direct_space_state


func _sync_foot() -> void:
	model.set_foot(owner_node.global_position + Vector3(0, -model.rest_half_height * model.scale, 0))


func _query(at_foot: Vector3, probe: Shape3D = null, use_exclude := true) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe if probe != null else model.shape
	q.transform = Transform3D(Basis.IDENTITY, at_foot)
	q.collision_mask = LAYER_OBSTACLES
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = _exclude if use_exclude else []
	return q


## Push out of any initial overlap along true contact normals (never through walls).
func recover_overlap() -> void:
	_sync_foot()
	var space := _space()
	for _i in tuning.recovery_iterations:
		var q := _query(model.foot)
		var hits := space.intersect_shape(q, 8)
		if hits.is_empty():
			return
		var rest := space.get_rest_info(q)
		if rest.is_empty():
			return
		var n: Vector3 = rest.normal
		if n.length_squared() < 1e-6:
			return
		owner_node.global_position += n * (tuning.skin * 2.0 + 0.01)
		var into := velocity.dot(n)
		if into < 0.0:
			velocity = velocity.slide(n)
		_sync_foot()


## Sweep the current envelope; returns [safe, unsafe] fractions.
func _cast(from_foot: Vector3, motion: Vector3, use_exclude := true) -> Array:
	var q := _query(from_foot, null, use_exclude)
	q.motion = motion
	return _space().cast_motion(q)


func _contact_rest(at_foot: Vector3) -> Dictionary:
	return _space().get_rest_info(_query(at_foot))


## Horizontal sweep + slide. All contacts remain constraints.
func move_horizontal(motion: Vector3) -> void:
	contact_normals.clear()
	contact_bodies.clear()
	impact_speed = 0.0
	last_sweep_fraction = 1.0
	var max_step := model.rest_max_radius * model.scale * tuning.max_step_fraction
	if motion.length() > max_step:
		motion = motion.normalized() * max_step
	_sync_foot()
	var remaining := motion
	for _i in tuning.slide_iterations:
		if remaining.length_squared() < 1e-10:
			break
		var fr := _cast(model.foot, remaining)
		var safe: float = fr[0]
		var unsafe: float = fr[1]
		if unsafe >= 0.999999:
			owner_node.global_position += remaining
			_sync_foot()
			last_sweep_fraction = minf(last_sweep_fraction, safe)
			return
		owner_node.global_position += remaining * safe
		_sync_foot()
		last_sweep_fraction = minf(last_sweep_fraction, safe)
		var rest := _contact_rest(model.foot + remaining * unsafe)
		if rest.is_empty():
			return
		var n: Vector3 = rest.normal
		if n.length_squared() < 1e-6:
			return
		n = Vector3(n.x, 0.0, n.z)
		if n.length_squared() < 1e-6:
			return
		n = n.normalized()
		contact_normals.append(n)
		if rest.get("collider") != null:
			contact_bodies.append(rest.get("collider"))
		var into := velocity.dot(n)
		if into < 0.0:
			impact_speed = maxf(impact_speed, -into)
			velocity = velocity.slide(n)
		remaining = remaining.slide(n) * (1.0 - safe)
	# Budget exhausted: stop safely rather than forcing through.


## Downward support query; raises support when stepping onto reachable geometry.
## Food still supports weight, so support queries ignore the edible exclusion.
func update_support() -> void:
	_sync_foot()
	var reach := (tuning.liquid_climb_reach if model.liquid > 0.3 else tuning.climb_reach) * model.scale
	var start := model.foot + Vector3(0, reach, 0)
	var fr := _cast(start, Vector3(0, -(reach + 2.0 * model.scale), 0), false)
	var unsafe: float = fr[1]
	var best := tuning.floor_y
	var body: Object = null
	if unsafe < 0.999999:
		var at := start + Vector3(0, -(reach + 2.0 * model.scale), 0) * unsafe
		var rest := _space().get_rest_info(_query(at, null, false))
		if not rest.is_empty() and rest.normal.y > 0.5:
			var top: float = rest.point.y
			if top <= model.foot.y + reach + tuning.skin and top > best:
				best = top
				body = rest.get("collider")
	support_y = best
	ground_body = body


## Free rise above the current envelope top, up to max_rise. INF when the corridor
## above the whole footprint is clear. Obstacles are included (food blocks a stand-up
## just like a wall does).
func ceiling_clearance_up(max_rise: float) -> float:
	if max_rise <= 0.0:
		return 0.0
	_sync_foot()
	var fr := _cast(model.foot, Vector3(0.0, max_rise, 0.0), false)
	var unsafe: float = fr[1]
	if unsafe >= 0.999999:
		return INF
	return maxf(0.0, unsafe * max_rise - tuning.skin)


## Vertical integration anchored to support; never sinks below the floor.
func move_vertical(dt: float, target_scale: float) -> void:
	var target_foot := support_y + tuning.skin
	var foot_y := owner_node.global_position.y - model.rest_half_height * model.scale
	var shrinking := target_scale < model.scale - 0.01
	if foot_y > target_foot + 0.02 and not shrinking:
		on_ground = false
		vertical_vel -= tuning.gravity * dt
		foot_y += vertical_vel * dt
		if foot_y <= target_foot:
			foot_y = target_foot
			vertical_vel = 0.0
			on_ground = true
	else:
		foot_y = lerpf(foot_y, target_foot, 1.0 - exp(-16.0 * dt))
		vertical_vel = 0.0
		on_ground = true
	owner_node.global_position.y = foot_y + model.rest_half_height * model.scale
	_sync_foot()


## Collision-test a posture transition over the whole footprint (current + proposed
## + intermediate bounds). Returns true when the target posture is legal.
func posture_is_legal(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> bool:
	# Unchanged posture is trivially legal; skip rebuilding the convex hull.
	if absf(p_scale - model.scale) < 1e-4 and absf(p_liquid - model.liquid) < 1e-4 \
			and absf(p_height_ratio - model.height_ratio) < 1e-4 \
			and absf(p_squeeze - model.squeeze) < 1e-4 \
			and p_axis.distance_squared_to(model.axis) < 1e-4:
		return true

	_sync_foot()
	var space := _space()
	for s in PROBE_STEPS + 1:
		var t := float(s) / float(PROBE_STEPS)
		var sc := lerpf(model.scale, p_scale, t)
		var lq := lerpf(model.liquid, p_liquid, t)
		var hr := lerpf(model.height_ratio, p_height_ratio, t)
		var sq := lerpf(model.squeeze, p_squeeze, t)
		var ax := model.axis.lerp(p_axis, t)
		var pts := model.baked_points(sc, lq, hr, sq, ax)
		_probe_shape.set_points(pts)
		var q := _query(model.foot, _probe_shape)
		if not space.intersect_shape(q, 1).is_empty():
			return false
	return true


func describe_block(p_height_ratio: float, p_squeeze: float) -> String:
	if p_height_ratio > model.height_ratio + 1e-4:
		return "overhead/ceiling blocks standing"
	if p_squeeze < model.squeeze - 1e-4:
		return "side walls block narrowing"
	return "expansion blocked by geometry"