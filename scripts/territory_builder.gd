class_name TerritoryBuilder
extends Node3D
## Builds the three Overworld Beast Territory landmarks inside TerrainScene:
##   1. Spider Webwood Forest ((-410, 480)): DeadTree snags, ferns, mushrooms, mossy boulders, bark logs,
##      drooping catenary silk drapes, radial/funnel webs, sculpted teardrop cocoons & Sticky Web patches.
##   2. Wolf Pack Crag ((290, -240)): Baked SurfaceNets granite den overhang (wolf_den_mesh.res) with
##      landmark_rock.gdshader, bark-textured fallen timber logs, camp hearth, ferns & articulated bones.
##   3. Underground Rat Warren ((-240, 280 -> 244)): Baked SurfaceNets cavern (rat_warren_mesh.res),
##      cave_water.gdshader drainage pools, speleothems, hanging roots, 5-layer fire torches & burrow props.

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
const CavePropFX = preload("res://scripts/cave_prop_fx.gd")
const WebwoodRegion = preload("res://regions/webwood/webwood_region.gd")
const ASSET_DIR := "res://assets/dungeon/"
const LAYER_TERRAIN := 1
const LAYER_OBSTACLES := 4

var _terrain: Node = null
var _scene_cache: Dictionary = {}
var _mat_norm_cache: Dictionary = {}

var _granite_shader_mat: ShaderMaterial
var _webwood_rock_mat: ShaderMaterial
var _warren_shader_mat: ShaderMaterial
var _vault_floor_mat: ShaderMaterial
var _vault_wall_mat: ShaderMaterial
var _vault_trim_mat: ShaderMaterial
var _vault_rock_mat: ShaderMaterial
var _vault_waterfall_mat: ShaderMaterial
var _vault_iron_mat: Material
var _vault_crystal_mat: StandardMaterial3D
var _speleothem_mat: StandardMaterial3D
var _bark_mat: StandardMaterial3D
var _warren_spel_mat: StandardMaterial3D
var _warren_bark_mat: StandardMaterial3D
var _bone_mat: StandardMaterial3D
var _cocoon_mat: StandardMaterial3D
var _silk_cord_mat: StandardMaterial3D
var _warren_water_mat: ShaderMaterial
var _swamp_water_mat: ShaderMaterial
var _orb_web_mat: ShaderMaterial
var _funnel_web_mat: ShaderMaterial

var _warren_interior: Node3D = null
var _spider_root: Node3D = null
var _slime_ref: Node3D = null
var _warren_culled: bool = false
var _flicker_lights: Array[Dictionary] = []
var _fire_seed_counter: int = 80
var _time_acc: float = 0.0


func setup_territories(terrain_node: Node, spider_trees: Array[Dictionary], webwood_region: WebwoodRegion = null, wolf_region: Node = null, waystones_region: Node = null, rat_region: Node = null) -> void:
	_terrain = terrain_node
	_init_materials()
	_build_spider_webwood(spider_trees, webwood_region)
	_build_wolf_crag(wolf_region)
	_build_rat_warren(rat_region)
	_build_world_waystones(waystones_region)


func _init_materials() -> void:
	_granite_shader_mat = CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.56, 0.54, 0.50),
		"cool_tint": Color(0.36, 0.40, 0.45),
		"moss_tint": Color(0.18, 0.34, 0.13),
		"triplanar_scale": 0.28,
		"bump": 1.10,
		"meadow_blend": 0.0,
	})
	_webwood_rock_mat = CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.46, 0.50, 0.42),
		"cool_tint": Color(0.26, 0.32, 0.28),
		"moss_tint": Color(0.18, 0.36, 0.13),
		"triplanar_scale": 0.30,
		"bump": 1.28,
		"meadow_blend": 0.0,
	})
	var rock_tex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
	var path_rock_tex := load("res://assets/nature/PathRocks_Diffuse.png") as Texture2D
	var masonry_sh := load("res://shaders/crypt_masonry.gdshader") as Shader

	var rw_off3 := Vector3(WorldLandmarks.RAT_WARREN_OFFSET.x, 0.0, WorldLandmarks.RAT_WARREN_OFFSET.y)
	var rw_hub_glow := Vector3(WorldLandmarks.RAT_WARREN_BAKED.x, 13.5, 244.5) + rw_off3

	_warren_shader_mat = CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.55, 0.51, 0.46),
		"cool_tint": Color(0.30, 0.34, 0.40),
		"moss_tint": Color(0.18, 0.36, 0.14),
		"triplanar_scale": 0.25,
		"bump": 1.32,
		"meadow_blend": 1.0,
		"meadow_sky_min": 0.48,
		"abyss_pos": rw_hub_glow,
		"abyss_col": Color(0.06, 0.24, 0.24),
		"abyss_radius": 10.5,
		"rough_dry": 0.97,
		"rough_wet": 0.88,
		"spec_dry": 0.01,
		"spec_wet": 0.04,
		"spec_light_strength": 0.002,
		"bump_detail_scale": 0.135,
	})
	if rock_tex != null:
		_warren_shader_mat.set_shader_parameter(&"rock_texture", rock_tex)
	if path_rock_tex != null:
		_warren_shader_mat.set_shader_parameter(&"floor_texture", path_rock_tex)

	_vault_rock_mat = CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.52, 0.49, 0.44),
		"cool_tint": Color(0.29, 0.33, 0.38),
		"moss_tint": Color(0.18, 0.36, 0.14),
		"triplanar_scale": 0.25,
		"bump": 1.28,
		"meadow_blend": 0.0,
		"abyss_pos": rw_hub_glow,
		"abyss_col": Color(0.06, 0.24, 0.24),
		"abyss_radius": 10.5,
		"rough_dry": 0.97,
		"rough_wet": 0.88,
		"spec_dry": 0.01,
		"spec_wet": 0.04,
		"spec_light_strength": 0.002,
		"bump_detail_scale": 0.135,
	})
	if rock_tex != null:
		_vault_rock_mat.set_shader_parameter(&"rock_texture", rock_tex)
	if path_rock_tex != null:
		_vault_rock_mat.set_shader_parameter(&"floor_texture", path_rock_tex)

	_speleothem_mat = CavePropFX.make_diffuse_rock_mat(Color(0.50, 0.51, 0.53))
	_bark_mat = CavePropFX.make_bark_mat(Color(0.84, 0.78, 0.72), Vector2(2.0, 2.8))
	_warren_spel_mat = CavePropFX.make_diffuse_rock_mat(Color(0.48, 0.49, 0.51))
	_warren_spel_mat.roughness = 0.97
	_warren_spel_mat.metallic = 0.0
	_warren_spel_mat.metallic_specular = 0.02
	_warren_bark_mat = CavePropFX.make_bark_mat(Color(0.80, 0.74, 0.68), Vector2(2.0, 2.8))
	_warren_bark_mat.roughness = 0.97
	_warren_bark_mat.metallic = 0.0
	_warren_bark_mat.metallic_specular = 0.02

	_vault_floor_mat = ShaderMaterial.new()
	_vault_floor_mat.shader = masonry_sh
	_vault_floor_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_vault_floor_mat.set_shader_parameter(&"surface_mode", 0.0)
	_vault_floor_mat.set_shader_parameter(&"block_scale", 0.74)
	_vault_floor_mat.set_shader_parameter(&"bump_strength", 1.25)
	_vault_floor_mat.set_shader_parameter(&"moss_strength", 0.56)
	_vault_floor_mat.set_shader_parameter(&"base_roughness", 0.96)
	_vault_floor_mat.set_shader_parameter(&"spec_scale", 0.05)
	_vault_floor_mat.set_shader_parameter(&"stone_dark", Color(0.12, 0.14, 0.15))
	_vault_floor_mat.set_shader_parameter(&"stone_mid", Color(0.26, 0.29, 0.29))
	_vault_floor_mat.set_shader_parameter(&"stone_warm", Color(0.36, 0.35, 0.30))
	_vault_floor_mat.set_shader_parameter(&"mortar_tint", Color(0.030, 0.036, 0.035))
	_vault_floor_mat.set_shader_parameter(&"moss_tint", Color(0.16, 0.40, 0.13))
	_vault_floor_mat.set_shader_parameter(&"moss_sky_y", 21.2)
	_vault_floor_mat.set_shader_parameter(&"abyss_glow_pos", rw_hub_glow + Vector3(0.0, 0.3, 0.0))
	_vault_floor_mat.set_shader_parameter(&"abyss_glow_col", Color(0.08, 0.28, 0.28))
	_vault_floor_mat.set_shader_parameter(&"abyss_glow_radius", 12.0)

	_vault_wall_mat = ShaderMaterial.new()
	_vault_wall_mat.shader = masonry_sh
	_vault_wall_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_vault_wall_mat.set_shader_parameter(&"surface_mode", 1.0)
	_vault_wall_mat.set_shader_parameter(&"block_scale", 0.66)
	_vault_wall_mat.set_shader_parameter(&"bump_strength", 1.28)
	_vault_wall_mat.set_shader_parameter(&"moss_strength", 0.62)
	_vault_wall_mat.set_shader_parameter(&"base_roughness", 0.96)
	_vault_wall_mat.set_shader_parameter(&"spec_scale", 0.05)
	_vault_wall_mat.set_shader_parameter(&"stone_dark", Color(0.13, 0.15, 0.16))
	_vault_wall_mat.set_shader_parameter(&"stone_mid", Color(0.28, 0.30, 0.30))
	_vault_wall_mat.set_shader_parameter(&"stone_warm", Color(0.38, 0.36, 0.31))
	_vault_wall_mat.set_shader_parameter(&"mortar_tint", Color(0.030, 0.036, 0.035))
	_vault_wall_mat.set_shader_parameter(&"moss_tint", Color(0.16, 0.41, 0.13))
	_vault_wall_mat.set_shader_parameter(&"moss_sky_y", 20.8)
	_vault_wall_mat.set_shader_parameter(&"abyss_glow_pos", rw_hub_glow + Vector3(0.0, 0.3, 0.0))
	_vault_wall_mat.set_shader_parameter(&"abyss_glow_col", Color(0.08, 0.26, 0.26))
	_vault_wall_mat.set_shader_parameter(&"abyss_glow_radius", 12.0)

	_vault_trim_mat = ShaderMaterial.new()
	_vault_trim_mat.shader = masonry_sh
	_vault_trim_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_vault_trim_mat.set_shader_parameter(&"surface_mode", 2.0)
	_vault_trim_mat.set_shader_parameter(&"block_scale", 0.88)
	_vault_trim_mat.set_shader_parameter(&"bump_strength", 1.22)
	_vault_trim_mat.set_shader_parameter(&"moss_strength", 0.48)
	_vault_trim_mat.set_shader_parameter(&"base_roughness", 0.95)
	_vault_trim_mat.set_shader_parameter(&"spec_scale", 0.05)
	_vault_trim_mat.set_shader_parameter(&"stone_dark", Color(0.095, 0.11, 0.13))
	_vault_trim_mat.set_shader_parameter(&"stone_mid", Color(0.20, 0.22, 0.23))
	_vault_trim_mat.set_shader_parameter(&"stone_warm", Color(0.29, 0.28, 0.25))
	_vault_trim_mat.set_shader_parameter(&"mortar_tint", Color(0.028, 0.032, 0.034))
	_vault_trim_mat.set_shader_parameter(&"moss_tint", Color(0.16, 0.40, 0.13))
	_vault_trim_mat.set_shader_parameter(&"moss_sky_y", 20.8)
	_vault_trim_mat.set_shader_parameter(&"abyss_glow_pos", rw_hub_glow + Vector3(0.0, 0.3, 0.0))
	_vault_trim_mat.set_shader_parameter(&"abyss_glow_col", Color(0.08, 0.26, 0.26))
	_vault_trim_mat.set_shader_parameter(&"abyss_glow_radius", 12.0)

	var iron_std := StandardMaterial3D.new()
	iron_std.albedo_color = Color(0.055, 0.058, 0.068)
	iron_std.metallic = 0.22
	iron_std.roughness = 0.82
	iron_std.metallic_specular = 0.08
	iron_std.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_vault_iron_mat = iron_std

	var crys_std := StandardMaterial3D.new()
	crys_std.albedo_color = Color(0.14, 0.44, 0.42)
	crys_std.roughness = 0.28
	crys_std.emission_enabled = true
	crys_std.emission = Color(0.10, 0.36, 0.34)
	crys_std.emission_energy_multiplier = 0.52
	_vault_crystal_mat = crys_std

	_warren_water_mat = CavePropFX.make_cave_water_mat(
		Color(0.025, 0.16, 0.16),
		Color(0.008, 0.045, 0.055),
		Color(0.42, 0.66, 0.62),
		false,
		Vector3(WorldLandmarks.RAT_WARREN_BAKED.x - 13.4, 14.15, 246.5) + rw_off3,
		0.28
	)
	_swamp_water_mat = CavePropFX.make_cave_water_mat(
		Color(0.04, 0.12, 0.08),
		Color(0.012, 0.036, 0.025),
		Color(0.22, 0.30, 0.18),
		false,
		Vector3(WorldLandmarks.RAT_WARREN_BAKED.x - 7.8, WorldLandmarks.RAT_SWAMP_WATER_Y, 286.5) + rw_off3,
		0.12
	)
	_swamp_water_mat.set_shader_parameter(&"caustic_strength", 0.05)
	_swamp_water_mat.set_shader_parameter(&"swamp_turbidity", 0.92)
	_vault_waterfall_mat = CavePropFX.make_cave_water_mat(
		Color(0.12, 0.42, 0.38),
		Color(0.03, 0.12, 0.14),
		Color(0.68, 0.84, 0.80),
		true,
		Vector3(WorldLandmarks.RAT_WARREN_BAKED.x - 13.4, 14.15, 246.5) + rw_off3,
		0.56
	)

	var bone_fnl := FastNoiseLite.new()
	bone_fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX
	bone_fnl.fractal_octaves = 3
	bone_fnl.frequency = 0.085
	var bone_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var coc_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for py in range(64):
		for px in range(64):
			var g_b := 0.5 + 0.5 * bone_fnl.get_noise_2d(float(px) * 0.65, float(py) * 3.8)
			var stria := 0.80 + 0.22 * g_b + 0.08 * sin(float(px) * 0.55 + g_b * 3.0)
			bone_img.set_pixel(px, py, Color(clampf(0.84 * stria, 0.45, 0.98), clampf(0.79 * stria, 0.42, 0.95), clampf(0.68 * stria, 0.35, 0.88), 1.0))
			var wrap_b := absf(sin(float(py) * 0.42 + bone_fnl.get_noise_2d(float(px) * 1.4, float(py) * 1.4) * 2.5))
			var silk_g := 0.68 + 0.28 * wrap_b
			coc_img.set_pixel(px, py, Color(clampf(0.78 * silk_g, 0.42, 0.96), clampf(0.80 * silk_g, 0.44, 0.98), clampf(0.76 * silk_g, 0.42, 0.95), 1.0))
	bone_img.generate_mipmaps()
	coc_img.generate_mipmaps()

	_bone_mat = StandardMaterial3D.new()
	_bone_mat.albedo_texture = ImageTexture.create_from_image(bone_img)
	_bone_mat.albedo_color = Color(0.95, 0.92, 0.86)
	_bone_mat.roughness = 0.66
	_bone_mat.uv1_scale = Vector3(2.0, 2.0, 2.0)

	_cocoon_mat = StandardMaterial3D.new()
	_cocoon_mat.albedo_texture = ImageTexture.create_from_image(coc_img)
	_cocoon_mat.albedo_color = Color(0.84, 0.86, 0.85)
	_cocoon_mat.roughness = 0.84
	_cocoon_mat.uv1_scale = Vector3(3.0, 4.0, 3.0)

	_silk_cord_mat = StandardMaterial3D.new()
	_silk_cord_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_silk_cord_mat.albedo_color = Color(0.88, 0.92, 0.96)
	_silk_cord_mat.roughness = 0.46
	_silk_cord_mat.emission_enabled = true
	_silk_cord_mat.emission = Color(0.54, 0.64, 0.74)
	_silk_cord_mat.emission_energy_multiplier = 0.35

	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_VALUE
	fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnl.fractal_octaves = 3
	fnl.frequency = 0.045
	var n_img := fnl.get_seamless_image(128, 128)
	var n_tex: ImageTexture = null
	if n_img != null:
		n_img.generate_mipmaps()
		n_tex = ImageTexture.create_from_image(n_img)

	var web_shader := load("res://shaders/spider_web.gdshader") as Shader
	_orb_web_mat = ShaderMaterial.new()
	_orb_web_mat.shader = web_shader
	_orb_web_mat.set_shader_parameter(&"silk_color", Color(0.90, 0.95, 0.99, 0.92))
	_orb_web_mat.set_shader_parameter(&"thread_width", 0.075)
	_orb_web_mat.set_shader_parameter(&"web_mode", 4.0)
	_orb_web_mat.set_shader_parameter(&"is_funnel", 0.0)
	if n_tex != null:
		_orb_web_mat.set_shader_parameter(&"noise_tex", n_tex)
		_orb_web_mat.set_shader_parameter(&"use_noise_tex", true)

	_funnel_web_mat = ShaderMaterial.new()
	_funnel_web_mat.shader = web_shader
	_funnel_web_mat.set_shader_parameter(&"silk_color", Color(0.88, 0.94, 0.98, 0.88))
	_funnel_web_mat.set_shader_parameter(&"thread_width", 0.075)
	_funnel_web_mat.set_shader_parameter(&"sway_amp", 0.020)
	_funnel_web_mat.set_shader_parameter(&"web_mode", 1.0)
	_funnel_web_mat.set_shader_parameter(&"is_funnel", 1.0)
	if n_tex != null:
		_funnel_web_mat.set_shader_parameter(&"noise_tex", n_tex)
		_funnel_web_mat.set_shader_parameter(&"use_noise_tex", true)


func _sample_h(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("sample_height"):
		return float(_terrain.call("sample_height", x, z))
	return 22.0


func _load_piece(file_name: String) -> Node3D:
	var full_path := ASSET_DIR + file_name
	var ps: PackedScene = _scene_cache.get(full_path, null)
	if ps == null:
		ps = load(full_path) as PackedScene
		if ps == null:
			return null
		_scene_cache[full_path] = ps
	var inst := ps.instantiate() as Node3D
	if inst != null:
		var stack: Array[Node] = [inst]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is MeshInstance3D:
				var mi := cur as MeshInstance3D
				var m := mi.mesh
				if m != null:
					for si in range(m.get_surface_count()):
						var mat := mi.get_surface_override_material(si)
						if mat == null:
							mat = m.surface_get_material(si)
						if mat is BaseMaterial3D:
							var k := mat.get_instance_id()
							var c: StandardMaterial3D = _mat_norm_cache.get(k, null)
							if c == null:
								c = mat.duplicate() as StandardMaterial3D
								c.roughness = maxf(c.roughness, 0.72)
								c.metallic_specular = minf(c.metallic_specular, 0.25)
								_mat_norm_cache[k] = c
							mi.set_surface_override_material(si, c)
			for ch in cur.get_children():
				stack.append(ch)
	return inst


func _place_piece(parent: Node3D, file_name: String, pos: Vector3, rot_y: float = 0.0, scl: Vector3 = Vector3.ONE) -> Node3D:
	var n := _load_piece(file_name)
	if n == null:
		return null
	n.position = pos
	n.rotation.y = rot_y
	n.scale = scl
	parent.add_child(n)
	return n


func _place_nature_scene(parent: Node3D, gltf_path: String, pos: Vector3, rot_y: float, scl: float) -> Node3D:
	var ps: PackedScene = _scene_cache.get(gltf_path, null)
	if ps == null:
		ps = load(gltf_path) as PackedScene
		if ps == null:
			return null
		_scene_cache[gltf_path] = ps
	var inst := ps.instantiate() as Node3D
	if inst != null:
		inst.position = pos
		inst.rotation.y = rot_y
		inst.scale = Vector3.ONE * scl
		parent.add_child(inst)
	return inst


func _add_box_body(parent: Node3D, pos: Vector3, size: Vector3, layer: int, rot_x: float = 0.0, rot_y: float = 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation = Vector3(rot_x, rot_y, 0.0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


func _add_flicker_light(parent: Node3D, pos: Vector3, col: Color, energy: float, radius: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = radius
	l.omni_attenuation = 1.35
	l.shadow_enabled = false
	parent.add_child(l)
	_flicker_lights.append({
		"light": l,
		"base": energy,
		"phase": float(_flicker_lights.size()) * 1.73,
	})


# ==============================================================================
# 1. SPIDER SILK FOREST (WEBWOOD, -410, y, 480)
# ==============================================================================

func _build_spider_webwood(spider_trees: Array[Dictionary], webwood_region: WebwoodRegion = null) -> void:
	_spider_root = Node3D.new()
	_spider_root.name = "SpiderWebwood"
	add_child(_spider_root)
	WorldLandmarks.sticky_web_zones.clear()

	var layout: Dictionary = webwood_region.get_effective_layout() if webwood_region != null else {}
	var center: Vector2 = layout.get("center", WorldLandmarks.SPIDER_FOREST_CENTER)
	var cy := _sample_h(center.x, center.y)

	# Irregular banks of stone break up sightlines without enclosing the brood hollow.
	var boulder_pts: Array[Vector3] = []
	var rock_offsets: Array[Vector2] = [Vector2(-8, 5), Vector2(-12, 8), Vector2(-16, 6), Vector2(9, 10), Vector2(14, 13), Vector2(-10, -12)]
	for i in range(rock_offsets.size()):
		var rx := center.x + rock_offsets[i].x
		var rz := center.y + rock_offsets[i].y
		var ry := _sample_h(rx, rz)
		boulder_pts.append(Vector3(rx, ry, rz))
		CavePropFX.spawn_fractured_boulder(
			_spider_root,
			Vector3(rx, ry + 0.72, rz),
			Vector3(2.1 + float(i % 3) * 0.35, 1.55, 1.90),
			_webwood_rock_mat,
			200 + i,
			true
		)

	# Scattered ancient trunks hold up the inner silk roof without forming an arena ring.
	var snag_pts: Array[Vector3] = []
	var snag_offsets: Array = layout.get("snag_offsets", WorldLandmarks.SPIDER_NEST_SNAGS)
	for di in range(snag_offsets.size()):
		var off: Vector2 = snag_offsets[di]
		var dx: float = center.x + off.x
		var dz: float = center.y + off.y
		var dy: float = _sample_h(dx, dz)
		snag_pts.append(Vector3(dx, dy, dz))
		var snag := _place_nature_scene(_spider_root, "res://assets/nature_extra/DeadTree_1.gltf", Vector3(dx, dy - 0.12, dz), float(di) * 2.4, 3.9 + 0.4 * float(di % 3))
		if snag != null:
			_add_box_body(_spider_root, Vector3(dx, dy + 2.4, dz), Vector3(1.1, 4.8, 1.1), LAYER_OBSTACLES)

	# Bark-textured fallen hollow trunks with shelf fungi around the glade perimeter
	var log_specs: Array[Array] = [
		[Vector2(center.x - 10.5, center.y - 7.0), 0.55, 6.8, 0.52],
		[Vector2(center.x + 11.2, center.y + 6.4), -0.82, 6.2, 0.48],
	]
	for li in range(log_specs.size()):
		var lx: float = log_specs[li][0].x
		var lz: float = log_specs[li][0].y
		var ly := _sample_h(lx, lz)
		CavePropFX.spawn_bark_fallen_log(
			_spider_root, Vector3(lx, ly + 0.34, lz),
			float(log_specs[li][1]), 0.03, float(log_specs[li][2]), float(log_specs[li][3]),
			40 + li, _bark_mat, true
		)

	# Lush woodland understory & glade-margin ecological gradient: Ferns, Bushes, Mushrooms & Rocks
	var fern_xfs: Array[Transform3D] = []
	var bush_xfs: Array[Transform3D] = []
	var mush_xfs: Array[Transform3D] = []
	var rock_xfs: Array[Transform3D] = []
	for k in range(38):
		var ang := float(k) * 2.39996
		var rad := 5.2 + sqrt(float(k) + 0.5) * 3.6
		var fx := center.x + cos(ang) * rad
		var fz := center.y + sin(ang) * rad
		if WorldLandmarks.min_dist_to_world_road(fx, fz, center) < 5.6:
			continue
		var fy := _sample_h(fx, fz)
		var b := Basis.from_euler(Vector3(0.0, ang * 1.3, 0.0))
		if (k % 3) == 0:
			fern_xfs.append(Transform3D(b.scaled(Vector3.ONE * (1.25 + 0.25 * float(k % 2))), Vector3(fx, fy - 0.04, fz)))
		elif (k % 3) == 1:
			bush_xfs.append(Transform3D(b.scaled(Vector3.ONE * (1.20 + 0.30 * float(k % 2))), Vector3(fx, fy - 0.05, fz)))
		else:
			mush_xfs.append(Transform3D(b.scaled(Vector3.ONE * 1.45), Vector3(fx, fy - 0.02, fz)))
		if (k % 3) == 0 and WorldLandmarks.min_dist_to_world_road(fx + 1.1, fz - 0.8, center) >= 5.6:
			rock_xfs.append(Transform3D(b.scaled(Vector3(1.35, 0.72, 1.35)), Vector3(fx + 1.1, fy - 0.14, fz - 0.8)))

	CavePropFX.spawn_gltf_batch(_spider_root, "WebwoodFerns", "res://assets/nature/Fern_1.gltf", fern_xfs)
	CavePropFX.spawn_gltf_batch(_spider_root, "WebwoodPlants", "res://assets/nature/Plant_1.gltf", bush_xfs)
	CavePropFX.spawn_gltf_batch(_spider_root, "WebwoodMushrooms", "res://assets/nature/Mushroom_Common.gltf", mush_xfs)
	CavePropFX.spawn_gltf_batch(_spider_root, "WebwoodRocks", "res://assets/nature/Rock_Medium_2.gltf", rock_xfs, _granite_shader_mat)

	var orbs := _new_webwood_batches()
	var canopies := _new_webwood_batches()
	var veils := _new_webwood_batches()
	var shrouds := _new_webwood_batches()
	var build_tangled_span := func(p0: Vector3, p1: Vector3, height: float, sag: float) -> void:
		var half := Vector3.UP * height * 0.5
		var seed01 := fposmod(p0.x * 0.129 + p1.z * 0.083, 1.0)
		_emit_webwood_orb(orbs, center, p0 + half, p1 + half, p1 - half * 0.1, p0 - half, sag, seed01, false)
		_emit_webwood_sheet(veils, center, p0 + half * 1.15, p1 + half * 1.15, p0 - half * 0.6, p1 - half * 0.6, sag * 0.8, seed01)
		_emit_webwood_sheet(canopies, center, p0 + half * 1.3, p1 + half * 1.3, p1, p0, sag * 0.6, seed01)

	# Wrap central ancient snags in flared 3D trunk/root silk shrouds + multi-layer tangled drapes
	for si in range(snag_pts.size()):
		var sp := snag_pts[si]
		var seed_s := fposmod(float(si) * 0.371 + sp.x * 0.05, 1.0)
		_emit_trunk_shroud(_webwood_batch_at(shrouds, center, sp), sp - Vector3.UP * 0.15, 0.85, 0.28, 5.8, seed_s)
		var bp := boulder_pts[si % boulder_pts.size()]
		var d_sb := Vector2(sp.x - bp.x, sp.z - bp.z).length()
		if d_sb >= 3.5 and d_sb <= 18.0:
			build_tangled_span.call(
				sp + Vector3(0.0, 2.8, 0.0),
				bp + Vector3(0.0, 1.7, 0.0),
				3.8, 0.58
			)
		if (si % 2) == 0:
			_spawn_sculpted_cocoon(
				_spider_root,
				sp + Vector3(-0.35 * float(1 if si == 0 else -1), 2.35, 0.28),
				Vector3(0.12, float(si) * 1.2, 0.08),
				0.92,
				float(20 + si)
			)

	# Wrap inner/mid spider_trees (R < 78m) in flared 3D silk trunk shrouds anchoring forest silk into root litter
	var shroud_h_scale := float(layout.get("shroud_height_scale", 0.88))
	for ti in range(spider_trees.size()):
		var tr_pos: Vector3 = spider_trees[ti]["position"]
		var tr_dist := Vector2(tr_pos.x - center.x, tr_pos.z - center.y).length()
		if tr_dist < 78.0 and (ti % 2 == 0 or tr_dist < 48.0):
			var sy_t := maxf(float(spider_trees[ti]["scale_y"]), 1.0)
			var sh_h := clampf(sy_t * 3.8, 4.0, 6.2)
			var sh_seed := fposmod(float(ti) * 0.618 + tr_pos.x * 0.03, 1.0)
			_emit_trunk_shroud(_webwood_batch_at(shrouds, center, tr_pos), tr_pos - Vector3.UP * 0.15, 0.72, 0.24, sh_h * shroud_h_scale, sh_seed)

	_weave_webwood_forest(spider_trees, center, orbs, canopies, veils, layout)
	_weave_webwood_crossings(spider_trees, center, orbs, canopies, veils, layout)

	# Multi-layered Brood Silk Cathedral Dome over the central hollow (hero kept strictly in batch 0 -> brood_orbs == 1)
	var left := snag_pts[4]
	var right := snag_pts[3]
	var crown := snag_pts[0] + Vector3.UP * 13.4
	var hero := _new_webwood_batches()
	var upper_left := left + Vector3.UP * 13.0
	var upper_right := right + Vector3.UP * 11.8
	_emit_webwood_orb([hero[0], hero[0], hero[0], hero[0]], center, upper_left, upper_right,
		right + Vector3.UP * 2.1, left + Vector3.UP * 3.2, 1.55, 0.38, true)
	_emit_silk_curve(hero[0], upper_left, upper_right, Vector3.DOWN * 0.85, 0.052)

	var dome_sheets: Array[Array] = [
		[crown, snag_pts[1] + Vector3.UP * 13.0, left + Vector3.UP * 11.0, right + Vector3.UP * 14.2, 2.15, 0.71],
		[right + Vector3.UP * 14.2, snag_pts[2] + Vector3.UP * 11.6, left + Vector3.UP * 11.0, left + Vector3.UP * 11.0, 1.95, 0.19],
		[snag_pts[0] + Vector3.UP * 10.6, snag_pts[3] + Vector3.UP * 10.2, snag_pts[2] + Vector3.UP * 9.8, snag_pts[4] + Vector3.UP * 9.5, 1.85, 0.43],
		[snag_pts[1] + Vector3.UP * 11.4, snag_pts[4] + Vector3.UP * 10.0, snag_pts[0] + Vector3.UP * 10.2, snag_pts[3] + Vector3.UP * 10.6, 1.65, 0.82],
		[snag_pts[2] + Vector3.UP * 9.2, snag_pts[1] + Vector3.UP * 8.8, snag_pts[3] + Vector3.UP * 7.8, snag_pts[4] + Vector3.UP * 7.5, 1.40, 0.27],
		[crown - Vector3.UP * 2.8, snag_pts[2] + Vector3.UP * 8.4, left + Vector3.UP * 7.2, right + Vector3.UP * 7.8, 1.55, 0.56],
		[snag_pts[0] + Vector3.UP * 7.2, snag_pts[1] + Vector3.UP * 7.5, boulder_pts[0] + Vector3.UP * 2.4, boulder_pts[3] + Vector3.UP * 2.6, 1.25, 0.64],
		[snag_pts[2] + Vector3.UP * 7.0, snag_pts[3] + Vector3.UP * 7.4, boulder_pts[4] + Vector3.UP * 2.2, boulder_pts[2] + Vector3.UP * 2.0, 1.20, 0.31],
	]
	for ds: Array in dome_sheets:
		_emit_webwood_sheet(canopies, center, ds[0], ds[1], ds[2], ds[3], float(ds[4]), float(ds[5]))

	var cathedral_curtains: Array[Array] = [
		[crown, left + Vector3.UP * 11.0, crown - Vector3.UP * 6.8, left + Vector3.UP * 4.8, 1.45, 0.61],
		[crown, snag_pts[1] + Vector3.UP * 13.0, crown - Vector3.UP * 6.2, snag_pts[1] + Vector3.UP * 5.2, 1.35, 0.22],
		[snag_pts[1] + Vector3.UP * 11.2, snag_pts[2] + Vector3.UP * 10.6, snag_pts[1] + Vector3.UP * 4.0, snag_pts[2] + Vector3.UP * 3.8, 1.25, 0.48],
		[snag_pts[3] + Vector3.UP * 11.8, snag_pts[2] + Vector3.UP * 10.8, snag_pts[3] + Vector3.UP * 4.2, snag_pts[2] + Vector3.UP * 4.0, 1.30, 0.85],
		[left + Vector3.UP * 10.2, snag_pts[4] + Vector3.UP * 7.2, left + Vector3.UP * 3.5, boulder_pts[1] + Vector3.UP * 1.4, 1.15, 0.14],
		[right + Vector3.UP * 10.4, snag_pts[5 % snag_pts.size()] + Vector3.UP * 8.0, right + Vector3.UP * 3.8, boulder_pts[3] + Vector3.UP * 1.6, 1.15, 0.77],
	]
	for cc: Array in cathedral_curtains:
		_emit_webwood_sheet(veils, center, cc[0], cc[1], cc[2], cc[3], float(cc[4]), float(cc[5]))

	_emit_silk_curve(_webwood_batch_at(orbs, center, crown), crown, snag_pts[1] + Vector3.UP * 13.0, Vector3.DOWN * 1.18, 0.042)
	_emit_silk_curve(_webwood_batch_at(orbs, center, right), right + Vector3.UP * 14.2, snag_pts[2] + Vector3.UP * 11.6, Vector3.DOWN * 1.07, 0.038)

	var drops: Array[Transform3D] = []
	for i in range(8):
		var t := 0.12 + float(i) * 0.105
		var span_p0 := upper_left if (i % 2 == 0) else crown - Vector3.UP * 1.2
		var span_p1 := upper_right if (i % 2 == 0) else snag_pts[2] + Vector3.UP * 10.4
		var anchor := span_p0.lerp(span_p1, t) - Vector3.UP * (sin(t * PI) * 0.92)
		var length := 1.25 + 0.75 * float(i % 3) + 0.25 * float(i % 2)
		var size := 0.72 + 0.16 * float(i % 3)
		drops.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, length, 1.0)), anchor - Vector3.UP * length * 0.5))
		_spawn_sculpted_cocoon(_spider_root, anchor - Vector3.UP * (length + 0.68 * size), Vector3(0.05, float(i) * 0.9, 0.05), size, float(i + 31))
	var strand_mesh := CylinderMesh.new()
	strand_mesh.height = 1.0
	strand_mesh.top_radius = 0.026
	strand_mesh.bottom_radius = 0.026
	strand_mesh.radial_segments = 5
	strand_mesh.rings = 0
	strand_mesh.material = _silk_cord_mat
	var strands := MultiMesh.new()
	strands.transform_format = MultiMesh.TRANSFORM_3D
	strands.mesh = strand_mesh
	strands.instance_count = drops.size()
	for i in range(drops.size()):
		strands.set_instance_transform(i, drops[i])
	var strand_node := MultiMeshInstance3D.new()
	strand_node.name = "BroodCocoonThreads"
	strand_node.multimesh = strands
	strand_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spider_root.add_child(strand_node)
	var canopy_mat := _funnel_web_mat.duplicate() as ShaderMaterial
	canopy_mat.set_shader_parameter(&"web_mode", 4.0)
	canopy_mat.set_shader_parameter(&"silk_color", layout.get("canopy_color", Color(0.77, 0.86, 0.91, 0.80)))
	canopy_mat.set_shader_parameter(&"sway_amp", float(layout.get("canopy_sway_amp", 0.020)))
	var veil_mat := canopy_mat.duplicate() as ShaderMaterial
	veil_mat.set_shader_parameter(&"web_mode", 2.0)
	veil_mat.set_shader_parameter(&"silk_color", layout.get("veil_color", Color(0.75, 0.84, 0.89, 0.74)))
	var shroud_mat := canopy_mat.duplicate() as ShaderMaterial
	shroud_mat.set_shader_parameter(&"web_mode", 3.0)
	shroud_mat.set_shader_parameter(&"silk_color", layout.get("shroud_color", Color(0.76, 0.84, 0.89, 0.82)))
	_commit_webwood_batches(hero, "WebwoodBroodOrb", _silk_cord_mat)
	_commit_webwood_batches(orbs, "WebwoodOrbs", _silk_cord_mat)
	_commit_webwood_batches(canopies, "WebwoodCanopy", canopy_mat)
	_commit_webwood_batches(veils, "WebwoodVeil", veil_mat)
	_commit_webwood_batches(shrouds, "WebwoodShrouds", shroud_mat)

	# 3D Terrain-Draped & Boulder/Root-Sloped Sticky Silk Blankets (no flat pasted quads!)
	var web_patches: Array[Array] = []
	if layout.has("ground_web_patches"):
		for gp: Vector4 in layout["ground_web_patches"]:
			web_patches.append([center + Vector2(gp.x, gp.y), gp.z, gp.w])
	else:
		web_patches = [
			[Vector2(center.x, center.y), 9.6, 0.4],
			[Vector2(center.x - 7.8, center.y - 5.4), 7.4, 1.3],
			[Vector2(center.x + 10.2, center.y - 1.8), 6.8, 2.2],
			[Vector2(center.x - 6.0, center.y + 7.8), 7.2, 3.1],
			[Vector2(center.x + 7.2, center.y + 6.8), 6.6, 4.0],
			[Vector2(center.x - 14.5, center.y + 1.5), 6.4, 5.2],
			[Vector2(center.x + 14.0, center.y + 11.5), 6.2, 6.1],
			[Vector2(center.x - 2.0, center.y - 13.5), 6.5, 7.0],
			[Vector2(center.x + 19.5, center.y - 12.0), 5.8, 7.8],
			[Vector2(center.x - 21.0, center.y - 14.0), 5.8, 8.4],
			[Vector2(center.x - 22.0, center.y + 16.0), 6.0, 9.2],
		]
	var sat_list: Array = layout.get("satellites", WorldLandmarks.SPIDER_NEST_SATELLITES)
	for anchor in sat_list:
		web_patches.append([anchor, 7.2, (anchor as Vector2).x * 0.1])
	if webwood_region != null:
		webwood_region.sticky_web_zones.clear()
	for wp in web_patches:
		var wpos: Vector2 = wp[0]
		var sz: float = float(wp[1])
		_build_draped_ground_web(_spider_root, wpos, sz, float(wp[2]), boulder_pts, snag_pts)
		var zone_rec := {"xz": wpos, "radius": sz * 0.48}
		if webwood_region != null:
			webwood_region.sticky_web_zones.append(zone_rec)
		WorldLandmarks.sticky_web_zones.append(zone_rec)

	# Tuck clustered cocoons around boulder bases & fallen logs rather than a neat geometric ring
	for bi in range(boulder_pts.size()):
		var bp := boulder_pts[bi]
		var to_c := (Vector3(center.x, bp.y, center.y) - bp).normalized()
		for ci in range(3):
			var cpos := bp + to_c * (1.45 + float(ci) * 0.55) + Vector3(-to_c.z, 0.0, to_c.x) * (float(ci) * 0.65 - 0.55)
			cpos.y = _sample_h(cpos.x, cpos.z) + 0.42
			_spawn_sculpted_cocoon(_spider_root, cpos, Vector3(0.45, float(bi) * 1.1 + float(ci), 0.25), 0.74 + 0.16 * float(ci), float(bi * 7 + ci))

	# A warm pocket beneath the cold silk roof tells players where the brood is.
	_add_webwood_egg_cache(center + Vector2(-3.2, 2.4))
	_add_flicker_light(_spider_root, Vector3(center.x - 3.0, cy + 2.7, center.y + 1.0), Color(1.0, 0.68, 0.34), 1.7, 14.0)


func _add_webwood_egg_cache(center: Vector2) -> void:
	var egg := SphereMesh.new()
	egg.radius = 0.5
	egg.height = 1.0
	egg.radial_segments = 10
	egg.rings = 6
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.78, 0.58, 0.36)
	shell.roughness = 0.76
	shell.emission_enabled = true
	shell.emission = Color(0.62, 0.32, 0.09)
	shell.emission_energy_multiplier = 0.28
	egg.material = shell
	var cache := MultiMesh.new()
	cache.transform_format = MultiMesh.TRANSFORM_3D
	cache.mesh = egg
	cache.instance_count = 21
	for i in range(cache.instance_count):
		var angle := float(i) * 2.39996
		var pos := center + Vector2(cos(angle), sin(angle)) * sqrt(float(i) / 20.0) * 3.1
		var height := 0.44 + 0.43 * absf(sin(angle * 1.7))
		var base := Basis.from_euler(Vector3(0.18 * sin(angle), angle, 0.24 * cos(angle)))
		base = base.scaled_local(Vector3(height * 0.76, height, height * 0.81))
		cache.set_instance_transform(i, Transform3D(base, Vector3(pos.x, _sample_h(pos.x, pos.y) + height * 0.4, pos.y)))
	var cluster := MultiMeshInstance3D.new()
	cluster.name = "BroodEggCache"
	cluster.multimesh = cache
	_spider_root.add_child(cluster)


class WebwoodBatch:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()


func _new_webwood_batches() -> Array[WebwoodBatch]:
	var batches: Array[WebwoodBatch] = []
	for i in range(4):
		batches.append(WebwoodBatch.new())
	return batches


func _commit_webwood_batches(batches: Array, label: String, material: Material) -> void:
	for i in range(batches.size()):
		var batch := batches[i] as WebwoodBatch
		if batch == null or batch.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = batch.verts
		arrays[Mesh.ARRAY_NORMAL] = batch.normals
		arrays[Mesh.ARRAY_INDEX] = batch.indices
		if batch.uvs.size() == batch.verts.size():
			arrays[Mesh.ARRAY_TEX_UV] = batch.uvs
		if batch.colors.size() == batch.verts.size():
			arrays[Mesh.ARRAY_COLOR] = batch.colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.name = "%s_%d" % [label, i]
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spider_root.add_child(instance)


func _webwood_batch_at(batches: Array, center: Vector2, point: Vector3) -> WebwoodBatch:
	return batches[int(point.x >= center.x) + 2 * int(point.z >= center.y)] as WebwoodBatch


func _emit_silk_segment(batch: WebwoodBatch, a: Vector3, b: Vector3, radius: float) -> void:
	var axis := (b - a).normalized()
	if axis.is_zero_approx():
		return
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.94 else Vector3.RIGHT).normalized()
	var other := axis.cross(side)
	# A three-sided filament is visible edge-on; emit 12 verts + 18 indices directly (no temp array or st.index()).
	var r0 := side * radius
	var r1 := (side * -0.5 + other * 0.866) * radius
	var r2 := (side * -0.5 - other * 0.866) * radius
	var base := batch.verts.size()
	for face_idx in range(3):
		var p := r0 if face_idx == 0 else (r1 if face_idx == 1 else r2)
		var q := r1 if face_idx == 0 else (r2 if face_idx == 1 else r0)
		var n := (p + q).normalized()
		var v0 := base + face_idx * 4
		batch.verts.append(a + p)
		batch.verts.append(b + p)
		batch.verts.append(b + q)
		batch.verts.append(a + q)
		batch.normals.append(n)
		batch.normals.append(n)
		batch.normals.append(n)
		batch.normals.append(n)
		batch.indices.append(v0)
		batch.indices.append(v0 + 1)
		batch.indices.append(v0 + 2)
		batch.indices.append(v0)
		batch.indices.append(v0 + 2)
		batch.indices.append(v0 + 3)


func _emit_silk_curve(batch: WebwoodBatch, a: Vector3, b: Vector3, sag: Vector3, radius: float, steps: int = 6) -> void:
	var previous := a
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var point := a.lerp(b, t) + sag * sin(t * PI)
		_emit_silk_segment(batch, previous, point, radius)
		previous = point


func _emit_webwood_orb(batches: Array, center: Vector2, a: Vector3, b: Vector3, c: Vector3, d: Vector3, belly: float, seed01: float, focal: bool) -> void:
	# Sculpted 3D radial + catenary-ring spider web lattice suspended with true out-of-plane depth
	var mid := (a + b + c + d) * 0.25
	var raw_n := (b - a).cross(d - a)
	var normal := raw_n.normalized() if raw_n.length_squared() > 0.001 else Vector3.UP
	var hub := mid + normal * (belly * 0.95) + Vector3.DOWN * 0.30
	var st := _webwood_batch_at(batches, center, mid)
	var thick := 0.044 if focal else 0.030
	# Perimeter anchor mooring cables
	_emit_silk_curve(st, a, b, Vector3.DOWN * 0.30 + normal * belly * 0.24, thick, 6)
	_emit_silk_curve(st, b, c, Vector3.DOWN * 0.20 + normal * belly * 0.18, thick * 0.85, 5)
	_emit_silk_curve(st, c, d, Vector3.DOWN * 0.26 + normal * belly * 0.22, thick * 0.88, 5)
	_emit_silk_curve(st, d, a, Vector3.DOWN * 0.20 + normal * belly * 0.18, thick * 0.85, 5)

	# 8–10 radial spokes converging on off-center 3D hub
	var anchors: Array[Vector3] = [
		a, a.lerp(b, 0.45), b, b.lerp(c, 0.52), c, c.lerp(d, 0.48), d, d.lerp(a, 0.54)
	]
	if focal:
		anchors.append(a.lerp(b, 0.78))
		anchors.append(c.lerp(d, 0.22))
	for ai in range(anchors.size()):
		var ap: Vector3 = anchors[ai]
		_emit_silk_curve(st, hub, ap, Vector3.DOWN * 0.18 + normal * (belly * 0.12), 0.022 if focal else 0.016, 4)

	# 3 concentric catenary silk spiral rings joining the 3D spokes
	var ring_count := 3 if focal else 2
	for ri in range(1, ring_count + 1):
		var frac := float(ri) / float(ring_count + 1)
		for ai in range(anchors.size()):
			var p0 := hub.lerp(anchors[ai], frac)
			var p1 := hub.lerp(anchors[(ai + 1) % anchors.size()], frac + 0.04 * sin(seed01 * TAU + float(ai)))
			_emit_silk_curve(st, p0, p1, Vector3.DOWN * 0.14 + normal * (belly * 0.08), 0.016 if focal else 0.013, 3)

	var chords := 8 if focal else 4
	var edge_pairs := [[a, b], [b, c], [c, d], [d, a]]
	for ci in range(chords):
		var u0 := fposmod(seed01 * 3.7 + float(ci) * 0.618034, 1.0)
		var u1 := fposmod(seed01 * 5.3 + float(ci) * 0.381966 + 0.19, 1.0)
		var e0 := ci % 4
		var e1 := (ci + 1 + (ci % 2)) % 4
		var p0: Vector3 = (edge_pairs[e0][0] as Vector3).lerp(edge_pairs[e0][1] as Vector3, u0)
		var p1: Vector3 = (edge_pairs[e1][0] as Vector3).lerp(edge_pairs[e1][1] as Vector3, u1)
		var sag_v := Vector3.DOWN * (0.24 + 0.20 * u0) + normal * belly * (0.35 + 0.35 * sin(u1 * PI))
		_emit_silk_curve(st, p0, p1, sag_v, 0.018 if focal else 0.014, 4)


func _emit_trunk_shroud(batch: WebwoodBatch, base_pos: Vector3, base_r: float, top_r: float, height: float, seed01: float) -> void:
	const SIDES := 6
	const RINGS := 4
	var col := Color(seed01, 1.15, 1.0)
	var ring_pts: Array = []
	for ri in range(RINGS + 1):
		var v := float(ri) / float(RINGS)
		var y := (1.0 - v) * height
		# Flare root base out aggressively (2.1x) so silk wraps down seamlessly into soil/webs
		var root_flare := pow(v, 3.0) * base_r * 1.15
		var rad := lerpf(top_r, base_r, v) + root_flare
		var row: Array[Vector3] = []
		for si in range(SIDES + 1):
			var u := float(si) / float(SIDES)
			var ang := u * TAU + v * 0.45 * sin(seed01 * TAU)
			var warp := 1.0 + 0.18 * sin(ang * 3.0 + seed01 * 9.0 + v * 4.0)
			row.append(base_pos + Vector3(cos(ang) * rad * warp, y, sin(ang) * rad * warp))
		ring_pts.append(row)
	for ri in range(RINGS):
		var v0 := float(ri) / float(RINGS)
		var v1 := float(ri + 1) / float(RINGS)
		for si in range(SIDES):
			var u0 := float(si) / float(SIDES)
			var u1 := float(si + 1) / float(SIDES)
			var p00: Vector3 = ring_pts[ri][si]
			var p10: Vector3 = ring_pts[ri][si + 1]
			var p01: Vector3 = ring_pts[ri + 1][si]
			var p11: Vector3 = ring_pts[ri + 1][si + 1]
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.length_squared() < 0.2:
				n = Vector3.UP
			var base := batch.verts.size()
			batch.verts.append(p00)
			batch.verts.append(p10)
			batch.verts.append(p11)
			batch.verts.append(p01)
			batch.normals.append(n)
			batch.normals.append(n)
			batch.normals.append(n)
			batch.normals.append(n)
			batch.colors.append(col)
			batch.colors.append(col)
			batch.colors.append(col)
			batch.colors.append(col)
			batch.uvs.append(Vector2(u0, v0))
			batch.uvs.append(Vector2(u1, v0))
			batch.uvs.append(Vector2(u1, v1))
			batch.uvs.append(Vector2(u0, v1))
			batch.indices.append(base)
			batch.indices.append(base + 1)
			batch.indices.append(base + 2)
			batch.indices.append(base)
			batch.indices.append(base + 2)
			batch.indices.append(base + 3)


func _build_draped_ground_web(parent: Node3D, center_xz: Vector2, size_m: float, seed_f: float, boulders: Array[Vector3], snags: Array[Vector3]) -> void:
	const SUB := 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size_m * 0.5
	var cos_r := cos(seed_f)
	var sin_r := sin(seed_f)
	var col := Color(fposmod(seed_f * 0.27, 1.0), clampf(size_m / 6.2, 0.9, 1.5), 1.0)
	var grid: Array = []
	for zi in range(SUB + 1):
		var v := float(zi) / float(SUB)
		var lz := (v - 0.5) * size_m
		var row: Array[Vector3] = []
		for xi in range(SUB + 1):
			var u := float(xi) / float(SUB)
			var lx := (u - 0.5) * size_m
			var wx := center_xz.x + lx * cos_r - lz * sin_r
			var wz := center_xz.y + lx * sin_r + lz * cos_r
			var wy := _sample_h(wx, wz) + 0.11
			var rad_n := clampf(Vector2(lx, lz).length() / maxf(half, 0.5), 0.0, 1.0)
			var lift := (1.0 - rad_n) * 0.16 + 0.08 * sin(wx * 0.8 + wz * 0.7 + seed_f)
			for bp in boulders:
				var d_b := Vector2(wx - bp.x, wz - bp.z).length()
				if d_b < 2.8:
					lift = maxf(lift, (1.0 - d_b / 2.8) * 0.98)
			for sp in snags:
				var d_s := Vector2(wx - sp.x, wz - sp.z).length()
				if d_s < 2.2:
					lift = maxf(lift, (1.0 - d_s / 2.2) * 1.15)
			row.append(Vector3(wx, wy + lift, wz))
		grid.append(row)
	var norms: Array = []
	for zi in range(SUB + 1):
		var nrow: Array[Vector3] = []
		for xi in range(SUB + 1):
			var pL: Vector3 = grid[zi][maxi(xi - 1, 0)]
			var pR: Vector3 = grid[zi][mini(xi + 1, SUB)]
			var pD: Vector3 = grid[maxi(zi - 1, 0)][xi]
			var pU: Vector3 = grid[mini(zi + 1, SUB)][xi]
			var vn := (pU - pD).cross(pR - pL).normalized()
			if vn.length_squared() < 0.2:
				vn = Vector3.UP
			elif vn.y < 0.0:
				vn = -vn
			nrow.append(vn)
		norms.append(nrow)
	for zi in range(SUB):
		for xi in range(SUB):
			var u0 := float(xi) / float(SUB)
			var u1 := float(xi + 1) / float(SUB)
			var v0 := float(zi) / float(SUB)
			var v1 := float(zi + 1) / float(SUB)
			var corners: Array[Array] = [
				[grid[zi][xi], norms[zi][xi], Vector2(u0, v0)],
				[grid[zi][xi + 1], norms[zi][xi + 1], Vector2(u1, v0)],
				[grid[zi + 1][xi + 1], norms[zi + 1][xi + 1], Vector2(u1, v1)],
				[grid[zi][xi], norms[zi][xi], Vector2(u0, v0)],
				[grid[zi + 1][xi + 1], norms[zi + 1][xi + 1], Vector2(u1, v1)],
				[grid[zi + 1][xi], norms[zi + 1][xi], Vector2(u0, v1)],
			]
			for vert: Array in corners:
				st.set_normal(vert[1] as Vector3)
				st.set_color(col)
				st.set_uv(vert[2] as Vector2)
				st.add_vertex(vert[0] as Vector3)
	var mesh := st.commit()
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _funnel_web_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

	# Anchor 3D tension cords from the funnel core out to perimeter terrain anchors
	var cord_batch := WebwoodBatch.new()
	var mid_p: Vector3 = grid[SUB / 2][SUB / 2] + Vector3.UP * 0.25
	var corner_cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, SUB - 1), Vector2i(SUB - 1, SUB - 1), Vector2i(SUB - 1, 1)]
	for ci in range(4):
		var c_idx: Vector2i = corner_cells[ci]
		var edge_p: Vector3 = grid[c_idx.x][c_idx.y]
		_emit_silk_curve(cord_batch, mid_p, edge_p, Vector3.UP * 0.14, 0.024, 4)
	if not cord_batch.verts.is_empty():
		var c_arr := []
		c_arr.resize(Mesh.ARRAY_MAX)
		c_arr[Mesh.ARRAY_VERTEX] = cord_batch.verts
		c_arr[Mesh.ARRAY_NORMAL] = cord_batch.normals
		c_arr[Mesh.ARRAY_INDEX] = cord_batch.indices
		var cm := ArrayMesh.new()
		cm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c_arr)
		var cmi := MeshInstance3D.new()
		cmi.mesh = cm
		cmi.material_override = _silk_cord_mat
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(cmi)


func _emit_webwood_sheet(batches: Array, center: Vector2, a: Vector3, b: Vector3, c: Vector3, d: Vector3, sag: float, seed01: float) -> void:
	var mid := (a + b + c + d) * 0.25
	var quadrant := int(mid.x >= center.x) + 2 * int(mid.z >= center.y)
	var batch := batches[quadrant] as WebwoodBatch
	var raw_n := (b - a).cross(c - a)
	if raw_n.length_squared() < 0.05:
		return
	var normal := raw_n.normalized()
	const STEPS := 7
	var tapered := c.is_equal_approx(d)
	var col := Color(seed01, clampf(a.distance_to(b) / 11.0, 0.65, 1.6), 1.0)
	var base := batch.verts.size()
	var stride := STEPS + 1
	var grid_pts: Array = []
	for row in range(STEPS + 1):
		var v := float(row) / float(STEPS)
		var grow: Array[Vector3] = []
		for col_idx in range(STEPS + 1):
			var u := float(col_idx) / float(STEPS)
			var p := a.lerp(b, u).lerp(c.lerp(d, u), v)
			p.y -= sin(u * PI) * lerpf(0.55, 1.0, v) * sag
			p += normal * (sin(u * PI) * sin(v * PI) * sag * 0.42)
			grow.append(p)
		grid_pts.append(grow)
	for row in range(STEPS + 1):
		var v := float(row) / float(STEPS)
		for col_idx in range(STEPS + 1):
			var u := float(col_idx) / float(STEPS)
			var p: Vector3 = grid_pts[row][col_idx]
			var pL: Vector3 = grid_pts[row][maxi(col_idx - 1, 0)]
			var pR: Vector3 = grid_pts[row][mini(col_idx + 1, STEPS)]
			var pD: Vector3 = grid_pts[maxi(row - 1, 0)][col_idx]
			var pU: Vector3 = grid_pts[mini(row + 1, STEPS)][col_idx]
			var vn := (pR - pL).cross(pU - pD).normalized()
			if vn.length_squared() < 0.2:
				vn = normal
			batch.verts.append(p)
			batch.normals.append(vn)
			batch.colors.append(col)
			batch.uvs.append(Vector2(u, v))
	for row in range(STEPS):
		for col_idx in range(STEPS):
			var i00 := base + row * stride + col_idx
			var i10 := i00 + 1
			var i01 := i00 + stride
			var i11 := i01 + 1
			batch.indices.append(i00)
			batch.indices.append(i10)
			batch.indices.append(i11)
			if not (tapered and row == STEPS - 1):
				batch.indices.append(i00)
				batch.indices.append(i11)
				batch.indices.append(i01)


func _weave_webwood_forest(trees: Array[Dictionary], center: Vector2, orbs: Array, canopies: Array, veils: Array, layout: Dictionary = {}) -> void:
	const CELL := 24.0
	var grid := {}
	for ti in range(trees.size()):
		var p: Vector3 = trees[ti]["position"]
		var cell := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not grid.has(cell):
			grid[cell] = []
		(grid[cell] as Array).append(ti)

	var trail_start: Vector2 = layout.get("trail_start", WorldLandmarks.SPIDER_TRAIL_START)
	var neighbor_range := float(layout.get("silk_neighbor_range", 23.0))
	var neighbor_sq := neighbor_range * neighbor_range
	var road := (trail_start - center).normalized()
	var linked := {}
	for i in range(trees.size()):
		var a: Vector3 = trees[i]["position"]
		var axz := Vector2(a.x, a.z)
		var radius := axz.distance_to(center)
		var stride := 1 if radius < 68.0 else (2 if radius < 124.0 else 4)
		if i % stride != 0:
			continue
		var best_list: Array[int] = [-1, -1]
		var best_d := [neighbor_sq, neighbor_sq]
		var acell := Vector2i(floori(a.x / CELL), floori(a.z / CELL))
		for gx in range(acell.x - 1, acell.x + 2):
			for gz in range(acell.y - 1, acell.y + 2):
				var bucket = grid.get(Vector2i(gx, gz))
				if bucket == null:
					continue
				for j_var in bucket:
					var j: int = j_var
					if j == i or linked.has(Vector2i(mini(i, j), maxi(i, j))):
						continue
					var pos: Vector3 = trees[j]["position"]
					var delta := pos - a
					var dist_sq := Vector2(delta.x, delta.z).length_squared()
					if dist_sq > 4.5 * 4.5 and absf(delta.y) < 5.5:
						if dist_sq < best_d[0] or (dist_sq == best_d[0] and j < best_list[0]):
							best_d[1] = best_d[0]
							best_list[1] = best_list[0]
							best_d[0] = dist_sq
							best_list[0] = j
						elif dist_sq < best_d[1] or (dist_sq == best_d[1] and j < best_list[1]):
							best_d[1] = dist_sq
							best_list[1] = j
		for bi in range(2):
			var nearest := best_list[bi]
			if nearest < 0:
				continue
			if bi == 1 and radius >= 72.0:
				continue
			linked[Vector2i(mini(i, nearest), maxi(i, nearest))] = true
			var b: Vector3 = trees[nearest]["position"]
			var bxz := Vector2(b.x, b.z)
			var seed01 := fposmod(float(i * 3 + bi) * 0.618034, 1.0)
			var up_a := Vector3.UP * float(trees[i]["scale_y"])
			var up_b := Vector3.UP * float(trees[nearest]["scale_y"])
			var side_a := road.cross(axz - center)
			var side_b := road.cross(bxz - center)
			var near_trail := road.dot((axz + bxz) * 0.5 - center) > -6.0 and (side_a * side_b <= 0.0 or minf(absf(side_a), absf(side_b)) < 5.0)
			if near_trail or radius < 126.0:
				var mid := (a + b) * 0.5
				var across := Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized()
				var third := -1
				var third_dist := 19.0 * 19.0
				var mcell := Vector2i(floori(mid.x / CELL), floori(mid.z / CELL))
				for gx in range(mcell.x - 1, mcell.x + 2):
					for gz in range(mcell.y - 1, mcell.y + 2):
						var bucket = grid.get(Vector2i(gx, gz))
						if bucket == null:
							continue
						for k_var in bucket:
							var k: int = k_var
							var pos: Vector3 = trees[k]["position"]
							var delta := pos - mid
							var dist_sq := delta.length_squared()
							if (dist_sq < third_dist or (dist_sq == third_dist and k < third)) and absf(delta.dot(across)) > 4.2 and absf(delta.y) < 5.0:
								third = k
								third_dist = dist_sq
				if third >= 0:
					var c: Vector3 = trees[third]["position"]
					c.y += maxf(7.5, float(trees[third]["scale_y"]) * 3.35)
					_emit_webwood_sheet(canopies, center, a + up_a * 3.6, b + up_b * 3.6, c, c, 1.45, seed01)
			if not near_trail:
				# Multi-tiered thick cobweb drapery + structural cables spanning vertical space between trunks
				_emit_webwood_sheet(canopies, center, a + up_a * 2.8, b + up_b * 2.6, b + up_b * 0.9, a + up_a * 0.8, 0.95, seed01)
				_emit_webwood_orb(orbs, center, a + up_a * 2.4, b + up_b * 2.2, b + up_b * 0.75, a + up_a * 0.65, 0.72, seed01, false)
				_emit_webwood_sheet(veils, center, a + up_a * 3.3, b + up_b * 3.0, a + up_a * 0.45, b + up_b * 0.65, 1.05, seed01)


func _weave_webwood_crossings(trees: Array[Dictionary], center: Vector2, orbs: Array, canopies: Array, veils: Array, layout: Dictionary = {}) -> void:
	var start: Vector2 = layout.get("trail_start", WorldLandmarks.SPIDER_TRAIL_START)
	var end: Vector2 = layout.get("trail_bend", WorldLandmarks.SPIDER_TRAIL_BEND)
	var forward := (end - start).normalized()
	var across := Vector2(-forward.y, forward.x)
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	for idx_t in range(7):
		var t: float = [0.16, 0.28, 0.40, 0.52, 0.64, 0.77, 0.90][idx_t]
		var station := start.lerp(end, t)
		var left := _webwood_trail_anchor(trees, station, forward, across, -1.0)
		var right := _webwood_trail_anchor(trees, station, forward, across, 1.0)
		if left.is_empty() or right.is_empty():
			continue
		var a: Vector3 = left["position"]
		var b: Vector3 = right["position"]
		var deck := maxf(maxf(a.y, b.y), _sample_h(station.x, station.y))
		if deck - minf(a.y, b.y) > 4.5:
			continue
		var a_top := Vector3(a.x, deck + 7.2 + sin(t * 9.0) * 0.8, a.z)
		var b_top := Vector3(b.x, deck + 8.4 + cos(t * 7.0) * 0.7, b.z)
		_emit_silk_curve(_webwood_batch_at(orbs, center, (a_top + b_top) * 0.5), a_top, b_top, Vector3.DOWN * 0.95, 0.042)
		_emit_webwood_sheet(canopies, center, a_top, b_top, a_top + Vector3.UP * 2.4, b_top + Vector3.UP * 1.6, 1.55, t)
		if prev_a != Vector3.ZERO:
			_emit_webwood_sheet(canopies, center, prev_a, prev_b, b_top, a_top, 1.35, t + 0.15)
		prev_a = a_top
		prev_b = b_top
		# Heavy tattered curtain drapes framing both shoulders of the silk trail tunnel
		var sh_l := a_top.lerp(b_top, 0.26)
		var sh_r := b_top.lerp(a_top, 0.26)
		_emit_webwood_sheet(veils, center, a_top, sh_l, a_top - Vector3.UP * 5.6, sh_l - Vector3.UP * 3.4, 0.75, t)
		_emit_webwood_sheet(veils, center, b_top, sh_r, b_top - Vector3.UP * 5.4, sh_r - Vector3.UP * 3.2, 0.75, t + 0.3)


func _webwood_trail_anchor(trees: Array[Dictionary], station: Vector2, forward: Vector2, across: Vector2, side: float) -> Dictionary:
	var best: Dictionary = {}
	var score := INF
	for tree in trees:
		var p: Vector3 = tree["position"]
		var delta := Vector2(p.x, p.z) - station
		var lateral := delta.dot(across) * side
		var along := absf(delta.dot(forward))
		if lateral < 4.0 or lateral > 17.0 or along > 12.0:
			continue
		var candidate := absf(lateral - 7.0) + along * 1.25
		if candidate < score:
			best = tree
			score = candidate
	return best


func _spawn_sculpted_cocoon(parent: Node3D, pos: Vector3, rot: Vector3, scale_m: float, seed_v: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var segs := 12
	var pts: Array = []
	var uvs: Array = []
	var cols: Array = []
	var outs: Array = []
	for ri in range(rings + 1):
		var v := float(ri) / float(rings)  # 0=bottom pinched tip, 1=top tied silk knot
		var y := (v - 0.5) * 1.45 * scale_m
		# Asymmetric pear-teardrop mummy wrap profile with cinched binding bands
		var base_prof := sin(pow(v, 0.82) * PI)
		var bind_pinch := 1.0 - 0.14 * pow(absf(sin(v * PI * 4.5)), 3.0)
		var r := (0.04 + 0.44 * base_prof * bind_pinch) * scale_m
		var rp: Array[Vector3] = []
		var ruv: Array[Vector2] = []
		var rc: Array[Color] = []
		var ro: Array[Vector3] = []
		for si in segs:
			var u := float(si) / float(segs)
			var ang := u * TAU
			var crease := 1.0 + 0.08 * sin(ang * 3.0 + v * 9.0 + seed_v)
			var px := cos(ang) * r * crease
			var pz := sin(ang) * r * crease
			rp.append(Vector3(px, y, pz))
			ruv.append(Vector2(u, v))
			var shade := lerpf(0.74, 0.98, 0.5 + 0.5 * sin(v * PI * 4.5))
			rc.append(Color(shade, shade, shade))
			ro.append(Vector3(px, y * 0.25, pz).normalized())
		pts.append(rp); uvs.append(ruv); cols.append(rc); outs.append(ro)
	CavePropFX._shared_cache["temp_wrap"] = true
	preload("res://terrain/cave_system.gd")._emit_smooth_grid(st, pts, uvs, cols, outs, false, true, false, 0.0)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _cocoon_mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


# ==============================================================================
# 2. WOLF PACK CRAG (Howlcrest Pine Grove at (290, -240))
# ==============================================================================

func _build_wolf_crag(wolf_region: Node = null) -> void:
	var root := Node3D.new()
	root.name = "WolfPackCrag"
	add_child(root)

	var w_cfg: Dictionary = wolf_region.call("get_effective_settings") if (wolf_region != null and wolf_region.has_method("get_effective_settings")) else {}
	var center: Vector2 = w_cfg.get("crag_center", WorldLandmarks.WOLF_CRAG_CENTER)
	var cy := _sample_h(center.x, center.y)

	# Baked SurfaceNets granite wolf-den cave overhang facing +Z toward the clearing
	CavePropFX.mount_baked_cavern(
		root, ASSET_DIR + "wolf_den", _granite_shader_mat, false, Vector3(center.x, cy, center.y)
	)

	# Cool static skylight/moonlight ambient fill inside wolf-den recess (ZERO fire/torch lights in wolf territory)
	var den_fill := OmniLight3D.new()
	den_fill.position = Vector3(center.x, cy + 2.4, center.y - 6.8)
	den_fill.light_color = Color(0.60, 0.74, 0.94)
	den_fill.light_energy = 1.35
	den_fill.omni_range = 14.0
	den_fill.omni_attenuation = 1.2
	den_fill.shadow_enabled = false
	root.add_child(den_fill)

	# Scattered low mossy scree pebbles inside den mouth (cleanly grounded, zero flat grey square plates)
	for scree_off: Array in [
		[Vector2(-3.2, -3.5), Vector3(0.48, 0.20, 0.42), 11],
		[Vector2(3.6, -2.8), Vector3(0.52, 0.22, 0.44), 12],
		[Vector2(-1.8, -5.8), Vector3(0.42, 0.18, 0.38), 13],
	]:
		var so: Vector2 = scree_off[0]
		var sx := center.x + so.x
		var sz := center.y + so.y
		CavePropFX.spawn_fractured_boulder(root, Vector3(sx, _sample_h(sx, sz) + 0.04, sz), scree_off[1], _granite_shader_mat, int(scree_off[2]), false)

	# Mossy boulder cluster and fallen hollow pine trunk on clearing flank (no campfire)
	var flank_pos := Vector3(center.x + 5.2, _sample_h(center.x + 5.2, center.y - 2.6), center.y - 2.6)
	CavePropFX.spawn_fractured_boulder(root, flank_pos + Vector3(0.0, 0.48, 0.0), Vector3(1.15, 0.78, 0.96), _granite_shader_mat, 91, true)
	CavePropFX.spawn_bark_fallen_log(root, flank_pos + Vector3(-1.4, 0.24, 1.1), 0.62, 0.04, 3.2, 0.28, 88, _bark_mat, true)

	# Multi-tiered Alpine Granite Cliff Massif, Flanking Spires & SW Howling Promontory!
	var crag_specs: Array[Array] = [
		[Vector3(-7.6, 1.35, -4.8), Vector3(3.4, 2.8, 3.0)],
		[Vector3(7.9, 1.40, -4.5), Vector3(3.5, 2.9, 3.0)],
		[Vector3(-10.5, 2.05, -9.2), Vector3(4.1, 3.6, 3.4)],
		[Vector3(10.8, 2.10, -8.8), Vector3(4.2, 3.7, 3.4)],
		[Vector3(-16.8, 2.65, -11.5), Vector3(4.6, 4.5, 4.0)],
		[Vector3(17.2, 2.55, -10.8), Vector3(4.5, 4.4, 3.8)],
		[Vector3(-23.5, 2.20, -4.5), Vector3(4.2, 3.8, 3.6)],
		[Vector3(24.0, 2.15, -3.8), Vector3(4.1, 3.6, 3.5)],
		[Vector3(-14.5, 1.65, 8.5), Vector3(3.8, 2.8, 3.2)],  # SW Alpha Howling Promontory
		[Vector3(-11.2, 0.90, 2.6), Vector3(2.6, 1.7, 2.3)],
		[Vector3(11.6, 0.95, 4.0), Vector3(2.7, 1.8, 2.4)],
		[Vector3(0.2, 3.15, -14.2), Vector3(5.6, 4.2, 4.0)],
		[Vector3(-7.4, 2.85, -16.8), Vector3(4.8, 4.6, 3.8)],
		[Vector3(7.8, 2.90, -16.4), Vector3(4.9, 4.7, 3.8)],
	]
	for bi in range(crag_specs.size()):
		var off: Vector3 = crag_specs[bi][0]
		var wx := center.x + off.x
		var wz := center.y + off.z
		CavePropFX.spawn_fractured_boulder(
			root, Vector3(wx, _sample_h(wx, wz) + off.y, wz), crag_specs[bi][1], _granite_shader_mat, 140 + bi, true
		)
	# Layered sculpted granite boulders bridging cliff shoulders AND rear den massif into pine duff floor
	for g_spec: Array in [
		["res://assets/nature/Rock_Medium_1.gltf", Vector2(-6.2, -0.8), 0.4, 1.35],
		["res://assets/nature/Rock_Medium_2.gltf", Vector2(6.8, 0.4), -0.7, 1.40],
		["res://assets/nature/Rock_Medium_3.gltf", Vector2(-9.2, -1.6), 1.2, 1.50],
		["res://assets/nature/Rock_Medium_1.gltf", Vector2(9.4, -1.2), -1.1, 1.55],
		["res://assets/nature/Rock_Medium_2.gltf", Vector2(-19.5, 1.5), 0.65, 1.75],
		["res://assets/nature/Rock_Medium_3.gltf", Vector2(20.2, 2.2), -0.85, 1.70],
		# Rear/flank alpine shoulder buttresses cloaking back of Wolf Den dome (seen from N/E/W approaches)
		["res://assets/nature/Rock_Medium_2.gltf", Vector2(-8.6, -13.4), 0.85, 1.95],
		["res://assets/nature/Rock_Medium_3.gltf", Vector2(8.8, -13.0), -0.95, 1.95],
		["res://assets/nature/Rock_Medium_1.gltf", Vector2(-4.4, -16.8), 2.1, 2.15],
		["res://assets/nature/Rock_Medium_2.gltf", Vector2(4.6, -16.6), -1.8, 2.15],
		["res://assets/nature/Rock_Medium_3.gltf", Vector2(0.2, -18.2), 0.3, 2.25],
	]:
		var goff: Vector2 = g_spec[1]
		var gx: float = center.x + goff.x
		var gz: float = center.y + goff.y
		var gy := _sample_h(gx, gz) - 0.35
		var rn := _place_nature_scene(root, String(g_spec[0]), Vector3(gx, gy, gz), float(g_spec[2]), float(g_spec[3]))
		if rn != null:
			_apply_mat_recursive(rn, _granite_shader_mat)

	# Natural alpine granite boundary monoliths flanking the South trail threshold (NO fire/torches or low-poly pillars)
	for cairn_spec: Array in [
		[Vector2(-11.2, 12.8), 0.45, 421],
		[Vector2(11.6, 11.4), -0.55, 422],
	]:
		var coff: Vector2 = cairn_spec[0]
		var cx_c := center.x + coff.x
		var cz_c := center.y + coff.y
		var cy_c := _sample_h(cx_c, cz_c)
		var cyaw := float(cairn_spec[1])
		CavePropFX.spawn_fractured_boulder(root, Vector3(cx_c, cy_c + 1.05, cz_c), Vector3(1.45, 2.35, 1.35), _granite_shader_mat, int(cairn_spec[2]), true)
		var side_b := _place_nature_scene(root, "res://assets/nature/Rock_Medium_2.gltf", Vector3(cx_c + 1.25, _sample_h(cx_c + 1.25, cz_c - 0.5) - 0.25, cz_c - 0.5), cyaw, 1.55)
		if side_b != null:
			_apply_mat_recursive(side_b, _granite_shader_mat)

	# Alpha's Howling Overlook Ledge on WSW shoulder (center + (-13.5, y, 4.2))
	var howl_xy := Vector2(center.x - 13.5, center.y + 4.2)
	var howl_y := _sample_h(howl_xy.x, howl_xy.y)
	for hs_i in range(3):
		var hx := howl_xy.x + float(hs_i) * 1.45 - 1.2
		var hz := howl_xy.y + float(hs_i % 2) * 1.1
		var hslab := _place_nature_scene(root, "res://assets/nature/Rock_Medium_2.gltf", Vector3(hx, _sample_h(hx, hz) - 0.22 + float(hs_i) * 0.22, hz), float(hs_i) * 0.9, 1.0)
		if hslab != null:
			hslab.scale = Vector3(1.75, 0.36, 1.45)
			_apply_mat_recursive(hslab, _granite_shader_mat)
	CavePropFX.spawn_bark_fallen_log(root, Vector3(howl_xy.x + 2.2, howl_y + 0.42, howl_xy.y + 1.8), 0.38, 0.14, 8.4, 0.42, 431, _bark_mat, true)

	# Abandoned Hunter Cache in East crag alcove (high-contrast textured timber & canvas, no mud-crushed albedo)
	var camp_x := center.x + 9.5
	var camp_z := center.y - 3.5
	var camp_y := _sample_h(camp_x, camp_z)
	var h_wag := _place_ruin_wall(root, "res://assets/village/Prop_Wagon.gltf", Vector3(camp_x + 3.4, camp_y - 0.08, camp_z - 1.8), -0.95, Vector3.ONE * 1.55, Vector2(0.16, -0.14), null, true, Vector3(3.7, 2.6, 2.7))
	_harmonize_prop_mats(h_wag, Color(0.76, 0.72, 0.68), 0.85, 0.14)
	var h_cr := _place_piece(root, "crates_stacked.gltf.glb", Vector3(camp_x - 0.8, camp_y - 0.04, camp_z + 2.2), 0.48, Vector3.ONE * 1.55)
	_harmonize_prop_mats(h_cr, Color(0.78, 0.74, 0.68), 0.85, 0.14)
	_add_box_body(root, Vector3(camp_x - 0.8, camp_y + 1.15, camp_z + 2.2), Vector3(2.4, 2.3, 2.4), LAYER_OBSTACLES)
	var h_bar := _place_piece(root, "barrel_large_decorated.gltf.glb", Vector3(camp_x + 1.8, camp_y - 0.04, camp_z + 3.1), -0.65, Vector3.ONE * 1.55)
	_harmonize_prop_mats(h_bar, Color(0.78, 0.74, 0.68), 0.85, 0.14)

	# Sunken flat alpine slate flagstones & a pack bone-cairn breaking up clearing floor silhouettes
	for s_spec: Array in [
		[Vector2(-2.2, 1.8), 0.35, 1.45],
		[Vector2(2.6, 2.4), -0.82, 1.35],
		[Vector2(-0.4, 5.2), 1.15, 1.55],
		[Vector2(3.8, -1.5), -0.25, 1.25],
		[Vector2(-5.4, 2.2), 0.65, 1.30],
		[Vector2(-2.8, 9.5), -0.45, 1.40],
		[Vector2(2.2, 10.8), 0.75, 1.35],
	]:
		var soff: Vector2 = s_spec[0]
		var sx: float = center.x + soff.x
		var sz: float = center.y + soff.y
		var sy := _sample_h(sx, sz)
		var slab := _place_nature_scene(root, "res://assets/nature/Rock_Medium_1.gltf", Vector3(sx, sy - 0.36, sz), float(s_spec[1]), 1.0)
		if slab != null:
			slab.scale = Vector3(float(s_spec[2]), 0.28, float(s_spec[2]) * 0.9)
			_apply_mat_recursive(slab, _granite_shader_mat)
	CavePropFX.spawn_fractured_boulder(root, Vector3(center.x - 6.8, _sample_h(center.x - 6.8, center.y + 3.2) + 0.45, center.y + 3.2), Vector3(1.15, 1.05, 0.95), _granite_shader_mat, 148, true)

	# Gnarled alpine DeadTree snags + expanded mountain pine ferns, bushes & granite rocks fanning to R=37m
	var fern_xfs: Array[Transform3D] = []
	var bush_xfs: Array[Transform3D] = []
	var rock_xfs: Array[Transform3D] = []
	for k in range(48):
		var ang := float(k) * 2.39996
		var rad := 7.5 + float(k) * 0.62
		var fx := center.x + cos(ang) * rad
		var fz := center.y + sin(ang) * rad
		if absf(fx - center.x) < 6.5 and fz < center.y - 2.0:
			continue
		if WorldLandmarks.min_dist_to_world_road(fx, fz) < 6.2:
			continue
		var fy := _sample_h(fx, fz)
		var b := Basis.from_euler(Vector3(0.0, ang, 0.0))
		if (k % 2) == 0:
			fern_xfs.append(Transform3D(b.scaled(Vector3.ONE * 1.35), Vector3(fx, fy - 0.04, fz)))
		else:
			bush_xfs.append(Transform3D(b.scaled(Vector3.ONE * 1.25), Vector3(fx, fy - 0.05, fz)))
		if (k % 3) == 0 and WorldLandmarks.min_dist_to_world_road(fx + 0.8, fz - 0.7) >= 6.2:
			rock_xfs.append(Transform3D(b.scaled(Vector3.ONE * 1.40), Vector3(fx + 0.8, fy - 0.06, fz - 0.7)))

	CavePropFX.spawn_gltf_batch(root, "WolfFerns", "res://assets/nature/Fern_1.gltf", fern_xfs)
	CavePropFX.spawn_gltf_batch(root, "WolfPlants", "res://assets/nature/Plant_1.gltf", bush_xfs)
	CavePropFX.spawn_gltf_batch(root, "WolfRocks", "res://assets/nature/Rock_Medium_1.gltf", rock_xfs, _granite_shader_mat)

	for dt_off: Array in [
		[Vector2(15.5, -4.5), 2.35],
		[Vector2(-15.5, -5.0), 2.35],
		[Vector2(17.5, 9.5), 2.45],
		[Vector2(-17.8, 10.2), 2.40],
		[Vector2(24.0, -14.0), 2.50],
		[Vector2(-24.5, -13.5), 2.50],
		[Vector2(1.5, 23.0), 2.30],
	]:
		var doff: Vector2 = dt_off[0]
		var dx := center.x + doff.x
		var dz := center.y + doff.y
		var dy := _sample_h(dx, dz)
		var snag := _place_nature_scene(root, "res://assets/nature_extra/DeadTree_1.gltf", Vector3(dx, dy - 0.14, dz), dx * 0.35 + dz * 0.25, float(dt_off[1]))
		if snag != null:
			_add_box_body(root, Vector3(dx, dy + 2.4, dz), Vector3(1.1, 4.8, 1.1), LAYER_OBSTACLES)

	# Multi-segment bark-textured fallen timber logs with branch stubs & shelf fungi (5 crag windfalls, off South trail)
	var log_specs: Array[Array] = [
		[Vector2(center.x - 8.5, center.y + 4.0), 0.42, 7.6, 0.52],
		[Vector2(center.x + 8.8, center.y + 3.5), -0.68, 6.8, 0.46],
		[Vector2(center.x + 12.2, center.y + 9.2), 1.35, 5.8, 0.42],
		[Vector2(center.x - 19.5, center.y - 1.5), 0.78, 8.2, 0.50],
		[Vector2(center.x + 19.0, center.y + 1.0), -0.92, 7.8, 0.48],
	]
	var lf_xfs: Array[Transform3D] = []
	for li in range(log_specs.size()):
		var lx: float = log_specs[li][0].x
		var lz: float = log_specs[li][0].y
		var ly := _sample_h(lx, lz)
		CavePropFX.spawn_bark_fallen_log(
			root, Vector3(lx, ly + 0.34, lz),
			float(log_specs[li][1]), 0.04, float(log_specs[li][2]), float(log_specs[li][3]),
			10 + li, _bark_mat, true
		)
		var bf := Basis.from_euler(Vector3(0.0, float(log_specs[li][1]) + 1.2, 0.0)).scaled(Vector3.ONE * 1.4)
		lf_xfs.append(Transform3D(bf, Vector3(lx, ly + float(log_specs[li][3]) * 1.1, lz)))
	CavePropFX.spawn_gltf_batch(root, "WolfLogFungi", "res://assets/nature/Mushroom_Laetiporus.gltf", lf_xfs)

	# Natural clustered prey bone piles tucked beside den threshold, campfire hearth & hunter larder!
	var bone_spots: Array[Array] = [
		[Vector2(-3.2, -5.8), 0.4, 0.95],
		[Vector2(-2.6, -5.2), 1.3, 0.78],
		[Vector2(2.4, -6.1), -0.8, 1.02],
		[Vector2(3.1, -5.5), 2.1, 0.82],
		[Vector2(4.0, -3.5), 0.9, 0.88],
		[Vector2(-4.4, -2.4), -1.6, 0.92],
		[Vector2(-10.6, 12.2), 0.7, 0.90],
		[Vector2(11.0, 10.9), -0.9, 0.94],
		[Vector2(8.8, -2.2), 1.4, 0.96],
		[Vector2(10.2, -1.5), -0.3, 0.86],
	]
	for bsp in bone_spots:
		var bx: float = center.x + bsp[0].x
		var bz: float = center.y + bsp[0].y
		var by := _sample_h(bx, bz)
		_spawn_articulated_bone(root, Vector3(bx, by + 0.09, bz), float(bsp[1]), float(bsp[2]))


func _spawn_articulated_bone(parent: Node3D, pos: Vector3, rot_y: float, length: float) -> void:
	var grp := Node3D.new()
	grp.position = pos
	grp.rotation = Vector3(0.0, rot_y, 0.04)
	parent.add_child(grp)

	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.065
	shaft.bottom_radius = 0.072
	shaft.height = length * 0.78
	shaft.radial_segments = 12
	var sm := MeshInstance3D.new()
	sm.mesh = shaft
	sm.material_override = _bone_mat
	sm.rotation.z = PI * 0.5
	grp.add_child(sm)

	# Four distal condyle knuckles (two pairs flanking both epiphyses)
	var knob := SphereMesh.new()
	knob.radius = 0.11
	knob.height = 0.20
	knob.radial_segments = 12
	knob.rings = 6
	for end_s in [-1.0, 1.0]:
		for k_side in [-1.0, 1.0]:
			var km := MeshInstance3D.new()
			km.mesh = knob
			km.material_override = _bone_mat
			km.position = Vector3(end_s * length * 0.40, 0.015, k_side * 0.075)
			km.scale = Vector3(1.15, 0.85, 0.95)
			grp.add_child(km)


# ==============================================================================
# 3. UNDERGROUND RAT WARREN (-240, y, 280 -> 244)
# ==============================================================================

func _vault_box_mesh(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _vault_box_solid(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, layer: int = LAYER_OBSTACLES, rot_deg: Vector3 = Vector3.ZERO) -> void:
	_vault_box_mesh(parent, pos, sz, mat, rot_deg)
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot_deg
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)


func _vault_brazier(parent: Node3D, pos: Vector3, scale_v: float = 0.85, flame_scale: float = 0.62, energy: float = 2.6, range_m: float = 18.0, light_col: Color = Color(1.0, 0.58, 0.24)) -> void:
	var grp := Node3D.new()
	grp.position = pos
	grp.scale = Vector3.ONE * scale_v
	parent.add_child(grp)

	var base_m := BoxMesh.new()
	base_m.size = Vector3(1.12, 0.24, 1.12)
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = base_m
	base_mi.material_override = _vault_trim_mat
	base_mi.position = Vector3(0.0, 0.12, 0.0)
	grp.add_child(base_mi)

	var ped := CylinderMesh.new()
	ped.top_radius = 0.34
	ped.bottom_radius = 0.46
	ped.height = 0.88
	ped.radial_segments = 8
	var ped_mi := MeshInstance3D.new()
	ped_mi.mesh = ped
	ped_mi.material_override = _vault_trim_mat
	ped_mi.position = Vector3(0.0, 0.56, 0.0)
	grp.add_child(ped_mi)

	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.54
	bowl.bottom_radius = 0.34
	bowl.height = 0.26
	bowl.radial_segments = 8
	var bowl_mi := MeshInstance3D.new()
	bowl_mi.mesh = bowl
	bowl_mi.material_override = _vault_iron_mat
	bowl_mi.position = Vector3(0.0, 1.06, 0.0)
	grp.add_child(bowl_mi)

	_add_box_body(grp, Vector3(0.0, 0.55, 0.0), Vector3(0.9, 1.1, 0.9), LAYER_OBSTACLES)
	_fire_seed_counter += 1
	CavePropFX.attach_torch_fire(grp, Vector3(0.0, 1.16, 0.0), _fire_seed_counter, flame_scale)
	_add_flicker_light(grp, Vector3(0.0, 1.75, 0.0), light_col, energy, range_m)


func _vault_torch(parent: Node3D, pos: Vector3, yaw: float, energy: float = 2.0, range_m: float = 15.0) -> void:
	var tp := _place_piece(parent, "torch_mounted.gltf.glb", pos, yaw, Vector3.ONE * 1.32)
	if tp != null:
		_apply_mat_recursive(tp, _vault_iron_mat)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	_fire_seed_counter += 1
	CavePropFX.attach_torch_fire(parent, pos + fwd * 0.40 + Vector3(0.0, 0.46, 0.0), _fire_seed_counter, 0.48)
	_add_flicker_light(parent, pos + fwd * 0.62 + Vector3(0.0, 0.85, 0.0), Color(1.0, 0.62, 0.26), energy, range_m)


func _vault_post_torch(parent: Node3D, base_pos: Vector3, yaw: float, seed_val: int, energy: float = 2.0, range_m: float = 15.0) -> void:
	# Grounded rough bark timber stake + mounted iron torch (zero mid-air floating sconces!)
	CavePropFX.spawn_bark_fallen_log(parent, base_pos + Vector3(0.0, 1.30, 0.0), yaw, PI * 0.5, 3.1, 0.17, seed_val, _warren_bark_mat, true)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	_vault_torch(parent, base_pos + Vector3(0.0, 2.25, 0.0) + fwd * 0.14, yaw, energy, range_m)


func _harmonize_prop_mats(node: Node, tint_mul: Color = Color(0.56, 0.50, 0.44), min_rough: float = 0.94, max_spec: float = 0.04) -> void:
	if node == null:
		return
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var m := mi.mesh
			if m != null:
				for si in range(m.get_surface_count()):
					var src := mi.get_surface_override_material(si)
					if src == null:
						src = m.surface_get_material(si)
					if src is BaseMaterial3D:
						var dup := src.duplicate() as BaseMaterial3D
						dup.albedo_color = Color(
							dup.albedo_color.r * tint_mul.r,
							dup.albedo_color.g * tint_mul.g,
							dup.albedo_color.b * tint_mul.b,
							dup.albedo_color.a
						)
						dup.roughness = maxf(dup.roughness, min_rough)
						dup.metallic = minf(dup.metallic, 0.15)
						dup.metallic_specular = minf(dup.metallic_specular, max_spec)
						mi.set_surface_override_material(si, dup)
		for ch in cur.get_children():
			stack.append(ch)


func _spawn_vault_crystal_cluster(parent: Node3D, base_pos: Vector3, count: int, seed_val: int) -> void:
	var grp := Node3D.new()
	grp.position = base_pos
	parent.add_child(grp)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in range(count):
		var cy := CylinderMesh.new()
		cy.top_radius = rng.randf_range(0.015, 0.04)
		cy.bottom_radius = rng.randf_range(0.14, 0.25)
		cy.height = rng.randf_range(0.75, 1.65)
		cy.radial_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = cy
		mi.material_override = _vault_crystal_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var yaw := float(i) * (TAU / maxf(1.0, float(count))) + rng.randf_range(-0.35, 0.35)
		var tilt := rng.randf_range(0.18, 0.54)
		mi.rotation = Vector3(cos(yaw) * tilt, yaw, sin(yaw) * tilt)
		mi.position = Vector3(sin(yaw) * 0.16, cy.height * 0.42, cos(yaw) * 0.16)
		grp.add_child(mi)


func _vault_solid_column(parent: Node3D, base_pos: Vector3, height: float, rad: float, yaw: float) -> void:
	# Continuous octagonal inner stone shaft eliminates floating-ring gaps between column.gltf drums
	var shaft := CylinderMesh.new()
	shaft.top_radius = rad * 0.46
	shaft.bottom_radius = rad * 0.54
	shaft.height = height + 0.8
	shaft.radial_segments = 8
	var shaft_mi := MeshInstance3D.new()
	shaft_mi.mesh = shaft
	shaft_mi.material_override = _vault_trim_mat
	shaft_mi.position = base_pos + Vector3(0.0, height * 0.5, 0.0)
	shaft_mi.rotation.y = yaw
	parent.add_child(shaft_mi)

	var step_h := 1.85 * rad
	var h_cur := 0.25 * rad
	while h_cur < height - 1.1 * rad:
		var drum := _place_piece(parent, "column.gltf.glb", base_pos + Vector3(0.0, h_cur, 0.0), yaw, Vector3(1.22 * rad, 1.45 * rad, 1.22 * rad))
		if drum != null:
			_apply_mat_recursive(drum, _vault_trim_mat)
		h_cur += step_h

	CavePropFX.spawn_fractured_boulder(parent, base_pos + Vector3(0.0, 0.55 * rad, 0.0), Vector3(1.55 * rad, 1.25 * rad, 1.55 * rad), _vault_rock_mat, int(absf(base_pos.x + base_pos.z)), false)
	CavePropFX.spawn_fractured_boulder(parent, base_pos + Vector3(0.0, height - 0.15, 0.0), Vector3(1.75 * rad, 1.35 * rad, 1.75 * rad), _vault_rock_mat, int(absf(base_pos.x * 2.0 + base_pos.z)), false)
	_add_box_body(parent, base_pos + Vector3(0.0, height * 0.5, 0.0), Vector3(1.15 * rad, height + 0.4, 1.15 * rad), LAYER_OBSTACLES)


func _vault_timber_bent(parent: Node3D, center: Vector3, half_span: float, height: float, yaw: float, seed_val: int) -> void:
	# Multi-member underground mine shoring arch: heavy posts + cap beam + diagonal knee braces (zero bare goalposts)
	var lat := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var post_h := height + 0.6
	for side_s: float in [-1.0, 1.0]:
		var side_o := side_s * half_span
		var post_pos := center + lat * side_o + Vector3(0.0, height * 0.48, 0.0)
		CavePropFX.spawn_bark_fallen_log(parent, post_pos, yaw, PI * 0.5, post_h, 0.28, seed_val + int(side_s * 7.0), _warren_bark_mat, true)
		var brace_pos := center + lat * (side_o * 0.66) + Vector3(0.0, height - 1.15, 0.0)
		CavePropFX.spawn_bark_fallen_log(parent, brace_pos, yaw + PI * 0.5, -side_s * 0.72, 2.75, 0.18, seed_val + 20 + int(side_s * 5.0), _warren_bark_mat, false)
	CavePropFX.spawn_bark_fallen_log(parent, center + Vector3(0.0, height - 0.18, 0.0), yaw + PI * 0.5, 0.0, half_span * 2.35, 0.31, seed_val + 50, _warren_bark_mat, false)


func _vault_stone_arch_rib(parent: Node3D, left_pt: Vector3, right_pt: Vector3, rise_h: float, seg_r: float, hang_brazier: bool = true) -> void:
	# Parabolic stone vault rib spanning two column crowns with optional suspended iron fire chandelier
	var span_v := right_pt - left_pt
	var yaw := atan2(-span_v.z, span_v.x)
	var steps := 5
	for i in range(steps):
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var p0 := left_pt.lerp(right_pt, t0) + Vector3(0.0, sin(t0 * PI) * rise_h, 0.0)
		var p1 := left_pt.lerp(right_pt, t1) + Vector3(0.0, sin(t1 * PI) * rise_h, 0.0)
		var seg_d := p1 - p0
		var cy := CylinderMesh.new()
		cy.top_radius = seg_r
		cy.bottom_radius = seg_r * 1.06
		cy.height = seg_d.length() + 0.35
		cy.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = cy
		mi.material_override = _vault_trim_mat
		mi.position = (p0 + p1) * 0.5
		mi.rotation = Vector3(0.0, yaw, atan2(seg_d.y, Vector2(seg_d.x, seg_d.z).length()) - PI * 0.5)
		parent.add_child(mi)
	if hang_brazier:
		var apex := (left_pt + right_pt) * 0.5 + Vector3(0.0, rise_h, 0.0)
		var chain_len := 2.45
		var ch := CylinderMesh.new()
		ch.top_radius = 0.05
		ch.bottom_radius = 0.05
		ch.height = chain_len
		ch.radial_segments = 6
		var ch_mi := MeshInstance3D.new()
		ch_mi.mesh = ch
		ch_mi.material_override = _vault_iron_mat
		ch_mi.position = apex - Vector3(0.0, chain_len * 0.5, 0.0)
		parent.add_child(ch_mi)
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.52
		bowl.bottom_radius = 0.24
		bowl.height = 0.32
		bowl.radial_segments = 8
		var b_mi := MeshInstance3D.new()
		b_mi.mesh = bowl
		b_mi.material_override = _vault_iron_mat
		b_mi.position = apex - Vector3(0.0, chain_len + 0.12, 0.0)
		parent.add_child(b_mi)
		_fire_seed_counter += 1
		CavePropFX.attach_torch_fire(parent, apex - Vector3(0.0, chain_len - 0.02, 0.0), _fire_seed_counter, 0.52)
		_add_flicker_light(parent, apex - Vector3(0.0, chain_len + 0.4, 0.0), Color(1.0, 0.64, 0.28), 1.9, 17.0)


func _strip_piece_colliders(node: Node) -> void:
	if node == null:
		return
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CollisionObject3D:
			cur.queue_free()
			continue
		for ch in cur.get_children():
			stack.append(ch)


func _place_ruin_wall(parent: Node3D, piece: String, pos: Vector3, yaw: float, scl: Vector3 = Vector3.ONE, tilt_xz: Vector2 = Vector2.ZERO, mat: Material = null, add_col: bool = true, col_size: Vector3 = Vector3(4.0, 3.6, 0.9)) -> Node3D:
	var node: Node3D = _place_nature_scene(parent, piece, pos, yaw, 1.0) if piece.begins_with("res://") else _place_piece(parent, piece, pos, yaw, scl)
	if node == null:
		return null
	if piece.begins_with("res://"):
		node.scale = scl
	_strip_piece_colliders(node)
	if tilt_xz != Vector2.ZERO:
		node.rotation.x = tilt_xz.x
		node.rotation.z = tilt_xz.y
	if mat != null:
		_apply_mat_recursive(node, mat)
	if add_col:
		var sb := _add_box_body(parent, pos + Vector3(0.0, col_size.y * 0.5, 0.0), col_size, LAYER_OBSTACLES, 0.0, yaw)
		if tilt_xz != Vector2.ZERO:
			sb.rotation = Vector3(tilt_xz.x, yaw, tilt_xz.y)
	return node


func _build_rat_warren(rat_region: Node = null) -> void:
	if rat_region != null and rat_region.has_method("clear_editor_preview"):
		rat_region.call("clear_editor_preview")
	var warren_root := Node3D.new()
	warren_root.name = "UndergroundRatWarren"
	warren_root.position = Vector3(WorldLandmarks.RAT_WARREN_OFFSET.x, 0.0, WorldLandmarks.RAT_WARREN_OFFSET.y)
	if rat_region != null and is_instance_valid(rat_region):
		rat_region.add_child(warren_root)
	else:
		add_child(warren_root)

	var mx := WorldLandmarks.RAT_WARREN_BAKED.x  # -240.0 (baked asset frame)
	var my := WorldLandmarks.RAT_FORECOURT_Y     # 22.0
	var vy := WorldLandmarks.RAT_VAULT_Y         # 14.5
	var sy := WorldLandmarks.RAT_SANCTUM_Y       # 10.0
	var basin_y := 13.05                         # Deep flooded basin 1.45m below Crossroads/West decks!
	var sample_rw_h := func(bx: float, bz: float) -> float:
		return _sample_h(bx + WorldLandmarks.RAT_WARREN_OFFSET.x, bz + WorldLandmarks.RAT_WARREN_OFFSET.y)

	# Baked SurfaceNets Multi-Loop Under-Empire cavern shell (Dog-Leg Entry + Hub + West Sump + East Burrow + Split NW/NE Loops + Deep Brood Hollow)
	CavePropFX.mount_baked_cavern(warren_root, ASSET_DIR + "rat_warren", _warren_shader_mat, true)

	# --------------------------------------------------------------------------
	# A. OVERGROWN ANCIENT STONE RUINS COMPLEX ("THE GNAWED RUINS")
	#    5-Zone Surface Ruins (bx in [-274..-206], bz in [258..334]) +
	#    No-Staircase Collapsed Stone Vault Breach at bz = 278.5
	#    Central Causeway Corridor (bx in [-244, -236]) kept clear for portals & slime!
	# --------------------------------------------------------------------------
	_add_box_body(warren_root, Vector3(mx, my - 0.52, 282.0), Vector3(14.0, 1.0, 12.0), LAYER_TERRAIN)

	# Zone A1: Full Interlocking Ancient Flagstone Barbican Avenue, Swamp Causeway & Wing Pavements (zero LAYER_OBSTACLES colliders)
	var pave_pts: Array[Vector2] = []
	for gz_c: float in [376.0, 372.0, 368.0, 364.0, 360.0, 356.0, 352.0, 348.0, 344.0, 340.0, 336.0, 332.0, 328.0, 324.0, 320.0, 316.0]:
		var row_offsets: Array[float] = [-3.85, 0.0, 3.85]
		if gz_c > 362.0:
			row_offsets = [-2.10, 2.10]
		for gx_c: float in row_offsets:
			pave_pts.append(Vector2(mx + gx_c, gz_c))
	for tz_p: float in [312.0, 308.0, 304.0, 300.0, 296.0, 292.0, 288.0, 284.0]:
		for gx_p: float in [-11.55, -7.70, -3.85, 0.0, 3.85, 7.70, 11.55]:
			var wx_p := mx + gx_p
			# Leave open water basin for the West Stone Aqueduct Cistern
			if wx_p > mx - 11.2 and wx_p < mx - 4.8 and tz_p >= 283.5 and tz_p <= 294.5:
				continue
			# Organic ruined ragged perimeter on far corners
			if absf(gx_p) > 10.5 and (tz_p < 289.0 or tz_p > 310.0):
				continue
			pave_pts.append(Vector2(wx_p, tz_p))
	for tz_w: float in [316.0, 312.0, 308.0, 304.0, 300.0, 296.0]:
		pave_pts.append(Vector2(mx - 34.65, tz_w))
		pave_pts.append(Vector2(mx - 30.80, tz_w))
		pave_pts.append(Vector2(mx - 26.95, tz_w))
		pave_pts.append(Vector2(mx - 23.10, tz_w))
		pave_pts.append(Vector2(mx - 19.25, tz_w))
		pave_pts.append(Vector2(mx - 15.40, tz_w))
		pave_pts.append(Vector2(mx + 15.40, tz_w))
		pave_pts.append(Vector2(mx + 19.25, tz_w))
		pave_pts.append(Vector2(mx + 23.10, tz_w))
		pave_pts.append(Vector2(mx + 26.95, tz_w))
		pave_pts.append(Vector2(mx + 30.80, tz_w))
	pave_pts.append(Vector2(mx, 280.4))

	for pi in range(pave_pts.size()):
		var pt := pave_pts[pi]
		var py := float(sample_rw_h.call(pt.x, pt.y)) + 0.04 + float(pi % 7) * 0.003
		var is_outer := absf(pt.x - mx) > 10.0 or pt.y > 325.0 or pt.y < 285.0
		var sel := (pi * 7 + int(absf(pt.x + pt.y))) % 10
		var tile_rel := "floor_tile_large.gltf.glb"
		if is_outer and sel < 4:
			tile_rel = "floor_dirt_large_rocky.gltf.glb"
		elif sel == 5 or sel == 8:
			tile_rel = "floor_tile_large_rocks.gltf.glb"
		var rot_y := float((pi * 3) % 4) * (PI * 0.5) + sin(float(pi) * 1.9) * 0.04
		var scl_v := Vector3(0.94, 1.0, 0.94)
		_place_ruin_wall(warren_root, tile_rel, Vector3(pt.x, py, pt.y), rot_y, scl_v, Vector2.ZERO, _vault_floor_mat, false)

	# Zone A2: Ruined South Gatehouse & Broken Outer Curtain Walls (bz = 314..328)
	for gp_s: float in [-1.0, 1.0]:
		var gx_p := mx + gp_s * 6.2
		var gy_p := float(sample_rw_h.call(gx_p, 320.5)) - 0.12
		_place_ruin_wall(warren_root, "pillar_decorated.gltf.glb", Vector3(gx_p, gy_p, 320.5), gp_s * 0.12, Vector3(1.75, 1.75, 1.75), Vector2(0.03 * gp_s, -0.04 * gp_s), _vault_trim_mat, true, Vector3(1.7, 5.5, 1.7))
		_vault_torch(warren_root, Vector3(mx + gp_s * 5.2, my + 3.05, 320.5), -gp_s * PI * 0.5, 2.1, 16.0)
	_place_ruin_wall(warren_root, "floor_foundation_allsides.gltf.glb", Vector3(mx - 9.4, float(sample_rw_h.call(mx - 9.4, 320.5)) - 0.25, 320.5), 0.08, Vector3(1.45, 0.80, 1.45), Vector2.ZERO, _vault_trim_mat, false)
	_place_ruin_wall(warren_root, "floor_foundation_allsides.gltf.glb", Vector3(mx + 9.6, float(sample_rw_h.call(mx + 9.6, 319.8)) - 0.25, 319.8), -0.10, Vector3(1.45, 0.80, 1.45), Vector2.ZERO, _vault_trim_mat, false)
	for gwall: Array in [
		["wall_archedwindow_open.gltf.glb", mx - 9.8, 320.5, 0.08, Vector3(1.40, 1.42, 1.40), Vector2(0.02, -0.04), Vector3(5.4, 5.2, 1.3)],
		["wall_broken.gltf.glb", mx - 14.6, 318.8, 0.42, Vector3(1.36, 1.25, 1.36), Vector2(0.04, -0.06), Vector3(5.4, 4.6, 1.3)],
		["wall_broken.gltf.glb", mx - 17.2, 324.2, PI * 0.5 + 0.14, Vector3(1.35, 1.10, 1.35), Vector2.ZERO, Vector3(5.4, 4.1, 1.3)],
		["wall_archedwindow_open.gltf.glb", mx + 9.8, 319.8, -0.10, Vector3(1.40, 1.44, 1.40), Vector2(-0.02, 0.04), Vector3(5.4, 5.2, 1.3)],
		["wall_cracked.gltf.glb", mx + 14.8, 317.8, -0.38, Vector3(1.36, 1.28, 1.36), Vector2(-0.04, 0.05), Vector3(5.4, 4.8, 1.3)],
		["wall_broken.gltf.glb", mx + 17.4, 323.5, PI * 0.5 - 0.16, Vector3(1.35, 1.08, 1.35), Vector2.ZERO, Vector3(5.4, 4.1, 1.3)],
	]:
		var gwx := float(gwall[1])
		var gwz := float(gwall[2])
		var gwy := float(sample_rw_h.call(gwx, gwz)) - 0.22
		_place_ruin_wall(warren_root, String(gwall[0]), Vector3(gwx, gwy, gwz), float(gwall[3]), gwall[4] as Vector3, gwall[5] as Vector2, _vault_wall_mat, true, gwall[6] as Vector3)

	# Toppled column drum beside the West gate pier + abandoned wagon & spilled crates on East side
	var tc_y := float(sample_rw_h.call(mx - 8.4, 324.2)) + 0.55
	_place_ruin_wall(warren_root, "column.gltf.glb", Vector3(mx - 8.4, tc_y, 324.2), 0.55, Vector3.ONE * 1.75, Vector2(0.12, 1.44), _vault_trim_mat, true, Vector3(3.2, 1.4, 1.4))
	var wag_y := float(sample_rw_h.call(mx + 10.4, 315.2)) - 0.06
	var wag := _place_ruin_wall(warren_root, "res://assets/village/Prop_Wagon.gltf", Vector3(mx + 10.4, wag_y, 315.2), -0.52, Vector3.ONE * 1.55, Vector2(0.05, -0.08), null, true, Vector3(3.7, 2.6, 2.7))
	_harmonize_prop_mats(wag, Color(0.44, 0.40, 0.36), 0.94, 0.04)

	# Zone A3: Collapsed West Cloister & Broken Stone Aqueduct Cistern (bx = -274..-246, bz = 280..314)
	for cw: Array in [
		["wall_corner.gltf.glb", mx - 18.8, 312.0, 0.12, Vector3(1.36, 1.28, 1.36), Vector2.ZERO],
		["wall_archedwindow_gated.gltf.glb", mx - 22.8, 307.2, PI * 0.5 + 0.06, Vector3(1.36, 1.36, 1.36), Vector2.ZERO],
		["wall_broken.gltf.glb", mx - 23.2, 301.5, PI * 0.5 - 0.08, Vector3(1.36, 1.20, 1.36), Vector2(0.03, -0.04)],
		["wall_cracked.gltf.glb", mx - 22.4, 295.5, PI * 0.5 + 0.22, Vector3(1.36, 1.26, 1.36), Vector2(0.05, 0.06)],
		["wall_broken.gltf.glb", mx - 18.2, 291.5, -0.18, Vector3(1.36, 1.12, 1.36), Vector2(-0.04, 0.03)],
	]:
		var cwx := float(cw[1])
		var cwz := float(cw[2])
		var cwy := float(sample_rw_h.call(cwx, cwz)) - 0.22
		_place_ruin_wall(warren_root, String(cw[0]), Vector3(cwx, cwy, cwz), float(cw[3]), cw[4] as Vector3, cw[5] as Vector2, _vault_wall_mat, true, Vector3(5.4, 4.9, 1.3))

	for cp: Array in [
		["pillar.gltf.glb", mx - 14.8, 308.5, 0.2, 1.75],
		["column.gltf.glb", mx - 15.2, 302.0, 0.8, 1.15],
		["pillar_decorated.gltf.glb", mx - 14.6, 295.8, -0.35, 1.90],
	]:
		var cpx := float(cp[1])
		var cpz := float(cp[2])
		var cpy := float(sample_rw_h.call(cpx, cpz)) - 0.10
		_place_ruin_wall(warren_root, String(cp[0]), Vector3(cpx, cpy, cpz), float(cp[3]), Vector3.ONE * float(cp[4]), Vector2.ZERO, _vault_trim_mat, true, Vector3(1.5, 4.4, 1.5))
	_vault_torch(warren_root, Vector3(mx - 13.9, my + 2.95, 295.8), PI * 0.5, 2.0, 15.0)

	# Ruined Stone Aqueduct Arch & Sunken Cistern Curb framing Western spring runoff waterfall
	_place_ruin_wall(warren_root, "wall_arched.gltf.glb", Vector3(mx - 7.9, my - 0.15, 281.6), 0.20, Vector3(1.08, 1.08, 1.08), Vector2.ZERO, _vault_wall_mat, true, Vector3(4.2, 3.8, 1.0))
	_vault_box_solid(warren_root, Vector3(mx - 10.2, my + 1.4, 282.4), Vector3(1.2, 3.1, 1.6), _vault_trim_mat, LAYER_OBSTACLES, Vector3(0.0, 12.0, 0.0))
	_vault_box_solid(warren_root, Vector3(mx - 5.5, my + 1.35, 282.0), Vector3(1.1, 2.9, 1.5), _vault_trim_mat, LAYER_OBSTACLES, Vector3(0.0, -8.0, 0.0))
	for rock_cleft: Array in [
		[Vector3(mx - 10.6, my - 0.08, 286.5), Vector3(1.5, 0.85, 2.4), 196],
		[Vector3(mx - 10.2, my - 0.08, 291.8), Vector3(1.6, 0.90, 2.5), 197],
		[Vector3(mx - 7.8, my - 0.12, 294.4), Vector3(2.8, 0.82, 1.4), 198],
		[Vector3(mx - 5.2, my - 0.08, 287.2), Vector3(1.3, 0.78, 2.2), 199],
	]:
		CavePropFX.spawn_fractured_boulder(warren_root, rock_cleft[0] as Vector3, rock_cleft[1] as Vector3, _vault_rock_mat, int(rock_cleft[2]), true)
	var ext_wf_mesh := PlaneMesh.new()
	ext_wf_mesh.size = Vector2(2.1, 4.2)
	ext_wf_mesh.subdivide_width = 6
	ext_wf_mesh.subdivide_depth = 10
	var ext_wf := MeshInstance3D.new()
	ext_wf.name = "RatExtRunoffWaterfall"
	ext_wf.mesh = ext_wf_mesh
	ext_wf.material_override = _vault_waterfall_mat
	ext_wf.position = Vector3(mx - 7.8, my + 1.55, 282.3)
	ext_wf.rotation = Vector3(PI * 0.5 - 0.18, 0.24, 0.0)
	ext_wf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warren_root.add_child(ext_wf)

	var ext_pool_pm := PlaneMesh.new()
	ext_pool_pm.size = Vector2(6.4, 10.6)
	var ext_pool := MeshInstance3D.new()
	ext_pool.mesh = ext_pool_pm
	ext_pool.material_override = _swamp_water_mat
	ext_pool.position = Vector3(mx - 7.9, WorldLandmarks.RAT_SWAMP_WATER_Y, 287.2)
	ext_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warren_root.add_child(ext_pool)
	CavePropFX.spawn_bark_fallen_log(warren_root, Vector3(mx - 7.8, my + 0.35, 288.2), 0.12, 0.0, 5.4, 0.32, 71, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(warren_root, Vector3(mx - 7.8, my + 0.35, 289.0), 0.05, 0.0, 5.4, 0.32, 72, _warren_bark_mat, true)

	# Zone A4: Ruined East Watchtower & Fallen Sanctuary Nave (bx = -232..-204, bz = 282..316)
	_place_ruin_wall(warren_root, "floor_foundation_allsides.gltf.glb", Vector3(mx + 15.5, float(sample_rw_h.call(mx + 15.5, 301.0)) - 0.35, 301.0), 0.18, Vector3(1.3, 0.65, 1.3), Vector2.ZERO, _vault_trim_mat, false)
	_place_ruin_wall(warren_root, "floor_foundation_allsides.gltf.glb", Vector3(mx + 20.5, float(sample_rw_h.call(mx + 20.5, 296.0)) - 0.35, 296.0), -0.25, Vector3(1.3, 0.65, 1.3), Vector2.ZERO, _vault_trim_mat, false)
	for ew: Array in [
		["wall_archedwindow_open.gltf.glb", mx + 17.0, 311.5, -0.15, Vector3(1.40, 1.48, 1.40), Vector2.ZERO],
		["wall_corner.gltf.glb", mx + 22.0, 308.0, -0.65, Vector3(1.40, 1.45, 1.40), Vector2.ZERO],
		["wall_archedwindow_gated.gltf.glb", mx + 23.8, 302.5, -PI * 0.5 + 0.12, Vector3(1.40, 1.50, 1.40), Vector2(-0.03, 0.04)],
		["wall_broken.gltf.glb", mx + 23.4, 296.5, -PI * 0.5 - 0.14, Vector3(1.36, 1.24, 1.36), Vector2(-0.06, -0.05)],
		["wall_cracked.gltf.glb", mx + 19.2, 291.2, -2.45, Vector3(1.36, 1.36, 1.36), Vector2.ZERO],
		["wall_broken.gltf.glb", mx + 14.2, 289.0, 0.22, Vector3(1.36, 1.12, 1.36), Vector2(0.04, -0.05)],
	]:
		var ewx := float(ew[1])
		var ewz := float(ew[2])
		var ewy := float(sample_rw_h.call(ewx, ewz)) - 0.22
		_place_ruin_wall(warren_root, String(ew[0]), Vector3(ewx, ewy, ewz), float(ew[3]), ew[4] as Vector3, ew[5] as Vector2, _vault_wall_mat, true, Vector3(5.4, 5.1, 1.3))

	for ep_p: Array in [
		["pillar_decorated.gltf.glb", mx + 13.8, 305.5, -0.25, 1.90],
		["column.gltf.glb", mx + 19.6, 303.2, 0.45, 2.15],
		["column.gltf.glb", mx + 14.5, 295.0, 1.10, 1.05],
		["pillar.gltf.glb", mx + 20.0, 294.5, -0.60, 1.65],
	]:
		var epx := float(ep_p[1])
		var epz := float(ep_p[2])
		var epy := float(sample_rw_h.call(epx, epz)) - 0.10
		_place_ruin_wall(warren_root, String(ep_p[0]), Vector3(epx, epy, epz), float(ep_p[3]), Vector3.ONE * float(ep_p[4]), Vector2.ZERO, _vault_trim_mat, true, Vector3(1.5, 4.6, 1.5))
	_vault_torch(warren_root, Vector3(mx + 13.0, my + 3.00, 305.5), -PI * 0.5, 2.1, 16.5)
	CavePropFX.spawn_bark_fallen_log(warren_root, Vector3(mx + 16.5, my + 1.55, 304.2), 0.35, 0.58, 5.8, 0.26, 211, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(warren_root, Vector3(mx + 17.8, my + 1.65, 297.2), -0.42, 0.65, 6.2, 0.24, 212, _warren_bark_mat, true)

	var wt_banner := _place_piece(warren_root, "banner_patternA_red.gltf.glb", Vector3(mx + 16.5, my + 1.65, 310.7), PI - 0.15, Vector3.ONE * 1.65)
	_harmonize_prop_mats(wt_banner, Color(0.45, 0.40, 0.36), 0.94, 0.04)

	# Zone A5: Collapsed Stone Vault Breach Mouth (bx = -248..-232, bz = 278.5 — NO STAIRCASE!) & Upper Hillside Ruined Citadel Crest
	for bp_s: float in [-1.0, 1.0]:
		_vault_box_solid(warren_root, Vector3(mx + bp_s * 6.05, my + 2.35, 279.6), Vector3(2.2, 5.4, 2.8), _vault_wall_mat, LAYER_OBSTACLES, Vector3(0.0, bp_s * 6.0, 0.0))
		_place_ruin_wall(warren_root, "pillar_decorated.gltf.glb", Vector3(mx + bp_s * 5.70, my - 0.10, 280.4), bp_s * 0.18, Vector3.ONE * 1.95, Vector2(0.07, bp_s * 0.14), _vault_trim_mat, true, Vector3(1.7, 5.5, 1.7))
		_place_ruin_wall(warren_root, "wall_broken.gltf.glb", Vector3(mx + bp_s * 9.4, my - 0.15, 280.5), bp_s * -0.26, Vector3(1.40, 1.32, 1.40), Vector2(0.03, bp_s * -0.05), _vault_wall_mat, true, Vector3(5.4, 4.9, 1.3))
		_vault_torch(warren_root, Vector3(mx + bp_s * 4.65, my + 3.10, 280.6), -bp_s * PI * 0.5, 2.3, 17.5)
	_vault_box_mesh(warren_root, Vector3(mx, my + 6.05, 278.2), Vector3(12.6, 1.65, 2.8), _vault_trim_mat, Vector3(4.0, 2.0, -3.5))
	CavePropFX.spawn_bark_fallen_log(warren_root, Vector3(mx, my + 5.45, 279.2), 0.04, 0.0, 11.2, 0.40, 181, _warren_bark_mat, false)

	# Upper Hillside Ruined Citadel Crest overlooking the Courtyard (bz = 264..272)
	for crest_w: Array in [
		["wall_broken.gltf.glb", mx - 12.6, 271.5, 0.15, Vector3(1.40, 1.38, 1.40)],
		["wall_archedwindow_open.gltf.glb", mx - 5.8, 267.5, 0.08, Vector3(1.42, 1.46, 1.42)],
		["wall_cracked.gltf.glb", mx + 4.8, 267.0, -0.12, Vector3(1.42, 1.42, 1.42)],
		["wall_broken.gltf.glb", mx + 13.0, 270.8, -0.22, Vector3(1.40, 1.38, 1.40)],
		["wall_corner.gltf.glb", mx - 18.2, 265.0, 0.55, Vector3(1.40, 1.34, 1.40)],
		["wall_corner.gltf.glb", mx + 18.8, 264.5, -0.60, Vector3(1.40, 1.34, 1.40)],
	]:
		var crx := float(crest_w[1])
		var crz := float(crest_w[2])
		var cry := float(sample_rw_h.call(crx, crz)) - 0.45
		_place_ruin_wall(warren_root, String(crest_w[0]), Vector3(crx, cry, crz), float(crest_w[3]), crest_w[4] as Vector3, Vector2(0.04, 0.03), _vault_wall_mat, true, Vector3(5.4, 5.1, 1.3))
	for crest_p: Array in [
		[mx - 8.8, 265.0, 2.15, Vector2(0.05, -0.07)],
		[mx + 9.4, 264.5, 2.25, Vector2(-0.04, 0.08)],
	]:
		var cpx := float(crest_p[0])
		var cpz := float(crest_p[1])
		var cpy := float(sample_rw_h.call(cpx, cpz)) - 0.45
		_place_ruin_wall(warren_root, "pillar_decorated.gltf.glb", Vector3(cpx, cpy, cpz), cpx * 0.2, Vector3.ONE * float(crest_p[2]), crest_p[3] as Vector2, _vault_trim_mat, true, Vector3(1.8, 5.8, 1.8))

	# Asymmetrical Karst Cliff Buttress welding the Collapsed Breach Mouth & Citadel Crest into the hillside
	var ext_cliffs: Array[Array] = [
		[Vector3(mx - 10.6, my + 3.4, 278.4), Vector3(4.2, 4.1, 3.8), 102],
		[Vector3(mx - 15.6, my + 2.6, 279.8), Vector3(4.5, 3.4, 3.8), 103],
		[Vector3(mx + 11.0, my + 3.8, 278.2), Vector3(4.3, 4.6, 3.8), 105],
		[Vector3(mx + 15.8, my + 2.8, 281.0), Vector3(4.2, 3.6, 3.8), 106],
		[Vector3(mx, my + 7.2, 276.4), Vector3(5.2, 2.8, 3.8), 107],
		[Vector3(mx - 5.2, my + 6.4, 276.6), Vector3(4.2, 3.0, 3.6), 108],
		[Vector3(mx + 5.4, my + 6.6, 276.6), Vector3(4.3, 3.1, 3.6), 109],
		[Vector3(mx - 23.0, my + 2.2, 284.0), Vector3(3.8, 2.8, 3.6), 110],
		[Vector3(mx + 23.4, my + 2.2, 285.5), Vector3(4.0, 2.8, 3.8), 111],
	]
	for cl in ext_cliffs:
		CavePropFX.spawn_fractured_boulder(warren_root, cl[0] as Vector3, cl[1] as Vector3, _vault_rock_mat, int(cl[2]), true)

	for rub_ruin: Array in [
		[mx - 11.2, 291.2, "rubble_large.gltf.glb", _vault_rock_mat, -0.8, Vector3(1.35, 1.0, 1.35)],
		[mx + 6.4, 284.4, "rubble_large.gltf.glb", _vault_rock_mat, -0.5, Vector3(1.35, 1.05, 1.35)],
		[mx - 7.0, 319.6, "rubble_half.gltf.glb", _vault_trim_mat, 0.4, Vector3(1.35, 1.1, 1.35)],
		[mx + 11.2, 317.4, "rubble_half.gltf.glb", _vault_trim_mat, -0.6, Vector3(1.35, 1.1, 1.35)],
		[mx - 18.4, 300.5, "rubble_large.gltf.glb", _vault_trim_mat, 1.1, Vector3(1.25, 0.9, 1.25)],
		[mx + 18.2, 298.4, "rubble_large.gltf.glb", _vault_trim_mat, -0.9, Vector3(1.25, 0.9, 1.25)],
		[mx + 10.6, 267.8, "rubble_large.gltf.glb", _vault_rock_mat, 0.35, Vector3(1.5, 1.1, 1.5)],
	]:
		var rx_p := float(rub_ruin[0])
		var rz_p := float(rub_ruin[1])
		var rp_node := _place_piece(warren_root, String(rub_ruin[2]), Vector3(rx_p, float(sample_rw_h.call(rx_p, rz_p)) - 0.25, rz_p), float(rub_ruin[4]), rub_ruin[5] as Vector3)
		if rp_node != null:
			_strip_piece_colliders(rp_node)
			_apply_mat_recursive(rp_node, rub_ruin[3] as Material)

	# Smuggler & Cloister Rat Hoards, Brick Debris, Gnawed Bones, Ivy Vines & DeadTree Snags
	for eb_spec: Array in [
		[Vector3(mx + 7.2, float(sample_rw_h.call(mx + 7.2, 314.6)), 314.6), "barrel_small_stack.gltf.glb", -0.45, 1.58],
		[Vector3(mx - 19.2, float(sample_rw_h.call(mx - 19.2, 303.8)), 303.8), "crates_stacked.gltf.glb", 0.35, 1.60],
		[Vector3(mx - 17.6, float(sample_rw_h.call(mx - 17.6, 306.4)), 306.4), "keg_decorated.gltf.glb", -0.65, 1.60],
		[Vector3(mx + 16.2, float(sample_rw_h.call(mx + 16.2, 307.2)), 307.2), "barrel_large_decorated.gltf.glb", -0.75, 1.62],
	]:
		var ep := eb_spec[0] as Vector3
		var en := _place_piece(warren_root, String(eb_spec[1]), ep, float(eb_spec[2]), Vector3.ONE * float(eb_spec[3]))
		_harmonize_prop_mats(en, Color(0.45, 0.40, 0.35), 0.94, 0.04)
		_add_box_body(warren_root, ep + Vector3(0.0, 1.25, 0.0), Vector3(2.4, 2.5, 2.4), LAYER_OBSTACLES)

	for brk: Array in [
		["Prop_Brick1.gltf", mx - 6.8, 317.8, 0.4],
		["Prop_Brick2.gltf", mx + 7.4, 317.2, -0.7],
		["Prop_Brick1.gltf", mx - 16.5, 298.8, 1.2],
		["Prop_Brick2.gltf", mx + 17.2, 301.4, -0.5],
	]:
		var bx_b := float(brk[1])
		var bz_b := float(brk[2])
		var b_node := _place_nature_scene(warren_root, "res://assets/village/" + String(brk[0]), Vector3(bx_b, float(sample_rw_h.call(bx_b, bz_b)) - 0.04, bz_b), float(brk[3]), 1.15)
		if b_node != null:
			_apply_mat_recursive(b_node, _vault_trim_mat)

	for vine_ruin: Array in [
		["Prop_Vine2.gltf", Vector3(mx - 9.0, my + 2.8, 319.9), 0.08],
		["Prop_Vine1.gltf", Vector3(mx + 9.0, my + 2.8, 319.2), -0.10],
		["Prop_Vine2.gltf", Vector3(mx - 21.4, my + 2.7, 306.8), PI * 0.5],
		["Prop_Vine1.gltf", Vector3(mx + 22.6, my + 2.9, 302.4), -PI * 0.5],
		["Prop_Vine2.gltf", Vector3(mx - 5.2, float(sample_rw_h.call(mx - 5.2, 268.0)) + 2.6, 268.0), 0.08],
	]:
		_place_nature_scene(warren_root, "res://assets/village/" + String(vine_ruin[0]), vine_ruin[1] as Vector3, float(vine_ruin[2]), 1.25)

	for eb_i in [Vector2(-3.8, 288.4), Vector2(3.8, 291.2), Vector2(-17.8, 301.2), Vector2(15.2, 301.8), Vector2(-4.4, 316.0)]:
		_spawn_articulated_bone(warren_root, Vector3(mx + eb_i.x, float(sample_rw_h.call(mx + eb_i.x, eb_i.y)) + 0.08, eb_i.y), eb_i.x * 0.7, 0.88)

	for sn_xz: Vector2 in [Vector2(mx - 24.5, 312.0), Vector2(mx + 25.2, 305.0), Vector2(mx - 21.0, 286.0)]:
		var sny := float(sample_rw_h.call(sn_xz.x, sn_xz.y))
		_place_nature_scene(warren_root, "res://assets/nature_extra/DeadTree_1.gltf", Vector3(sn_xz.x, sny - 0.14, sn_xz.y), sn_xz.x * 0.4, 2.05)

	CavePropFX.spawn_vine_batch(warren_root, [
		{"pos": Vector3(mx - 2.2, my + 4.9, 279.8), "len": 2.4, "width": 1.0, "rot": 0.4},
		{"pos": Vector3(mx + 2.2, my + 4.9, 279.8), "len": 2.2, "width": 1.0, "rot": 1.8},
		{"pos": Vector3(mx, my + 5.1, 280.0), "len": 1.5, "width": 0.9, "rot": 2.2},
		{"pos": Vector3(mx - 7.8, my + 3.2, 282.0), "len": 1.9, "width": 0.95, "rot": 2.6},
	])
	for sh_pos: Vector3 in [
		Vector3(mx - 10.6, float(sample_rw_h.call(mx - 10.6, 323.5)) + 0.04, 323.5),
		Vector3(mx + 11.2, float(sample_rw_h.call(mx + 11.2, 322.8)) + 0.04, 322.8),
		Vector3(mx - 20.5, float(sample_rw_h.call(mx - 20.5, 315.5)) + 0.04, 315.5),
		Vector3(mx + 20.8, float(sample_rw_h.call(mx + 20.8, 313.0)) + 0.04, 313.0),
	]:
		_place_nature_scene(warren_root, "res://assets/nature/Plant_1.gltf", sh_pos, sh_pos.x * 0.4, 1.30)

	var rim_ferns: Array[Transform3D] = []
	for fr: Array in [
		[Vector3(mx - 5.2, float(sample_rw_h.call(mx - 5.2, 286.6)), 286.6), 1.35],
		[Vector3(mx + 5.8, float(sample_rw_h.call(mx + 5.8, 286.6)), 286.6), 1.35],
		[Vector3(mx - 15.0, float(sample_rw_h.call(mx - 15.0, 311.0)), 311.0), 1.40],
		[Vector3(mx + 14.8, float(sample_rw_h.call(mx + 14.8, 310.4)), 310.4), 1.40],
		[Vector3(mx - 2.6, my + 5.2, 277.6), 1.45],
		[Vector3(mx + 2.6, my + 5.2, 277.6), 1.45],
		[Vector3(mx - 11.6, float(sample_rw_h.call(mx - 11.6, 324.2)), 324.2), 1.40],
		[Vector3(mx + 11.8, float(sample_rw_h.call(mx + 11.8, 323.8)), 323.8), 1.40],
		[Vector3(mx - 24.5, float(sample_rw_h.call(mx - 24.5, 298.0)), 298.0), 1.55],
		[Vector3(mx + 25.0, float(sample_rw_h.call(mx + 25.0, 299.5)), 299.5), 1.55],
		[Vector3(mx - 19.5, float(sample_rw_h.call(mx - 19.5, 326.0)), 326.0), 1.50],
		[Vector3(mx + 19.5, float(sample_rw_h.call(mx + 19.5, 325.5)), 325.5), 1.50],
	]:
		rim_ferns.append(Transform3D(Basis.from_euler(Vector3(0.0, float(rim_ferns.size()) * 1.4, 0.0)).scaled(Vector3.ONE * float(fr[1])), fr[0]))
	CavePropFX.spawn_gltf_batch(warren_root, "RatRimFerns", "res://assets/nature/Fern_1.gltf", rim_ferns)

	# Outer Moorland Perimeter Transition: dark mossy crags, gnarled deadwoods & outer expanded ruins districts
	for out_rock: Array in [
		[Vector2(mx - 45.0, 328.0), Vector3(3.6, 2.3, 3.2), 1101],
		[Vector2(mx - 46.5, 296.0), Vector3(3.8, 2.6, 3.2), 1102],
		[Vector2(mx + 45.0, 322.0), Vector3(3.6, 2.4, 3.2), 1103],
		[Vector2(mx + 46.5, 292.0), Vector3(3.7, 2.5, 3.3), 1104],
		[Vector2(mx - 36.0, 266.0), Vector3(3.8, 2.8, 3.4), 1105],
		[Vector2(mx + 37.5, 265.0), Vector3(3.7, 2.7, 3.2), 1106],
		[Vector2(mx - 20.0, 254.0), Vector3(3.2, 2.1, 2.8), 1107],
		[Vector2(mx + 20.5, 253.0), Vector3(3.3, 2.2, 2.9), 1108],
		[Vector2(mx - 26.0, 360.0), Vector3(3.0, 1.7, 2.8), 1109],
		[Vector2(mx + 27.0, 358.0), Vector3(3.1, 1.8, 2.9), 1110],
	]:
		var or_xz: Vector2 = out_rock[0]
		var or_rad: Vector3 = out_rock[1]
		var or_y := float(sample_rw_h.call(or_xz.x, or_xz.y)) + or_rad.y * 0.25
		CavePropFX.spawn_fractured_boulder(warren_root, Vector3(or_xz.x, or_y, or_xz.y), or_rad, _vault_rock_mat, int(out_rock[2]), true)

	for perim_tree: Vector2 in [
		Vector2(mx - 47.0, 344.0), Vector2(mx + 48.0, 340.0),
		Vector2(mx - 49.0, 310.0), Vector2(mx + 49.0, 306.0),
		Vector2(mx - 40.0, 264.0), Vector2(mx + 41.0, 263.0),
		Vector2(mx - 34.0, 366.0), Vector2(mx + 35.0, 364.0),
	]:
		var pty := float(sample_rw_h.call(perim_tree.x, perim_tree.y))
		_place_nature_scene(warren_root, "res://assets/nature_extra/DeadTree_1.gltf", Vector3(perim_tree.x, pty - 0.16, perim_tree.y), perim_tree.x * 0.35, 2.25)

	# --------------------------------------------------------------------------
	# Zone A6: Outer Southern Barbican Gatehouse, Processional Avenue & Sweep Walls (bz = 334..364)
	# --------------------------------------------------------------------------
	for bg_s: float in [-1.0, 1.0]:
		var bgx := mx + bg_s * 6.4
		var bgy := float(sample_rw_h.call(bgx, 354.5)) - 0.15
		_place_ruin_wall(warren_root, "floor_foundation_allsides.gltf.glb", Vector3(mx + bg_s * 8.6, bgy - 0.15, 354.5), bg_s * 0.12, Vector3(1.50, 0.85, 1.50), Vector2.ZERO, _vault_trim_mat, false)
		_place_ruin_wall(warren_root, "pillar_decorated.gltf.glb", Vector3(bgx, bgy, 354.5), bg_s * 0.18, Vector3.ONE * 1.95, Vector2(0.03 * bg_s, -0.05 * bg_s), _vault_trim_mat, true, Vector3(1.8, 5.8, 1.8))
		_vault_torch(warren_root, Vector3(mx + bg_s * 5.4, bgy + 3.25, 354.5), -bg_s * PI * 0.5, 2.2, 16.5)
	for barb_w: Array in [
		["wall_archedwindow_open.gltf.glb", mx - 10.2, 354.0, 0.08, Vector3(1.42, 1.46, 1.42), Vector2(0.02, -0.04)],
		["wall_broken.gltf.glb", mx - 15.2, 351.2, 0.38, Vector3(1.38, 1.28, 1.38), Vector2(0.04, -0.06)],
		["wall_corner.gltf.glb", mx - 20.4, 347.8, 0.65, Vector3(1.38, 1.24, 1.38), Vector2.ZERO],
		["wall_broken.gltf.glb", mx - 26.0, 342.0, PI * 0.42, Vector3(1.35, 1.15, 1.35), Vector2(0.03, 0.04)],
		["wall_archedwindow_open.gltf.glb", mx + 10.2, 353.6, -0.10, Vector3(1.42, 1.46, 1.42), Vector2(-0.02, 0.04)],
		["wall_cracked.gltf.glb", mx + 15.4, 350.6, -0.36, Vector3(1.38, 1.32, 1.38), Vector2(-0.03, 0.05)],
		["wall_corner.gltf.glb", mx + 20.8, 346.8, -0.72, Vector3(1.38, 1.26, 1.38), Vector2.ZERO],
		["wall_archedwindow_gated.gltf.glb", mx + 25.8, 340.5, -PI * 0.38, Vector3(1.35, 1.22, 1.35), Vector2(-0.04, -0.03)],
	]:
		var bwx := float(barb_w[1])
		var bwz := float(barb_w[2])
		var bwy := float(sample_rw_h.call(bwx, bwz)) - 0.28
		_place_ruin_wall(warren_root, String(barb_w[0]), Vector3(bwx, bwy, bwz), float(barb_w[3]), barb_w[4] as Vector3, barb_w[5] as Vector2, _vault_wall_mat, true, Vector3(5.4, 5.0, 1.3))

	# Toppled column & abandoned smuggler wagon wreck between Barbican & Inner Gate
	var bcol_y := float(sample_rw_h.call(mx + 8.6, 358.2)) + 0.52
	_place_ruin_wall(warren_root, "column.gltf.glb", Vector3(mx + 8.6, bcol_y, 358.2), -0.62, Vector3.ONE * 1.75, Vector2(-0.10, 1.44), _vault_trim_mat, true, Vector3(3.2, 1.4, 1.4))
	var bwag_y := float(sample_rw_h.call(mx - 9.4, 341.0)) - 0.06
	var bwag := _place_ruin_wall(warren_root, "res://assets/village/Prop_Wagon.gltf", Vector3(mx - 9.4, bwag_y, 341.0), 0.72, Vector3.ONE * 1.55, Vector2(-0.06, 0.08), null, true, Vector3(3.7, 2.6, 2.7))
	_harmonize_prop_mats(bwag, Color(0.44, 0.40, 0.36), 0.94, 0.04)
	var bcr := _place_piece(warren_root, "crates_stacked.gltf.glb", Vector3(mx - 12.6, bwag_y, 338.8), 0.40, Vector3.ONE * 1.60)
	_harmonize_prop_mats(bcr, Color(0.44, 0.40, 0.35), 0.94, 0.04)
	_add_box_body(warren_root, Vector3(mx - 12.6, bwag_y + 1.25, 338.8), Vector3(2.4, 2.5, 2.4), LAYER_OBSTACLES)

	# --------------------------------------------------------------------------
	# Zone A3b: Far West Ruined Granary Hall & Extended Aqueduct Arcade (bx = mx - 44..-24)
	# --------------------------------------------------------------------------
	for aq_x: float in [mx - 12.2, mx - 16.6, mx - 21.0, mx - 25.4]:
		var aqy := float(sample_rw_h.call(aq_x, 281.6)) - 0.20
		_place_ruin_wall(warren_root, "wall_arched.gltf.glb", Vector3(aq_x, aqy, 281.6), 0.06, Vector3(1.38, 1.42, 1.38), Vector2.ZERO, _vault_wall_mat, true, Vector3(5.6, 5.1, 1.3))
	for gran_w: Array in [
		["wall_corner.gltf.glb", mx - 37.5, 320.5, 0.14, Vector3(1.38, 1.28, 1.38), Vector2.ZERO],
		["wall_archedwindow_open.gltf.glb", mx - 38.8, 314.5, PI * 0.5 - 0.06, Vector3(1.38, 1.36, 1.38), Vector2(0.03, -0.04)],
		["wall_broken.gltf.glb", mx - 39.2, 308.0, PI * 0.5 + 0.12, Vector3(1.38, 1.22, 1.38), Vector2(0.04, 0.05)],
		["wall_cracked.gltf.glb", mx - 38.4, 301.0, PI * 0.5 - 0.15, Vector3(1.38, 1.28, 1.38), Vector2(-0.04, 0.04)],
		["wall_broken.gltf.glb", mx - 33.5, 294.5, -0.18, Vector3(1.38, 1.15, 1.38), Vector2(0.03, -0.05)],
		["wall_broken.gltf.glb", mx - 28.0, 323.0, 0.24, Vector3(1.35, 1.12, 1.35), Vector2.ZERO],
	]:
		var grx := float(gran_w[1])
		var grz := float(gran_w[2])
		var gry := float(sample_rw_h.call(grx, grz)) - 0.28
		_place_ruin_wall(warren_root, String(gran_w[0]), Vector3(grx, gry, grz), float(gran_w[3]), gran_w[4] as Vector3, gran_w[5] as Vector2, _vault_wall_mat, true, Vector3(5.4, 4.9, 1.3))
	for gp_w: Array in [
		["pillar.gltf.glb", mx - 32.5, 314.0, 0.3, 1.85],
		["column.gltf.glb", mx - 32.8, 306.5, -0.4, 1.18],
		["pillar_decorated.gltf.glb", mx - 32.2, 299.5, 0.6, 1.95],
		["column.gltf.glb", mx - 27.2, 310.0, 1.2, 1.65],
	]:
		var pxw := float(gp_w[1])
		var pzw := float(gp_w[2])
		var pyw := float(sample_rw_h.call(pxw, pzw)) - 0.15
		_place_ruin_wall(warren_root, String(gp_w[0]), Vector3(pxw, pyw, pzw), float(gp_w[3]), Vector3.ONE * float(gp_w[4]), Vector2.ZERO, _vault_trim_mat, true, Vector3(1.6, 4.6, 1.6))
	_vault_torch(warren_root, Vector3(mx - 31.6, float(sample_rw_h.call(mx - 32.2, 299.5)) + 3.05, 299.5), PI * 0.5, 2.0, 15.0)
	_place_ruin_wall(warren_root, "column.gltf.glb", Vector3(mx - 29.5, float(sample_rw_h.call(mx - 29.5, 303.5)) + 0.54, 303.5), 0.85, Vector3.ONE * 1.75, Vector2(0.08, 1.45), _vault_trim_mat, true, Vector3(3.2, 1.4, 1.4))
	_place_nature_scene(warren_root, "res://assets/nature_extra/DeadTree_1.gltf", Vector3(mx - 35.8, float(sample_rw_h.call(mx - 35.8, 310.5)) - 0.16, 310.5), 0.75, 2.15)

	# --------------------------------------------------------------------------
	# Zone A4b: Far East Ruined Abbey Nave & Two-Tier Bell-Tower Stump (bx = mx + 24..44)
	# --------------------------------------------------------------------------
	var btx := mx + 30.5
	var btz := 304.0
	var bty := float(sample_rw_h.call(btx, btz)) - 0.25
	_place_ruin_wall(warren_root, "floor_foundation_allsides.gltf.glb", Vector3(btx, bty - 0.10, btz), 0.12, Vector3(2.40, 1.10, 2.40), Vector2.ZERO, _vault_trim_mat, false)
	for bt_l: Array in [
		["wall_corner.gltf.glb", btx + 3.1, btz + 3.1, -0.55, Vector3(1.42, 1.50, 1.42)],
		["wall_archedwindow_gated.gltf.glb", btx + 4.1, btz - 2.2, -PI * 0.5 + 0.10, Vector3(1.42, 1.50, 1.42)],
		["wall_broken.gltf.glb", btx - 2.2, btz - 4.1, -2.90, Vector3(1.38, 1.44, 1.38)],
	]:
		_place_ruin_wall(warren_root, String(bt_l[0]), Vector3(float(bt_l[1]), bty, float(bt_l[2])), float(bt_l[3]), bt_l[4] as Vector3, Vector2.ZERO, _vault_wall_mat, true, Vector3(5.4, 5.2, 1.3))
	# Upper Bell-Tower Second-Story Remnant rising ~8.8m above courtyard
	_place_ruin_wall(warren_root, "wall_archedwindow_open.gltf.glb", Vector3(btx + 3.9, bty + 4.65, btz - 2.0), -PI * 0.5 + 0.10, Vector3(1.38, 1.22, 1.38), Vector2(-0.04, 0.03), _vault_wall_mat, false)
	_place_ruin_wall(warren_root, "wall_broken.gltf.glb", Vector3(btx + 2.9, bty + 4.65, btz + 2.9), -0.55, Vector3(1.35, 1.08, 1.35), Vector2.ZERO, _vault_wall_mat, false)
	_place_ruin_wall(warren_root, "pillar_decorated.gltf.glb", Vector3(btx - 2.8, bty, btz + 2.8), -0.45, Vector3.ONE * 2.15, Vector2.ZERO, _vault_trim_mat, true, Vector3(1.8, 6.2, 1.8))
	_vault_torch(warren_root, Vector3(btx - 3.3, bty + 3.35, btz + 2.8), -PI * 0.5, 2.2, 16.5)
	var bt_ban := _place_piece(warren_root, "banner_shield_blue.gltf.glb", Vector3(btx + 3.1, bty + 4.2, btz - 2.0), -PI * 0.5 + 0.10, Vector3.ONE * 1.75)
	_harmonize_prop_mats(bt_ban, Color(0.45, 0.42, 0.38), 0.94, 0.04)
	_place_nature_scene(warren_root, "res://assets/village/Prop_Vine2.gltf", Vector3(btx + 3.2, bty + 7.2, btz - 2.0), -PI * 0.5, 1.70)
	for ab_w: Array in [
		["wall_arched.gltf.glb", mx + 36.2, 314.0, -0.35, Vector3(1.38, 1.38, 1.38)],
		["wall_broken.gltf.glb", mx + 37.8, 294.0, -PI * 0.5 - 0.18, Vector3(1.38, 1.24, 1.38)],
		["wall_cracked.gltf.glb", mx + 31.8, 287.5, 0.25, Vector3(1.38, 1.28, 1.38)],
		["wall_broken.gltf.glb", mx + 29.0, 321.5, -0.28, Vector3(1.35, 1.15, 1.35)],
	]:
		var awx := float(ab_w[1])
		var awz := float(ab_w[2])
		var awy := float(sample_rw_h.call(awx, awz)) - 0.28
		_place_ruin_wall(warren_root, String(ab_w[0]), Vector3(awx, awy, awz), float(ab_w[3]), ab_w[4] as Vector3, Vector2(0.03, -0.04), _vault_wall_mat, true, Vector3(5.4, 4.9, 1.3))
	_place_nature_scene(warren_root, "res://assets/nature_extra/DeadTree_1.gltf", Vector3(mx + 35.5, float(sample_rw_h.call(mx + 35.5, 309.0)) - 0.16, 309.0), -0.95, 2.20)

	# --------------------------------------------------------------------------
	# Zone A5b: Broadened Upper Hillside Ruined Citadel Ramparts (bx = mx - 40..mx + 40, bz = 256..272)
	# --------------------------------------------------------------------------
	for hill_r: Array in [
		["wall_corner.gltf.glb", mx - 26.0, 266.0, 0.35, Vector3(1.42, 1.48, 1.42)],
		["wall_broken.gltf.glb", mx - 33.5, 270.0, 0.18, Vector3(1.38, 1.26, 1.38)],
		["wall_archedwindow_open.gltf.glb", mx + 27.0, 265.0, -0.32, Vector3(1.42, 1.48, 1.42)],
		["wall_broken.gltf.glb", mx + 34.5, 269.0, -0.15, Vector3(1.38, 1.26, 1.38)],
	]:
		var hrx := float(hill_r[1])
		var hrz := float(hill_r[2])
		var hry := float(sample_rw_h.call(hrx, hrz)) - 0.50
		_place_ruin_wall(warren_root, String(hill_r[0]), Vector3(hrx, hry, hrz), float(hill_r[3]), hill_r[4] as Vector3, Vector2(0.04, 0.03), _vault_wall_mat, true, Vector3(5.4, 5.1, 1.3))
	for hill_p: Array in [[mx - 24.5, 264.5, 2.20], [mx + 25.5, 263.5, 2.25]]:
		var hpx := float(hill_p[0])
		var hpz := float(hill_p[1])
		_place_ruin_wall(warren_root, "pillar_decorated.gltf.glb", Vector3(hpx, float(sample_rw_h.call(hpx, hpz)) - 0.50, hpz), hpx * 0.15, Vector3.ONE * float(hill_p[2]), Vector2(0.04, -0.05), _vault_trim_mat, true, Vector3(1.8, 6.0, 1.8))

	# --------------------------------------------------------------------------
	# Zone A7: Sunken Swamp Environment, Flooded Lagoon, Docks, Rowboats & Bog Flora
	# --------------------------------------------------------------------------
	_build_rat_swamp_surroundings(warren_root, mx, my, WorldLandmarks.RAT_SWAMP_WATER_Y, sample_rw_h)

	# --------------------------------------------------------------------------
	# B. NON-LINEAR WINDING MULTI-LOOP UNDER-EMPIRE BURROW (Zero straight axial sightline!)
	#    Dog-Leg Entry (-240->-234, 278..253) | Asymmetrical Confluence Hub (-239.5, 244)
	#    West Sump (-276, 243) + NW Bolt-Hole | East Root-Larder (-203, 242) + NE Loop
	#    Split NW/NE Winding Burrows around Central Karst & Root Divide -> Deep Brood Hollow (-239, 194, y=10)
	# --------------------------------------------------------------------------
	_warren_interior = Node3D.new()
	_warren_interior.name = "WarrenInterior"
	warren_root.add_child(_warren_interior)

	for pr_spec: Array in [
		["RatVaultProbe", Vector3(mx, vy + 5.0, 243.5), Vector3(106.0, 18.0, 52.0)],
		["RatSanctumProbe", Vector3(mx, sy + 7.0, 196.0), Vector3(58.0, 18.0, 44.0)],
	]:
		var probe := ReflectionProbe.new()
		probe.name = String(pr_spec[0])
		probe.interior = true
		probe.box_projection = false
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		probe.ambient_color = Color(0.28, 0.31, 0.36, 1.0)
		probe.ambient_color_energy = 0.34
		probe.position = pr_spec[1] as Vector3
		probe.size = pr_spec[2] as Vector3
		_warren_interior.add_child(probe)

	# 1. Dog-Leg Descent Tunnel Ramp (z=278..253) curving Eastward around massive West Bedrock/Root Buttress
	var d_len := sqrt(20.0 * 20.0 + 7.5 * 7.5)
	var d_pitch := atan2(7.5, 20.0)
	var d_cy := 18.25 - 0.50 * cos(d_pitch)
	_add_box_body(_warren_interior, Vector3(mx + 2.0, d_cy, 268.0), Vector3(13.0, 1.0, d_len + 2.0), LAYER_TERRAIN, -d_pitch, 0.0)
	# Throat shoring bent at z=271 & curved Eastward bent at z=261.5
	var ry_271 := WorldLandmarks.sample_rat_warren_floor(271.0).w
	_vault_timber_bent(_warren_interior, Vector3(mx + 0.6, ry_271, 271.0), 4.35, 5.0, PI * 0.5, 271)
	_vault_torch(_warren_interior, Vector3(mx - 3.60, ry_271 + 2.25, 271.0), -PI * 0.5, 1.9, 13.5)
	var ry_261 := WorldLandmarks.sample_rat_warren_floor(261.5).w
	_vault_timber_bent(_warren_interior, Vector3(mx + 5.6, ry_261, 261.5), 4.25, 5.1, PI * 0.5 + 0.28, 261)
	_vault_torch(_warren_interior, Vector3(mx + 9.50, ry_261 + 2.25, 260.4), PI * 0.5 + 0.28, 2.0, 14.5)
	# West-Wall Bedrock & Root Buttress jutting from the West lower descent to block straight-line sightlines
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx - 3.6, 16.2, 257.5), Vector3(3.6, 3.8, 3.4), _vault_rock_mat, 189, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx - 3.2, 18.6, 257.8), 0.35, 1.15, 9.6, 0.28, 190, _warren_bark_mat, false)
	# Subsided ruin masonry walls & pitched broken flagstones along the dog-leg ramp
	_place_ruin_wall(_warren_interior, "wall_broken.gltf.glb", Vector3(mx - 4.8, ry_271 - 0.45, 272.5), PI * 0.5 + 0.14, Vector3(1.0, 0.92, 1.0), Vector2(0.06, -0.09), _vault_wall_mat, false)
	_place_ruin_wall(_warren_interior, "wall_broken.gltf.glb", Vector3(mx + 9.2, ry_261 - 0.45, 263.0), -PI * 0.5 - 0.22, Vector3(1.0, 0.92, 1.0), Vector2(-0.05, 0.08), _vault_wall_mat, false)
	for df_i in range(4):
		var dfz := 274.5 - float(df_i) * 4.2
		var dfx := mx + lerpf(0.2, 3.6, float(df_i) / 3.0) + (0.6 if (df_i % 2 == 0) else -0.5)
		var dfy := WorldLandmarks.sample_rat_warren_floor(dfz).w - 0.04
		var d_piece := "floor_tile_small_broken_A.gltf.glb" if (df_i % 2 == 0) else "floor_tile_small_broken_B.gltf.glb"
		_place_ruin_wall(_warren_interior, d_piece, Vector3(dfx, dfy, dfz), float(df_i) * 0.42, Vector3(1.3, 1.0, 1.3), Vector2(-d_pitch, 0.0), _vault_floor_mat, false)

	# 2. REGION B: ASYMMETRICAL CENTRAL CONFLUENCE (-239.5, 244)
	# Single asymmetrical flooded cove basin (SW deep pocket + SE trickle) — ZERO classical columns or symmetrical arches!
	var main_wpm := PlaneMesh.new()
	main_wpm.size = Vector2(36.0, 28.0)
	main_wpm.subdivide_width = 24
	main_wpm.subdivide_depth = 20
	var main_wmi := MeshInstance3D.new()
	main_wmi.name = "VaultSunkenBasinWater"
	main_wmi.mesh = main_wpm
	main_wmi.material_override = _warren_water_mat
	main_wmi.position = Vector3(mx, 13.35, 244.0)
	main_wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warren_interior.add_child(main_wmi)

	var hub_grate := _place_piece(_warren_interior, "floor_tile_big_grate.gltf.glb", Vector3(mx + 1.2, vy - 0.06, 244.2), 0.34, Vector3.ONE)
	if hub_grate != null:
		_apply_mat_recursive(hub_grate, _vault_iron_mat)
	for rub_xy: Vector2 in [
		Vector2(mx - 4.4, 248.0), Vector2(mx + 4.1, 241.8), Vector2(mx - 7.8, 241.0),
		Vector2(mx + 8.2, 242.8), Vector2(mx - 6.6, 249.8), Vector2(mx + 6.4, 249.5),
	]:
		var rb := _place_piece(_warren_interior, "rubble_large.gltf.glb", Vector3(rub_xy.x, vy - 0.22, rub_xy.y), rub_xy.x * 0.37, Vector3(0.84, 0.42, 0.84))
		if rb != null:
			_apply_mat_recursive(rb, _vault_rock_mat)
	# Half-buried sunken ruin foundations & broken cellar wall in Crossroads
	_place_ruin_wall(_warren_interior, "floor_foundation_allsides.gltf.glb", Vector3(mx - 9.5, vy - 0.85, 249.5), 0.42, Vector3(1.25, 0.65, 1.25), Vector2(0.08, -0.07), _vault_trim_mat, false)
	_place_ruin_wall(_warren_interior, "floor_foundation_allsides.gltf.glb", Vector3(mx + 9.8, vy - 0.80, 247.5), -0.35, Vector3(1.20, 0.65, 1.20), Vector2(-0.07, 0.06), _vault_trim_mat, false)
	_place_ruin_wall(_warren_interior, "wall_broken.gltf.glb", Vector3(mx - 12.8, vy - 0.30, 249.0), PI * 0.5 + 0.18, Vector3(1.0, 0.85, 1.0), Vector2(0.05, -0.06), _vault_wall_mat, false)
	for dr_p: Array in [[mx - 3.2, 232.0, 0.5], [mx + 3.0, 231.8, -0.4]]:
		var dr_n := _place_piece(_warren_interior, "rubble_half.gltf.glb", Vector3(float(dr_p[0]), vy - 0.15, float(dr_p[1])), float(dr_p[2]), Vector3(1.15, 0.85, 1.15))
		if dr_n != null:
			_strip_piece_colliders(dr_n)
			_apply_mat_recursive(dr_n, _vault_trim_mat)

	# Single NE Elevated Timber Scavenger Loft (asymmetrical — NO mirrored twin gallery!)
	var gx := mx + 11.5
	var gy := vy + 3.45
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(gx - 1.4, vy + 1.45, 232.2), 0.0, PI * 0.5, 5.2, 0.22, 515, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(gx - 1.4, vy + 1.45, 235.4), 0.0, PI * 0.5, 5.2, 0.22, 518, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(gx - 0.6, gy, 233.6), 0.14, 0.0, 5.4, 0.24, 520, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(gx - 0.8, gy, 234.3), 0.14, 0.0, 5.2, 0.22, 530, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(gx - 0.4, gy - 1.15, 232.2), 0.0, -0.72, 2.8, 0.18, 540, _warren_bark_mat, false)
	var g_crates := _place_piece(_warren_interior, "crates_stacked.gltf.glb", Vector3(gx - 0.4, gy + 0.16, 233.4), 0.5, Vector3.ONE * 0.90)
	_harmonize_prop_mats(g_crates, Color(0.42, 0.38, 0.34), 0.95, 0.03)
	_vault_torch(_warren_interior, Vector3(gx - 1.4, vy + 2.85, 235.4), -PI * 0.35, 2.1, 15.0)

	# Crooked timber gangplanks & two asymmetrical grounded torch posts in Crossroads
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx - 11.8, vy + 0.08, 243.4), 0.24, 0.0, 4.9, 0.24, 501, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx + 12.2, vy + 0.08, 241.5), -0.18, 0.0, 4.8, 0.24, 502, _warren_bark_mat, true)
	_vault_post_torch(_warren_interior, Vector3(mx - 4.5, vy, 247.6), 0.55, 551, 2.0, 15.5)
	_vault_post_torch(_warren_interior, Vector3(mx + 6.4, vy, 240.2), -0.85, 552, 2.0, 15.5)

	# Single SW Seepage Waterfall pouring into SW Cove + Crystal Glow
	var wf_mesh := PlaneMesh.new()
	wf_mesh.size = Vector2(2.6, 7.6)
	wf_mesh.subdivide_width = 8
	wf_mesh.subdivide_depth = 16
	var wf_mi := MeshInstance3D.new()
	wf_mi.name = "RatConfluenceWaterfall_SW"
	wf_mi.mesh = wf_mesh
	wf_mi.material_override = _vault_waterfall_mat
	wf_mi.position = Vector3(mx - 13.5, vy + 2.2, 246.5)
	wf_mi.rotation = Vector3(0.0, PI * 0.42, 0.0)
	wf_mi.rotate_object_local(Vector3.RIGHT, PI * 0.5 - 0.14)
	wf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warren_interior.add_child(wf_mi)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(mx - 10.2, basin_y - 0.15, 246.8), 6, 210)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(mx + 7.2, basin_y - 0.15, 247.8), 4, 245)
	_add_flicker_light(_warren_interior, Vector3(mx - 9.0, basin_y + 1.2, 246.5), Color(0.20, 0.58, 0.54), 1.45, 14.0)

	# Asymmetric Lower Descent Outlet Boulders & Plunging Root Framing (replaces symmetric column pair at 255.8)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx + 8.8, vy + 2.6, 255.6), Vector3(3.2, 3.6, 2.8), _vault_rock_mat, 823, true)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx - 7.8, vy + 2.8, 254.2), Vector3(3.4, 3.8, 2.8), _vault_rock_mat, 839, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx + 6.4, vy + 3.2, 254.0), -0.45, 0.85, 6.4, 0.26, 851, _warren_bark_mat, false)

	# CENTRAL KARST & ROOT DIVIDE (mx, vy, 224..232) — Physically & Visually splits Hub into Winding NW & NE Burrows!
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx, vy + 2.4, 229.5), Vector3(3.6, 3.4, 3.8), _vault_rock_mat, 861, true)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx - 2.6, vy + 1.8, 231.0), Vector3(2.8, 2.8, 3.0), _vault_rock_mat, 862, true)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx + 2.4, vy + 2.0, 230.5), Vector3(2.8, 3.0, 3.0), _vault_rock_mat, 863, true)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx - 0.5, vy + 3.2, 223.0), Vector3(4.4, 4.4, 4.8), _vault_rock_mat, 864, true)
	# Plunging giant roots anchored floor-to-ceiling binding the central rock divide
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx - 1.2, vy + 4.8, 229.0), 0.25, 1.22, 12.6, 0.36, 870, _warren_bark_mat, false)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx + 1.6, vy + 4.8, 227.5), -0.42, 1.18, 12.4, 0.32, 871, _warren_bark_mat, false)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx + 0.2, vy + 4.6, 231.5), 0.65, 1.16, 12.2, 0.26, 872, _warren_bark_mat, false)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(mx - 1.8, vy + 0.1, 232.6), 5, 875)
	_add_flicker_light(_warren_interior, Vector3(mx - 1.6, vy + 2.0, 232.5), Color(0.22, 0.64, 0.58), 1.6, 14.5)

	# Central Rotunda Overhead Skylight Chimney (y=24.15 -> central confluence 14.5)
	for ic: Array in [
		[Vector3(mx - 3.6, 23.8, 244.5), Vector3(2.2, 1.35, 3.8), 315],
		[Vector3(mx + 3.6, 23.8, 244.5), Vector3(2.2, 1.35, 3.8), 316],
		[Vector3(mx, 23.8, 244.5 - 3.6), Vector3(3.8, 1.35, 2.2), 317],
		[Vector3(mx, 23.8, 244.5 + 3.6), Vector3(3.8, 1.35, 2.2), 318],
	]:
		CavePropFX.spawn_fractured_boulder(_warren_interior, ic[0] as Vector3, ic[1] as Vector3, _vault_rock_mat, int(ic[2]), false)
	var sky_grate := _place_piece(_warren_interior, "floor_tile_big_grate.gltf.glb", Vector3(mx, 24.15, 244.5), 0.0, Vector3(1.45, 1.0, 1.45))
	if sky_grate != null:
		_apply_mat_recursive(sky_grate, _vault_iron_mat)
	for gr_s: float in [-1.0, 1.0]:
		_vault_box_mesh(_warren_interior, Vector3(mx + gr_s * 3.1, 24.0, 244.5), Vector3(0.75, 0.85, 6.8), _vault_trim_mat)
		_vault_box_mesh(_warren_interior, Vector3(mx, 24.0, 244.5 + gr_s * 3.1), Vector3(6.8, 0.85, 0.75), _vault_trim_mat)

	var sky_spot := SpotLight3D.new()
	sky_spot.name = "RatVaultSkylightSpot"
	sky_spot.position = Vector3(mx, 23.75, 244.5)
	sky_spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	sky_spot.light_color = Color(0.72, 0.88, 0.98)
	sky_spot.light_energy = 11.0
	sky_spot.spot_range = 26.0
	sky_spot.spot_angle = 30.0
	sky_spot.spot_attenuation = 0.65
	sky_spot.shadow_enabled = true
	sky_spot.shadow_bias = 0.04
	_warren_interior.add_child(sky_spot)

	var beam_shader: Shader = load("res://terrain/cave_sunbeam.gdshader")
	if beam_shader != null:
		var bmat := ShaderMaterial.new()
		bmat.shader = beam_shader
		bmat.set_shader_parameter("beam_color", Color(0.68, 0.86, 0.98))
		bmat.set_shader_parameter("beam_intensity", 0.13)
		var bmesh := CylinderMesh.new()
		bmesh.top_radius = 1.65
		bmesh.bottom_radius = 4.05
		bmesh.height = 9.4
		bmesh.radial_segments = 24
		bmesh.rings = 6
		bmesh.cap_top = false
		bmesh.cap_bottom = false
		var bmi := MeshInstance3D.new()
		bmi.name = "RatVaultSkylightBeam"
		bmi.mesh = bmesh
		bmi.material_override = bmat
		bmi.position = Vector3(mx, vy + 4.70, 244.5)
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_warren_interior.add_child(bmi)

	# 3. REGION C: WEST WING — NATURAL BOULDER SQUEEZE ARCH (x=-258, z=238.2) -> CRESCENT SUMP & NW BOLT-HOLE
	for gz_off: float in [-1.55, 1.55]:
		CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx - 18.0, vy + 1.8, 238.2 + gz_off * 1.45), Vector3(1.9, 2.9, 1.9), _vault_rock_mat, 750 + int(gz_off * 10.0), true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx - 18.0, vy + 2.5, 238.2), 0.14, 0.0, 5.0, 0.30, 758, _warren_bark_mat, true)
	_vault_box_solid(_warren_interior, Vector3(mx - 18.0, vy + 1.55, 238.2), Vector3(0.42, 1.25, 2.0), _vault_iron_mat, LAYER_OBSTACLES)

	var west_wpm := PlaneMesh.new()
	west_wpm.size = Vector2(30.0, 32.0)
	var west_wmi := MeshInstance3D.new()
	west_wmi.mesh = west_wpm
	west_wmi.material_override = _warren_water_mat
	west_wmi.position = Vector3(-276.0, 13.35, 243.5)
	west_wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warren_interior.add_child(west_wmi)
	var dp := _place_piece(_warren_interior, "rubble_large.gltf.glb", Vector3(-279.0, vy - 0.12, 244.5), 0.85, Vector3(1.4, 0.75, 1.4))
	if dp != null:
		_apply_mat_recursive(dp, _vault_rock_mat)
	for dock_i in range(3):
		var dz := 242.8 + float(dock_i) * 0.62
		CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(-278.4, vy - 0.04, dz), 0.06 * float(dock_i - 1), 0.0, 3.8, 0.20, 710 + dock_i, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(-273.5, vy + 0.06, 246.5), 0.48, 0.0, 5.8, 0.28, 701, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(-278.5, vy + 0.06, 239.2), -0.35, 0.0, 5.2, 0.26, 702, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(-261.0, 17.2, 226.5), 0.75, 1.16, 10.4, 0.24, 718, _warren_bark_mat, false)
	_vault_post_torch(_warren_interior, Vector3(-272.2, vy, 240.0), 0.45, 725, 2.0, 15.0)
	_vault_post_torch(_warren_interior, Vector3(-279.6, vy, 246.8), -0.75, 726, 2.0, 15.5)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(-287.6, vy + 1.8, 241.0), Vector3(2.2, 3.4, 2.2), _vault_rock_mat, 741, true)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(-287.6, vy + 1.8, 246.0), Vector3(2.2, 3.4, 2.2), _vault_rock_mat, 742, true)
	CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(-287.4, vy + 0.6, 243.5), Vector3(1.6, 1.3, 2.6), _vault_rock_mat, 743, false)
	var w_wf_m := PlaneMesh.new()
	w_wf_m.size = Vector2(3.0, 7.6)
	var w_wf_mi := MeshInstance3D.new()
	w_wf_mi.mesh = w_wf_m
	w_wf_mi.material_override = _vault_waterfall_mat
	w_wf_mi.position = Vector3(-286.6, vy + 2.4, 243.5)
	w_wf_mi.rotation = Vector3(0.0, PI * 0.5, 0.0)
	w_wf_mi.rotate_object_local(Vector3.RIGHT, PI * 0.5 - 0.14)
	w_wf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warren_interior.add_child(w_wf_mi)
	_place_ruin_wall(_warren_interior, "wall_arched.gltf.glb", Vector3(-286.2, vy - 0.20, 243.5), PI * 0.5, Vector3(1.05, 1.02, 1.05), Vector2.ZERO, _vault_wall_mat, false)
	CavePropFX.spawn_speleothem_cluster(_warren_interior, [
		{"pos": Vector3(-285.0, 13.35, 238.5), "len": 3.4, "rad": 0.46, "ceiling": false},
		{"pos": Vector3(-284.5, 13.35, 248.0), "len": 3.2, "rad": 0.44, "ceiling": false},
		{"pos": Vector3(-275.0, 21.8, 240.0), "len": 2.9, "rad": 0.42, "ceiling": true},
		{"pos": Vector3(-276.0, 21.8, 247.0), "len": 3.1, "rad": 0.44, "ceiling": true},
	], _warren_spel_mat)
	var w_bars := _place_piece(_warren_interior, "barrel_small_stack.gltf.glb", Vector3(-270.4, vy - 0.02, 240.4), 0.4, Vector3.ONE * 1.58)
	_harmonize_prop_mats(w_bars, Color(0.42, 0.38, 0.34), 0.95, 0.03)
	var w_crates := _place_piece(_warren_interior, "crates_stacked.gltf.glb", Vector3(-278.8, vy - 0.02, 244.5), -0.65, Vector3.ONE * 1.58)
	_harmonize_prop_mats(w_crates, Color(0.40, 0.36, 0.32), 0.95, 0.03)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(-283.5, 13.35, 240.5), 6, 401)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(-282.5, 13.35, 247.0), 5, 402)
	_add_flicker_light(_warren_interior, Vector3(-280.0, 14.8, 243.5), Color(0.22, 0.62, 0.58), 1.8, 16.0)

	# 4. REGION D: EAST WING — KNEE-BRACED TIMBERING, TWISTING TREE ROOTS & FUNGAL LARDER (-203, 242)
	for sh_spec: Array in [
		[Vector3(-212.5, vy, 242.5), 0.36, 5.4, 4.1],
		[Vector3(-203.0, vy, 241.5), -0.34, 5.7, 4.4],
		[Vector3(-207.0, vy, 229.0), 1.05, 5.3, 4.1],
	]:
		_vault_timber_bent(_warren_interior, sh_spec[0] as Vector3, float(sh_spec[3]), float(sh_spec[2]), float(sh_spec[1]), int(absf((sh_spec[0] as Vector3).z)))
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(-196.2, vy + 4.8, 238.0), 0.42, 1.18, 12.2, 0.34, 621, _warren_bark_mat, false)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(-197.0, vy + 4.8, 245.5), -0.48, 1.16, 12.0, 0.32, 622, _warren_bark_mat, false)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(-195.8, vy + 1.48, 241.5), 6, 631)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(-204.2, vy - 0.05, 247.5), 5, 632)
	_add_flicker_light(_warren_interior, Vector3(-196.0, vy + 2.8, 241.5), Color(0.22, 0.62, 0.58), 1.7, 15.0)
	_vault_post_torch(_warren_interior, Vector3(-207.2, vy, 232.0), 0.65, 635, 2.0, 15.0)
	_vault_post_torch(_warren_interior, Vector3(-200.5, vy, 245.6), -1.10, 636, 2.1, 15.5)
	for eb_boulder: Array in [
		[Vector3(-193.0, vy + 2.6, 236.5), Vector3(3.6, 2.8, 3.4), 601],
		[Vector3(-192.5, vy + 2.8, 247.5), Vector3(3.8, 3.0, 3.5), 602],
		[Vector3(-204.5, vy + 1.4, 249.8), Vector3(3.2, 2.4, 2.8), 604],
	]:
		CavePropFX.spawn_fractured_boulder(_warren_interior, eb_boulder[0] as Vector3, eb_boulder[1] as Vector3, _vault_rock_mat, int(eb_boulder[2]), true)
	_place_ruin_wall(_warren_interior, "wall_cracked.gltf.glb", Vector3(-194.2, vy + 1.45, 242.0), -PI * 0.5, Vector3(1.36, 1.26, 1.36), Vector2(-0.04, 0.05), _vault_wall_mat, false)
	var e_shelf := _place_ruin_wall(_warren_interior, "wall_shelves.gltf.glb", Vector3(-194.6, vy + 1.45, 242.0), -PI * 0.5, Vector3.ONE * 1.50, Vector2.ZERO, null, false)
	_harmonize_prop_mats(e_shelf, Color(0.42, 0.38, 0.34), 0.95, 0.03)
	CavePropFX.spawn_speleothem_cluster(_warren_interior, [
		{"pos": Vector3(-196.5, vy + 1.45, 236.5), "len": 3.4, "rad": 0.45, "ceiling": false},
		{"pos": Vector3(-196.5, vy + 1.45, 247.0), "len": 3.6, "rad": 0.46, "ceiling": false},
		{"pos": Vector3(-205.5, 25.8, 238.5), "len": 3.2, "rad": 0.42, "ceiling": true},
		{"pos": Vector3(-205.5, 25.8, 246.0), "len": 3.1, "rad": 0.42, "ceiling": true},
	], _warren_spel_mat)
	var e_crates := _place_piece(_warren_interior, "crates_stacked.gltf.glb", Vector3(-195.8, vy + 1.48, 243.4), -0.4, Vector3.ONE * 1.60)
	_harmonize_prop_mats(e_crates, Color(0.42, 0.38, 0.34), 0.95, 0.03)
	var e_bar := _place_piece(_warren_interior, "barrel_small_stack.gltf.glb", Vector3(-202.2, vy - 0.02, 237.2), 0.7, Vector3.ONE * 1.58)
	_harmonize_prop_mats(e_bar, Color(0.42, 0.38, 0.34), 0.95, 0.03)
	for eb_spot: Vector3 in [Vector3(-205.5, vy + 0.08, 242.5), Vector3(-201.5, vy + 0.08, 236.8), Vector3(-199.5, vy + 0.08, 240.0)]:
		_spawn_articulated_bone(_warren_interior, eb_spot, eb_spot.z * 0.4, 0.95)

	# 5. REGION E: SPLIT NW & NE WINDING BURROW LOOPS -> RAT KING'S DEEP BROOD HOLLOW (-239, 194, y=10 -> 11.45)
	var n_slope_len := sqrt(29.0 * 29.0 + 4.5 * 4.5)
	var n_pitch := atan2(4.5, 29.0)
	var n_cy := 12.25 - 0.50 * cos(n_pitch)
	_add_box_body(_warren_interior, Vector3(-249.0, n_cy, 217.5), Vector3(9.5, 1.0, n_slope_len + 2.0), LAYER_TERRAIN, -n_pitch, -0.15)
	_add_box_body(_warren_interior, Vector3(-228.5, n_cy, 217.5), Vector3(9.5, 1.0, n_slope_len + 2.0), LAYER_TERRAIN, -n_pitch, 0.15)
	# Curving NE & NW Burrow Timber Shoring + Outer-Wall Bend Torches guiding around the Central Bedrock Divide
	for b_spec: Array in [
		[Vector3(-251.5, WorldLandmarks.sample_rat_warren_floor(223.5).w, 223.5), 4.0, 5.2, PI * 0.5 - 0.35],
		[Vector3(-248.5, WorldLandmarks.sample_rat_warren_floor(212.5).w, 212.5), 4.1, 5.4, PI * 0.5 + 0.25],
		[Vector3(-226.0, WorldLandmarks.sample_rat_warren_floor(222.0).w, 222.0), 4.2, 5.4, PI * 0.5 + 0.36],
		[Vector3(-228.8, WorldLandmarks.sample_rat_warren_floor(211.0).w, 211.0), 4.2, 5.5, PI * 0.5 - 0.28],
	]:
		_vault_timber_bent(_warren_interior, b_spec[0] as Vector3, float(b_spec[1]), float(b_spec[2]), float(b_spec[3]), int((b_spec[0] as Vector3).z))
	_vault_post_torch(_warren_interior, Vector3(-254.2, WorldLandmarks.sample_rat_warren_floor(222.5).w, 222.5), PI * 0.45, 921, 2.0, 14.5)
	_vault_post_torch(_warren_interior, Vector3(-222.6, WorldLandmarks.sample_rat_warren_floor(221.5).w, 221.5), -PI * 0.45, 922, 2.1, 15.0)
	_vault_post_torch(_warren_interior, Vector3(-225.2, WorldLandmarks.sample_rat_warren_floor(210.5).w, 210.5), -PI * 0.35, 923, 2.0, 14.5)

	# Single Asymmetrical NW Dark Seepage Pool + Crooked Fallen-Log Bridges (9.20m water fills carved 8.25m cove cleanly)
	var m_pm := PlaneMesh.new()
	m_pm.size = Vector2(11.5, 28.0)
	var m_mi := MeshInstance3D.new()
	m_mi.mesh = m_pm
	m_mi.material_override = _warren_water_mat
	m_mi.position = Vector3(mx - 18.5, 9.20, 193.5)
	m_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warren_interior.add_child(m_mi)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx - 15.5, sy - 0.15, 195.0), -0.18, 0.0, 6.2, 0.28, 560, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx - 16.0, sy - 0.14, 192.2), 0.22, 0.0, 5.8, 0.24, 561, _warren_bark_mat, true)
	_add_flicker_light(_warren_interior, Vector3(mx - 17.5, 10.8, 193.5), Color(0.20, 0.58, 0.54), 1.6, 16.0)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(mx - 16.2, 9.15, 199.0), 5, 505)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(mx - 15.8, 9.15, 188.0), 5, 525)

	for rub_n: Array in [
		[mx - 4.2, 201.5, 0.4], [mx + 4.4, 200.5, -0.5],
		[mx - 5.2, 192.0, -0.3], [mx + 5.0, 191.0, 0.7],
	]:
		var rn := _place_piece(_warren_interior, "rubble_large.gltf.glb", Vector3(float(rub_n[0]), sy - 0.16, float(rub_n[1])), float(rub_n[2]), Vector3(1.15, 0.55, 1.15))
		if rn != null:
			_apply_mat_recursive(rn, _vault_rock_mat)

	# Massive Plunging Subterranean Tree Roots anchored floor-to-ceiling around Deep Brood Hollow perimeter
	for root_arc: Array in [
		[Vector3(mx - 12.2, sy + 6.2, 201.0), 0.35, 1.18, 15.2, 0.42, 901],
		[Vector3(mx + 12.6, sy + 6.2, 199.5), -0.42, 1.16, 15.4, 0.44, 902],
		[Vector3(mx - 13.0, sy + 6.0, 190.5), 0.62, 1.20, 14.8, 0.40, 903],
		[Vector3(mx + 12.2, sy + 6.2, 188.0), -0.55, 1.18, 15.0, 0.38, 904],
	]:
		CavePropFX.spawn_bark_fallen_log(_warren_interior, root_arc[0] as Vector3, float(root_arc[1]), float(root_arc[2]), float(root_arc[3]), float(root_arc[4]), int(root_arc[5]), _warren_bark_mat, false)
	for perim_b: Array in [
		[Vector3(mx - 12.0, sy + 1.4, 204.5), Vector3(2.8, 3.0, 2.6), 911],
		[Vector3(mx + 12.6, sy + 1.6, 202.0), Vector3(3.0, 3.2, 2.8), 912],
		[Vector3(mx + 14.2, sy + 1.8, 191.5), Vector3(3.2, 3.4, 3.0), 913],
	]:
		CavePropFX.spawn_fractured_boulder(_warren_interior, perim_b[0] as Vector3, perim_b[1] as Vector3, _vault_rock_mat, int(perim_b[2]), true)
	_vault_post_torch(_warren_interior, Vector3(mx - 10.6, sy, 197.5), 0.72, 931, 2.1, 16.0)
	_vault_post_torch(_warren_interior, Vector3(mx + 11.4, sy, 196.0), -0.82, 932, 2.1, 16.5)

	# Rat King's Tangled Root & Bone Brood Mound (y=11.45, -238.5, 181.5 — ZERO chest, ZERO coins/cheese!)
	var dais_y := sy + 1.45
	for rub_off: Vector2 in [Vector2(-4.4, 180.6), Vector2(4.4, 180.6), Vector2(-7.8, 182.2), Vector2(7.8, 182.2), Vector2(0.0, 178.0)]:
		CavePropFX.spawn_fractured_boulder(_warren_interior, Vector3(mx + rub_off.x, dais_y + 1.2, rub_off.y), Vector3(2.8, 2.8, 2.4), _vault_rock_mat, int(absf(rub_off.y) + rub_off.x), true)
	CavePropFX.spawn_speleothem_cluster(_warren_interior, [
		{"pos": Vector3(mx - 6.8, dais_y - 0.2, 180.0), "len": 5.6, "rad": 0.65, "ceiling": false},
		{"pos": Vector3(mx + 6.8, dais_y - 0.2, 180.0), "len": 5.6, "rad": 0.65, "ceiling": false},
		{"pos": Vector3(mx - 3.6, dais_y - 0.2, 178.8), "len": 6.4, "rad": 0.72, "ceiling": false},
		{"pos": Vector3(mx + 3.6, dais_y - 0.2, 178.8), "len": 6.4, "rad": 0.72, "ceiling": false},
		{"pos": Vector3(mx - 4.0, 23.0, 185.0), "len": 4.2, "rad": 0.52, "ceiling": true},
		{"pos": Vector3(mx + 4.0, 23.0, 185.0), "len": 4.2, "rad": 0.52, "ceiling": true},
	], _warren_spel_mat)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(mx - 3.4, dais_y - 0.05, 180.8), 6, 971)
	_spawn_vault_crystal_cluster(_warren_interior, Vector3(mx + 3.4, dais_y - 0.05, 180.8), 6, 972)
	var altar_y := dais_y - 0.02
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx - 0.8, altar_y + 0.35, 181.2), 0.38, 0.22, 5.2, 0.28, 981, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx + 1.2, altar_y + 0.40, 180.9), -0.46, 0.25, 4.8, 0.26, 982, _warren_bark_mat, true)
	CavePropFX.spawn_bark_fallen_log(_warren_interior, Vector3(mx + 0.4, altar_y + 0.55, 182.1), 1.42, 0.14, 4.2, 0.22, 983, _warren_bark_mat, false)
	for nb: Array in [
		[Vector3(mx - 1.4, altar_y + 0.10, 182.0), 0.45, 1.15],
		[Vector3(mx + 1.6, altar_y + 0.12, 181.8), -0.82, 1.25],
		[Vector3(mx + 0.1, altar_y + 0.14, 183.0), 1.30, 1.20],
		[Vector3(mx - 2.6, altar_y + 0.10, 182.6), -0.35, 1.05],
		[Vector3(mx + 2.8, altar_y + 0.10, 182.8), 0.90, 1.08],
		[Vector3(mx + 0.6, altar_y + 0.45, 181.2), 2.15, 0.95],
	]:
		_spawn_articulated_bone(_warren_interior, nb[0] as Vector3, float(nb[1]), float(nb[2]))
	var nest_keg := _place_piece(_warren_interior, "keg_decorated.gltf.glb", Vector3(mx - 2.4, altar_y, 181.0), 0.55, Vector3.ONE * 1.55)
	_harmonize_prop_mats(nest_keg, Color(0.40, 0.36, 0.32), 0.95, 0.03)
	var nest_bar := _place_piece(_warren_interior, "barrel_small_stack.gltf.glb", Vector3(mx + 2.5, altar_y, 181.1), -0.70, Vector3.ONE * 1.55)
	_harmonize_prop_mats(nest_bar, Color(0.39, 0.36, 0.33), 0.95, 0.03)
	_place_ruin_wall(_warren_interior, "wall_broken.gltf.glb", Vector3(mx - 11.5, sy - 0.30, 189.0), PI * 0.5 + 0.12, Vector3(1.38, 1.28, 1.38), Vector2(0.05, -0.06), _vault_wall_mat, false)
	_place_ruin_wall(_warren_interior, "wall_broken.gltf.glb", Vector3(mx + 11.8, sy - 0.30, 187.5), -PI * 0.5 - 0.14, Vector3(1.38, 1.28, 1.38), Vector2(-0.04, 0.07), _vault_wall_mat, false)
	_place_ruin_wall(_warren_interior, "pillar_decorated.gltf.glb", Vector3(mx - 3.8, dais_y + 0.30, 182.2), 0.60, Vector3.ONE * 1.65, Vector2(0.25, 1.32), _vault_trim_mat, false)
	_add_flicker_light(_warren_interior, Vector3(mx + 0.8, altar_y + 2.6, 181.6), Color(0.95, 0.58, 0.24), 2.8, 20.0)
	_add_flicker_light(_warren_interior, Vector3(mx - 2.8, altar_y + 1.8, 181.2), Color(0.20, 0.68, 0.62), 2.1, 18.0)

	# Scavenged Barrels/Crates, Articulated Bones, Speleothems, Vines, Mushroom Groves & Pebbles across all Burrows
	for prop_spec: Array in [
		["barrel_small_stack.gltf.glb", Vector3(mx - 6.8, sy - 0.02, 182.8), 0.4, 1.58, Vector3(2.4, 2.6, 2.4)],
		["keg_decorated.gltf.glb", Vector3(mx + 6.6, sy - 0.02, 183.0), -0.6, 1.58, Vector3(2.4, 2.6, 2.4)],
		["barrel_large_decorated.gltf.glb", Vector3(mx - 8.2, vy - 0.02, 252.6), -0.45, 1.55, Vector3(2.4, 2.6, 2.4)],
		["crates_stacked.gltf.glb", Vector3(mx - 8.5, sy - 0.02, 201.0), 0.35, 1.55, Vector3(2.5, 2.7, 2.5)],
	]:
		var pnode := _place_piece(_warren_interior, String(prop_spec[0]), prop_spec[1], float(prop_spec[2]), Vector3.ONE * float(prop_spec[3]))
		_harmonize_prop_mats(pnode, Color(0.40, 0.37, 0.34), 0.95, 0.03)
		var csz: Vector3 = prop_spec[4]
		_add_box_body(_warren_interior, (prop_spec[1] as Vector3) + Vector3(0.0, csz.y * 0.5, 0.0), csz, LAYER_OBSTACLES)

	for rbone: Array in [
		[Vector3(mx - 2.1, vy + 0.09, 234.5), 0.5, 0.85],
		[Vector3(mx + 2.2, vy + 0.09, 237.8), -1.1, 0.78],
		[Vector3(mx - 6.8, vy + 0.09, 249.6), 1.7, 0.82],
		[Vector3(mx + 6.6, vy + 0.09, 249.4), -0.4, 0.90],
		[Vector3(mx - 5.2, sy + 0.09, 196.0), 0.9, 0.95],
		[Vector3(mx + 5.8, sy + 0.09, 193.0), -1.3, 0.92],
	]:
		_spawn_articulated_bone(_warren_interior, rbone[0] as Vector3, float(rbone[1]), float(rbone[2]))

	CavePropFX.spawn_speleothem_cluster(_warren_interior, [
		{"pos": Vector3(mx - 10.6, 23.4, 233.8), "len": 3.1, "rad": 0.42, "ceiling": true},
		{"pos": Vector3(mx + 10.6, 23.4, 233.8), "len": 3.0, "rad": 0.40, "ceiling": true},
		{"pos": Vector3(-278.0, 21.4, 238.0), "len": 3.2, "rad": 0.42, "ceiling": true},
		{"pos": Vector3(-200.0, 21.8, 244.0), "len": 3.2, "rad": 0.42, "ceiling": true},
		{"pos": Vector3(mx - 12.0, 22.8, 194.0), "len": 3.6, "rad": 0.48, "ceiling": true},
		{"pos": Vector3(mx + 12.0, 22.8, 194.0), "len": 3.6, "rad": 0.48, "ceiling": true},
	], _warren_spel_mat)

	CavePropFX.spawn_vine_batch(_warren_interior, [
		{"pos": Vector3(mx - 2.6, 23.8, 244.5), "len": 3.2, "width": 0.85, "rot": 0.5},
		{"pos": Vector3(mx + 2.6, 23.8, 244.5), "len": 3.0, "width": 0.85, "rot": 1.9},
		{"pos": Vector3(mx - 6.8, 22.8, 238.5), "len": 2.5, "width": 0.90, "rot": 2.5},
		{"pos": Vector3(mx + 6.8, 22.8, 238.5), "len": 2.6, "width": 0.90, "rot": 0.9},
		{"pos": Vector3(-203.0, 21.5, 240.0), "len": 3.4, "width": 1.0, "rot": 1.2},
		{"pos": Vector3(mx, 22.2, 231.0), "len": 4.2, "width": 1.1, "rot": 0.8},
	])

	var wmush_xfs: Array[Transform3D] = []
	for m_pos: Vector3 in [
		Vector3(mx - 7.8, vy, 239.4), Vector3(mx + 7.8, vy, 239.8),
		Vector3(mx - 7.2, vy, 250.2), Vector3(mx + 7.2, vy, 250.6),
		Vector3(-206.0, vy, 237.5), Vector3(-202.0, vy, 246.5),
		Vector3(-198.5, vy + 1.50, 239.0), Vector3(-196.0, vy + 1.50, 246.0),
		Vector3(-271.0, vy, 238.5), Vector3(mx + 9.0, sy, 203.0),
		Vector3(mx - 1.8, vy, 233.2), Vector3(mx + 1.9, altar_y, 182.8),
		Vector3(mx - 2.1, altar_y, 182.4),
	]:
		var bm := Basis.from_euler(Vector3(0.0, float(wmush_xfs.size()) * 1.4, 0.0)).scaled(Vector3.ONE * 1.30)
		wmush_xfs.append(Transform3D(bm, m_pos))
	CavePropFX.spawn_gltf_batch(_warren_interior, "RatMushrooms", "res://assets/nature/Mushroom_Common.gltf", wmush_xfs)

	var rpeb_xfs: Array[Transform3D] = []
	for p_pos: Vector3 in [
		Vector3(mx - 2.2, vy, 245.5), Vector3(mx + 2.4, vy, 242.6), Vector3(mx - 1.5, vy, 238.0),
		Vector3(mx + 1.8, vy, 234.0), Vector3(mx - 6.4, vy, 242.5), Vector3(mx + 6.4, vy, 242.5),
		Vector3(-272.0, vy, 244.0), Vector3(-204.0, vy, 241.0), Vector3(mx - 4.0, sy, 198.0),
		Vector3(mx + 4.0, sy, 192.0),
	]:
		var k := float(rpeb_xfs.size())
		var s := 0.50 + 0.25 * fmod(k * 0.41, 1.0)
		rpeb_xfs.append(Transform3D(Basis.from_euler(Vector3(0.0, k, 0.0)).scaled(Vector3(s, s * 0.65, s)), p_pos))
	CavePropFX.spawn_gltf_batch(_warren_interior, "RatPebbles", "res://assets/nature/Pebble_Round_1.gltf", rpeb_xfs)


func _apply_mat_recursive(node: Node, mat: Material) -> void:
	if node == null or mat == null:
		return
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			(cur as MeshInstance3D).material_override = mat
		for ch in cur.get_children():
			stack.append(ch)


func _build_rat_swamp_surroundings(warren_root: Node3D, mx: float, my: float, sw_y: float, sample_rw_h: Callable) -> void:
	# 1. Continuous Sunken Swamp Lagoon & Marsh Channels sheet at sw_y = 21.38 m
	#    Starts south of the Dog-Leg Vault Breach (bz >= 286) so underground chambers never clip,
	#    naturally submerging below raised dry stone courtyards/causeways (y ~ 22.0 m).
	var swamp_sheet := PlaneMesh.new()
	swamp_sheet.size = Vector2(220.0, 180.0)
	swamp_sheet.subdivide_width = 48
	swamp_sheet.subdivide_depth = 40
	var swamp_mi := MeshInstance3D.new()
	swamp_mi.name = "RatSwampLagoonWater"
	swamp_mi.mesh = swamp_sheet
	swamp_mi.material_override = _swamp_water_mat
	swamp_mi.position = Vector3(mx, sw_y, 355.0)
	swamp_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warren_root.add_child(swamp_mi)

	# 2. Flooded Southern Swamp Bridge Approach Parapets & Moor Lantern Bollards (bz = 365..378)
	for br_s: float in [-1.0, 1.0]:
		var bpx := mx + br_s * 4.8
		var bpy := float(sample_rw_h.call(bpx, 372.5)) - 0.15
		_place_ruin_wall(warren_root, "pillar.gltf.glb", Vector3(bpx, bpy, 372.5), br_s * 0.25, Vector3.ONE * 1.15, Vector2(0.03 * br_s, -0.04 * br_s), _vault_trim_mat, true, Vector3(1.1, 3.0, 1.1))
		_vault_torch(warren_root, Vector3(mx + br_s * 4.35, bpy + 2.05, 372.5), -br_s * PI * 0.5, 1.85, 13.5)
		_place_ruin_wall(warren_root, "wall_broken.gltf.glb", Vector3(mx + br_s * 5.2, bpy - 0.45, 366.5), PI * 0.5 + br_s * 0.08, Vector3(0.95, 0.55, 0.95), Vector2.ZERO, _vault_wall_mat, true, Vector3(3.6, 1.6, 0.9))

	# 3. Sunken Timber Boardwalks, Swamp Ferry Piers & Half-Submerged Rowboats (west & east lagoons)
	var swamp_timber_color := Color(0.36, 0.34, 0.28)
	var docks: Array[Array] = [
		["res://assets/fishing/platform-planks.glb", Vector3(mx - 12.0, sw_y + 0.08, 344.2), PI * 0.5, Vector3(1.25, 1.0, 1.25), Vector3(5.0, 0.6, 2.6)],
		["res://assets/fishing/structure-platform-dock.glb", Vector3(mx - 17.5, sw_y + 0.08, 344.2), PI * 0.5, Vector3(1.20, 1.05, 1.20), Vector3(6.2, 0.8, 2.8)],
		["res://assets/fishing/platform-planks.glb", Vector3(mx - 23.4, sw_y + 0.05, 344.0), PI * 0.5 - 0.05, Vector3(1.25, 1.0, 1.25), Vector3(4.8, 0.6, 2.4)],
		["res://assets/fishing/structure-platform-dock-small.glb", Vector3(mx - 29.2, sw_y + 0.06, 343.6), 0.14, Vector3(1.22, 1.05, 1.22), Vector3(3.6, 0.8, 3.6)],
		["res://assets/fishing/platform-planks.glb", Vector3(mx + 12.2, sw_y + 0.08, 340.0), -PI * 0.5, Vector3(1.25, 1.0, 1.25), Vector3(5.0, 0.6, 2.6)],
		["res://assets/fishing/structure-platform-dock.glb", Vector3(mx + 18.0, sw_y + 0.08, 340.0), -PI * 0.5 - 0.03, Vector3(1.20, 1.05, 1.20), Vector3(6.2, 0.8, 2.8)],
		["res://assets/fishing/structure-platform-dock-small.glb", Vector3(mx + 24.4, sw_y + 0.05, 340.6), -0.18, Vector3(1.22, 1.05, 1.22), Vector3(3.6, 0.8, 3.6)],
		["res://assets/fishing/platform.glb", Vector3(mx + 30.2, sw_y - 0.02, 341.4), 0.25, Vector3(1.20, 1.0, 1.20), Vector3(3.2, 0.6, 3.2)],
	]
	for dk in docks:
		var dk_pos: Vector3 = dk[1]
		var dk_n := _place_ruin_wall(warren_root, String(dk[0]), dk_pos, float(dk[2]), dk[3] as Vector3, Vector2.ZERO, null, true, dk[4] as Vector3)
		_harmonize_prop_mats(dk_n, swamp_timber_color, 0.94, 0.04)

	var west_boat := _place_ruin_wall(warren_root, "res://assets/fishing/boat-row-small.glb", Vector3(mx - 33.4, sw_y - 0.10, 344.6), 0.68, Vector3.ONE * 1.18, Vector2(0.08, -0.10), null, true, Vector3(2.8, 0.9, 1.4))
	_harmonize_prop_mats(west_boat, swamp_timber_color, 0.92, 0.05)
	var wcrate := _place_ruin_wall(warren_root, "res://assets/fishing/crate.glb", Vector3(mx - 29.2, sw_y + 0.28, 342.8), 0.45, Vector3.ONE * 1.05, Vector2.ZERO, null, false)
	_harmonize_prop_mats(wcrate, Color(0.32, 0.28, 0.24), 0.95, 0.03)
	var wbar := _place_ruin_wall(warren_root, "res://assets/fishing/barrel.glb", Vector3(mx - 30.2, sw_y + 0.28, 343.6), -0.30, Vector3.ONE * 1.05, Vector2.ZERO, null, false)
	_harmonize_prop_mats(wbar, Color(0.32, 0.28, 0.24), 0.95, 0.03)

	var east_boat := _place_ruin_wall(warren_root, "res://assets/fishing/boat-row-large.glb", Vector3(mx + 35.8, sw_y - 0.14, 342.8), -1.05, Vector3.ONE * 1.18, Vector2(-0.12, 0.14), null, true, Vector3(3.4, 1.0, 1.6))
	_harmonize_prop_mats(east_boat, swamp_timber_color, 0.92, 0.05)
	var ebott := _place_ruin_wall(warren_root, "res://assets/fishing/crate-bottles.glb", Vector3(mx + 25.0, sw_y + 0.26, 340.8), 0.72, Vector3.ONE * 1.08, Vector2.ZERO, null, false)
	_harmonize_prop_mats(ebott, Color(0.32, 0.28, 0.24), 0.95, 0.03)
	_vault_post_torch(warren_root, Vector3(mx - 28.4, sw_y + 0.12, 341.8), 0.4, 811, 1.85, 13.5)
	_vault_post_torch(warren_root, Vector3(mx + 24.4, sw_y + 0.12, 339.2), -0.5, 812, 1.85, 13.5)

	# 4. Outer Half-Submerged Swamp Ruins Outposts (SW Watch-Gate, Far West Reservoir, SE Shrine Cloister, Far East Precinct)
	for sw_r: Array in [
		# SW Flooded Gatehouse & Submerged Wall Wing (mx - 42..55, bz = 344..364)
		["wall_archedwindow_open.gltf.glb", mx - 44.5, 353.0, 0.35, Vector3(1.38, 1.42, 1.38), Vector2(0.05, -0.06)],
		["wall_broken.gltf.glb", mx - 49.5, 348.0, 0.92, Vector3(1.36, 1.26, 1.36), Vector2(-0.04, 0.05)],
		["wall_cracked.gltf.glb", mx - 41.0, 358.5, -0.25, Vector3(1.36, 1.24, 1.36), Vector2.ZERO],
		# Far West Submerged Reservoir Colonnade (mx - 50..58, bz = 294..324)
		["wall_arched.gltf.glb", mx - 51.0, 304.0, PI * 0.5 + 0.14, Vector3(1.38, 1.38, 1.38), Vector2(0.04, 0.04)],
		["wall_broken.gltf.glb", mx - 52.5, 314.0, PI * 0.5 - 0.18, Vector3(1.36, 1.22, 1.36), Vector2(-0.05, 0.03)],
		["wall_corner.gltf.glb", mx - 48.0, 294.5, 0.32, Vector3(1.36, 1.28, 1.36), Vector2.ZERO],
		# SE Flooded Shrine Cloister (mx + 42..56, bz = 344..364)
		["wall_archedwindow_gated.gltf.glb", mx + 44.5, 351.0, -0.42, Vector3(1.38, 1.42, 1.38), Vector2(-0.05, 0.06)],
		["wall_broken.gltf.glb", mx + 49.5, 345.5, -1.05, Vector3(1.36, 1.24, 1.36), Vector2(0.04, -0.04)],
		["wall_cracked.gltf.glb", mx + 40.5, 357.5, 0.28, Vector3(1.36, 1.28, 1.36), Vector2.ZERO],
		# Far East Flooded Abbey Outer Wall (mx + 48..58, bz = 294..326)
		["wall_arched.gltf.glb", mx + 50.5, 305.0, -PI * 0.5 - 0.12, Vector3(1.38, 1.38, 1.38), Vector2(-0.04, -0.04)],
		["wall_broken.gltf.glb", mx + 51.5, 315.5, -PI * 0.5 + 0.22, Vector3(1.36, 1.20, 1.36), Vector2(0.05, -0.03)],
		["wall_corner.gltf.glb", mx + 47.5, 294.0, -0.38, Vector3(1.38, 1.30, 1.38), Vector2.ZERO],
	]:
		var srx := float(sw_r[1])
		var srz := float(sw_r[2])
		var sry := minf(float(sample_rw_h.call(srx, srz)), sw_y - 0.15) - 0.25
		_place_ruin_wall(warren_root, String(sw_r[0]), Vector3(srx, sry, srz), float(sw_r[3]), sw_r[4] as Vector3, sw_r[5] as Vector2, _vault_wall_mat, true, Vector3(5.4, 4.9, 1.3))

	for sw_p: Array in [
		[mx - 42.5, 349.5, 1.95, Vector2(0.06, -0.09)],
		[mx - 47.0, 309.0, 1.90, Vector2(-0.05, 0.08)],
		[mx + 43.0, 347.5, 1.95, Vector2(-0.07, 0.10)],
		[mx + 46.5, 310.0, 1.85, Vector2(0.04, -0.07)],
	]:
		var spx := float(sw_p[0])
		var spz := float(sw_p[1])
		var spy := minf(float(sample_rw_h.call(spx, spz)), sw_y - 0.10) - 0.20
		_place_ruin_wall(warren_root, "pillar_decorated.gltf.glb", Vector3(spx, spy, spz), spx * 0.3, Vector3.ONE * float(sw_p[2]), sw_p[3] as Vector2, _vault_trim_mat, true, Vector3(1.7, 5.5, 1.7))

	# Draped vines across sunken outer masonry
	for sv_w: Array in [
		["Prop_Vine2.gltf", mx - 44.5, 353.0, 0.35],
		["Prop_Vine1.gltf", mx - 51.0, 304.0, PI * 0.5],
		["Prop_Vine4.gltf", mx + 44.5, 351.0, -0.42],
		["Prop_Vine2.gltf", mx + 50.5, 305.0, -PI * 0.5],
	]:
		var vx := float(sv_w[1])
		var vz := float(sv_w[2])
		var vy_w := minf(float(sample_rw_h.call(vx, vz)), sw_y - 0.15) + 2.45
		_place_nature_scene(warren_root, "res://assets/village/" + String(sv_w[0]), Vector3(vx, vy_w, vz), float(sv_w[3]), 1.35)

	# 5. Half-Flooded Bog Hummock Trees (Gnarled DeadTree snags + Spreading Broadleaf CommonTrees)
	var bog_trees: Array[Array] = [
		["res://assets/nature_extra/DeadTree_1.gltf", mx - 44.0, 333.0, 2.35],
		["res://assets/nature_extra/DeadTree_1.gltf", mx + 39.0, 332.0, 2.45],
		["res://assets/nature_extra/DeadTree_1.gltf", mx - 54.0, 336.0, 2.50],
		["res://assets/nature_extra/DeadTree_1.gltf", mx + 54.0, 334.0, 2.40],
		["res://assets/nature_extra/DeadTree_1.gltf", mx - 32.0, 368.0, 2.25],
		["res://assets/nature_extra/DeadTree_1.gltf", mx + 33.0, 366.0, 2.30],
		["res://assets/nature_extra/DeadTree_1.gltf", mx - 57.0, 290.0, 2.40],
		["res://assets/nature_extra/DeadTree_1.gltf", mx + 57.0, 289.0, 2.40],
		["res://assets/nature_extra/DeadTree_1.gltf", mx - 16.0, 368.0, 2.10],
		["res://assets/nature_extra/DeadTree_1.gltf", mx + 17.0, 366.0, 2.15],
		["res://assets/nature/CommonTree_1.gltf", mx - 49.0, 366.0, 1.35],
		["res://assets/nature/CommonTree_2.gltf", mx + 51.0, 364.0, 1.40],
		["res://assets/nature/CommonTree_1.gltf", mx - 58.0, 316.0, 1.45],
		["res://assets/nature/CommonTree_2.gltf", mx + 59.0, 318.0, 1.40],
		["res://assets/nature/CommonTree_1.gltf", mx - 24.0, 376.0, 1.28],
		["res://assets/nature/CommonTree_2.gltf", mx + 25.0, 374.0, 1.32],
	]
	for bt in bog_trees:
		var btx := float(bt[1])
		var btz := float(bt[2])
		var bty := float(sample_rw_h.call(btx, btz))
		var b_tr := _place_nature_scene(warren_root, String(bt[0]), Vector3(btx, bty - 0.18, btz), btx * 0.43 + btz * 0.29, float(bt[3]))
		if b_tr != null:
			_add_box_body(warren_root, Vector3(btx, bty + 2.2, btz), Vector3(1.1, 4.6, 1.1), LAYER_OBSTACLES)

	# 6. Procedural Swamp Aquatic & Shoreline Ecology (Lily Pads, Lotuses, Cattail Reeds, Ferns, Mushrooms)
	var sw_rng := RandomNumberGenerator.new()
	sw_rng.seed = 41771
	var lily_xfs: Array[Transform3D] = []
	var lotus_xfs: Array[Transform3D] = []
	var reed_xfs: Array[Transform3D] = []
	var head_xfs: Array[Transform3D] = []
	var bog_fern_xfs: Array[Transform3D] = []
	var bog_plant_xfs: Array[Transform3D] = []
	var bog_mush_xfs: Array[Transform3D] = []

	for li in range(380):
		var lx := mx + sw_rng.randf_range(-68.0, 68.0)
		var lz := sw_rng.randf_range(287.0, 396.0)
		if absf(lx - mx) < 9.5:
			continue
		var lh := float(sample_rw_h.call(lx, lz))
		# Open swamp water surface -> floating lily pad clusters & pale blossoms
		if lh < sw_y - 0.08 and lily_xfs.size() < 190:
			var pads := sw_rng.randi_range(2, 4)
			for p_k in range(pads):
				var ox := lx + sw_rng.randf_range(-1.1, 1.1)
				var oz := lz + sw_rng.randf_range(-1.1, 1.1)
				if float(sample_rw_h.call(ox, oz)) < sw_y - 0.05:
					var pscl := sw_rng.randf_range(0.32, 0.62)
					var pb := Basis.from_euler(Vector3(0.0, sw_rng.randf() * TAU, 0.0)).scaled(Vector3(pscl, 1.0, pscl * sw_rng.randf_range(0.88, 1.12)))
					lily_xfs.append(Transform3D(pb, Vector3(ox, sw_y + 0.018, oz)))
					if p_k == 0 and sw_rng.randf() < 0.24 and lotus_xfs.size() < 34:
						var fl_s := pscl * 0.42
						lotus_xfs.append(Transform3D(Basis.from_euler(Vector3(0.0, sw_rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * fl_s), Vector3(ox + 0.04, sw_y + 0.032, oz - 0.04)))
		# Shallow mud banks & marsh hummocks -> tall cattail reeds, ferns & marsh mushrooms
		elif lh >= sw_y - 0.46 and lh <= sw_y + 0.28:
			if reed_xfs.size() < 340:
				var stalks := sw_rng.randi_range(3, 5)
				for sk in range(stalks):
					var rx := lx + sw_rng.randf_range(-0.7, 0.7)
					var rz := lz + sw_rng.randf_range(-0.7, 0.7)
					var ry := float(sample_rw_h.call(rx, rz))
					var rh := sw_rng.randf_range(1.15, 2.05)
					var yaw := sw_rng.randf() * TAU
					var tilt_x := sw_rng.randf_range(-0.14, 0.14)
					var tilt_z := sw_rng.randf_range(-0.14, 0.14)
					var rb := Basis.from_euler(Vector3(tilt_x, yaw, tilt_z))
					reed_xfs.append(Transform3D(rb.scaled(Vector3(1.0, rh, 1.0)), Vector3(rx, ry - 0.08, rz)))
					if sk % 2 == 0 and head_xfs.size() < 150:
						var tip_local := rb * Vector3(0.0, rh * 0.76, 0.0)
						head_xfs.append(Transform3D(rb.scaled(Vector3(1.0, clampf(rh * 0.65, 0.85, 1.25), 1.0)), Vector3(rx, ry - 0.08, rz) + tip_local))
			if lh > sw_y - 0.04 and bog_fern_xfs.size() < 56:
				bog_fern_xfs.append(Transform3D(Basis.from_euler(Vector3(0.0, sw_rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * sw_rng.randf_range(1.25, 1.75)), Vector3(lx, lh - 0.04, lz)))
			elif lh > sw_y + 0.02 and bog_plant_xfs.size() < 38 and sw_rng.randf() < 0.45:
				bog_plant_xfs.append(Transform3D(Basis.from_euler(Vector3(0.0, sw_rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * sw_rng.randf_range(1.15, 1.55)), Vector3(lx, lh - 0.04, lz)))
			if lh > sw_y and bog_mush_xfs.size() < 28 and sw_rng.randf() < 0.25:
				bog_mush_xfs.append(Transform3D(Basis.from_euler(Vector3(0.0, sw_rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * sw_rng.randf_range(1.2, 1.65)), Vector3(lx + 0.2, lh, lz - 0.2)))

	var lily_mat := StandardMaterial3D.new()
	lily_mat.albedo_color = Color(0.16, 0.38, 0.14)
	lily_mat.roughness = 0.84
	lily_mat.metallic = 0.0
	lily_mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	lily_mat.metallic_specular = 0.05
	lily_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spawn_batched_multimesh(warren_root, "RatSwampLilyPads", _build_lily_pad_mesh(), lily_mat, lily_xfs, false)

	var lotus_mat := StandardMaterial3D.new()
	lotus_mat.albedo_color = Color(0.84, 0.78, 0.72)
	lotus_mat.roughness = 0.80
	lotus_mat.metallic = 0.0
	lotus_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spawn_batched_multimesh(warren_root, "RatSwampLotuses", _build_lotus_mesh(), lotus_mat, lotus_xfs, false)

	var stalk_mesh := CylinderMesh.new()
	stalk_mesh.top_radius = 0.018
	stalk_mesh.bottom_radius = 0.042
	stalk_mesh.height = 1.0
	stalk_mesh.radial_segments = 5
	var stalk_mat := StandardMaterial3D.new()
	stalk_mat.albedo_color = Color(0.20, 0.34, 0.12)
	stalk_mat.roughness = 0.88
	stalk_mat.metallic_specular = 0.04
	_spawn_batched_multimesh(warren_root, "RatSwampCattailStalks", stalk_mesh, stalk_mat, reed_xfs, true, Vector3(0.0, 0.5, 0.0))

	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.048
	head_mesh.bottom_radius = 0.052
	head_mesh.height = 0.26
	head_mesh.radial_segments = 6
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.24, 0.14, 0.07)
	head_mat.roughness = 0.96
	head_mat.metallic_specular = 0.01
	_spawn_batched_multimesh(warren_root, "RatSwampCattailHeads", head_mesh, head_mat, head_xfs, true)

	if not bog_fern_xfs.is_empty():
		CavePropFX.spawn_gltf_batch(warren_root, "RatSwampFerns", "res://assets/nature/Fern_1.gltf", bog_fern_xfs)
	if not bog_plant_xfs.is_empty():
		CavePropFX.spawn_gltf_batch(warren_root, "RatSwampPlants", "res://assets/nature/Plant_1.gltf", bog_plant_xfs)
	if not bog_mush_xfs.is_empty():
		CavePropFX.spawn_gltf_batch(warren_root, "RatSwampMushrooms", "res://assets/nature/Mushroom_Common.gltf", bog_mush_xfs)


func _spawn_batched_multimesh(parent: Node3D, node_name: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D], cast_shad: bool, local_offset: Vector3 = Vector3.ZERO) -> void:
	if xforms.is_empty() or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	var off_xf := Transform3D(Basis.IDENTITY, local_offset)
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i] * off_xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shad else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


func _build_lily_pad_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 14
	var gap := 0.42
	for i in range(segs):
		var a0 := gap + (TAU - gap * 2.0) * (float(i) / float(segs))
		var a1 := gap + (TAU - gap * 2.0) * (float(i + 1) / float(segs))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0.0, 0.0, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a0), 0.015, sin(a0)))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a1), 0.015, sin(a1)))
	return st.commit()


func _build_lotus_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petals := 6
	for i in range(petals):
		var ang := TAU * float(i) / float(petals)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.28
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0.0, 0.0, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(dir * 0.55 + side + Vector3(0.0, 0.22, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(dir * 0.55 - side + Vector3(0.0, 0.22, 0.0))
	return st.commit()


# ==============================================================================
# 4. CONTINENT ROADSIDE WAYSTONE LANTERNS & ANCIENT MILESTONES
# ==============================================================================

func _build_world_waystones(waystones_region: Node = null) -> void:
	var road_root := Node3D.new()
	road_root.name = "WorldWaystones"
	add_child(road_root)

	# Anchored along the terrain shader's continent dirt trails to connect landmarks visually!
	var waystones: Array[Array] = []
	if waystones_region != null and waystones_region.has_method("get_waystone_markers"):
		var markers: Array = waystones_region.call("get_waystone_markers")
		for m: Dictionary in markers:
			waystones.append([m["xz"], float(m["yaw"]), "Waystone"])
	if waystones.is_empty():
		waystones = [
			[Vector2(-84.0, 99.0), 0.72, "BasinSouthFork"],
			[Vector2(-108.0, 154.0), 0.65, "CentralTrailShrine"],
			[Vector2(209.0, 193.0), 0.58, "RatTrailApproaching"],
			[Vector2(468.0, 442.0), -0.35, "RatWarrenFork"],
			[Vector2(-326.0, 398.0), 0.68, "WebwoodEdgeCairn"],
			[Vector2(-528.0, 306.0), -0.15, "WesternMoorShrine"],
			[Vector2(-751.0, 346.0), 0.20, "CryptRoadLantern"],
			[Vector2(147.0, -112.0), -0.82, "WolfTrailFord"],
			[Vector2(163.0, -146.0), -0.65, "WolfCragThreshold"],
		]
	var fern_xfs: Array[Transform3D] = []
	for wi in range(waystones.size()):
		var wz: Vector2 = WorldLandmarks.project_off_world_road(waystones[wi][0] as Vector2, 7.6)
		var wy := _sample_h(wz.x, wz.y)
		if wy < 7.0 or wy > 110.0:
			continue
		var yaw := float(waystones[wi][1])
		# Weathered stone pillar + mossy side boulder + flickering iron flame lantern (strictly on roadside shoulder)
		var p_pos := Vector3(wz.x, wy - 0.12, wz.y)
		var wp := _place_piece(road_root, "pillar_decorated.gltf.glb", p_pos, yaw, Vector3(1.25, 1.35, 1.25))
		if wp != null:
			_apply_mat_recursive(wp, _speleothem_mat)
		_add_box_body(road_root, Vector3(wz.x, wy + 1.55, wz.y), Vector3(1.5, 3.3, 1.5), LAYER_OBSTACLES)
		_place_piece(road_root, "torch_mounted.gltf.glb", Vector3(wz.x, wy + 2.75, wz.y) + Vector3(0.0, 0.0, 0.56).rotated(Vector3.UP, yaw), yaw, Vector3.ONE * 1.55)
		_fire_seed_counter += 1
		var flame_p := Vector3(wz.x, wy + 3.32, wz.y) + Vector3(0.0, 0.0, 0.92).rotated(Vector3.UP, yaw)
		CavePropFX.attach_torch_fire(road_root, flame_p, _fire_seed_counter, 0.56)
		_add_flicker_light(road_root, flame_p + Vector3(0.0, 0.35, 0.0), Color(1.0, 0.68, 0.28), 1.9, 13.5)

		var rock_cand_a := wz + Vector2(cos(yaw + 1.4), sin(yaw + 1.4)) * 1.45
		var rock_cand_b := wz - Vector2(cos(yaw + 1.4), sin(yaw + 1.4)) * 1.45
		var rock_xz := rock_cand_a if WorldLandmarks.min_dist_to_world_road(rock_cand_a.x, rock_cand_a.y) >= WorldLandmarks.min_dist_to_world_road(rock_cand_b.x, rock_cand_b.y) else rock_cand_b
		var rx := rock_xz.x
		var rz := rock_xz.y
		CavePropFX.spawn_fractured_boulder(road_root, Vector3(rx, _sample_h(rx, rz) + 0.18, rz), Vector3(0.75, 0.55, 0.68), _granite_shader_mat, 500 + wi, false)

		for fi in range(2):
			var fang := yaw + float(fi) * 2.2 - 0.8
			var fx := wz.x + cos(fang) * 1.55
			var fz := wz.y + sin(fang) * 1.55
			if WorldLandmarks.min_dist_to_world_road(fx, fz) >= 5.6:
				fern_xfs.append(Transform3D(Basis.from_euler(Vector3(0.0, fang, 0.0)).scaled(Vector3.ONE * 1.15), Vector3(fx, _sample_h(fx, fz) - 0.04, fz)))

	if not fern_xfs.is_empty():
		CavePropFX.spawn_gltf_batch(road_root, "WaystoneFerns", "res://assets/nature/Fern_1.gltf", fern_xfs)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time_acc += delta
	for fl in _flicker_lights:
		var l := fl["light"] as OmniLight3D
		if l != null:
			var ph := float(fl["phase"])
			l.light_energy = float(fl["base"]) * (1.0 + 0.09 * sin(_time_acc * 6.8 + ph) + 0.05 * cos(_time_acc * 12.3 + ph * 1.4))

	if _warren_interior == null:
		return
	if _slime_ref == null or not is_instance_valid(_slime_ref):
		_slime_ref = get_tree().get_first_node_in_group("player_slime") as Node3D
	if _slime_ref == null:
		return
	var d2 := Vector2(_slime_ref.global_position.x - WorldLandmarks.RAT_WARREN_MOUTH.x, _slime_ref.global_position.z - (252.0 + WorldLandmarks.RAT_WARREN_OFFSET.y)).length_squared()
	var far := d2 > 22500.0
	if far != _warren_culled:
		_warren_culled = far
		_warren_interior.visible = not far
