class_name OrbitCamera
extends Node3D
## Silky-smooth drag-to-orbit, wheel-zoom camera with critically damped tracking,
## rotational inertia, smooth zoom interpolation, and non-snapping spring-arm occlusion.

@export var camera: Camera3D
@export var follow: Slime

@export_group("Orbit & Feel")
@export var theta := 0.45
@export var phi := 1.18
@export var radius := 5.4
@export var drag_sensitivity := 0.0055
@export var invert_y := false
@export var min_phi := 0.22
@export_range(0.0, 3.14159, 0.01) var max_phi := 2.50
## Rotational damping rate (higher = snappier, lower = more floaty/cinematic).
@export var rotation_smoothing := 18.0

@export_group("Zoom")
@export var zoom_step := 0.5
@export var zoom_smoothing := 14.0
## Radius limits, multiplied by the slime's current scale.
@export var min_radius_per_scale := 3.0
@export var max_radius_per_scale := 9.5

@export_group("Follow")
## Height of the look-at point above the slime's centre, per unit of slime scale.
@export var target_height_per_scale := 0.15
## Vertical offset reduction when slime is in liquid state, per unit scale.
@export var liquid_height_drop := 0.55
## Horizontal look-at smoothing rate.
@export var horizontal_follow_lerp := 16.0
## Vertical look-at smoothing lerp rate.
@export var vertical_follow_lerp := 12.0
## Lead velocity look-ahead time in seconds.
@export var velocity_lead_time := 0.08
## Minimum vertical clearance above floor/ground level for camera position.
@export var min_floor_clearance := 0.25
## Height offset below slime position to assume ground plane when ungrounded.
@export var floor_offset := 1.5
## Camera starts following once the slime moves faster than this (0..1 of walk speed).
## Negative means "use the slime's authored tuning value".
@export var follow_speed_threshold := -1.0

var target := Vector3.ZERO
var _target_theta := 0.45
var _target_phi := 1.18
var _target_radius := 5.4
var _current_occlusion_dist := 5.4
var _dragging := false
var _last_scale := 1.0
var _engaged := false
var _smoothed_vel := Vector3.ZERO
var _ang_vel_theta := 0.0
var _ang_vel_phi := 0.0
var _frame_drag_theta := 0.0
var _frame_drag_phi := 0.0
var _last_written_theta := 0.45
var _last_written_phi := 1.18
var _last_written_radius := 5.4


func _ready() -> void:
	_target_theta = theta
	_target_phi = phi
	_target_radius = radius
	_last_written_theta = theta
	_last_written_phi = phi
	_last_written_radius = radius
	_current_occlusion_dist = radius
	if follow:
		_last_scale = follow.slime_scale
		var follow_pos := follow.get_visual_position() if follow.has_method("get_visual_position") else follow.global_position
		target = follow_pos + Vector3.UP * (target_height_per_scale * follow.slime_scale)
		_update_camera(1.0 / 60.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false
		_ang_vel_theta = 0.0
		_ang_vel_phi = 0.0
		_frame_drag_theta = 0.0
		_frame_drag_phi = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if follow == null or follow.is_dead:
		_dragging = false
		return
	if event.is_action_pressed("orbit_drag") or (event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE) and event.pressed):
		_dragging = true
		_ang_vel_theta = 0.0
		_ang_vel_phi = 0.0
	elif event.is_action_released("orbit_drag") or (event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE) and not event.pressed):
		if not Input.is_action_pressed("orbit_drag") \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var orbit_held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) \
			or Input.is_action_pressed("orbit_drag")
		if not orbit_held:
			_dragging = false
			return
		var motion := event as InputEventMouseMotion
		var d_theta := -clampf(motion.relative.x * drag_sensitivity, -0.35, 0.35)
		var y_dir := 1.0 if invert_y else -1.0
		var d_phi := clampf(motion.relative.y * drag_sensitivity * y_dir, -0.35, 0.35)
		_target_theta += d_theta
		var prev_phi := _target_phi
		_target_phi = clampf(_target_phi + d_phi, min_phi, max_phi)
		_frame_drag_theta += d_theta
		_frame_drag_phi += (_target_phi - prev_phi)
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		var d_theta := -clampf(pan.delta.x * drag_sensitivity * 12.0, -0.35, 0.35)
		var y_dir := 1.0 if invert_y else -1.0
		var d_phi := clampf(pan.delta.y * drag_sensitivity * 12.0 * y_dir, -0.35, 0.35)
		_target_theta += d_theta
		_target_phi = clampf(_target_phi + d_phi, min_phi, max_phi)
	elif event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		_zoom((1.0 - clampf(mag.factor, 0.5, 2.0)) * 5.0)
	elif event.is_action_pressed("zoom_in") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed):
		if follow.dev_mode and Input.is_key_pressed(KEY_ALT):
			return
		_zoom(-zoom_step)
	elif event.is_action_pressed("zoom_out") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed):
		if follow.dev_mode and Input.is_key_pressed(KEY_ALT):
			return
		_zoom(zoom_step)


func _zoom(amount: float) -> void:
	if follow == null:
		return
	var s := follow.slime_scale
	var max_r := (28.0 if follow.dev_mode else max_radius_per_scale) * s
	var mult := clampf(_target_radius / 4.2, 0.65, 3.8) * (2.2 if follow.dev_mode else 1.35)
	_target_radius = clampf(_target_radius + amount * mult, min_radius_per_scale * s, max_r)


func _process(delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return
	if absf(theta - _last_written_theta) > 1e-5:
		_target_theta = theta
	if absf(phi - _last_written_phi) > 1e-5:
		_target_phi = clampf(phi, min_phi, max_phi)
	if absf(radius - _last_written_radius) > 1e-5:
		_target_radius = radius
	if not _engaged:
		var thr := follow_speed_threshold
		if thr < 0.0 and follow.tuning != null:
			thr = follow.tuning.follow_speed_threshold
		if follow.speed01 > maxf(thr, 0.0):
			_engaged = true

	var dt := clampf(delta, 1e-4, 0.1)
	var s := follow.slime_scale

	# Handle scale adjustments smoothly
	if absf(s - _last_scale) > 1e-4:
		var ratio := s / _last_scale
		_target_radius *= ratio
		radius *= ratio
		_current_occlusion_dist *= ratio
		_last_scale = s

	# Track drag angular release velocity & apply subtle release inertia
	if _dragging or absf(_frame_drag_theta) > 1e-7 or absf(_frame_drag_phi) > 1e-7:
		var vel_alpha := 1.0 - exp(-22.0 * dt)
		_ang_vel_theta = lerpf(_ang_vel_theta, clampf(_frame_drag_theta / dt, -10.0, 10.0), vel_alpha)
		_ang_vel_phi = lerpf(_ang_vel_phi, clampf(_frame_drag_phi / dt, -10.0, 10.0), vel_alpha)
		_frame_drag_theta = 0.0
		_frame_drag_phi = 0.0
	if not _dragging:
		if absf(_ang_vel_theta) > 1e-4 or absf(_ang_vel_phi) > 1e-4:
			_target_theta += _ang_vel_theta * dt
			var next_phi := clampf(_target_phi + _ang_vel_phi * dt, min_phi, max_phi)
			if next_phi == min_phi or next_phi == max_phi:
				_ang_vel_phi = 0.0
			_target_phi = next_phi
			var coast_decay := exp(-12.0 * dt)
			_ang_vel_theta *= coast_decay
			_ang_vel_phi *= coast_decay
		else:
			_ang_vel_theta = 0.0
			_ang_vel_phi = 0.0

	# 1. Rotational smoothing (critical damping of orbit angles)
	theta = lerpf(theta, _target_theta, 1.0 - exp(-rotation_smoothing * dt))
	phi = lerpf(phi, _target_phi, 1.0 - exp(-rotation_smoothing * dt))
	_last_written_theta = theta
	_last_written_phi = phi

	# 2. Smooth zoom interpolation
	radius = lerpf(radius, _target_radius, 1.0 - exp(-zoom_smoothing * dt))
	_last_written_radius = radius

	# 3. Position tracking with filtered velocity lead and interpolated visual position
	var follow_pos := follow.get_visual_position() if follow.has_method("get_visual_position") else follow.global_position
	var target_look_y := follow_pos.y + target_height_per_scale * s - (liquid_height_drop * s * follow.liquid_amt)
	var raw_vel := Vector3.ZERO
	if follow.motor != null:
		raw_vel = Vector3(follow.motor.velocity.x, 0.0, follow.motor.velocity.z)
	_smoothed_vel = _smoothed_vel.lerp(raw_vel, 1.0 - exp(-8.0 * dt))

	if _engaged or follow.dev_mode:
		var lead := _smoothed_vel * velocity_lead_time
		var goal_x := follow_pos.x + lead.x
		var goal_z := follow_pos.z + lead.z
		# Teleport snap if camera fell far behind (e.g. noclip or warp)
		var h_dist_sq := (goal_x - target.x) * (goal_x - target.x) + (goal_z - target.z) * (goal_z - target.z)
		if h_dist_sq > 400.0 or absf(target_look_y - target.y) > 20.0:
			_smoothed_vel = Vector3.ZERO
			target.x = follow_pos.x
			target.z = follow_pos.z
			target.y = target_look_y
		else:
			target.x = lerpf(target.x, goal_x, 1.0 - exp(-horizontal_follow_lerp * dt))
			target.z = lerpf(target.z, goal_z, 1.0 - exp(-horizontal_follow_lerp * dt))
			target.y = lerpf(target.y, target_look_y, 1.0 - exp(-vertical_follow_lerp * dt))
	else:
		if absf(target_look_y - target.y) > 20.0:
			target.y = target_look_y
		else:
			target.y = lerpf(target.y, target_look_y, 1.0 - exp(-vertical_follow_lerp * dt))

	_update_camera(dt)


func _update_camera(dt: float = 0.016) -> void:
	if camera == null:
		return
	var s := follow.slime_scale if follow != null else 1.0
	var pitch_start := 1.22
	var eff_phi := phi
	var up_t := 0.0
	if phi > pitch_start:
		eff_phi = pitch_start + 0.42 * tanh((phi - pitch_start) / 0.42)
		var u_raw := clampf((phi - pitch_start) / maxf(max_phi - pitch_start, 0.01), 0.0, 1.0)
		up_t = u_raw * u_raw * (3.0 - 2.0 * u_raw)
	var eff_radius := radius * lerpf(1.0, 0.74, up_t)
	var offset := Vector3(
		eff_radius * sin(eff_phi) * sin(theta),
		eff_radius * cos(eff_phi),
		eff_radius * sin(eff_phi) * cos(theta))
	var cam_pos := target + offset
	var look_target := target + Vector3.UP * (up_t * s * 3.1)
	var noclip_cam := follow != null and follow.is_dev_noclip_active()

	if not noclip_cam:
		var follow_y := (follow.get_visual_position().y if follow.has_method("get_visual_position") else follow.global_position.y) if follow != null else (-1.2 + floor_offset)
		var floor_y := (follow_y - floor_offset) if follow != null else -1.2
		cam_pos.y = maxf(cam_pos.y, floor_y + min_floor_clearance)

		if is_inside_tree() and get_world_3d() != null:
			var space := get_world_3d().direct_space_state
			var to_cam := cam_pos - target
			var dist := to_cam.length()
			if space != null and dist > 0.6:
				var dir := to_cam / dist
				var ref_up := Vector3.UP
				if absf(dir.dot(ref_up)) > 0.99:
					ref_up = Vector3(sin(theta), 0.0, cos(theta)).normalized()
				var cam_right := ref_up.cross(dir).normalized()
				var cam_up := dir.cross(cam_right).normalized()
				var whisker_offsets: Array[Vector3] = [
					Vector3.ZERO,
					cam_right * 0.25,
					-cam_right * 0.25,
					cam_up * 0.22,
					-cam_up * 0.22,
				]
				var min_hit_dist := INF
				var occluded := false
				# Query obstacle geometry along view corridor (Layer 1 terrain, Layer 4 cave walls)
				var ray := PhysicsRayQueryParameters3D.new()
				ray.collision_mask = 1 | 4
				ray.collide_with_areas = false
				for w_off in whisker_offsets:
					ray.from = target + dir * 0.35 + w_off
					ray.to = cam_pos + dir * 0.35 + w_off
					var hit := space.intersect_ray(ray)
					if not hit.is_empty():
						var hit_pos: Vector3 = hit.position
						var hit_dist := maxf(target.distance_to(hit_pos) - 0.34, 1.15)
						if hit_dist < min_hit_dist:
							min_hit_dist = hit_dist
						occluded = true

				if occluded:
					# Occluded: snap/clamp inward immediately so walls never clip the near plane
					if min_hit_dist < _current_occlusion_dist:
						_current_occlusion_dist = minf(_current_occlusion_dist, min_hit_dist)
					else:
						_current_occlusion_dist = lerpf(_current_occlusion_dist, min_hit_dist, 1.0 - exp(-5.0 * dt))
				else:
					# Clear: return out smoothly so passing pillars never causes camera pumping
					_current_occlusion_dist = lerpf(_current_occlusion_dist, eff_radius, 1.0 - exp(-5.0 * dt))

				var safe_r := minf(dist, _current_occlusion_dist)
				cam_pos = target + dir * safe_r
	else:
		_current_occlusion_dist = eff_radius

	camera.global_position = cam_pos
	var view_vec := look_target - cam_pos
	if view_vec.length_squared() > 1e-4:
		var v_norm := view_vec.normalized()
		var up_vec := Vector3.UP
		if absf(v_norm.dot(up_vec)) > 0.99:
			up_vec = Vector3(sin(theta), 0.0, cos(theta)).normalized()
		camera.look_at(look_target, up_vec)
