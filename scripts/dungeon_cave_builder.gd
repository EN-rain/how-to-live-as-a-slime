class_name DungeonCaveBuilder
extends Node3D
## Sunken Necropolis Stairwell & Gothic Skeleton Crypt interior.
## Zero artificial surface hill mound: a carved ashlar staircase plaza drops cleanly
## from meadow ground (y=26.0, z=326) through a vaulted gothic archway (z=304)
## deep into the baked karst crypt chambers (y=8.0 Atrium/Cistern/Ossuary, y=4.0 Sanctum),
## textured with world-space triplanar chiseled limestone/slate (crypt_masonry.gdshader).

const WorldLandmarks := preload("res://scripts/world_landmarks.gd")
const CavePropFX := preload("res://scripts/cave_prop_fx.gd")

const LAYER_TERRAIN := 1
const LAYER_OBSTACLES := 4

const CX := WorldLandmarks.SKEL_CAVE_MOUTH.x
const EXT_Y := WorldLandmarks.SKEL_FORECOURT_Y
const UPPER_Y := WorldLandmarks.SKEL_UPPER_Y
const SANCTUM_Y := WorldLandmarks.SKEL_SANCTUM_Y

const RES_BASE := "res://assets/dungeon/"
const SKEL_BAKED_PREFIX := "res://assets/dungeon/skel_cave"
const NATURE_BASE := "res://assets/nature/"

var _scene_cache: Dictionary = {}
var _crypt_rock_mat: ShaderMaterial = null
var _surface_moss_rock_mat: ShaderMaterial = null
var _crypt_floor_mat: ShaderMaterial = null
var _crypt_ashlar_mat: ShaderMaterial = null
var _crypt_trim_mat: ShaderMaterial = null
var _crypt_iron_mat: Material = null
var _crypt_foliage_mat: StandardMaterial3D = null
var _water_cistern_mat: ShaderMaterial = null
var _water_fall_mat: ShaderMaterial = null
var _water_abyss_mat: ShaderMaterial = null
var _stone_props_mat: StandardMaterial3D = null
var _timed_spikes: Array[Dictionary] = []
var _abyss_time: float = 0.0
var crypt_region: Node = null
var _spike_cycle_speed: float = 1.0


func _ready() -> void:
	name = "SkeletonDungeonCave"
	add_to_group("skeleton_dungeon_cave")
	if crypt_region != null and crypt_region.has_method("get_profile"):
		var prof = crypt_region.call("get_profile")
		if prof != null:
			_spike_cycle_speed = float(prof.get("spike_cycle_speed"))
	_build_crypt()
	set_process(true)


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


func _floor_y(z: float) -> float:
	return WorldLandmarks.sample_skeleton_cave_floor(CX, z).w


func _sample_parent_terrain_y(wx: float, wz: float) -> float:
	var p := get_parent()
	if p != null and p.has_method(&"sample_height"):
		return float(p.call(&"sample_height", wx, wz))
	return EXT_Y


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
		"abyss_pos": Vector3(CX, SANCTUM_Y, 224.0),
		"abyss_col": Color(0.22, 0.11, 0.38),
		"abyss_radius": 22.0,
	})

	_surface_moss_rock_mat = CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.46, 0.44, 0.39),
		"cool_tint": Color(0.28, 0.31, 0.35),
		"moss_tint": Color(0.18, 0.36, 0.13),
		"triplanar_scale": 0.24,
		"bump": 1.10,
		"meadow_blend": 0.0,
	})

	var masonry_sh := load("res://shaders/crypt_masonry.gdshader") as Shader

	_crypt_floor_mat = ShaderMaterial.new()
	_crypt_floor_mat.shader = masonry_sh
	_crypt_floor_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_crypt_floor_mat.set_shader_parameter(&"surface_mode", 0.0)
	_crypt_floor_mat.set_shader_parameter(&"block_scale", 0.72)
	_crypt_floor_mat.set_shader_parameter(&"bump_strength", 1.25)
	_crypt_floor_mat.set_shader_parameter(&"moss_strength", 0.44)
	_crypt_floor_mat.set_shader_parameter(&"base_roughness", 0.87)
	_crypt_floor_mat.set_shader_parameter(&"stone_dark", Color(0.11, 0.12, 0.15))
	_crypt_floor_mat.set_shader_parameter(&"stone_mid", Color(0.25, 0.26, 0.28))
	_crypt_floor_mat.set_shader_parameter(&"stone_warm", Color(0.34, 0.31, 0.27))
	_crypt_floor_mat.set_shader_parameter(&"mortar_tint", Color(0.03, 0.035, 0.04))
	_crypt_floor_mat.set_shader_parameter(&"moss_tint", Color(0.18, 0.39, 0.13))
	_crypt_floor_mat.set_shader_parameter(&"moss_sky_y", 22.5)
	_crypt_floor_mat.set_shader_parameter(&"abyss_glow_pos", Vector3(CX, SANCTUM_Y, 224.0))
	_crypt_floor_mat.set_shader_parameter(&"abyss_glow_col", Color(0.22, 0.11, 0.40))
	_crypt_floor_mat.set_shader_parameter(&"abyss_glow_radius", 22.0)

	_crypt_ashlar_mat = ShaderMaterial.new()
	_crypt_ashlar_mat.shader = masonry_sh
	_crypt_ashlar_mat.set_shader_parameter(&"rock_detail_tex", rock_tex)
	_crypt_ashlar_mat.set_shader_parameter(&"surface_mode", 1.0)
	_crypt_ashlar_mat.set_shader_parameter(&"block_scale", 0.62)
	_crypt_ashlar_mat.set_shader_parameter(&"bump_strength", 1.32)
	_crypt_ashlar_mat.set_shader_parameter(&"moss_strength", 0.50)
	_crypt_ashlar_mat.set_shader_parameter(&"base_roughness", 0.89)
	_crypt_ashlar_mat.set_shader_parameter(&"stone_dark", Color(0.12, 0.13, 0.15))
	_crypt_ashlar_mat.set_shader_parameter(&"stone_mid", Color(0.27, 0.28, 0.29))
	_crypt_ashlar_mat.set_shader_parameter(&"stone_warm", Color(0.37, 0.33, 0.29))
	_crypt_ashlar_mat.set_shader_parameter(&"mortar_tint", Color(0.035, 0.038, 0.045))
	_crypt_ashlar_mat.set_shader_parameter(&"moss_tint", Color(0.19, 0.42, 0.14))
	_crypt_ashlar_mat.set_shader_parameter(&"moss_sky_y", 21.5)
	_crypt_ashlar_mat.set_shader_parameter(&"abyss_glow_pos", Vector3(CX, SANCTUM_Y, 224.0))
	_crypt_ashlar_mat.set_shader_parameter(&"abyss_glow_col", Color(0.22, 0.11, 0.40))
	_crypt_ashlar_mat.set_shader_parameter(&"abyss_glow_radius", 22.0)

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
	_crypt_trim_mat.set_shader_parameter(&"moss_sky_y", 22.0)
	_crypt_trim_mat.set_shader_parameter(&"abyss_glow_pos", Vector3(CX, SANCTUM_Y, 224.0))
	_crypt_trim_mat.set_shader_parameter(&"abyss_glow_col", Color(0.22, 0.11, 0.40))
	_crypt_trim_mat.set_shader_parameter(&"abyss_glow_radius", 22.0)

	# Blackened Forged Wrought Iron (crisp dark charcoal metal under both sun and torchlight, never pale grey)
	var iron_std := StandardMaterial3D.new()
	iron_std.albedo_color = Color(0.055, 0.058, 0.068)
	iron_std.metallic = 0.48
	iron_std.roughness = 0.46
	iron_std.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_crypt_iron_mat = iron_std

	_stone_props_mat = CavePropFX.make_diffuse_rock_mat(Color(0.56, 0.57, 0.60))

	_water_cistern_mat = CavePropFX.make_cave_water_mat(
		Color(0.04, 0.30, 0.28),
		Color(0.01, 0.06, 0.07),
		Color(0.50, 0.76, 0.70),
		false,
		Vector3(CX - 34.5, UPPER_Y - 0.35, 281.5),
		0.32
	)
	_water_fall_mat = CavePropFX.make_cave_water_mat(
		Color(0.14, 0.56, 0.50),
		Color(0.04, 0.18, 0.20),
		Color(0.76, 0.92, 0.88),
		true,
		Vector3(CX - 34.5, UPPER_Y - 0.35, 281.5),
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


func _build_crypt() -> void:
	_init_materials()

	# 1. Baked organic karst cavern & open-air sunken stairwell rock cut
	CavePropFX.mount_baked_cavern(self, SKEL_BAKED_PREFIX, _crypt_rock_mat, true)

	# 2. Exterior Necropolis Courtyard & Chiseled Sunken Staircase (y = 26 -> 8, z = 340 -> 298)
	_build_sunken_staircase_entrance()

	# 3. Atrium Vault & Sanctum Stairway (y = 8 -> 4, z = 298 -> 252)
	_build_atrium_hall()

	# 4. West Flooded Cistern Wing & 1.55m Iron Squeeze Portcullis (y = 8, water 7.65)
	_build_cistern_wing()

	# 5. East Ossuary Wing & Timed Spike Traps (y = 8)
	_build_ossuary_wing()

	# 6. Overlord Sanctum Cathedral, Abyssal Moats & Altar Dais (y = 4, water 3.65)
	_build_sanctum_cathedral()

	# 7. Interior Speleothems & Hanging Roots/Vines matching Crystal Cave fidelity
	_build_karst_speleothems_and_vines()


# ==============================================================================
# HELPERS: MESH PRIMITIVES, COLLIDERS & MATERIAL OVERRIDES
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
						dup.roughness = maxf(dup.roughness, 0.80)
						dup.metallic = minf(dup.metallic, 0.14)
						dup.albedo_color = dup.albedo_color * Color(0.68, 0.66, 0.62)
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


func _place_floor_grid(xmin: float, xmax: float, zmin: float, zmax: float, y: float, step: float = 4.0) -> void:
	var x := xmin
	var toggle := 0
	var mats: Array[Transform3D] = []
	while x <= xmax + 0.01:
		var z := zmin
		while z <= zmax + 0.01:
			var rel := "floor_tile_large_rocks.gltf.glb" if (toggle % 4 == 1) else "floor_tile_large.gltf.glb"
			_spawn_piece(rel, Vector3(x, y - 0.02, z), float((toggle % 4) * 90), 1.0, "none", _crypt_floor_mat)
			mats.append(Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
			toggle += 1
			z += step
		x += step


func _spawn_brazier(pos: Vector3, seed_idx: int, height_scale: float = 1.0, flame_scale: float = 0.62, light_energy: float = 2.6, light_range: float = 17.5, light_color: Color = Color(1.0, 0.56, 0.22)) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	# Carved basalt hexagonal pedestal + bronze/iron fire bowl
	var ped_h := 1.05 * height_scale
	var ped := CylinderMesh.new()
	ped.top_radius = 0.36
	ped.bottom_radius = 0.52
	ped.height = ped_h
	ped.radial_segments = 8
	var ped_mi := MeshInstance3D.new()
	ped_mi.mesh = ped
	ped_mi.material_override = _crypt_trim_mat
	ped_mi.position = Vector3(0.0, ped_h * 0.5, 0.0)
	root.add_child(ped_mi)

	var rim := CylinderMesh.new()
	rim.top_radius = 0.56
	rim.bottom_radius = 0.38
	rim.height = 0.28
	rim.radial_segments = 8
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


func _spawn_wall_torch(pos: Vector3, yaw_deg: float, seed_idx: int, light_energy: float = 2.0, light_range: float = 15.0) -> void:
	_spawn_piece("torch_mounted.gltf.glb", pos, yaw_deg, 1.32, "none", _crypt_iron_mat)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	CavePropFX.attach_torch_fire(self, pos + fwd * 0.42 + Vector3(0.0, 0.46, 0.0), seed_idx, 0.48)
	var pl := OmniLight3D.new()
	pl.position = pos + fwd * 0.65 + Vector3(0.0, 0.85, 0.0)
	pl.light_color = Color(1.0, 0.58, 0.24)
	pl.light_energy = light_energy
	pl.omni_range = light_range
	pl.omni_attenuation = 1.35
	pl.shadow_enabled = false
	add_child(pl)


func _spawn_stair_treads(z_top: float, z_bot: float, y_top: float, y_bot: float, width: float, num_steps: int, tread_mat: Material) -> void:
	var dz := (z_top - z_bot) / float(num_steps)
	var dy := (y_top - y_bot) / float(num_steps)
	for i in range(num_steps):
		var zc := z_top - (float(i) + 0.5) * dz
		var yt := y_top - (float(i) + 0.5) * dy
		var step_h := dy + 0.26
		# Subtle alternating bullnose overlap & hand-cut stone offset
		var x_jit := sin(float(i) * 2.13) * 0.05
		var d_jit := dz * (1.16 + 0.05 * cos(float(i) * 1.7))
		_box_mesh(self, Vector3(CX + x_jit, yt - step_h * 0.5 + 0.02, zc), Vector3(width, step_h, d_jit), tread_mat)


# ==============================================================================
# SUNKEN NECROPOLIS COURTYARD & DOWNWARD STONE STAIRCASE
# ==============================================================================

func _build_sunken_staircase_entrance() -> void:
	# 1. Framed Flagstone Forecourt & Processional Causeway (edges tucked into E/W stone curbing!)
	_box_solid(self, Vector3(CX, EXT_Y - 0.24, 330.6), Vector3(13.2, 0.50, 8.6), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "CourtyardApron")
	_box_solid(self, Vector3(CX, EXT_Y - 0.22, 335.6), Vector3(11.6, 0.42, 3.0), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "CourtyardStepThreshold")
	# Textured 4x4m ancient carved stone pavers across forecourt & broad approach causeway
	var causeway_tiles: Array[Array] = [
		[Vector2(CX - 3.6, 328.4), "floor_tile_large_rocks.gltf.glb", 0.0, 1.0],
		[Vector2(CX + 0.0, 328.4), "floor_tile_large.gltf.glb", 90.0, 1.0],
		[Vector2(CX + 3.6, 328.4), "floor_tile_large_rocks.gltf.glb", 180.0, 1.0],
		[Vector2(CX - 3.6, 332.2), "floor_tile_large.gltf.glb", 90.0, 1.0],
		[Vector2(CX + 0.0, 332.2), "floor_tile_large_rocks.gltf.glb", 0.0, 1.0],
		[Vector2(CX + 3.6, 332.2), "floor_tile_large.gltf.glb", 270.0, 1.0],
		[Vector2(CX - 2.4, 336.2), "floor_tile_large_rocks.gltf.glb", 90.0, 0.95],
		[Vector2(CX + 2.2, 336.3), "floor_tile_large.gltf.glb", 180.0, 0.95],
		[Vector2(CX - 1.8, 339.8), "floor_tile_large_rocks.gltf.glb", 14.0, 0.90],
		[Vector2(CX + 1.9, 340.0), "floor_dirt_large_rocky.gltf.glb", -11.0, 0.90],
		[Vector2(CX + 0.0, 343.2), "floor_dirt_large_rocky.gltf.glb", 6.0, 0.85],
	]
	for ct in causeway_tiles:
		var pxz: Vector2 = ct[0]
		var py := EXT_Y - 0.04 if pxz.y <= 334.8 else (_sample_parent_terrain_y(pxz.x, pxz.y) - 0.02)
		_spawn_piece(String(ct[1]), Vector3(pxz.x, py, pxz.y), float(ct[2]), float(ct[3]), "none", _crypt_floor_mat)

	# 2. Smooth Continuous Stairwell Ramp Collider (y=26.0 @ z=326 -> y=8.0 @ z=298)
	var dz_stair := 28.0
	var dy_stair := EXT_Y - UPPER_Y # 18.0m
	var ramp_len := sqrt(dz_stair * dz_stair + dy_stair * dy_stair) # ~33.29m
	var ramp_pitch_deg := rad_to_deg(atan2(dy_stair, dz_stair))     # +32.74 deg
	var mid_y := (EXT_Y + UPPER_Y) * 0.5
	var mid_z := (326.0 + 298.0) * 0.5
	var n_up := Vector3(0.0, cos(deg_to_rad(ramp_pitch_deg)), sin(deg_to_rad(ramp_pitch_deg)))
	var ramp_center := Vector3(CX, mid_y, mid_z) - n_up * 0.45
	_col_box(self, ramp_center, Vector3(9.4, 0.90, ramp_len + 0.6), LAYER_TERRAIN, Vector3(ramp_pitch_deg, 0.0, 0.0), "StairwellRampCol")
	_box_mesh(self, ramp_center - n_up * 0.32, Vector3(9.2, 0.85, ramp_len + 0.6), _crypt_trim_mat, Vector3(ramp_pitch_deg, 0.0, 0.0))

	# 44 individually articulated chiseled stone steps plunging downward!
	_spawn_stair_treads(326.0, 298.0, EXT_Y, UPPER_Y, 9.0, 44, _crypt_floor_mat)

	# 3. Massive Ashlar Retaining Trench Walls & 100% INTERCONNECTED Wrought-Iron Balustrade Circuit
	var fence_y := EXT_Y + 0.62
	var ew_z_piers: Array[float] = [326.80, 323.85, 320.90, 317.95, 315.00, 312.05, 309.10, 306.15, 303.20]
	for side_s: float in [-1.0, 1.0]:
		var wx := CX + side_s * 6.05
		var rail_x := CX + side_s * 5.20
		# Main vertical ashlar retaining wall rising flush into top coping
		_box_solid(self, Vector3(wx, 16.55, 315.4), Vector3(3.3, 20.1, 24.4), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "TrenchRetainingWall")
		# Stepped sloped stringer beam along the stair inner edge (flush with retaining wall)
		_box_mesh(self, Vector3(CX + side_s * 4.40, mid_y + 0.35, mid_z), Vector3(0.85, 1.25, ramp_len + 0.8), _crypt_trim_mat, Vector3(ramp_pitch_deg, 0.0, 0.0))
		# Top perimeter ashlar coping balustrade sealing the grass/cutout lip completely (covers x = CX +- 4.30..8.30)
		_box_solid(self, Vector3(CX + side_s * 6.30, EXT_Y + 0.26, 315.4), Vector3(4.00, 0.72, 25.0), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "TrenchCopingRim")

		# 6 Gothic Fluted Pilaster Buttresses descending inside the stairwell wall + iron torches!
		for pi in range(6):
			var pz := 324.2 - float(pi) * 3.85
			var py := _floor_y(pz)
			var bh := EXT_Y + 0.55 - (py - 0.8)
			_box_mesh(self, Vector3(CX + side_s * 4.45, (py - 0.8) + bh * 0.5, pz), Vector3(0.85, bh, 1.15), _crypt_trim_mat)
			_box_mesh(self, Vector3(CX + side_s * 4.45, EXT_Y + 0.72, pz), Vector3(1.08, 0.34, 1.38), _crypt_trim_mat)
			if pi % 2 == 0 or pi == 5:
				var yaw := 90.0 if side_s < 0.0 else -90.0
				_spawn_wall_torch(Vector3(CX + side_s * 4.05, py + 2.85, pz), yaw, 100 + pi * 2 + (0 if side_s < 0.0 else 1), 2.3, 18.0)

		# Continuous Stone Plinth Curb + Carved Bay Piers + Triple Continuous Forged Iron Horizontal Tie Rails (ZERO GAPS!)
		_box_solid(self, Vector3(rail_x, EXT_Y + 0.68, 315.0), Vector3(0.46, 0.28, 24.2), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "BalustradePlinthEW")
		for ry_off: float in [0.24, 0.90, 1.56]:
			_box_mesh(self, Vector3(rail_x, fence_y + ry_off, 315.0), Vector3(0.13, 0.09, 24.0), _crypt_iron_mat)
		for pzi in range(ew_z_piers.size()):
			var pz := ew_z_piers[pzi]
			var is_end := (pzi == 0 or pzi == ew_z_piers.size() - 1)
			var pw := 0.88 if is_end else 0.64
			var ph := 2.25 if is_end else 1.88
			_box_solid(self, Vector3(rail_x, EXT_Y + 0.56 + ph * 0.5, pz), Vector3(pw, ph, pw), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "FencePierEW")
			_box_mesh(self, Vector3(rail_x, EXT_Y + 0.56 + ph + 0.12, pz), Vector3(pw + 0.22, 0.24, pw + 0.22), _crypt_ashlar_mat)
			if pzi < ew_z_piers.size() - 1:
				var mid_bay_z := (pz + ew_z_piers[pzi + 1]) * 0.5
				_spawn_piece("res://assets/village/Prop_MetalFence_Ornament.gltf", Vector3(rail_x, fence_y, mid_bay_z), 90.0, Vector3(1.24, 0.62, 1.0), "wall", _crypt_iron_mat)
				# Extra solid forged iron vertical bars tying panel pickets seamlessly into continuous horizontal rails
				for bar_off: float in [-0.95, -0.48, 0.0, 0.48, 0.95]:
					_box_mesh(self, Vector3(rail_x, fence_y + 0.90, mid_bay_z + bar_off), Vector3(0.06, 1.38, 0.06), _crypt_iron_mat)

	# North Back coping + Interconnected Pier-and-Iron Balustrade (z = 303.2, x = CX - 5.20 .. CX + 5.20)
	_box_solid(self, Vector3(CX, EXT_Y + 0.36, 303.2), Vector3(14.8, 0.90, 2.2), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "NorthPitCoping")
	_box_solid(self, Vector3(CX, EXT_Y + 0.68, 303.2), Vector3(11.0, 0.28, 0.46), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "BalustradePlinthN")
	for ry_off: float in [0.24, 0.90, 1.56]:
		_box_mesh(self, Vector3(CX, fence_y + ry_off, 303.2), Vector3(10.8, 0.09, 0.13), _crypt_iron_mat)
	for npi in range(1, 4):
		var npx := CX - 5.20 + float(npi) * 2.60
		_box_solid(self, Vector3(npx, EXT_Y + 0.56 + 0.94, 303.2), Vector3(0.64, 1.88, 0.64), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "FencePierN")
		_box_mesh(self, Vector3(npx, EXT_Y + 0.56 + 1.98, 303.2), Vector3(0.86, 0.24, 0.86), _crypt_ashlar_mat)
	for nbi in range(4):
		var nbx := CX - 3.90 + float(nbi) * 2.60
		_spawn_piece("res://assets/village/Prop_MetalFence_Ornament.gltf", Vector3(nbx, fence_y, 303.2), 0.0, Vector3(1.12, 0.62, 1.0), "wall", _crypt_iron_mat)
		for bar_off: float in [-0.75, 0.0, 0.75]:
			_box_mesh(self, Vector3(nbx + bar_off, fence_y + 0.90, 303.2), Vector3(0.06, 1.38, 0.06), _crypt_iron_mat)

	# 4. Monumental Vaulted Gothic Portal Headwall at z = 304.2 (clear arch opening |x - CX| <= 4.35, y = 11.7..21.8!)
	var p_z := 304.2
	for side_s: float in [-1.0, 1.0]:
		_box_solid(self, Vector3(CX + side_s * 5.45, 19.2, p_z), Vector3(2.3, 15.8, 2.6), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "PortalJambTower")
		_spawn_piece("pillar_decorated.gltf.glb", Vector3(CX + side_s * 4.45, 11.6, p_z + 0.95), 0.0, 1.85, "none", _crypt_trim_mat)
		_spawn_piece("pillar_decorated.gltf.glb", Vector3(CX + side_s * 4.45, 15.8, p_z + 0.95), 0.0, 1.85, "none", _crypt_trim_mat)
	_box_solid(self, Vector3(CX, 24.4, p_z), Vector3(13.2, 5.2, 2.7), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "PortalHeaderSpandrel")
	for side_s: float in [-1.0, 1.0]:
		_box_mesh(self, Vector3(CX + side_s * 2.35, 22.15, p_z + 0.35), Vector3(4.6, 1.15, 2.1), _crypt_trim_mat, Vector3(0.0, 0.0, -side_s * 26.0))
	_box_mesh(self, Vector3(CX, 23.25, p_z + 0.95), Vector3(1.55, 2.35, 1.35), _crypt_trim_mat)
	_spawn_piece("sword_shield_gold.gltf.glb", Vector3(CX, 23.35, p_z + 1.62), 0.0, 1.55, "none", _crypt_trim_mat)

	for vi in range(-3, 4):
		var vx := CX + float(vi) * 1.95
		var vy := 25.8 - float(abs(vi) % 2) * 1.1
		_spawn_piece("res://assets/village/Prop_Vine2.gltf", Vector3(vx, vy, p_z + 1.15), 180.0, 1.45, "none", null)

	# 5. Grand Gatehouse Sanctuary Pillars, Interconnected Forecourt Iron Fencing & Wing Ruins
	for side_s: float in [-1.0, 1.0]:
		# Twin South-East/West Forecourt Gatehouse Obelisks flanking stair mouth (z = 327.0)
		_box_solid(self, Vector3(CX + side_s * 6.4, EXT_Y + 1.65, 327.0), Vector3(2.0, 3.3, 2.0), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "CourtyardObelisk")
		_spawn_brazier(Vector3(CX + side_s * 6.4, EXT_Y + 3.30, 327.0), 110 + (0 if side_s < 0.0 else 1), 0.72, 0.86, 3.4, 24.0)
		# Interconnect stair corner pier (x=CX+-5.2, z=326.8) directly into CourtyardObelisk (x=CX+-6.4, z=327.0)!
		_box_solid(self, Vector3(CX + side_s * 5.80, EXT_Y + 0.56, 326.88), Vector3(1.60, 0.56, 0.54), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "FrontReturnCurb")
		for ry_off: float in [0.24, 0.90, 1.56]:
			_box_mesh(self, Vector3(CX + side_s * 5.80, fence_y + ry_off, 326.88), Vector3(1.40, 0.09, 0.13), _crypt_iron_mat)
		for bar_x: float in [5.48, 5.80]:
			_box_mesh(self, Vector3(CX + side_s * bar_x, fence_y + 0.90, 326.88), Vector3(0.06, 1.38, 0.06), _crypt_iron_mat)

		# Connect CourtyardObelisk (z=327.0) south through MidPier (z=330.8) directly into OuterPlinth (z=334.6)!
		# Continuous stone forecourt curb + 2 bays of interconnected forged-iron fence panels + top/mid/bottom rails
		var fc_x := CX + side_s * 6.60
		_box_solid(self, Vector3(fc_x, EXT_Y + 0.14, 330.8), Vector3(0.68, 0.82, 8.2), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "ForecourtSideCurb")
		_box_solid(self, Vector3(fc_x, EXT_Y + 1.48, 330.8), Vector3(0.66, 1.92, 0.66), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "ForecourtMidPier")
		_box_mesh(self, Vector3(fc_x, EXT_Y + 2.54, 330.8), Vector3(0.88, 0.24, 0.88), _crypt_ashlar_mat)
		for ry_off: float in [0.24, 0.90, 1.56]:
			_box_mesh(self, Vector3(fc_x, fence_y + ry_off, 330.8), Vector3(0.13, 0.09, 7.6), _crypt_iron_mat)
		for fbz: float in [328.9, 332.7]:
			_spawn_piece("res://assets/village/Prop_MetalFence_Ornament.gltf", Vector3(fc_x, fence_y, fbz), 90.0, Vector3(1.36, 0.62, 1.0), "wall", _crypt_iron_mat)
			for bar_off: float in [-1.15, -0.58, 0.0, 0.58, 1.15]:
				_box_mesh(self, Vector3(fc_x, fence_y + 0.90, fbz + bar_off), Vector3(0.06, 1.38, 0.06), _crypt_iron_mat)

		# Lower portal guardian braziers perched on flat stone plinths flanking the archway
		var lp_y := _floor_y(306.8)
		_box_solid(self, Vector3(CX + side_s * 3.85, lp_y - 0.35, 306.8), Vector3(1.45, 0.90, 1.45), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "PortalGuardianPlinth")
		_spawn_brazier(Vector3(CX + side_s * 3.85, lp_y + 0.10, 306.8), 112 + (0 if side_s < 0.0 else 1), 0.95, 0.72, 2.9, 20.0)
		# Ruined Necropolis Wing Walls extending smoothly out from gatehouse piers into rock outcrops
		_spawn_piece("wall_cracked.gltf.glb", Vector3(CX + side_s * 9.0, EXT_Y - 0.20, 327.0), 0.0, Vector3(1.0, 0.65, 1.0), "wall", _crypt_ashlar_mat)
		_spawn_piece("wall_broken.gltf.glb", Vector3(CX + side_s * 12.6, EXT_Y - 0.32, 326.6), -side_s * 16.0, Vector3(1.0, 0.55, 1.0), "wall", _crypt_ashlar_mat)
		_spawn_piece("rubble_half.gltf.glb", Vector3(CX + side_s * 14.8, EXT_Y - 0.45, 325.0), -side_s * 36.0, Vector3(0.85, 0.55, 0.85), "wall", _crypt_ashlar_mat)
		# Outer Gatehouse Sentinel Braziers flanking the main south entry stairs (z = 334.6)
		var og_y := minf(EXT_Y - 0.15, _sample_parent_terrain_y(CX + side_s * 6.8, 334.6) - 0.25)
		_box_solid(self, Vector3(CX + side_s * 6.8, og_y + 1.25, 334.6), Vector3(1.65, 2.5, 1.65), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "OuterPlinth")
		_box_mesh(self, Vector3(CX + side_s * 6.8, og_y + 2.55, 334.6), Vector3(1.90, 0.28, 1.90), _crypt_trim_mat)
		_spawn_brazier(Vector3(CX + side_s * 6.8, og_y + 2.68, 334.6), 114 + (0 if side_s < 0.0 else 1), 0.62, 0.72, 2.9, 20.0)
		_spawn_piece("banner_shield_blue.gltf.glb", Vector3(CX + side_s * 6.8, og_y + 0.72, 333.65), -side_s * 14.0, 1.22, "none", null)

	_build_crypt_surroundings()


func _build_crypt_surroundings() -> void:
	# A. Natural Limestone Karst Bedrock Outcrops & Mossy Boulders (grass-blended like Crystal Cave!)
	var ridge_clusters: Array[Array] = [
		# West flank bedrock ridge stepping outward from retaining coping
		[Vector2(CX - 9.0, 322.5), Vector3(2.9, 1.40, 2.6), 301],
		[Vector2(CX - 11.4, 319.0), Vector3(3.4, 1.85, 3.2), 302],
		[Vector2(CX - 9.2, 314.5), Vector3(2.8, 1.55, 3.0), 303],
		[Vector2(CX - 11.8, 309.5), Vector3(3.6, 2.05, 3.4), 304],
		[Vector2(CX - 9.5, 304.2), Vector3(3.1, 1.85, 2.9), 305],
		# East flank bedrock ridge stepping outward
		[Vector2(CX + 9.0, 322.0), Vector3(2.8, 1.38, 2.7), 306],
		[Vector2(CX + 11.6, 318.0), Vector3(3.5, 1.92, 3.3), 307],
		[Vector2(CX + 9.4, 313.5), Vector3(2.9, 1.62, 2.8), 308],
		[Vector2(CX + 12.0, 308.5), Vector3(3.7, 2.15, 3.5), 309],
		[Vector2(CX + 9.6, 303.8), Vector3(3.0, 1.88, 2.9), 310],
		# North crest rock shelves behind North coping rail (creates rugged rocky hill backdrop!)
		[Vector2(CX - 6.0, 299.6), Vector3(3.6, 2.30, 2.9), 311],
		[Vector2(CX - 0.5, 299.0), Vector3(4.2, 2.60, 3.2), 312],
		[Vector2(CX + 5.8, 299.4), Vector3(3.5, 2.25, 2.8), 313],
		# Foreground flanking mossy boulder ledges hugging OuterPlinth & causeway threshold (zero bare grass seam!)
		[Vector2(CX - 9.2, 333.6), Vector3(2.5, 1.15, 2.4), 314],
		[Vector2(CX + 9.4, 333.4), Vector3(2.5, 1.18, 2.4), 315],
		[Vector2(CX - 8.4, 338.2), Vector3(2.3, 1.00, 2.0), 316],
		[Vector2(CX + 8.6, 338.0), Vector3(2.3, 1.02, 2.0), 317],
	]
	for rc in ridge_clusters:
		var cxz: Vector2 = rc[0]
		var rrad: Vector3 = rc[1]
		var cy := _sample_parent_terrain_y(cxz.x, cxz.y) + rrad.y * 0.14
		CavePropFX.spawn_fractured_boulder(self, Vector3(cxz.x, cy, cxz.y), rrad, _surface_moss_rock_mat, int(rc[2]), true)

	# Layered sculpted karst Rock_Medium outcrops framing forecourt approach & trench wings with grass-blended shader
	var rocky_ledges: Array[Array] = [
		[NATURE_BASE + "Rock_Medium_1.gltf", Vector2(CX - 11.8, 330.2), 28.0, 1.35],
		[NATURE_BASE + "Rock_Medium_2.gltf", Vector2(CX + 12.0, 329.8), -32.0, 1.35],
		[NATURE_BASE + "Rock_Medium_3.gltf", Vector2(CX - 6.8, 338.6), 44.0, 1.05],
		[NATURE_BASE + "Rock_Medium_1.gltf", Vector2(CX + 7.0, 338.4), -48.0, 1.05],
		[NATURE_BASE + "Rock_Medium_2.gltf", Vector2(CX - 5.0, 342.4), 18.0, 0.92],
		[NATURE_BASE + "Rock_Medium_3.gltf", Vector2(CX + 5.2, 342.2), -24.0, 0.92],
		[NATURE_BASE + "Rock_Medium_1.gltf", Vector2(CX - 14.5, 316.5), 72.0, 1.55],
		[NATURE_BASE + "Rock_Medium_2.gltf", Vector2(CX + 14.8, 316.0), -68.0, 1.55],
		[NATURE_BASE + "Rock_Medium_3.gltf", Vector2(CX - 11.0, 299.5), 112.0, 1.65],
		[NATURE_BASE + "Rock_Medium_1.gltf", Vector2(CX + 11.2, 299.5), -108.0, 1.65],
	]
	for rl in rocky_ledges:
		var rxz: Vector2 = rl[1]
		var ry := _sample_parent_terrain_y(rxz.x, rxz.y) - 0.30
		_spawn_piece(String(rl[0]), Vector3(rxz.x, ry, rxz.y), float(rl[2]), float(rl[3]), "wall", _surface_moss_rock_mat)

	# B. Deeply Grounded Cenotaph Tombs, Ruined Precinct Boundary Walls & Ivy Drapery
	var tomb_spots: Array[Array] = [
		[Vector2(CX - 14.2, 322.0), -14.0],
		[Vector2(CX + 14.4, 321.5), 16.0],
		[Vector2(CX - 14.8, 312.5), 9.0],
		[Vector2(CX + 15.0, 312.8), -11.0],
		[Vector2(CX - 15.2, 302.5), -22.0],
		[Vector2(CX + 15.5, 303.0), 20.0],
	]
	for ts in tomb_spots:
		var xz: Vector2 = ts[0]
		var ang := float(ts[1])
		var min_y := minf(
			minf(_sample_parent_terrain_y(xz.x - 1.0, xz.y - 1.2), _sample_parent_terrain_y(xz.x + 1.0, xz.y + 1.2)),
			minf(_sample_parent_terrain_y(xz.x - 1.0, xz.y + 1.2), _sample_parent_terrain_y(xz.x + 1.0, xz.y - 1.2))
		) - 0.45
		_box_solid(self, Vector3(xz.x, min_y + 0.55, xz.y), Vector3(1.45, 1.35, 2.4), _crypt_trim_mat, LAYER_OBSTACLES, Vector3(0.0, ang, 0.0), "CenotaphTomb")
		_box_mesh(self, Vector3(xz.x, min_y + 1.45, xz.y) + Vector3(0.0, 0.0, -0.85).rotated(Vector3.UP, deg_to_rad(ang)), Vector3(1.08, 1.55, 0.42), _crypt_ashlar_mat, Vector3(0.0, ang, 0.0))

	# Flanking graveyard perimeter ruins + snapped ancient columns (connects wing walls visually around tombs!)
	for side_s: float in [-1.0, 1.0]:
		var w1x := CX + side_s * 16.6
		var w1y := _sample_parent_terrain_y(w1x, 318.0) - 0.42
		_spawn_piece("wall_broken.gltf.glb", Vector3(w1x, w1y, 318.0), side_s * 76.0, Vector3(1.0, 0.50, 1.0), "wall", _crypt_ashlar_mat)
		_spawn_piece("res://assets/village/Prop_Vine2.gltf", Vector3(CX + side_s * 9.0, EXT_Y + 2.15, 327.3), 180.0, 1.25, "none", null)
		_spawn_piece("res://assets/village/Prop_Vine1.gltf", Vector3(CX + side_s * 12.2, EXT_Y + 1.55, 326.8), -side_s * 16.0, 1.15, "none", null)

	var ruin_cols: Array[Array] = [
		[Vector2(CX - 9.4, 331.4), 1.45, 0.0],
		[Vector2(CX + 9.6, 331.2), 1.65, 0.0],
		[Vector2(CX - 15.8, 329.5), 1.20, 12.0],
		[Vector2(CX + 16.0, 329.0), 1.35, -14.0],
	]
	for rcol in ruin_cols:
		var xz: Vector2 = rcol[0]
		var gy := _sample_parent_terrain_y(xz.x, xz.y) - 0.35
		_spawn_piece("column.gltf.glb", Vector3(xz.x, gy, xz.y), float(rcol[2]), float(rcol[1]), "wall", _crypt_ashlar_mat)

	# C. Haunted Crypt Grove (Pines, Common Trees & Gnarled Dead Trees framing crypt edges cleanly)
	var tree_ring: Array[Array] = [
		[NATURE_BASE + "Pine_1.gltf", Vector2(CX - 20.5, 324.0), 1.55, 18.0],
		[NATURE_BASE + "Pine_2.gltf", Vector2(CX + 21.0, 323.0), 1.60, -34.0],
		["res://assets/nature_extra/DeadTree_1.gltf", Vector2(CX - 17.5, 333.5), 1.35, 42.0],
		["res://assets/nature_extra/DeadTree_1.gltf", Vector2(CX + 18.0, 333.0), 1.42, -55.0],
		[NATURE_BASE + "CommonTree_1.gltf", Vector2(CX - 24.0, 311.0), 1.45, 88.0],
		[NATURE_BASE + "Pine_1.gltf", Vector2(CX + 23.5, 310.0), 1.70, 125.0],
		[NATURE_BASE + "Pine_2.gltf", Vector2(CX - 18.5, 297.5), 1.65, -75.0],
		[NATURE_BASE + "CommonTree_2.gltf", Vector2(CX - 8.5, 293.0), 1.50, 15.0],
		[NATURE_BASE + "Pine_1.gltf", Vector2(CX + 2.0, 291.5), 1.75, -110.0],
		[NATURE_BASE + "Pine_2.gltf", Vector2(CX + 12.5, 293.5), 1.62, 65.0],
		["res://assets/nature_extra/DeadTree_1.gltf", Vector2(CX - 13.5, 299.0), 1.50, -145.0],
		["res://assets/nature_extra/DeadTree_1.gltf", Vector2(CX + 15.0, 299.5), 1.40, 140.0],
		[NATURE_BASE + "Pine_1.gltf", Vector2(CX - 28.0, 300.0), 1.85, 50.0],
		[NATURE_BASE + "Pine_2.gltf", Vector2(CX + 27.5, 298.5), 1.80, -40.0],
		[NATURE_BASE + "Pine_1.gltf", Vector2(CX - 23.5, 339.5), 1.48, 75.0],
		[NATURE_BASE + "Pine_2.gltf", Vector2(CX + 24.0, 338.5), 1.52, -82.0],
	]
	for tr in tree_ring:
		var txz: Vector2 = tr[1]
		var ty := _sample_parent_terrain_y(txz.x, txz.y) - 0.35
		_spawn_piece(String(tr[0]), Vector3(txz.x, ty, txz.y), float(tr[3]), float(tr[2]), "wall", null)

	# D. Lush Dark-Green MultiMesh Undergrowth (Plant_1 Shrubs, Broad Ferns, Clovers & Tall Meadow Grass — ZERO red foliage!)
	var shrub_xf: Array[Transform3D] = []
	var tall_grass_xf: Array[Transform3D] = []
	var wispy_grass_xf: Array[Transform3D] = []
	var fern_xf: Array[Transform3D] = []
	var clover_xf: Array[Transform3D] = []

	for bi in range(44):
		var a := float(bi) * 0.618 * TAU
		var rad := 8.8 + fmod(float(bi) * 3.7, 13.5)
		var bx := CX + cos(a) * rad * 1.15
		var bz := 320.0 + sin(a) * rad * 1.08
		# Keep open causeway center and sunken trench clear
		if absf(bx - CX) < 6.4 and bz > 301.0 and bz < 344.0:
			continue
		var by := _sample_parent_terrain_y(bx, bz) - 0.08
		var bsc := 1.05 + fmod(float(bi) * 0.23, 0.75)
		var bxf := Transform3D(Basis.from_euler(Vector3(0.0, float(bi) * 1.37, 0.0)).scaled(Vector3(bsc, bsc, bsc)), Vector3(bx, by, bz))
		if bi % 3 == 0:
			fern_xf.append(bxf)
		else:
			shrub_xf.append(bxf)

	for gi in range(135):
		var ang := float(gi) * 0.618 * TAU
		var rad := 7.2 + fmod(float(gi) * 2.71, 18.5)
		var gx := CX + cos(ang) * rad * 1.18
		var gz := 320.5 + sin(ang) * rad * 1.10
		if absf(gx - CX) < 5.6 and gz > 302.0 and gz < 343.5:
			continue
		var gy := _sample_parent_terrain_y(gx, gz) - 0.05
		var sc := 0.95 + fmod(float(gi) * 0.31, 0.78)
		var xf := Transform3D(Basis.from_euler(Vector3(0.0, ang * 1.7, 0.0)).scaled(Vector3(sc, sc * 1.1, sc)), Vector3(gx, gy, gz))
		var mod_v := gi % 6
		if mod_v < 2:
			tall_grass_xf.append(xf)
		elif mod_v < 4:
			wispy_grass_xf.append(xf)
		elif mod_v == 4:
			fern_xf.append(xf)
		else:
			clover_xf.append(xf)

	CavePropFX.spawn_gltf_batch(self, "CryptShrubs", NATURE_BASE + "Plant_1.gltf", shrub_xf, null, false)
	CavePropFX.spawn_gltf_batch(self, "CryptTallGrass", NATURE_BASE + "Grass_Common_Tall.gltf", tall_grass_xf, null, false)
	CavePropFX.spawn_gltf_batch(self, "CryptWispyGrass", NATURE_BASE + "Grass_Wispy_Tall.gltf", wispy_grass_xf, null, false)
	CavePropFX.spawn_gltf_batch(self, "CryptFerns", NATURE_BASE + "Fern_1.gltf", fern_xf, null, false)
	CavePropFX.spawn_gltf_batch(self, "CryptClovers", NATURE_BASE + "Clover_1.gltf", clover_xf, null, false)


# ==============================================================================
# ATRIUM CRYPT HALL & STAIRWAY TO SANCTUM (y = 8.0 -> 4.0)
# ==============================================================================

func _build_atrium_hall() -> void:
	# Chiseled flagstone floor deck across Atrium (y = 8.0, x = CX-16..CX+16, z = 268..298)
	_box_solid(self, Vector3(CX, UPPER_Y - 0.45, 283.0), Vector3(32.5, 0.90, 30.8), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "AtriumFloorCol")
	_place_floor_grid(CX - 12.0, CX + 12.0, 270.0, 294.0, UPPER_Y, 4.0)

	# Gothic Atrium Colonnade Pillars + Buttressed Ribs (continuous floor-to-arch shaft, zero gap!)
	for side_s: float in [-1.0, 1.0]:
		var px := CX + side_s * 8.2
		for pz: float in [293.0, 283.5, 274.0]:
			_box_mesh(self, Vector3(px, UPPER_Y + 0.35, pz), Vector3(2.2, 0.70, 2.2), _crypt_trim_mat)
			# Solid continuous ashlar column shaft + stacked overlapping carved capitals
			_box_solid(self, Vector3(px, UPPER_Y + 4.85, pz), Vector3(1.15, 9.2, 1.15), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "AtriumPillarShaft")
			_spawn_piece("column.gltf.glb", Vector3(px, UPPER_Y + 0.65, pz), 0.0, 1.80, "none", _crypt_trim_mat)
			_spawn_piece("column.gltf.glb", Vector3(px, UPPER_Y + 3.65, pz), 0.0, 1.80, "none", _crypt_trim_mat)
			_spawn_piece("column.gltf.glb", Vector3(px, UPPER_Y + 6.65, pz), 0.0, 1.80, "none", _crypt_trim_mat)
			_spawn_piece("banner_patternA_red.gltf.glb", Vector3(px - side_s * 0.95, UPPER_Y + 3.2, pz), -90.0 if side_s > 0.0 else 90.0, 1.25, "none", null)
		# Overhead pointed arch ribs spanning between colonnades
		for pz: float in [293.0, 283.5, 274.0]:
			_box_mesh(self, Vector3(CX + side_s * 4.2, UPPER_Y + 9.6, pz), Vector3(9.4, 0.95, 1.15), _crypt_trim_mat, Vector3(0.0, 0.0, -side_s * 18.0))

	# 4 Atrium Lit Braziers illuminating column nave & central bone sarcophagus
	_spawn_brazier(Vector3(CX - 5.4, UPPER_Y, 290.5), 1, 1.0, 0.68, 3.0, 22.0)
	_spawn_brazier(Vector3(CX + 5.4, UPPER_Y, 290.5), 2, 1.0, 0.68, 3.0, 22.0)
	_spawn_brazier(Vector3(CX - 5.4, UPPER_Y, 276.5), 3, 1.0, 0.68, 3.0, 22.0)
	_spawn_brazier(Vector3(CX + 5.4, UPPER_Y, 276.5), 4, 1.0, 0.68, 3.0, 22.0)

	# Central Crypt Memorial Plinth & Relic Table
	_box_solid(self, Vector3(CX, UPPER_Y + 0.24, 283.5), Vector3(5.6, 0.48, 3.6), _crypt_trim_mat, LAYER_TERRAIN, Vector3.ZERO, "AtriumCenterPlinth")
	_spawn_piece("table_long_decorated_A.gltf.glb", Vector3(CX, UPPER_Y + 0.48, 283.5), 90.0, 1.15, "wall", null)
	_spawn_piece("candle_triple.gltf.glb", Vector3(CX, UPPER_Y + 1.46, 283.5), 20.0, 1.25, "none", null)
	_spawn_piece("rubble_half.gltf.glb", Vector3(CX - 12.6, UPPER_Y, 291.0), 40.0, 1.15, "wall", _crypt_ashlar_mat)
	_spawn_piece("rubble_large.gltf.glb", Vector3(CX + 12.6, UPPER_Y, 290.5), -35.0, 1.15, "wall", _crypt_ashlar_mat)

	# Stairway descending from Atrium (z = 268, y = 8.0) -> Sanctum (z = 252, y = 4.0)
	var dz_s := 16.0
	var dy_s := UPPER_Y - SANCTUM_Y # 4.0m
	var r_len := sqrt(dz_s * dz_s + dy_s * dy_s)
	var r_pitch := rad_to_deg(atan2(dy_s, dz_s)) # +14.04 deg
	var m_y := (UPPER_Y + SANCTUM_Y) * 0.5
	var m_z := (268.0 + 252.0) * 0.5
	var n_u := Vector3(0.0, cos(deg_to_rad(r_pitch)), sin(deg_to_rad(r_pitch)))
	_col_box(self, Vector3(CX, m_y, m_z) - n_u * 0.45, Vector3(11.0, 0.90, r_len + 0.6), LAYER_TERRAIN, Vector3(r_pitch, 0.0, 0.0), "SanctumStairRamp")
	_box_mesh(self, Vector3(CX, m_y, m_z) - n_u * 0.65, Vector3(10.6, 0.85, r_len + 0.6), _crypt_trim_mat, Vector3(r_pitch, 0.0, 0.0))
	_spawn_stair_treads(268.0, 252.0, UPPER_Y, SANCTUM_Y, 10.2, 18, _crypt_floor_mat)

	for side_s: float in [-1.0, 1.0]:
		_box_solid(self, Vector3(CX + side_s * 5.6, m_y + 0.55, m_z), Vector3(1.1, 1.8, r_len), _crypt_trim_mat, LAYER_OBSTACLES, Vector3(r_pitch, 0.0, 0.0), "SanctumStairBalustrade")
		_spawn_brazier(Vector3(CX + side_s * 6.0, UPPER_Y, 268.5), 5 + (0 if side_s < 0.0 else 1), 1.0, 0.70, 2.8, 19.0)


# ==============================================================================
# WEST FLOODED CISTERN WING & 1.55m IRON SQUEEZE PORTCULLIS (y = 8.0)
# ==============================================================================

func _build_cistern_wing() -> void:
	# South Cistern Causeway connecting Atrium (CX-15) -> Squeeze Gate (CX-34) -> Vault Chamber (CX-48)
	# Strictly keeps North basin (z=274.2..285.8) OPEN so CisternWaterPool (y=7.65) is genuinely sunken!
	_box_solid(self, Vector3(CX - 30.0, UPPER_Y - 0.45, 266.8), Vector3(34.0, 0.90, 14.8), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "CisternCausewayDeck")
	_box_solid(self, Vector3(CX - 43.0, UPPER_Y - 0.45, 280.0), Vector3(10.0, 0.90, 12.6), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "CisternWestLanding")
	_box_solid(self, Vector3(CX - 15.0, UPPER_Y - 0.45, 280.0), Vector3(6.2, 0.90, 12.6), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "CisternEastLanding")
	_box_solid(self, Vector3(CX - 28.0, UPPER_Y - 0.45, 288.0), Vector3(22.0, 0.90, 4.4), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "CisternNorthWallWalk")
	_place_floor_grid(CX - 42.0, CX - 16.0, 260.0, 272.0, UPPER_Y, 4.0)

	# Cistern recessed stone pool beds (y = 5.65) + reflective water sheet (y = 7.65)
	_box_solid(self, Vector3(CX - 28.0, UPPER_Y - 2.35, 280.0), Vector3(21.2, 0.55, 13.0), _crypt_trim_mat, LAYER_TERRAIN, Vector3.ZERO, "CisternPoolBed")
	for side_z: float in [274.0, 286.0]:
		_box_solid(self, Vector3(CX - 28.0, UPPER_Y - 0.55, side_z), Vector3(21.2, 2.2, 0.9), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "CisternPoolCurb")
	for side_x: float in [CX - 38.2, CX - 17.8]:
		_box_solid(self, Vector3(side_x, UPPER_Y - 0.55, 280.0), Vector3(0.9, 2.2, 12.5), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "CisternPoolEndCurb")

	var water_q := PlaneMesh.new()
	water_q.size = Vector2(20.4, 12.6)
	water_q.subdivide_width = 24
	water_q.subdivide_depth = 16
	var w_mi := MeshInstance3D.new()
	w_mi.name = "CisternWaterPool"
	w_mi.mesh = water_q
	w_mi.material_override = _water_cistern_mat
	w_mi.position = Vector3(CX - 28.0, UPPER_Y - 0.35, 280.0) # y = 7.65
	w_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w_mi)

	# Subterranean waterfall pouring from upper limestone fissure down into West Cistern!
	var wf_q := PlaneMesh.new()
	wf_q.size = Vector2(3.6, 7.6)
	wf_q.subdivide_width = 8
	wf_q.subdivide_depth = 18
	var wf_mi := MeshInstance3D.new()
	wf_mi.name = "CisternWaterfall"
	wf_mi.mesh = wf_q
	wf_mi.material_override = _water_fall_mat
	wf_mi.position = Vector3(CX - 34.5, UPPER_Y + 3.45, 283.2)
	wf_mi.rotation_degrees = Vector3(84.0, 0.0, 0.0)
	wf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wf_mi)

	# 1.55m SQUEEZE GATE (Portcullis raised 1.55m above y=8.0 causeway at x=CX-34, z=263.5)
	var sg_x := CX - 34.0 # -854.0
	var sg_z := 263.5
	# Causeway floor slab under gate (extra smooth & solid)
	_box_solid(self, Vector3(sg_x, UPPER_Y - 0.40, sg_z), Vector3(14.0, 0.80, 9.0), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "SqueezeCauseway")

	# Heavy Gothic ashlar arch framing + Forged Iron Portcullis visual
	for side_z: float in [-4.0, 4.0]:
		_box_solid(self, Vector3(sg_x, UPPER_Y + 3.2, sg_z + side_z), Vector3(2.2, 6.8, 2.2), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "SqueezeGatePier")
	_box_mesh(self, Vector3(sg_x, UPPER_Y + 6.4, sg_z), Vector3(2.4, 1.4, 9.2), _crypt_trim_mat)
	# Forged iron portcullis raised to exact 1.55m bottom clearance!
	_spawn_piece("wall_gated.gltf.glb", Vector3(sg_x, UPPER_Y + 1.55, sg_z), 90.0, Vector3(1.5, 1.35, 1.4), "none", _crypt_iron_mat)
	# Strict 1.55m vertical aperture collider across gateway (height=5.0, center=8.0+1.55+2.5=12.05 -> bottom=9.55!)
	_col_box(self, Vector3(sg_x, UPPER_Y + 1.55 + 2.50, sg_z), Vector3(1.35, 5.00, 7.6), LAYER_OBSTACLES, Vector3.ZERO, "SqueezePortcullisCol")
	# Side blocking bulkheads so full-size slimes cannot walk around north/south flanks of the squeeze gate
	_box_solid(self, Vector3(sg_x, UPPER_Y + 3.2, sg_z - 7.8), Vector3(2.4, 7.0, 5.8), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "SqueezeNorthWingWall")
	_box_solid(self, Vector3(sg_x, UPPER_Y + 3.2, sg_z + 7.2), Vector3(2.4, 7.0, 4.6), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "SqueezeSouthWingWall")

	_spawn_brazier(Vector3(sg_x + 3.4, UPPER_Y, sg_z - 2.6), 7, 0.9, 0.58, 2.5, 17.5, Color(0.55, 0.95, 0.85))
	_spawn_brazier(Vector3(sg_x - 3.4, UPPER_Y, sg_z - 2.6), 8, 0.9, 0.58, 2.5, 17.5, Color(0.55, 0.95, 0.85))
	# Hidden cistern treasure vault west of squeeze gate
	_spawn_piece("chest_gold.gltf.glb" if ResourceLoader.exists(RES_BASE + "chest_gold.gltf.glb") else "chest_gold.glb", Vector3(CX - 43.0, UPPER_Y, 263.5), 90.0, 1.35, "wall", null)
	_spawn_piece("barrel_large_decorated.gltf.glb", Vector3(CX - 42.0, UPPER_Y, 267.0), 25.0, 1.20, "wall", null)
	_spawn_piece("crates_stacked.gltf.glb", Vector3(CX - 41.5, UPPER_Y, 260.4), -15.0, 1.15, "wall", null)


# ==============================================================================
# EAST OSSUARY WING & TIMED SPIKE TRAPS (y = 8.0)
# ==============================================================================

func _build_ossuary_wing() -> void:
	_box_solid(self, Vector3(CX + 26.0, UPPER_Y - 0.45, 274.5), Vector3(28.0, 0.90, 26.0), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "OssuaryFloorDeck")
	_place_floor_grid(CX + 16.0, CX + 36.0, 264.0, 286.0, UPPER_Y, 4.0)

	# East Ossuary sarcophagi plinths, arched niches & weathered crypt shelving
	for ox: float in [CX + 20.0, CX + 28.0, CX + 35.5]:
		_spawn_piece("column.gltf.glb", Vector3(ox, UPPER_Y, 264.5), 0.0, 1.65, "wall", _crypt_trim_mat)
		_spawn_piece("column.gltf.glb", Vector3(ox, UPPER_Y, 284.5), 0.0, 1.65, "wall", _crypt_trim_mat)

	# Timed Mechanical Floor Spike Traps along main East Ossuary lane
	for ti in range(2):
		var tx := CX + 24.0 + float(ti) * 6.0
		var tz := 270.0
		_spawn_piece("floor_tile_big_grate.gltf.glb", Vector3(tx, UPPER_Y + 0.01, tz), 0.0, 1.05, "none", _crypt_iron_mat)
		var spikes := _spawn_piece("floor_tile_big_spikes.glb", Vector3(tx, UPPER_Y - 0.34, tz), 0.0, 1.0, "none", _crypt_iron_mat)
		if spikes != null:
			_timed_spikes.append({"node": spikes, "base_y": UPPER_Y - 0.34, "phase": float(ti) * 1.45})

	# Bone alcoves & supply stashes
	_spawn_piece("wall_shelves.gltf.glb", Vector3(CX + 37.5, UPPER_Y, 274.0), -90.0, 1.35, "wall", _crypt_ashlar_mat)
	_spawn_piece("chest.glb", Vector3(CX + 34.5, UPPER_Y, 279.0), -110.0, 1.25, "wall", null)
	_spawn_piece("keg_decorated.gltf.glb", Vector3(CX + 22.0, UPPER_Y, 281.5), 15.0, 1.25, "wall", null)
	_spawn_piece("candle_triple.gltf.glb", Vector3(CX + 22.0, UPPER_Y + 1.15, 281.5), 0.0, 1.35, "none", null)
	_spawn_brazier(Vector3(CX + 19.0, UPPER_Y, 270.0), 9, 0.95, 0.65, 2.7, 19.0)
	_spawn_brazier(Vector3(CX + 33.5, UPPER_Y, 274.0), 10, 0.95, 0.65, 2.7, 19.0)


# ==============================================================================
# OVERLORD SANCTUM CATHEDRAL & ABYSSAL MOAT (y = 4.0)
# ==============================================================================

func _build_sanctum_cathedral() -> void:
	# Central Sanctum Cathedral Nave Deck (width = 21.0m, x = CX-10.5..CX+10.5 -> strictly clear of flanking moats!)
	_box_solid(self, Vector3(CX, SANCTUM_Y - 0.45, 232.0), Vector3(21.0, 0.90, 41.0), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "SanctumFloorDeck")
	# North Apse backing floor behind dais
	_box_solid(self, Vector3(CX, SANCTUM_Y - 0.45, 212.0), Vector3(36.0, 0.90, 6.0), _crypt_floor_mat, LAYER_TERRAIN, Vector3.ZERO, "SanctumApseBack")
	_place_floor_grid(CX - 8.0, CX + 8.0, 214.0, 250.0, SANCTUM_Y, 4.0)

	# Flanking Sunken Abyssal Water Moats along x = CX +- 15.8 (water y = 3.65, solid stone canal bed y = 2.05)
	for side_s: float in [-1.0, 1.0]:
		var mx := CX + side_s * 15.8
		_box_solid(self, Vector3(mx, SANCTUM_Y - 2.15, 232.0), Vector3(11.4, 0.50, 38.0), _crypt_trim_mat, LAYER_TERRAIN, Vector3.ZERO, "SanctumMoatBed")
		_box_solid(self, Vector3(CX + side_s * 10.35, SANCTUM_Y - 0.45, 232.0), Vector3(1.15, 2.25, 38.0), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "SanctumMoatCurb")
		_box_solid(self, Vector3(CX + side_s * 21.2, SANCTUM_Y + 0.65, 232.0), Vector3(1.8, 5.4, 38.5), _crypt_ashlar_mat, LAYER_OBSTACLES, Vector3.ZERO, "SanctumMoatOuterWall")
		var mw := PlaneMesh.new()
		mw.size = Vector2(10.6, 37.0)
		mw.subdivide_width = 12
		mw.subdivide_depth = 28
		var mw_mi := MeshInstance3D.new()
		mw_mi.mesh = mw
		mw_mi.material_override = _water_abyss_mat
		mw_mi.position = Vector3(mx, SANCTUM_Y - 0.35, 232.0) # y = 3.65
		mw_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mw_mi)

		# Monumental Gothic Cathedral Colonnade running down Sanctum Nave (solid floor-to-arch columns!)
		for pz: float in [248.0, 238.0, 228.0, 218.0]:
			var px := CX + side_s * 8.6
			_box_mesh(self, Vector3(px, SANCTUM_Y + 0.38, pz), Vector3(2.3, 0.76, 2.3), _crypt_trim_mat)
			_box_solid(self, Vector3(px, SANCTUM_Y + 5.65, pz), Vector3(1.22, 10.8, 1.22), _crypt_trim_mat, LAYER_OBSTACLES, Vector3.ZERO, "SanctumPillarCore")
			_spawn_piece("pillar_decorated.gltf.glb", Vector3(px, SANCTUM_Y + 0.68, pz), 0.0, 1.95, "none", _crypt_trim_mat)
			_spawn_piece("pillar_decorated.gltf.glb", Vector3(px, SANCTUM_Y + 4.10, pz), 0.0, 1.95, "none", _crypt_trim_mat)
			_spawn_piece("pillar_decorated.gltf.glb", Vector3(px, SANCTUM_Y + 7.55, pz), 0.0, 1.95, "none", _crypt_trim_mat)
			_box_mesh(self, Vector3(CX + side_s * 4.5, SANCTUM_Y + 11.4, pz), Vector3(9.8, 1.05, 1.25), _crypt_trim_mat, Vector3(0.0, 0.0, -side_s * 20.0))

	# Overlord Altar Dais at North Sanctuary Apse (CX, y=4.0..4.56, z=216.0)
	_box_solid(self, Vector3(CX, SANCTUM_Y + 0.14, 216.0), Vector3(13.2, 0.28, 8.8), _crypt_trim_mat, LAYER_TERRAIN, Vector3.ZERO, "SanctumDaisLower")
	_box_solid(self, Vector3(CX, SANCTUM_Y + 0.42, 215.2), Vector3(9.2, 0.28, 6.0), _crypt_ashlar_mat, LAYER_TERRAIN, Vector3.ZERO, "SanctumDaisUpper")
	_spawn_piece("table_long_decorated_A.gltf.glb", Vector3(CX, SANCTUM_Y + 0.56, 214.8), 0.0, 1.35, "wall", _crypt_trim_mat)
	_spawn_piece("chest_gold.glb", Vector3(CX, SANCTUM_Y + 1.54, 214.8), 0.0, 1.10, "none", null)
	_spawn_piece("sword_shield_gold.gltf.glb", Vector3(CX, SANCTUM_Y + 4.4, 212.2), 0.0, 1.85, "none", _crypt_trim_mat)

	for side_s: float in [-1.0, 1.0]:
		_spawn_piece("banner_shield_blue.gltf.glb", Vector3(CX + side_s * 5.2, SANCTUM_Y + 0.56, 213.4), -side_s * 18.0, 1.45, "none", null)
		_spawn_brazier(Vector3(CX + side_s * 4.6, SANCTUM_Y + 0.28, 217.5), 20 + (0 if side_s < 0.0 else 1), 1.10, 0.78, 3.0, 22.0, Color(0.68, 0.38, 0.96))
		_spawn_brazier(Vector3(CX + side_s * 6.8, SANCTUM_Y, 228.0), 21 + (0 if side_s < 0.0 else 1), 1.05, 0.72, 3.2, 24.0, Color(1.0, 0.54, 0.20))
		_spawn_brazier(Vector3(CX + side_s * 6.8, SANCTUM_Y, 238.0), 22 + (0 if side_s < 0.0 else 1), 1.05, 0.72, 3.2, 24.0, Color(1.0, 0.54, 0.20))
		_spawn_brazier(Vector3(CX + side_s * 6.8, SANCTUM_Y, 247.5), 24 + (0 if side_s < 0.0 else 1), 1.05, 0.72, 3.2, 24.0, Color(1.0, 0.54, 0.20))

	# Balanced necrotic violet key light at the Overlord Dais (contrasted by warm fire along the nave!)
	var boss_pl := OmniLight3D.new()
	boss_pl.position = Vector3(CX, SANCTUM_Y + 3.8, 214.8)
	boss_pl.light_color = Color(0.50, 0.26, 0.88)
	boss_pl.light_energy = 2.4
	boss_pl.omni_range = 20.0
	boss_pl.omni_attenuation = 1.35
	boss_pl.shadow_enabled = false
	add_child(boss_pl)


# ==============================================================================
# KARST SPELEOTHEMS & HANGING VINES
# ==============================================================================

func _build_karst_speleothems_and_vines() -> void:
	var spel_specs: Array[Dictionary] = [
		# Atrium ceiling limestone stalactites anchored cleanly into arched vault rock
		{"pos": Vector3(CX - 12.0, UPPER_Y + 11.4, 290.0), "len": 3.4, "rad": 0.42, "seed": 11.0, "ceiling": true},
		{"pos": Vector3(CX + 12.2, UPPER_Y + 11.4, 289.0), "len": 3.8, "rad": 0.46, "seed": 12.0, "ceiling": true},
		{"pos": Vector3(CX - 13.0, UPPER_Y + 11.2, 274.5), "len": 3.2, "rad": 0.38, "seed": 13.0, "ceiling": true},
		{"pos": Vector3(CX + 13.0, UPPER_Y + 11.2, 275.0), "len": 3.6, "rad": 0.44, "seed": 14.0, "ceiling": true},
		# Cistern wet stalactites
		{"pos": Vector3(CX - 26.0, UPPER_Y + 9.8, 283.0), "len": 3.8, "rad": 0.46, "seed": 21.0, "ceiling": true},
		{"pos": Vector3(CX - 34.0, UPPER_Y + 9.9, 280.0), "len": 4.2, "rad": 0.52, "seed": 22.0, "ceiling": true},
		{"pos": Vector3(CX - 43.0, UPPER_Y + 9.2, 268.0), "len": 3.5, "rad": 0.40, "seed": 23.0, "ceiling": true},
		# Sanctum cathedral ceiling stalactites (vault roof ~ 18.8 center, 15.8 over moats) + moat stalagmites
		{"pos": Vector3(CX - 13.5, SANCTUM_Y + 14.8, 240.0), "len": 4.4, "rad": 0.54, "seed": 31.0, "ceiling": true},
		{"pos": Vector3(CX + 13.5, SANCTUM_Y + 14.8, 239.0), "len": 4.6, "rad": 0.52, "seed": 32.0, "ceiling": true},
		{"pos": Vector3(CX - 14.0, SANCTUM_Y + 14.6, 224.0), "len": 4.1, "rad": 0.48, "seed": 33.0, "ceiling": true},
		{"pos": Vector3(CX + 14.0, SANCTUM_Y + 14.6, 223.0), "len": 4.3, "rad": 0.50, "seed": 34.0, "ceiling": true},
		{"pos": Vector3(CX - 18.5, SANCTUM_Y - 1.8, 236.0), "len": 4.2, "rad": 0.62, "seed": 41.0, "ceiling": false, "collider": false},
		{"pos": Vector3(CX + 18.5, SANCTUM_Y - 1.8, 234.0), "len": 4.5, "rad": 0.64, "seed": 42.0, "ceiling": false, "collider": false},
	]
	CavePropFX.spawn_speleothem_cluster(self, spel_specs, _stone_props_mat)

	var vine_pts: Array[Dictionary] = [
		# Creeping ivy & root clusters at the vaulted portal entrance & Atrium upper arch
		{"pos": Vector3(CX - 3.6, 22.2, 304.8), "len": 3.2, "width": 1.15, "rot": 0.4},
		{"pos": Vector3(CX + 3.6, 22.4, 304.6), "len": 3.5, "width": 1.20, "rot": 1.9},
		{"pos": Vector3(CX - 11.2, UPPER_Y + 10.8, 286.0), "len": 4.0, "width": 1.05, "rot": 0.8},
		{"pos": Vector3(CX + 11.4, UPPER_Y + 10.8, 282.0), "len": 3.8, "width": 1.10, "rot": 2.3},
		{"pos": Vector3(CX - 28.0, UPPER_Y + 9.8, 281.5), "len": 4.4, "width": 1.25, "rot": 1.2},
		{"pos": Vector3(CX - 12.5, SANCTUM_Y + 14.4, 240.0), "len": 4.5, "width": 1.20, "rot": 0.6},
		{"pos": Vector3(CX + 12.5, SANCTUM_Y + 14.4, 226.0), "len": 4.2, "width": 1.15, "rot": 2.6},
	]
	CavePropFX.spawn_vine_batch(self, vine_pts)
