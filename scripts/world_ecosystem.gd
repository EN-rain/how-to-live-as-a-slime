class_name WorldEcosystem
extends Node3D

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
const ActorArchetype = preload("res://resources/actors/actor_archetype.gd")

@export_group("Actor Archetypes")
@export var wolf_alpha_archetype: ActorArchetype = preload("res://resources/actors/wolf_alpha.tres")
@export var wolf_timber_archetype: ActorArchetype = preload("res://resources/actors/wolf_timber.tres")
@export var spider_broodmother_archetype: ActorArchetype = preload("res://resources/actors/spider_broodmother.tres")
@export var spider_weaver_archetype: ActorArchetype = preload("res://resources/actors/spider_weaver.tres")
@export var spider_spiderling_archetype: ActorArchetype = preload("res://resources/actors/spider_spiderling.tres")
@export var rat_king_archetype: ActorArchetype = preload("res://resources/actors/rat_king.tres")
@export var rat_sewer_archetype: ActorArchetype = preload("res://resources/actors/rat_sewer.tres")
@export var skeleton_warrior_archetype: ActorArchetype = preload("res://resources/actors/skeleton_warrior.tres")
@export var skeleton_overlord_archetype: ActorArchetype = preload("res://resources/actors/skeleton_overlord.tres")
@export var villager_citizen_archetype: ActorArchetype = preload("res://resources/actors/villager_citizen.tres")
@export var wildlife_critter_archetype: ActorArchetype = preload("res://resources/actors/wildlife_critter.tres")
## Manages all Human NPCs, Wildlife/Livestock, Hostile Mobs, combat projectiles,
## billboard HP bars, VillageNavGraph routing, and Mobile animation LOD slicing.

const SPATIAL_CELL_SIZE := 6.0
const PROJ_POOL_SIZE := 16
const MAX_HP_BARS := 48

var nav_graph := VillageNavGraph.new()
var actors: Array[LivingActor] = []
var _village_actors: Array[LivingActor] = []
var _hostile_actors: Array[LivingActor] = []
var player_slime: Slime = null

var _terrain: Node = null
var _village_root: Node = null
var _time_weather: WorldTimeWeather = null
var _cave_atm: Node = null
var _dock_cache_done := false
var _has_dock := false
var _dock_shore_xy := Vector2.ZERO
var _dock_fwd := Vector2.UP
var _dock_right := Vector2.RIGHT
var _actor_shader := preload("res://shaders/actor_matte.gdshader")
var _mat_cache: Dictionary = {}
var _weapon_cache: Dictionary = {}
var _mat_glow_eye: StandardMaterial3D
var _spatial_grid: Dictionary = {}  # Vector2i -> Array[LivingActor]

var _village_provoked_timer: float = 0.0
var _frame_counter: int = 0

## Auto-detected registry of every shipped actor model (see actor_model_library.gd).
## Preloaded rather than resolved through the global class cache so the script also
## compiles in a fresh checkout / headless CI before the editor has re-scanned.
const ActorModels = preload("res://scripts/actor_model_library.gd")
var model_library := ActorModels.new()

# Pooled projectiles (arrows & arcane bolts)
var _projectiles: Array[Dictionary] = []
var _hp_bar_mm: MultiMeshInstance3D = null
var _hp_bar_im_quad: QuadMesh = null


func _ready() -> void:
	add_to_group("world_ecosystem")
	_build_shared_eye_mat()
	_build_projectile_pool()
	_build_hp_bar_multimesh()
	call_deferred("_initialize_ecosystem")


func _initialize_ecosystem() -> void:
	var root := get_parent()
	if root != null:
		player_slime = root.get_node_or_null("Slime") as Slime
		_terrain = root.get_node_or_null("TerrainScene")
		_time_weather = root.get_node_or_null("WorldTimeWeather") as WorldTimeWeather
		if _terrain != null:
			_village_root = _terrain.get_node_or_null("Village")
			var cs := _terrain.get_node_or_null("CaveSystem")
			if cs != null:
				_cave_atm = cs.get_node_or_null("CaveAtmosphere")

	nav_graph.build(_village_root)
	_scan_model_library()
	_spawn_all_populations()


## Detects which actor models actually exist on disk before any actor is spawned.
## Runs once; the resulting pools drive missing-file fallback and respawn re-rolls.
func _scan_model_library() -> void:
	model_library.build()
	print("[WorldEcosystem] actor models auto-detected: %s" % str(model_library.category_counts()))
	for note in model_library.scan_notes():
		push_warning("[WorldEcosystem] model library: " + note)


func _build_shared_eye_mat() -> void:
	_mat_glow_eye = StandardMaterial3D.new()
	_mat_glow_eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_glow_eye.albedo_color = Color(0.55, 0.96, 1.0)
	_mat_glow_eye.emission_enabled = true
	_mat_glow_eye.emission = Color(0.45, 0.92, 1.0)
	_mat_glow_eye.emission_energy_multiplier = 2.0


func _build_projectile_pool() -> void:
	var arrow_scene := load("res://assets/npcs/arrow.gltf") as PackedScene
	var bolt_mesh := SphereMesh.new()
	bolt_mesh.radius = 0.16
	bolt_mesh.height = 0.32
	bolt_mesh.radial_segments = 8
	bolt_mesh.rings = 4
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.albedo_color = Color(1.0, 0.48, 0.92)
	bolt_mat.emission_enabled = true
	bolt_mat.emission = Color(0.95, 0.32, 1.0)
	bolt_mat.emission_energy_multiplier = 2.4

	for i in range(PROJ_POOL_SIZE):
		var holder := Node3D.new()
		holder.visible = false
		holder.name = "Proj_%d" % i
		var arrow_vis: Node3D = null
		if arrow_scene != null:
			arrow_vis = arrow_scene.instantiate() as Node3D
			_normalize_node_materials(arrow_vis)
			arrow_vis.rotation.x = PI * 0.5
			holder.add_child(arrow_vis)
		var bolt_vis := MeshInstance3D.new()
		bolt_vis.mesh = bolt_mesh
		bolt_vis.material_override = bolt_mat
		bolt_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt_vis.visible = false
		holder.add_child(bolt_vis)
		add_child(holder)
		_projectiles.append({
			"node": holder,
			"arrow": arrow_vis,
			"bolt": bolt_vis,
			"active": false,
			"vel": Vector3.ZERO,
			"life": 0.0,
			"dmg": 14.0,
			"faction": LivingActor.Faction.HOSTILE,
			"shooter": null,
			"is_spell": false,
		})


func _build_hp_bar_multimesh() -> void:
	_hp_bar_mm = MultiMeshInstance3D.new()
	_hp_bar_mm.name = "ActorHPBars"
	_hp_bar_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var q := QuadMesh.new()
	q.size = Vector2(1.15, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	q.material = mat
	_hp_bar_im_quad = q

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = MAX_HP_BARS
	mm.visible_instance_count = 0
	mm.mesh = q
	_hp_bar_mm.multimesh = mm
	add_child(_hp_bar_mm)


func _spawn_all_populations() -> void:
	var vc := Vector2(VillageBuilder.VILLAGE_CENTER.x, VillageBuilder.VILLAGE_CENTER.z)
	var guard_posts := nav_graph.get_guard_posts()
	var stalls := nav_graph.get_stall_spots()
	var socials := nav_graph.get_social_spots()
	var fisher_route := nav_graph.get_fisherman_route()
	var paddocks := nav_graph.get_paddock_spots()
	var gate_outs := nav_graph.get_gate_approaches()

	# --- 1. 8 Town Guards (Knight sword/shield on avenues + Rogue crossbowmen at outer gates) ---
	for i in range(8):
		var is_ranged := (i == 1 or i == 3)
		var glb := "res://assets/npcs/Rogue.glb" if is_ranged else "res://assets/npcs/Knight.glb"
		var post_idx := i if is_ranged else (4 + i)
		var start_xz: Vector2 = guard_posts[post_idx % guard_posts.size()] if not guard_posts.is_empty() else vc
		var patrol: Array[Vector2] = []
		if not guard_posts.is_empty():
			for step in range(4):
				patrol.append(guard_posts[(post_idx + step) % guard_posts.size()])
		_spawn_actor({
			"name": "Crossbow Guard" if is_ranged else "Town Guard",
			"category": "npc",
			"glb": glb,
			"scale": 0.84,
			"faction": LivingActor.Faction.VILLAGE,
			"role": LivingActor.RoleKind.GUARD,
			"attack_kind": LivingActor.AttackKind.RANGED_BOW if is_ranged else LivingActor.AttackKind.MELEE,
			"pos_xz": start_xz,
			"patrol": patrol,
			"hp": 145.0,
			"walk_spd": 2.9,
			"run_spd": 5.9,
			"range": 13.0 if is_ranged else 2.1,
			"aggro": 24.0,
			"dmg": 18.0 if not is_ranged else 14.0,
			"cd": 1.35 if is_ranged else 1.10,
			"eq_r": "res://assets/npcs/crossbow_1handed.gltf" if is_ranged else "res://assets/npcs/sword_1handed.gltf",
			"eq_l": "" if is_ranged else "res://assets/npcs/shield_badge.gltf",
		})

	# --- 2. 15 Lively Villagers (Stallkeepers, Shoppers, Inn/Smithy Folk, Fisherman) ---
	var fallback_yaw := PI * 0.5
	var villager_defs := [
		{"name": "Market Merchant", "glb": "res://assets/npcs/Rogue_Hooded.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[0]["pos"] if stalls.size() > 0 else vc + Vector2(-10.4, -8.6), "yaw": stalls[0]["yaw"] if stalls.size() > 0 else fallback_yaw, "work": "Cheer", "start_work": true},
		{"name": "Produce Vendor", "glb": "res://assets/npcs/Rogue.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[1]["pos"] if stalls.size() > 1 else vc + Vector2(-10.4, -4.6), "yaw": stalls[1]["yaw"] if stalls.size() > 1 else fallback_yaw, "work": "Interact", "start_work": true},
		{"name": "Tea & Herb Seller", "glb": "res://assets/npcs/Mage.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "res://assets/npcs/mug_full.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[2]["pos"] if stalls.size() > 2 else vc + Vector2(-10.4, 4.6), "yaw": stalls[2]["yaw"] if stalls.size() > 2 else fallback_yaw, "work": "Use_Item", "start_work": true},
		{"name": "Bakery Keeper", "glb": "res://assets/npcs/Barbarian.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[3]["pos"] if stalls.size() > 3 else vc + Vector2(10.4, -4.6), "yaw": stalls[3]["yaw"] if stalls.size() > 3 else -fallback_yaw, "work": "Cheer", "start_work": true},
		{"name": "Spice & Barrel Trader", "glb": "res://assets/npcs/Rogue_Hooded.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[4]["pos"] if stalls.size() > 4 else vc + Vector2(10.4, 4.6), "yaw": stalls[4]["yaw"] if stalls.size() > 4 else -fallback_yaw, "work": "Interact", "start_work": true},
		{"name": "Market Shopper", "glb": "res://assets/npcs/Barbarian.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": socials[0]["pos"] if socials.size() > 0 else vc + Vector2(-6.3, -8.6), "yaw": socials[0]["yaw"] if socials.size() > 0 else -fallback_yaw, "work": "Interact", "start_work": true},
		{"name": "Town Browser", "glb": "res://assets/npcs/Rogue.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": socials[3]["pos"] if socials.size() > 3 else vc + Vector2(6.3, -8.6), "yaw": socials[3]["yaw"] if socials.size() > 3 else fallback_yaw, "work": "Use_Item", "start_work": true},
		{"name": "Well Gossip", "glb": "res://assets/npcs/Rogue_Hooded.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": socials[6]["pos"] if socials.size() > 6 else vc + Vector2(-2.8, 2.8), "yaw": socials[6]["yaw"] if socials.size() > 6 else -0.8, "work": "Cheer", "start_work": true},
		{"name": "Villager Guest", "glb": "res://assets/npcs/Mage.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": socials[7]["pos"] if socials.size() > 7 else vc + Vector2(2.8, -2.8), "yaw": socials[7]["yaw"] if socials.size() > 7 else 2.3, "work": "Interact", "start_work": true},
		{"name": "Innkeeper", "glb": "res://assets/npcs/Barbarian.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "res://assets/npcs/mug_full.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": vc + Vector2(-15.2, -7.8), "yaw": fallback_yaw, "work": "Cheer", "start_work": true},
		{"name": "Inn Patron", "glb": "res://assets/npcs/Rogue.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/mug_full.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": socials[9]["pos"] if socials.size() > 9 else vc + Vector2(-13.1, -9.8), "yaw": socials[9]["yaw"] if socials.size() > 9 else -fallback_yaw, "work": "Sit_Chair_Idle", "start_work": true},
		{"name": "Village Blacksmith", "glb": "res://assets/npcs/Barbarian.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/axe_1handed.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": vc + Vector2(6.9, 14.5), "yaw": -fallback_yaw, "work": "Interact", "start_work": true},
		{"name": "Town Apothecary", "glb": "res://assets/npcs/Mage.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/staff.gltf", "eq_l": "res://assets/npcs/spellbook_open.gltf", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": socials[4]["pos"] if socials.size() > 4 else vc + Vector2(6.3, -4.6), "yaw": socials[4]["yaw"] if socials.size() > 4 else fallback_yaw, "work": "Use_Item", "start_work": true},
		{"name": "Court Scholar", "glb": "res://assets/npcs/Mage.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/spellbook_open.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": socials[12]["pos"] if socials.size() > 12 else vc + Vector2(-5.2, -13.8), "yaw": socials[12]["yaw"] if socials.size() > 12 else 0.2, "work": "Use_Item", "start_work": true},
		{"name": "Harbor Fisherman", "glb": "res://assets/npcs/Rogue.glb", "role": LivingActor.RoleKind.FISHERMAN, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": fisher_route[fisher_route.size() - 1] if not fisher_route.is_empty() else vc + Vector2(80, 120), "patrol": fisher_route},
	]
	for vd in villager_defs:
		var v_cfg := {
			"name": vd["name"],
			"category": "npc",
			"glb": vd["glb"],
			"scale": 0.84,
			"faction": LivingActor.Faction.VILLAGE,
			"role": vd["role"],
			"attack_kind": vd["kind"],
			"pos_xz": vd["pos"],
			"patrol": vd.get("patrol", [] as Array[Vector2]),
			"hp": 95.0,
			"walk_spd": 2.45,
			"run_spd": 4.9,
			"range": 11.0 if vd["kind"] == LivingActor.AttackKind.RANGED_SPELL else 1.85,
			"aggro": 15.0,
			"dmg": 12.0,
			"cd": 1.35,
			"eq_r": vd["eq_r"],
			"eq_l": vd["eq_l"],
			"work": vd.get("work", "Interact"),
			"start_work": vd.get("start_work", false),
		}
		if vd.has("yaw"):
			v_cfg["yaw"] = vd["yaw"]
		_spawn_actor(v_cfg)

	# --- 3. 14 Animals (Livestock in Village Paddocks, Plaza Dogs & Wild Deer/Stags/Foxes in Meadows) ---
	var livestock := [
		{"name": "Village Cow", "glb": "res://assets/animals/Cow.glb", "scale": 0.36, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[0] if paddocks.size() > 0 else vc + Vector2(-44, 68)},
		{"name": "Spotted Cow", "glb": "res://assets/animals/Cow.glb", "scale": 0.35, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[1] if paddocks.size() > 1 else vc + Vector2(44, 68)},
		{"name": "Chestnut Horse", "glb": "res://assets/animals/Horse.glb", "scale": 0.43, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[2] if paddocks.size() > 2 else vc + Vector2(-78, -28)},
		{"name": "White Horse", "glb": "res://assets/animals/Horse_White.glb", "scale": 0.43, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[3] if paddocks.size() > 3 else vc + Vector2(78, -28)},
		{"name": "Plaza Pup", "glb": "res://assets/animals/ShibaInu.glb", "scale": 0.27, "role": LivingActor.RoleKind.DOG, "pos": vc + Vector2(-2.6, 5.6)},
		{"name": "Inn Hound", "glb": "res://assets/animals/ShibaInu.glb", "scale": 0.28, "role": LivingActor.RoleKind.DOG, "pos": vc + Vector2(-12.6, -4.0)},
		{"name": "Gatehouse Hound", "glb": "res://assets/animals/ShibaInu.glb", "scale": 0.28, "role": LivingActor.RoleKind.DOG, "pos": vc + Vector2(3.5, 48.0)},
	]
	for a in livestock:
		var is_dog: bool = a["role"] == LivingActor.RoleKind.DOG
		_spawn_actor({
			"name": a["name"],
			"category": "animal",
			"glb": a["glb"],
			"scale": a["scale"],
			"faction": LivingActor.Faction.VILLAGE if is_dog else LivingActor.Faction.NEUTRAL,
			"role": a["role"],
			"attack_kind": LivingActor.AttackKind.MELEE,
			"pos_xz": a["pos"],
			"hp": 80.0 if is_dog else 65.0,
			"walk_spd": 2.2,
			"run_spd": 6.4,
			"range": 1.6,
			"aggro": 15.0 if is_dog else 0.0,
			"dmg": 10.0,
			"cd": 1.0,
			"hp_h": 1.5,
			"rad": 0.65,
		})

	var wild_specs := [
		{"name": "Meadow Stag", "glb": "res://assets/animals/Stag.glb", "scale": 0.40, "pos": Vector2(420.0, 2060.0), "h": 2.1},
		{"name": "Meadow Doe", "glb": "res://assets/animals/Deer.glb", "scale": 0.42, "pos": Vector2(436.0, 2048.0), "h": 1.8},
		{"name": "Meadow Doe", "glb": "res://assets/animals/Deer.glb", "scale": 0.41, "pos": Vector2(-58.0, 62.0), "h": 1.8},
		{"name": "Hillside Stag", "glb": "res://assets/animals/Stag.glb", "scale": 0.40, "pos": Vector2(180.0, 2120.0), "h": 2.1},
		{"name": "Red Fox", "glb": "res://assets/animals/Fox.glb", "scale": 0.30, "pos": Vector2(84.0, -52.0), "h": 1.0},
		{"name": "Coastline Fox", "glb": "res://assets/animals/Fox.glb", "scale": 0.30, "pos": Vector2(695.0, 2295.0), "h": 1.0},
		{"name": "Forest Doe", "glb": "res://assets/animals/Deer.glb", "scale": 0.42, "pos": Vector2(725.0, 2085.0), "h": 1.8},
	]
	for wa in wild_specs:
		_spawn_actor({
			"name": wa["name"],
			"category": "animal",
			"glb": wa["glb"],
			"scale": wa["scale"],
			"faction": LivingActor.Faction.NEUTRAL,
			"role": LivingActor.RoleKind.ANIMAL,
			"attack_kind": LivingActor.AttackKind.MELEE,
			"pos_xz": wa["pos"],
			"hp": 55.0,
			"walk_spd": 2.5,
			"run_spd": 7.6,
			"range": 1.5,
			"aggro": 0.0,
			"dmg": 0.0,
			"cd": 1.5,
			"hp_h": wa["h"],
			"rad": 0.60,
		})

	# --- 4. Beast Territories (Wolf Pack Crag, Spider Silk Forest, Underground Rat Warren) ---
	var beast_specs := [
		# Wolf Pack Crag ((290, -240), expanded Howlcrest ridge territory, pack_id="wolf_pack")
		{"name": "Alpha Dire Wolf", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.54, "pos": Vector2(290.0, -244.0), "tc": Vector2(290.0, -240.0), "tr": 34.0, "lr": 105.0, "pack": &"wolf_pack", "hp": 185.0, "dmg": 20.0, "h": 1.65},
		{"name": "Timber Wolf", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.41, "pos": Vector2(278.0, -234.0), "tc": Vector2(290.0, -240.0), "tr": 42.0, "lr": 105.0, "pack": &"wolf_pack", "hp": 95.0, "dmg": 14.0, "h": 1.30},
		{"name": "Timber Wolf", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.40, "pos": Vector2(302.0, -236.0), "tc": Vector2(290.0, -240.0), "tr": 42.0, "lr": 105.0, "pack": &"wolf_pack", "hp": 95.0, "dmg": 14.0, "h": 1.30},
		{"name": "Timber Wolf", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.42, "pos": Vector2(292.0, -220.0), "tc": Vector2(290.0, -240.0), "tr": 46.0, "lr": 105.0, "pack": &"wolf_pack", "hp": 95.0, "dmg": 14.0, "h": 1.30},
		{"name": "Crag Ridge Stalker", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.42, "pos": Vector2(270.0, -226.0), "tc": Vector2(280.0, -230.0), "tr": 44.0, "lr": 105.0, "pack": &"wolf_pack", "hp": 100.0, "dmg": 15.0, "h": 1.32},
		{"name": "Howlcrest Sentinel", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.43, "pos": Vector2(312.0, -234.0), "tc": Vector2(304.0, -236.0), "tr": 44.0, "lr": 105.0, "pack": &"wolf_pack", "hp": 100.0, "dmg": 15.0, "h": 1.32},
		{"name": "Pine Gorge Hunter", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.40, "pos": Vector2(296.0, -210.0), "tc": Vector2(290.0, -222.0), "tr": 48.0, "lr": 105.0, "pack": &"wolf_pack", "hp": 92.0, "dmg": 14.0, "h": 1.30},

		# Wide Webwood Spider Domain ((-410, 480), R = 165m, pack_id="spider_brood")
		# Central Broodmother Cathedral Nest
		{"name": "Broodmother Spider", "glb": "res://assets/mobs/Spider.glb", "scale": 0.58, "pos": Vector2(-410.0, 480.0), "tc": Vector2(-410.0, 480.0), "tr": 42.0, "lr": 152.0, "pack": &"spider_brood", "hp": 240.0, "dmg": 22.0, "h": 1.85, "rad": 0.88, "aggro": 26.0, "run_spd": 7.0},
		{"name": "Broodguard Weaver", "glb": "res://assets/mobs/Spider.glb", "scale": 0.40, "pos": Vector2(-426.0, 466.0), "tc": Vector2(-410.0, 480.0), "tr": 54.0, "lr": 152.0, "pack": &"spider_brood", "hp": 115.0, "dmg": 15.0, "h": 1.24, "rad": 0.72, "aggro": 24.0, "run_spd": 7.2},
		{"name": "Broodguard Weaver", "glb": "res://assets/mobs/Spider.glb", "scale": 0.38, "pos": Vector2(-394.0, 496.0), "tc": Vector2(-410.0, 480.0), "tr": 54.0, "lr": 152.0, "pack": &"spider_brood", "hp": 110.0, "dmg": 15.0, "h": 1.22, "rad": 0.72, "aggro": 24.0, "run_spd": 7.2},
		{"name": "Broodguard Weaver", "glb": "res://assets/mobs/Spider.glb", "scale": 0.39, "pos": Vector2(-424.0, 494.0), "tc": Vector2(-410.0, 480.0), "tr": 54.0, "lr": 152.0, "pack": &"spider_brood", "hp": 112.0, "dmg": 15.0, "h": 1.22, "rad": 0.72, "aggro": 24.0, "run_spd": 7.2},
		{"name": "Broodguard Weaver", "glb": "res://assets/mobs/Spider.glb", "scale": 0.37, "pos": Vector2(-396.0, 464.0), "tc": Vector2(-410.0, 480.0), "tr": 54.0, "lr": 152.0, "pack": &"spider_brood", "hp": 110.0, "dmg": 15.0, "h": 1.22, "rad": 0.72, "aggro": 24.0, "run_spd": 7.2},
		{"name": "Webwood Spider", "glb": "res://assets/mobs/Spider.glb", "scale": 0.33, "pos": Vector2(-394.0, 474.0), "tc": Vector2(-410.0, 480.0), "tr": 78.0, "lr": 155.0, "pack": &"spider_brood", "hp": 86.0, "dmg": 13.0, "h": 1.06, "run_spd": 7.4},
		{"name": "Webwood Spider", "glb": "res://assets/mobs/Spider.glb", "scale": 0.32, "pos": Vector2(-426.0, 488.0), "tc": Vector2(-410.0, 480.0), "tr": 78.0, "lr": 155.0, "pack": &"spider_brood", "hp": 84.0, "dmg": 13.0, "h": 1.05, "run_spd": 7.4},
		{"name": "Webwood Spider", "glb": "res://assets/mobs/Spider.glb", "scale": 0.31, "pos": Vector2(-412.0, 460.0), "tc": Vector2(-410.0, 480.0), "tr": 78.0, "lr": 155.0, "pack": &"spider_brood", "hp": 84.0, "dmg": 13.0, "h": 1.05, "run_spd": 7.4},
		{"name": "Webwood Spider", "glb": "res://assets/mobs/Spider.glb", "scale": 0.31, "pos": Vector2(-408.0, 502.0), "tc": Vector2(-410.0, 480.0), "tr": 78.0, "lr": 155.0, "pack": &"spider_brood", "hp": 84.0, "dmg": 13.0, "h": 1.05, "run_spd": 7.4},

		# Surface Gnawed Ruins Rat Swarm (subterranean_kind=0, patrolling gatehouse, courtyard, cloister & watchtower)
		{"name": "Ruin Courtyard Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.40, "pos": Vector2(-241.0, 434.0), "tc": Vector2(-235.0, 436.0), "tr": 16.0, "lr": 32.0, "pack": &"rat_swarm", "hp": 56.0, "dmg": 11.0, "h": 0.80},
		{"name": "Cloister Scavenger Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.41, "pos": Vector2(-252.0, 434.0), "tc": Vector2(-252.0, 434.0), "tr": 12.0, "lr": 26.0, "pack": &"rat_swarm", "hp": 58.0, "dmg": 11.0, "h": 0.80},
		{"name": "Watchtower Ruin Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.41, "pos": Vector2(-218.0, 431.0), "tc": Vector2(-220.0, 433.0), "tr": 14.0, "lr": 28.0, "pack": &"rat_swarm", "hp": 58.0, "dmg": 11.0, "h": 0.80},
		{"name": "Gatehouse Gnawer Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.39, "pos": Vector2(-231.0, 450.0), "tc": Vector2(-235.0, 448.0), "tr": 15.0, "lr": 30.0, "pack": &"rat_swarm", "hp": 54.0, "dmg": 10.0, "h": 0.78},
		{"name": "Barbican Sentry Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.42, "pos": Vector2(-236.0, 486.0), "tc": Vector2(-235.0, 486.0), "tr": 14.0, "lr": 28.0, "pack": &"rat_swarm", "hp": 60.0, "dmg": 12.0, "h": 0.82},
		{"name": "Granary Ruin Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.40, "pos": Vector2(-264.0, 442.0), "tc": Vector2(-264.0, 442.0), "tr": 12.0, "lr": 26.0, "pack": &"rat_swarm", "hp": 58.0, "dmg": 11.0, "h": 0.80},
		{"name": "Belfry Scavenger Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.41, "pos": Vector2(-206.0, 441.0), "tc": Vector2(-206.0, 441.0), "tr": 12.0, "lr": 26.0, "pack": &"rat_swarm", "hp": 58.0, "dmg": 11.0, "h": 0.80},

		# Expanded Underground Rat Warren Under-Empire (deepwoods east of Webwood, subterranean_kind=2, pack_id="rat_swarm")
		{"name": "Plague Rat King", "glb": "res://assets/mobs/Rat.glb", "scale": 0.68, "pos": Vector2(-235.0, 320.0), "tc": Vector2(-235.0, 323.0), "tr": 15.0, "lr": 26.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-257.0, 313.0), "bmax": Vector2(-213.0, 349.0), "hp": 185.0, "dmg": 18.0, "h": 1.25},
		{"name": "Sanctum Gnaw-Guard", "glb": "res://assets/mobs/Rat.glb", "scale": 0.44, "pos": Vector2(-243.5, 327.5), "tc": Vector2(-235.0, 329.0), "tr": 15.0, "lr": 24.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-257.0, 313.0), "bmax": Vector2(-213.0, 349.0), "hp": 72.0, "dmg": 13.0, "h": 0.90},
		{"name": "Sanctum Gnaw-Guard", "glb": "res://assets/mobs/Rat.glb", "scale": 0.43, "pos": Vector2(-226.5, 328.0), "tc": Vector2(-235.0, 329.0), "tr": 15.0, "lr": 24.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-257.0, 313.0), "bmax": Vector2(-213.0, 349.0), "hp": 72.0, "dmg": 13.0, "h": 0.90},
		{"name": "Sewer Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.38, "pos": Vector2(-243.0, 375.0), "tc": Vector2(-235.0, 378.0), "tr": 13.0, "lr": 22.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-251.0, 364.0), "bmax": Vector2(-219.0, 391.0), "hp": 50.0, "dmg": 10.0, "h": 0.78},
		{"name": "Sewer Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.36, "pos": Vector2(-227.0, 376.0), "tc": Vector2(-235.0, 378.0), "tr": 13.0, "lr": 22.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-251.0, 364.0), "bmax": Vector2(-219.0, 391.0), "hp": 50.0, "dmg": 10.0, "h": 0.78},
		{"name": "Sewer Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.40, "pos": Vector2(-241.0, 385.0), "tc": Vector2(-235.0, 378.0), "tr": 13.0, "lr": 22.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-251.0, 364.0), "bmax": Vector2(-219.0, 391.0), "hp": 50.0, "dmg": 10.0, "h": 0.78},
		{"name": "Sewer Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.37, "pos": Vector2(-228.0, 387.0), "tc": Vector2(-235.0, 378.0), "tr": 13.0, "lr": 22.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-251.0, 364.0), "bmax": Vector2(-219.0, 391.0), "hp": 50.0, "dmg": 10.0, "h": 0.78},
		{"name": "Burrow Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.39, "pos": Vector2(-235.0, 368.0), "tc": Vector2(-235.0, 378.0), "tr": 13.0, "lr": 22.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-251.0, 364.0), "bmax": Vector2(-219.0, 391.0), "hp": 50.0, "dmg": 10.0, "h": 0.78},
		{"name": "Cistern Bilge Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.40, "pos": Vector2(-267.0, 376.0), "tc": Vector2(-270.0, 378.0), "tr": 11.0, "lr": 18.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-283.0, 365.0), "bmax": Vector2(-257.0, 390.0), "hp": 58.0, "dmg": 11.0, "h": 0.80},
		{"name": "Cistern Bilge Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.38, "pos": Vector2(-273.0, 382.0), "tc": Vector2(-270.0, 378.0), "tr": 11.0, "lr": 18.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-283.0, 365.0), "bmax": Vector2(-257.0, 390.0), "hp": 58.0, "dmg": 11.0, "h": 0.80},
		{"name": "Nest Scavenger Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.41, "pos": Vector2(-199.0, 374.0), "tc": Vector2(-198.0, 377.0), "tr": 12.0, "lr": 18.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-211.0, 364.0), "bmax": Vector2(-185.0, 390.0), "hp": 60.0, "dmg": 11.0, "h": 0.82},
		{"name": "Nest Scavenger Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.39, "pos": Vector2(-195.0, 383.0), "tc": Vector2(-198.0, 377.0), "tr": 12.0, "lr": 18.0, "pack": &"rat_swarm", "sub": 2, "bmin": Vector2(-211.0, 364.0), "bmax": Vector2(-185.0, 390.0), "hp": 60.0, "dmg": 11.0, "h": 0.82},
		# Crypt Rat in Skeleton Cave East Ossuary
		{"name": "Crypt Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.40, "pos": Vector2(-786.0, 266.0), "tc": Vector2(-790.0, 272.0), "tr": 10.0, "lr": 16.0, "pack": &"skel_crypt", "sub": 1, "bmin": Vector2(-802.0, 258.0), "bmax": Vector2(-778.0, 287.0), "hp": 55.0, "dmg": 10.0, "h": 0.78},
	]
	# Dense Webwood spider swarm clusters: egg-cache spiderlings, trail ambushers, outer nests & mid-wood glades
	for i in range(10):
		var ang := float(i) * TAU / 10.0 + 0.31
		var r := 6.5 + float(i % 3) * 4.5
		var pos := Vector2(-412.0, 481.0) + Vector2(cos(ang), sin(ang)) * r
		beast_specs.append({
			"name": "Brood Spiderling", "glb": "res://assets/mobs/Spider.glb",
			"scale": 0.17 + float(i % 3) * 0.02, "pos": pos, "tc": Vector2(-410.0, 480.0),
			"tr": 28.0, "lr": 115.0, "pack": &"spider_brood",
			"hp": 36.0, "dmg": 7.5, "h": 0.65, "rad": 0.42, "aggro": 22.0, "run_spd": 8.4,
		})
	var trail_spiders := [
		{"name": "Webwood Ambush Spider", "pos": Vector2(-362.0, 418.0), "scale": 0.34, "hp": 94.0, "dmg": 14.0, "h": 1.10, "rad": 0.64, "spd": 7.5},
		{"name": "Webwood Skitterer", "pos": Vector2(-355.0, 428.0), "scale": 0.24, "hp": 54.0, "dmg": 10.0, "h": 0.82, "rad": 0.50, "spd": 8.1},
		{"name": "Brood Spiderling", "pos": Vector2(-374.0, 434.0), "scale": 0.19, "hp": 36.0, "dmg": 7.5, "h": 0.65, "rad": 0.42, "spd": 8.5},
		{"name": "Webwood Ambush Spider", "pos": Vector2(-382.0, 446.0), "scale": 0.35, "hp": 96.0, "dmg": 14.0, "h": 1.12, "rad": 0.65, "spd": 7.5},
		{"name": "Webwood Skitterer", "pos": Vector2(-376.0, 456.0), "scale": 0.25, "hp": 58.0, "dmg": 10.5, "h": 0.85, "rad": 0.52, "spd": 8.0},
		{"name": "Brood Spiderling", "pos": Vector2(-390.0, 450.0), "scale": 0.20, "hp": 38.0, "dmg": 8.0, "h": 0.68, "rad": 0.44, "spd": 8.4},
	]
	for ts in trail_spiders:
		beast_specs.append({
			"name": ts["name"], "glb": "res://assets/mobs/Spider.glb",
			"scale": ts["scale"], "pos": ts["pos"], "tc": ts["pos"],
			"tr": 32.0, "lr": 75.0, "pack": &"spider_brood",
			"hp": ts["hp"], "dmg": ts["dmg"], "h": ts["h"], "rad": ts["rad"], "aggro": 24.0, "run_spd": ts["spd"],
		})
	var outer_nests := [
		Vector2(-362.0, 405.0), # North Trail Ambush Nest
		Vector2(-498.0, 466.0), # West Deepwood Nest
		Vector2(-416.0, 566.0), # South Ridge Nest
		Vector2(-328.0, 514.0), # East Hollow Nest
	]
	var nest_roles := [
		{"name": "Webwood Ambush Spider", "scale": 0.35, "hp": 96.0, "dmg": 14.0, "h": 1.12, "rad": 0.65, "spd": 7.4, "off": Vector2(0.0, 0.0)},
		{"name": "Webwood Stalker", "scale": 0.30, "hp": 78.0, "dmg": 13.0, "h": 1.00, "rad": 0.60, "spd": 7.6, "off": Vector2(10.0, 7.0)},
		{"name": "Webwood Stalker", "scale": 0.29, "hp": 76.0, "dmg": 12.0, "h": 0.98, "rad": 0.58, "spd": 7.6, "off": Vector2(-9.0, 9.0)},
		{"name": "Brood Spiderling", "scale": 0.20, "hp": 38.0, "dmg": 8.0, "h": 0.68, "rad": 0.44, "spd": 8.4, "off": Vector2(6.0, -8.0)},
		{"name": "Brood Spiderling", "scale": 0.18, "hp": 34.0, "dmg": 7.0, "h": 0.64, "rad": 0.42, "spd": 8.5, "off": Vector2(-7.0, -7.0)},
	]
	for nc in outer_nests:
		for nr in nest_roles:
			beast_specs.append({
				"name": nr["name"], "glb": "res://assets/mobs/Spider.glb",
				"scale": nr["scale"], "pos": nc + nr["off"], "tc": nc,
				"tr": 46.0, "lr": 82.0, "pack": &"spider_brood",
				"hp": nr["hp"], "dmg": nr["dmg"], "h": nr["h"], "rad": nr["rad"], "aggro": 24.0, "run_spd": nr["spd"],
			})
	var glade_packs := [
		Vector2(-454.0, 436.0), # NW Silk Glade
		Vector2(-460.0, 524.0), # SW Silk Glade
		Vector2(-366.0, 536.0), # SE Silk Glade
		Vector2(-364.0, 444.0), # NE Silk Glade
	]
	var glade_roles := [
		{"name": "Webwood Weaver", "scale": 0.34, "hp": 92.0, "dmg": 14.0, "h": 1.10, "rad": 0.64, "spd": 7.4, "off": Vector2(0.0, 0.0)},
		{"name": "Webwood Stalker", "scale": 0.29, "hp": 76.0, "dmg": 12.0, "h": 0.98, "rad": 0.58, "spd": 7.6, "off": Vector2(9.0, -6.0)},
		{"name": "Webwood Skitterer", "scale": 0.24, "hp": 54.0, "dmg": 10.0, "h": 0.82, "rad": 0.50, "spd": 8.1, "off": Vector2(-8.0, 6.0)},
		{"name": "Brood Spiderling", "scale": 0.19, "hp": 36.0, "dmg": 7.5, "h": 0.65, "rad": 0.42, "spd": 8.4, "off": Vector2(5.0, 8.0)},
	]
	for gc in glade_packs:
		for gr in glade_roles:
			beast_specs.append({
				"name": gr["name"], "glb": "res://assets/mobs/Spider.glb",
				"scale": gr["scale"], "pos": gc + gr["off"], "tc": gc,
				"tr": 42.0, "lr": 96.0, "pack": &"spider_brood",
				"hp": gr["hp"], "dmg": gr["dmg"], "h": gr["h"], "rad": gr["rad"], "aggro": 22.0, "run_spd": gr["spd"],
			})
	var webwood_delta := Vector2.ZERO
	if _terrain != null and _terrain.has_method("get_webwood_center"):
		webwood_delta = _terrain.call("get_webwood_center") - WorldLandmarks.SPIDER_FOREST_CENTER
	var arch_map := {
		"Alpha Dire Wolf": wolf_alpha_archetype,
		"Timber Wolf": wolf_timber_archetype,
		"Broodmother Spider": spider_broodmother_archetype,
		"Webwood Weaver": spider_weaver_archetype,
		"Brood Spiderling": spider_spiderling_archetype,
		"Plague Rat King": rat_king_archetype,
		"Sewer Rat": rat_sewer_archetype,
	}
	for bm in beast_specs:
		var arch: ActorArchetype = arch_map.get(bm["name"], null)
		var b_pos: Vector2 = bm["pos"]
		var b_tc: Vector2 = bm["tc"]
		if bm["pack"] == &"spider_brood" and not webwood_delta.is_zero_approx():
			b_pos += webwood_delta
			b_tc += webwood_delta
		var b_cfg := {
			"name": bm["name"],
			"category": "mob",
			"glb": arch.glb_path if (arch != null and not arch.glb_path.is_empty()) else bm["glb"],
			"scale": arch.scale_factor if arch != null else bm["scale"],
			"faction": LivingActor.Faction.HOSTILE,
			"role": LivingActor.RoleKind.BEAST,
			"attack_kind": LivingActor.AttackKind.MELEE,
			"pos_xz": b_pos,
			"tc": b_tc,
			"tr": bm["tr"],
			"lr": bm["lr"],
			"pack": bm["pack"],
			"sub": bm.get("sub", 0),
			"hp": arch.max_hp if arch != null else bm["hp"],
			"walk_spd": arch.walk_speed if arch != null else float(bm.get("walk_spd", 3.0)),
			"run_spd": arch.run_speed if arch != null else float(bm.get("run_spd", 6.6)),
			"range": 1.9,
			"aggro": arch.aggro_radius if arch != null else float(bm.get("aggro", 21.0)),
			"dmg": arch.attack_damage if arch != null else bm["dmg"],
			"cd": 1.15,
			"hp_h": arch.hp_bar_height if arch != null else bm["h"],
			"rad": arch.body_radius if arch != null else float(bm.get("rad", 0.62)),
		}
		if bm.has("bmin"):
			b_cfg["bmin"] = bm["bmin"]
			b_cfg["bmax"] = bm["bmax"]
		_spawn_actor(b_cfg)

	var skeleton_specs := [
		# Village Raiders (outside Slimebrook gates)
		{"name": "Skeleton Warrior", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[0] + Vector2(-22, -26)) if gate_outs.size() > 0 else vc + Vector2(-22, -96), "night_only": false},
		{"name": "Skeleton Minion", "glb": "res://assets/mobs/Skeleton_Minion.glb", "eq_r": "res://assets/mobs/Skeleton_Axe.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[2] + Vector2(-24, 16)) if gate_outs.size() > 2 else vc + Vector2(-102, 16), "night_only": false},
		{"name": "Skeleton Marksman", "glb": "res://assets/mobs/Skeleton_Rogue.glb", "eq_r": "res://assets/mobs/Skeleton_Crossbow.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_BOW, "pos": (gate_outs[3] + Vector2(24, -18)) if gate_outs.size() > 3 else vc + Vector2(102, -18), "night_only": false},
		{"name": "Skeleton Necromancer", "glb": "res://assets/mobs/Skeleton_Mage.glb", "eq_r": "res://assets/mobs/Skeleton_Staff.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": (gate_outs[0] + Vector2(24, -30)) if gate_outs.size() > 0 else vc + Vector2(24, -100), "night_only": true},
		{"name": "Skeleton Raider", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[2] + Vector2(-28, -20)) if gate_outs.size() > 2 else vc + Vector2(-104, -20), "night_only": true},
		{"name": "Skeleton Skirmisher", "glb": "res://assets/mobs/Skeleton_Minion.glb", "eq_r": "res://assets/mobs/Skeleton_Axe.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[3] + Vector2(26, 22)) if gate_outs.size() > 3 else vc + Vector2(104, 22), "night_only": true},

		# Second Cave Exterior Sentries (South Crypt Courtyard z >= 329, pack_id="skel_gate")
		{"name": "Crypt Gate Warrior", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": Vector2(-829.0, 331.0), "tc": Vector2(-820.0, 340.0), "tr": 12.0, "lr": 36.0, "pack": &"skel_gate", "night_only": false, "hp": 115.0},
		{"name": "Crypt Gate Scout", "glb": "res://assets/mobs/Skeleton_Rogue.glb", "eq_r": "res://assets/mobs/Skeleton_Crossbow.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_BOW, "pos": Vector2(-811.0, 332.0), "tc": Vector2(-820.0, 340.0), "tr": 12.0, "lr": 36.0, "pack": &"skel_gate", "night_only": false, "hp": 90.0},
		{"name": "Crypt Gate Minion", "glb": "res://assets/mobs/Skeleton_Minion.glb", "eq_r": "res://assets/mobs/Skeleton_Axe.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": Vector2(-820.0, 338.0), "tc": Vector2(-820.0, 340.0), "tr": 12.0, "lr": 36.0, "pack": &"skel_gate", "night_only": false, "hp": 85.0},

		# Subterranean Skeleton Cave Legion (subterranean_kind=1, constrained to Crypt Rooms)
		{"name": "Atrium Bone Guard", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": Vector2(-826.0, 282.0), "tc": Vector2(-820.0, 284.0), "tr": 12.0, "lr": 22.0, "pack": &"skel_crypt", "sub": 1, "bmin": Vector2(-833.0, 271.0), "bmax": Vector2(-807.0, 297.0), "night_only": false, "hp": 125.0},
		{"name": "Atrium Crypt Marksman", "glb": "res://assets/mobs/Skeleton_Rogue.glb", "eq_r": "res://assets/mobs/Skeleton_Crossbow.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_BOW, "pos": Vector2(-813.0, 280.0), "tc": Vector2(-820.0, 284.0), "tr": 12.0, "lr": 22.0, "pack": &"skel_crypt", "sub": 1, "bmin": Vector2(-833.0, 271.0), "bmax": Vector2(-807.0, 297.0), "night_only": false, "hp": 95.0},
		{"name": "Cistern Necro-Acolyte", "glb": "res://assets/mobs/Skeleton_Mage.glb", "eq_r": "res://assets/mobs/Skeleton_Staff.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": Vector2(-844.0, 277.0), "tc": Vector2(-845.0, 277.0), "tr": 9.0, "lr": 16.0, "pack": &"skel_crypt", "sub": 1, "bmin": Vector2(-852.0, 260.0), "bmax": Vector2(-837.0, 287.0), "night_only": false, "hp": 110.0},
		{"name": "Ossuary Stalker", "glb": "res://assets/mobs/Skeleton_Rogue.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": Vector2(-791.0, 278.0), "tc": Vector2(-791.0, 275.0), "tr": 9.0, "lr": 16.0, "pack": &"skel_crypt", "sub": 1, "bmin": Vector2(-802.0, 259.0), "bmax": Vector2(-779.0, 287.0), "night_only": false, "hp": 110.0},
		{"name": "Skeleton Overlord", "glb": "res://assets/mobs/Skeleton_Mage.glb", "eq_r": "res://assets/mobs/Skeleton_Staff.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": Vector2(-820.0, 225.0), "tc": Vector2(-820.0, 232.0), "tr": 12.0, "lr": 20.0, "pack": &"skel_boss", "sub": 1, "bmin": Vector2(-836.0, 215.0), "bmax": Vector2(-804.0, 249.0), "night_only": false, "hp": 340.0, "dmg": 22.0, "scale": 1.18, "hp_h": 3.2},
		{"name": "Overlord Honor Guard", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": Vector2(-828.0, 233.0), "tc": Vector2(-820.0, 232.0), "tr": 12.0, "lr": 20.0, "pack": &"skel_boss", "sub": 1, "bmin": Vector2(-836.0, 215.0), "bmax": Vector2(-804.0, 249.0), "night_only": false, "hp": 145.0, "dmg": 18.0},
		{"name": "Overlord Honor Guard", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": Vector2(-812.0, 233.0), "tc": Vector2(-820.0, 232.0), "tr": 12.0, "lr": 20.0, "pack": &"skel_boss", "sub": 1, "bmin": Vector2(-836.0, 215.0), "bmax": Vector2(-804.0, 249.0), "night_only": false, "hp": 145.0, "dmg": 18.0},
	]
	for sm in skeleton_specs:
		var s_cfg := {
			"name": sm["name"],
			"category": "mob",
			"glb": sm["glb"],
			"scale": sm.get("scale", 0.82),
			"faction": LivingActor.Faction.HOSTILE,
			"role": LivingActor.RoleKind.RAIDER,
			"attack_kind": sm["kind"],
			"pos_xz": sm["pos"],
			"tc": sm.get("tc", sm["pos"]),
			"tr": sm.get("tr", 0.0),
			"lr": sm.get("lr", 0.0),
			"pack": sm.get("pack", &""),
			"sub": sm.get("sub", 0),
			"hp": sm.get("hp", 95.0),
			"walk_spd": 2.8,
			"run_spd": 5.5,
			"range": 13.0 if sm["kind"] != LivingActor.AttackKind.MELEE else 2.0,
			"aggro": 26.0,
			"dmg": sm.get("dmg", 14.0),
			"cd": 1.35,
			"hp_h": sm.get("hp_h", 2.35),
			"eq_r": sm["eq_r"],
			"eq_l": sm["eq_l"],
			"night_only": sm["night_only"],
		}
		if sm.has("bmin"):
			s_cfg["bmin"] = sm["bmin"]
			s_cfg["bmax"] = sm["bmax"]
		_spawn_actor(s_cfg)


func _spawn_actor(cfg: Dictionary) -> LivingActor:
	var category := String(cfg.get("category", "npc"))
	var model_path := _resolve_model_path(cfg)
	if model_path.is_empty():
		push_warning("[WorldEcosystem] no actor model available for category '%s' (%s)" % [category, String(cfg.get("name", "Actor"))])
		return null
	var ps := _load_actor_scene(model_path)
	if ps == null:
		# The configured model exists on disk but failed to import — rotate to another one.
		for _attempt in range(3):
			var alt := model_library.pick(category, model_path)
			if alt.is_empty():
				break
			model_path = alt
			ps = _load_actor_scene(alt)
			if ps != null:
				break
	if ps == null:
		push_warning("[WorldEcosystem] could not load any model for '%s'" % String(cfg.get("name", "Actor")))
		return null
	var model_root := ps.instantiate() as Node3D
	if model_root == null:
		return null
	var s_val: float = float(cfg.get("scale", 1.0))
	model_root.scale = Vector3.ONE * s_val

	var meshes: Array[MeshInstance3D] = []
	_normalize_node_materials(model_root, meshes)
	var anim := _find_anim_player(model_root)
	var skel := _find_skeleton(model_root)

	var eq_r := String(cfg.get("eq_r", ""))
	var eq_l := String(cfg.get("eq_l", ""))
	var muzzle: Node3D = null
	if skel != null:
		if not eq_r.is_empty():
			muzzle = _attach_equipment(skel, "handslot.r", eq_r)
		if not eq_l.is_empty():
			_attach_equipment(skel, "handslot.l", eq_l)

	var actor := LivingActor.new()
	actor.actor_idx = actors.size()
	actor.display_name = String(cfg.get("name", "Actor"))
	actor.category = category
	actor.model_path = model_path
	actor.visual_scale = s_val
	actor.equip_r = eq_r
	actor.equip_l = eq_l
	actor.faction = cfg.get("faction", LivingActor.Faction.NEUTRAL)
	actor.role = cfg.get("role", LivingActor.RoleKind.ARTISAN)
	actor.attack_kind = cfg.get("attack_kind", LivingActor.AttackKind.MELEE)
	actor.is_night_raider = bool(cfg.get("night_only", false))
	var pxz: Vector2 = cfg.get("pos_xz", Vector2.ZERO)
	actor.home_xz = pxz
	actor.territory_center = cfg.get("tc", pxz)
	actor.territory_radius = float(cfg.get("tr", 0.0))
	actor.leash_radius = float(cfg.get("lr", 0.0))
	actor.pack_id = cfg.get("pack", &"")
	actor.subterranean_kind = int(cfg.get("sub", 0))
	if cfg.has("bmin") and cfg.has("bmax"):
		actor.has_room_bounds = true
		actor.room_min_xz = cfg["bmin"] as Vector2
		actor.room_max_xz = cfg["bmax"] as Vector2
	var patrol_arr: Array[Vector2] = []
	for pt_v in cfg.get("patrol", []):
		patrol_arr.append(pt_v as Vector2)
	actor.patrol_points = patrol_arr
	actor.max_hp = float(cfg.get("hp", 100.0))
	actor.hp = actor.max_hp
	actor.move_speed = float(cfg.get("walk_spd", 2.6))
	actor.run_speed = float(cfg.get("run_spd", 5.5))
	actor.attack_range = float(cfg.get("range", 2.0))
	actor.aggro_range = float(cfg.get("aggro", 20.0))
	actor.attack_damage = float(cfg.get("dmg", 14.0))
	actor.attack_cooldown = float(cfg.get("cd", 1.25))
	actor.hp_bar_height = float(cfg.get("hp_h", 2.35))
	actor.body_radius = float(cfg.get("rad", 0.55))
	if cfg.has("work"):
		actor.work_anim_hint = String(cfg["work"])
	if cfg.has("yaw"):
		var yw := float(cfg["yaw"])
		actor.initial_facing_yaw = yw
		actor.has_initial_facing = true
		actor.facing_hint_yaw = yw
		actor.has_facing_hint = true
		actor.rotation.y = yw
	if bool(cfg.get("start_work", false)):
		actor.ai_state = LivingActor.AIState.SCHEDULE_WORK
		actor._state_timer = randf_range(5.0, 9.5)

	var gy := sample_ground_y(pxz.x, pxz.y, actor.role == LivingActor.RoleKind.FISHERMAN, actor.subterranean_kind)
	actor.position = Vector3(pxz.x, gy, pxz.y)
	add_child(actor)
	actor.setup_visuals(model_root, anim, meshes, muzzle)

	if actor.is_night_raider:
		var night_now := _time_weather != null and _time_weather.is_night
		if not night_now:
			actor.visible = false
			actor.ai_state = LivingActor.AIState.DEAD
			actor._respawn_timer = 2.0

	actors.append(actor)
	if actor.faction == LivingActor.Faction.VILLAGE:
		_village_actors.append(actor)
	elif actor.faction == LivingActor.Faction.HOSTILE:
		_hostile_actors.append(actor)
	return actor


## Validates a configured model path against the auto-detected library and, when the
## file is gone, silently substitutes another model of the same category.
func _resolve_model_path(cfg: Dictionary) -> String:
	var want := String(cfg.get("glb", ""))
	if want.is_empty():
		return model_library.pick(String(cfg.get("category", "npc")))
	if model_library.is_known(want) or ResourceLoader.exists(want):
		return want
	var replacement := model_library.pick(String(cfg.get("category", "npc")), want)
	if not replacement.is_empty():
		push_warning("[WorldEcosystem] missing model %s -> using %s" % [want, replacement])
	else:
		push_warning("[WorldEcosystem] missing model %s and no replacement in its category" % want)
	return replacement


func _load_actor_scene(path: String) -> PackedScene:
	var ps: PackedScene = model_library.scene(path) as PackedScene
	if ps == null and not path.is_empty():
		ps = load(path) as PackedScene
	return ps


## Paths inside `category` that no live actor is currently showing.
func _free_model_paths(category: String) -> PackedStringArray:
	var used := {}
	for a in actors:
		if a != null and is_instance_valid(a) and a.category == category and not a.model_path.is_empty():
			used[a.model_path] = true
	var out := PackedStringArray()
	for p in model_library.pool(category):
		if not used.has(p):
			out.append(p)
	return out


## Respawn rotator: swaps `actor` onto a different free model of its category,
## rebuilding meshes, animation map and equipment. Returns false when nothing
## better was available (e.g. a category with a single model).
func reroll_actor_model(actor: LivingActor) -> bool:
	if actor == null or not is_instance_valid(actor) or actor.category.is_empty():
		return false
	var next_path := ""
	var family: PackedStringArray = model_library.family_members(actor.model_path)
	if family.is_empty():
		family = model_library.pool(actor.category)
	var free_all := _free_model_paths(actor.category)
	var free_family := PackedStringArray()
	for p in family:
		if free_all.has(p):
			free_family.append(p)

	# Prefer an unused sibling (Rogue -> Rogue_Hooded), then any sibling.
	next_path = model_library.pick(actor.category, actor.model_path, free_family, actor._rng)
	if next_path.is_empty():
		next_path = model_library.pick(actor.category, actor.model_path, family, actor._rng)
	if next_path.is_empty() or next_path == actor.model_path:
		return false
	var ps := _load_actor_scene(next_path)
	if ps == null:
		return false
	var model_root := ps.instantiate() as Node3D
	if model_root == null:
		return false

	model_root.scale = Vector3.ONE * actor.visual_scale
	var meshes: Array[MeshInstance3D] = []
	_normalize_node_materials(model_root, meshes)
	var anim := _find_anim_player(model_root)
	var skel := _find_skeleton(model_root)

	var muzzle: Node3D = null
	if skel != null:
		if not actor.equip_r.is_empty():
			muzzle = _attach_equipment(skel, "handslot.r", actor.equip_r)
		if not actor.equip_l.is_empty():
			_attach_equipment(skel, "handslot.l", actor.equip_l)

	actor.install_visuals(model_root, anim, meshes, muzzle)
	actor.model_path = next_path
	return true


func _normalize_node_materials(node: Node, out_meshes: Array[MeshInstance3D] = [], vis_end: float = 165.0, vis_margin: float = 16.0) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var dup := mi.mesh.duplicate() as Mesh
			for si in range(dup.get_surface_count()):
				var sm := dup.surface_get_material(si)
				dup.surface_set_material(si, _to_actor_matte(sm))
			mi.mesh = dup
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = vis_margin
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		out_meshes.append(mi)
	for ch in node.get_children():
		_normalize_node_materials(ch, out_meshes, vis_end, vis_margin)


func _to_actor_matte(src: Material) -> Material:
	if src == null:
		return null
	var mname := src.resource_name.to_lower()
	if mname.contains("glow"):
		return _mat_glow_eye
	var tex: Texture2D = null
	var col := Color.WHITE
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		tex = bm.albedo_texture
		col = bm.albedo_color
	var key := "%s::%s" % [tex.resource_path if tex != null else "notex", col.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key] as Material

	var sm := ShaderMaterial.new()
	sm.shader = _actor_shader
	sm.set_shader_parameter("albedo_color", col)
	if tex != null:
		sm.set_shader_parameter("use_tex", true)
		sm.set_shader_parameter("albedo_tex", tex)
	else:
		sm.set_shader_parameter("use_tex", false)
	_mat_cache[key] = sm
	return sm


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for ch in n.get_children():
		var found := _find_anim_player(ch)
		if found != null:
			return found
	return null


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for ch in n.get_children():
		var found := _find_skeleton(ch)
		if found != null:
			return found
	return null


func _attach_equipment(skel: Skeleton3D, bone_name: String, res_path: String) -> Node3D:
	if skel.find_bone(bone_name) < 0:
		return null
	var mesh_node := _get_normalized_weapon(res_path)
	if mesh_node == null:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone_name
	skel.add_child(ba)
	var inst := mesh_node.duplicate() as Node3D
	ba.add_child(inst)
	return ba


func _get_normalized_weapon(res_path: String) -> Node3D:
	if _weapon_cache.has(res_path):
		return _weapon_cache[res_path] as Node3D
	var ps := load(res_path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	if inst != null:
		var w_meshes: Array[MeshInstance3D] = []
		_normalize_node_materials(inst, w_meshes, 85.0, 10.0)
		_weapon_cache[res_path] = inst
	return inst


func _process(delta: float) -> void:
	if actors.is_empty():
		return
	var dt := minf(delta, 0.05)
	_frame_counter += 1
	_village_provoked_timer = maxf(0.0, _village_provoked_timer - dt)

	var rain_val := _time_weather.rain_intensity if _time_weather != null else 0.0
	var night_val := _time_weather.is_night if _time_weather != null else false
	var provoked := _village_provoked_timer > 0.0

	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	var cam_pos := cam.global_position if cam != null else (player_slime.global_position if player_slime != null else Vector3.ZERO)
	var cave_hidden := false
	var in_extra_cave := false
	if _cave_atm != null and "get" in _cave_atm:
		var ec_v: Variant = _cave_atm.get("_in_extra_cave")
		in_extra_cave = ec_v != null and bool(ec_v)
		var cf: Variant = _cave_atm.get("_cave_factor")
		if cf != null and float(cf) > 0.72 and not in_extra_cave:
			cave_hidden = true
	if visible == cave_hidden:
		visible = not cave_hidden

	# Rebuild 6 m spatial hash in place for O(1) crowd separation & slime slam checks
	for b in _spatial_grid.values():
		(b as Array).clear()
	for act in actors:
		if not act.is_alive():
			continue
		var c := _cell_of(Vector2(act.global_position.x, act.global_position.z))
		var bucket: Variant = _spatial_grid.get(c)
		if bucket == null:
			_spatial_grid[c] = [act]
		else:
			(bucket as Array).append(act)

	# Step actor AI (throttled when deep underground or far > 160m outside combat) & LOD-sliced animations
	for act in actors:
		var d_sq := cam_pos.distance_squared_to(act.global_position)
		var act_hidden := cave_hidden or (in_extra_cave and act.subterranean_kind == 0 and d_sq > 1225.0)
		var high_rate := (not act_hidden and d_sq < 25600.0) or act.ai_state == LivingActor.AIState.CHASE or act.ai_state == LivingActor.AIState.ATTACK or act.ai_state == LivingActor.AIState.FLEE
		if high_rate:
			var step_dt := dt + act._ai_accum_dt
			act._ai_accum_dt = 0.0
			act.step_ai(step_dt, self, rain_val, night_val, provoked)
		else:
			act._ai_accum_dt += dt
			if ((act.actor_idx + _frame_counter) % 6) == 0:
				var step_dt := act._ai_accum_dt
				act._ai_accum_dt = 0.0
				act.step_ai(step_dt, self, rain_val, night_val, provoked)
		act.step_animation_lod(dt, d_sq, _frame_counter, act_hidden)

	_check_slime_body_slam()
	_step_projectiles(dt)
	_update_hp_bars(cam_pos, cave_hidden)


func _cell_of(pos_xz: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos_xz.x / SPATIAL_CELL_SIZE)), int(floor(pos_xz.y / SPATIAL_CELL_SIZE)))


func find_nearest_enemy_in_radius(pos_xz: Vector2, target_faction: int, radius: float) -> LivingActor:
	var best: LivingActor = null
	var best_sq := radius * radius
	var pool: Array[LivingActor] = _village_actors if target_faction == LivingActor.Faction.VILLAGE else (_hostile_actors if target_faction == LivingActor.Faction.HOSTILE else actors)
	for act in pool:
		if act.faction != target_faction or not act.is_alive():
			continue
		var axz := Vector2(act.global_position.x, act.global_position.z)
		var dsq := pos_xz.distance_squared_to(axz)
		if dsq < best_sq:
			best_sq = dsq
			best = act
	return best


func compute_separation(self_actor: LivingActor, pos_xz: Vector2) -> Vector2:
	var push := Vector2.ZERO
	var base := _cell_of(pos_xz)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var c := Vector2i(base.x + dx, base.y + dz)
			if not _spatial_grid.has(c):
				continue
			var bucket := _spatial_grid[c] as Array
			for item in bucket:
				var other := item as LivingActor
				if other == self_actor:
					continue
				var oxz := Vector2(other.global_position.x, other.global_position.z)
				var dvec := pos_xz - oxz
				var min_d := self_actor.body_radius + other.body_radius
				var dsq := dvec.length_squared()
				if dsq < min_d * min_d:
					if dsq > 0.0001:
						var d := sqrt(dsq)
						push += (dvec / d) * ((min_d - d) / min_d)
					else:
						push += Vector2(0.5, 0.5)
	return push


func _check_slime_body_slam() -> void:
	if player_slime == null or not is_instance_valid(player_slime) or player_slime.is_dead or player_slime.motor == null:
		return
	var sl_pos := player_slime.global_position
	var sl_xz := Vector2(sl_pos.x, sl_pos.z)
	var sl_vel := player_slime.motor.velocity
	var horiz_spd := Vector2(sl_vel.x, sl_vel.z).length()
	var vert_spd := player_slime.motor.vertical_vel
	var is_slamming := (horiz_spd > 5.8) or (vert_spd < -3.2)
	if not is_slamming:
		return

	var slam_rad := 1.45 * player_slime.slime_scale
	var base := _cell_of(sl_xz)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var c := Vector2i(base.x + dx, base.y + dz)
			if not _spatial_grid.has(c):
				continue
			for item in (_spatial_grid[c] as Array):
				var act := item as LivingActor
				if not act.is_alive() or act._slam_grace > 0.0:
					continue
				if absf(act.global_position.y + 0.8 - sl_pos.y) > 2.6 * player_slime.slime_scale:
					continue
				var axz := Vector2(act.global_position.x, act.global_position.z)
				var reach := slam_rad + act.body_radius
				if sl_xz.distance_squared_to(axz) <= reach * reach:
					act._slam_grace = 0.55
					var push_dir := (axz - sl_xz).normalized() if sl_xz.distance_squared_to(axz) > 0.001 else Vector2(1.0, 0.0)
					var dmg := (22.0 + horiz_spd * 2.4 + maxf(-vert_spd, 0.0) * 1.8) * player_slime.slime_scale
					act.vertical_vel = maxf(act.vertical_vel, 4.8)
					act.apply_damage(dmg, push_dir * 8.5, player_slime, true)
					if act.faction == LivingActor.Faction.VILLAGE:
						provoke_village(24.0)
					player_slime.motor.vertical_vel = maxf(player_slime.motor.vertical_vel, 5.2)
					player_slime.trigger_poke(Vector3(0.0, -0.3, 0.0), Vector3(-push_dir.x * 0.4, -0.6, -push_dir.y * 0.4))


func provoke_village(duration: float = 24.0) -> void:
	_village_provoked_timer = maxf(_village_provoked_timer, duration)


func damage_player_slime(slime: Slime, impulse: Vector3, volume_loss: float, attacker_name: String) -> void:
	if slime == null or not is_instance_valid(slime) or slime.is_dead:
		return
	if slime.has_method("apply_combat_hit"):
		slime.call("apply_combat_hit", volume_loss, impulse, attacker_name)


func _on_slime_defeated_actor(act: LivingActor) -> void:
	if player_slime != null and is_instance_valid(player_slime) and not player_slime.is_dead:
		player_slime.add_volume(0.45)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_toast"):
			hud.call("show_toast", "Defeated %s (+Mass)" % act.display_name, Color(0.56, 0.98, 0.68), 2.2)


func spawn_projectile(shooter: LivingActor, origin: Vector3, dir: Vector3, is_spell: bool, dmg: float) -> void:
	for p in _projectiles:
		if not bool(p["active"]):
			var node := p["node"] as Node3D
			node.visible = true
			node.global_position = origin
			var d := dir.normalized()
			if absf(d.y) < 0.98:
				node.look_at(origin + d, Vector3.UP)
			p["active"] = true
			p["vel"] = d * (20.0 if is_spell else 26.0)
			p["life"] = 2.4
			p["dmg"] = dmg
			p["faction"] = shooter.faction
			p["shooter"] = shooter
			p["is_spell"] = is_spell
			var arrow_n := p["arrow"] as Node3D
			if arrow_n != null:
				arrow_n.visible = not is_spell
			(p["bolt"] as MeshInstance3D).visible = is_spell
			return


func _step_projectiles(dt: float) -> void:
	var sl := player_slime
	var sl_valid := sl != null and is_instance_valid(sl) and not sl.is_dead
	var sl_pos := sl.global_position + Vector3(0.0, 0.65 * sl.slime_scale, 0.0) if sl_valid else Vector3.ZERO
	var sl_rad := 1.1 * sl.slime_scale if sl_valid else 1.0

	for p in _projectiles:
		if not bool(p["active"]):
			continue
		p["life"] = float(p["life"]) - dt
		if float(p["life"]) <= 0.0:
			p["active"] = false
			(p["node"] as Node3D).visible = false
			continue
		var node := p["node"] as Node3D
		var vel: Vector3 = p["vel"]
		if not bool(p["is_spell"]):
			vel.y -= 5.2 * dt
			p["vel"] = vel
		var next_pos := node.global_position + vel * dt
		if vel.length_squared() > 0.01:
			node.look_at(next_pos, Vector3.UP)
		node.global_position = next_pos

		# Check Slime hit
		var sf: int = int(p["faction"])
		if sl_valid and (sf == LivingActor.Faction.HOSTILE or (sf == LivingActor.Faction.VILLAGE and _village_provoked_timer > 0.0)):
			if next_pos.distance_squared_to(sl_pos) <= sl_rad * sl_rad:
				var d_xz := Vector2(vel.x, vel.z).normalized()
				damage_player_slime(sl, Vector3(d_xz.x * 4.5, 1.8, d_xz.y * 4.5), float(p["dmg"]) * 0.038, "an enemy archer")
				p["active"] = false
				node.visible = false
				continue

		# Check Actor hit via spatial hash cell
		var enemy_f := LivingActor.Faction.VILLAGE if sf == LivingActor.Faction.HOSTILE else LivingActor.Faction.HOSTILE
		var hit := find_nearest_enemy_in_radius(Vector2(next_pos.x, next_pos.z), enemy_f, 1.05)
		if hit != null and absf(next_pos.y - (hit.global_position.y + 1.0)) < 1.25:
			var push := Vector2(vel.x, vel.z).normalized() * 3.8
			hit.apply_damage(float(p["dmg"]), push, p["shooter"] as Node, false)
			p["active"] = false
			node.visible = false
			continue

		if next_pos.y <= sample_ground_y(next_pos.x, next_pos.z, false):
			p["active"] = false
			node.visible = false


func _update_hp_bars(cam_pos: Vector3, cave_hidden: bool) -> void:
	if _hp_bar_mm == null or _hp_bar_mm.multimesh == null:
		return
	var mm := _hp_bar_mm.multimesh
	if cave_hidden:
		mm.visible_instance_count = 0
		return
	var count := 0
	for act in actors:
		if not act.is_alive():
			continue
		if act.hp >= act.max_hp * 0.99 and act._combat_show_timer <= 0.0:
			continue
		if cam_pos.distance_squared_to(act.global_position) > 784.0:  # > 28 m
			continue
		var frac := clampf(act.hp / maxf(act.max_hp, 1.0), 0.02, 1.0)
		var bar_pos := act.global_position + Vector3(0.0, act.hp_bar_height, 0.0)
		var xf := Transform3D(Basis().scaled(Vector3(frac, 1.0, 1.0)), bar_pos)
		mm.set_instance_transform(count, xf)
		var col := Color(0.28, 0.90, 0.42) if act.faction == LivingActor.Faction.VILLAGE else Color(0.95, 0.28, 0.28)
		mm.set_instance_color(count, col)
		count += 1
		if count >= MAX_HP_BARS:
			break
	mm.visible_instance_count = count


func rally_pack(caller: LivingActor, enemy_actor: LivingActor, enemy_slime: Slime) -> void:
	if caller == null or caller.pack_id.is_empty():
		return
	var c_pos := Vector2(caller.global_position.x, caller.global_position.z)
	for act in _hostile_actors:
		if act == caller or not act.is_alive() or act.pack_id != caller.pack_id:
			continue
		if c_pos.distance_squared_to(Vector2(act.global_position.x, act.global_position.z)) <= 1024.0: # <= 32 m
			if act.target_slime == null and act.target_actor == null:
				act.target_actor = enemy_actor
				act.target_slime = enemy_slime
				act.ai_state = LivingActor.AIState.CHASE


func sample_ground_y(x: float, z: float, support_dock: bool, subterranean_kind: int = 0) -> float:
	if subterranean_kind == 1:
		return WorldLandmarks.sample_skeleton_cave_floor(x, z).w
	if subterranean_kind == 2:
		return WorldLandmarks.sample_rat_warren_floor(z, x).w
	var ty := 0.0
	if _terrain != null and _terrain.has_method("sample_height"):
		ty = float(_terrain.call("sample_height", x, z))
	if support_dock:
		if not _dock_cache_done and _village_root != null:
			_dock_cache_done = true
			if _village_root.has_meta("dock_shore_xy"):
				_has_dock = true
				_dock_shore_xy = _village_root.get_meta("dock_shore_xy") as Vector2
				var dyaw := float(_village_root.get_meta("dock_yaw", 0.0))
				_dock_fwd = Vector2(sin(dyaw), cos(dyaw))
				_dock_right = Vector2(_dock_fwd.y, -_dock_fwd.x)
		if _has_dock:
			var rel := Vector2(x, z) - _dock_shore_xy
			var along := rel.dot(_dock_fwd)
			var across := absf(rel.dot(_dock_right))
			# Keep Harbor Fisherman smoothly elevated onto Wharf Entry / Wharf (y=1.73) and Pier Deck (y=1.65)
			if along > -10.8 and along < 21.6 and across < 4.5:
				var deck_y := 1.73 if along < -3.5 else 1.65
				ty = maxf(ty, deck_y)
	return ty


func get_ecosystem_stats() -> Dictionary:
	var alive_n := 0
	var npcs := 0
	var animals := 0
	var mobs := 0
	var fighting := 0
	for act in actors:
		if act.is_alive():
			alive_n += 1
			match act.category:
				"npc": npcs += 1
				"animal": animals += 1
				"mob": mobs += 1
			if act.ai_state == LivingActor.AIState.CHASE or act.ai_state == LivingActor.AIState.ATTACK:
				fighting += 1
	return {
		"total_alive": alive_n,
		"npcs": npcs,
		"animals": animals,
		"mobs": mobs,
		"fighting": fighting,
		"provoked": _village_provoked_timer > 0.0,
	}
