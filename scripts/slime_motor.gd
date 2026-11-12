class_name SlimeMotor
extends RefCounted
## Single owner of a slime's physical transform, velocity, support and posture.
##
## Movement is sweep-then-slide against real obstacle geometry: advance to the safe
## fraction, preserve the remainder along the contact tangent, and keep EVERY
## blocking contact as a constraint (a dead end stops motion even between side
## walls). Posture/expansion changes are collision-tested over the whole footprint
## before being committed. Nothing else may write the actor's position.

const LAYER_TERRAIN := 1
const LAYER_SLIMES := 2
const LAYER_OBSTACLES := 4
const LAYER_SOLID := LAYER_TERRAIN | LAYER_OBSTACLES | LAYER_SLIMES
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
var ground_normal := Vector3.UP
var just_landed := false
var landing_impact_speed := 0.0

## Hydrodynamic state updated from CaveSystem.sample_water_at() each tick.
var in_water := false
var water_y := -9999.0
var water_depth := 0.0
var water_submersion := 0.0
var water_wetness := 0.0
var water_flow_vel := Vector3.ZERO
var just_splashed := false
var last_splash_pos := Vector3.ZERO
var splash_age := 99.0
var splash_seq: int = 0
var water_enter_speed := 0.0
var want_run_swim := false

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
var _deep_ray_query: PhysicsRayQueryParameters3D
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
	_deep_ray_query = PhysicsRayQueryParameters3D.new()
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


## Horizontal sweep origin for the Core Sphere: aligned with the slime's X/Z center and
## positioned just above the foot so it collides with low cubes (0.5m+) while passing under low tunnels (0.75m+).
func core_sweep_origin() -> Vector3:
	return model.foot + Vector3(0.0, model.core_sphere_radius() + 0.02, 0.0)


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


## Push out of any initial overlap with level obstacles using collide_shape contact pairs
## across BOTH core spheres. Using collide_shape avoids single-body RID exclusion blinding
## against monolithic concaves like CaveWallBody, and sequential projection escapes acute corners cleanly.
func recover_overlap() -> void:
	_sync_foot()
	var space := _space()
	var core_r := model.core_sphere_radius()
	var sphere := core_sphere_shape(core_r)
	var max_step := maxf(core_r * 0.65, 0.12)
	for _i in tuning.recovery_iterations:
		var origins: Array[Vector3] = [core_sweep_origin(), model.core_sphere_center()]
		var escape := Vector3.ZERO
		var max_depth := 0.0
		var grounded_floor := support_y > tuning.floor_y + 0.5 and model.foot.y <= support_y + model.core_sphere_radius() * 2.0 + 0.35
		for orig in origins:
			var q := _query(orig, sphere, true, LAYER_OBSTACLES)
			debug_intersect_count += 1
			var pairs := space.collide_shape(q, 16)
			if pairs.size() >= 2:
				var pair_count := pairs.size() / 2
				for pi in pair_count:
					var pt_self: Vector3 = pairs[pi * 2]
					var pt_world: Vector3 = pairs[pi * 2 + 1]
					var d := pt_world - pt_self
					var depth := d.length()
					if depth < 0.00002:
						continue
					var n := d / depth
					# Keep side/wall corner contacts strictly horizontal when near walls or grounded so
					# sloped wall fillets cannot drive the slime upward or underground.
					if absf(n.y) < 0.72 or (grounded_floor and n.y < -0.15):
						var nh := Vector3(n.x, 0.0, n.z)
						if nh.length_squared() < 1e-6:
							continue
						n = nh.normalized()
						depth = maxf(Vector2(d.x, d.z).length(), depth * 0.7)
					max_depth = maxf(max_depth, depth)
					var rem := depth + 0.0015 - escape.dot(n)
					if rem > 0.0:
						escape += n * rem
			else:
				debug_rest_count += 1
				var rest := space.get_rest_info(q)
				if not rest.is_empty():
					var rn: Vector3 = rest.normal
					if rn.length_squared() >= 1e-6:
						rn = rn.normalized()
						if absf(rn.y) < 0.72 or (grounded_floor and rn.y < -0.15):
							rn = Vector3(rn.x, 0.0, rn.z)
						if rn.length_squared() >= 1e-6:
							rn = rn.normalized()
							var fallback_d := tuning.skin + 0.005
							max_depth = maxf(max_depth, fallback_d)
							var rem_r := fallback_d - escape.dot(rn)
							if rem_r > 0.0:
								escape += rn * rem_r
		if max_depth < 0.00002 or escape.length_squared() < 1e-11:
			return
		var step_len := escape.length()
		if step_len > max_step:
			escape *= max_step / step_len
		if grounded_floor and escape.y < 0.0:
			var min_foot := support_y + tuning.skin * 0.5
			if model.foot.y + escape.y < min_foot:
				escape.y = maxf(escape.y, min_foot - model.foot.y)
				if escape.y > 0.0:
					escape.y = 0.0
		if escape.length_squared() < 1e-9:
			return
		owner_node.global_position += escape
		var esc_dir := escape.normalized()
		var into := velocity.dot(esc_dir)
		if into < 0.0:
			velocity = velocity.slide(esc_dir)
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
## clears, the Core Sphere immediately carries the body through; against solid walls and
## concave corners, accumulated active contact planes halt penetration without tunneling.
func move_horizontal(motion: Vector3) -> void:
	contact_normals.clear()
	contact_bodies.clear()
	impact_speed = 0.0
	last_sweep_fraction = 1.0
	_sync_foot()
	var sphere := core_sphere_shape()
	var max_step := maxf(model.rest_max_radius * model.scale * tuning.max_step_fraction, 0.12)
	var steps := clampi(int(ceil(motion.length() / maxf(max_step, 1e-3))), 1, MAX_MOVE_SUBSTEPS)
	var chunk := motion / float(steps)
	var space := _space()
	for _s in steps:
		if chunk.length_squared() < 1e-10:
			break
		var stalled := 0
		var slid := chunk
		var active_planes: Array[Vector3] = []
		for _i in tuning.slide_iterations:
			if slid.length_squared() < 1e-10:
				break
			var center_pos := model.core_sphere_center()
			var base_pos := core_sweep_origin()
			var fr_center := _cast(center_pos, slid, true, sphere)
			var fr_base := _cast(base_pos, slid, true, sphere)
			var use_center := float(fr_center[1]) <= float(fr_base[1])
			var hit_origin := center_pos if use_center else base_pos
			var fr := fr_center if use_center else fr_base
			var safe: float = fr[0]
			var unsafe: float = fr[1]
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
				if stalled >= 2 and active_planes.size() >= 1:
					break
			else:
				stalled = 0

			var hit_now := model.core_sphere_center() if use_center else core_sweep_origin()
			var probe_pos := hit_origin if (safe <= 1e-5 and unsafe <= 1e-5) else (hit_origin + slid * unsafe)
			var rest := _contact_rest(probe_pos, sphere)
			if rest.is_empty():
				rest = _contact_rest(hit_now, sphere)

			var n := Vector3.ZERO
			var hit_collider: Object = null
			if not rest.is_empty():
				n = rest.normal
				hit_collider = rest.get("collider")
			else:
				debug_intersect_count += 1
				var pairs := space.collide_shape(_query(probe_pos, sphere, true, LAYER_SOLID), 8)
				if pairs.size() >= 2:
					var sum_n := Vector3.ZERO
					for pi in (pairs.size() / 2):
						var d := pairs[pi * 2 + 1] - pairs[pi * 2]
						if d.length_squared() > 1e-10:
							sum_n += d.normalized()
					n = sum_n

			n = Vector3(n.x, 0.0, n.z)
			if n.length_squared() < 1e-6:
				break
			n = n.normalized()
			if not contact_normals.has(n):
				contact_normals.append(n)
			if hit_collider != null and not contact_bodies.has(hit_collider):
				contact_bodies.append(hit_collider)

			var into := velocity.dot(n)
			if into < 0.0:
				impact_speed = maxf(impact_speed, -into)
				velocity = velocity.slide(n)

			var has_plane := false
			for p in active_planes:
				if p.dot(n) > 0.998:
					has_plane = true
					break
			if not has_plane:
				active_planes.append(n)

			var rem := slid * maxf(1.0 - safe, 0.0)
			for _pass in active_planes.size() * 2 + 1:
				var changed := false
				for p in active_planes:
					var dp := rem.dot(p)
					if dp < -1e-5:
						rem = rem - p * dp
						changed = true
				if not changed:
					break
			var blocked_by_corner := rem.length_squared() < 1e-10 or rem.dot(chunk) <= 1e-6
			if not blocked_by_corner:
				for p in active_planes:
					if rem.dot(p) < -1e-3:
						blocked_by_corner = true
						break
			if blocked_by_corner:
				slid = Vector3.ZERO
				break
			slid = rem


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
	var fr := _cast(core_sweep_origin(), push, true, core_sphere_shape(), LAYER_OBSTACLES)
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
## Falls back to core-sized and slim terrain-only probes when the wide envelope grazes
## a steep cave wall or passage corner, preventing sudden floor-support dropouts.
func update_support() -> void:
	_sync_foot()
	var reach := lerpf(tuning.climb_reach, tuning.liquid_climb_reach, model.liquid) * model.scale
	var drop := reach + 2.0 * model.scale
	var start := model.foot + Vector3(0, reach, 0)
	var best := tuning.floor_y
	var body: Object = null
	var found := false

	var fr := _cast(start, Vector3(0, -drop, 0), false, null, LAYER_TERRAIN | LAYER_OBSTACLES)
	var unsafe: float = fr[1]
	if unsafe < 0.999999:
		var at := start + Vector3(0, -drop, 0) * unsafe
		debug_rest_count += 1
		var rest := _space().get_rest_info(_query(at, null, false, LAYER_TERRAIN | LAYER_OBSTACLES))
		if not rest.is_empty() and rest.normal.y > 0.5:
			var top: float = rest.point.y
			if top <= model.foot.y + reach + tuning.skin and top > best:
				var rise := top + tuning.skin - model.foot.y
				if rise <= 1e-4 or ceiling_clearance_up(rise) >= rise - 1e-4:
					best = top
					body = rest.get("collider")
					ground_normal = rest.normal
					found = true

	if not found:
		var core_r := model.core_sphere_radius()
		var core_sph := core_sphere_shape(core_r)
		var core_start := model.foot + Vector3(0, reach + core_r, 0)
		var fr_c := _cast(core_start, Vector3(0, -drop, 0), false, core_sph, LAYER_TERRAIN | LAYER_OBSTACLES)
		var u_c: float = fr_c[1]
		if u_c < 0.999999:
			var at_c := core_start + Vector3(0, -drop, 0) * u_c
			debug_rest_count += 1
			var rest_c := _space().get_rest_info(_query(at_c, core_sph, false, LAYER_TERRAIN | LAYER_OBSTACLES))
			if not rest_c.is_empty() and rest_c.normal.y > 0.5:
				var top_c: float = rest_c.point.y
				if top_c <= model.foot.y + reach + tuning.skin and top_c > best:
					var rise_c := top_c + tuning.skin - model.foot.y
					if rise_c <= 1e-4 or ceiling_clearance_up(rise_c, model.core_shape(2)) >= rise_c - 1e-4:
						best = top_c
						body = rest_c.get("collider")
						ground_normal = rest_c.normal
						found = true

	if not found:
		var slim_r := minf(model.core_sphere_radius(), 0.20 * model.scale)
		var slim_sph := core_sphere_shape(slim_r)
		var slim_start := model.foot + Vector3(0, reach + slim_r, 0)
		var fr_t := _cast(slim_start, Vector3(0, -drop, 0), false, slim_sph, LAYER_TERRAIN)
		var u_t: float = fr_t[1]
		if u_t < 0.999999:
			var at_t := slim_start + Vector3(0, -drop, 0) * u_t
			debug_rest_count += 1
			var rest_t := _space().get_rest_info(_query(at_t, slim_sph, false, LAYER_TERRAIN))
			if not rest_t.is_empty() and rest_t.normal.y > 0.35:
				var top_t: float = rest_t.point.y
				if top_t <= model.foot.y + reach + tuning.skin and top_t > best:
					var rise_t := top_t + tuning.skin - model.foot.y
					if rise_t <= 1e-4 or ceiling_clearance_up(rise_t, model.core_shape(2)) >= rise_t - 1e-4:
						best = top_t
						body = rest_t.get("collider")
						ground_normal = rest_t.normal
						found = true

	# Deep-water / pit floor ray fallback so seabeds and lake pits deeper than 2.4m still report true support
	if not found and (in_water or owner_node.global_position.y < 14.0):
		if _deep_ray_query == null:
			_deep_ray_query = PhysicsRayQueryParameters3D.new()
		_deep_ray_query.from = model.foot + Vector3(0.0, reach, 0.0)
		_deep_ray_query.to = Vector3(model.foot.x, tuning.floor_y, model.foot.z)
		_deep_ray_query.collision_mask = LAYER_TERRAIN | LAYER_OBSTACLES
		_deep_ray_query.collide_with_bodies = true
		_deep_ray_query.collide_with_areas = false
		_deep_ray_query.exclude = _exclude
		var deep_hit := _space().intersect_ray(_deep_ray_query)
		if not deep_hit.is_empty():
			var d_norm: Vector3 = deep_hit.normal
			var d_y: float = (deep_hit.position as Vector3).y
			if d_norm.y > 0.35 and d_y <= model.foot.y + reach + tuning.skin and d_y > best:
				best = d_y
				body = deep_hit.get("collider")
				ground_normal = d_norm
				found = true

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


## Sample nearby water bodies & update submersion, wetness, flow velocity, and entry splash state.
func update_water_state(dt: float, is_subterranean: bool) -> void:
	just_splashed = false
	splash_age = minf(splash_age + dt, 99.0)
	_sync_foot()
	var foot_y := model.foot.y
	var winfo := CaveSystem.sample_water_at(owner_node.global_position, support_y, is_subterranean)
	var was_in := in_water
	if bool(winfo.get("in_water", false)) and foot_y < float(winfo["water_y"]) - 0.03:
		in_water = true
		water_y = float(winfo["water_y"])
		water_depth = maxf(water_y - foot_y, 0.0)
		water_submersion = clampf((water_depth - 0.03) / maxf(model.full_height * 0.72, 0.25), 0.0, 1.0)
		water_flow_vel = winfo.get("flow_vel", Vector3.ZERO) as Vector3
		water_wetness = clampf(maxf(water_wetness, 0.52 + water_submersion * 0.48), 0.0, 1.0)
		if (not was_in and (water_depth > 0.14 or absf(vertical_vel) > 1.5)) or (absf(vertical_vel) > 4.0 and splash_age > 0.35):
			just_splashed = true
			last_splash_pos = Vector3(owner_node.global_position.x, water_y, owner_node.global_position.z)
			splash_age = 0.0
			splash_seq += 1
			water_enter_speed = clampf(absf(vertical_vel) + Vector2(velocity.x, velocity.z).length() * 0.45, 2.2, 14.0)
	else:
		in_water = false
		water_y = float(winfo.get("water_y", -9999.0))
		water_depth = 0.0
		water_submersion = 0.0
		water_flow_vel = Vector3.ZERO
		water_wetness = maxf(0.0, water_wetness - dt * 0.22)


## Vertical integration anchored to support with speed-coupled hydrodynamics:
## walking (`W` or slower) / idle sinks gently down to the underwater floor;
## running (`Shift+W`) generates hydrodynamic lift and rises smoothly to the surface.
func move_vertical(dt: float, target_scale: float) -> void:
	just_landed = false
	var target_foot := support_y + tuning.skin
	var foot_y := owner_node.global_position.y - model.rest_half_height * model.scale
	var shrinking := target_scale < model.scale - 0.01
	var desired := 0.0
	var was_airborne := not on_ground
	var buoy_depth := model.full_height * 0.30
	var swim_spd := Vector2(velocity.x, velocity.z).length()
	var is_run_swim := want_run_swim or swim_spd > tuning.walk_speed * 1.15
	var deep_water := in_water and (water_y - target_foot) > buoy_depth
	if deep_water and foot_y < water_y + 0.12 and not shrinking:
		if is_run_swim:
			var neutral_foot := maxf(target_foot, water_y - buoy_depth)
			var b_phase := _water_bob_phase(foot_y) + owner_node.global_position.x * 0.55 + owner_node.global_position.z * 0.42
			var bob_wave := sin(b_phase) * 0.018 + cos(b_phase * 1.63) * 0.010
			var target_buoy := maxf(target_foot, neutral_foot + bob_wave)
			if was_airborne and foot_y <= target_buoy and vertical_vel < -2.0:
				just_splashed = true
				last_splash_pos = Vector3(owner_node.global_position.x, water_y, owner_node.global_position.z)
				splash_age = 0.0
				splash_seq += 1
				water_enter_speed = clampf(absf(vertical_vel) + swim_spd * 0.45, 2.2, 14.0)
			var disp_err := target_buoy - foot_y
			var target_vy := clampf(disp_err * 4.5, -2.6, 3.4)
			vertical_vel = lerpf(vertical_vel, target_vy, 1.0 - exp(-6.5 * dt))
			desired = vertical_vel * dt
			on_ground = foot_y <= target_foot + 0.03 and disp_err <= 0.02
		else:
			if foot_y > target_foot + 0.03:
				var dist_to_floor := foot_y - target_foot
				var sink_speed := minf(2.4, dist_to_floor * 4.2 + 0.35)
				vertical_vel = lerpf(vertical_vel, -sink_speed, 1.0 - exp(-5.0 * dt))
				desired = vertical_vel * dt
				on_ground = false
			else:
				if was_airborne:
					just_landed = true
					landing_impact_speed = absf(vertical_vel)
				vertical_vel = 0.0
				on_ground = true
				var follow_rate := 36.0 if target_foot > foot_y else 16.0
				desired = (target_foot - foot_y) * (1.0 - exp(-follow_rate * dt))
	elif foot_y > target_foot + 0.02 and not shrinking:
		on_ground = false
		vertical_vel -= tuning.gravity * dt
		desired = vertical_vel * dt
	else:
		if was_airborne:
			just_landed = true
			landing_impact_speed = absf(vertical_vel)
		vertical_vel = 0.0
		on_ground = true
		var follow_rate := 36.0 if target_foot > foot_y else 16.0
		desired = (target_foot - foot_y) * (1.0 - exp(-follow_rate * dt))
	if absf(desired) <= 1e-7:
		_sync_foot()
		return
	var safe := _sweep_vertical(desired)
	var next_foot := foot_y + desired * safe
	if desired < 0.0 and next_foot < target_foot:
		next_foot = target_foot
	if safe < 0.999999:
		if was_airborne:
			just_landed = true
			landing_impact_speed = absf(vertical_vel)
		vertical_vel = 0.0
		if desired < 0.0:
			on_ground = true
	owner_node.global_position.y = next_foot + model.rest_half_height * model.scale
	_sync_foot()


func _water_bob_phase(_foot_y: float) -> float:
	return float(Time.get_ticks_msec()) * 0.0028


## Safe fraction of a vertical hull sweep (1.0 when the corridor is clear).
## Downward drops also sweep both core spheres against LAYER_OBSTACLES so wall overhangs
## cannot be entered during vertical settlement near corners.
func _sweep_vertical(delta: float) -> float:
	_sync_foot()
	var best_safe := 1.0
	var fr := _cast(model.foot, Vector3(0.0, delta, 0.0))
	if float(fr[1]) < 0.999999:
		best_safe = minf(best_safe, clampf(float(fr[0]), 0.0, 1.0))
	if delta < 0.0:
		var sphere := core_sphere_shape()
		var fr_base := _cast(core_sweep_origin(), Vector3(0.0, delta, 0.0), true, sphere, LAYER_OBSTACLES)
		if float(fr_base[1]) < 0.999999 and not (float(fr_base[0]) <= 0.0 and float(fr_base[1]) <= 0.0):
			best_safe = minf(best_safe, clampf(float(fr_base[0]), 0.0, 1.0))
		var fr_ctr := _cast(model.core_sphere_center(), Vector3(0.0, delta, 0.0), true, sphere, LAYER_OBSTACLES)
		if float(fr_ctr[1]) < 0.999999 and not (float(fr_ctr[0]) <= 0.0 and float(fr_ctr[1]) <= 0.0):
			best_safe = minf(best_safe, clampf(float(fr_ctr[0]), 0.0, 1.0))
	return best_safe


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