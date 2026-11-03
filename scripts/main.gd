extends Node3D

## Main game coordinator: spawns edibles & mobs into the World scene, drives the
## follow camera & screen shake, pools particle bursts, and connects HUD, Menus, Save/Load, and Win state.

const EDIBLE_SEED := 20261103
const MOB_SEED := 424242
const SAFE_SPAWN_RADIUS := 5.0
const SAFE_SPAWN_PUSH := 5.5
const SHAKE_FREQUENCY := 32.0
const HURT_TRAUMA := 0.4
const BURST_POOL_INITIAL_SIZE := 6

## Deterministic edible clusters: resource, amount, centre and spread.
## Adding food = adding a .tres here (or a new line pointing at one).
const EDIBLE_GROUPS := [
	{"data": preload("res://resources/edibles/bug.tres"), "count": 10, "center": Vector3(0, 0, 4), "radius": 8.0},
	{"data": preload("res://resources/edibles/berry.tres"), "count": 8, "center": Vector3(-6, 0, -4), "radius": 7.0},
	{"data": preload("res://resources/edibles/crumb.tres"), "count": 8, "center": Vector3(7, 0, 0), "radius": 7.0},
	{"data": preload("res://resources/edibles/pebble.tres"), "count": 6, "center": Vector3(0, 0, -8), "radius": 6.0},
	{"data": preload("res://resources/edibles/fruit.tres"), "count": 8, "center": Vector3(-14, 0, 8), "radius": 8.0},
	{"data": preload("res://resources/edibles/critter.tres"), "count": 7, "center": Vector3(14, 0, -6), "radius": 8.0},
	{"data": preload("res://resources/edibles/chicken.tres"), "count": 6, "center": Vector3(2, 0, 16), "radius": 7.0},
	{"data": preload("res://resources/edibles/barrel.tres"), "count": 5, "center": Vector3(-16, 0, -14), "radius": 6.0},
	{"data": preload("res://resources/edibles/cart.tres"), "count": 3, "center": Vector3(16, 0, 14), "radius": 6.0},
	{"data": preload("res://resources/edibles/statue.tres"), "count": 3, "center": Vector3(0, 0, -18), "radius": 5.0},
	{"data": preload("res://resources/edibles/house.tres"), "count": 2, "center": Vector3(-18, 0, 18), "radius": 4.0},
]

const VILLAGER_DATA := preload("res://resources/mobs/villager.tres")
const BIRD_DATA := preload("res://resources/mobs/bird.tres")

static var _burst_mat_cache: Dictionary = {}

@export_group("Scenes & Audio")
@export var edible_scene: PackedScene = preload("res://scenes/edible.tscn")
@export var mob_scene: PackedScene = preload("res://scenes/mob.tscn")
@export var eat_burst_scene: PackedScene = preload("res://scenes/eat_burst.tscn")
@export var eat_sound_stream: AudioStream = preload("res://assets/sounds/pop.wav")

@export_group("Tiers")
## HUD tier boundaries. The top one lives on Slime (`top_tier_size`) because
## the eye colour depends on it too.
@export var tier_small: float = 1.05
@export var tier_medium: float = 1.7

@export_group("Camera & Shake")
@export var camera_base_distance: float = 3.4
@export var camera_size_distance: float = 4.6
@export var camera_height_ratio: float = 0.85
@export var camera_look_height: float = 0.9
@export var camera_smooth: float = 5.0
@export var trauma_decay: float = 1.6

@export_group("Spawning")
@export var villager_count: int = 6
@export var bird_count: int = 7

@export_group("Nodes")
@export var world: GameWorld
@export var player: Slime
@export var camera: Camera3D
@export var edibles_root: Node3D
@export var mobs_root: Node3D
@export var hud_label: Label
@export var game_menus: GameMenus
@export var eat_sound: AudioStreamPlayer

var _trauma := 0.0
var _shake_time := 0.0
var _camera_ready := false
var _remaining := 0
var _total_spawned := 0
var _elapsed_time := 0.0
var _win_recorded := false
var _burst_pool: Array[GPUParticles3D] = []


func _ready() -> void:
	randomize()
	if world == null:
		world = get_node_or_null("World") as GameWorld
	if player == null:
		player = get_node_or_null("Player") as Slime
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
		if camera == null:
			camera = _create_fallback_camera()
	if edibles_root == null:
		edibles_root = get_node_or_null("Edibles") as Node3D
	if mobs_root == null:
		mobs_root = get_node_or_null("Mobs") as Node3D
	if hud_label == null:
		hud_label = get_node_or_null("HUD/Label") as Label
	if game_menus == null:
		game_menus = get_node_or_null("GameMenus") as GameMenus
		if game_menus == null:
			game_menus = get_node_or_null("HUD/GameMenus") as GameMenus
	if eat_sound == null:
		eat_sound = get_node_or_null("EatSound") as AudioStreamPlayer

	player.position = Vector3(0, 1.0, 0)
	_prewarm_burst_pool()
	_spawn_edibles()
	_spawn_mobs()
	_total_spawned = get_tree().get_nodes_in_group("edible").size()
	_remaining = _total_spawned

	player.ate.connect(_on_player_ate)
	player.size_changed.connect(_on_size_changed)
	player.hurt.connect(func() -> void: _add_trauma(HURT_TRAUMA))

	if eat_sound != null and eat_sound_stream != null:
		eat_sound.stream = eat_sound_stream

	_wire_menus()
	_apply_saved_settings()
	_update_hud()


func _process(delta: float) -> void:
	if _remaining > 0:
		_elapsed_time += delta
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("quick_save") and event.is_action_pressed("quick_save"):
		save_game()
		get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("quick_load") and event.is_action_pressed("quick_load"):
		load_game()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart"):
		restart_game()


func _wire_menus() -> void:
	if game_menus == null:
		return
	game_menus.save_requested.connect(save_game)
	game_menus.load_requested.connect(load_game)
	game_menus.restart_requested.connect(restart_game)
	game_menus.delete_save_requested.connect(delete_saved_game)
	game_menus.settings_changed.connect(_on_settings_changed)


func _apply_saved_settings() -> void:
	var settings := SaveManager.load_settings()
	var vol := float(settings.get("volume_db", -6.0))
	var ssao := bool(settings.get("ssao_enabled", false))
	var sdfgi := bool(settings.get("sdfgi_enabled", false))
	if eat_sound != null:
		eat_sound.volume_db = vol
	if world != null:
		world.set_ssao(ssao)
		world.set_sdfgi(sdfgi)
	if game_menus != null:
		game_menus.sync_settings_controls(vol, ssao, sdfgi)


func _on_settings_changed(volume_db: float, ssao: bool, sdfgi: bool) -> void:
	if eat_sound != null:
		eat_sound.volume_db = volume_db
	if world != null:
		world.set_ssao(ssao)
		world.set_sdfgi(sdfgi)
	SaveManager.save_settings(volume_db, ssao, sdfgi)


# --- Spawning ---------------------------------------------------------------

func _spawn_edibles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = EDIBLE_SEED
	var parent: Node = edibles_root if edibles_root != null else self
	for group in EDIBLE_GROUPS:
		var data: EdibleData = group["data"]
		var y := data.size * 0.55
		for i in int(group["count"]):
			var angle := rng.randf() * TAU
			var radius := sqrt(rng.randf()) * float(group["radius"])
			var centre: Vector3 = group["center"]
			var edible := edible_scene.instantiate() as Edible
			edible.data = data
			var spot := Vector3(centre.x + cos(angle) * radius, y, centre.z + sin(angle) * radius)
			# Never spawn a free meal inside the player's starting eat radius.
			var flat := Vector2(spot.x, spot.z)
			if flat.length() < SAFE_SPAWN_RADIUS:
				var outward := flat.normalized() if flat.length() > 0.01 else Vector2.RIGHT
				spot.x = outward.x * SAFE_SPAWN_PUSH
				spot.z = outward.y * SAFE_SPAWN_PUSH
			# Position before add_child: _ready() must not run at the origin.
			edible.position = spot
			parent.add_child(edible)


func _spawn_mobs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = MOB_SEED
	var parent: Node = mobs_root if mobs_root != null else self
	for i in villager_count:
		var villager := mob_scene.instantiate() as Mob
		villager.data = VILLAGER_DATA
		var angle := TAU * float(i) / float(maxi(villager_count, 1)) + rng.randf_range(-0.25, 0.25)
		var radius := rng.randf_range(11.0, 22.0)
		villager.position = Vector3(cos(angle) * radius, 1.2, sin(angle) * radius)
		parent.add_child(villager)
	for i in bird_count:
		var bird := mob_scene.instantiate() as Mob
		bird.data = BIRD_DATA
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(5.0, 25.0)
		bird.position = Vector3(cos(angle) * radius, rng.randf_range(1.5, 3.5), sin(angle) * radius)
		parent.add_child(bird)


# --- Save & Load ------------------------------------------------------------

func save_game() -> bool:
	if not is_instance_valid(player):
		return false
	var edibles_state: Array[Dictionary] = []
	var mobs_state: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("edible"):
		if not is_instance_valid(node):
			continue
		if node is Edible:
			var ed := node as Edible
			if not ed._being_eaten and ed.data != null and not ed.data.resource_path.is_empty():
				edibles_state.append({
					"data_path": ed.data.resource_path,
					"position": ed.global_position,
				})
		elif node is Mob:
			var mb := node as Mob
			if not mb.is_dead and mb.data != null and not mb.data.resource_path.is_empty():
				mobs_state.append({
					"data_path": mb.data.resource_path,
					"position": mb.global_position,
				})
	var ok := SaveManager.save_run(player, edibles_state, mobs_state, _elapsed_time)
	if game_menus != null:
		game_menus.refresh_save_buttons()
		game_menus.show_toast("Progress Saved" if ok else "Save Failed")
	return ok


func load_game() -> bool:
	var state := SaveManager.load_run()
	if state.is_empty() or not is_instance_valid(player):
		if game_menus != null:
			game_menus.show_toast("No Saved Run Found")
		return false

	# Clear current edibles and mobs.
	for node in get_tree().get_nodes_in_group("edible"):
		if is_instance_valid(node):
			node.remove_from_group("edible")
			node.queue_free()

	var ed_parent: Node = edibles_root if edibles_root != null else self
	var saved_edibles: Array = state.get("edibles", [])
	for item in saved_edibles:
		if item is Dictionary and item.has("data_path"):
			var path := String(item["data_path"])
			if ResourceLoader.exists(path):
				var ed := edible_scene.instantiate() as Edible
				ed.data = load(path) as EdibleData
				ed.position = item.get("position", Vector3.ZERO)
				ed_parent.add_child(ed)

	var mob_parent: Node = mobs_root if mobs_root != null else self
	var saved_mobs: Array = state.get("mobs", [])
	for item in saved_mobs:
		if item is Dictionary and item.has("data_path"):
			var path := String(item["data_path"])
			if ResourceLoader.exists(path):
				var mb := mob_scene.instantiate() as Mob
				mb.data = load(path) as MobData
				mb.position = item.get("position", Vector3.ZERO)
				mob_parent.add_child(mb)

	_elapsed_time = float(state.get("elapsed_time", 0.0))
	_remaining = saved_edibles.size() + saved_mobs.size()
	_win_recorded = (_remaining <= 0)

	player.apply_save_state(
		float(state.get("nutrition", player.start_nutrition)),
		int(state.get("eaten_count", 0)),
		state.get("base_color", player.body_color),
		state.get("position", Vector3(0.0, 1.0, 0.0))
	)
	_camera_ready = false
	_update_hud()
	if game_menus != null:
		game_menus.show_toast("Saved Run Loaded")
	return true


func delete_saved_game() -> void:
	SaveManager.delete_save()
	if game_menus != null:
		game_menus.refresh_save_buttons()
		game_menus.show_toast("Saved Data Cleared")


func restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# --- Camera, Object Pool & Juice --------------------------------------------

func _create_fallback_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.1
	cam.far = 160.0
	add_child(cam)
	cam.current = true
	return cam


func _update_camera(delta: float) -> void:
	if not is_instance_valid(player) or camera == null:
		return
	var distance := camera_base_distance + camera_size_distance * player.size
	var target := player.global_position + Vector3(0, camera_look_height * player.size, 0)
	var desired := player.global_position + Vector3(0, distance * camera_height_ratio, distance)
	if not _camera_ready:
		camera.global_position = desired
		_camera_ready = true
	else:
		camera.global_position = camera.global_position.lerp(desired, clampf(camera_smooth * delta, 0.0, 1.0))
	camera.look_at(target, Vector3.UP)
	if _trauma > 0.0:
		_shake_time += delta * SHAKE_FREQUENCY
		var shake := _trauma * _trauma
		# Smooth pseudo-random via sin, never rand each frame (that buzzes).
		camera.global_position += Vector3(
			sin(_shake_time * 1.7), sin(_shake_time * 2.3), sin(_shake_time * 1.3)
		) * shake * 0.45
		camera.rotate_object_local(Vector3(0, 0, 1), sin(_shake_time * 1.1) * shake * 0.03)


func _add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _on_player_ate(meal_nutrition: float, meal_color: Color, at: Vector3) -> void:
	_remaining = maxi(_remaining - 1, 0)
	_add_trauma(clampf(0.1 + meal_nutrition / 140.0, 0.1, 0.5))
	_burst(at, meal_color, 10 + int(meal_nutrition * 0.4))
	if eat_sound != null and eat_sound.stream != null:
		eat_sound.pitch_scale = randf_range(0.85, 1.15)
		eat_sound.play()
	_update_hud()


func _on_size_changed(_new_size: float) -> void:
	_update_hud()


## Pre-warms a fixed pool of GPUParticles3D nodes so bites reuse existing nodes
## instead of calling instantiate()/queue_free() in hot gameplay loops.
func _prewarm_burst_pool() -> void:
	if eat_burst_scene == null:
		return
	for _i in BURST_POOL_INITIAL_SIZE:
		var p := _create_pooled_burst()
		if p != null:
			_burst_pool.append(p)


func _create_pooled_burst() -> GPUParticles3D:
	if eat_burst_scene == null:
		return null
	var p := eat_burst_scene.instantiate() as GPUParticles3D
	if p == null:
		return null
	p.visible = false
	p.emitting = false
	add_child(p)
	p.finished.connect(func() -> void:
		p.emitting = false
		p.visible = false
		if not _burst_pool.has(p):
			_burst_pool.append(p)
	)
	return p


static func _burst_material_for(color: Color, template: ParticleProcessMaterial) -> ParticleProcessMaterial:
	var key := color.to_html()
	if _burst_mat_cache.has(key):
		return _burst_mat_cache[key]
	var mat := (template.duplicate() as ParticleProcessMaterial) if template != null else ParticleProcessMaterial.new()
	mat.color = color
	_burst_mat_cache[key] = mat
	return mat


func _burst(at: Vector3, color: Color, count: int) -> void:
	var particles: GPUParticles3D = _burst_pool.pop_back() if not _burst_pool.is_empty() else _create_pooled_burst()
	if particles == null:
		return
	particles.amount = clampi(count, 6, 48)
	particles.process_material = _burst_material_for(
		color,
		particles.process_material as ParticleProcessMaterial
	)
	particles.global_position = at
	particles.visible = true
	particles.restart()
	particles.emitting = true


# --- HUD & Win State --------------------------------------------------------

func _update_hud() -> void:
	var tier := "Tiny"
	if player.size > player.top_tier_size:
		tier = "Large"
	elif player.size > tier_medium:
		tier = "Medium"
	elif player.size > tier_small:
		tier = "Small"
	if hud_label != null:
		hud_label.text = "Size %.2f  ·  %s\nEaten %d" % [player.size, tier, player.eaten_count]
		if _remaining <= 0:
			hud_label.text += "\nNothing left to eat."

	if game_menus != null:
		game_menus.update_progression(
			player.size,
			tier_small,
			tier_medium,
			player.top_tier_size,
			_remaining,
			_total_spawned
		)
		if _remaining <= 0 and not _win_recorded:
			_win_recorded = true
			var stats := SaveManager.record_world_eaten(_elapsed_time, player.eaten_count)
			game_menus.show_win_screen(
				player.size,
				player.eaten_count,
				_elapsed_time,
				float(stats.get("best_time", _elapsed_time)),
				int(stats.get("worlds_eaten", 1))
			)
