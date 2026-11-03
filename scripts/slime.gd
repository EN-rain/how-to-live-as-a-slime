class_name Slime
extends CharacterBody3D

## The player. Movement, squash & stretch, growth, and the eating trigger.
##
## Growth curve: size = base_size * (nutrition / start_nutrition) ^ growth_exponent,
## so early bites are visibly chunky and late tiers need the bigger meals. Speed
## and jump scale with size so a bigger slime still crosses the map at a similar pace.

signal ate(nutrition: float, meal_color: Color, world_position: Vector3)
signal size_changed(new_size: float)
signal hurt

const GROUND_ACCEL := 30.0
const AIR_ACCEL := 12.0
const TURN_SPEED := 12.0
const COLOR_SHIFT_RATE := 0.06
const HURT_FLASH_STRENGTH := 0.75

@export_group("Movement")
@export var base_speed: float = 5.2
@export var base_jump: float = 7.0
@export var gravity: float = 24.0
## Speed and jump scale with size so a big slime still moves at a usable pace.
@export_range(0.0, 1.5, 0.05) var speed_scale_exponent: float = 0.55
@export_range(0.0, 1.5, 0.05) var jump_scale_exponent: float = 0.5

@export_group("Growth")
@export var start_nutrition: float = 27.0
@export_range(0.1, 1.0, 0.05) var growth_exponent: float = 0.4
@export var base_size: float = 0.8
@export var min_size: float = 0.55
@export var max_size: float = 4.0
@export var growth_duration: float = 0.35
## Damage can shrink you, but never below this nutrition.
@export var min_nutrition: float = 6.0

@export_group("Feel")
@export var jump_stretch: float = 1.18
@export var land_squash: float = 0.78
@export var squash_recover: float = 10.0

@export_group("Look")
@export var body_color: Color = Color(0.45, 0.92, 0.7)
## Size at which the pupils go pale (plan §7) and the HUD reads "Large".
@export var top_tier_size: float = 2.6
@export var pupil_color: Color = Color(0.05, 0.04, 0.08)
@export var blank_eye_color: Color = Color(0.87, 0.9, 0.87)
@export_range(0.0, 0.2, 0.005) var wobble_idle: float = 0.04
@export_range(0.0, 0.2, 0.005) var wobble_move: float = 0.05
@export var flash_decay: float = 3.0

@export_group("Nodes")
@export var body_mesh: MeshInstance3D
@export var left_pupil: MeshInstance3D
@export var right_pupil: MeshInstance3D
@export var eat_area: Area3D

var nutrition := 0.0
var size := 0.0
var eaten_count := 0

var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _eat_area: Area3D
var _base_color := Color(0.55, 0.9, 0.65)
var _target_size := 0.8
var _size_tween: Tween
var _visual_scale := Vector3.ONE
var _was_on_floor := true
var _flash := 0.0
var _pupil_mat: StandardMaterial3D
var _sweep_queued := false


func _ready() -> void:
	add_to_group("player")
	nutrition = start_nutrition
	size = base_size
	_target_size = base_size
	_base_color = body_color
	scale = Vector3.ONE * size

	_mesh = body_mesh if body_mesh != null else ($Body as MeshInstance3D)
	if left_pupil == null:
		left_pupil = get_node_or_null("Body/LeftEye/Pupil") as MeshInstance3D
	if right_pupil == null:
		right_pupil = get_node_or_null("Body/RightEye/Pupil") as MeshInstance3D
	_eat_area = eat_area if eat_area != null else ($EatArea as Area3D)

	# Plan §8: an icosphere wobbles evenly; a UV sphere pinches at the poles.
	_mesh.mesh = Icosphere.build(0.5, 3)
	_setup_materials()
	_update_eyes()
	_eat_area.area_entered.connect(_on_area_entered)
	_eat_area.body_entered.connect(_on_body_entered)
	size_changed.emit(size)


func _setup_materials() -> void:
	var existing_mat := _mesh.material_override as ShaderMaterial
	if existing_mat != null:
		_material = existing_mat.duplicate() as ShaderMaterial
		if _material.next_pass != null:
			_material.next_pass = _material.next_pass.duplicate()
	else:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/slime.gdshader")
		var outline := ShaderMaterial.new()
		outline.shader = preload("res://shaders/slime_outline.gdshader")
		outline.set_shader_parameter("outline_width", 0.03)
		_material.next_pass = outline
	_material.set_shader_parameter("base_color", _base_color)
	_material.set_shader_parameter("wobble_amplitude", wobble_idle)
	_mesh.material_override = _material

	_pupil_mat = ToonMaterial.flat(pupil_color)
	if left_pupil != null:
		left_pupil.material_override = _pupil_mat
	if right_pupil != null:
		right_pupil.material_override = _pupil_mat


## Plan §7: the eyes go blank at the top tier.
func _update_eyes() -> void:
	if _pupil_mat == null:
		return
	_pupil_mat.albedo_color = (
		pupil_color if size < top_tier_size else blank_eye_color
	)


func _physics_process(delta: float) -> void:
	var horizontal := Input.get_axis("move_left", "move_right")
	var forward := Input.get_axis("move_back", "move_forward")
	var dir := Vector3(horizontal, 0.0, -forward)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	var speed := _current_speed()
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = _current_jump()
		_squash(jump_stretch)

	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_squash(land_squash)
	_was_on_floor = is_on_floor()

	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), TURN_SPEED * delta)

	# Wobble harder while moving, and spring the squash back to rest.
	var move_ratio := clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.01), 0.0, 1.0)
	_material.set_shader_parameter("wobble_amplitude", wobble_idle + move_ratio * wobble_move)
	_visual_scale = _visual_scale.lerp(Vector3.ONE, clampf(squash_recover * delta, 0.0, 1.0))
	_mesh.scale = _visual_scale


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * flash_decay, 0.0)
		_material.set_shader_parameter("flash", _flash)


## Keep volume roughly constant: stretch Y, pinch XZ, and vice versa.
func _squash(vertical: float) -> void:
	var pinch := 1.0 / sqrt(vertical)
	_visual_scale = Vector3(pinch, vertical, pinch)


func _current_speed() -> float:
	return base_speed * pow(size, speed_scale_exponent)


func _current_jump() -> float:
	return base_jump * pow(size, jump_scale_exponent)


func add_nutrition(amount: float) -> void:
	nutrition = maxf(nutrition + amount, min_nutrition)
	_refresh_size()


func take_damage(amount: float) -> void:
	nutrition = maxf(nutrition - amount, min_nutrition)
	_refresh_size()
	_flash = HURT_FLASH_STRENGTH
	hurt.emit()


func get_base_color() -> Color:
	return _base_color


func apply_save_state(saved_nutrition: float, saved_eaten: int, saved_color: Color, saved_pos: Vector3) -> void:
	nutrition = maxf(saved_nutrition, min_nutrition)
	eaten_count = maxi(saved_eaten, 0)
	_base_color = saved_color
	if _material != null:
		_material.set_shader_parameter("base_color", _base_color)
	global_position = saved_pos
	velocity = Vector3.ZERO
	_target_size = clampf(
		base_size * pow(nutrition / start_nutrition, growth_exponent),
		min_size,
		max_size
	)
	size = _target_size
	if _size_tween and _size_tween.is_valid():
		_size_tween.kill()
	scale = Vector3.ONE * size
	_update_eyes()
	size_changed.emit(size)
	_queue_eat_sweep()


func _refresh_size() -> void:
	var next_size := clampf(
		base_size * pow(nutrition / start_nutrition, growth_exponent),
		min_size,
		max_size
	)
	if is_equal_approx(next_size, _target_size):
		return
	_target_size = next_size
	_apply_size()


func _apply_size() -> void:
	size = _target_size
	_update_eyes()
	if _size_tween and _size_tween.is_valid():
		_size_tween.kill()
	_size_tween = create_tween()
	_size_tween.tween_property(self, "scale", Vector3.ONE * size, growth_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	size_changed.emit(size)
	_queue_eat_sweep()


## `area_entered` fires once. If the slime grows past a prop it is already
## standing on, nothing re-fires, so re-check overlaps after every size change.
## Otherwise "grow to unlock new food" would not work while standing still.
func _queue_eat_sweep() -> void:
	if _sweep_queued or not is_inside_tree():
		return
	_sweep_queued = true
	_sweep_eat_overlaps.call_deferred()


func _sweep_eat_overlaps() -> void:
	_sweep_queued = false
	if _eat_area == null or not is_inside_tree():
		return
	for area in _eat_area.get_overlapping_areas():
		if area.has_method("try_eat") and area.try_eat(size):
			_eat(area)
			return
	for body in _eat_area.get_overlapping_bodies():
		if body.has_method("try_eat") and body.try_eat(size):
			_eat(body)
			return


func _on_area_entered(area: Area3D) -> void:
	if area.has_method("try_eat") and area.try_eat(size):
		_eat(area)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("try_eat") and body.try_eat(size):
		_eat(body)


func _eat(target: Node3D) -> void:
	if not target.has_method("absorb"):
		return
	var meal_nutrition := 0.0
	var raw_nutrition = target.get("nutrition")
	if raw_nutrition != null:
		meal_nutrition = float(raw_nutrition)
	var meal_color := _base_color
	var raw_color = target.get("color")
	if raw_color is Color:
		meal_color = raw_color

	target.absorb(self)
	eaten_count += 1
	add_nutrition(meal_nutrition)

	# The slime takes on a hint of everything it eats.
	_base_color = _base_color.lerp(meal_color, COLOR_SHIFT_RATE)
	_material.set_shader_parameter("base_color", _base_color)

	ate.emit(meal_nutrition, meal_color, target.global_position)
