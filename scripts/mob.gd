class_name Mob
extends CharacterBody3D

## Reusable mob with a tiny state machine: wander -> flee (when the slime is
## bigger) / chase + bite (when the slime is smaller).
##
## Plan note: the plan suggests NavigationAgent3D. The prototype map is flat and
## hand-placed, so steering avoids a navmesh bake at runtime; swap in
## NavigationAgent3D when the map gains real obstacles.

const KINDS := {
	"villager": {
		"size": 1.1,
		"nutrition": 30.0,
		"speed": 2.2,
		"flee_speed": 4.4,
		"flies": false,
		"color": Color(0.55, 0.36, 0.45),
		"attack_range": 1.6,
		"bite_damage": 9.0,
		"bite_cooldown": 1.1,
	},
	"bird": {
		"size": 0.35,
		"nutrition": 8.0,
		"speed": 3.0,
		"flee_speed": 6.5,
		"flies": true,
		"color": Color(0.25, 0.32, 0.55),
		"attack_range": 1.2,
		"bite_damage": 3.0,
		"bite_cooldown": 0.8,
	},
}

@export var kind := "villager"

var size := 1.0
var nutrition := 20.0
var color := Color.WHITE
var is_dead := false

var _speed := 2.0
var _flee_speed := 4.0
var _flies := false
var _attack_range := 1.6
var _bite_damage := 9.0
var _bite_cooldown := 1.0
var _bite_cd := 0.0
var _state := "wander"
var _wander_center := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _hover_phase := 0.0
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _mesh: MeshInstance3D


func _ready() -> void:
	_rng.randomize()
	_hover_phase = _rng.randf() * TAU
	var cfg: Dictionary = KINDS.get(kind, KINDS["villager"])
	size = float(cfg["size"])
	nutrition = float(cfg["nutrition"])
	color = cfg["color"]
	_speed = float(cfg["speed"])
	_flee_speed = float(cfg["flee_speed"])
	_flies = bool(cfg["flies"])
	_attack_range = float(cfg["attack_range"])
	_bite_damage = float(cfg["bite_damage"])
	_bite_cooldown = float(cfg["bite_cooldown"])
	_mesh = $Mesh
	_build_visuals()
	_build_collision()
	_wander_center = global_position
	_player = get_tree().get_first_node_in_group("player")
	_pick_wander_target()


func _build_visuals() -> void:
	var mat := ToonMaterial.make(color, size * 0.025)
	_mesh.material_override = mat
	if _flies:
		var body := SphereMesh.new()
		body.radius = size * 0.5
		body.height = size
		_mesh.mesh = body
		var wing_mat := ToonMaterial.make(color.lightened(0.12), 0.015)
		for side in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			var wing_mesh := BoxMesh.new()
			wing_mesh.size = Vector3(size * 0.9, 0.03, size * 0.35)
			wing.mesh = wing_mesh
			wing.material_override = wing_mat
			wing.position = Vector3(side * size * 0.65, 0.0, 0.0)
			_mesh.add_child(wing)
		_add_eyes(_mesh, size * 0.5)
	else:
		var body := CapsuleMesh.new()
		body.radius = size * 0.32
		body.height = size * 0.75
		_mesh.mesh = body
		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = size * 0.26
		head_mesh.height = size * 0.52
		head.mesh = head_mesh
		head.material_override = ToonMaterial.make(color.lightened(0.14), size * 0.02)
		head.position = Vector3(0, size * 0.62, 0)
		_mesh.add_child(head)
		_add_eyes(head, size * 0.26)


func _add_eyes(parent: Node3D, head_radius: float) -> void:
	var eye_mat := ToonMaterial.flat(Color(1, 1, 1))
	var pupil_mat := ToonMaterial.flat(Color(0.05, 0.04, 0.08))
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = head_radius * 0.28
		eye_mesh.height = head_radius * 0.56
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(head_radius * 0.42 * side, head_radius * 0.12, head_radius * 0.82)
		parent.add_child(eye)
		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = head_radius * 0.13
		pupil_mesh.height = head_radius * 0.26
		pupil.mesh = pupil_mesh
		pupil.material_override = pupil_mat
		pupil.position = Vector3(0, 0, head_radius * 0.22)
		eye.add_child(pupil)


func _build_collision() -> void:
	if _flies:
		var sphere := SphereShape3D.new()
		sphere.radius = size * 0.5
		$Collision.shape = sphere
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = size * 0.35
		capsule.height = maxf(size * 1.6, capsule.radius * 2.0)
		$Collision.shape = capsule


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_bite_cd = maxf(_bite_cd - delta, 0.0)

	var player_size := 0.0
	var dist := INF
	var to_player := Vector3.ZERO
	if is_instance_valid(_player):
		to_player = _player.global_position - global_position
		dist = to_player.length()
		var raw_size = _player.get("size")
		if raw_size != null:
			player_size = float(raw_size)

	if dist < 28.0 and player_size > 0.0:
		if player_size > size * 1.05:
			_state = "flee"
		elif player_size < size * 0.95:
			_state = "chase"
		else:
			_state = "wander"
	else:
		_state = "wander"

	var dir := Vector3.ZERO
	match _state:
		"flee":
			dir = -to_player
			dir.y = 0.0
			dir = dir.normalized()
			var boost := 1.0 + clampf((player_size - size) / maxf(size, 0.01), 0.0, 1.5) * 0.3
			_steer(dir, _flee_speed * boost, delta)
		"chase":
			dir = to_player
			dir.y = 0.0
			dir = dir.normalized()
			_steer(dir, _speed * 1.2, delta)
			if dist < _attack_range + size * 0.6 and _bite_cd <= 0.0:
				_bite()
		_:
			_wander_timer -= delta
			if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 0.8:
				_pick_wander_target()
			dir = _wander_target - global_position
			dir.y = 0.0
			dir = dir.normalized()
			_steer(dir, _speed, delta)


func _steer(dir: Vector3, speed: float, delta: float) -> void:
	var accel := 8.0 if _flies else 14.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	if _flies:
		var hover := 2.3
		if _state == "chase" and is_instance_valid(_player):
			hover = maxf(_player.global_position.y + 0.9, 0.7)
		hover += sin(Time.get_ticks_msec() * 0.002 + _hover_phase) * 0.25
		velocity.y = (hover - global_position.y) * 2.5
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 24.0 * delta
	move_and_slide()
	global_position.x = clampf(global_position.x, -28.0, 28.0)
	global_position.z = clampf(global_position.z, -28.0, 28.0)
	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)


func _pick_wander_target() -> void:
	_wander_timer = _rng.randf_range(1.5, 4.0)
	_wander_target = _wander_center + Vector3(
		_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0)
	)
	_wander_target.x = clampf(_wander_target.x, -28.0, 28.0)
	_wander_target.z = clampf(_wander_target.z, -28.0, 28.0)


func _bite() -> void:
	_bite_cd = _bite_cooldown
	if not is_instance_valid(_player):
		return
	if _player.has_method("take_damage"):
		_player.take_damage(_bite_damage)
		var away := global_position - _player.global_position
		away.y = 0.0
		velocity += away.normalized() * 2.5


## Eating contract shared with Edible, so the slime's Area3D can swallow mobs.
func try_eat(player_size: float) -> bool:
	return not is_dead and size <= player_size


func absorb(target: Node3D) -> void:
	if is_dead:
		return
	is_dead = true
	_state = "absorbed"
	collision_layer = 0
	collision_mask = 0
	$Collision.set_deferred("disabled", true)

	var mat := _mesh.material_override as ShaderMaterial
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target.global_position, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "rotation:y", rotation.y + 6.0, 0.35)
	if mat:
		tween.tween_method(
			func(value: float) -> void: mat.set_shader_parameter("dissolve", value),
			0.0, 1.0, 0.35
		)
	tween.chain().tween_callback(queue_free)
