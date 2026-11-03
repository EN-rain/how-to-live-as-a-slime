class_name Slime
extends CharacterBody3D

## The player. Movement, squash & stretch, growth, and the eating trigger.
##
## Growth curve: size = 0.8 * (nutrition / START_NUTRITION) ^ 0.4, so early
## bites are visibly chunky and late tiers need the bigger meals. Speed and jump
## scale with size so a bigger slime still crosses the map at a similar pace.

signal ate(nutrition: float, meal_color: Color, world_position: Vector3)
signal size_changed(new_size: float)
signal hurt

const BASE_SPEED := 5.2
const BASE_JUMP := 7.0
const GRAVITY := 24.0
const START_NUTRITION := 27.0
const MIN_SIZE := 0.55
const MAX_SIZE := 4.0

var nutrition := START_NUTRITION
var size := 0.8
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


func _ready() -> void:
	add_to_group("player")
	scale = Vector3.ONE * size
	_mesh = $Body
	_build_material()
	_add_eyes()
	_eat_area = $EatArea
	_eat_area.area_entered.connect(_on_area_entered)
	_eat_area.body_entered.connect(_on_body_entered)
	size_changed.emit(size)


func _build_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/slime.gdshader")
	_material.set_shader_parameter("base_color", _base_color)
	_material.set_shader_parameter("wobble_amplitude", 0.045)
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://shaders/outline.gdshader")
	outline.set_shader_parameter("outline_width", 0.03)
	_material.next_pass = outline
	_mesh.material_override = _material


func _add_eyes() -> void:
	var eye_mat := ToonMaterial.flat(Color(1, 1, 1))
	var pupil_mat := ToonMaterial.flat(Color(0.05, 0.04, 0.08))
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.1
		eye_mesh.height = 0.2
		eye_mesh.radial_segments = 12
		eye_mesh.rings = 6
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(0.17 * side, 0.1, 0.42)
		_mesh.add_child(eye)
		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.05
		pupil_mesh.height = 0.1
		pupil_mesh.radial_segments = 10
		pupil_mesh.rings = 5
		pupil.mesh = pupil_mesh
		pupil.material_override = pupil_mat
		pupil.position = Vector3(0.0, 0.0, 0.06)
		eye.add_child(pupil)


func _physics_process(delta: float) -> void:
	var horizontal := Input.get_axis("move_left", "move_right")
	var forward := Input.get_axis("move_back", "move_forward")
	var dir := Vector3(horizontal, 0.0, -forward)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	var speed := _current_speed()
	var accel := 30.0 if is_on_floor() else 12.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = _current_jump()
		_squash(1.18)

	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_squash(0.78)
	_was_on_floor = is_on_floor()

	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 12.0 * delta)

	# Wobble harder while moving, and spring the squash back to rest.
	var move_ratio := clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.01), 0.0, 1.0)
	_material.set_shader_parameter("wobble_amplitude", 0.04 + move_ratio * 0.05)
	_visual_scale = _visual_scale.lerp(Vector3.ONE, clampf(10.0 * delta, 0.0, 1.0))
	_mesh.scale = _visual_scale


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		_material.set_shader_parameter("flash", _flash)


## Keep volume roughly constant: stretch Y, pinch XZ, and vice versa.
func _squash(vertical: float) -> void:
	var pinch := 1.0 / sqrt(vertical)
	_visual_scale = Vector3(pinch, vertical, pinch)


func _current_speed() -> float:
	return BASE_SPEED * pow(size, 0.55)


func _current_jump() -> float:
	return BASE_JUMP * pow(size, 0.5)


func add_nutrition(amount: float) -> void:
	nutrition = maxf(nutrition + amount, 6.0)
	_refresh_size()


func take_damage(amount: float) -> void:
	nutrition = maxf(nutrition - amount, 6.0)
	_refresh_size()
	_flash = 0.75
	hurt.emit()


func _refresh_size() -> void:
	var next_size := clampf(0.8 * pow(nutrition / START_NUTRITION, 0.4), MIN_SIZE, MAX_SIZE)
	if is_equal_approx(next_size, _target_size):
		return
	_target_size = next_size
	_apply_size()


func _apply_size() -> void:
	size = _target_size
	if _size_tween and _size_tween.is_valid():
		_size_tween.kill()
	_size_tween = create_tween()
	_size_tween.tween_property(self, "scale", Vector3.ONE * size, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	size_changed.emit(size)


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
	_base_color = _base_color.lerp(meal_color, 0.06)
	_material.set_shader_parameter("base_color", _base_color)

	ate.emit(meal_nutrition, meal_color, target.global_position)
