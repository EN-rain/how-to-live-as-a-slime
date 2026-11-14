class_name WorldEcosystem
extends Node3D
## Manages all Human NPCs, Wildlife/Livestock, Hostile Mobs, combat projectiles,
## billboard HP bars, VillageNavGraph routing, and Mobile animation LOD slicing.

const SPATIAL_CELL_SIZE := 6.0
const PROJ_POOL_SIZE := 16
const MAX_HP_BARS := 32

var nav_graph := VillageNavGraph.new()
var actors: Array[LivingActor] = []
var player_slime: Slime = null

var _terrain: Node = null
var _village_root: Node = null
var _time_weather: WorldTimeWeather = null
var _cave_atm: Node = null
var _actor_shader := preload("res://shaders/actor_matte.gdshader")
var _mat_cache: Dictionary = {}
var _weapon_cache: Dictionary = {}
var _mat_glow_eye: StandardMaterial3D
var _spatial_grid: Dictionary = {}  # Vector2i -> Array[LivingActor]

var _village_provoked_timer: float = 0.0
var _frame_counter: int = 0

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
	_spawn_all_populations()


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

	# --- 1. 8 Town Guards (Knight sword/shield + Rogue crossbowmen) ---
	for i in range(8):
		var is_ranged := (i == 2 or i == 6)
		var glb := "res://assets/npcs/Rogue.glb" if is_ranged else "res://assets/npcs/Knight.glb"
		var start_xz: Vector2 = guard_posts[i % guard_posts.size()] if not guard_posts.is_empty() else vc
		var patrol: Array[Vector2] = []
		if not guard_posts.is_empty():
			for step in range(4):
				patrol.append(guard_posts[(i + step) % guard_posts.size()])
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

	# --- 2. 8 Villagers (Merchants, Artisans, Fisherman) ---
	var villager_defs := [
		{"name": "Market Merchant", "glb": "res://assets/npcs/Rogue_Hooded.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "res://assets/npcs/mug_full.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[0]["pos"] if stalls.size() > 0 else vc + Vector2(-10, -8)},
		{"name": "Produce Vendor", "glb": "res://assets/npcs/Rogue.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[1]["pos"] if stalls.size() > 1 else vc + Vector2(10, -8)},
		{"name": "Inn Patron", "glb": "res://assets/npcs/Barbarian.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/mug_full.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": vc + Vector2(-8.0, -18.0)},
		{"name": "Village Blacksmith", "glb": "res://assets/npcs/Barbarian.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/axe_1handed.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": vc + Vector2(22.0, 12.0)},
		{"name": "Town Apothecary", "glb": "res://assets/npcs/Mage.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/staff.gltf", "eq_l": "res://assets/npcs/spellbook_open.gltf", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": vc + Vector2(-22.0, 12.0)},
		{"name": "Court Scholar", "glb": "res://assets/npcs/Mage.glb", "role": LivingActor.RoleKind.ARTISAN, "eq_r": "res://assets/npcs/spellbook_open.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": socials[0]["pos"] if socials.size() > 0 else vc},
		{"name": "Spice Trader", "glb": "res://assets/npcs/Rogue_Hooded.glb", "role": LivingActor.RoleKind.MERCHANT, "eq_r": "res://assets/npcs/dagger.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": stalls[2]["pos"] if stalls.size() > 2 else vc + Vector2(-10, 8)},
		{"name": "Harbor Fisherman", "glb": "res://assets/npcs/Rogue.glb", "role": LivingActor.RoleKind.FISHERMAN, "eq_r": "", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": fisher_route[fisher_route.size() - 1] if not fisher_route.is_empty() else vc + Vector2(80, 120), "patrol": fisher_route},
	]
	for vd in villager_defs:
		_spawn_actor({
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
		})

	# --- 3. 12 Animals (Livestock in Village Paddocks + Wild Deer/Stags/Foxes in Meadows) ---
	var livestock := [
		{"name": "Village Cow", "glb": "res://assets/animals/Cow.glb", "scale": 0.36, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[0] if paddocks.size() > 0 else vc + Vector2(-44, 68)},
		{"name": "Spotted Cow", "glb": "res://assets/animals/Cow.glb", "scale": 0.35, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[1] if paddocks.size() > 1 else vc + Vector2(44, 68)},
		{"name": "Chestnut Horse", "glb": "res://assets/animals/Horse.glb", "scale": 0.43, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[2] if paddocks.size() > 2 else vc + Vector2(-78, -28)},
		{"name": "White Horse", "glb": "res://assets/animals/Horse_White.glb", "scale": 0.43, "role": LivingActor.RoleKind.ANIMAL, "pos": paddocks[3] if paddocks.size() > 3 else vc + Vector2(78, -28)},
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

	# --- 4. 12 Hostile Mobs (Forest Wolves, Spiders, Rats + Skeleton Raiders) ---
	var beast_specs := [
		{"name": "Timber Wolf", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.38, "pos": Vector2(475.0, 2145.0), "hp": 85.0, "dmg": 14.0, "h": 1.25},
		{"name": "Timber Wolf", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.39, "pos": Vector2(695.0, 2150.0), "hp": 85.0, "dmg": 14.0, "h": 1.25},
		{"name": "Valley Wolf", "glb": "res://assets/mobs/Wolf.glb", "scale": 0.38, "pos": Vector2(125.0, 120.0), "hp": 85.0, "dmg": 14.0, "h": 1.25},
		{"name": "Forest Spider", "glb": "res://assets/mobs/Spider.glb", "scale": 0.28, "pos": Vector2(-88.0, 95.0), "hp": 70.0, "dmg": 12.0, "h": 0.95},
		{"name": "Cavern Spider", "glb": "res://assets/mobs/Spider.glb", "scale": 0.30, "pos": Vector2(490.0, 2310.0), "hp": 75.0, "dmg": 13.0, "h": 0.95},
		{"name": "Giant Rat", "glb": "res://assets/mobs/Rat.glb", "scale": 0.38, "pos": Vector2(665.0, 2315.0), "hp": 45.0, "dmg": 9.0, "h": 0.75},
	]
	for bm in beast_specs:
		_spawn_actor({
			"name": bm["name"],
			"category": "mob",
			"glb": bm["glb"],
			"scale": bm["scale"],
			"faction": LivingActor.Faction.HOSTILE,
			"role": LivingActor.RoleKind.BEAST,
			"attack_kind": LivingActor.AttackKind.MELEE,
			"pos_xz": bm["pos"],
			"hp": bm["hp"],
			"walk_spd": 2.9,
			"run_spd": 6.4,
			"range": 1.9,
			"aggro": 20.0,
			"dmg": bm["dmg"],
			"cd": 1.15,
			"hp_h": bm["h"],
			"rad": 0.62,
		})

	var skeleton_specs := [
		{"name": "Skeleton Warrior", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[0] + Vector2(-22, -26)) if gate_outs.size() > 0 else vc + Vector2(-22, -96), "night_only": false},
		{"name": "Skeleton Minion", "glb": "res://assets/mobs/Skeleton_Minion.glb", "eq_r": "res://assets/mobs/Skeleton_Axe.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[2] + Vector2(-24, 16)) if gate_outs.size() > 2 else vc + Vector2(-102, 16), "night_only": false},
		{"name": "Skeleton Marksman", "glb": "res://assets/mobs/Skeleton_Rogue.glb", "eq_r": "res://assets/mobs/Skeleton_Crossbow.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_BOW, "pos": (gate_outs[3] + Vector2(24, -18)) if gate_outs.size() > 3 else vc + Vector2(102, -18), "night_only": false},
		{"name": "Skeleton Necromancer", "glb": "res://assets/mobs/Skeleton_Mage.glb", "eq_r": "res://assets/mobs/Skeleton_Staff.gltf", "eq_l": "", "kind": LivingActor.AttackKind.RANGED_SPELL, "pos": (gate_outs[0] + Vector2(24, -30)) if gate_outs.size() > 0 else vc + Vector2(24, -100), "night_only": true},
		{"name": "Skeleton Raider", "glb": "res://assets/mobs/Skeleton_Warrior.glb", "eq_r": "res://assets/mobs/Skeleton_Blade.gltf", "eq_l": "res://assets/mobs/Skeleton_Shield_Large_A.gltf", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[2] + Vector2(-28, -20)) if gate_outs.size() > 2 else vc + Vector2(-104, -20), "night_only": true},
		{"name": "Skeleton Skirmisher", "glb": "res://assets/mobs/Skeleton_Minion.glb", "eq_r": "res://assets/mobs/Skeleton_Axe.gltf", "eq_l": "", "kind": LivingActor.AttackKind.MELEE, "pos": (gate_outs[3] + Vector2(26, 22)) if gate_outs.size() > 3 else vc + Vector2(104, 22), "night_only": true},
	]
	for sm in skeleton_specs:
		_spawn_actor({
			"name": sm["name"],
			"category": "mob",
			"glb": sm["glb"],
			"scale": 0.82,
			"faction": LivingActor.Faction.HOSTILE,
			"role": LivingActor.RoleKind.RAIDER,
			"attack_kind": sm["kind"],
			"pos_xz": sm["pos"],
			"hp": 95.0,
			"walk_spd": 2.8,
			"run_spd": 5.5,
			"range": 13.0 if sm["kind"] != LivingActor.AttackKind.MELEE else 2.0,
			"aggro": 26.0,
			"dmg": 14.0,
			"cd": 1.35,
			"eq_r": sm["eq_r"],
			"eq_l": sm["eq_l"],
			"night_only": sm["night_only"],
		})


func _spawn_actor(cfg: Dictionary) -> LivingActor:
	var ps := load(String(cfg["glb"])) as PackedScene
	if ps == null:
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
	actor.category = String(cfg.get("category", "npc"))
	actor.faction = cfg.get("faction", LivingActor.Faction.NEUTRAL)
	actor.role = cfg.get("role", LivingActor.RoleKind.ARTISAN)
	actor.attack_kind = cfg.get("attack_kind", LivingActor.AttackKind.MELEE)
	actor.is_night_raider = bool(cfg.get("night_only", false))
	var pxz: Vector2 = cfg.get("pos_xz", Vector2.ZERO)
	actor.home_xz = pxz
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

	var gy := sample_ground_y(pxz.x, pxz.y, actor.role == LivingActor.RoleKind.FISHERMAN)
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
	return actor


func _normalize_node_materials(node: Node, out_meshes: Array[MeshInstance3D] = []) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var dup := mi.mesh.duplicate() as Mesh
			for si in range(dup.get_surface_count()):
				var sm := dup.surface_get_material(si)
				dup.surface_set_material(si, _to_actor_matte(sm))
			mi.mesh = dup
		out_meshes.append(mi)
	for ch in node.get_children():
		_normalize_node_materials(ch, out_meshes)


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
		_normalize_node_materials(inst)
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
	if _cave_atm != null and "get" in _cave_atm:
		var cf: Variant = _cave_atm.get("_cave_factor")
		if cf != null and float(cf) > 0.72:
			cave_hidden = true

	# Rebuild 6 m spatial hash for O(1) separation & enemy scanning
	_spatial_grid.clear()
	for act in actors:
		if not act.is_alive():
			continue
		var c := _cell_of(Vector2(act.global_position.x, act.global_position.z))
		if not _spatial_grid.has(c):
			_spatial_grid[c] = [act]
		else:
			(_spatial_grid[c] as Array).append(act)

	# Step actor AI & LOD-sliced animations
	for act in actors:
		act.step_ai(dt, self, rain_val, night_val, provoked)
		var d_sq := cam_pos.distance_squared_to(act.global_position)
		act.step_animation_lod(dt, d_sq, _frame_counter, cave_hidden)

	_check_slime_body_slam()
	_step_projectiles(dt)
	_update_hp_bars(cam_pos, cave_hidden)


func _cell_of(pos_xz: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos_xz.x / SPATIAL_CELL_SIZE)), int(floor(pos_xz.y / SPATIAL_CELL_SIZE)))


func find_nearest_enemy_in_radius(pos_xz: Vector2, target_faction: int, radius: float) -> LivingActor:
	var best: LivingActor = null
	var best_sq := radius * radius
	var cr := int(ceil(radius / SPATIAL_CELL_SIZE))
	var base := _cell_of(pos_xz)
	for dx in range(-cr, cr + 1):
		for dz in range(-cr, cr + 1):
			var c := Vector2i(base.x + dx, base.y + dz)
			if not _spatial_grid.has(c):
				continue
			var bucket := _spatial_grid[c] as Array
			for item in bucket:
				var act := item as LivingActor
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


func sample_ground_y(x: float, z: float, support_dock: bool) -> float:
	var ty := 0.0
	if _terrain != null and _terrain.has_method("sample_height"):
		ty = float(_terrain.call("sample_height", x, z))
	if support_dock and _village_root != null and _village_root.has_meta("dock_shore_xy"):
		var shore := _village_root.get_meta("dock_shore_xy") as Vector2
		var dyaw := float(_village_root.get_meta("dock_yaw", 0.0))
		var rel := Vector2(x, z) - shore
		var fwd := Vector2(sin(dyaw), cos(dyaw))
		var right := Vector2(fwd.y, -fwd.x)
		var along := rel.dot(fwd)
		var across := absf(rel.dot(right))
		# Keep Harbor Fisherman smoothly elevated onto the Wharf & T-Head Pier timber deck
		if along > -11.5 and along < 20.0 and across < 4.5:
			ty = maxf(ty, 1.32)
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
