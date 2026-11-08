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
@export var min_phi := 0.35
@export_range(0.0, 3.14159, 0.01) var max_phi := 1.5080

@export_group("Zoom")
@export var zoom_step := 0.3
## Radius limits, multiplied by the slime's current scale.
@export var min_radius_per_scale := 3.0
@export var max_radius_per_scale := 9.5

@export_group("Follow")
## Height of the look-at point above the slime's centre, per unit of slime scale.
@export var target_height_per_scale := 0.15
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
		phi = clampf(phi - motion.relative.y * drag_sensitivity, min_phi, max_phi)
		_update_camera()
	elif event.is_action_pressed("zoom_in"):
		_zoom(-zoom_step)
	elif event.is_action_pressed("zoom_out"):
		_zoom(zoom_step)


func _zoom(amount: float) -> void:
	if follow == null:
		return
	var s := follow.slime_scale
	radius = clampf(radius + amount, min_radius_per_scale * s, max_radius_per_scale * s)
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
	var target_look_y := follow.position.y + target_height_per_scale * s - (0.55 * s * follow.liquid_amt)
	if absf(s - _last_scale) > 1e-4:
		radius *= s / _last_scale
		target.y = target_look_y
		_last_scale = s
		_update_camera()
	else:
		target.y = lerpf(target.y, target_look_y, 1.0 - exp(-6.0 * _delta))
	if _engaged:
		target.x = follow.position.x
		target.z = follow.position.z
	_update_camera()


func _update_camera() -> void:
	var offset := Vector3(
		radius * sin(phi) * sin(theta),
		radius * cos(phi),
		radius * sin(phi) * cos(theta))
	var cam_pos := target + offset
	var floor_y := follow.tuning.floor_y if follow != null and follow.tuning != null else -1.2
	cam_pos.y = maxf(cam_pos.y, floor_y + 0.25)
	camera.global_position = cam_pos
	camera.look_at(target, Vector3.UP)
