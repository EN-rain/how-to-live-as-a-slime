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
const WORLD_COLLISION_LAYER := 1
const CAMERA_WALL_MARGIN := 0.3
const CAMERA_MIN_DISTANCE := 0.9
const CAMERA_MIN_PITCH := 0.05
const CAMERA_MAX_PITCH := 1.2
const CAMERA_ZOOM_STEP := 0.1

## Deterministic edible clusters: resource, amount, centre and spread.
## Adding food = adding a .tres here (or a new line pointing at one).
const EDIBLE_GROUPS := [
	{"data": preload("res://resources/edibles/bug.tres"), "count": 12, "center": Vector3(0, 0, 6), "radius": 12.0},
	{"data": preload("res://resources/edibles/berry.tres"), "count": 10, "center": Vector3(-12, 0, -8), "radius": 12.0},
	{"data": preload("res://resources/edibles/crumb.tres"), "count": 10, "center": Vector3(12, 0, 0), "radius": 12.0},
	{"data": preload("res://resources/edibles/pebble.tres"), "count": 8, "center": Vector3(0, 0, -14), "radius": 10.0},
	{"data": preload("res://resources/edibles/fruit.tres"), "count": 10, "center": Vector3(-22, 0, 14), "radius": 12.0},
	{"data": preload("res://resources/edibles/critter.tres"), "count": 9, "center": Vector3(22, 0, -12), "radius": 12.0},
	{"data": preload("res://resources/edibles/chicken.tres"), "count": 8, "center": Vector3(4, 0, 26), "radius": 11.0},
	{"data": preload("res://resources/edibles/barrel.tres"), "count": 7, "center": Vector3(-26, 0, -22), "radius": 11.0},
	{"data": preload("res://resources/edibles/cart.tres"), "count": 4, "center": Vector3(26, 0, 24), "radius": 10.0},
	{"data": preload("res://resources/edibles/statue.tres"), "count": 4, "center": Vector3(0, 0, -30), "radius": 9.0},
	{"data": preload("res://resources/edibles/house.tres"), "count": 3, "center": Vector3(-30, 0, 28), "radius": 8.0},
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
## Third-person orbit: distance behind the slime at the smallest size.
@export var camera_base_distance: float = 3.3
## Extra orbit distance per unit of slime size, so big slimes stay framed.
@export var camera_size_distance: float = 1.7
## Camera elevation above the look target. ~20-25 degrees reads as third person.
@export_range(-5.0, 75.0, 1.0) var camera_pitch_deg: float = 22.0
@export_range(0.01, 1.0, 0.01) var camera_orbit_sensitivity: float = 0.22
## Look target height above the slime's origin, per unit of size.
@export var camera_look_height: float = 0.9
@export var camera_smooth: float = 8.0
@export_range(0.5, 1.0, 0.05) var camera_zoom_min: float = 0.65
@export_range(1.0, 3.0, 0.05) var camera_zoom_max: float = 1.8
@export var trauma_decay: float = 1.6

@export_group("Spawning")
@export var villager_count: int = 9
@export var bird_count: int = 10

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
var _camera_yaw := PI
var _camera_pitch := 0.0
var _camera_zoom := 1.0
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

	player.position = Vector3(0, _ground_height(0.0, 0.0) + 1.0, 0)
	_camera_pitch = deg_to_rad(camera_pitch_deg)
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

	# Third-person orbit: drag with any mouse button to look around, wheel to zoom.
	if event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		_camera_yaw -= event.relative.x * deg_to_rad(camera_orbit_sensitivity)
		_camera_pitch = clampf(
			_camera_pitch + event.relative.y * deg_to_rad(camera_orbit_sensitivity),
			CAMERA_MIN_PITCH,
			CAMERA_MAX_PITCH
		)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_zoom = maxf(camera_zoom_min, _camera_zoom - CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_zoom = minf(camera_zoom_max, _camera_zoom + CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()


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
		var centre: Vector3 = group["center"]
		var reach: float = group["radius"]
		for i in int(group["count"]):
			var spot := Vector3.ZERO
			# Resample until the meal is reachable: a prop buried in a tree
			# trunk or rock can never be eaten, which would block 100% clears.
			for attempt in 24:
				var angle := rng.randf() * TAU
				var radius := sqrt(rng.randf()) * reach
				spot = Vector3(centre.x + cos(angle) * radius, 0.0, centre.z + sin(angle) * radius)
				# Never spawn a free meal inside the player's starting eat radius.
				var flat := Vector2(spot.x, spot.z)
				if flat.length() < SAFE_SPAWN_RADIUS:
					var outward := flat.normalized() if flat.length() > 0.01 else Vector2.RIGHT
					spot.x = outward.x * SAFE_SPAWN_PUSH
					spot.z = outward.y * SAFE_SPAWN_PUSH
				if _is_spot_clear(spot.x, spot.z, 1.6):
					break
			# Sit the meal on the terrain rather than on the old y = 0 plane.
			spot.y = _ground_height(spot.x, spot.z) + data.size * 0.55
			var edible := edible_scene.instantiate() as Edible
			edible.data = data
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
		var spot := _mob_spawn_point(rng, 12.0, 44.0, 2.6)
		spot.y = _ground_height(spot.x, spot.z) + 1.2
		villager.position = spot
		parent.add_child(villager)
	for i in bird_count:
		var bird := mob_scene.instantiate() as Mob
		bird.data = BIRD_DATA
		var spot := _mob_spawn_point(rng, 6.0, 46.0, 2.6)
		spot.y = _ground_height(spot.x, spot.z) + rng.randf_range(1.5, 3.5)
		bird.position = spot
		parent.add_child(bird)


func _mob_spawn_point(rng: RandomNumberGenerator, inner: float, outer: float, clearance: float) -> Vector3:
	var spot := Vector3.ZERO
	for attempt in 24:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(inner, outer)
		spot = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _is_spot_clear(spot.x, spot.z, clearance):
			break
	return spot


## True when (x, z) is clear of tree and rock obstacles by `clearance` metres.
## World props are on StaticBody3D collision, so a spawn inside them is stuck.
func _is_spot_clear(x: float, z: float, clearance: float) -> bool:
	if world == null:
		return true
	for root in [world.trees_root, world.rocks_root]:
		if root == null:
			continue
		for prop in root.get_children():
			var p := prop as Node3D
			if p != null and Vector2(x - p.position.x, z - p.position.z).length() < clearance:
				return false
	return true


## Terrain elevation at (x, z); falls back to the old flat plane before World._ready.
func _ground_height(x: float, z: float) -> float:
	if world == null:
		return 0.0
	return world.terrain_height(x, z)


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
				var saved_pos: Vector3 = item.get("position", Vector3.ZERO)
				ed.position = Vector3(
					saved_pos.x,
					_ground_height(saved_pos.x, saved_pos.z) + ed.data.size * 0.55,
					saved_pos.z
				)
				ed_parent.add_child(ed)

	var mob_parent: Node = mobs_root if mobs_root != null else self
	var saved_mobs: Array = state.get("mobs", [])
	for item in saved_mobs:
		if item is Dictionary and item.has("data_path"):
			var path := String(item["data_path"])
			if ResourceLoader.exists(path):
				var mb := mob_scene.instantiate() as Mob
				mb.data = load(path) as MobData
				var saved_pos: Vector3 = item.get("position", Vector3.ZERO)
				var hover := 2.4 if mb.data.flies else 1.2
				mb.position = Vector3(saved_pos.x, _ground_height(saved_pos.x, saved_pos.z) + hover, saved_pos.z)
				mob_parent.add_child(mb)

	_elapsed_time = float(state.get("elapsed_time", 0.0))
	_remaining = saved_edibles.size() + saved_mobs.size()
	_win_recorded = (_remaining <= 0)

	var saved_player: Vector3 = state.get("position", Vector3(0.0, 1.0, 0.0))
	saved_player.y = _ground_height(saved_player.x, saved_player.z) + 1.0
	player.apply_save_state(
		float(state.get("nutrition", player.start_nutrition)),
		int(state.get("eaten_count", 0)),
		state.get("base_color", player.body_color),
		saved_player
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
	cam.far = 220.0
	add_child(cam)
	cam.current = true
	return cam


func _update_camera(delta: float) -> void:
	if not is_instance_valid(player) or camera == null:
		return
	var distance := (camera_base_distance + camera_size_distance * player.size) * _camera_zoom
	var target := player.global_position + Vector3(0, camera_look_height * player.size, 0)
	var pitch := clampf(_camera_pitch, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
	var offset := Vector3(
		sin(_camera_yaw) * cos(pitch),
		sin(pitch),
		cos(_camera_yaw) * cos(pitch)
	) * distance
	var desired := _clamp_camera_to_world(target, target + offset)
	if not _camera_ready:
		camera.global_position = desired
		_camera_ready = true
	else:
		# Pull in fast (never let a wall cover the player), ease out normally.
		var follow := camera_smooth * (2.0 if desired.distance_to(target) < camera.global_position.distance_to(target) else 1.0)
		camera.global_position = camera.global_position.lerp(desired, clampf(follow * delta, 0.0, 1.0))
	camera.look_at(target, Vector3.UP)
	if _trauma > 0.0:
		_shake_time += delta * SHAKE_FREQUENCY
		var shake := _trauma * _trauma
		# Smooth pseudo-random via sin, never rand each frame (that buzzes).
		camera.global_position += Vector3(
			sin(_shake_time * 1.7), sin(_shake_time * 2.3), sin(_shake_time * 1.3)
		) * shake * 0.45
		camera.rotate_object_local(Vector3(0, 0, 1), sin(_shake_time * 1.1) * shake * 0.03)


## Keeps the camera out of walls, trees, and rocks by raycasting from the
## slime's look target outward and pulling the camera in front of the hit.
func _clamp_camera_to_world(target: Vector3, desired: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired
	var query := PhysicsRayQueryParameters3D.create(target, desired, WORLD_COLLISION_LAYER)
	if is_instance_valid(player):
		query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return desired
	var pos: Vector3 = hit["position"] + (target - desired).normalized() * CAMERA_WALL_MARGIN
	if pos.distance_to(target) < CAMERA_MIN_DISTANCE:
		pos = target + (desired - target).normalized() * CAMERA_MIN_DISTANCE
	return pos


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
