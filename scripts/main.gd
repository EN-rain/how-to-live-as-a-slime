extends Node3D

## World builder + camera + juice for the prototype. Everything is created here
## at runtime so the .tscn files stay tiny and editable.

const LightingPreset := preload("res://scripts/lighting_preset.gd")
const EdibleScene: PackedScene = preload("res://scenes/edible.tscn")
const MobScene: PackedScene = preload("res://scenes/mob.tscn")

const WORLD_SIZE := 60.0

## HUD tier boundaries. The top one lives on Slime (`top_tier_size`) because
## the eye colour depends on it too; these two only drive the label.
const TIER_SMALL := 1.05
const TIER_MEDIUM := 1.7

## SDFGI is the single most expensive environment setting on integrated GPUs.
## The prototype budget is 60 fps on an Intel Iris Xe, so it stays off; the sky
## ambient + toon bands carry the fill light. Flip to true on a discrete GPU.
const SDFGI_ENABLED := false
## SSAO is a full-screen pass and cost ~55 fps on the Iris Xe. Off by default;
## turn it on for hero shots on a discrete GPU.
const SSAO_ENABLED := false

## Deterministic edible clusters: kind, amount, centre and spread on the ground.
const EDIBLE_GROUPS := [
	{"kind": "bug", "count": 10, "center": Vector3(0, 0, 4), "radius": 8.0},
	{"kind": "berry", "count": 8, "center": Vector3(-6, 0, -4), "radius": 7.0},
	{"kind": "crumb", "count": 8, "center": Vector3(7, 0, 0), "radius": 7.0},
	{"kind": "pebble", "count": 6, "center": Vector3(0, 0, -8), "radius": 6.0},
	{"kind": "fruit", "count": 8, "center": Vector3(-14, 0, 8), "radius": 8.0},
	{"kind": "critter", "count": 7, "center": Vector3(14, 0, -6), "radius": 8.0},
	{"kind": "chicken", "count": 6, "center": Vector3(2, 0, 16), "radius": 7.0},
	{"kind": "barrel", "count": 5, "center": Vector3(-16, 0, -14), "radius": 6.0},
	{"kind": "cart", "count": 3, "center": Vector3(16, 0, 14), "radius": 6.0},
	{"kind": "statue", "count": 3, "center": Vector3(0, 0, -18), "radius": 5.0},
	{"kind": "house", "count": 2, "center": Vector3(-18, 0, 18), "radius": 4.0},
]

const TREE_SPOTS := [
	Vector3(-22, 0, -6), Vector3(-19, 0, 2), Vector3(-24, 0, 12),
	Vector3(21, 0, -18), Vector3(24, 0, -10), Vector3(18, 0, 6),
	Vector3(-10, 0, 22), Vector3(4, 0, 24), Vector3(14, 0, 20),
	Vector3(-2, 0, -24), Vector3(8, 0, -22), Vector3(-20, 0, -20),
]

const ROCK_SPOTS := [
	Vector3(-8, 0, 12), Vector3(11, 0, 6), Vector3(-15, 0, -2),
	Vector3(6, 0, -12), Vector3(22, 0, 2), Vector3(-4, 0, 18),
	Vector3(-24, 0, 4), Vector3(16, 0, -24),
]

@onready var player := $Player as Slime
@onready var hud_label := $HUD/Label as Label
@onready var eat_sound := $EatSound as AudioStreamPlayer

var camera: Camera3D
var _trauma := 0.0
var _shake_time := 0.0
var _camera_ready := false
var _remaining := 0


func _ready() -> void:
	randomize()
	_setup_input()
	_build_environment()
	_build_ground()
	_build_walls()
	_build_decor()
	_build_camera()
	player.position = Vector3(0, 1.0, 0)
	_spawn_edibles()
	_spawn_mobs()
	# Edibles and mobs both register in the "edible" group (plan §7: quiet ending
	# when there is nothing left to eat).
	_remaining = get_tree().get_nodes_in_group("edible").size()
	player.ate.connect(_on_player_ate)
	player.size_changed.connect(_on_size_changed)
	player.hurt.connect(func() -> void: _add_trauma(0.4))
	if ResourceLoader.exists("res://assets/sounds/pop.wav"):
		eat_sound.stream = load("res://assets/sounds/pop.wav")
		eat_sound.volume_db = -6.0
	_update_hud()


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - 1.6 * delta, 0.0)
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


# --- Input ------------------------------------------------------------------

func _setup_input() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("restart", [KEY_R])


func _add_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


# --- World ------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	LightingPreset.apply_sky(env)
	LightingPreset.apply_tonemap(env, {"exposure": 1.0, "saturation": 1.1})
	if SSAO_ENABLED:
		LightingPreset.apply_ambient_occlusion(env, {"radius": 1.0, "intensity": 1.4, "ssil": false})
	if SDFGI_ENABLED:
		LightingPreset.apply_sdfgi(env, {"min_cell_size": 0.5})
	LightingPreset.apply_fog(env, {
		"depth_begin": 26.0, "depth_end": 80.0, "density": 0.55, "sky_affect": 0.0,
	})
	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	add_child(sun)
	LightingPreset.apply_sun(sun, {
		"elevation_deg": 32.0, "azimuth_deg": -50.0, "energy": 1.6,
	})
	# Two cascades over a 55 m map: same look as four cascades at a fraction of
	# the shadow cost (see the godot-render-performance method: lower the
	# sub-setting, keep the look).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.04


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(WORLD_SIZE, 1.0, WORLD_SIZE)
	mesh.mesh = plane
	mesh.material_override = ToonMaterial.make(Color(0.45, 0.62, 0.32), 0.02, Color(0.09, 0.07, 0.12), false)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = plane.size
	collision.shape = shape
	body.add_child(mesh)
	body.add_child(collision)
	body.position = Vector3(0, -0.5, 0)
	add_child(body)


func _build_walls() -> void:
	var half := WORLD_SIZE * 0.5
	var specs := [
		{"pos": Vector3(0, 4, -half), "size": Vector3(WORLD_SIZE, 8, 1)},
		{"pos": Vector3(0, 4, half), "size": Vector3(WORLD_SIZE, 8, 1)},
		{"pos": Vector3(-half, 4, 0), "size": Vector3(1, 8, WORLD_SIZE)},
		{"pos": Vector3(half, 4, 0), "size": Vector3(1, 8, WORLD_SIZE)},
	]
	for spec in specs:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec["size"]
		collision.shape = shape
		body.add_child(collision)
		body.position = spec["pos"]
		add_child(body)


func _build_decor() -> void:
	# One material per colour, shared by every tree/rock instance.
	var trunk_mat := ToonMaterial.shared(Color(0.42, 0.29, 0.2), 0.02)
	var leaf_mats: Array[ShaderMaterial] = [
		ToonMaterial.shared(Color(0.32, 0.55, 0.3), 0.02),
		ToonMaterial.shared(Color(0.32, 0.55, 0.3).lightened(0.08), 0.02),
	]
	for spot in TREE_SPOTS:
		_add_tree(spot, trunk_mat, leaf_mats)
	var rock_mat := ToonMaterial.shared(Color(0.5, 0.52, 0.55), 0.02)
	for spot in ROCK_SPOTS:
		_add_rock(spot, rock_mat)


func _add_tree(at: Vector3, trunk_mat: ShaderMaterial, leaf_mats: Array) -> void:
	var tree := Node3D.new()
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.32
	trunk_mesh.height = 2.4
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_mat
	trunk.position.y = 1.2
	tree.add_child(trunk)
	for i in 2:
		var leaves := MeshInstance3D.new()
		var leaves_mesh := SphereMesh.new()
		leaves_mesh.radius = 1.5 - i * 0.35
		leaves_mesh.height = (1.5 - i * 0.35) * 2.0
		leaves.mesh = leaves_mesh
		leaves.material_override = leaf_mats[i]
		leaves.position.y = 2.6 + i * 1.1
		tree.add_child(leaves)
	tree.position = at
	add_child(tree)


func _add_rock(at: Vector3, rock_mat: ShaderMaterial) -> void:
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.7
	mesh.height = 1.4
	rock.mesh = mesh
	rock.material_override = rock_mat
	rock.position = at + Vector3(0, 0.45, 0)
	rock.scale = Vector3(1.2, 0.7, 1.0)
	add_child(rock)


# --- Spawning ---------------------------------------------------------------

func _spawn_edibles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261103
	for group in EDIBLE_GROUPS:
		var cfg: Dictionary = Edible.KINDS[group["kind"]]
		var y := float(cfg["size"]) * 0.55
		for i in int(group["count"]):
			var angle := rng.randf() * TAU
			var radius := sqrt(rng.randf()) * float(group["radius"])
			var centre: Vector3 = group["center"]
			var edible := EdibleScene.instantiate() as Edible
			edible.kind = group["kind"]
			var spot := Vector3(centre.x + cos(angle) * radius, y, centre.z + sin(angle) * radius)
			# Never spawn a free meal inside the player's starting eat radius.
			var flat := Vector2(spot.x, spot.z)
			if flat.length() < 5.0:
				var outward := flat.normalized() if flat.length() > 0.01 else Vector2.RIGHT
				spot.x = outward.x * 5.5
				spot.z = outward.y * 5.5
			# Position before add_child: _ready() must not run at the origin.
			edible.position = spot
			add_child(edible)


func _spawn_mobs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 6:
		var villager := MobScene.instantiate() as Mob
		villager.kind = "villager"
		var angle := TAU * float(i) / 6.0 + rng.randf_range(-0.25, 0.25)
		var radius := rng.randf_range(11.0, 22.0)
		villager.position = Vector3(cos(angle) * radius, 1.2, sin(angle) * radius)
		add_child(villager)
	for i in 7:
		var bird := MobScene.instantiate() as Mob
		bird.kind = "bird"
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(5.0, 25.0)
		bird.position = Vector3(cos(angle) * radius, rng.randf_range(1.5, 3.5), sin(angle) * radius)
		add_child(bird)


# --- Camera & juice ---------------------------------------------------------

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.1
	camera.far = 160.0
	add_child(camera)
	camera.current = true


func _update_camera(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var distance := 3.4 + 4.6 * player.size
	var target := player.global_position + Vector3(0, 0.9 * player.size, 0)
	var desired := player.global_position + Vector3(0, distance * 0.85, distance)
	if not _camera_ready:
		camera.global_position = desired
		_camera_ready = true
	else:
		camera.global_position = camera.global_position.lerp(desired, clampf(5.0 * delta, 0.0, 1.0))
	camera.look_at(target, Vector3.UP)
	if _trauma > 0.0:
		_shake_time += delta * 32.0
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
	if eat_sound.stream:
		eat_sound.pitch_scale = randf_range(0.85, 1.15)
		eat_sound.play()
	_update_hud()


func _on_size_changed(_new_size: float) -> void:
	_update_hud()


func _burst(at: Vector3, color: Color, count: int) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.5
	process.gravity = Vector3(0, -7, 0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.color = color
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.25

	var drop := SphereMesh.new()
	drop.radius = 0.07
	drop.height = 0.14
	var drop_mat := ToonMaterial.flat(color)
	drop.material = drop_mat

	particles.process_material = process
	particles.draw_pass_1 = drop
	add_child(particles)
	particles.global_position = at
	particles.finished.connect(particles.queue_free)


# --- HUD --------------------------------------------------------------------

func _update_hud() -> void:
	var tier := "Tiny"
	if player.size > player.top_tier_size:
		tier = "Large"
	elif player.size > TIER_MEDIUM:
		tier = "Medium"
	elif player.size > TIER_SMALL:
		tier = "Small"
	hud_label.text = "Size %.2f  ·  %s\nEaten %d" % [player.size, tier, player.eaten_count]
	if _remaining <= 0:
		hud_label.text += "\nNothing left to eat."
