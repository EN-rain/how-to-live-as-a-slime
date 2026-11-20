@tool
class_name DungeonCaveBuilder
extends Node3D
## Highland Barrow Cliff Portal & Procedural Multi-Room Skeleton Catacombs.
## Replaces the old pasted pit and static cross layout with a natural forested rock barrow
## entrance descending into a seeded non-cross dungeon of 9–11 interconnected vaults, crypts,
## flooded cisterns, ossuaries, spike galleries, a 1.55 m squeeze reliquary, loop corridors,
## and the Overlord Cathedral Sanctum.

const WorldLandmarks := preload("res://scripts/world_landmarks.gd")
const CavePropFX := preload("res://scripts/cave_prop_fx.gd")

const LAYER_TERRAIN := 1
const LAYER_OBSTACLES := 4

const CX := WorldLandmarks.SKEL_CAVE_MOUTH.x
const EXT_Y := WorldLandmarks.SKEL_FORECOURT_Y
const UPPER_Y := WorldLandmarks.SKEL_UPPER_Y
const MID_Y := WorldLandmarks.SKEL_MID_Y
const SANCTUM_Y := WorldLandmarks.SKEL_SANCTUM_Y

const CELL_STEP := 44.0
const CORR_HALF_W := 4.8
const DOOR_W := 9.6
const DOOR_H := 8.0
const CORR_H := 8.4

const RES_BASE := "res://assets/dungeon/"
const NATURE_BASE := "res://assets/nature/"

const DIR_DEFS: Array[Dictionary] = [
	{"name": "n", "opp": "s", "grid": Vector2i(0, 1), "world": Vector2(0.0, -1.0)},
	{"name": "s", "opp": "n", "grid": Vector2i(0, -1), "world": Vector2(0.0, 1.0)},
	{"name": "w", "opp": "e", "grid": Vector2i(-1, 0), "world": Vector2(-1.0, 0.0)},
	{"name": "e", "opp": "w", "grid": Vector2i(1, 0), "world": Vector2(1.0, 0.0)},
]

var _scene_cache: Dictionary = {}
var _crypt_rock_mat: ShaderMaterial = null
var _surface_moss_rock_mat: ShaderMaterial = null
var _crypt_floor_mat: ShaderMaterial = null
var _crypt_ashlar_mat: ShaderMaterial = null
var _crypt_trim_mat: ShaderMaterial = null
var _crypt_iron_mat: Material = null
var _water_cistern_mat: ShaderMaterial = null
var _water_fall_mat: ShaderMaterial = null
var _water_abyss_mat: ShaderMaterial = null
var _stone_props_mat: StandardMaterial3D = null
var _timed_spikes: Array[Dictionary] = []
var _abyss_time: float = 0.0
var crypt_region: Node = null
var _spike_cycle_speed: float = 1.0
var dungeon_seed: int = 0
@export var preview_in_editor: bool = true


func _ready() -> void:
	name = "SkeletonDungeonCave"
	add_to_group("skeleton_dungeon_cave")
	if crypt_region == null and get_parent() != null and get_parent().has_method("get_profile"):
		crypt_region = get_parent()
	if Engine.is_editor_hint() and not preview_in_editor:
		set_process(false)
		return
	if crypt_region != null and crypt_region.has_method("get_profile"):
		var prof: Variant = crypt_region.call("get_profile")
		if prof != null:
			_spike_cycle_speed = float(prof.get("spike_cycle_speed"))
	dungeon_seed = _resolve_dungeon_seed()
	_build_crypt(dungeon_seed)
	set_process(not Engine.is_editor_hint())


func rebuild_with_seed(seed_val: int) -> void:
	dungeon_seed = maxi(seed_val, 1)
	for ch in get_children():
		ch.queue_free()
	_timed_spikes.clear()
	_build_crypt(dungeon_seed)


func _resolve_dungeon_seed() -> int:
	if crypt_region != null and crypt_region.has_method("get_profile"):
		var prof: Variant = crypt_region.call("get_profile")
		if prof != null:
			var fixed_v := int(prof.get("fixed_dungeon_seed"))
			var use_rand := bool(prof.get("randomize_dungeon_seed"))
			if fixed_v > 0 and not use_rand:
				return fixed_v
	var r := RandomNumberGenerator.new()
	r.randomize()
	return maxi(int(r.randi() & 0x3fffffff), 1)


func _process(delta: float) -> void:
	_abyss_time += delta * _spike_cycle_speed
	for entry in _timed_spikes:
		var spike_node := entry.get("node") as Node3D
		if spike_node == null or not is_instance_valid(spike_node):
			continue
		var phase: float = fmod(_abyss_time * 1.15 + float(entry["phase"]), 3.4)
		var thrust := 0.0
		if phase < 0.35:
			thrust = lerpf(0.0, 1.0, phase / 0.35)
		elif phase < 1.35:
			thrust = 1.0
		elif phase < 1.85:
			thrust = lerpf(1.0, 0.0, (phase - 1.35) / 0.50)
		spike_node.position.y = float(entry["base_y"]) + thrust * 0.55


func _get_scene(rel: String) -> PackedScene:
	var path: String = rel if rel.begins_with("res://") else (RES_BASE + rel)
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	var ps := load(path) as PackedScene
	_scene_cache[path] = ps
	return ps


func _init_materials() -> void:
	var rock_tex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D

	_crypt_rock_mat = CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.58, 0.55, 0.50),
		"cool_tint": Color(0.35, 0.39, 0.46),
		"moss_tint": Color(0.24, 0.50, 0.19),
		"triplanar_scale": 0.25,
		"bump": 1.38,
		"meadow_blend": 0.0,
		"abyss_pos": Vector3(CX, SANCTUM_Y, 184.0),
		"abyss_col": Color(0.22, 0.11, 0.38),
		"abyss_radius": 24.0,
	})

	_surface_moss_rock_mat = CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.46, 0.44, 0.39),
		"cool_tint": Color(0.28, 0.31, 0.35),
		"moss_tint": Color(0.18, 0.36, 0.13),
		"triplanar_scale": 0.24,
		"bump": 1.15,
		"meadow_blend": 0.0,
	})

	var masonry_sh := load("res://shaders/crypt_masonry.gdshader") as Shader

	_crypt_floor_mat = ShaderMaterial.new()
	_crypt_floor_mat.shader = masonry_sh
	_crypt_floor_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_crypt_floor_mat.set_shader_parameter(&"surface_mode", 0.0)
	_crypt_floor_mat.set_shader_parameter(&"block_scale", 0.72)
	_crypt_floor_mat.set_shader_parameter(&"bump_strength", 1.25)
	_crypt_floor_mat.set_shader_parameter(&"moss_strength", 0.42)
	_crypt_floor_mat.set_shader_parameter(&"base_roughness", 0.87)
	_crypt_floor_mat.set_shader_parameter(&"stone_dark", Color(0.11, 0.12, 0.15))
	_crypt_floor_mat.set_shader_parameter(&"stone_mid", Color(0.25, 0.26, 0.28))
	_crypt_floor_mat.set_shader_parameter(&"stone_warm", Color(0.34, 0.31, 0.27))
	_crypt_floor_mat.set_shader_parameter(&"mortar_tint", Color(0.03, 0.035, 0.04))
	_crypt_floor_mat.set_shader_parameter(&"moss_tint", Color(0.18, 0.39, 0.13))
	_crypt_floor_mat.set_shader_parameter(&"moss_sky_y", 24.5)
	_crypt_floor_mat.set_shader_parameter(&"abyss_glow_pos", Vector3(CX, SANCTUM_Y, 184.0))
	_crypt_floor_mat.set_shader_parameter(&"abyss_glow_col", Color(0.22, 0.11, 0.40))
	_crypt_floor_mat.set_shader_parameter(&"abyss_glow_radius", 24.0)

	_crypt_ashlar_mat = ShaderMaterial.new()
	_crypt_ashlar_mat.shader = masonry_sh
	_crypt_ashlar_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_crypt_ashlar_mat.set_shader_parameter(&"surface_mode", 1.0)
	_crypt_ashlar_mat.set_shader_parameter(&"block_scale", 0.62)
	_crypt_ashlar_mat.set_shader_parameter(&"bump_strength", 1.32)
	_crypt_ashlar_mat.set_shader_parameter(&"moss_strength", 0.48)
	_crypt_ashlar_mat.set_shader_parameter(&"base_roughness", 0.89)
	_crypt_ashlar_mat.set_shader_parameter(&"stone_dark", Color(0.12, 0.13, 0.15))
	_crypt_ashlar_mat.set_shader_parameter(&"stone_mid", Color(0.27, 0.28, 0.29))
	_crypt_ashlar_mat.set_shader_parameter(&"stone_warm", Color(0.37, 0.33, 0.29))
	_crypt_ashlar_mat.set_shader_parameter(&"mortar_tint", Color(0.035, 0.038, 0.045))
	_crypt_ashlar_mat.set_shader_parameter(&"moss_tint", Color(0.19, 0.42, 0.14))
	_crypt_ashlar_mat.set_shader_parameter(&"moss_sky_y", 23.5)
	_crypt_ashlar_mat.set_shader_parameter(&"abyss_glow_pos", Vector3(CX, SANCTUM_Y, 184.0))
	_crypt_ashlar_mat.set_shader_parameter(&"abyss_glow_col", Color(0.22, 0.11, 0.40))
	_crypt_ashlar_mat.set_shader_parameter(&"abyss_glow_radius", 24.0)

	_crypt_trim_mat = ShaderMaterial.new()
	_crypt_trim_mat.shader = masonry_sh
	_crypt_trim_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_crypt_trim_mat.set_shader_parameter(&"surface_mode", 2.0)
	_crypt_trim_mat.set_shader_parameter(&"block_scale", 0.88)
	_crypt_trim_mat.set_shader_parameter(&"bump_strength", 1.15)
	_crypt_trim_mat.set_shader_parameter(&"moss_strength", 0.30)
	_crypt_trim_mat.set_shader_parameter(&"base_roughness", 0.80)
	_crypt_trim_mat.set_shader_parameter(&"stone_dark", Color(0.07, 0.075, 0.095))
	_crypt_trim_mat.set_shader_parameter(&"stone_mid", Color(0.17, 0.18, 0.20))
	_crypt_trim_mat.set_shader_parameter(&"stone_warm", Color(0.25, 0.23, 0.21))
	_crypt_trim_mat.set_shader_parameter(&"mortar_tint", Color(0.025, 0.025, 0.03))
	_crypt_trim_mat.set_shader_parameter(&"moss_tint", Color(0.18, 0.38, 0.14))
	_crypt_trim_mat.set_shader_parameter(&"moss_sky_y", 23.0)
	_crypt_trim_mat.set_shader_parameter(&"abyss_glow_pos", Vector3(CX, SANCTUM_Y, 184.0))
	_crypt_trim_mat.set_shader_parameter(&"abyss_glow_col", Color(0.22, 0.11, 0.40))
	_crypt_trim_mat.set_shader_parameter(&"abyss_glow_radius", 24.0)

	var iron_std := StandardMaterial3D.new()
	iron_std.albedo_color = Color(0.075, 0.08, 0.095)
	iron_std.metallic = 0.50
	iron_std.roughness = 0.44
	iron_std.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_crypt_iron_mat = iron_std

	_stone_props_mat = CavePropFX.make_diffuse_rock_mat(Color(0.56, 0.57, 0.60))

	_water_cistern_mat = CavePropFX.make_cave_water_mat(
		Color(0.04, 0.30, 0.28),
		Color(0.01, 0.06, 0.07),
		Color(0.50, 0.76, 0.70),
		false,
		Vector3(CX, UPPER_Y - 0.35, 248.0),
		0.32
	)
	_water_fall_mat = CavePropFX.make_cave_water_mat(
		Color(0.14, 0.56, 0.50),
		Color(0.04, 0.18, 0.20),
		Color(0.76, 0.92, 0.88),
		true,
		Vector3(CX, UPPER_Y - 0.35, 248.0),
		0.56
	)
	_water_abyss_mat = CavePropFX.make_cave_water_mat(
		Color(0.08, 0.26, 0.34),
		Color(0.015, 0.04, 0.08),
		Color(0.42, 0.70, 0.82),
		false,
		Vector3(0.0, -9999.0, 0.0),
		0.22
	)


func _build_crypt(seed_val: int) -> void:
	_init_materials()
	var layout := _generate_dungeon_layout(seed_val)
	var sanctum_c: Vector3 = WorldLandmarks.skel_dungeon_sanctum_center
	for mat in [_crypt_rock_mat, _crypt_floor_mat, _crypt_ashlar_mat, _crypt_trim_mat]:
		if mat != null:
			mat.set_shader_parameter(&"abyss_glow_pos", sanctum_c)
			mat.set_shader_parameter(&"abyss_pos", sanctum_c)

	# 1. Natural Highland Barrow Cliff Portal & Ravine Descent (z = 342 -> 289, y = 26 -> 14)
	_build_barrow_hillside_portal()

	# 2. Procedural Catacomb Rooms & Watertight Masonry+Rock Corridors
	var rooms: Array[Dictionary] = layout["rooms"]
	var corridors: Array[Dictionary] = layout["corridors"]
	for rm in rooms:
		_build_room(rm)
	for corr in corridors:
		_build_corridor_segment(corr)


# ==============================================================================
# PROCEDURAL SEEDED MULTI-ROOM DUNGEON GENERATOR (9-11 ROOMS + LOOPS)
# ==============================================================================

static func _cell_world(g: Vector2i) -> Vector2:
	return Vector2(CX + float(g.x) * CELL_STEP, 280.0 - float(g.y) * CELL_STEP)


static func _dir_info(delta: Vector2i) -> Dictionary:
	for d in DIR_DEFS:
		if (d["grid"] as Vector2i) == delta:
			return d
	return {}


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d->%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d->%d,%d" % [b.x, b.y, a.x, a.y]


func _generate_dungeon_layout(seed_val: int) -> Dictionary:
	var best_rooms: Array[Dictionary] = []
	var best_corridors: Array[Dictionary] = []

	for attempt in range(12):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val + attempt * 7919

		var occupied: Dictionary = {}  # Vector2i -> true
		var adj: Dictionary = {}       # Vector2i -> Array[Vector2i]
		var edge_list: Array[Array] = []
		var edge_set: Dictionary = {}

		var add_cell := func(g: Vector2i) -> void:
			occupied[g] = true
			if not adj.has(g):
				adj[g] = []

		var connect_cells := func(a: Vector2i, b: Vector2i) -> void:
			var ek := _edge_key(a, b)
			if edge_set.has(ek):
				return
			edge_set[ek] = true
			edge_list.append([a, b])
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)

		var root := Vector2i(0, 0)
		var first_hop := Vector2i(0, 1)
		add_cell.call(root)
		add_cell.call(first_hop)
		connect_cells.call(root, first_hop)

		# Build meandering main spine (6-7 cells) forcing lateral turns so never a cross/line
		var spine: Array[Vector2i] = [root, first_hop]
		var cur := first_hop
		var prev_dir := Vector2i(0, 1)
		var spine_target := rng.randi_range(6, 7)
		var used_cols: Dictionary = {0: true}

		for _si in range(2, spine_target):
			var candidates: Array[Dictionary] = []
			for d in DIR_DEFS:
				var dg: Vector2i = d["grid"]
				var nb := cur + dg
				if nb.x < -3 or nb.x > 3 or nb.y < 1 or nb.y > 5:
					continue
				if occupied.has(nb):
					continue
				var w := 1.0
				if dg != prev_dir:
					w += 2.6
				if dg.x != 0 and not used_cols.has(nb.x):
					w += 2.4
				if dg.y > 0:
					w += 0.9
				candidates.append({"cell": nb, "dir": dg, "w": w})
			if candidates.is_empty():
				break
			var total_w := 0.0
			for c in candidates:
				total_w += float(c["w"])
			var pick_r := rng.randf() * total_w
			var chosen: Dictionary = candidates[0]
			var acc := 0.0
			for c in candidates:
				acc += float(c["w"])
				if acc >= pick_r:
					chosen = c
					break
			var next_c: Vector2i = chosen["cell"]
			prev_dir = chosen["dir"]
			add_cell.call(next_c)
			connect_cells.call(cur, next_c)
			spine.append(next_c)
			used_cols[next_c.x] = true
			cur = next_c

		# Side branches off existing rooms (!= root) up to 9-11 total chambers
		var desired_rooms := rng.randi_range(9, 11)
		var branch_tries := 0
		while occupied.size() < desired_rooms and branch_tries < 48:
			branch_tries += 1
			var keys := occupied.keys()
			var parent_c: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
			if parent_c == root:
				continue
			var free_nbs: Array[Vector2i] = []
			for d in DIR_DEFS:
				var nb: Vector2i = parent_c + (d["grid"] as Vector2i)
				if nb.x < -3 or nb.x > 3 or nb.y < 1 or nb.y > 5:
					continue
				if not occupied.has(nb):
					free_nbs.append(nb)
			if free_nbs.is_empty():
				continue
			var pick_nb := free_nbs[rng.randi_range(0, free_nbs.size() - 1)]
			add_cell.call(pick_nb)
			connect_cells.call(parent_c, pick_nb)

		if occupied.size() < 9:
			continue

		# Compute initial BFS distance from root to locate Sanctum & pick Squeeze leaf before adding loops
		var init_dist: Dictionary = {root: 0}
		var q: Array[Vector2i] = [root]
		var qi := 0
		while qi < q.size():
			var u := q[qi]
			qi += 1
			for v: Vector2i in (adj[u] as Array):
				if not init_dist.has(v):
					init_dist[v] = int(init_dist[u]) + 1
					q.append(v)

		var sanctum_cell := first_hop
		var max_d := -1
		for g_k in init_dist.keys():
			var g: Vector2i = g_k
			var dval := int(init_dist[g])
			if dval > max_d or (dval == max_d and (adj[g] as Array).size() == 1):
				max_d = dval
				sanctum_cell = g

		var squeeze_cell := Vector2i(999, 999)
		var squeeze_candidates: Array[Vector2i] = []
		for g_k in occupied.keys():
			var g: Vector2i = g_k
			if g != root and g != sanctum_cell and (adj[g] as Array).size() == 1:
				squeeze_candidates.append(g)
		if not squeeze_candidates.is_empty():
			squeeze_cell = squeeze_candidates[rng.randi_range(0, squeeze_candidates.size() - 1)]

		# Add 1-2 cycle-closing loop corridors between adjacent rooms (never onto Vestibule/Sanctum/Squeeze)
		var loop_pairs: Array[Array] = []
		for g_k in occupied.keys():
			var g: Vector2i = g_k
			if g == root or g == sanctum_cell or g == squeeze_cell:
				continue
			for dg: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nb: Vector2i = g + dg
				if not occupied.has(nb):
					continue
				if nb == root or nb == sanctum_cell or nb == squeeze_cell:
					continue
				if not edge_set.has(_edge_key(g, nb)):
					loop_pairs.append([g, nb])
		for li in range(mini(2, loop_pairs.size())):
			var pick_i := rng.randi_range(0, loop_pairs.size() - 1)
			var lp: Array = loop_pairs[pick_i]
			loop_pairs.remove_at(pick_i)
			connect_cells.call(lp[0], lp[1])

		# Final BFS depth & elevation tiers
		var bfs_dist: Dictionary = {root: 0}
		var bfs_parent: Dictionary = {root: root}
		q = [root]
		qi = 0
		while qi < q.size():
			var u := q[qi]
			qi += 1
			for v: Vector2i in (adj[u] as Array):
				if not bfs_dist.has(v):
					bfs_dist[v] = int(bfs_dist[u]) + 1
					bfs_parent[v] = u
					q.append(v)

		var floor_map: Dictionary = {}
		for g_k in occupied.keys():
			var g: Vector2i = g_k
			var d_b := int(bfs_dist.get(g, 1))
			if g == sanctum_cell or d_b >= 5:
				floor_map[g] = SANCTUM_Y
			elif d_b >= 3:
				floor_map[g] = MID_Y
			else:
				floor_map[g] = UPPER_Y

		# Ensure sanctum neighbors are no higher than MID_Y so every connected ramp has dy <= 5.0m
		for nb: Vector2i in (adj[sanctum_cell] as Array):
			if float(floor_map[nb]) > MID_Y:
				floor_map[nb] = MID_Y

		# Assign varied dungeon themes (guarantee cistern, ossuary, spike_gallery, nave, reliquary, rotunda)
		var theme_pool: Array[String] = ["cistern", "ossuary", "spike_gallery", "nave", "reliquary", "rotunda", "barracks", "nave", "ossuary"]
		for si in range(theme_pool.size() - 1, 0, -1):
			var sj := rng.randi_range(0, si)
			var tmp := theme_pool[si]
			theme_pool[si] = theme_pool[sj]
			theme_pool[sj] = tmp
		var theme_idx := 0

		var built_rooms: Array[Dictionary] = []
		var room_lookup: Dictionary = {}
		var col_used: Dictionary = {}
		var row_used: Dictionary = {}

		for g_k in occupied.keys():
			var g: Vector2i = g_k
			col_used[g.x] = true
			row_used[g.y] = true
			var center := _cell_world(g)
			var fy := float(floor_map[g])
			var doors := {"n": false, "s": false, "w": false, "e": false}
			if g == root:
				doors["s"] = true  # Portal descent tunnel enters South (+Z) wall of Vestibule
			for nb: Vector2i in (adj[g] as Array):
				var di := _dir_info(nb - g)
				if not di.is_empty():
					doors[String(di["name"])] = true

			var parent_g: Vector2i = bfs_parent.get(g, root)
			var entry_delta := Vector2i(0, 1) if g == root else (g - parent_g)
			var entry_info := _dir_info(entry_delta)
			var entry_dir := Vector2(0.0, -1.0) if entry_info.is_empty() else (entry_info["world"] as Vector2)

			var theme := ""
			var title := ""
			var half := Vector2(rng.randf_range(11.0, 13.5), rng.randf_range(11.0, 13.5))
			var ceil_h := rng.randf_range(9.4, 10.6)
			if g == root:
				theme = "vestibule"
				title = "Entry Vestibule"
				half = Vector2(12.6, 12.6)
				ceil_h = 10.8
			elif g == sanctum_cell:
				theme = "sanctum"
				title = "Overlord Sanctum"
				half = Vector2(15.0, 15.0)
				ceil_h = 13.2
			elif g == squeeze_cell:
				theme = "squeeze_vault"
				title = "Sealed Reliquary"
				half = Vector2(12.0, 12.0)
				ceil_h = 9.6
			else:
				theme = theme_pool[theme_idx % theme_pool.size()]
				theme_idx += 1
				match theme:
					"cistern":
						title = "Flooded Cistern"
						half = Vector2(13.5, 13.5)
						ceil_h = 10.8
					"ossuary":
						title = "Bone Ossuary"
						half = Vector2(12.4, 11.6)
					"spike_gallery":
						title = "Trapped Gallery"
						half = Vector2(11.8, 11.8)
					"nave":
						title = "Pillared Nave"
						half = Vector2(13.0, 13.0)
					"reliquary":
						title = "Crypt Reliquary"
					"rotunda":
						title = "Sunken Rotunda"
					_:
						title = "Bone Watchroom"

			var rm := {
				"id": built_rooms.size(),
				"grid": g,
				"center": center,
				"half": half,
				"floor_y": fy,
				"ceil_h": ceil_h,
				"theme": theme,
				"title": title,
				"doors": doors,
				"entry_dir": entry_dir,
				"depth": int(bfs_dist.get(g, 0)),
			}
			built_rooms.append(rm)
			room_lookup[g] = rm

		if col_used.size() < 3 or row_used.size() < 3 or edge_list.size() < 8:
			continue

		var built_corrs: Array[Dictionary] = []
		for ep in edge_list:
			var ga: Vector2i = ep[0]
			var gb: Vector2i = ep[1]
			var ra: Dictionary = room_lookup[ga]
			var rb: Dictionary = room_lookup[gb]
			var ca: Vector2 = ra["center"]
			var cb: Vector2 = rb["center"]
			var ha: Vector2 = ra["half"]
			var hb: Vector2 = rb["half"]
			var dir2 := (cb - ca).normalized()
			var start_p := ca + Vector2(dir2.x * ha.x, dir2.y * ha.y)
			var end_p := cb - Vector2(dir2.x * hb.x, dir2.y * hb.y)
			built_corrs.append({
				"a": start_p,
				"b": end_p,
				"y_a": float(ra["floor_y"]),
				"y_b": float(rb["floor_y"]),
				"half_w": CORR_HALF_W,
				"dir": dir2,
			})

		best_rooms = built_rooms
		best_corridors = built_corrs
		break

	# Compute overall world bounds for atmosphere & spatial containment
	var bmin := Vector2(CX - 25.0, 270.0)
	var bmax := Vector2(CX + 25.0, 338.0)
	var v_spawn := Vector3(CX, UPPER_Y, 280.0)
	var s_center := Vector3(CX, SANCTUM_Y, 184.0)
	for rm in best_rooms:
		var c: Vector2 = rm["center"]
		var h: Vector2 = rm["half"]
		bmin.x = minf(bmin.x, c.x - h.x - 4.0)
		bmin.y = minf(bmin.y, c.y - h.y - 4.0)
		bmax.x = maxf(bmax.x, c.x + h.x + 4.0)
		bmax.y = maxf(bmax.y, c.y + h.y + 4.0)
		if String(rm["theme"]) == "vestibule":
			v_spawn = Vector3(c.x, float(rm["floor_y"]), c.y)
		elif String(rm["theme"]) == "sanctum":
			s_center = Vector3(c.x, float(rm["floor_y"]), c.y)

	WorldLandmarks.skel_dungeon_seed = seed_val
	WorldLandmarks.skel_dungeon_rooms = best_rooms
	WorldLandmarks.skel_dungeon_corridors = best_corridors
	WorldLandmarks.skel_dungeon_bounds_min = bmin
	WorldLandmarks.skel_dungeon_bounds_max = bmax
	WorldLandmarks.skel_dungeon_vestibule_spawn = v_spawn
	WorldLandmarks.skel_dungeon_sanctum_center = s_center
	return {"rooms": best_rooms, "corridors": best_corridors}


# ==============================================================================
# PRIMITIVES, ORIENTED BOXES, COLLIDERS & MATERIAL OVERRIDES
# ==============================================================================

func _box_mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, cast_shadow: bool = true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box_solid(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, layer: int, rot_deg: Vector3 = Vector3.ZERO, bname: String = "MasonryBlock") -> MeshInstance3D:
	var mi := _box_mesh(parent, pos, size, mat, rot_deg, true)
	var sb := StaticBody3D.new()
	sb.name = bname
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	if rot_deg != Vector3.ZERO:
		sb.rotation_degrees = rot_deg
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)
	return mi


func _oriented_box(parent: Node3D, xform: Transform3D, size: Vector3, mat: Material, layer: int, bname: String = "OrientedBlock") -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xform
	parent.add_child(mi)

	var sb := StaticBody3D.new()
	sb.name = bname
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.transform = xform
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)


func _col_box(parent: Node3D, pos: Vector3, size: Vector3, layer: int, rot_deg: Vector3 = Vector3.ZERO, cname: String = "Col") -> void:
	var sb := StaticBody3D.new()
	sb.name = cname
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	if rot_deg != Vector3.ZERO:
		sb.rotation_degrees = rot_deg
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)


func _spawn_piece(rel: String, pos: Vector3, rot_deg: float = 0.0, scl: Variant = 1.0, layer_mode: String = "none", override_mat: Material = null) -> Node3D:
	var ps := _get_scene(rel)
	if ps == null:
		return null
	var node := ps.instantiate() as Node3D
	if node == null:
		return null
	node.position = pos
	node.rotation_degrees.y = rot_deg
	if scl is Vector3:
		node.scale = scl
	else:
		var sf := float(scl)
		node.scale = Vector3(sf, sf, sf)
	add_child(node)
	_normalize_piece_materials(node, override_mat)
	if layer_mode == "wall":
		_assign_collision_layer(node, LAYER_OBSTACLES)
	elif layer_mode == "floor":
		_assign_collision_layer(node, LAYER_TERRAIN)
	elif layer_mode == "none":
		_strip_all_colliders(node)
	return node


func _normalize_piece_materials(node: Node, override_mat: Material) -> void:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if override_mat != null:
				mi.material_override = override_mat
			elif mi.mesh != null:
				for si in range(mi.mesh.get_surface_count()):
					var mat := mi.get_active_material(si)
					if mat is StandardMaterial3D:
						var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						dup.roughness = maxf(dup.roughness, 0.78)
						dup.metallic = minf(dup.metallic, 0.16)
						dup.albedo_color = dup.albedo_color * Color(0.80, 0.78, 0.74)
						mi.set_surface_override_material(si, dup)
		for ch in cur.get_children():
			stack.append(ch)


func _strip_all_colliders(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CollisionObject3D:
			cur.queue_free()
			continue
		for ch in cur.get_children():
			stack.append(ch)


func _assign_collision_layer(root: Node, layer_bit: int) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CollisionObject3D:
			var co := cur as CollisionObject3D
			co.collision_layer = layer_bit
			co.collision_mask = 0
		for ch in cur.get_children():
			stack.append(ch)


func _place_floor_grid(xmin: float, xmax: float, zmin: float, zmax: float, y: float, step: float = 5.6) -> void:
	var x := xmin
	var toggle := 0
	var tile_scale := (step * 0.94) / 4.0
	while x <= xmax + 0.01:
		var z := zmin
		while z <= zmax + 0.01:
			var rel := "floor_tile_large_rocks.gltf.glb" if (toggle % 4 == 1) else "floor_tile_large.gltf.glb"
			var y_stagger := 0.035 + float(toggle % 5) * 0.004
			_spawn_piece(rel, Vector3(x, y + y_stagger, z), float((toggle % 4) * 90), tile_scale, "none", _crypt_floor_mat)
			toggle += 1
			z += step
		x += step


func _spawn_brazier(pos: Vector3, seed_idx: int, height_scale: float = 1.0, flame_scale: float = 0.62, light_energy: float = 2.6, light_range: float = 17.5, light_color: Color = Color(1.0, 0.56, 0.22)) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var ped_h := 1.05 * height_scale
	var ped := CylinderMesh.new()
	ped.top_radius = 0.36
	ped.bottom_radius = 0.52
	ped.height = ped_h
	ped.radial_segments = 10
	var ped_mi := MeshInstance3D.new()
	ped_mi.mesh = ped
	ped_mi.material_override = _crypt_trim_mat
	ped_mi.position = Vector3(0.0, ped_h * 0.5, 0.0)
	root.add_child(ped_mi)

	var rim := CylinderMesh.new()
	rim.top_radius = 0.56
	rim.bottom_radius = 0.38
	rim.height = 0.28
	rim.radial_segments = 10
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	rim_mi.material_override = _crypt_iron_mat
	rim_mi.position = Vector3(0.0, ped_h + 0.12, 0.0)
	root.add_child(rim_mi)

	_col_box(root, Vector3(0.0, ped_h * 0.5, 0.0), Vector3(0.92, ped_h + 0.3, 0.92), LAYER_OBSTACLES, Vector3.ZERO, "BrazierCol")
	CavePropFX.attach_torch_fire(root, Vector3(0.0, ped_h + 0.22, 0.0), seed_idx, flame_scale)

	var pl := OmniLight3D.new()
	pl.position = Vector3(0.0, ped_h + 0.85, 0.0)
	pl.light_color = light_color
	pl.light_energy = light_energy
	pl.omni_range = light_range
	pl.omni_attenuation = 1.35
	pl.shadow_enabled = false
	root.add_child(pl)


func _spawn_wall_torch(pos: Vector3, yaw_deg: float, seed_idx: int, light_energy: float = 2.2, light_range: float = 18.0) -> void:
	_spawn_piece("torch_mounted.gltf.glb", pos, yaw_deg, 1.75, "none", _crypt_iron_mat)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	CavePropFX.attach_torch_fire(self, pos + fwd * 0.56 + Vector3(0.0, 0.62, 0.0), seed_idx, 0.64)
	var pl := OmniLight3D.new()
	pl.position = pos + fwd * 0.65 + Vector3(0.0, 0.85, 0.0)
	pl.light_color = Color(1.0, 0.58, 0.24)
	pl.light_energy = light_energy
	pl.omni_range = light_range
	pl.omni_attenuation = 1.35
	pl.shadow_enabled = false
	add_child(pl)


func _spawn_stair_treads(a: Vector2, b: Vector2, y_a: float, y_b: float, width: float, num_steps: int, tread_mat: Material) -> void:
	var ab := b - a
	var L := ab.length()
	if L < 0.1 or num_steps < 1:
		return
	var dir2 := ab / L
	var yaw := atan2(-dir2.x, -dir2.y)
	var dy := (y_a - y_b) / float(num_steps)
	var step_d := L / float(num_steps)
	for i in range(num_steps):
		var t := (float(i) + 0.5) / float(num_steps)
		var p2 := a.lerp(b, t)
		var yt := lerpf(y_a, y_b, t)
		var step_h := absf(dy) + 0.28
		var bm := BoxMesh.new()
		var w_alt := width + (0.014 if (i % 2 == 0) else -0.014)
		bm.size = Vector3(w_alt, step_h, step_d * 1.14)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = tread_mat
		mi.position = Vector3(p2.x, yt - step_h * 0.5 + 0.025, p2.y)
		mi.rotation.y = yaw
		add_child(mi)


# ==============================================================================
# NATURAL HIGHLAND BARROW CLIFF PORTAL & RAVINE DESCENT
# ==============================================================================

func _build_barrow_hillside_portal() -> void:
	# 1. Ravine flagstone entry threshold (y=26.0, z=324..345) — recessed visual deck + staggered flagstones prevents coplanar terrain z-fighting!
	_col_box(self, Vector3(CX, EXT_Y - 0.35, 332.5), Vector3(15.0, 0.70, 15.0), LAYER_TERRAIN, Vector3.ZERO, "RavineThresholdDeck")
	_box_mesh(self, Vector3(CX, EXT_Y - 0.43, 332.5), Vector3(14.8, 0.70, 14.8), _crypt_floor_mat, Vector3.ZERO, false)
	var tile_idx := 0
	for rz: float in [326.5, 332.0, 337.5, 343.0]:
		for rx_off: float in [-4.8, 0.0, 4.8]:
			var rel := "floor_tile_large_rocks.gltf.glb" if (int(absf(rz + rx_off)) % 2 == 1) else "floor_tile_large.gltf.glb"
			var y_off := 0.045 + float(tile_idx % 5) * 0.004
			_spawn_piece(rel, Vector3(CX + rx_off, EXT_Y + y_off, rz), float(int(absf(rx_off) * 30.0) % 4 * 90), Vector3(1.12, 1.0, 1.12), "none", _crypt_floor_mat)
			tile_idx += 1

	# 2. Natural moss-draped granite cliff cheeks & brow arch framing portal cutout (ZERO colliders inside x = CX +- 5.0m)
	var cliff_boulders: Array[Array] = [
		[Vector3(CX - 10.6, EXT_Y + 3.6, 323.5), Vector3(5.6, 6.2, 5.8), 301, true],
		[Vector3(CX + 10.6, EXT_Y + 3.6, 323.5), Vector3(5.6, 6.2, 5.8), 302, true],
		[Vector3(CX - 13.6, EXT_Y + 3.0, 330.0), Vector3(5.2, 4.8, 5.0), 303, true],
		[Vector3(CX + 13.6, EXT_Y + 3.0, 330.0), Vector3(5.2, 4.8, 5.0), 304, true],
		[Vector3(CX - 11.4, EXT_Y + 1.9, 337.5), Vector3(4.2, 3.4, 4.2), 305, true],
		[Vector3(CX + 11.4, EXT_Y + 1.9, 337.5), Vector3(4.2, 3.4, 4.2), 306, true],
		# High rocky hillside brow arch spanning ABOVE portal y=44.5..50.0 (clear >= 8.2m above ground!)
		[Vector3(CX, EXT_Y + 11.2, 320.5), Vector3(10.8, 4.2, 6.2), 307, true],
		[Vector3(CX - 6.6, EXT_Y + 9.4, 321.5), Vector3(5.4, 4.6, 5.8), 308, true],
		[Vector3(CX + 6.6, EXT_Y + 9.4, 321.5), Vector3(5.4, 4.6, 5.8), 309, true],
		[Vector3(CX, EXT_Y + 10.6, 314.5), Vector3(13.0, 4.8, 6.8), 310, true],
	]
	for cb: Array in cliff_boulders:
		CavePropFX.spawn_fractured_boulder(self, cb[0] as Vector3, cb[1] as Vector3, _surface_moss_rock_mat, int(cb[2]), bool(cb[3]))

	# Carve ruined stone archway pillars flanking the hillside mouth (9.6m wide x 8.0m high aperture)
	for side_s: float in [-1.0, 1.0]:
		_box_solid(self, Vector3(CX + side_s * 6.3, EXT_Y + 4.4, 324.2), Vector3(3.0, 8.8, 3.4), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "BarrowArchPier")
		_spawn_piece("pillar_decorated.gltf.glb", Vector3(CX + side_s * 5.7, EXT_Y, 325.6), 0.0, 2.20, "none", _crypt_trim_mat)
		_spawn_piece("pillar_decorated.gltf.glb", Vector3(CX + side_s * 5.7, EXT_Y + 4.2, 325.6), 0.0, 2.20, "none", _crypt_trim_mat)
		_spawn_brazier(Vector3(CX + side_s * 7.6, EXT_Y, 331.5), 110 + (0 if side_s < 0.0 else 1), 1.35, 0.92, 3.2, 24.0)
	_box_solid(self, Vector3(CX, EXT_Y + 9.1, 324.2), Vector3(15.6, 2.2, 3.6), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "BarrowArchLintel")
	_spawn_piece("sword_shield_gold.gltf.glb", Vector3(CX, EXT_Y + 9.1, 326.25), 0.0, 2.0, "none", _crypt_trim_mat)

	# 3. Vaulted Subterranean Descent Tunnel (z = 326.0 -> 289.0, y = 26.0 -> 14.0) into Vestibule
	var tun_a := Vector2(CX, 326.0)
	var tun_b := Vector2(CX, 289.0)
	_build_corridor_segment({
		"a": tun_a,
		"b": tun_b,
		"y_a": EXT_Y,
		"y_b": UPPER_Y,
		"half_w": 4.9,
		"dir": Vector2(0.0, -1.0),
		"is_entrance": true,
	})
	# Extra hanging ivy & cliff shadows over portal lip
	CavePropFX.spawn_vine_batch(self, [
		{"pos": Vector3(CX - 3.6, EXT_Y + 7.9, 325.7), "len": 3.0, "width": 1.4, "rot": 0.4},
		{"pos": Vector3(CX + 3.8, EXT_Y + 8.0, 325.6), "len": 3.2, "width": 1.4, "rot": 1.9},
	])


# ==============================================================================
# CORRIDOR & ROOM ARCHITECTURAL BUILDERS
# ==============================================================================

func _build_corridor_segment(corr: Dictionary) -> void:
	var a: Vector2 = corr["a"]
	var b: Vector2 = corr["b"]
	var y_a := float(corr["y_a"])
	var y_b := float(corr["y_b"])
	var hw := float(corr.get("half_w", CORR_HALF_W))
	var is_entrance := bool(corr.get("is_entrance", false))

	var ab := b - a
	var horiz_len := ab.length()
	if horiz_len < 0.2:
		return
	var dir2 := ab / horiz_len
	var dy := y_b - y_a
	var chord3 := Vector3(dir2.x * horiz_len, dy, dir2.y * horiz_len)
	var slope_len := chord3.length()
	var z_axis := chord3.normalized()
	var x_axis := Vector3(dir2.y, 0.0, -dir2.x).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)

	var mid_pos := Vector3((a.x + b.x) * 0.5, (y_a + y_b) * 0.5, (a.y + b.y) * 0.5)
	var eff_len := slope_len + (1.05 if is_entrance else 1.85)

	# Solid walkable floor deck (LAYER_TERRAIN, offset -0.018m so flat corridors never coplanarly z-fight RoomFloor)
	_oriented_box(self, Transform3D(basis, mid_pos - y_axis * 0.498), Vector3(hw * 2.0 + 1.48, 0.96, eff_len), _crypt_floor_mat, LAYER_TERRAIN, "CorrFloor")
	# Solid masonry ceiling slab (LAYER_OBSTACLES)
	_oriented_box(self, Transform3D(basis, mid_pos + y_axis * (CORR_H + 0.57)), Vector3(hw * 2.0 + 2.48, 1.1, eff_len), _crypt_ashlar_mat, LAYER_OBSTACLES, "CorrCeil")
	# Left & Right masonry walls (LAYER_OBSTACLES, slightly offset from DoorPier/BarrowArchPier faces)
	for side_s: float in [-1.0, 1.0]:
		_oriented_box(
			self,
			Transform3D(basis, mid_pos + x_axis * (side_s * (hw + 0.67)) + y_axis * (CORR_H * 0.5)),
			Vector3(1.26, CORR_H + 0.86, eff_len),
			_crypt_ashlar_mat,
			LAYER_OBSTACLES,
			"CorrWall"
		)

	# Stepped visual stair treads if sloped
	if absf(dy) > 0.35:
		var steps := clampi(int(round(absf(dy) * 2.4)), 6, 36)
		_spawn_stair_treads(a, b, y_a, y_b, hw * 1.92, steps, _crypt_floor_mat)

	# Transverse stone arch ribs & wall torches along corridor
	var num_ribs := maxi(2, int(horiz_len / 7.5))
	for ri in range(1, num_ribs):
		var t := float(ri) / float(num_ribs)
		var rp := a.lerp(b, t)
		var ry := lerpf(y_a, y_b, t)
		var r_pos := Vector3(rp.x, ry, rp.y)
		_oriented_box(self, Transform3D(basis, r_pos + y_axis * (CORR_H - 0.15)), Vector3(hw * 2.0 + 0.4, 0.55, 0.85), _crypt_trim_mat, LAYER_OBSTACLES, "CorrRib")
		if (ri % 2) == 1:
			var side_sign := -1.0 if ((ri / 2) % 2 == 0) else 1.0
			var w_dir := x_axis * (-side_sign)
			var torch_yaw := rad_to_deg(atan2(-w_dir.x, -w_dir.z))
			_spawn_wall_torch(r_pos + x_axis * (side_sign * (hw - 0.14)) + y_axis * 3.8, torch_yaw, ri + int(absf(rp.x + rp.y)), 2.2, 18.0)


func _build_room(room: Dictionary) -> void:
	var c: Vector2 = room["center"]
	var half: Vector2 = room["half"]
	var fy := float(room["floor_y"])
	var ceil_h := float(room["ceil_h"])
	var doors: Dictionary = room["doors"]
	var theme := String(room["theme"])

	# Floor slab & tiled stone floor surface
	_box_solid(self, Vector3(c.x, fy - 0.50, c.y), Vector3(half.x * 2.0 + 2.6, 1.0, half.y * 2.0 + 2.6), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "RoomFloor")
	_box_solid(self, Vector3(c.x, fy + ceil_h + 0.65, c.y), Vector3(half.x * 2.0 + 2.6, 1.3, half.y * 2.0 + 2.6), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "RoomCeiling")

	# Perimeter walls with clean 9.6m x 8.0m openings where corridors meet
	_build_room_wall(c, half.x, half.y, fy, ceil_h, "n", bool(doors.get("n", false)))
	_build_room_wall(c, half.x, half.y, fy, ceil_h, "s", bool(doors.get("s", false)))
	_build_room_wall(c, half.x, half.y, fy, ceil_h, "w", bool(doors.get("w", false)))
	_build_room_wall(c, half.x, half.y, fy, ceil_h, "e", bool(doors.get("e", false)))

	# Corner Gothic columns & room corner warm braziers / ceiling ribs
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var px := c.x + sx * (half.x - 1.4)
			var pz := c.y + sz * (half.y - 1.4)
			_spawn_piece("column.gltf.glb", Vector3(px, fy, pz), 0.0, Vector3(1.5, ceil_h / 4.2, 1.5), "wall", _crypt_trim_mat)
	if theme != "squeeze_vault":
		for bx_s: float in [-0.45, 0.45]:
			var bp := Vector3(c.x + bx_s * (half.x - 1.8), fy, c.y + (-0.45 if bx_s > 0.0 else 0.45) * (half.y - 1.8))
			_spawn_brazier(bp, int(room["id"]) * 10 + (1 if bx_s > 0.0 else 2), 1.30, 0.84, 2.9, 23.0)

	# Theme-specific interior dressing (preserving perimeter & doorway transit lanes!)
	var r_id := int(room["id"])
	match theme:
		"vestibule":
			_box_mesh(self, Vector3(c.x, fy + 0.30, c.y), Vector3(5.6, 0.60, 5.6), _crypt_trim_mat)
			_spawn_piece("table_long_decorated_A.gltf.glb", Vector3(c.x, fy + 0.60, c.y), 90.0, 1.55, "wall", null)
			_spawn_piece("candle_triple.gltf.glb", Vector3(c.x, fy + 1.98, c.y), 25.0, 1.65, "none", null)
			_place_floor_grid(c.x - half.x + 2.8, c.x + half.x - 2.8, c.y - half.y + 2.8, c.y + half.y - 2.8, fy, 5.6)

		"sanctum":
			var entry_d: Vector2 = room["entry_dir"]
			var back_d := -entry_d
			var dais_pos := Vector2(c.x, c.y) - back_d * 5.2
			var yaw_boss := rad_to_deg(atan2(-entry_d.x, -entry_d.y))
			_box_solid(self, Vector3(dais_pos.x, fy + 0.20, dais_pos.y), Vector3(10.8, 0.40, 10.8), _crypt_trim_mat, LAYER_TERRAIN, Vector3.ZERO, "SanctumDais")
			_box_solid(self, Vector3(dais_pos.x, fy + 0.56, dais_pos.y), Vector3(7.4, 0.34, 7.4), _crypt_ashlar_mat, LAYER_TERRAIN, Vector3.ZERO, "SanctumDaisTop")
			_spawn_piece("table_long_decorated_A.gltf.glb", Vector3(dais_pos.x, fy + 0.74, dais_pos.y), yaw_boss, 1.75, "wall", _crypt_trim_mat)
			_spawn_piece("chest_gold.glb", Vector3(dais_pos.x, fy + 2.30, dais_pos.y), yaw_boss, 1.65, "none", null)
			_spawn_brazier(Vector3(dais_pos.x - 5.2, fy + 0.40, dais_pos.y), 91, 1.45, 0.98, 3.4, 26.0, Color(0.68, 0.38, 0.96))
			_spawn_brazier(Vector3(dais_pos.x + 5.2, fy + 0.40, dais_pos.y), 92, 1.45, 0.98, 3.4, 26.0, Color(0.68, 0.38, 0.96))
			var boss_pl := OmniLight3D.new()
			boss_pl.position = Vector3(dais_pos.x, fy + 5.6, dais_pos.y)
			boss_pl.light_color = Color(0.50, 0.26, 0.88)
			boss_pl.light_energy = 3.0
			boss_pl.omni_range = 28.0
			boss_pl.shadow_enabled = false
			add_child(boss_pl)

		"cistern":
			# Central recessed water pool (keeps >= 5.0m dry stone walk all around perimeter to every door!)
			var pw := half.x * 1.05
			var pd := half.y * 1.05
			_box_solid(self, Vector3(c.x, fy - 1.85, c.y), Vector3(pw, 0.45, pd), _crypt_trim_mat, LAYER_TERRAIN, Vector3.ZERO, "CisternBed")
			var wq := PlaneMesh.new()
			wq.size = Vector2(pw - 0.6, pd - 0.6)
			wq.subdivide_width = 16
			wq.subdivide_depth = 16
			var wmi := MeshInstance3D.new()
			wmi.mesh = wq
			wmi.material_override = _water_cistern_mat
			wmi.position = Vector3(c.x, fy - 0.34, c.y)
			wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wmi)
			for side_z: float in [-pd * 0.5, pd * 0.5]:
				_box_solid(self, Vector3(c.x, fy - 0.15, c.y + side_z), Vector3(pw + 0.6, 0.65, 0.65), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "PoolCurbZ")
			for side_x: float in [-pw * 0.5, pw * 0.5]:
				_box_solid(self, Vector3(c.x + side_x, fy - 0.15, c.y), Vector3(0.65, 0.65, pd + 0.6), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "PoolCurbX")
			# Glowing cistern waterfall & wide stone bridge plank across the center
			_box_solid(self, Vector3(c.x, fy - 0.04, c.y), Vector3(4.2, 0.26, pd + 0.6), _crypt_trim_mat, LAYER_TERRAIN, Vector3.ZERO, "CisternBridge")
			var wf := PlaneMesh.new()
			wf.size = Vector2(3.6, 7.6)
			wf.subdivide_depth = 12
			var wfi := MeshInstance3D.new()
			wfi.mesh = wf
			wfi.material_override = _water_fall_mat
			wfi.position = Vector3(c.x, fy + 3.4, c.y - pd * 0.35)
			wfi.rotation_degrees = Vector3(82.0, 0.0, 0.0)
			wfi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wfi)

		"ossuary":
			_spawn_piece("wall_shelves.gltf.glb", Vector3(c.x + half.x - 1.6, fy, c.y), -90.0, 1.70, "wall", _crypt_ashlar_mat)
			_spawn_piece("wall_shelves.gltf.glb", Vector3(c.x - half.x + 1.6, fy, c.y), 90.0, 1.70, "wall", _crypt_ashlar_mat)
			_spawn_piece("chest.glb", Vector3(c.x + 2.6, fy, c.y + 2.2), -35.0, 1.65, "wall", null)
			_spawn_piece("keg_decorated.gltf.glb", Vector3(c.x - 2.8, fy, c.y - 2.2), 22.0, 1.60, "wall", null)
			_spawn_piece("candle_triple.gltf.glb", Vector3(c.x - 2.8, fy + 1.46, c.y - 2.2), 0.0, 1.65, "none", null)

		"spike_gallery":
			for ti in range(2):
				var sp_pos := Vector3(c.x + (float(ti) - 0.5) * 6.4, fy, c.y)
				_spawn_piece("floor_tile_big_grate.gltf.glb", sp_pos + Vector3(0.0, 0.01, 0.0), 0.0, 1.45, "none", _crypt_iron_mat)
				var spk := _spawn_piece("floor_tile_big_spikes.glb", sp_pos + Vector3(0.0, -0.34, 0.0), 0.0, 1.45, "none", _crypt_iron_mat)
				if spk != null:
					_timed_spikes.append({"node": spk, "base_y": fy - 0.34, "phase": float(ti) * 1.45})

		"squeeze_vault":
			# Placed on a dead-end leaf! Split interior with 1.55m Iron Squeeze Portcullis guarding chest.
			var ed: Vector2 = room["entry_dir"]
			var g_fwd := Vector3(ed.x, 0.0, ed.y).normalized()
			var g_right := Vector3(-ed.y, 0.0, ed.x).normalized()
			var g_basis := Basis(g_right, Vector3.UP, g_fwd)
			var gate_origin := Vector3(c.x, fy, c.y) - g_fwd * 2.4
			var gate_yaw := rad_to_deg(atan2(ed.x, ed.y))
			_spawn_piece("wall_gated.gltf.glb", gate_origin + Vector3(0.0, 1.55, 0.0), gate_yaw, Vector3(2.1, 1.9, 1.7), "none", _crypt_iron_mat)
			_oriented_box(self, Transform3D(g_basis, gate_origin + Vector3(0.0, 1.55 + 3.4, 0.0)), Vector3(10.6, 6.8, 1.4), _crypt_iron_mat, LAYER_OBSTACLES, "SqueezePortcullisCol")
			for ws: float in [-1.0, 1.0]:
				_oriented_box(self, Transform3D(g_basis, gate_origin + g_right * (ws * 8.6) + Vector3(0.0, ceil_h * 0.5, 0.0)), Vector3(7.2, ceil_h + 0.6, 1.5), _crypt_ashlar_mat, LAYER_OBSTACLES, "SqueezeWingWall")
			var chest_pos := Vector3(c.x, fy, c.y) + g_fwd * 5.2
			_spawn_piece("chest_gold.glb", chest_pos, gate_yaw + 180.0, 1.75, "wall", null)
			_spawn_brazier(chest_pos + g_right * 3.8, 87, 1.25, 0.80, 2.8, 22.0, Color(0.55, 0.95, 0.85))
			_spawn_brazier(chest_pos - g_right * 3.8, 88, 1.25, 0.80, 2.8, 22.0, Color(0.55, 0.95, 0.85))

		_:
			# Nave, reliquary, rotunda, barracks: symmetric stone pillars & crates leaving clear lanes
			_spawn_piece("crates_stacked.gltf.glb", Vector3(c.x + 3.6, fy, c.y + 3.4), 30.0, 1.60, "wall", null)
			_spawn_piece("barrel_large_decorated.gltf.glb", Vector3(c.x - 3.8, fy, c.y - 3.4), -20.0, 1.60, "wall", null)

	# Karst ceiling stalactites & hanging cave vines inside high rooms
	CavePropFX.spawn_speleothem_cluster(self, [
		{"pos": Vector3(c.x - 5.2, fy + ceil_h - 0.1, c.y - 4.8), "len": 3.2, "rad": 0.45, "seed": float(r_id * 11 + 1), "ceiling": true},
		{"pos": Vector3(c.x + 5.4, fy + ceil_h - 0.1, c.y + 4.6), "len": 3.4, "rad": 0.48, "seed": float(r_id * 11 + 2), "ceiling": true},
	], _stone_props_mat)


func _build_room_wall(center: Vector2, hx: float, hz: float, fy: float, ceil_h: float, side: String, has_door: bool) -> void:
	var along_x := (side == "n" or side == "s")
	var span := (hx * 2.0 + 2.2) if along_x else (hz * 2.0 + 2.2)
	var wall_pos := Vector3.ZERO
	if side == "n":
		wall_pos = Vector3(center.x, fy, center.y - hz - 0.6)
	elif side == "s":
		wall_pos = Vector3(center.x, fy, center.y + hz + 0.6)
	elif side == "w":
		wall_pos = Vector3(center.x - hx - 0.6, fy, center.y)
	else:
		wall_pos = Vector3(center.x + hx + 0.6, fy, center.y)

	var thick := 1.2
	var total_h := ceil_h + 1.2
	if not has_door:
		var sz := Vector3(span, total_h, thick) if along_x else Vector3(thick, total_h, span)
		_box_solid(self, wall_pos + Vector3(0.0, total_h * 0.5, 0.0), sz, _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "RoomWall_" + side)
		return

	var pier_w := maxf((span - DOOR_W) * 0.5, 0.8)
	var pier_off := DOOR_W * 0.5 + pier_w * 0.5
	for s: float in [-1.0, 1.0]:
		var p_off := Vector3(s * pier_off, total_h * 0.5, 0.0) if along_x else Vector3(0.0, total_h * 0.5, s * pier_off)
		var p_sz := Vector3(pier_w, total_h, thick) if along_x else Vector3(thick, total_h, pier_w)
		_box_solid(self, wall_pos + p_off, p_sz, _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "DoorPier_" + side)

	var lintel_h := maxf(total_h - DOOR_H, 0.8)
	var l_pos := wall_pos + Vector3(0.0, DOOR_H + lintel_h * 0.5, 0.0)
	var l_sz := Vector3(DOOR_W, lintel_h, thick) if along_x else Vector3(thick, lintel_h, DOOR_W)
	_box_solid(self, l_pos, l_sz, _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "DoorLintel_" + side)
