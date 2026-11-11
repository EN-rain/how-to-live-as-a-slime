class_name OrbitCamera
extends Node3D
## Drag-to-orbit, wheel-zoom camera that follows the slime. Mirrors the HTML's cameraState.

@export var camera: Camera3D
@export var follow: Slime

@export_group("Orbit")
@export var theta := 0.45
@export var phi := 1.18
@export var radius := 5.4
@export var drag_sensitivity := 0.007
@export var invert_y := false
@export var min_phi := 0.22
@export_range(0.0, 3.14159, 0.01) var max_phi := 2.50

@export_group("Zoom")
@export var zoom_step := 0.3
## Radius limits, multiplied by the slime's current scale.
@export var min_radius_per_scale := 3.0
@export var max_radius_per_scale := 9.5

@export_group("Follow")
## Height of the look-at point above the slime's centre, per unit of slime scale.
@export var target_height_per_scale := 0.15
## Vertical offset reduction when slime is in liquid state, per unit scale.
@export var liquid_height_drop := 0.55
## Vertical look-at smoothing lerp rate.
@export var vertical_follow_lerp := 14.0
## Minimum vertical clearance above floor/ground level for camera position.
@export var min_floor_clearance := 0.25
## Height offset below slime position to assume ground plane when ungrounded.
@export var floor_offset := 1.5
## Camera starts following once the slime moves faster than this (0..1 of walk speed).
## Negative means "use the slime's authored tuning value".
@export var follow_speed_threshold := -1.0

var target := Vector3.ZERO
var _dragging := false
var _last_scale := 1.0
var _engaged := false


func _ready() -> void:
	if follow:
		_last_scale = follow.slime_scale
		target = follow.position + Vector3.UP * target_height_per_scale * follow.slime_scale
		_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if follow == null:
		return
	if event.is_action_pressed("orbit_drag"):
		_dragging = true
	elif event.is_action_released("orbit_drag"):
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		theta -= motion.relative.x * drag_sensitivity
		var y_dir := 1.0 if invert_y else -1.0
		phi = clampf(phi + motion.relative.y * drag_sensitivity * y_dir, min_phi, max_phi)
		_update_camera()
	elif event.is_action_pressed("zoom_in"):
		if follow.dev_mode and Input.is_key_pressed(KEY_ALT):
			return
		_zoom(-zoom_step)
	elif event.is_action_pressed("zoom_out"):
		if follow.dev_mode and Input.is_key_pressed(KEY_ALT):
			return
		_zoom(zoom_step)


func _zoom(amount: float) -> void:
	if follow == null:
		return
	var s := follow.slime_scale
	var max_r := (28.0 if follow.dev_mode else max_radius_per_scale) * s
	radius = clampf(radius + amount, min_radius_per_scale * s, max_r)
	_update_camera()


func _process(_delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return
	if not _engaged:
		var thr := follow_speed_threshold
		if thr < 0.0 and follow.tuning != null:
			thr = follow.tuning.follow_speed_threshold
		if follow.speed01 > maxf(thr, 0.0):
			_engaged = true
	var s := follow.slime_scale
	var target_look_y := follow.position.y + target_height_per_scale * s - (liquid_height_drop * s * follow.liquid_amt)
	if absf(s - _last_scale) > 1e-4:
		radius *= s / _last_scale
		target.y = target_look_y
		_last_scale = s
		_update_camera()
	else:
		target.y = lerpf(target.y, target_look_y, 1.0 - exp(-vertical_follow_lerp * _delta))
	if _engaged or follow.dev_mode:
		target.x = follow.position.x
		target.z = follow.position.z
	_update_camera()


func _update_camera() -> void:
	var up_t := clampf((phi - 1.35) / maxf(max_phi - 1.35, 0.01), 0.0, 1.0)
	var eff_phi := minf(phi, 1.58)
	var eff_radius := radius * lerpf(1.0, 0.68, up_t)
	var offset := Vector3(
		eff_radius * sin(eff_phi) * sin(theta),
		eff_radius * cos(eff_phi),
		eff_radius * sin(eff_phi) * cos(theta))
	var cam_pos := target + offset
	var look_target := target + Vector3.UP * (up_t * radius * 1.85)
	var noclip_cam := follow != null and follow.is_dev_noclip_active()
	if not noclip_cam:
		var floor_y := (follow.global_position.y - floor_offset) if follow != null else -1.2
		cam_pos.y = maxf(cam_pos.y, floor_y + min_floor_clearance)
		if is_inside_tree() and get_world_3d() != null:
			var space := get_world_3d().direct_space_state
			var to_cam := cam_pos - target
			var dist := to_cam.length()
			if space != null and dist > 0.6:
				var dir := to_cam / dist
				var ray := PhysicsRayQueryParameters3D.create(target + dir * 0.45, cam_pos + dir * 0.25, 1 | 4)
				ray.collide_with_areas = false
				var hit := space.intersect_ray(ray)
				if not hit.is_empty():
					var hit_pos: Vector3 = hit.position
					var safe_dist := maxf(target.distance_to(hit_pos) - 0.32, 1.35)
					cam_pos = target + dir * minf(dist, safe_dist)
	camera.global_position = cam_pos
	var view_vec := look_target - cam_pos
	if view_vec.length_squared() > 1e-4:
		var v_norm := view_vec.normalized()
		var up_vec := Vector3.UP
		if absf(v_norm.dot(up_vec)) > 0.99:
			up_vec = Vector3(sin(theta), 0.0, cos(theta)).normalized()
		camera.look_at(look_target, up_vec)
