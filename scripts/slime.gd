class_name Slime
extends Node3D
## The jelly slime entity: handles player control, follower breadcrumb AI, or autonomous roamer AI,
## fluid deformation, liquid mode (Z), climb/engulf, splitting (E, Q), and merging (M).

signal poked(local_point: Vector3, impulse: Vector3)

enum Role {
	PLAYER,
	FOLLOWER,
	ROAMER
}

@export var role: Role = Role.PLAYER

@export_group("Nodes")
@export var body: MeshInstance3D
@export var camera: Camera3D
@export var floor_mesh: MeshInstance3D
@export var props: SlimeProps

@export_group("Movement")
@export var walk_speed := 3.0
@export var run_speed := 10.0
@export var liquid_speed := 2.2
@export var velocity_response := 8.0
@export var arena_radius := 190.0

@export_group("Size")
@export var start_scale := 1.0
@export var scale_response := 3.5
@export var floor_y := -1.2
@export var height_per_scale := 1.2
@export var body_radius := 1.6

@export_group("Crawl and lean")
@export var crawl_rate := 2.6
@export var speed_for_full_crawl := 3.0
@export var lean_gain := 0.35
@export var lean_stiffness := 60.0
@export var lean_damping := 7.0
@export var ripple_base := 0.12
@export var ripple_per_speed := 0.45

@export_group("Poke")
@export var poke_strength := 0.55
@export var poke_downward := 0.25

@export_group("Eyes")
@export var facing_response := 8.0
@export var moving_threshold := 0.3
@export var blink_period := 4.0
@export var blink_start := 3.85
@export var blink_closed_amount := 0.12
@export var start_facing := 0.45

@export_group("Liquid and Engulf")
@export var liquid_height_ratio := 0.22
@export var liquid_spread_ratio := 2.13
@export var liquid_clearance_ratio := 0.12
@export var devour_duration := 1.6

@export_group("Follower & Roamer AI")
@export var target_leader: Slime = null
@export var follow_distance := 3.2

var velocity := Vector3.ZERO
var slime_scale := 1.0
var target_scale := 1.0
var speed01 := 0.0

# Vertical motion & ground support
var support_y := -1.2
var vertical_vel := 0.0
var is_on_ground := true
var ground_prop = null

# Liquid mode (Z key)
var liquid_mode := false
var liquid_amt := 0.0

# Engulfing (Z on top of larger object)
var engulf_target = null
var engulf_progress := 0.0

# ---- Fission (budding split) animation state ----
var is_fissioning := false
var fission_timer := 0.0
var fission_duration := 0.38
var fission_fwd := Vector3.FORWARD
var fission_start_scale := 1.0
var fission_target_scale := 0.794

# CLONE budding state
var is_budding := false
var bud_timer := 0.0
var bud_duration := 0.38
var bud_parent: Slime = null
var bud_target_scale := 1.0
var bud_fwd := Vector3.FORWARD

# Merge animation state
var is_merging := false
var merge_target: Slime = null
var merge_timer := 0.0
var merge_duration := 0.45
var merge_source_scale := 1.0
var _has_merged := false

# Physics & deformation state (per-slime)
var calm := 0.0
var touch_time := -10.0
var cur_max := 3.0
var squeeze_k := 1.0
var sq_dir := Vector3(1, 0, 0)
var splat_x := 0.0
var splat_v := 0.0
var spread_x := 0.0
var spread_v := 0.0
var sharp_amt := 0.0
var contact_r := 2.15
var impact_dir := Vector3(0, 0, 1)
var press_amt := 0.0

# Per-slime detected gap state
var cur_gap_center := Vector2.ZERO
var cur_gap_w := INF
var cur_gap_dir := Vector2.ZERO

# Breadcrumb history for followers to trace
var breadcrumbs: Array[Dictionary] = []
var _breadcrumb_timer := 0.0

# Internal props being digested
var inside_props: Array = []

# AI internal state
var _ai_target_pos := Vector3.ZERO
var _ai_roam_timer := 0.0
var _ai_recovery_timer := 0.0
var _ai_target_prop = null
var _ai_stuck_timer := 0.0
var _ai_last_pos := Vector3.ZERO
# Follower-specific: flatten-to-fit flag (suppresses engulf while navigating low areas)
var _following_flatten := false
var _follower_stuck_timer := 0.0

var _mat: ShaderMaterial
var _time := 0.0
var _impulse_time := 10.0
var _impulse2_time := 10.0
var _crawl_dir := Vector3(0, 0, 1)
var _crawl_phase := 0.0
var _facing_yaw := 0.0
var _lean := Vector3.ZERO
var _lean_vel := Vector3.ZERO

var time: float:
	get:
		return _time


func get_volume() -> float:
	## Authoritative volume of the slime based on target_scale
	return (4.0 / 3.0) * PI * pow(body_radius * target_scale, 3.0)


func get_visual_volume() -> float:
	return (4.0 / 3.0) * PI * pow(body_radius * slime_scale, 3.0)



func _ready() -> void:
	if not is_budding:
		slime_scale = start_scale
		target_scale = start_scale
		_facing_yaw = start_facing
		support_y = floor_y

	# Duplicate material override so each clone has independent shader uniforms
	if body and body.material_override:
		var dup = body.material_override.duplicate()
		if dup is ShaderMaterial:
			_mat = dup
			body.material_override = _mat
			_mat.set_shader_parameter("uMelt", 0.28)
			_reset_array_uniforms()

	if props == null:
		props = get_node_or_null("../Ecosystem") as SlimeProps
	if props:
		props.register_slime(self)

	_apply_transform()


func _exit_tree() -> void:
	if props and is_instance_valid(props):
		props.unregister_slime(self)


func _reset_array_uniforms() -> void:
	if _mat == null:
		return
	var zeros6 := PackedVector3Array()
	var small6 := PackedVector3Array()
	for i in 6:
		zeros6.append(Vector3.ZERO)
		small6.append(Vector3(0.01, 0.01, 0.01))
	var zeros2 := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var small2 := PackedVector3Array([Vector3(0.01, 0.01, 0.01), Vector3(0.01, 0.01, 0.01)])
	_mat.set_shader_parameter("uEatPos", zeros6)
	_mat.set_shader_parameter("uEatParam", zeros6)
	_mat.set_shader_parameter("uBoxHalf", small6)
	_mat.set_shader_parameter("uSolidPos", zeros2)
	_mat.set_shader_parameter("uSolidParam", zeros2)
	_mat.set_shader_parameter("uSolidHalf", small2)
	_mat.set_shader_parameter("uSolidDir", zeros2)
	_mat.set_shader_parameter("uDrapeAmt", 0.0)
	_mat.set_shader_parameter("uSplitAmt", 0.0)
	_mat.set_shader_parameter("uBudAmt", 0.0)
	_mat.set_shader_parameter("uBudScale", 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if role != Role.PLAYER:
		return
	if event.is_action_pressed("slime_poke") and camera:
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			_try_poke(event.position)
		elif event is InputEventScreenTouch:
			_try_poke(event.position)
		else:
			var vp := get_viewport()
			if vp:
				_try_poke(vp.get_visible_rect().size * 0.5)
	elif event.is_action_pressed("split_follow"):
		split_clone(Role.FOLLOWER)
	elif event.is_action_pressed("split_roam"):
		split_clone(Role.ROAMER)
	elif event.is_action_pressed("merge_clones"):
		merge_nearby_clones()


func _try_poke(screen_pos: Vector2) -> void:
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var base_r := body_radius * slime_scale
	# Account for liquid flattening/spreading: raycast against true flattened ellipsoid shape
	var rx := base_r * lerpf(1.0, liquid_spread_ratio, liquid_amt)
	var ry := base_r * lerpf(1.0, liquid_height_ratio, liquid_amt)
	var rz := rx

	var inv_r := Vector3(1.0 / rx, 1.0 / ry, 1.0 / rz)
	var oc := (origin - global_position) * inv_r
	var d := dir * inv_r
	var a := d.dot(d)
	var b := oc.dot(d)
	var c := oc.dot(oc) - 1.0
	var disc := b * b - a * c
	if disc < 0.0:
		return
	var s := sqrt(disc)
	var t := (-b - s) / a
	if t < 0.0:
		t = (-b + s) / a
	if t < 0.0:
		return
	var hit := origin + dir * t
	var local_point := (hit - global_position).normalized() * body_radius
	var push := (hit - camera.global_position).normalized() * poke_strength
	push.y -= poke_downward
	trigger_poke(local_point, push)


func trigger_poke(local_point: Vector3, impulse: Vector3) -> void:
	_impulse_time = 0.001
	if _mat:
		_mat.set_shader_parameter("uImpulsePos", local_point)
		_mat.set_shader_parameter("uImpulseVector", impulse)
	poked.emit(local_point, impulse)


func trigger_poke2(local_point: Vector3, impulse: Vector3) -> void:
	_impulse2_time = 0.001
	if _mat:
		_mat.set_shader_parameter("uImpulse2Pos", local_point)
		_mat.set_shader_parameter("uImpulse2Vector", impulse)


func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	_time += dt
	_impulse_time += dt
	_impulse2_time += dt

	# --- Merge animation (M key) ---
	if is_merging:
		merge_timer += dt
		if merge_target and is_instance_valid(merge_target) and not merge_target.is_merging:
			position = position.lerp(merge_target.position, 14.0 * dt)
			slime_scale = lerpf(slime_scale, 0.02, 12.0 * dt)
			_apply_transform()
			if merge_timer >= merge_duration or position.distance_squared_to(merge_target.position) < 0.2:
				if not _has_merged:
					_has_merged = true
					merge_target.target_scale = pow(pow(merge_target.target_scale, 3.0) + pow(merge_source_scale, 3.0), 1.0 / 3.0)
					merge_target.trigger_poke(Vector3(0, 0.3, 0), Vector3(0, -0.65, 0))
					merge_target.trigger_poke2(Vector3(0, -0.3, 0), Vector3(0, 0.5, 0))
					# Safely transfer any ongoing digestion props to merge_target
					if props:
						for p in props.props:
							if p.state == SlimeProps.STATE_EATING and p.eater == self:
								p.eater = merge_target
								# Fix 10: Avoid duplicate entries in merge target's digestion list
								if not merge_target.inside_props.has(p):
									merge_target.inside_props.append(p)
					inside_props.clear()
					queue_free()
		else:
			# Target disappeared or became invalid: cancel merge safely instead of deleting self
			is_merging = false
			merge_target = null
			_has_merged = false
		return

	# ---- PARENT fission: budding separation ----
	if is_fissioning:
		fission_timer += dt
		var k: float = clampf(fission_timer / fission_duration, 0.0, 1.0)
		var e := sin(k * PI * 0.5)

		slime_scale = lerpf(fission_start_scale, fission_target_scale, e)
		_apply_transform()

		var stretch_amt := sin(k * PI) * 0.75
		if _mat:
			_mat.set_shader_parameter("uSplitAmt", stretch_amt)
			_mat.set_shader_parameter("uSplitDir", fission_fwd)

		if k >= 1.0:
			is_fissioning = false
			slime_scale = fission_target_scale
			if _mat:
				_mat.set_shader_parameter("uSplitAmt", 0.0)

	# ---- CLONE budding: emerging from parent ----
	if is_budding:
		bud_timer += dt
		var k: float = clampf(bud_timer / bud_duration, 0.0, 1.0)
		var e := sin(k * PI * 0.5)

		slime_scale = lerpf(bud_target_scale * 0.25, bud_target_scale, e)
		_apply_transform()

		if bud_parent and is_instance_valid(bud_parent):
			var sep_dist := (bud_parent.body_radius * bud_parent.slime_scale + body_radius * slime_scale) * 1.15
			position = bud_parent.position + bud_fwd * (sep_dist * e)
			position.y = bud_parent.position.y

		var stretch_amt := sin(k * PI) * 0.75
		if _mat:
			_mat.set_shader_parameter("uSplitAmt", stretch_amt)
			_mat.set_shader_parameter("uSplitDir", -bud_fwd)

		if k >= 1.0:
			is_budding = false
			bud_parent = null
			slime_scale = bud_target_scale
			if _mat:
				_mat.set_shader_parameter("uSplitAmt", 0.0)

	# --- Handle role-based input or AI driving ---
	var desired := Vector3.ZERO
	# Lock movement during clone snap animation; parent anchors/slows during viscous fission
	if not is_budding:
		match role:
			Role.PLAYER:
				desired = _process_player_input(dt)
				if is_fissioning:
					desired *= 0.35
			Role.FOLLOWER:
				desired = _process_follower_ai(dt)
			Role.ROAMER:
				desired = _process_roamer_ai(dt)

	# --- Liquid transition ---
	var target_liquid := 1.0 if liquid_mode else 0.0
	liquid_amt += (target_liquid - liquid_amt) * (1.0 - exp(-12.0 * dt))
	if _mat:
		_mat.set_shader_parameter("uLiquid", liquid_amt)

	# --- Horizontal velocity update ---
	var v_resp := velocity_response * (0.6 if liquid_amt > 0.5 else 1.0)
	velocity = velocity.lerp(desired, 1.0 - exp(-v_resp * dt))
	position.x += velocity.x * dt
	position.z += velocity.z * dt

	# Clamp to arena boundary
	var flat := Vector2(position.x, position.z).length()
	if flat > arena_radius:
		position.x *= arena_radius / flat
		position.z *= arena_radius / flat

	# --- Scale smoothing (updated BEFORE vertical motion so ground height aligns with frame scale) ---
	slime_scale += (target_scale - slime_scale) * (1.0 - exp(-scale_response * dt))
	_apply_transform()

	# --- Vertical motion & climbing on props ---
	_process_vertical(dt)

	# --- Record breadcrumbs for followers ---
	if role == Role.PLAYER:
		_breadcrumb_timer += dt
		if _breadcrumb_timer >= 0.1:
			_breadcrumb_timer = 0.0
			# Fix 20: Record environment (ceiling height, gap width) instead of raw liquid state.
			# Followers use their own size to decide whether to flatten — not leader's Z state.
			var ceiling_h := _measure_ceiling_clearance()
			var gap_w := cur_gap_w
			breadcrumbs.append({"pos": position, "ceiling_h": ceiling_h, "gap_w": gap_w, "time": _time})
			if breadcrumbs.size() > 120:
				breadcrumbs.pop_front()

	# --- Crawl / lean springs ---
	var speed := velocity.length()
	speed01 = minf(speed / speed_for_full_crawl, 1.0)
	if speed > 0.05:
		_crawl_dir = Vector3(velocity.x, 0.0, velocity.z).normalized()
	_crawl_phase += speed * dt * crawl_rate

	var lean_target := Vector3(velocity.x * lean_gain * (1.0 - calm), 0.0, velocity.z * lean_gain * (1.0 - calm)) - _lean
	_lean_vel += lean_target * lean_stiffness * dt
	_lean_vel += _lean_vel * (-lean_damping * dt)
	_lean += _lean_vel * dt
	if _time - touch_time < 0.2:
		_lean_vel = Vector3.ZERO
		_lean *= exp(-14.0 * dt)

	# --- Eyes orientation & blink ---
	if speed > moving_threshold:
		var diff := atan2(_crawl_dir.x, _crawl_dir.z) - _facing_yaw
		diff = atan2(sin(diff), cos(diff))
		_facing_yaw += diff * (1.0 - exp(-facing_response * dt))
	var blink := blink_closed_amount if fmod(_time, blink_period) > blink_start else 1.0

	# --- Per-frame shader uniforms ---
	if _mat:
		_mat.set_shader_parameter("uImpulseTime", _impulse_time)
		_mat.set_shader_parameter("uImpulse2Time", _impulse2_time)
		_mat.set_shader_parameter("uMoveDir", _crawl_dir)
		_mat.set_shader_parameter("uMoveAmt", speed01 * (1.0 - 0.95 * calm))
		_mat.set_shader_parameter("uCrawl", _crawl_phase)
		_mat.set_shader_parameter("uLean", _lean)
		_mat.set_shader_parameter("uRippleIntensity", ripple_base + ripple_per_speed * speed01 + liquid_amt * 0.15)
		_mat.set_shader_parameter("uFacing", _facing_yaw)
		_mat.set_shader_parameter("uBlink", blink)

	# --- Engulfing update ---
	# Fix 21: Followers flattening to fit under overhangs must NOT accidentally devour props
	if not (role == Role.FOLLOWER and _following_flatten):
		_process_engulf(dt)


func _process_player_input(dt: float) -> Vector3:
	# Block Z (liquid) during fission — combining deformations causes visual/physics conflicts
	var wants_liquid := Input.is_action_pressed("slime_liquid")
	if is_fissioning:
		liquid_mode = false
	else:
		liquid_mode = wants_liquid

	var in_z := Input.get_axis("move_back", "move_forward")
	var in_x := Input.get_axis("move_left", "move_right")

	var fwd := Vector3(0, 0, -1)
	if camera:
		fwd = -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var desired := fwd * in_z + right * in_x

	if liquid_mode:
		cur_max = liquid_speed
	elif Input.is_action_pressed("run"):
		cur_max = run_speed
	else:
		cur_max = walk_speed

	if desired.length_squared() > 0.0:
		desired = desired.normalized() * cur_max
	return desired


func _process_follower_ai(dt: float) -> Vector3:
	# Fix 20–23: Environment breadcrumbs, own clearance decision, stuck detection, beeline cap
	if target_leader == null or not is_instance_valid(target_leader):
		target_leader = null
		if props and props.player_slime and is_instance_valid(props.player_slime) and props.player_slime != self:
			target_leader = props.player_slime
		else:
			_following_flatten = false
			return Vector3.ZERO

	# Determine individual slot offset so followers don't stack on top of each other
	var follower_index := 0
	if props:
		for s in props.registered_slimes:
			if s == self:
				break
			if is_instance_valid(s) and s.role == Role.FOLLOWER and s.target_leader == target_leader:
				follower_index += 1

	var slot_spacing := (slime_scale * body_radius * 2.0 + 0.8)
	var desired_dist := follow_distance * (target_leader.slime_scale + slime_scale) * 0.5 + float(follower_index) * slot_spacing

	var target_pt := target_leader.position
	# Fix 20: Use recorded environment to decide liquid — NOT the leader's liquid_mode directly
	var env_ceiling_h := INF
	var env_gap_w := INF

	var trail := target_leader.breadcrumbs
	var found_breadcrumb := false
	if trail.size() > 0:
		var accum := 0.0
		var prev := target_leader.position
		for i in range(trail.size() - 1, -1, -1):
			var b = trail[i]
			accum += prev.distance_to(b["pos"])
			prev = b["pos"]
			if accum >= desired_dist:
				target_pt = b["pos"]
				env_ceiling_h = b.get("ceiling_h", INF)
				env_gap_w = b.get("gap_w", INF)
				found_breadcrumb = true
				break

	if not found_breadcrumb:
		# Fallback: stay behind leader rather than collapsing onto leader's center
		var leader_back := -target_leader._crawl_dir
		if leader_back.length_squared() < 0.01:
			leader_back = Vector3(0, 0, 1)
		target_pt = target_leader.position + leader_back.normalized() * desired_dist

	var to_target := target_pt - position
	to_target.y = 0.0
	var dist := to_target.length()

	# Fix 22: Follower stuck detection
	_follower_stuck_timer += dt
	if _ai_last_pos.distance_squared_to(position) > 0.3:
		_follower_stuck_timer = 0.0
		_ai_last_pos = position
	if _follower_stuck_timer > 3.0 and dist > 1.0:
		# Pick an intermediate position offset to get unstuck
		var perp := to_target.cross(Vector3.UP).normalized()
		target_pt = position + perp * 3.0 + to_target.normalized() * 2.0
		_follower_stuck_timer = 0.0

	# Fix 20: Decide liquid from environment, not leader's state
	# Need clearance for our actual size, with lookahead (start flattening before reaching low spot)
	var my_full_height := height_per_scale * slime_scale * 2.0
	var needs_flat := env_ceiling_h < my_full_height * 1.1 or env_gap_w < body_radius * slime_scale * 1.8
	# Hysteresis: flatten when needed, only un-flatten when clearance is comfortable
	var has_room := env_ceiling_h > my_full_height * 1.4 and env_gap_w > body_radius * slime_scale * 2.5
	if needs_flat and not _following_flatten:
		_following_flatten = true
		liquid_mode = true
	elif _following_flatten and has_room:
		_following_flatten = false
		liquid_mode = false
	# Also flatten if our own squeeze detector says we're squeezing
	if squeeze_k < 0.65 and not _following_flatten:
		_following_flatten = true
		liquid_mode = true
	elif _following_flatten and squeeze_k > 0.85 and has_room:
		_following_flatten = false
		liquid_mode = false

	# Fix 23: Cap beeline speed — no tunneling through walls when catching up
	var base_speed := liquid_speed if liquid_mode else walk_speed
	var max_catch_up := run_speed * 0.9
	cur_max = max_catch_up if dist > 8.0 else base_speed

	# Smooth arrival easing to prevent stopping threshold jitter/overshoot
	var stop_dist := slime_scale * 0.35 + 0.2
	var slow_dist := stop_dist + 2.0
	if dist <= stop_dist:
		return Vector3.ZERO

	var speed_factor := clampf((dist - stop_dist) / (slow_dist - stop_dist), 0.0, 1.0)
	speed_factor = speed_factor * speed_factor * (3.0 - 2.0 * speed_factor)
	return to_target.normalized() * (cur_max * speed_factor)


func _process_roamer_ai(dt: float) -> Vector3:
	## Fix 19: Pure wander — no food goal-seeking. Gentle heading drift with collision-driven liquid.
	_ai_roam_timer += dt
	_ai_stuck_timer += dt
	if _ai_recovery_timer > 0.0:
		_ai_recovery_timer = maxf(0.0, _ai_recovery_timer - dt)

	# Stuck detection
	if _ai_last_pos.distance_squared_to(position) > 0.2:
		_ai_stuck_timer = 0.0
		_ai_last_pos = position

	# Stuck recovery: pick an escape heading and go liquid briefly
	if _ai_stuck_timer > 2.5:
		if _ai_stuck_timer > 4.5:
			var ang := randf() * TAU
			var escape_dest := position + Vector3(cos(ang) * 12.0, 0, sin(ang) * 12.0)
			var flat := Vector2(escape_dest.x, escape_dest.z)
			if flat.length() > arena_radius * 0.85:
				flat = flat.normalized() * (arena_radius * 0.75)
				escape_dest.x = flat.x
				escape_dest.z = flat.y
			_ai_target_pos = escape_dest
			_ai_stuck_timer = 0.0
			_ai_recovery_timer = 2.5
		# Liquid during stuck, cleared below with hysteresis
		if not liquid_mode:
			liquid_mode = true

	# Liquid hysteresis: squeeze_k < 0.6 → go liquid; don't un-liquid until squeeze_k > 0.85
	# This prevents rapid flickering at the threshold.
	if squeeze_k < 0.6 and not liquid_mode:
		liquid_mode = true
	elif liquid_mode and squeeze_k > 0.85 and _ai_recovery_timer <= 0.0 and _ai_stuck_timer < 1.0:
		liquid_mode = false

	# Wander: pick a new gentle heading every 2–4 seconds
	if _ai_roam_timer > 0.0 and (position.distance_squared_to(_ai_target_pos) < 9.0 or _ai_target_pos == Vector3.ZERO):
		_ai_roam_timer = 0.0
		# Drift heading ±45° from current crawl direction rather than fully random long goals
		var base_ang := atan2(_crawl_dir.x, _crawl_dir.z) if _crawl_dir.length_squared() > 0.01 else randf() * TAU
		var drift := randf_range(-PI * 0.4, PI * 0.4)
		var new_ang := base_ang + drift
		var wander_dist := randf_range(6.0, 14.0)
		var wander_dest := position + Vector3(sin(new_ang) * wander_dist, 0.0, cos(new_ang) * wander_dist)
		var flat := Vector2(wander_dest.x, wander_dest.z)
		if flat.length() > arena_radius * 0.85:
			flat = flat.normalized() * (arena_radius * 0.75)
			wander_dest.x = flat.x
			wander_dest.z = flat.y
		_ai_target_pos = wander_dest
		# Randomize next heading change interval (2–4 s)
		_ai_roam_timer = -randf_range(2.0, 4.0)

	var wander_dir := (_ai_target_pos - position)
	wander_dir.y = 0.0
	var desired_heading := wander_dir.normalized() if wander_dir.length_squared() > 0.01 else _crawl_dir

	cur_max = liquid_speed if liquid_mode else walk_speed
	return desired_heading * cur_max


func _find_best_food_for_roamer():
	if props == null:
		return null
	var edible_lim := body_radius * slime_scale * 1.5
	var best_p = null
	var best_score := -99999.0

	for p in props.props:
		if p.state != SlimeProps.STATE_IDLE or p.get("is_static") or p.radius >= edible_lim:
			continue
		if p.mesh == null or not is_instance_valid(p.mesh):
			continue
		var dist := position.distance_to(p.mesh.position)
		if dist > 85.0:
			continue
		var score: float = (p.radius * 25.0) - dist * 1.2
		if score > best_score:
			best_score = score
			best_p = p
	return best_p


func _process_vertical(dt: float) -> void:
	# Node position stays firmly at support height; vertex shader flattens from the top down to the floor
	var S := slime_scale
	var full_target_y := support_y + (height_per_scale * S)

	# Fix 6: Before standing back up from liquid, check for overhead clearance.
	# If a prop is in the way, stay flat (liquid_clearance_ratio height) rather than getting ejected sideways.
	# Overhead clearance check:
	# Keep the base firmly anchored to support_y, and pass headroom compression to shader,
	# NEVER sink the node position.y into the floor!
	var target_y := full_target_y
	var overhead_compression := 1.0
	if liquid_amt > 0.05 and props != null:
		var full_top := support_y + (2.0 * height_per_scale * S)
		var flat_top := support_y + (2.0 * height_per_scale * S * liquid_height_ratio)
		var slime_r := body_radius * S
		var overhead_blocked := false
		for p in props.props:
			if p.state != SlimeProps.STATE_IDLE or p.mesh == null:
				continue
			var m := p.mesh
			var he := props._half_of(p)
			var prop_bottom := m.position.y - he.y
			if prop_bottom < flat_top or prop_bottom > full_top + 0.2:
				continue
			var dx := m.position.x - position.x
			var dz := m.position.z - position.z
			var dist_h := Vector2(dx, dz).length()
			if dist_h < slime_r + maxf(he.x, he.z) * 0.9:
				overhead_blocked = true
				var available_height := maxf(0.1, prop_bottom - support_y)
				overhead_compression = clampf(available_height / (2.0 * height_per_scale * S), liquid_height_ratio, 1.0)
				break
		if overhead_blocked and not liquid_mode and role == Role.PLAYER:
			liquid_mode = true

	set_shader_param("uOverheadCompress", overhead_compression)

	# Fix 25: When shrinking (target_scale < slime_scale), target_y drops and would trigger
	# gravity fall. Instead, lerp down smoothly to avoid a micro-bounce on every split/merge.
	var is_shrinking := target_scale < slime_scale - 0.01
	if position.y > target_y + 0.02 and not is_shrinking:
		is_on_ground = false
		vertical_vel -= 22.0 * dt
		position.y += vertical_vel * dt
		if position.y <= target_y:
			position.y = target_y
			vertical_vel = 0.0
			is_on_ground = true
	else:
		position.y = lerpf(position.y, target_y, 1.0 - exp(-16.0 * dt))
		vertical_vel = 0.0
		is_on_ground = true
	# In liquid mode the puddle still must stay at or above the floor — clamp it.
	var liquid_floor := floor_y + height_per_scale * S * liquid_height_ratio * 0.5
	if liquid_amt > 0.1 and position.y < liquid_floor:
		position.y = liquid_floor


func _process_engulf(dt: float) -> void:
	# Liquid mode (Z key) engulfing:
	# If covering an object with the liquid body from above or all around,
	# the slime drapes over and devours the object!
	# NO arbitrary radius cutoffs — eligibility is determined by physical coverage and volume budget!
	var target_p = null
	if liquid_mode and liquid_amt > 0.35 and props != null:
		var S := slime_scale
		var spread := lerpf(1.0, liquid_spread_ratio, liquid_amt)
		var puddle_radius := body_radius * S * spread
		# Actual liquid puddle bottom sits at support_y / floor_y:
		var puddle_bottom := support_y
		var my_volume := get_volume()

		# Check props: prioritize currently mounted ground_prop if any, else check nearby props
		var candidates: Array = []
		if ground_prop != null and ground_prop.state == SlimeProps.STATE_IDLE and not ground_prop.is_static:
			candidates.append(ground_prop)
		for p in props.props:
			if p.state == SlimeProps.STATE_IDLE and not p.is_static and p != ground_prop:
				candidates.append(p)

		var best_score := -INF
		for p in candidates:
			var m: MeshInstance3D = p.mesh
			if m == null or not is_instance_valid(m):
				continue
			var he: Vector3 = props._half_of(p)
			var prop_top: float = m.position.y + he.y
			var prop_bottom: float = m.position.y - he.y

			# Section 4 Volume budget: covering requires enough slime volume to form a shell
			# Shell area approx = top footprint + side walls
			var top_area := 4.0 * he.x * he.z if p.shape == SlimeProps.SHAPE_BOX else (PI * he.x * he.z)
			var side_area := (4.0 * he.x + 4.0 * he.z) * (2.0 * he.y)
			var min_shell_thickness := 0.08 * S
			var needed_shell_volume := (top_area + side_area) * min_shell_thickness
			if my_volume < needed_shell_volume * 0.8:
				continue # Slime doesn't have enough volume to cover this shape

			var flat_d: float = Vector2(position.x - m.position.x, position.z - m.position.z).length()

			# Coverage check against real footprint (corner / vertex reach):
			var prop_max_r: float = Vector2(he.x, he.z).length()
			var covers_horiz := (flat_d + prop_max_r <= puddle_radius * 1.05)

			# Vertical reach: slime must be atop or draping down over the prop
			var touches_vert := (puddle_bottom <= prop_top + 0.3 * S) and (position.y + 0.5 * S >= prop_bottom)

			if covers_horiz and touches_vert:
				var score: float = 1000.0 - flat_d
				if score > best_score:
					best_score = score
					target_p = p
				break # Found best valid candidate (prioritized ground_prop)

	if target_p != null:
		if engulf_target != target_p:
			engulf_target = target_p
			engulf_progress = 0.0

		engulf_progress = minf(1.0, engulf_progress + dt / maxf(devour_duration, 0.1))

		if _mat and target_p.mesh and is_instance_valid(target_p.mesh):
			var m: MeshInstance3D = target_p.mesh
			_mat.set_shader_parameter("uDrapePos", (m.position - position) / slime_scale)
			_mat.set_shader_parameter("uDrapeHalf", target_p.half * m.scale.x / slime_scale)
			_mat.set_shader_parameter("uDrapeShape", float(target_p.shape) + target_p.sides * 0.01)
			_mat.set_shader_parameter("uDrapeYaw", m.rotation.y)
			_mat.set_shader_parameter("uDrapeAmt", engulf_progress)

		if engulf_progress >= 1.0:
			_devour_prop(target_p)
			engulf_progress = 0.0
			engulf_target = null
			if _mat:
				_mat.set_shader_parameter("uDrapeAmt", 0.0)
		return

	# Target was lost or not covering: decay visual draping and progress
	if engulf_progress > 0.0:
		engulf_progress = maxf(0.0, engulf_progress - dt * 2.0)
		if _mat:
			_mat.set_shader_parameter("uDrapeAmt", engulf_progress)
		if engulf_progress <= 0.001:
			engulf_progress = 0.0
			engulf_target = null
			if _mat:
				_mat.set_shader_parameter("uDrapeAmt", 0.0)
	else:
		engulf_target = null


func _measure_ceiling_clearance() -> float:
	## Returns the vertical clearance above this slime (distance to nearest overhead prop bottom).
	if props == null:
		return INF
	var S := slime_scale
	var slime_top := position.y + height_per_scale * S
	var slime_r := body_radius * S
	var closest := INF
	for p in props.props:
		if p.state != SlimeProps.STATE_IDLE or p.mesh == null:
			continue
		var m := p.mesh
		var he := props._half_of(p)
		var prop_bottom := m.position.y - he.y
		if prop_bottom <= slime_top:
			continue  # below or at our level
		var dx := m.position.x - position.x
		var dz := m.position.z - position.z
		if Vector2(dx, dz).length() < slime_r + maxf(he.x, he.z):
			var clearance := prop_bottom - slime_top
			if clearance < closest:
				closest = clearance
	return closest


func _devour_prop(p) -> void:
	p.state = SlimeProps.STATE_EATING
	p.eater = self
	p.base_scale = p.mesh.scale # store exact scale: can never grow bigger when digesting!
	p.t = 0.0
	p.start = p.mesh.position
	p.off = Vector3(randf() - 0.5, -0.1 + randf() * 0.3, randf() - 0.5)
	p.total_mass = pow(p.radius, 3.0) * 0.3
	p.absorbed_mass = 0.0
	inside_props.append(p)
	if props:
		props.eaten += 1
		props.eaten_changed.emit(props.eaten)


func split_clone(clone_role: Role) -> void:
	## Split into two independent volume-conserved slimes (each = 0.7937x parent scale).
	# Block splits during liquid mode (Z), while transitioning back to solid, or while engulfing
	if target_scale < 0.45 or is_fissioning or is_budding or is_merging:
		return
	if liquid_mode or liquid_amt > 0.1 or engulf_target != null or Input.is_action_pressed("slime_liquid"):
		return

	# Fix 26: Use camera direction if slime is standing still, rather than stale _crawl_dir
	var fwd: Vector3
	if velocity.length() > 0.3:
		fwd = _crawl_dir.normalized()
	elif camera:
		fwd = -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	else:
		fwd = _crawl_dir.normalized()
	if fwd.length_squared() < 0.01:
		fwd = Vector3(0, 0, -1)

	var split_fwd := -fwd
	var new_target_scale := target_scale * pow(0.5, 1.0 / 3.0)

	# Spawn clone FIRST. If spawning fails, parent is completely untouched!
	var clone := _spawn_fission_clone(clone_role, split_fwd, new_target_scale)
	if clone == null:
		return

	# Only commit parent fission state after successful clone spawn
	fission_fwd = split_fwd
	fission_duration = 0.38
	fission_start_scale = slime_scale
	fission_target_scale = new_target_scale
	target_scale = new_target_scale
	is_fissioning = true
	fission_timer = 0.0


func _spawn_fission_clone(clone_role: Role, fwd_dir: Vector3, clone_target_scale: float) -> Slime:
	var prefab := load("res://scenes/slime.tscn") as PackedScene
	if prefab == null:
		return null
	var clone := prefab.instantiate() as Slime
	if clone == null:
		return null

	clone.role = clone_role
	clone.start_scale = clone_target_scale * 0.25
	clone.target_scale = clone_target_scale
	clone.slime_scale = clone.start_scale
	clone.props = props
	clone.floor_mesh = floor_mesh
	clone.floor_y = floor_y
	clone.support_y = support_y

	clone.position = position + fwd_dir * (0.2 * body_radius * clone_target_scale)
	clone.position.y = position.y
	clone._facing_yaw = _facing_yaw

	if clone_role == Role.FOLLOWER:
		clone.target_leader = self

	clone.is_budding = true
	clone.bud_parent = self
	clone.bud_timer = 0.0
	clone.bud_duration = 0.38
	clone.bud_target_scale = clone_target_scale
	clone.bud_fwd = fwd_dir

	var p_node := get_parent()
	if p_node:
		p_node.add_child(clone)
	else:
		return null

	return clone


func merge_nearby_clones() -> void:
	# Fix 8: Block merging during liquid/engulf states
	if props == null or is_merging or is_fissioning or is_budding:
		return
	if liquid_mode or liquid_amt > 0.1:
		return
	# Reduced merge range to prevent pulling clones through walls
	var merge_rad := (body_radius * slime_scale) * 2.5 + 1.0
	var to_merge: Array[Slime] = []

	for s in props.registered_slimes:
		if s == self or not is_instance_valid(s) or s.is_merging or s.is_fissioning or s.is_budding:
			continue
		# Fix 9: Skip clones in liquid state too (undefined interaction)
		if s.liquid_mode or s.liquid_amt > 0.1:
			continue
		var dist := position.distance_to(s.position)
		if dist > merge_rad + (s.body_radius * s.slime_scale):
			continue
		# Simple line-of-sight check: reject if any static wall AABB separates the two positions
		var blocked := false
		if props:
			var from2 := Vector2(position.x, position.z)
			var to2 := Vector2(s.position.x, s.position.z)
			for p in props.props:
				if not p.is_static or p.mesh == null:
					continue
				var m := p.mesh
				var he := props._half_of(p)
				# AABB 2D segment intersection (simple rejection test)
				var bmin := Vector2(m.position.x - he.x, m.position.z - he.z)
				var bmax := Vector2(m.position.x + he.x, m.position.z + he.z)
				# Expand box slightly for safety
				bmin -= Vector2(0.1, 0.1)
				bmax += Vector2(0.1, 0.1)
				var seg := to2 - from2
				var t0 := 0.0
				var t1 := 1.0
				for axis in 2:
					var o := from2[axis]
					var d2 := seg[axis]
					var lo := bmin[axis]
					var hi := bmax[axis]
					if absf(d2) < 1e-6:
						if o < lo or o > hi:
							t0 = 1.0  # parallel and outside
							break
					else:
						var ta := (lo - o) / d2
						var tb := (hi - o) / d2
						if ta > tb:
							var tmp := ta; ta = tb; tb = tmp
						t0 = maxf(t0, ta)
						t1 = minf(t1, tb)
				if t0 <= t1:
					blocked = true
					break
		if not blocked:
			to_merge.append(s)

	if to_merge.is_empty():
		return

	for s in to_merge:
		s.is_merging = true
		s.merge_target = self
		s.merge_timer = 0.0
		s.merge_duration = 0.42
		s.merge_source_scale = s.target_scale
		s.velocity = Vector3.ZERO

	trigger_poke(Vector3(0, 0.3, 0), Vector3(0, -0.6, 0))


func set_shader_param(param: StringName, value: Variant) -> void:
	if _mat:
		_mat.set_shader_parameter(param, value)


func _apply_transform() -> void:
	scale = Vector3.ONE * slime_scale
