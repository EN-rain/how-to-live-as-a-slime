class_name Mob
extends CharacterBody3D

## Reusable mob with a state machine: wander -> flee (when the slime is
## bigger) / chase + bite (when the slime is smaller).
##
## Uses `NavigationAgent3D` on the World's obstacle-carved `NavigationMesh` plus
## a zero-allocation reusable raycast feeler to pathfind around trees and rocks.

static var _shape_cache: Dictionary = {}

const DEFAULT_GROUND_SCENE: PackedScene = preload("res://scenes/mobs/villager.tscn")
const DEFAULT_FLY_SCENE: PackedScene = preload("res://scenes/mobs/bird.tscn")
const DETECTION_RANGE := 28.0
const FLEE_SIZE_RATIO := 1.05
const CHASE_SIZE_RATIO := 0.95
const MAP_BOUND := 27.5
const GRAVITY := 24.0
const FLY_ACCEL := 8.0
const GROUND_ACCEL := 14.0
const TURN_SPEED := 8.0
const BASE_HOVER_HEIGHT := 2.3
const ABSORB_DURATION := 0.35
const OBSTACLE_RAY_LENGTH := 2.2
const VISIBILITY_END := 85.0
const REPATH_INTERVAL := 0.25

## Which mob this is. Assign a .tres from resources/mobs/ in the Inspector.
@export var data: MobData

@export_group("Nodes")
@export var visual_root: Node3D
@export var collision_node: CollisionShape3D
@export var nav_agent: NavigationAgent3D

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
var _repath_timer := 0.0
var _hover_phase := 0.0
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _visual_root: Node3D
var _collision: CollisionShape3D
var _nav_agent: NavigationAgent3D
var _parts: Array[MeshInstance3D] = []
var _ray_query: PhysicsRayQueryParameters3D


func _ready() -> void:
	add_to_group("edible")
	_rng.randomize()
	_hover_phase = _rng.randf() * TAU
	# Stagger initial repath timers across mobs so path queries don't spike on the same frame.
	_repath_timer = _rng.randf_range(0.0, REPATH_INTERVAL)
	# Sensible fallback so a freshly placed Mob still runs unset.
	if data == null:
		data = MobData.new()
	size = data.size
	nutrition = data.nutrition
	color = data.color
	_speed = data.speed
	_flee_speed = data.flee_speed
	_flies = data.flies
	_attack_range = data.attack_range
	_bite_damage = data.bite_damage
	_bite_cooldown = data.bite_cooldown

	_visual_root = visual_root if visual_root != null else ($VisualRoot as Node3D)
	_collision = collision_node if collision_node != null else ($Collision as CollisionShape3D)
	_nav_agent = nav_agent if nav_agent != null else (get_node_or_null("NavigationAgent3D") as NavigationAgent3D)

	# Pre-allocate ray query once per mob to avoid per-frame allocations in _physics_process.
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = 1
	_ray_query.exclude = [get_rid()]

	_instantiate_visual_scene()
	_configure_collision()
	_wander_center = global_position
	_player = get_tree().get_first_node_in_group("player")
	_pick_wander_target()


static func _shape_for(mob: MobData) -> Shape3D:
	var key := String(mob.id)
	if _shape_cache.has(key):
		return _shape_cache[key]
	var shape: Shape3D
	if mob.flies:
		var sphere := SphereShape3D.new()
		sphere.radius = mob.size * 0.5
		shape = sphere
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = mob.size * 0.35
		capsule.height = maxf(mob.size * 1.6, capsule.radius * 2.0)
		shape = capsule
	_shape_cache[key] = shape
	return shape


func _instantiate_visual_scene() -> void:
	_parts.clear()
	if _visual_root == null:
		return
	for child in _visual_root.get_children():
		child.queue_free()

	var scene_to_spawn: PackedScene = data.visual_scene
	if scene_to_spawn == null:
		scene_to_spawn = DEFAULT_FLY_SCENE if _flies else DEFAULT_GROUND_SCENE
	if scene_to_spawn == null:
		return

	var instance := scene_to_spawn.instantiate()
	_visual_root.add_child(instance)
	_visual_root.scale = Vector3.ONE * size

	var mat := ToonMaterial.shared(color, size * 0.025)
	var shadow_mode := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if size >= 1.0
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_collect_mesh_parts(instance, mat, shadow_mode)


func _collect_mesh_parts(
		node: Node,
		mat: ShaderMaterial,
		shadow_mode: GeometryInstance3D.ShadowCastingSetting
	) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		mi.material_override = mat
		mi.visibility_range_end = VISIBILITY_END
		mi.cast_shadow = shadow_mode
		_parts.append(mi)
	for child in node.get_children():
		_collect_mesh_parts(child, mat, shadow_mode)


func _configure_collision() -> void:
	if _collision != null:
		_collision.shape = _shape_for(data)
	if _nav_agent != null:
		_nav_agent.radius = maxf(size * 0.45, 0.25)
		_nav_agent.max_speed = _flee_speed * 1.5


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_repath_timer = maxf(_repath_timer - delta, 0.0)

	var player_size := 0.0
	var dist_sq := INF
	var to_player := Vector3.ZERO
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(_player):
		to_player = _player.global_position - global_position
		dist_sq = to_player.length_squared()
		var raw_size = _player.get("size")
		if raw_size != null:
			player_size = float(raw_size)

	if dist_sq < DETECTION_RANGE * DETECTION_RANGE and player_size > 0.0:
		if player_size > size * FLEE_SIZE_RATIO:
			_state = "flee"
		elif player_size < size * CHASE_SIZE_RATIO:
			_state = "chase"
		else:
			_state = "wander"
	else:
		_state = "wander"

	var goal := _wander_target
	var move_speed := _speed
	match _state:
		"flee":
			var away := -to_player
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
			goal = global_position + away * 9.0
			goal.x = clampf(goal.x, -MAP_BOUND, MAP_BOUND)
			goal.z = clampf(goal.z, -MAP_BOUND, MAP_BOUND)
			var boost := 1.0 + clampf((player_size - size) / maxf(size, 0.01), 0.0, 1.5) * 0.3
			move_speed = _flee_speed * boost
		"chase":
			if is_instance_valid(_player):
				goal = _player.global_position
			move_speed = _speed * 1.2
			var bite_reach := _attack_range + size * 0.6
			if dist_sq < bite_reach * bite_reach and _bite_cd <= 0.0:
				_bite()
		_:
			_wander_timer -= delta
			if _wander_timer <= 0.0 or global_position.distance_squared_to(_wander_target) < 0.64:
				_pick_wander_target()
			goal = _wander_target
			move_speed = _speed

	var dir := _compute_navigation_direction(goal)
	_steer(dir, move_speed, delta)


## Queries `NavigationAgent3D` for the next waypoint around trees and rocks on
## the World's NavigationMesh, and blends with a zero-allocation physics feeler.
func _compute_navigation_direction(goal: Vector3) -> Vector3:
	var target_point := goal
	if not _flies and _nav_agent != null and is_inside_tree():
		if _repath_timer <= 0.0:
			_nav_agent.target_position = goal
			_repath_timer = REPATH_INTERVAL
		var nav_map := _nav_agent.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0 and not _nav_agent.is_navigation_finished():
			var next_pos := _nav_agent.get_next_path_position()
			if next_pos.distance_squared_to(global_position) > 0.01:
				target_point = next_pos

	var dir := target_point - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	dir = dir.normalized()

	# Zero-allocation raycast feeler for grounded mobs around static World obstacles (layer 1).
	if not _flies and _ray_query != null and is_inside_tree():
		var space := get_world_3d().direct_space_state
		if space != null:
			var from := global_position + Vector3(0.0, 0.5, 0.0)
			_ray_query.from = from
			_ray_query.to = from + dir * (OBSTACLE_RAY_LENGTH + size * 0.4)
			var hit := space.intersect_ray(_ray_query)
			if not hit.is_empty():
				var normal: Vector3 = hit["normal"]
				normal.y = 0.0
				var slide := (dir + normal * 1.45).normalized()
				if slide.length_squared() > 0.01:
					dir = slide
	return dir


func _steer(dir: Vector3, speed: float, delta: float) -> void:
	var accel := FLY_ACCEL if _flies else GROUND_ACCEL
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	if _flies:
		var hover := BASE_HOVER_HEIGHT
		if _state == "chase" and is_instance_valid(_player):
			hover = maxf(_player.global_position.y + 0.9, 0.7)
		hover += sin(Time.get_ticks_msec() * 0.002 + _hover_phase) * 0.25
		velocity.y = (hover - global_position.y) * 2.5
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	global_position.x = clampf(global_position.x, -MAP_BOUND, MAP_BOUND)
	global_position.z = clampf(global_position.z, -MAP_BOUND, MAP_BOUND)
	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), TURN_SPEED * delta)


func _pick_wander_target() -> void:
	_wander_timer = _rng.randf_range(1.5, 4.0)
	_wander_target = _wander_center + Vector3(
		_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0)
	)
	_wander_target.x = clampf(_wander_target.x, -MAP_BOUND, MAP_BOUND)
	_wander_target.z = clampf(_wander_target.z, -MAP_BOUND, MAP_BOUND)
	if _nav_agent != null and is_inside_tree():
		_nav_agent.target_position = _wander_target


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
	# Deferred: absorb() may run inside a physics signal callback.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if _collision != null:
		_collision.set_deferred("disabled", true)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target.global_position, ABSORB_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, ABSORB_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "rotation:y", rotation.y + 6.0, ABSORB_DURATION)
	tween.tween_method(_set_dissolve, 0.0, 1.0, ABSORB_DURATION)
	tween.chain().tween_callback(queue_free)


## Instance-level dissolve, so the material stays shared between mobs.
func _set_dissolve(value: float) -> void:
	for part in _parts:
		if is_instance_valid(part):
			part.set_instance_shader_parameter("dissolve", value)
