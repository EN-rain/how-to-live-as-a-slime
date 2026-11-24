@tool
class_name CaveSystem
extends Node3D
## Runtime loader and atmosphere/lighting/set-dressing controller for the baked SDF World Cave.
## Geometry and ConcavePolygonShape3D colliders are baked offline in the sandbox by tools/bake_cave.gd.

const CAVE_MESH_PATH := "res://terrain/cave/cave_mesh.res"
const CAVE_FLOOR_SHAPE_PATH := "res://terrain/cave/cave_floor_shape.res"
const CAVE_WALL_SHAPE_PATH := "res://terrain/cave/cave_wall_shape.res"
const CAVE_PROPS_CACHE_PATH := "res://terrain/cave/cave_props_cache.dat"
const CAVE_SHELL_CHUNKS_PATH := "user://cache/cave_shell_chunks.res"
const CAVE_WATER_MESHES_PATH := "user://cache/cave_water_meshes.res"
const DOOR_WALL_MESH_PATH := "res://terrain/cave/door_wall_mesh.res"
const DOOR_MONOLITH_MESH_PATH := "user://cache/door_monolith_mesh.res"
const CRYSTAL_INTERIOR_TEX_PATH := "res://terrain/cave/crystal_interior_tex.res"
const FIRE_NOISE_TEX_PATH := "res://terrain/cave/fire_noise_tex.res"
const FIRE_FLIPBOOK_TEX_PATH := "res://terrain/cave/fire_flipbook_tex.res"

const GEOFENCE_OVERWORLD_H := 56.5

@export var greybox_mode: bool = false

@export_group("Inspector Configs")
@export var bake_config: CaveBakeConfig
@export var scatter_config: CaveScatterConfig
@export var water_config: CaveWaterConfig
@export var layout_data: CaveLayoutData

@export_group("Landmarks & Gameplay")
@export_range(1.0, 25.0, 0.5) var geode_volume_bonus: float = 8.0
@export_range(5.0, 60.0, 1.0) var door_awaken_distance: float = 28.0
@export_range(0.0, 1.0, 0.02) var door_idle_glow: float = 0.18

@export_group("Editor Actions")
@export_tool_button("Export CaveOrigin -> cave_layout.tres") var btn_export_layout := _editor_export_layout
@export_tool_button("Rebuild Cave Preview") var btn_rebuild_cave := _editor_rebuild_preview

static var _shared_sdf: CaveSDF = null
static var _cached_props_data: Dictionary = {}
static var _cached_pebble_mesh: Mesh = null
static var _cached_speleothem_mesh: Mesh = null
static var _cached_crystal_stone_mesh: Mesh = null
static var _cached_crystal_shards_mesh: Mesh = null
static var _cached_abyssal_stone_mesh: ArrayMesh = null
static var _cached_water_meshes: Dictionary = {}
static var _cached_wf_ceil_y: float = 34.0
static var _crystal_striation_tex: ImageTexture = null
static var _crystal_interior_tex: ImageTexture = null
static var _fire_flipbook_tex: ImageTexture = null
static var _fire_noise_tex: ImageTexture = null
static var _cached_door_wall_mesh: ArrayMesh = null
static var _cached_door_monolith_mesh: ArrayMesh = null


static func _save_cached_res(res: Resource, path: String) -> void:
	if res == null:
		return
	var dir_abs := ProjectSettings.globalize_path(path.get_base_dir())
	if not DirAccess.dir_exists_absolute(dir_abs):
		if path.begins_with("user://"):
			DirAccess.make_dir_recursive_absolute(dir_abs)
		else:
			return
	ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)

var _pending_crystal_props: Array[Dictionary] = []
var _crystal_mat_cache := {}

var _cached_rock_mat: ShaderMaterial = null
var _grass_shader_mat: ShaderMaterial = null
var _flora_grass_node: Node3D = null
var _cave_shell_chunks: Array[MeshInstance3D] = []
var _cave_shell_shadow_proxy: MeshInstance3D = null
var _zoned_mmis: Array = [[], [], [], [], []]
var _zone_vis_state: Array[bool] = [true, true, true, true, true]
var _lake_water_node: Node3D = null
var _pool_water_node: Node3D = null
var _stream_water_node: Node3D = null
var _waterfall_node: Node3D = null
var _cave_boulder_shapes: Array[Shape3D] = []
var _slime_ref: Node3D = null
var _pool_water_mat: ShaderMaterial = null
var _lake_water_mat: ShaderMaterial = null
var _surface_sea_level: float = 0.0
static var _active_sea_level: float = 0.0
static var _active_water_config: CaveWaterConfig = null
var _stream_water_mat: ShaderMaterial = null
var _ocean_water_mat: ShaderMaterial = null

var _geode_reward_node: Node3D = null
var _geode_reward_mesh: Node3D = null
var _geode_reward_area: Area3D = null
var _geode_reward_collected: bool = false
var _geode_spin_t: float = 0.0
var _geode_orb_satellites: Array[Node3D] = []
var _door_anim_t: float = 0.0
var _fire_flicker_t: float = 0.0
var _door_awaken_val: float = 0.18
var _door_astrolabe_outer: Node3D = null
var _door_astrolabe_inner: Node3D = null
var _door_relief_mat: ShaderMaterial = null
const SN_SLIME_POS := &"slime_pos"
const SN_SLIME_RADIUS := &"slime_radius"
const SN_SLIME_VEL := &"slime_vel"
const SN_SLIME_SUBMERSION := &"slime_submersion"
const SN_ACTIVE_WAKE_COUNT := &"active_wake_count"
const SN_WAKE_POINTS := &"wake_points"
const SN_AWAKEN_AMOUNT := &"awaken_amount"

var _torch_flame_mats: Array[ShaderMaterial] = []
var _torch_card_mats: Array[ShaderMaterial] = []
var _torch_haze_mats: Array[ShaderMaterial] = []
var _door_haze_meshes: Array[MeshInstance3D] = []
var _door_particles: Array[GPUParticles3D] = []
var _door_vfx_active: bool = true
var _last_pushed_awaken: float = -1.0
var _vault_door_omni: OmniLight3D = null
var _vault_door_omni_base_pos: Vector3 = Vector3.ZERO
var _reverb_bus_idx: int = -1

var _wake_points: Array[Vector4] = []
var _wake_head: int = 0
var _last_wake_pos := Vector3(9999.0, -9999.0, 9999.0)
var _wake_emit_timer := 0.0
var _water_ripple_submersion := 0.0
var _water_ripple_pos := Vector3(9999.0, -9999.0, 9999.0)
var _water_ripple_rad := 1.6
var _water_uniforms_dirty := true

# Zone & frustum culling node refs
var _cave_shell: MeshInstance3D = null
var _lighting_rig: Node3D = null
var _skylight_spot: SpotLight3D = null
var _accent_lights: Array[OmniLight3D] = []
var _water_holder: Node3D = null
var _shards_holder: Node3D = null
var _abyssal_holder: Node3D = null
var _crystal_stones_node: Node3D = null
var _abyssal_base_node: MeshInstance3D = null
var _pebbles_node: Node3D = null
var _speleothems_node: Node3D = null
var _flora_node: Node3D = null
var _beams_node: Node3D = null
var _door_node: Node3D = null
var _pedestal_node: MeshInstance3D = null
var _boulders_node: Node3D = null

var _ow_terrain: Node3D = null
var _ow_grass: Node3D = null
var _ow_wispy: Node3D = null
var _ow_trees: Node3D = null
var _ow_rocks: Node3D = null
var _ow_veg: Node3D = null
var _ow_water: Node3D = null
var _ow_village: Node3D = null
var _ow_sun: DirectionalLight3D = null
var _zone_cull_mode: int = -1 # -1 uninit, 0 full/transitional, 1 far outdoors, 2 deep underground
var _last_cull_cam := Vector3(1e9, 1e9, 1e9)


func _ready() -> void:
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root == self:
		if get_node_or_null("BakedCaveMesh") == null and ResourceLoader.exists(CAVE_MESH_PATH):
			var mi := MeshInstance3D.new()
			mi.name = "BakedCaveMesh"
			mi.mesh = ResourceLoader.load(CAVE_MESH_PATH) as Mesh
			mi.material_override = _get_cave_rock_material()
			add_child(mi)


static func get_sdf() -> CaveSDF:
	if _shared_sdf == null:
		_shared_sdf = CaveSDF.new(1337)
	return _shared_sdf


# ==============================================================================
# STATIC TERRAIN & MOTOR INTEGRATION QUERIES
# ==============================================================================

static func apply_overworld_mountain_and_plaza(x: float, z: float, base_land_h: float, _terrain_noise: FastNoiseLite) -> float:
	if x < -440.0 or x > 170.0 or z < -410.0 or z > 120.0:
		return base_land_h
	var cl := CaveLayout.to_local(Vector3(x, 0.0, z))
	if cl.x < -310.0 or cl.x > 175.0 or cl.z < -45.0 or cl.z > 310.0:
		return base_land_h
	return CaveSDF.eval_karst_hill_height(cl.x, cl.z, base_land_h)


static func is_quad_in_portal_cutout(v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3) -> bool:
	return CaveSDF.is_quad_in_cave_cutout(v00, v10, v01, v11)


static func is_in_portal_scatter_exclusion(x: float, z: float, is_grass: bool = false) -> bool:
	if x < -150.0 or x > 30.0 or z < -155.0 or z > 30.0:
		return false
	return CaveSDF.is_in_overworld_scatter_exclusion(x, z, is_grass)


static func is_subterranean_or_cutout(x: float, z: float, foot_y: float, overworld_h: float) -> bool:
	if x < -350.0 or x > 85.0 or z < -330.0 or z > 105.0:
		return false
	var cl := CaveLayout.to_local(Vector3(x, foot_y, z))
	if cl.x < -225.0 or cl.x > 80.0 or cl.z < -38.0 or cl.z > 245.0:
		return false

	# 1. Inside either heightfield cutout (Entrance Outcrop or Skylight hole), always use SDF mesh
	if CaveSDF.eval_mouth_patch_t(cl.x, cl.z) < 0.68 or CaveSDF.eval_sky_patch_t(cl.x, cl.z) < 0.68:
		return true

	# 2. If actor is up on the grassy mountain roof outside the cutouts, use overworld heightfield
	if foot_y >= overworld_h - 2.2:
		return false

	# 3. Actor is below the mountain skin: check if inside/near subterranean cave air
	var sdf := get_sdf()
	return sdf.eval_cave_void_smooth(cl.x, foot_y + 1.1, cl.z) < 3.2


static func sample_sdf_floor_below(x: float, z: float, foot_y: float, overworld_h: float) -> Vector4:
	var sdf := get_sdf()
	var cl := CaveLayout.to_local(Vector3(x, foot_y, z))
	var u := cl.x
	var s := cl.z

	# Use fast analytical smooth SDF when subterranean inside the cave (avoids 3D noise lag on slopes)
	var use_fast := (foot_y < 46.0 and s > 4.0)
	var y_air := foot_y + 1.1
	var f_air := sdf.eval_cave_void_smooth(u, y_air, s) if use_fast else sdf.eval_sdf_full(u, y_air, s, overworld_h)
	if f_air >= 0.0:
		for lift in 3:
			var try_y := foot_y + 1.8 + float(lift) * 0.8
			var try_f := sdf.eval_cave_void_smooth(u, try_y, s) if use_fast else sdf.eval_sdf_full(u, try_y, s, overworld_h)
			if try_f < 0.0:
				y_air = try_y
				f_air = try_f
				break

	var y_prev := y_air
	var step := 0.85
	var y_min := 0.2 if foot_y > 46.0 else maxf(0.2, foot_y - 9.0)
	var hit_y := foot_y
	var found := false
	var nudged := false
	var ln := Vector3.UP
	var eps := 0.45
	var y_cur := y_air - step
	while y_cur >= y_min:
		var f_cur := sdf.eval_cave_void_smooth(u, y_cur, s) if use_fast else sdf.eval_sdf_full(u, y_cur, s, overworld_h)
		if f_air < 0.0 and f_cur >= 0.0:
			var lo := y_cur
			var hi := y_prev
			for _b in 4:
				var mid := 0.5 * (lo + hi)
				var f_mid := sdf.eval_cave_void_smooth(u, mid, s) if use_fast else sdf.eval_sdf_full(u, mid, s, overworld_h)
				if f_mid >= 0.0:
					lo = mid
				else:
					hi = mid
			var cand_y := 0.5 * (lo + hi)
			var gx: float
			var gy: float
			var gz: float
			if use_fast:
				gx = sdf.eval_cave_void_smooth(u + eps, cand_y, s) - sdf.eval_cave_void_smooth(u - eps, cand_y, s)
				gy = sdf.eval_cave_void_smooth(u, cand_y + eps, s) - sdf.eval_cave_void_smooth(u, cand_y - eps, s)
				gz = sdf.eval_cave_void_smooth(u, cand_y, s + eps) - sdf.eval_cave_void_smooth(u, cand_y, s - eps)
			else:
				gx = sdf.eval_sdf_full(u + eps, cand_y, s, overworld_h) - sdf.eval_sdf_full(u - eps, cand_y, s, overworld_h)
				gy = sdf.eval_sdf_full(u, cand_y + eps, s, overworld_h) - sdf.eval_sdf_full(u, cand_y - eps, s, overworld_h)
				gz = sdf.eval_sdf_full(u, cand_y, s + eps, overworld_h) - sdf.eval_sdf_full(u, cand_y, s - eps, overworld_h)
			var cand_ln := Vector3(-gx, -gy, -gz).normalized()
			if cand_ln.y >= 0.45:
				hit_y = cand_y
				ln = cand_ln
				found = true
				break
			# Grazed a vertical or overhanging wall: nudge laterally at most once per query so it never loops endlessly
			if not nudged:
				nudged = true
				var lat := Vector2(cand_ln.x, cand_ln.z)
				if lat.length_squared() > 1e-4:
					lat = lat.normalized() * 0.85
					u += lat.x
					s += lat.y
					f_cur = sdf.eval_cave_void_smooth(u, y_cur, s) if use_fast else sdf.eval_sdf_full(u, y_cur, s, overworld_h)
			else:
				break
		y_prev = y_cur
		f_air = f_cur
		y_cur -= step

	if not found:
		hit_y = maxf(0.5, foot_y - 2.0)
		ln = Vector3.UP

	var wn := (CaveLayout.to_world(ln) - CaveLayout.ORIGIN)
	wn.y = ln.y
	wn = wn.normalized()
	return Vector4(wn.x, wn.y, wn.z, hit_y)


static func _local_dir_to_world_xz(du: float, ds: float) -> Vector3:
	return Vector3(
		CaveLayout.FWD_XZ.x * ds + CaveLayout.RIGHT_XZ.x * du,
		0.0,
		CaveLayout.FWD_XZ.y * ds + CaveLayout.RIGHT_XZ.y * du
	)


## Unified query for all water domains (Collapse Pool, Outflow Stream, Organic Underground Lake,
## and Overworld Ocean). Returns {in_water: bool, water_y: float, flow_vel: Vector3}.
func sample_world_water_at(world_pos: Vector3, ground_y: float, is_subterranean: bool) -> Dictionary:
	return sample_water_at(world_pos, ground_y, is_subterranean, water_config, _surface_sea_level)


static func sample_water_at(world_pos: Vector3, ground_y: float, is_subterranean: bool, water_cfg: CaveWaterConfig = null, sea_level: float = NAN) -> Dictionary:
	var eff_wcfg := water_cfg if water_cfg != null else _active_water_config
	var sl := sea_level if not is_nan(sea_level) else _active_sea_level
	var cl := CaveLayout.to_local(world_pos)
	var in_cave_box := cl.z > -4.0 and cl.z < 245.0 and cl.x > -225.0 and cl.x < 80.0 and world_pos.y < 52.0

	if is_subterranean or in_cave_box:
		# 1. Collapse Hall Carved Pool Basin
		var pool_c: Vector3 = CaveLayout.POOL["c"]
		var pool_rx: float = float(CaveLayout.POOL["rx"]) + 0.42
		var pool_rz: float = float(CaveLayout.POOL["rz"]) + 0.42
		var p_wy: float = eff_wcfg.pool_water_y if eff_wcfg != null else float(CaveLayout.POOL["water_y"])
		var pu := (cl.x - pool_c.x) / pool_rx
		var ps := (cl.z - pool_c.z) / pool_rz
		if pu * pu + ps * ps <= 1.0 and ground_y < p_wy + 0.04:
			var wf: Vector3 = CaveLayout.WATERFALL
			var away_wf := Vector2(cl.x - wf.x, cl.z - wf.z)
			var to_mouth := Vector2(-44.0 - cl.x, 88.5 - cl.z)
			var flow_loc := Vector2.ZERO
			if away_wf.length() < 4.5 and away_wf.length_squared() > 1e-4:
				flow_loc += away_wf.normalized() * 0.55
			if to_mouth.length_squared() > 0.25:
				flow_loc += to_mouth.normalized() * 0.30
			return {
				"in_water": true,
				"water_y": p_wy,
				"flow_vel": _local_dir_to_world_xz(flow_loc.x, flow_loc.y),
			}

		# 2. Organic Multi-Cove Underground Lake Lagoon
		var lake_c: Vector3 = CaveLayout.UNDERGROUND_LAKE["c"]
		var lake_rx: float = float(CaveLayout.UNDERGROUND_LAKE["rx"])
		var lake_rz: float = float(CaveLayout.UNDERGROUND_LAKE["rz"])
		var l_wy: float = eff_wcfg.lake_water_y if eff_wcfg != null else float(CaveLayout.UNDERGROUND_LAKE["water_y"])
		var lu := (cl.x - lake_c.x) / lake_rx
		var ls := (cl.z - lake_c.z) / lake_rz
		var l_raw := sqrt(lu * lu + ls * ls)
		if l_raw < 1.45:
			var lr := l_raw / CaveLayout.lake_shore_radius_scale(atan2(ls, lu))
			if lr <= 1.0 and ground_y < l_wy + 0.04:
				return {
					"in_water": true,
					"water_y": l_wy,
					"flow_vel": Vector3.ZERO,
				}

		# 3. Stream Grotto Outflow Channel
		var ctrl := CaveLayout.STREAM_CTRL
		var best_d2 := 1.21 # 1.10 m half-width squared matching visible water sheet
		var best_wy := -9999.0
		var best_dir := Vector2.ZERO
		for i in range(ctrl.size() - 1):
			var a := ctrl[i]
			var b := ctrl[i + 1]
			var abx := b.x - a.x
			var abz := b.z - a.z
			var l2 := abx * abx + abz * abz
			if l2 < 1e-5:
				continue
			var t := clampf(((cl.x - a.x) * abx + (cl.z - a.z) * abz) / l2, 0.0, 1.0)
			var px := a.x + abx * t
			var pz := a.z + abz * t
			var d2 := (cl.x - px) * (cl.x - px) + (cl.z - pz) * (cl.z - pz)
			if d2 < best_d2:
				best_d2 = d2
				best_wy = lerpf(a.y, b.y, t)
				best_dir = Vector2(abx, abz).normalized()
		if best_wy > -9000.0 and ground_y < best_wy + 0.16:
			var eff_wy := maxf(best_wy, ground_y + 0.06)
			var flow_spd: float = eff_wcfg.stream_flow_speed if eff_wcfg != null else 1.45
			return {
				"in_water": true,
				"water_y": eff_wy,
				"flow_vel": _local_dir_to_world_xz(best_dir.x * flow_spd, best_dir.y * flow_spd),
			}

		return {"in_water": false, "water_y": -9999.0, "flow_vel": Vector3.ZERO}

	# 4. Overworld Continental Coastline & Ocean (shared sea_level) and Sunken Rat Swamp Lagoon
	if not in_cave_box and world_pos.y >= sl - 48.0 and world_pos.y < sl + 5.0 and ground_y < sl + 0.04:
		var r2_ow := world_pos.x * world_pos.x + world_pos.z * world_pos.z
		if r2_ow > 1500.0 * 1500.0:
			return {"in_water": true, "water_y": sl, "flow_vel": Vector3.ZERO}
	if not is_subterranean and world_pos.z > WorldLandmarks.RAT_WARREN_MOUTH.y + 1.0 and world_pos.z < WorldLandmarks.RAT_WARREN_MOUTH.y + 141.0 and absf(world_pos.x - WorldLandmarks.RAT_WARREN_MOUTH.x) < 95.0:
		var sw_y := WorldLandmarks.RAT_SWAMP_WATER_Y
		if ground_y < sw_y + 0.03 and world_pos.y < sw_y + 1.8:
			return {"in_water": true, "water_y": sw_y, "flow_vel": Vector3.ZERO}

	return {"in_water": false, "water_y": -9999.0, "flow_vel": Vector3.ZERO}


# ==============================================================================
# RUNTIME SCENE BUILDER
# ==============================================================================

func rebuild_cave(terrain_scene: Node3D, seed_val: int = 1337, build_colliders: bool = true) -> void:
	_clear_generated_children()
	_flora_grass_node = null
	_grass_shader_mat = null
	_pool_water_mat = null
	_lake_water_mat = null
	_stream_water_mat = null
	_ocean_water_mat = null
	if terrain_scene != null:
		_surface_sea_level = float(terrain_scene.get("sea_level"))
		_active_sea_level = _surface_sea_level
		_active_water_config = water_config
		var ow_water := terrain_scene.get_node_or_null("Water") as MeshInstance3D
		if ow_water != null and ow_water.material_override is ShaderMaterial:
			_ocean_water_mat = ow_water.material_override as ShaderMaterial
	_geode_reward_node = null
	_geode_reward_mesh = null
	_geode_reward_area = null
	_geode_reward_collected = false
	_geode_orb_satellites.clear()
	_door_anim_t = 0.0
	_fire_flicker_t = 0.0
	_door_awaken_val = 0.18
	_door_astrolabe_outer = null
	_door_astrolabe_inner = null
	_door_relief_mat = null
	_torch_flame_mats.clear()
	_torch_card_mats.clear()
	_torch_haze_mats.clear()
	_vault_door_omni = null
	_vault_door_omni_base_pos = Vector3.ZERO
	_wake_points.clear()
	for _wi in 12:
		_wake_points.append(Vector4(0.0, -1.0, 0.0, 0.0))
	_wake_head = 0
	_last_wake_pos = Vector3(9999.0, -9999.0, 9999.0)
	_wake_emit_timer = 0.0
	_water_ripple_submersion = 0.0
	_water_ripple_pos = Vector3(9999.0, -9999.0, 9999.0)
	_water_ripple_rad = 1.6

	if not ResourceLoader.exists(CAVE_MESH_PATH):
		push_warning("CaveSystem: Baked mesh missing at %s (run tools/bake_cave.gd)" % CAVE_MESH_PATH)
		return

	var cave_mesh := load(CAVE_MESH_PATH) as ArrayMesh
	if cave_mesh == null:
		return

	var shell := MeshInstance3D.new()
	shell.name = "CaveShell"
	shell.mesh = cave_mesh
	shell.layers = 0
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.custom_aabb = AABB(Vector3(-345.0, -5.0, -325.0), Vector3(425.0, 85.0, 420.0))
	add_child(shell)
	_build_chunked_cave_shell(shell, cave_mesh, _get_cave_rock_material())

	if build_colliders:
		if ResourceLoader.exists(CAVE_FLOOR_SHAPE_PATH):
			var floor_shape := load(CAVE_FLOOR_SHAPE_PATH) as Shape3D
			if floor_shape != null:
				var fb := StaticBody3D.new()
				fb.name = "CaveFloorBody"
				fb.collision_layer = 1
				fb.collision_mask = 0
				var fcs := CollisionShape3D.new()
				fcs.shape = floor_shape
				fb.add_child(fcs)
				shell.add_child(fb)

		if ResourceLoader.exists(CAVE_WALL_SHAPE_PATH):
			var wall_shape := load(CAVE_WALL_SHAPE_PATH) as Shape3D
			if wall_shape != null:
				var wb := StaticBody3D.new()
				wb.name = "CaveWallBody"
				wb.collision_layer = 4
				wb.collision_mask = 0
				var wcs := CollisionShape3D.new()
				wcs.shape = wall_shape
				wb.add_child(wcs)
				shell.add_child(wb)

	_build_interior_lighting_rig()

	var boulder_body: StaticBody3D = null
	if build_colliders:
		boulder_body = StaticBody3D.new()
		boulder_body.name = "CaveBoulderBody"
		boulder_body.collision_layer = 4
		boulder_body.collision_mask = 0
		add_child(boulder_body)

	var rock_meshes := _load_rock_meshes()
	var rock_shapes := _build_rock_convex_shapes(rock_meshes)

	var props_data := _load_or_compute_props(terrain_scene, seed_val)

	# P2: Kitbashed entrance talus, brow crags, breakdown mound boulders & deadwood tree/log
	var fallen_log_xf := _build_boulders_and_trees(terrain_scene, boulder_body, rock_meshes, rock_shapes, null, props_data)

	# P3: Active atmosphere controller (sunbeam cone meshes removed to avoid floor intersection halo)
	if not Engine.is_editor_hint():
		var atmos := CaveAtmosphere.new()
		atmos.name = "CaveAtmosphere"
		add_child(atmos)

	# P4: Radiating Geode crystal clusters + tiny Fork crawlway mouth teaser crystals + Deep Abyssal Shard Bundle
	_pending_crystal_props.clear()
	_crystal_mat_cache.clear()
	_build_crystals(null, props_data)
	_build_abyssal_shard_bundle(boulder_body)

	# P5: Pool basin water, drip waterfall ribbon, outflow stream, river pebbles,
	#     paired speleothems, strictly zero-collision ecological CaveFlora, and the Ancient Big Door
	_build_water_features()
	_build_pebbles(null, props_data)
	_build_speleothems(boulder_body, null, props_data)
	_build_flora(terrain_scene, fallen_log_xf, null, props_data)
	_build_ancient_big_door()

	# P6: Geode Prismatic Crystal Core collectible reward & acoustic zone reverb plumbing
	_build_geode_reward()
	_build_reverb_zones()
	_init_zone_culling_refs()

	if not Engine.is_editor_hint() and build_colliders and not _pending_crystal_props.is_empty():
		_register_crystal_props_deferred.call_deferred()


func _init_zone_culling_refs() -> void:
	_cave_shell = get_node_or_null("CaveShell") as MeshInstance3D
	_lighting_rig = get_node_or_null("CaveLighting") as Node3D
	_skylight_spot = _lighting_rig.get_node_or_null("SkylightKeySpot") as SpotLight3D if _lighting_rig != null else null
	_accent_lights.clear()
	_vault_door_omni = null
	if _lighting_rig != null:
		for ch in _lighting_rig.get_children():
			if ch is OmniLight3D:
				_accent_lights.append(ch as OmniLight3D)
				if ch.name == "VaultDoorOmni":
					_vault_door_omni = ch as OmniLight3D
					_vault_door_omni_base_pos = _vault_door_omni.position
	_water_holder = get_node_or_null("CaveWater") as Node3D
	_lake_water_node = _water_holder.get_node_or_null("UndergroundLakeWater") as Node3D if _water_holder != null else null
	_pool_water_node = _water_holder.get_node_or_null("PoolWater") as Node3D if _water_holder != null else null
	_stream_water_node = _water_holder.get_node_or_null("StreamWater") as Node3D if _water_holder != null else null
	_waterfall_node = _water_holder.get_node_or_null("WaterfallRibbon") as Node3D if _water_holder != null else null
	_shards_holder = get_node_or_null("CaveCrystalShards") as Node3D
	_abyssal_holder = get_node_or_null("CaveAbyssalCrystalShards") as Node3D
	_crystal_stones_node = get_node_or_null("CaveCrystalStones") as Node3D
	_abyssal_base_node = get_node_or_null("CaveAbyssalShards") as MeshInstance3D
	_pebbles_node = get_node_or_null("CavePebbles") as Node3D
	_speleothems_node = get_node_or_null("CaveSpeleothems") as Node3D
	_flora_node = get_node_or_null("CaveFlora") as Node3D
	_beams_node = get_node_or_null("SkylightBeams") as Node3D
	_door_node = get_node_or_null("AncientBigDoor") as Node3D
	_pedestal_node = get_node_or_null("GeodeAltarPedestal") as MeshInstance3D
	_boulders_node = get_node_or_null("CaveBoulders") as Node3D

	var terrain_p := get_parent()
	if terrain_p != null:
		_ow_terrain = terrain_p.get_node_or_null("Terrain") as Node3D
		_ow_grass = terrain_p.get_node_or_null("Grass") as Node3D
		_ow_wispy = terrain_p.get_node_or_null("GrassWispy") as Node3D
		_ow_trees = terrain_p.get_node_or_null("Trees") as Node3D
		_ow_rocks = terrain_p.get_node_or_null("Rocks") as Node3D
		_ow_veg = terrain_p.get_node_or_null("Vegetation") as Node3D
		_ow_water = terrain_p.get_node_or_null("Water") as Node3D
		_ow_village = terrain_p.get_node_or_null("Village") as Node3D
		var main_n := terrain_p.get_parent()
		_ow_sun = main_n.get_node_or_null("Sun") as DirectionalLight3D if main_n != null else null
	_zone_cull_mode = -1
	_zone_vis_state = [false, false, false, false, false]
	_last_cull_cam = Vector3(1e9, 1e9, 1e9)
	_water_uniforms_dirty = true


func update_zone_culling(cam_pos: Vector3, cl: Vector3, cave_factor: float) -> void:
	if Engine.is_editor_hint() or _cave_shell == null:
		return
	if cam_pos.distance_squared_to(_last_cull_cam) < 0.36 and _zone_cull_mode >= 0:
		return
	_last_cull_cam = cam_pos

	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	var d_skylight_2d := Vector2(cl.x - sky_c.x, cl.z - sky_c.z).length()
	var d_mouth_2d := Vector2(cl.x, cl.z).length()

	# Mode: 1 = far outdoors (hide deep cave interiors & lights); 2 = deep subterranean inside Crystal Cave (hide overworld foliage/ocean/terrain); 0 = twilight/skylight transition
	var in_crystal_xy := absf(cl.x) < 190.0 and cl.z < 260.0
	var target_mode := 0
	if cave_factor < 0.03 and (not in_crystal_xy or cl.z < -8.0 or (cl.y > 41.0 and d_skylight_2d > 42.0 and d_mouth_2d > 54.0)):
		target_mode = 1
	elif in_crystal_xy and cave_factor > 0.85 and cl.z > 44.0 and cl.y < 36.0 and d_skylight_2d > 48.0 and d_mouth_2d > 56.0:
		target_mode = 2

	var show_cave_interior := (target_mode != 1)
	var show_overworld := (target_mode != 2) or (d_mouth_2d < 85.0) or (d_skylight_2d < 60.0)
	var hide_ocean_in_cave := (cave_factor > 0.70 and cl.z > 20.0 and cl.y < 40.0)

	var zone_vis: Array[bool]
	if target_mode == 1:
		zone_vis = [
			d_mouth_2d <= 125.0,
			(d_mouth_2d <= 78.0) or (d_skylight_2d <= 72.0),
			d_skylight_2d <= 85.0,
			false,
			false,
		]
	else:
		zone_vis = [
			(cl.z < 94.0) or (d_mouth_2d <= 98.0),
			cl.z < 144.0,
			(cl.z >= 12.0 and cl.z < 166.0 and cl.x > -72.0),
			(cl.z >= 78.0) or (cl.x > -2.0),
			(cl.x < -30.0 and cl.z >= 115.0) or (cl.x < -68.0),
		]

	if _zone_cull_mode != target_mode:
		_zone_cull_mode = target_mode
		if _lighting_rig != null:
			_lighting_rig.visible = show_cave_interior
		if _water_holder != null:
			_water_holder.visible = show_cave_interior
		if _shards_holder != null:
			_shards_holder.visible = show_cave_interior
		if _crystal_stones_node != null:
			_crystal_stones_node.visible = show_cave_interior
		if _pebbles_node != null:
			_pebbles_node.visible = show_cave_interior
		if _speleothems_node != null:
			_speleothems_node.visible = show_cave_interior
		if _flora_node != null:
			_flora_node.visible = show_cave_interior
		if _beams_node != null:
			_beams_node.visible = show_cave_interior

		if _ow_terrain != null:
			_ow_terrain.visible = show_overworld
		if _ow_grass != null:
			_ow_grass.visible = show_overworld
		if _ow_wispy != null:
			_ow_wispy.visible = show_overworld
		if _ow_trees != null:
			_ow_trees.visible = show_overworld
		if _ow_rocks != null:
			_ow_rocks.visible = show_overworld
		if _ow_veg != null:
			_ow_veg.visible = show_overworld
		if _ow_village != null:
			_ow_village.visible = show_overworld
		if _ow_sun != null:
			_ow_sun.visible = show_overworld

	if _door_node != null:
		var want_door := show_cave_interior and zone_vis[4]
		if _door_node.visible != want_door:
			_door_node.visible = want_door
	if _pedestal_node != null:
		var want_geo := show_cave_interior and zone_vis[2]
		if _pedestal_node.visible != want_geo:
			_pedestal_node.visible = want_geo
	if _geode_reward_node != null:
		var want_rew := show_cave_interior and zone_vis[2]
		if _geode_reward_node.visible != want_rew:
			_geode_reward_node.visible = want_rew
	var want_abyss := show_cave_interior and (zone_vis[2] or zone_vis[3])
	if _abyssal_holder != null and _abyssal_holder.visible != want_abyss:
		_abyssal_holder.visible = want_abyss
	if _abyssal_base_node != null and _abyssal_base_node.visible != want_abyss:
		_abyssal_base_node.visible = want_abyss
	if show_cave_interior:
		if _lake_water_node != null and _lake_water_node.visible != zone_vis[3]:
			_lake_water_node.visible = zone_vis[3]
		var want_grotto_w := zone_vis[1] or zone_vis[2]
		if _pool_water_node != null and _pool_water_node.visible != want_grotto_w:
			_pool_water_node.visible = want_grotto_w
		if _stream_water_node != null and _stream_water_node.visible != want_grotto_w:
			_stream_water_node.visible = want_grotto_w
		if _waterfall_node != null and _waterfall_node.visible != want_grotto_w:
			_waterfall_node.visible = want_grotto_w
		for zid in 5:
			var zv := zone_vis[zid]
			if _zone_vis_state[zid] != zv:
				_zone_vis_state[zid] = zv
				var arr: Array = _zoned_mmis[zid]
				for mmi in arr:
					if mmi != null and is_instance_valid(mmi) and (mmi as Node3D).visible != zv:
						(mmi as Node3D).visible = zv

	if _ow_water != null:
		var want_ocean := show_overworld and not hide_ocean_in_cave
		if _ow_water.visible != want_ocean:
			_ow_water.visible = want_ocean

	# SkylightKeySpot disabled to prevent hard circular shadow/cone halo on the cave floor
	if _skylight_spot != null and _skylight_spot.visible:
		_skylight_spot.visible = false
	if show_cave_interior:
		for omni in _accent_lights:
			if omni != null:
				var ok_zone := true
				if omni.name == "UndergroundLakeOmni":
					ok_zone = zone_vis[3]
				elif omni.name == "VaultDoorOmni":
					ok_zone = zone_vis[4]
				elif omni.name == "GeodeCrystalOmni":
					ok_zone = zone_vis[2] or cl.x > -28.0
				elif omni.name == "GrottoArchOmni":
					ok_zone = zone_vis[1] or zone_vis[3]
				var max_r := omni.omni_range + 16.0
				omni.visible = ok_zone and cam_pos.distance_squared_to(omni.global_position) <= max_r * max_r
	if _cave_shell != null:
		var want_shell_shadow := (target_mode != 1 and d_skylight_2d < 34.0)
		var want_mouth_shadow := (d_mouth_2d < 38.0)
		var want_shell_vis := not (target_mode == 1 and d_mouth_2d > 125.0 and d_skylight_2d > 85.0)
		if _cave_shell.visible != want_shell_vis:
			_cave_shell.visible = want_shell_vis
		if _cave_shell.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_cave_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if want_shell_vis:
			for chunk_mi in _cave_shell_chunks:
				if chunk_mi == null or not is_instance_valid(chunk_mi):
					continue
				var zid := int(chunk_mi.get_meta("zid", 0))
				var cvis: bool = zone_vis[zid] if (zid >= 0 and zid < 5) else false
				if chunk_mi.visible != cvis:
					chunk_mi.visible = cvis
				var c_sh := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if cvis:
					if zid == 0 and want_mouth_shadow:
						c_sh = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
					elif zid == 1 and want_shell_shadow and _cave_shell_shadow_proxy == null:
						c_sh = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if chunk_mi.cast_shadow != c_sh:
					chunk_mi.cast_shadow = c_sh
		if _cave_shell_shadow_proxy != null and is_instance_valid(_cave_shell_shadow_proxy):
			var want_proxy := want_shell_vis and want_shell_shadow and zone_vis[1]
			if _cave_shell_shadow_proxy.visible != want_proxy:
				_cave_shell_shadow_proxy.visible = want_proxy

	# Gate deep vault brazier particles & heat-haze backbuffer copy behind cavern bend
	var want_vault_vfx := show_cave_interior and zone_vis[4]
	if _door_vfx_active != want_vault_vfx:
		_door_vfx_active = want_vault_vfx
		for gp in _door_particles:
			if gp != null and is_instance_valid(gp):
				gp.emitting = want_vault_vfx
				gp.visible = want_vault_vfx
		if not want_vault_vfx:
			for hmi in _door_haze_meshes:
				if hmi != null and is_instance_valid(hmi):
					hmi.visible = false


func _load_or_compute_props(terrain_scene: Node3D, seed_val: int = 1337) -> Dictionary:
	if not _cached_props_data.is_empty():
		return _cached_props_data

	if FileAccess.file_exists(CAVE_PROPS_CACHE_PATH):
		var f := FileAccess.open(CAVE_PROPS_CACHE_PATH, FileAccess.READ)
		if f != null:
			var d = f.get_var(true)
			f.close()
			if d is Dictionary and not d.is_empty():
				_cached_props_data = d
				return _cached_props_data

	var computed := compute_cave_props(terrain_scene, seed_val)
	_cached_props_data = computed
	var f_out := FileAccess.open(CAVE_PROPS_CACHE_PATH, FileAccess.WRITE)
	if f_out != null:
		f_out.store_var(computed, true)
		f_out.close()
	return _cached_props_data


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var parent := get_parent()
	if _slime_ref == null or not is_instance_valid(_slime_ref):
		if parent != null and parent.get_parent() != null:
			_slime_ref = parent.get_parent().get_node_or_null("Slime") as Node3D

	if _ocean_water_mat == null and parent != null:
		var ow_w := parent.get_node_or_null("Water") as MeshInstance3D
		if ow_w != null and ow_w.material_override is ShaderMaterial:
			_ocean_water_mat = ow_w.material_override as ShaderMaterial

	var active_water_slime: Node3D = _slime_ref
	if active_water_slime != null:
		var m_chk: Variant = active_water_slime.get("motor")
		if m_chk != null and not bool(m_chk.in_water):
			var eco: Variant = active_water_slime.get("props")
			if eco != null and "registered_slimes" in eco:
				for other in eco.registered_slimes:
					if is_instance_valid(other) and other != active_water_slime and other.motor != null and other.motor.in_water:
						active_water_slime = other
						break

	var dt_safe := clampf(delta, 0.0, 0.05)
	if _wake_points.size() != 12:
		_wake_points.clear()
		for _wi in 12:
			_wake_points.append(Vector4(0.0, -1.0, 0.0, 0.0))

	var any_in_water := false
	var s_pos := Vector3(9999.0, -9999.0, 9999.0)
	var s_vel := Vector3.ZERO
	var s_rad := 1.6
	if active_water_slime != null and is_instance_valid(active_water_slime):
		var m: Variant = active_water_slime.get("motor")
		if m != null and bool(m.in_water) and float(m.water_submersion) > 0.01:
			any_in_water = true
			var mod: Variant = active_water_slime.get("model")
			var sc_val: float = float(active_water_slime.get("slime_scale"))
			s_rad = (mod.rest_max_radius * sc_val * mod.spread) if mod != null else 1.6
			s_pos = active_water_slime.global_position
			var surf_presence := 1.0
			if mod != null:
				var foot_y_w: float = s_pos.y - float(mod.rest_half_height) * sc_val
				var top_y_w: float = foot_y_w + float(mod.rest_full_height) * sc_val
				var depth_below_surf: float = maxf(float(m.water_y) - top_y_w, 0.0)
				surf_presence = exp(-depth_below_surf * 1.35)
				var rest_h_w: float = clampf((float(m.water_y) - foot_y_w) / maxf(sc_val, 0.01), 0.0, float(mod.rest_full_height) * 0.5)
				s_rad = maxf(float(mod.call("rest_radius_at", rest_h_w)) * sc_val * float(mod.spread), 0.45)
			s_vel = m.velocity
			_water_ripple_submersion = float(m.water_submersion) * surf_presence
			_water_ripple_pos = s_pos
			_water_ripple_rad = s_rad

			if _last_wake_pos.distance_squared_to(s_pos) > 2500.0:
				for wi in 12:
					_wake_points[wi] = Vector4(0.0, -1.0, 0.0, 0.0)
				_last_wake_pos = s_pos

			var spd_xz := Vector2(s_vel.x, s_vel.z).length()
			if spd_xz > 0.30 and _water_ripple_submersion > 0.08 and surf_presence > 0.15:
				_wake_emit_timer += dt_safe
				var d_since := Vector2(s_pos.x - _last_wake_pos.x, s_pos.z - _last_wake_pos.z).length()
				if d_since >= 0.68 or _wake_emit_timer >= 0.16:
					_wake_points[_wake_head] = Vector4(s_pos.x, 0.0, s_pos.z, clampf(spd_xz / 5.5, 0.22, 0.95) * surf_presence)
					_wake_head = (_wake_head + 1) % 12
					_last_wake_pos = s_pos
					_wake_emit_timer = 0.0

	if not any_in_water:
		# Dissolve water ripples quickly (~0.12s fade) in place at the last in-water spot so ripples vanish cleanly once out
		_water_ripple_submersion *= exp(-28.0 * dt_safe)
		if _water_ripple_submersion < 0.025:
			_water_ripple_submersion = 0.0
			_water_ripple_pos = Vector3(9999.0, -9999.0, 9999.0)
		s_pos = _water_ripple_pos
		s_rad = _water_ripple_rad
		_wake_emit_timer = 0.0

	var active_wakes := 0
	for wi in 12:
		var wp: Vector4 = _wake_points[wi]
		if wp.y >= 0.0:
			wp.y += dt_safe
			if any_in_water:
				if wp.y > 2.65:
					wp = Vector4(0.0, -1.0, 0.0, 0.0)
			else:
				wp.w *= exp(-16.0 * dt_safe)
				if wp.w < 0.02 or wp.y > 2.2:
					wp = Vector4(0.0, -1.0, 0.0, 0.0)
			_wake_points[wi] = wp
			if wp.y >= 0.0:
				active_wakes += 1

	var water_active := any_in_water or _water_ripple_submersion > 0.0 or active_wakes > 0
	if water_active or _water_uniforms_dirty:
		_water_uniforms_dirty = water_active
		for wmat: ShaderMaterial in [_pool_water_mat, _lake_water_mat, _stream_water_mat, _ocean_water_mat]:
			if wmat != null:
				wmat.set_shader_parameter(SN_SLIME_POS, s_pos)
				wmat.set_shader_parameter(SN_SLIME_VEL, s_vel)
				wmat.set_shader_parameter(SN_SLIME_RADIUS, s_rad)
				wmat.set_shader_parameter(SN_SLIME_SUBMERSION, _water_ripple_submersion)
				wmat.set_shader_parameter(SN_ACTIVE_WAKE_COUNT, active_wakes)
				if active_wakes > 0 or not water_active:
					wmat.set_shader_parameter(SN_WAKE_POINTS, _wake_points)

	if not _geode_reward_collected and (_geode_reward_node == null or _geode_reward_node.visible) and _geode_reward_mesh != null and is_instance_valid(_geode_reward_mesh):
		_geode_spin_t += delta
		_geode_reward_mesh.rotation.y = _geode_spin_t * 0.42
		_geode_reward_mesh.position.y = sin(_geode_spin_t * 1.9) * 0.14
		var core_node := _geode_reward_mesh.get_node_or_null("OrbCore") as Node3D
		if core_node != null:
			core_node.rotation.y = -_geode_spin_t * 0.72
			core_node.rotation.x = sin(_geode_spin_t * 1.05) * 0.08
		for sat_i in _geode_orb_satellites.size():
			var sat := _geode_orb_satellites[sat_i]
			if sat != null and is_instance_valid(sat):
				var orb_ang := _geode_spin_t * (1.08 + float(sat_i) * 0.16) + float(sat_i) * (TAU / maxf(float(_geode_orb_satellites.size()), 1.0))
				var orb_r := 1.02 + float(sat_i % 2) * 0.22
				var tilt := 0.34 if (sat_i % 2 == 0) else -0.30
				sat.position = Vector3(cos(orb_ang) * orb_r, sin(orb_ang) * tilt + 0.12 * cos(orb_ang * 2.0), sin(orb_ang) * orb_r)
				sat.rotation = Vector3(sin(orb_ang) * 0.32, -orb_ang + PI * 0.5, cos(orb_ang) * 0.28)

	if _door_node != null and _door_node.visible and is_instance_valid(_door_node):
		var target_awaken := door_idle_glow
		if _slime_ref != null and is_instance_valid(_slime_ref):
			var d_door := _slime_ref.global_position.distance_to(_door_node.global_position)
			target_awaken = clampf(1.0 - (d_door - 7.5) / maxf(door_awaken_distance, 1.0), door_idle_glow, 1.0)
		_door_awaken_val = lerpf(_door_awaken_val, target_awaken, minf(delta * 3.2, 1.0))
		var speed_mult := 1.0 + _door_awaken_val * 0.55
		_door_anim_t += delta * speed_mult
		_fire_flicker_t += delta

		if absf(_door_awaken_val - _last_pushed_awaken) > 1e-4:
			_last_pushed_awaken = _door_awaken_val
			for mat: ShaderMaterial in _torch_flame_mats:
				if mat != null:
					mat.set_shader_parameter(SN_AWAKEN_AMOUNT, _door_awaken_val)
			for mat: ShaderMaterial in _torch_card_mats:
				if mat != null:
					mat.set_shader_parameter(SN_AWAKEN_AMOUNT, _door_awaken_val)
			for mat: ShaderMaterial in _torch_haze_mats:
				if mat != null:
					mat.set_shader_parameter(SN_AWAKEN_AMOUNT, _door_awaken_val)

		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		var cam_d_door := cam.global_position.distance_to(_door_node.global_position) if cam != null else (_slime_ref.global_position.distance_to(_door_node.global_position) if (_slime_ref != null and is_instance_valid(_slime_ref)) else 999.0)
		var show_haze := _door_vfx_active and cam_d_door <= 38.0
		for hmi in _door_haze_meshes:
			if hmi != null and is_instance_valid(hmi) and hmi.visible != show_haze:
				hmi.visible = show_haze

		if _vault_door_omni != null and is_instance_valid(_vault_door_omni) and _vault_door_omni.visible:
			var ft := _fire_flicker_t
			# Summed irrational-ratio firelight waves + subtle high-frequency flicker
			var wave_a := sin(ft * 7.31) * 0.42
			var wave_b := sin(ft * 13.73 + 1.17) * 0.28
			var wave_c := cos(ft * 21.19 + 2.41) * 0.18
			var wave_d := sin(ft * 33.47 + 0.53) * 0.12
			var flicker_raw := wave_a + wave_b + wave_c + wave_d
			var flicker_e := clampf(0.95 + 0.16 * flicker_raw, 0.76, 1.16)
			_vault_door_omni.light_energy = (3.55 + _door_awaken_val * 0.55) * flicker_e

			var jx := (sin(ft * 9.13) * 0.6 + cos(ft * 19.31) * 0.4) * 0.14
			var jy := (sin(ft * 11.47 + 0.8) * 0.6 + sin(ft * 24.71) * 0.4) * 0.13
			var jz := (cos(ft * 8.29 + 1.9) * 0.6 + sin(ft * 17.53) * 0.4) * 0.14
			_vault_door_omni.position = _vault_door_omni_base_pos + Vector3(jx, jy, jz)

			var ember_c := Color(1.0, 0.56, 0.22)
			var flame_gold_c := Color(1.0, 0.80, 0.48)
			var color_t := clampf(0.50 + 0.42 * flicker_raw + _door_awaken_val * 0.12, 0.0, 1.0)
			_vault_door_omni.light_color = ember_c.lerp(flame_gold_c, color_t)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _geode_reward_collected or _zone_cull_mode == 1 or _geode_reward_node == null:
		return
	var candidates: Array = []
	var parent := get_parent()
	var main_node := parent.get_parent() if parent != null else null
	if main_node != null:
		var eco := main_node.get_node_or_null("Ecosystem")
		if eco != null and "registered_slimes" in eco:
			candidates.append_array(eco.registered_slimes)
		var direct_slime := main_node.get_node_or_null("Slime")
		if direct_slime != null and not candidates.has(direct_slime):
			candidates.append(direct_slime)

	var rpos := _geode_reward_node.global_position
	for s in candidates:
		if not is_instance_valid(s):
			continue
		var sp: Vector3 = (s as Node3D).global_position
		var dx := sp.x - rpos.x
		var dz := sp.z - rpos.z
		var dy := absf(sp.y - rpos.y)
		if (dx * dx + dz * dz) <= 7.84 and dy <= 3.5:
			_collect_geode_reward(s)
			break


func _register_crystal_props_deferred() -> void:
	if Engine.is_editor_hint() or _pending_crystal_props.is_empty():
		return
	var parent := get_parent()
	var main_node := parent.get_parent() if parent != null else null
	var eco := main_node.get_node_or_null("Ecosystem") as SlimeProps if main_node != null else null
	if eco == null:
		return
	for item: Dictionary in _pending_crystal_props:
		var mi := item["mi"] as MeshInstance3D
		var mat := item["mat"] as ShaderMaterial
		if mi == null or not is_instance_valid(mi):
			continue
		eco.register_external_prop(
			mi,
			mat,
			int(item["shape"]),
			item["half"] as Vector3,
			float(item["base_r"]),
			int(item["sides"]),
			float(item["vol"]),
			true,
			&"cave_crystals",
			true,
			true,
			true
		)
	_pending_crystal_props.clear()


func _collect_geode_reward(collector: Variant) -> void:
	if _geode_reward_collected:
		return
	_geode_reward_collected = true
	set_physics_process(false)

	var target_slime: Variant = collector
	if collector != null and collector is Object and "role" in collector:
		var main_node := get_parent().get_parent() if get_parent() != null else null
		var player_slime := main_node.get_node_or_null("Slime") if main_node != null else null
		if player_slime != null and collector != player_slime and collector.role != 0:
			target_slime = player_slime

	if target_slime != null and target_slime.has_method("add_volume"):
		target_slime.add_volume(geode_volume_bonus)

	if _geode_reward_mesh != null:
		_geode_reward_mesh.visible = false
	if _geode_reward_area != null:
		_geode_reward_area.monitoring = false

	var st := get_tree()
	if st != null:
		st.call_group("hud", "show_toast", "Geode Heart Absorbed! (+%.1f m³)" % geode_volume_bonus, Color(0.55, 0.94, 1.0), 4.0)

	if DisplayServer.get_name() != "headless":
		var sm := get_node_or_null("/root/SettingsManager")
		if sm != null and sm.has_method("play_ui_sound"):
			sm.play_ui_sound("confirm")


func _on_geode_area_body_entered(body: Node3D) -> void:
	if _geode_reward_collected or body == null:
		return
	var p := body.get_parent()
	if p != null and p.has_method("add_volume"):
		_collect_geode_reward(p)


func is_geode_reward_collected() -> bool:
	return _geode_reward_collected


func _clear_generated_children() -> void:
	_pending_crystal_props.clear()
	_crystal_mat_cache.clear()
	_cave_shell_chunks.clear()
	_cave_shell_shadow_proxy = null
	_zoned_mmis = [[], [], [], [], []]
	_cave_boulder_shapes.clear()
	if not Engine.is_editor_hint() and is_inside_tree():
		var parent := get_parent()
		var main_node := parent.get_parent() if parent != null else null
		var eco := main_node.get_node_or_null("Ecosystem") as SlimeProps if main_node != null else null
		if eco != null:
			eco.clear_external_group(&"cave_crystals")
	for c in get_children():
		# Preserve Inspector-authored scene nodes (CaveOrigin, authored CaveLighting, sub-scenes)
		if c is CaveOriginNode or c.has_meta("_authored") or c.scene_file_path != "" or (c.name == "CaveLighting" and c.owner != null):
			continue
		remove_child(c)
		c.free()


func _editor_export_layout() -> void:
	var origin := get_node_or_null("CaveOrigin") as CaveOriginNode
	if origin != null:
		origin.export_layout_resource()
		layout_data = CaveLayout.load_active_layout()
	else:
		push_warning("[CaveSystem] No CaveOrigin child node found to export.")


func _editor_rebuild_preview() -> void:
	var parent_ts := get_parent()
	if parent_ts != null:
		rebuild_cave(parent_ts, bake_config.seed_val if bake_config != null else 1337, false)


func _get_cave_rock_material() -> ShaderMaterial:
	if _cached_rock_mat == null:
		_cached_rock_mat = ShaderMaterial.new()
		_cached_rock_mat.shader = load("res://terrain/cave_rock.gdshader") as Shader
		var rock_tex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
		var floor_tex := load("res://assets/nature/PathRocks_Diffuse.png") as Texture2D
		if rock_tex != null:
			_cached_rock_mat.set_shader_parameter("rock_texture", rock_tex)
		if floor_tex != null:
			_cached_rock_mat.set_shader_parameter("floor_texture", floor_tex)
	_cached_rock_mat.set_shader_parameter("cave_origin_xz", Vector2(CaveLayout.ORIGIN.x, CaveLayout.ORIGIN.z))
	_cached_rock_mat.set_shader_parameter("cave_fwd_xz", CaveLayout.FWD_XZ)
	_cached_rock_mat.set_shader_parameter("cave_right_xz", CaveLayout.RIGHT_XZ)
	var sky_c_mat: Vector3 = CaveLayout.SKYLIGHT["c"]
	_cached_rock_mat.set_shader_parameter("skylight_local_xz", Vector2(sky_c_mat.x, sky_c_mat.z))
	_cached_rock_mat.set_shader_parameter("greybox_mode", greybox_mode)
	return _cached_rock_mat


# ==============================================================================
# P3: LIGHTING RIG (<= 4 DYNAMIC LIGHTS, EXACTLY 1 SHADOWED)
# ==============================================================================

static func _cave_zone_for_world_pos(wp: Vector3) -> int:
	var cl := CaveLayout.to_local(wp)
	if cl.z < 42.0:
		return 0
	if cl.z < 106.0 and cl.x <= 0.0:
		return 1
	if cl.z < 130.0 and cl.x > 0.0:
		return 2
	if cl.x >= -75.0:
		return 3
	return 4


static func _build_decimated_shadow_mesh(src_verts: PackedVector3Array, src_indices: PackedInt32Array, grid_step: float = 0.92) -> ArrayMesh:
	var inv := 1.0 / maxf(grid_step, 0.25)
	var cell_to_idx: Dictionary = {}
	var sum_pos: Array[Vector3] = []
	var sum_cnt: Array[int] = []
	var vmap := PackedInt32Array()
	vmap.resize(src_verts.size())
	for vi in src_verts.size():
		var p := src_verts[vi]
		var key := Vector3i(roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv))
		var ci: int = cell_to_idx.get(key, -1)
		if ci < 0:
			ci = sum_pos.size()
			cell_to_idx[key] = ci
			sum_pos.append(p)
			sum_cnt.append(1)
		else:
			sum_pos[ci] += p
			sum_cnt[ci] += 1
		vmap[vi] = ci

	var out_verts := PackedVector3Array()
	out_verts.resize(sum_pos.size())
	for i in sum_pos.size():
		out_verts[i] = sum_pos[i] / float(sum_cnt[i])

	var out_idx := PackedInt32Array()
	var tri_n := src_indices.size() / 3
	for ti in tri_n:
		var b := ti * 3
		var a := vmap[src_indices[b]]
		var bb := vmap[src_indices[b + 1]]
		var c := vmap[src_indices[b + 2]]
		if a == bb or bb == c or a == c:
			continue
		out_idx.append(a)
		out_idx.append(bb)
		out_idx.append(c)

	if out_idx.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out_verts
	arr[Mesh.ARRAY_INDEX] = out_idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _attach_shadow_proxy_node(shell: MeshInstance3D, sh_mesh: Mesh, aabb: AABB) -> void:
	if sh_mesh == null:
		return
	var sp := MeshInstance3D.new()
	sp.name = "CaveShellChunk_1_Shadow"
	sp.mesh = sh_mesh
	sp.layers = 2
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	sp.custom_aabb = aabb
	sp.visible = false
	shell.add_child(sp)
	_cave_shell_shadow_proxy = sp


func _build_chunked_cave_shell(shell: MeshInstance3D, cave_mesh: ArrayMesh, mat: Material) -> void:
	_cave_shell_chunks.clear()
	_cave_shell_shadow_proxy = null
	if cave_mesh.get_surface_count() == 0:
		return
	var arrs := cave_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return

	if ResourceLoader.exists(CAVE_SHELL_CHUNKS_PATH):
		var cached := load(CAVE_SHELL_CHUNKS_PATH) as ArrayMesh
		if cached != null and int(cached.get_meta("vert_count", -1)) == verts.size() and bool(cached.get_meta("has_shadow_proxy_v2", false)):
			var zids: PackedInt32Array = cached.get_meta("zids", PackedInt32Array())
			var aabbs: Array = cached.get_meta("aabbs", [])
			var chunk_surf_n := zids.size()
			if chunk_surf_n > 0 and chunk_surf_n <= cached.get_surface_count() and aabbs.size() == chunk_surf_n:
				var z1_aabb := AABB()
				for si in chunk_surf_n:
					var c_mesh := ArrayMesh.new()
					c_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cached.surface_get_arrays(si))
					var chunk_mi := MeshInstance3D.new()
					var zid := int(zids[si])
					chunk_mi.name = "CaveShellChunk_%d" % zid
					chunk_mi.set_meta("zid", zid)
					chunk_mi.mesh = c_mesh
					chunk_mi.material_override = mat
					chunk_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					chunk_mi.custom_aabb = aabbs[si] as AABB
					if zid == 1:
						z1_aabb = chunk_mi.custom_aabb
					shell.add_child(chunk_mi)
					_cave_shell_chunks.append(chunk_mi)
				if cached.get_surface_count() > chunk_surf_n:
					var sh_mesh := ArrayMesh.new()
					sh_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cached.surface_get_arrays(chunk_surf_n))
					_attach_shadow_proxy_node(shell, sh_mesh, z1_aabb)
				return

	var normals: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrs[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
	var has_nrm := normals.size() == verts.size()
	var has_col := colors.size() == verts.size()
	var has_uv := uvs.size() == verts.size()
	var use_idx := not indices.is_empty()
	var tri_count := (indices.size() if use_idx else verts.size()) / 3

	var zone_tris: Array[PackedInt32Array] = []
	for _z in 5:
		zone_tris.append(PackedInt32Array())
	for ti in tri_count:
		var b := ti * 3
		var i0 := indices[b] if use_idx else b
		var i1 := indices[b + 1] if use_idx else (b + 1)
		var i2 := indices[b + 2] if use_idx else (b + 2)
		var centroid := (verts[i0] + verts[i1] + verts[i2]) * (1.0 / 3.0)
		var zid := _cave_zone_for_world_pos(centroid)
		var zarr := zone_tris[zid]
		zarr.append(i0)
		zarr.append(i1)
		zarr.append(i2)

	var vmap_local := PackedInt32Array()
	vmap_local.resize(verts.size())
	var vmap_stamp := PackedInt32Array()
	vmap_stamp.resize(verts.size())
	var stamp := 0

	var cache_pack := ArrayMesh.new()
	var cache_zids := PackedInt32Array()
	var cache_aabbs: Array[AABB] = []

	for zid in 5:
		var tris := zone_tris[zid]
		if tris.is_empty():
			continue
		stamp += 1
		var c_verts := PackedVector3Array()
		var c_normals := PackedVector3Array()
		var c_colors := PackedColorArray()
		var c_uvs := PackedVector2Array()
		var c_indices := PackedInt32Array()
		c_indices.resize(tris.size())
		var min_pt := Vector3(INF, INF, INF)
		var max_pt := Vector3(-INF, -INF, -INF)

		for k in tris.size():
			var gi := tris[k]
			var li: int
			if vmap_stamp[gi] == stamp:
				li = vmap_local[gi]
			else:
				li = c_verts.size()
				vmap_stamp[gi] = stamp
				vmap_local[gi] = li
				var vp := verts[gi]
				c_verts.append(vp)
				if has_nrm:
					c_normals.append(normals[gi])
				if has_col:
					c_colors.append(colors[gi])
				if has_uv:
					c_uvs.append(uvs[gi])
				min_pt.x = minf(min_pt.x, vp.x)
				min_pt.y = minf(min_pt.y, vp.y)
				min_pt.z = minf(min_pt.z, vp.z)
				max_pt.x = maxf(max_pt.x, vp.x)
				max_pt.y = maxf(max_pt.y, vp.y)
				max_pt.z = maxf(max_pt.z, vp.z)
			c_indices[k] = li

		var c_arrs := []
		c_arrs.resize(Mesh.ARRAY_MAX)
		c_arrs[Mesh.ARRAY_VERTEX] = c_verts
		if has_nrm:
			c_arrs[Mesh.ARRAY_NORMAL] = c_normals
		if has_col:
			c_arrs[Mesh.ARRAY_COLOR] = c_colors
		if has_uv:
			c_arrs[Mesh.ARRAY_TEX_UV] = c_uvs
		c_arrs[Mesh.ARRAY_INDEX] = c_indices

		var c_mesh := ArrayMesh.new()
		c_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c_arrs)
		var chunk_aabb := AABB(min_pt, max_pt - min_pt).grow(0.5)
		var chunk_mi := MeshInstance3D.new()
		chunk_mi.name = "CaveShellChunk_%d" % zid
		chunk_mi.set_meta("zid", zid)
		chunk_mi.mesh = c_mesh
		chunk_mi.material_override = mat
		chunk_mi.cast_shadow = shell.cast_shadow
		chunk_mi.custom_aabb = chunk_aabb
		shell.add_child(chunk_mi)
		_cave_shell_chunks.append(chunk_mi)

		cache_pack.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c_arrs)
		cache_zids.append(zid)
		cache_aabbs.append(chunk_aabb)
		if zid == 1:
			var sh_proxy := _build_decimated_shadow_mesh(c_verts, c_indices, 1.65)
			if sh_proxy != null:
				_attach_shadow_proxy_node(shell, sh_proxy, chunk_aabb)

	if _cave_shell_shadow_proxy != null and _cave_shell_shadow_proxy.mesh is ArrayMesh:
		var shm := _cave_shell_shadow_proxy.mesh as ArrayMesh
		if shm.get_surface_count() > 0:
			cache_pack.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shm.surface_get_arrays(0))

	if cache_pack.get_surface_count() > 0:
		cache_pack.set_meta("vert_count", verts.size())
		cache_pack.set_meta("zids", cache_zids)
		cache_pack.set_meta("aabbs", cache_aabbs)
		cache_pack.set_meta("has_shadow_proxy_v2", true)
		_save_cached_res(cache_pack, CAVE_SHELL_CHUNKS_PATH)


func _add_zoned_multimeshes(parent_node: Node3D, base_name: String, mesh: Mesh, xforms: Array, colors: Array, cast_shadow: GeometryInstance3D.ShadowCastingSetting, mat_ov: Material = null, vis_end: float = 0.0, vis_margin: float = 0.0, aabb_grow: float = 3.0) -> void:
	if parent_node == null or mesh == null or xforms.is_empty():
		return
	var zone_xfs: Array[Array] = [[], [], [], [], []]
	var zone_cols: Array[Array] = [[], [], [], [], []]
	var use_cols := colors.size() == xforms.size()
	for i in xforms.size():
		var xf: Transform3D = xforms[i] as Transform3D
		var zid := _cave_zone_for_world_pos(xf.origin)
		zone_xfs[zid].append(xf)
		if use_cols:
			zone_cols[zid].append(colors[i])

	for zid in 5:
		var zxfs: Array = zone_xfs[zid]
		if zxfs.is_empty():
			continue
		var min_pt := Vector3(INF, INF, INF)
		var max_pt := Vector3(-INF, -INF, -INF)
		for i in zxfs.size():
			var o: Vector3 = (zxfs[i] as Transform3D).origin
			min_pt.x = minf(min_pt.x, o.x)
			min_pt.y = minf(min_pt.y, o.y)
			min_pt.z = minf(min_pt.z, o.z)
			max_pt.x = maxf(max_pt.x, o.x)
			max_pt.y = maxf(max_pt.y, o.y)
			max_pt.z = maxf(max_pt.z, o.z)
		var center := (min_pt + max_pt) * 0.5

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = use_cols
		mm.mesh = mesh
		mm.instance_count = zxfs.size()
		var zcols: Array = zone_cols[zid]
		for i in zxfs.size():
			var xf: Transform3D = zxfs[i] as Transform3D
			xf.origin -= center
			mm.set_instance_transform(i, xf)
			if use_cols:
				mm.set_instance_color(i, zcols[i] as Color)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_Z%d" % [base_name, zid]
		mmi.position = center
		mmi.multimesh = mm
		mmi.cast_shadow = cast_shadow
		if mat_ov != null:
			mmi.material_override = mat_ov
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = vis_margin
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.custom_aabb = AABB(min_pt - center, max_pt - min_pt).grow(aabb_grow)
		parent_node.add_child(mmi)
		_zoned_mmis[zid].append(mmi)


func _build_interior_lighting_rig() -> void:
	var existing := get_node_or_null("CaveLighting")
	if existing != null:
		return
	var rig := Node3D.new()
	rig.name = "CaveLighting"
	add_child(rig)

	# Interior Ambient Override (kills outdoor sky-blue ambient leak on Mobile renderer)
	var probe := ReflectionProbe.new()
	probe.name = "CaveInteriorProbe"
	probe.interior = true
	probe.box_projection = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.38, 0.43, 0.52, 1.0)
	probe.ambient_color_energy = 0.65
	var p_center := CaveLayout.to_world(Vector3(-68.0, 24.0, 116.0))
	probe.basis = Basis(
		Vector3(CaveLayout.RIGHT_XZ.x, 0.0, CaveLayout.RIGHT_XZ.y),
		Vector3.UP,
		Vector3(-CaveLayout.FWD_XZ.x, 0.0, -CaveLayout.FWD_XZ.y)
	)
	probe.position = p_center
	probe.size = Vector3(286.0, 56.0, 244.0)
	rig.add_child(probe)

	# 1. KEY LIGHT (Shadowed): Sunbeam spot through the Cenote Skylight onto the Moss Mound
	var key_spot := SpotLight3D.new()
	key_spot.name = "SkylightKeySpot"
	var sky_c_spot: Vector3 = CaveLayout.SKYLIGHT["c"]
	var mound_c_spot: Vector3 = CaveLayout.MOUND["c"]
	var sky_from := CaveLayout.to_world(Vector3(sky_c_spot.x + 2.0, 64.0, sky_c_spot.z - 2.0))
	var sky_aim := CaveLayout.to_world(Vector3(mound_c_spot.x, 20.0, mound_c_spot.z))
	key_spot.light_color = Color(1.0, 0.95, 0.84, 1.0)
	key_spot.light_energy = 0.0
	key_spot.visible = false
	key_spot.spot_range = 74.0
	key_spot.spot_attenuation = 0.85
	key_spot.spot_angle = 40.0
	key_spot.spot_angle_attenuation = 2.05
	key_spot.shadow_enabled = true
	key_spot.light_cull_mask = 3
	key_spot.shadow_bias = 0.08
	key_spot.shadow_normal_bias = 0.2
	key_spot.shadow_blur = 0.0
	rig.add_child(key_spot)
	key_spot.look_at_from_position(sky_from, sky_aim, Vector3.UP)

	# 2-8. ACCENT LIGHTS (unshadowed omnis with tight range & falloff; total lights = 8 <= 8 budget):
	# Warm mound bounce, passage landmark beacons, cool grotto aqua fill, violet geode glow, lake glow, door torchlight
	var accents := [
		["CollapseBounceOmni", Vector3(-56.0, 26.5, 67.0), Color(0.98, 0.88, 0.72), 1.15, 29.0, 1.45],
		["TwilightArchOmni", Vector3(-34.0, 22.5, 42.0), Color(0.95, 0.78, 0.52), 1.35, 22.0, 1.50],
		["GrottoArchOmni", Vector3(-42.0, 20.8, 86.0), Color(0.32, 0.86, 0.98), 1.65, 24.0, 1.45],
		["SpiralLedgeStartOmni", Vector3(-73.0, 23.5, 81.0), Color(0.65, 0.55, 1.0), 1.45, 22.0, 1.45],
		["GeodeCrystalOmni", Vector3(5.5, 20.8, 55.0), Color(0.56, 0.72, 1.0), 4.20, 44.0, 0.85],
		["UndergroundLakeOmni", Vector3(-6.0, 15.2, 178.0), Color(0.58, 0.92, 1.00), 5.10, 116.0, 0.60],
		["VaultDoorOmni", Vector3(-183.6, 7.2, 66.4), Color(0.96, 0.80, 0.56), 3.65, 42.0, 0.96],
	]
	for a: Array in accents:
		var omni := OmniLight3D.new()
		omni.name = String(a[0])
		omni.position = CaveLayout.to_world(a[1] as Vector3)
		omni.light_color = a[2] as Color
		omni.light_energy = float(a[3])
		omni.omni_range = float(a[4])
		omni.omni_attenuation = float(a[5])
		omni.shadow_enabled = false
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = 55.0
		omni.distance_fade_length = 20.0
		rig.add_child(omni)


# ==============================================================================
# NAVIGATION CORRIDOR SAFETY & SDF SURFACE QUERIES
# ==============================================================================

static func _dist_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _is_clear_of_all_routes(u: float, s: float, min_clear: float) -> bool:
	var pt := Vector2(u, s)
	# Keep player spawn point open
	if pt.distance_to(Vector2(CaveLayout.SPAWN.x, CaveLayout.SPAWN.z)) < min_clear + 2.2:
		return false
	# Keep Geode core & landing clear
	var gc: Vector3 = CaveLayout.CHAMBERS["geode_pocket"]["c"]
	if pt.distance_to(Vector2(gc.x, gc.z)) < min_clear + 1.5:
		return false
	# Keep Collapse Hall central walk point clear
	if pt.distance_to(Vector2(-52.0, 74.0)) < min_clear + 1.5:
		return false
	# Keep Abyssal Atrium center hub clear
	var aa_c: Vector3 = CaveLayout.CHAMBERS["abyssal_atrium"]["c"]
	if pt.distance_to(Vector2(aa_c.x, aa_c.z)) < min_clear + 2.0:
		return false
	# Keep Underground Lake promenade entrance clear
	var lake_nodes_cl: Array = CaveLayout.TUNNELS["lake_tunnel"]
	var lake_entry_pt: Vector3 = lake_nodes_cl[lake_nodes_cl.size() - 1]["p"]
	if pt.distance_to(Vector2(lake_entry_pt.x, lake_entry_pt.z)) < min_clear + 2.0:
		return false
	# Keep Ancient Door dais and frontal approach clear
	if pt.distance_to(Vector2(-182.0, 68.0)) < min_clear + 3.0:
		return false

	for tname: String in ["twilight_passage", "hall_throat", "stream_grotto", "split_crawlway", "deep_descent", "lake_tunnel", "lake_shoreline", "door_tunnel"]:
		var nodes: Array = CaveLayout.TUNNELS[tname]
		var req := min_clear + (2.0 if tname == "split_crawlway" else (4.2 if tname == "lake_shoreline" else 1.6))
		for i in range(nodes.size() - 1):
			var pa: Vector3 = nodes[i]["p"]
			var pb: Vector3 = nodes[i + 1]["p"]
			if _dist_to_segment_2d(pt, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)) < req:
				return false

	# Also keep explicit split-crawlway entry corridor clear
	if _dist_to_segment_2d(pt, Vector2(-32.0, 40.5), Vector2(-27.0, 42.5)) < min_clear + 2.2:
		return false

	# Keep Spiral Ledge Exit corridor wide open
	var lpts := CaveLayout.LEDGE_ROUTE
	for i in range(lpts.size() - 1):
		var pa: Vector3 = lpts[i]
		var pb: Vector3 = lpts[i + 1]
		if _dist_to_segment_2d(pt, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)) < min_clear + 2.5:
			return false

	return true


static func _sample_ceiling_y(sdf: CaveSDF, u: float, y_start: float, s: float, y_max: float = 54.0) -> float:
	var y := y_start
	var prev_f := sdf.eval_sdf_full(u, y, s, GEOFENCE_OVERWORLD_H)
	while y < y_max:
		y += 0.6
		var cur_f := sdf.eval_sdf_full(u, y, s, GEOFENCE_OVERWORLD_H)
		if prev_f < 0.0 and cur_f >= 0.0:
			var lo := y - 0.6
			var hi := y
			for _i in 4:
				var mid := 0.5 * (lo + hi)
				if sdf.eval_sdf_full(u, mid, s, GEOFENCE_OVERWORLD_H) >= 0.0:
					hi = mid
				else:
					lo = mid
			return 0.5 * (lo + hi)
		prev_f = cur_f
	return y_max


static func _sample_floor_y(sdf: CaveSDF, u: float, y_start: float, s: float) -> float:
	var wp := CaveLayout.to_world(Vector3(u, y_start, s))
	return sample_sdf_floor_below(wp.x, wp.z, y_start, GEOFENCE_OVERWORLD_H).w


static func _sample_exterior_sdf_y(sdf: CaveSDF, terrain_scene: Node3D, u: float, s: float) -> float:
	var w_xz := CaveLayout.to_world(Vector3(u, 26.0, s))
	var ov_h := float(terrain_scene.call("sample_height", w_xz.x, w_xz.z)) if terrain_scene != null else CaveLayout.ORIGIN.y
	var y_top := maxf(ov_h + 6.0, 38.0)
	var y_prev := y_top
	var prev_f := sdf.eval_sdf_full(u, y_prev, s, ov_h)
	var y_cur := y_prev - 0.5
	while y_cur >= 20.0:
		var cur_f := sdf.eval_sdf_full(u, y_cur, s, ov_h)
		if prev_f < 0.0 and cur_f >= 0.0:
			var lo := y_cur
			var hi := y_prev
			for _b in 5:
				var mid := 0.5 * (lo + hi)
				if sdf.eval_sdf_full(u, mid, s, ov_h) >= 0.0:
					lo = mid
				else:
					hi = mid
			return 0.5 * (lo + hi)
		y_prev = y_cur
		prev_f = cur_f
		y_cur -= 0.5
	return ov_h


# ==============================================================================
# P2: KITBASHED BOULDERS, ENTRANCE BROW TREE & FALLEN MOUND DEADWOOD LOG
# ==============================================================================

static var _extracted_mesh_cache: Dictionary = {}
static var _cached_rock_convex_shapes: Array[ConvexPolygonShape3D] = []
static var _cached_rock_meshes: Array[Mesh] = []


func _load_rock_meshes() -> Array[Mesh]:
	if not _cached_rock_meshes.is_empty():
		return _cached_rock_meshes

	var rock_mat := StandardMaterial3D.new()
	var rock_tex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
	if rock_tex != null:
		rock_mat.albedo_texture = rock_tex
	rock_mat.albedo_color = Color(0.84, 0.82, 0.78)
	rock_mat.roughness = 0.92
	rock_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	rock_mat.cull_mode = BaseMaterial3D.CULL_BACK

	var out: Array[Mesh] = []
	for p: String in [
		"res://assets/nature/Rock_Medium_1.gltf",
		"res://assets/nature/Rock_Medium_2.gltf",
		"res://assets/nature/Rock_Medium_3.gltf",
	]:
		var sc := load(p) as PackedScene
		var found: Mesh = null
		if sc != null:
			var inst := sc.instantiate()
			for c in inst.get_children():
				if c is MeshInstance3D and c.mesh != null:
					found = c.mesh.duplicate()
					break
			inst.free()
		if found != null:
			found.surface_set_material(0, rock_mat)
		out.append(found)
	_cached_rock_meshes = out
	return out


func _build_rock_convex_shapes(rock_meshes: Array[Mesh]) -> Array[ConvexPolygonShape3D]:
	if not _cached_rock_convex_shapes.is_empty():
		return _cached_rock_convex_shapes

	var shapes: Array[ConvexPolygonShape3D] = []
	for m: Mesh in rock_meshes:
		if m != null:
			shapes.append(m.create_convex_shape(false, false))
		else:
			shapes.append(null)
	_cached_rock_convex_shapes = shapes
	return shapes


func _extract_surface_mesh(gltf_path: String, surface_indices: Array[int], mats: Array[Material]) -> Mesh:
	var key := "%s_%s" % [gltf_path, str(surface_indices)]
	if _extracted_mesh_cache.has(key):
		return _extracted_mesh_cache[key]

	var sc := load(gltf_path) as PackedScene
	if sc == null:
		return null
	var inst := sc.instantiate()
	var src: Mesh = null
	for c in inst.get_children():
		if c is MeshInstance3D and c.mesh != null:
			src = c.mesh
			break
	var out_mesh: ArrayMesh = null
	if src != null:
		out_mesh = ArrayMesh.new()
		for i in surface_indices.size():
			var si := surface_indices[i]
			if si < src.get_surface_count():
				var arr := src.surface_get_arrays(si)
				var s_idx := out_mesh.get_surface_count()
				out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				if i < mats.size() and mats[i] != null:
					out_mesh.surface_set_material(s_idx, mats[i])
	inst.free()
	_extracted_mesh_cache[key] = out_mesh
	return out_mesh


static func compute_cave_props(terrain_scene: Node3D, seed_val: int = 1337) -> Dictionary:
	var sdf := get_sdf()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 9091

	# --- 1. BOULDERS ---
	var grouped: Array[Array] = [[], [], []]
	var collider_items: Array[Dictionary] = []
	var add_boulder := func(arch: int, wp: Vector3, rot: Vector3, sc: Vector3, collide: bool) -> void:
		var b := Basis.from_euler(rot).scaled(sc)
		var xf := Transform3D(b, wp)
		grouped[arch % 3].append(xf)
		if collide:
			collider_items.append({"arch": arch % 3, "xf": xf})

	var mouth_boulders := [
		[Vector3(-7.6, 0.0, -3.5), 1.9, true],
		[Vector3(-10.5, 0.0, -6.5), 1.7, true],
		[Vector3(-12.2, 0.0, -3.2), 2.1, true],
		[Vector3(-8.4, 0.0, -7.2), 1.4, true],
		[Vector3(7.6, 0.0, -3.8), 1.9, true],
		[Vector3(10.5, 0.0, -6.5), 1.7, true],
		[Vector3(12.2, 0.0, -2.8), 2.1, true],
		[Vector3(8.2, 0.0, -7.4), 1.3, true],
	]
	for idx in mouth_boulders.size():
		var item: Array = mouth_boulders[idx]
		var loc: Vector3 = item[0]
		var sc_base: float = float(item[1])
		var w_xz := CaveLayout.to_world(loc)
		var sdf_y := _sample_exterior_sdf_y(sdf, terrain_scene, loc.x, loc.z)
		var ov_y := float(terrain_scene.call("sample_height", w_xz.x, w_xz.z)) if terrain_scene != null else sdf_y
		var gy := minf(sdf_y, ov_y)
		if gy < 25.0 or gy > 31.0:
			continue
		var arch := idx % 3
		var sx := sc_base * rng.randf_range(0.95, 1.25)
		var sy := sc_base * rng.randf_range(0.75, 1.02)
		var sz := sc_base * rng.randf_range(0.95, 1.25)
		var rot := Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))
		add_boulder.call(arch, Vector3(w_xz.x, gy - 0.78 * sy, w_xz.z), rot, Vector3(sx, sy, sz), bool(item[2]))

	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	var rim_angles := [0.65, 1.35, 2.10, 2.85, 3.60, 4.35, 5.10]
	for idx in rim_angles.size():
		var ang: float = rim_angles[idx]
		var r := rng.randf_range(12.2, 15.2)
		var lu := (sky_c.x - 0.8) + cos(ang) * r
		var ls := sky_c.z + sin(ang) * r
		if not _is_clear_of_all_routes(lu, ls, 2.8):
			continue
		var w_xz := CaveLayout.to_world(Vector3(lu, 56.0, ls))
		var ov_y := float(terrain_scene.call("sample_height", w_xz.x, w_xz.z)) if terrain_scene != null else _sample_exterior_sdf_y(sdf, terrain_scene, lu, ls)
		if ov_y < 52.0 or ov_y > 61.0:
			continue
		if sdf.eval_cave_void_smooth(lu, ov_y - 2.2, ls) <= 0.6:
			continue
		var sc_base := rng.randf_range(1.2, 1.8)
		add_boulder.call(
			idx % 3,
			Vector3(w_xz.x, ov_y - 0.70 * sc_base, w_xz.z),
			Vector3(rng.randf_range(-0.14, 0.14), rng.randf_range(0.0, TAU), rng.randf_range(-0.14, 0.14)),
			Vector3(sc_base * 1.15, sc_base * 0.8, sc_base),
			true
		)

	var hall_blocks := [
		[-64.5, 67.0, 1.5], [-68.0, 65.5, 1.7], [-66.5, 72.5, 1.8], [-62.0, 74.5, 1.4],
		[-70.5, 69.0, 2.0], [-72.0, 64.0, 1.6], [-59.0, 75.5, 1.3],
		[-38.5, 44.5, 1.3], [-36.5, 37.5, 1.2], [-27.5, 37.0, 1.2],
	]
	for idx in hall_blocks.size():
		var b_arr: Array = hall_blocks[idx]
		var lu: float = float(b_arr[0])
		var ls: float = float(b_arr[1])
		if not _is_clear_of_all_routes(lu, ls, 2.6):
			continue
		var fy := _sample_floor_y(sdf, lu, 25.0, ls)
		var sc_base: float = float(b_arr[2])
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.35 * sc_base, ls))
		add_boulder.call(
			(idx + 1) % 3,
			wp,
			Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0.0, TAU), rng.randf_range(-0.22, 0.22)),
			Vector3(sc_base * 1.15, sc_base * 0.85, sc_base),
			true
		)

	var brow_loc := Vector3(-19.5, 38.0, 14.5)
	var brow_w := CaveLayout.to_world(brow_loc)
	var brow_ov_y := float(terrain_scene.call("sample_height", brow_w.x, brow_w.z)) if terrain_scene != null else _sample_exterior_sdf_y(sdf, terrain_scene, brow_loc.x, brow_loc.z)
	var bt_basis := Basis.from_euler(Vector3(0.04, 0.55, -0.08)).scaled(Vector3(2.25, 2.35, 2.25))
	var brow_tree_xf := Transform3D(bt_basis, Vector3(brow_w.x, brow_ov_y - 1.15, brow_w.z))

	var log_base_u := -65.5
	var log_base_s := 71.2
	var log_fy := _sample_floor_y(sdf, log_base_u, 25.0, log_base_s)
	var log_wp := CaveLayout.to_world(Vector3(log_base_u, log_fy + 0.55, log_base_s))
	var log_basis := Basis.from_euler(Vector3(1.42, 0.65, 0.14)).scaled(Vector3(1.95, 2.05, 1.95))
	var fallen_log_xf := Transform3D(log_basis, log_wp)
	var trunk_dir := (log_basis.y).normalized()
	var log_cs_xf := Transform3D(log_basis.orthonormalized(), log_wp + trunk_dir * 3.1)

	# --- 2. CRYSTALS ---
	var crystal_xforms: Array[Transform3D] = []
	var crystal_colors: Array[Color] = []
	var palette := [
		Color(0.08, 0.85, 1.0),
		Color(0.20, 0.42, 1.0),
		Color(0.62, 0.22, 1.0),
		Color(0.10, 0.94, 0.72),
	]
	var gc: Vector3 = CaveLayout.CHAMBERS["geode_pocket"]["c"]
	var seed_pt := Vector3(gc.x, gc.y + 1.8, gc.z)
	for _c in 22:
		var az := (float(_c) / 22.0) * TAU + rng.randf_range(-0.10, 0.10)
		var el := rng.randf_range(-0.32, -0.04)
		var d_loc := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)).normalized()
		var r_hit := -1.0
		var r_cur := 3.6
		var r_prev := r_cur
		var prev_d := sdf.eval_sdf_full(seed_pt.x + d_loc.x * r_cur, seed_pt.y + d_loc.y * r_cur, seed_pt.z + d_loc.z * r_cur, GEOFENCE_OVERWORLD_H)
		while r_cur < 11.2:
			r_prev = r_cur
			r_cur += 0.36
			var hp := seed_pt + d_loc * r_cur
			var cur_d := sdf.eval_sdf_full(hp.x, hp.y, hp.z, GEOFENCE_OVERWORLD_H)
			if prev_d < 0.0 and cur_d >= 0.0:
				var lo := r_prev
				var hi := r_cur
				for _bs in 5:
					var mid := 0.5 * (lo + hi)
					var mp := seed_pt + d_loc * mid
					if sdf.eval_sdf_full(mp.x, mp.y, mp.z, GEOFENCE_OVERWORLD_H) >= 0.0:
						hi = mid
					else:
						lo = mid
				r_hit = hi
				break
			prev_d = cur_d
		if r_hit < 0.0:
			continue
		var lp := seed_pt + d_loc * r_hit
		if lp.z > 59.5 and absf(lp.x - gc.x) < 4.5:
			continue
		if lp.x < -0.5 and lp.z > 50.5 and lp.z < 59.5:
			continue
		if lp.x > gc.x + 2.5 and lp.z > 47.0 and lp.z < 58.5:
			continue
		if lp.y < gc.y + 0.1 or lp.y > gc.y + 2.6:
			continue
		var eps := 0.35
		var gx := sdf.eval_sdf_full(lp.x + eps, lp.y, lp.z, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(lp.x - eps, lp.y, lp.z, GEOFENCE_OVERWORLD_H)
		var gy := sdf.eval_sdf_full(lp.x, lp.y + eps, lp.z, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(lp.x, lp.y - eps, lp.z, GEOFENCE_OVERWORLD_H)
		var gz := sdf.eval_sdf_full(lp.x, lp.y, lp.z + eps, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(lp.x, lp.y, lp.z - eps, GEOFENCE_OVERWORLD_H)
		var n_loc := Vector3(-gx, -gy, -gz).normalized()
		if n_loc.length_squared() < 0.1:
			n_loc = -d_loc
		# Only spawn clusters on upward-sloped shelves/floor margins so vertical crags don't slice them in half
		if n_loc.y < 0.20:
			continue
		var n_world := Vector3(
			CaveLayout.FWD_XZ.x * n_loc.z + CaveLayout.RIGHT_XZ.x * n_loc.x,
			clampf(n_loc.y, 0.25, 0.96),
			CaveLayout.FWD_XZ.y * n_loc.z + CaveLayout.RIGHT_XZ.y * n_loc.x
		).normalized()
		var w_anchor := CaveLayout.to_world(lp - n_loc * 0.14)
		var shards := rng.randi_range(1, 2)
		var cluster_col: Color = palette[rng.randi() % palette.size()]
		for _s in shards:
			var splay := Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(0.10, 0.36), rng.randf_range(-0.18, 0.18))
			var s_dir := (n_world + splay).normalized()
			var b := _basis_align_y(s_dir, rng.randf() * TAU)
			var sc_h := rng.randf_range(1.05, 1.72)
			var sc_w := sc_h * rng.randf_range(1.00, 1.14)
			b = b.scaled(Vector3(sc_w, sc_h, sc_w))
			var lat := splay * 0.45
			crystal_xforms.append(Transform3D(b, w_anchor + Vector3(lat.x, 0.0, lat.z)))
			crystal_colors.append(cluster_col)

	# Landmark guiding crystal clusters framing Collapse Hall passage mouths & Spiral Ledge route
	var landmark_clusters := [
		# Stream Grotto archway left & right pillars (aqua/cyan beacons)
		[Vector3(-46.5, 19.5, 84.5), Color(0.08, 0.88, 1.0), 1.35, 3],
		[Vector3(-38.0, 19.5, 86.5), Color(0.14, 0.78, 1.0), 1.25, 2],
		# Spiral Ledge trailhead & upper ledge waypoints (violet/amethyst beacons)
		[Vector3(-68.5, 21.5, 82.0), Color(0.62, 0.26, 1.0), 1.30, 3],
		[Vector3(-76.5, 25.0, 74.5), Color(0.54, 0.32, 1.0), 1.15, 2],
		[Vector3(-74.0, 31.0, 56.5), Color(0.32, 0.56, 1.0), 1.15, 2],
		[Vector3(-56.0, 37.5, 51.0), Color(0.16, 0.84, 1.0), 1.15, 2],
		# Deep Descent East archway left & right pillars off Geode Pocket (cyan/blue beacons)
		[Vector3(9.2, 14.8, 46.2), Color(0.18, 0.76, 1.0), 1.35, 3],
		[Vector3(11.8, 14.8, 55.2), Color(0.20, 0.62, 1.0), 1.35, 3],
		# Deep Descent sweeping bend shoulder beacon (cool aqua/blue)
		[Vector3(30.2, 12.6, 72.8), Color(0.12, 0.78, 1.0), 1.30, 2],
		# Abyssal Atrium East Alcove beacon (cyan/violet)
		[Vector3(49.5, 10.6, 110.0), Color(0.10, 0.88, 0.96), 1.40, 3],
		# Split-Slime Crawlway mouth teaser crystals (warm violet/cyan)
		[Vector3(-29.5, 19.2, 43.2), Color(0.64, 0.28, 1.0), 0.90, 2],
		# Abyssal Atrium to Underground Lake NNE promenade archway beacon (radiant cyan)
		[Vector3(14.5, 7.8, 134.5), Color(0.08, 0.90, 0.94), 1.45, 3],
		# SE Rocky Reef Islet & South Peninsula glowing crystal landmarks inside Underground Lake
		[Vector3(10.0, 8.0, 176.0), Color(0.10, 0.92, 1.0), 1.28, 3],
		[Vector3(-2.7, 7.6, 199.2), Color(0.24, 0.68, 1.0), 1.24, 3],
		# Door Tunnel entrance flanks off WSW Lake Promenade (warm amber beacons)
		[Vector3(-58.2, 7.2, 190.6), Color(1.0, 0.64, 0.16), 1.32, 3],
		[Vector3(-63.8, 7.2, 200.2), Color(1.0, 0.64, 0.16), 1.32, 2],
		# Door Tunnel S-curve midpoint beacon (warm amber)
		[Vector3(-120.0, 4.0, 146.0), Color(1.0, 0.62, 0.14), 1.30, 2],
		# Ancient Big Door forecourt flank (monumental gold beacon)
		[Vector3(-185.0, 3.0, 72.0), Color(1.0, 0.60, 0.14), 1.65, 3],
	]
	for lc_item: Array in landmark_clusters:
		var lpos: Vector3 = lc_item[0]
		var lcol: Color = lc_item[1]
		var lscale: float = float(lc_item[2])
		var lcnt: int = int(lc_item[3])
		var fy_c := _sample_floor_y(sdf, lpos.x, lpos.y + 3.0, lpos.z)
		var w_base := CaveLayout.to_world(Vector3(lpos.x, fy_c - 0.08, lpos.z))
		for s_idx in lcnt:
			var ang_c := (float(s_idx) / float(lcnt)) * TAU + rng.randf_range(-0.18, 0.18)
			var tilt_c := 0.08 if s_idx == 0 else rng.randf_range(0.18, 0.36)
			var dir_c := Vector3(cos(ang_c) * sin(tilt_c), cos(tilt_c), sin(ang_c) * sin(tilt_c)).normalized()
			var b_c := _basis_align_y(dir_c, rng.randf() * TAU)
			var sh := lscale * (1.28 if s_idx == 0 else rng.randf_range(0.84, 1.08))
			var sw := sh * rng.randf_range(1.00, 1.12)
			b_c = b_c.scaled(Vector3(sw, sh, sw))
			var off_xz := Vector3(0.0, 0.0, 0.0) if s_idx == 0 else Vector3(cos(ang_c) * 0.55, 0.0, sin(ang_c) * 0.55)
			crystal_xforms.append(Transform3D(b_c, w_base + off_xz))
			crystal_colors.append(lcol)

	# 2a-small. Scattered Small & Micro Crystal Fragments across Collapse Hall Spawn Mound,
	# Hall Throat, Breakdown Fork, Split Crawlway, Stream Grotto, Geode Pocket & Deep Descent
	# (sized sh = 0.24..0.58 so the super-small 0.36x cave-spawn slime and its split clones can forage immediately)
	var frag_rng := RandomNumberGenerator.new()
	frag_rng.seed = seed_val + 44117
	var frag_zones := [
		# Collapse Hall Spawn Mound & Skylight rim ring (immediate starter forage!)
		[Vector3(-56.5, 21.4, 62.5), 2.0, 9.5, 18, 0.24, 0.42],
		[Vector3(-60.5, 19.5, 70.0), 3.0, 13.5, 14, 0.26, 0.48],
		# Hall Throat & Breakdown Fork
		[Vector3(-42.0, 20.5, 51.0), 1.5, 7.5, 10, 0.28, 0.50],
		[Vector3(-32.5, 23.5, 41.5), 1.5, 7.0, 8, 0.26, 0.48],
		# Split-Slime Crawlway interior reward trail
		[Vector3(-18.0, 21.2, 47.5), 0.4, 2.2, 5, 0.24, 0.38],
		[Vector3(-8.0, 18.2, 51.5), 0.4, 2.2, 5, 0.24, 0.38],
		# Stream Grotto & Geode Pocket floor fragments
		[Vector3(-24.0, 17.2, 97.0), 1.0, 5.5, 8, 0.30, 0.54],
		[Vector3(2.0, 15.2, 56.0), 1.5, 5.2, 10, 0.28, 0.54],
		# Deep Descent & Abyssal Atrium floor fragments
		[Vector3(36.0, 12.0, 82.0), 1.5, 6.5, 8, 0.32, 0.58],
	]
	for fz: Array in frag_zones:
		var zc: Vector3 = fz[0]
		var r_min: float = float(fz[1])
		var r_max: float = float(fz[2])
		var f_cnt: int = int(fz[3])
		var sc_min: float = float(fz[4])
		var sc_max: float = float(fz[5])
		for fi in f_cnt:
			var ang_f := (float(fi) / float(maxi(f_cnt, 1))) * TAU + frag_rng.randf_range(-0.28, 0.28)
			var rad_f := lerpf(r_min, r_max, sqrt(frag_rng.randf()))
			var lu_f := zc.x + cos(ang_f) * rad_f
			var ls_f := zc.z + sin(ang_f) * rad_f
			# Keep immediate spawn center (r < 1.8m) clear so the slime doesn't spawn overlapping a shard
			if Vector2(lu_f - CaveLayout.SPAWN.x, ls_f - CaveLayout.SPAWN.z).length() < 1.85:
				continue
			if sdf.eval_cave_void_smooth(lu_f, zc.y + 1.1, ls_f) > -0.25:
				continue
			var fy_f := _sample_floor_y(sdf, lu_f, zc.y + 3.2, ls_f)
			if absf(fy_f - zc.y) > 4.2:
				continue
			var w_frag := CaveLayout.to_world(Vector3(lu_f, fy_f - 0.04, ls_f))
			var tilt_f := frag_rng.randf_range(0.06, 0.34)
			var t_ang := frag_rng.randf() * TAU
			var dir_f := Vector3(cos(t_ang) * sin(tilt_f), cos(tilt_f), sin(t_ang) * sin(tilt_f)).normalized()
			var sh_f := frag_rng.randf_range(sc_min, sc_max)
			var sw_f := sh_f * frag_rng.randf_range(0.96, 1.16)
			var b_f := _basis_align_y(dir_f, frag_rng.randf() * TAU).scaled(Vector3(sw_f, sh_f, sw_f))
			crystal_xforms.append(Transform3D(b_f, w_frag))
			crystal_colors.append(palette[(fi + int(absf(zc.x))) % palette.size()])

	# Dense Underwater Crystal Reef Groves across the Deep Abyssal Trench & Sculpted Underground Lake Depths
	var pit_c: Vector3 = CaveLayout.LAKE_ABYSS_PIT["c"]
	var pit_rx: float = float(CaveLayout.LAKE_ABYSS_PIT["rx"])
	var pit_rz: float = float(CaveLayout.LAKE_ABYSS_PIT["rz"])
	var pit_yaw: float = float(CaveLayout.LAKE_ABYSS_PIT["yaw"])
	var cy_pit := cos(pit_yaw)
	var sy_pit := sin(pit_yaw)
	var pit_palette := [
		Color(0.08, 0.92, 1.0),
		Color(0.12, 0.96, 0.80),
		Color(0.18, 0.56, 1.0),
		Color(0.56, 0.30, 1.0),
	]
	var lake_c: Vector3 = CaveLayout.UNDERGROUND_LAKE["c"]
	var placed_hubs: Array[Vector2] = [Vector2(pit_c.x, pit_c.z)]
	var placed_pods: Array[Vector2] = []

	var spawn_underwater_pod := func(lu_p: float, ls_p: float, min_pod_gap: float, min_pit_dist: float, target_sc: float, tilt_bias: Vector3, col_p: Color, sink_extra: float = 0.0) -> bool:
		var pt := Vector2(lu_p, ls_p)
		if pt.distance_to(Vector2(pit_c.x, pit_c.z)) < min_pit_dist:
			return false
		# Keep clear of dry karst islets and South Peninsula
		if pt.distance_to(Vector2(-17.0, 167.5)) < 6.4 or pt.distance_to(Vector2(10.0, 176.0)) < 6.0 or pt.distance_to(Vector2(-2.7, 199.2)) < 5.6:
			return false
		for prev_pod: Vector2 in placed_pods:
			if pt.distance_to(prev_pod) < min_pod_gap:
				return false
		var fy_p := _sample_floor_y(sdf, lu_p, 6.2, ls_p)
		if fy_p < 1.05 or fy_p > 4.25:
			return false
		var fx1 := _sample_floor_y(sdf, lu_p + 0.65, 6.2, ls_p)
		var fx0 := _sample_floor_y(sdf, lu_p - 0.65, 6.2, ls_p)
		var fz1 := _sample_floor_y(sdf, lu_p, 6.2, ls_p + 0.65)
		var fz0 := _sample_floor_y(sdf, lu_p, 6.2, ls_p - 0.65)
		var n_loc := Vector3(-(fx1 - fx0) / 1.3, 1.0, -(fz1 - fz0) / 1.3).normalized()
		var n_world := Vector3(
			CaveLayout.FWD_XZ.x * n_loc.z + CaveLayout.RIGHT_XZ.x * n_loc.x,
			clampf(n_loc.y, 0.52, 1.0),
			CaveLayout.FWD_XZ.y * n_loc.z + CaveLayout.RIGHT_XZ.y * n_loc.x
		).normalized()

		placed_pods.append(pt)
		var base_y := fy_p - 0.18 - sink_extra
		var w_base_p := CaveLayout.to_world(Vector3(lu_p, base_y, ls_p))
		# Strictly cap submerged crystal tips <= 4.95 m (1.45 m unobstructed below water_y = 6.40)
		var max_sh := clampf((4.95 - base_y) / 1.15, 0.50, 2.30)
		var sh_p := clampf(target_sc, 0.52, max_sh)
		var sw_p := sh_p * rng.randf_range(1.02, 1.18)
		var raw_dir := (Vector3(0.0, 1.0, 0.0) + tilt_bias).normalized()
		var s_dir := raw_dir.lerp(n_world, 0.36).normalized()
		var b_s := _basis_align_y(s_dir, rng.randf() * TAU).scaled(Vector3(sw_p, sh_p, sw_p))
		crystal_xforms.append(Transform3D(b_s, w_base_p))
		crystal_colors.append(col_p)
		return true

	var add_crystal_grove := func(hub_u: float, hub_s: float, hub_gap: float, pods_in_grove: int, spread_r: float, min_sc: float, max_sc: float, col_idx: int) -> void:
		var hub_pt := Vector2(hub_u, hub_s)
		if hub_pt.distance_to(Vector2(pit_c.x, pit_c.z)) < 3.05:
			return
		if hub_pt.distance_to(Vector2(-17.0, 167.5)) < 6.6 or hub_pt.distance_to(Vector2(10.0, 176.0)) < 6.2 or hub_pt.distance_to(Vector2(-2.7, 199.2)) < 5.8:
			return
		for prev_hub: Vector2 in placed_hubs:
			if hub_pt.distance_to(prev_hub) < hub_gap:
				return
		var fy_h := _sample_floor_y(sdf, hub_u, 6.2, hub_s)
		if fy_h < 1.08 or fy_h > 4.20:
			return
		placed_hubs.append(hub_pt)

		# Elongate grove along an organic tectonic fissure axis with tightly interlocking sibling pods
		var drift_ang := rng.randf() * TAU
		var core_sc := rng.randf_range(min_sc, max_sc)
		var core_tilt := Vector3(rng.randf_range(-0.14, 0.14), 0.0, rng.randf_range(-0.14, 0.14))
		spawn_underwater_pod.call(hub_u, hub_s, 0.52, 2.25, core_sc, core_tilt, pit_palette[col_idx % pit_palette.size()], 0.0)

		for gi in range(1, pods_in_grove):
			var t_g := float(gi) / float(maxi(pods_in_grove - 1, 1))
			# Bias pods into paired clusters & short fissures rather than uniform circles
			var f_ang := drift_ang + (PI if (gi % 2 == 1) else 0.0) + rng.randf_range(-0.82, 0.82)
			var dist_g := lerpf(0.66, spread_r, sqrt(t_g)) * rng.randf_range(0.84, 1.10)
			var pu := hub_u + cos(f_ang) * dist_g
			var ps := hub_s + sin(f_ang) * dist_g
			var out_v := CaveLayout.FWD_XZ * sin(f_ang) + CaveLayout.RIGHT_XZ * cos(f_ang)
			var tilt_mag := rng.randf_range(0.18, 0.38)
			var tilt_v := Vector3(out_v.x * tilt_mag, 0.0, out_v.y * tilt_mag)
			var sc_fac := lerpf(0.92, 0.56, t_g) * rng.randf_range(0.86, 1.10)
			var c_pick: Color = pit_palette[col_idx % pit_palette.size()] if (gi % 3 != 2) else pit_palette[(col_idx + 1) % pit_palette.size()]
			spawn_underwater_pod.call(pu, ps, 0.54, 2.15, core_sc * sc_fac, tilt_v, c_pick, 0.03)

	# 2a. Asymmetric Tectonic Reef Skirt directly interlocking with CaveAbyssalShards basalt base
	for si in 14:
		var ang_s := (float(si) / 14.0) * TAU + 0.18 * sin(float(si) * 2.1) + rng.randf_range(-0.10, 0.10)
		var r_skirt := 2.25 + 0.65 * (0.5 + 0.5 * cos(ang_s * 2.0 - 0.8)) + rng.randf_range(-0.22, 0.35)
		var lu_s := pit_c.x + cos(ang_s) * r_skirt
		var ls_s := pit_c.z + sin(ang_s) * r_skirt
		var out_s := CaveLayout.FWD_XZ * sin(ang_s) + CaveLayout.RIGHT_XZ * cos(ang_s)
		var tilt_s := Vector3(out_s.x * rng.randf_range(0.24, 0.44), 0.0, out_s.y * rng.randf_range(0.24, 0.44))
		spawn_underwater_pod.call(lu_s, ls_s, 0.72, 2.02, rng.randf_range(0.82, 1.38), tilt_s, pit_palette[si % pit_palette.size()], 0.05)

	# 2b. Dense Abyssal Trench Crystal Groves (18 tight multi-pod interlocking reefs filling the sculpted pit)
	var phi := 2.3999632
	for pi in 24:
		var ang_p := float(pi) * phi + rng.randf_range(-0.20, 0.20)
		var r_fac := lerpf(0.32, 0.98, sqrt((float(pi) + 0.5) / 24.0))
		# Modulate radial density organically so reefs form sweeping ridges + dark sand swim canyons
		var lx_e := cos(ang_p) * pit_rx * r_fac + rng.randf_range(-0.95, 0.95)
		var lz_e := sin(ang_p) * pit_rz * r_fac + rng.randf_range(-0.85, 0.85)
		var lu_p := pit_c.x + (lx_e * cy_pit - lz_e * sy_pit)
		var ls_p := pit_c.z + (lx_e * sy_pit + lz_e * cy_pit)
		var n_pods := 6 if (pi % 3 != 2) else 5
		add_crystal_grove.call(lu_p, ls_p, 2.45, n_pods, 1.92, 1.28, 2.05, pi)

	# 2c. Deep Sculpted Underground Lake Basins & ESE Channel Multi-Pod Crystal Groves
	for li in 30:
		var ang_l := float(li) * phi + 0.65
		var t_l := (float(li) + 0.5) / 30.0
		var r_l := lerpf(0.18, 0.78, sqrt(t_l))
		var shore_pt := CaveLayout.lake_shore_point(ang_l, r_l)
		var lu_l := shore_pt.x + rng.randf_range(-1.3, 1.3)
		var ls_l := shore_pt.y + rng.randf_range(-1.3, 1.3)
		if Vector2(lu_l - lake_c.x, ls_l - lake_c.z).length() > 40.0:
			continue
		var n_pods_l := 5 if (li % 2 == 0) else 4
		add_crystal_grove.call(lu_l, ls_l, 3.65, n_pods_l, 1.68, 1.05, 1.72, li + 2)

	# --- 3. PEBBLES ---
	var pebble_xforms: Array[Transform3D] = []
	var pool_c: Vector3 = CaveLayout.POOL["c"]
	var rx: float = float(CaveLayout.POOL["rx"])
	var rz: float = float(CaveLayout.POOL["rz"])
	for _i in 85:
		var ang := rng.randf() * TAU
		var rr := rng.randf_range(0.72, 1.15)
		var lu := pool_c.x + cos(ang) * rx * rr
		var ls := pool_c.z + sin(ang) * rz * rr
		var fy := _sample_floor_y(sdf, lu, 21.0, ls)
		if fy > 19.3:
			continue
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.02, ls))
		var scv := rng.randf_range(0.85, 2.35)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))).scaled(Vector3(scv, scv * 0.85, scv))
		pebble_xforms.append(Transform3D(b, wp))

	var grotto_nodes: Array = CaveLayout.TUNNELS["stream_grotto"]
	for i in range(grotto_nodes.size() - 1):
		var pa: Vector3 = grotto_nodes[i]["p"]
		var pb: Vector3 = grotto_nodes[i + 1]["p"]
		for _k in 24:
			var t := rng.randf()
			var p := pa.lerp(pb, t)
			var lu := p.x + rng.randf_range(-2.8, 2.8)
			var ls := p.z + rng.randf_range(-2.8, 2.8)
			var fy := _sample_floor_y(sdf, lu, p.y + 2.0, ls)
			if absf(fy - p.y) > 1.8:
				continue
			var wp := CaveLayout.to_world(Vector3(lu, fy - 0.02, ls))
			var scv := rng.randf_range(0.80, 2.15)
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))).scaled(Vector3(scv, scv * 0.85, scv))
			pebble_xforms.append(Transform3D(b, wp))

	# --- 4. SPELEOTHEMS ---
	var speleo_xforms: Array[Transform3D] = []
	var stalagmites: Array[Dictionary] = []
	var zones := [
		[-12.0, 27.0, 5.5, 10],
		[-49.0, 88.0, 9.5, 16],
		[-78.0, 72.0, 10.0, 14],
		[-22.0, 99.0, 4.5, 12],
	]
	for z_arr: Array in zones:
		var cu: float = float(z_arr[0])
		var cs: float = float(z_arr[1])
		var rad: float = float(z_arr[2])
		var cnt: int = int(z_arr[3])
		for _i in cnt:
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(rad * 0.45, rad)
			var lu := cu + cos(ang) * dist
			var ls := cs + sin(ang) * dist
			if Vector2(lu + 62.0, ls - 68.0).length() < 9.5:
				continue
			if sdf.eval_cave_void_smooth(lu, 22.0, ls) > -0.35:
				continue
			var cy := _sample_ceiling_y(sdf, lu, 22.0, ls, 49.0)
			if cy > 47.0 or cy < 22.5:
				continue
			var fy := _sample_floor_y(sdf, lu, 22.0, ls)
			var gap := cy - fy
			if gap < 4.5:
				continue

			var is_hero := rng.randf() < 0.16
			var len_top := rng.randf_range(3.2, 4.8) if is_hero else rng.randf_range(1.4, 3.0)
			len_top = minf(len_top, gap * 0.42)
			var w_top := len_top * rng.randf_range(0.30, 0.46)
			var b_top := Basis.from_euler(Vector3(PI, rng.randf() * TAU, 0.0)).scaled(Vector3(w_top, len_top, w_top))
			speleo_xforms.append(Transform3D(b_top, CaveLayout.to_world(Vector3(lu, cy + 0.25, ls))))

			if _is_clear_of_all_routes(lu, ls, 4.4) and Vector2(lu + 48.0, ls - 87.5).length() > 11.5:
				var len_bot := len_top * rng.randf_range(0.45, 0.78)
				var w_bot := len_bot * rng.randf_range(0.42, 0.58)
				var wp_bot := CaveLayout.to_world(Vector3(lu, fy - 0.22, ls))
				var b_bot := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).scaled(Vector3(w_bot, len_bot, w_bot))
				speleo_xforms.append(Transform3D(b_bot, wp_bot))
				stalagmites.append({
					"radius": maxf(0.45 * w_bot, 0.35),
					"height": len_bot,
					"pos": wp_bot + Vector3(0.0, len_bot * 0.5, 0.0)
				})

	# --- 5. FLORA ---
	var grass_xf: Array[Transform3D] = []
	var fern_xf: Array[Transform3D] = []
	var plant_xf: Array[Transform3D] = []
	var bush_xf: Array[Transform3D] = []
	var shelf_xf: Array[Transform3D] = []
	var grotto_mush_xf: Array[Transform3D] = []
	var mound_c: Vector3 = CaveLayout.MOUND["c"]

	for _i in 95:
		var ang := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 5.2
		var lu := mound_c.x + cos(ang) * rr
		var ls := mound_c.z + sin(ang) * rr
		if ls < 62.0 or ls > 72.5 or Vector2(lu - pool_c.x, ls - pool_c.z).length() < 12.2:
			continue
		if Vector2(lu - CaveLayout.SPAWN.x, ls - CaveLayout.SPAWN.z).length() < 2.2:
			continue
		var fy := _sample_floor_y(sdf, lu, 26.0, ls)
		if fy < 19.5 or fy > 25.0:
			continue
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.06, ls))
		var sc := rng.randf_range(0.45, 0.72) * (1.0 - 0.35 * smoothstep(3.0, 5.2, rr))
		grass_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * rng.randf_range(0.55, 0.78), sc)), wp))

	for _i in 44:
		var ang := rng.randf() * TAU
		var rr := rng.randf_range(1.6, 10.8)
		var lu := mound_c.x + cos(ang) * rr
		var ls := mound_c.z + sin(ang) * rr
		if Vector2(lu - CaveLayout.SPAWN.x, ls - CaveLayout.SPAWN.z).length() < 2.8:
			continue
		if _dist_to_segment_2d(Vector2(lu, ls), Vector2(-60.2, 57.0), Vector2(-55.5, 63.5)) < 3.5:
			continue
		if _dist_to_segment_2d(Vector2(lu, ls), Vector2(-59.5, 73.5), Vector2(-53.5, 81.5)) < 4.2:
			continue
		if ls < 59.5 or ls > 74.5 or Vector2(lu - pool_c.x, ls - pool_c.z).length() < 12.2:
			continue
		var fy := _sample_floor_y(sdf, lu, 26.0, ls)
		if fy < 19.2:
			continue
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.06, ls))
		if rng.randf() < 0.56:
			var fsc := rng.randf_range(0.30, 0.48)
			fern_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))).scaled(Vector3(fsc, fsc, fsc)), wp))
		else:
			var psc := rng.randf_range(0.85, 1.35)
			plant_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(psc, psc, psc)), wp))

	var bush_spots := [
		Vector3(-68.0, 22.0, 71.0), Vector3(-69.5, 22.0, 63.5), Vector3(-63.5, 21.0, 75.5),
	]
	for bpt: Vector3 in bush_spots:
		var fy := _sample_floor_y(sdf, bpt.x, bpt.y + 2.0, bpt.z)
		var bsc := rng.randf_range(0.85, 1.35)
		bush_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(bsc, bsc, bsc)), CaveLayout.to_world(Vector3(bpt.x, fy - 0.08, bpt.z))))

	for _i in 65:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var lu := side * rng.randf_range(4.2, 7.6)
		var ls := rng.randf_range(-11.2, -6.2)
		var w_xz := CaveLayout.to_world(Vector3(lu, 27.2, ls))
		var fy := _sample_exterior_sdf_y(sdf, terrain_scene, lu, ls)
		if terrain_scene != null:
			fy = minf(fy, float(terrain_scene.call("sample_height", w_xz.x, w_xz.z)))
		if fy < 25.8 or fy > 30.8:
			continue
		var gsc := rng.randf_range(0.85, 1.30)
		grass_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(gsc, gsc, gsc)), Vector3(w_xz.x, fy - 0.04, w_xz.z)))
		if rng.randf() < 0.16:
			var fsc := rng.randf_range(0.28, 0.42)
			fern_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(fsc, fsc, fsc)), Vector3(w_xz.x, fy - 0.05, w_xz.z)))

	if fallen_log_xf != Transform3D.IDENTITY:
		var trunk_axis := fallen_log_xf.basis.y.normalized()
		var trunk_origin := fallen_log_xf.origin
		for _i in 8:
			var d_along := rng.randf_range(1.2, 5.6)
			var ang := rng.randf_range(-0.9, 0.9)
			var outward := (fallen_log_xf.basis.x.normalized() * cos(ang) + Vector3.UP * sin(ang) * 0.4 + Vector3.UP * 0.4).normalized()
			var pos := trunk_origin + trunk_axis * d_along + outward * 0.42
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15)))
			var sc := rng.randf_range(0.75, 1.30)
			shelf_xf.append(Transform3D(b.scaled(Vector3(sc, sc, sc)), pos))

	for i in range(grotto_nodes.size() - 1):
		var pa: Vector3 = grotto_nodes[i]["p"]
		var pb: Vector3 = grotto_nodes[i + 1]["p"]
		var dir2 := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
		var right2 := Vector2(-dir2.y, dir2.x)
		for _c in 9:
			var t := rng.randf()
			var p := pa.lerp(pb, t)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var bank_dist := rng.randf_range(1.9, 4.1) * side
			var lu := p.x + right2.x * bank_dist + rng.randf_range(-0.6, 0.6)
			var ls := p.z + right2.y * bank_dist + rng.randf_range(-0.6, 0.6)
			if sdf.eval_cave_void_smooth(lu, p.y + 1.2, ls) > -0.1:
				continue
			var fy := _sample_floor_y(sdf, lu, p.y + 2.5, ls)
			if absf(fy - p.y) > 1.8:
				continue
			var msc := rng.randf_range(0.85, 1.65)
			grotto_mush_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))).scaled(Vector3(msc, msc * rng.randf_range(0.9, 1.25), msc)), CaveLayout.to_world(Vector3(lu, fy - 0.04, ls))))

	# Hairline wet shoreline pebbles right along the organic lake water's edge
	for _p in 76:
		var th_p := rng.randf() * TAU
		var rr_p := rng.randf_range(0.96, 1.05)
		var pt_p := CaveLayout.lake_shore_point(th_p, rr_p)
		var lu_p := pt_p.x
		var ls_p := pt_p.y
		var fy_p := _sample_floor_y(sdf, lu_p, 10.5, ls_p)
		if fy_p < 6.05 or fy_p > 7.65:
			continue
		var wp_p := CaveLayout.to_world(Vector3(lu_p, fy_p - 0.02, ls_p))
		var scv_p := rng.randf_range(0.90, 2.10)
		var b_p := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))).scaled(Vector3(scv_p, scv_p * 0.85, scv_p))
		pebble_xforms.append(Transform3D(b_p, wp_p))

	# Submerged limestone shoal & abyssal basin pebbles highlighting bathymetric depth across the lake floor
	for _sp in 72:
		var th_sp := rng.randf() * TAU
		var rr_sp := rng.randf_range(0.18, 0.90)
		var pt_sp := CaveLayout.lake_shore_point(th_sp, rr_sp)
		var lu_sp := pt_sp.x
		var ls_sp := pt_sp.y
		if Vector2(lu_sp + 17.0, ls_sp - 167.5).length() < 6.5 or Vector2(lu_sp - 10.0, ls_sp - 176.0).length() < 6.2:
			continue
		var fy_sp := _sample_floor_y(sdf, lu_sp, 6.3, ls_sp)
		if fy_sp < 1.25 or fy_sp > 6.10:
			continue
		var wp_sp := CaveLayout.to_world(Vector3(lu_sp, fy_sp - 0.03, ls_sp))
		var scv_sp := rng.randf_range(0.95, 2.35)
		var b_sp := Basis.from_euler(Vector3(rng.randf_range(-0.18, 0.18), rng.randf() * TAU, rng.randf_range(-0.18, 0.18))).scaled(Vector3(scv_sp, scv_sp * 0.78, scv_sp))
		pebble_xforms.append(Transform3D(b_sp, wp_sp))

	# Luminous cave mushrooms on the outer rocky verge outside the organic shoreline walkway
	for _m in 46:
		var th := rng.randf() * TAU
		var rr := rng.randf_range(1.32, 1.48)
		var pt_m := CaveLayout.lake_shore_point(th, rr)
		var lu := pt_m.x
		var ls := pt_m.y
		if not _is_clear_of_all_routes(lu, ls, 1.0):
			continue
		if sdf.eval_cave_void_smooth(lu, 8.8, ls) > -0.1:
			continue
		var fy := _sample_floor_y(sdf, lu, 11.0, ls)
		if fy < 7.1 or fy > 11.5:
			continue
		var msc := rng.randf_range(1.1, 2.0)
		grotto_mush_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))).scaled(Vector3(msc, msc * rng.randf_range(0.9, 1.3), msc)), CaveLayout.to_world(Vector3(lu, fy - 0.04, ls))))

	return {
		"boulders": {
			"grouped": grouped,
			"collider_items": collider_items,
			"brow_tree_xf": brow_tree_xf,
			"fallen_log_xf": fallen_log_xf,
			"log_cs_xf": log_cs_xf,
		},
		"crystals": {
			"xforms": crystal_xforms,
			"colors": crystal_colors,
		},
		"pebbles": {
			"xforms": pebble_xforms,
		},
		"speleothems": {
			"xforms": speleo_xforms,
			"stalagmites": stalagmites,
		},
		"flora": {
			"grass_xf": grass_xf,
			"fern_xf": fern_xf,
			"plant_xf": plant_xf,
			"bush_xf": bush_xf,
			"shelf_xf": shelf_xf,
			"grotto_mush_xf": grotto_mush_xf,
		}
	}


func _build_boulders_and_trees(
	terrain_scene: Node3D,
	boulder_body: StaticBody3D,
	rock_meshes: Array[Mesh],
	rock_shapes: Array[ConvexPolygonShape3D],
	_rng: RandomNumberGenerator = null,
	props_data: Dictionary = {}
) -> Transform3D:
	if props_data.is_empty():
		props_data = _load_or_compute_props(terrain_scene)
	var b_data: Dictionary = props_data.get("boulders", {})
	var grouped: Array = b_data.get("grouped", [[], [], []])
	var collider_items: Array = b_data.get("collider_items", [])
	var brow_tree_xf: Transform3D = b_data.get("brow_tree_xf", Transform3D.IDENTITY)
	var fallen_log_xf: Transform3D = b_data.get("fallen_log_xf", Transform3D.IDENTITY)
	var log_cs_xf: Transform3D = b_data.get("log_cs_xf", Transform3D.IDENTITY)

	var holder := Node3D.new()
	holder.name = "CaveBoulders"
	add_child(holder)

	for a in 3:
		var m: Mesh = rock_meshes[a] if a < rock_meshes.size() else null
		var xforms: Array = grouped[a] if a < grouped.size() else []
		_add_zoned_multimeshes(holder, "CaveRock%d" % (a + 1), m, xforms, [], GeometryInstance3D.SHADOW_CASTING_SETTING_ON, null, 0.0, 0.0, 5.0)

	if boulder_body != null:
		var body_rid := boulder_body.get_rid()
		PhysicsServer3D.body_clear_shapes(body_rid)
		_cave_boulder_shapes.clear()
		for c_item: Dictionary in collider_items:
			var arch: int = int(c_item["arch"])
			var conv: ConvexPolygonShape3D = rock_shapes[arch] if arch < rock_shapes.size() else null
			if conv != null:
				_cave_boulder_shapes.append(conv)
				PhysicsServer3D.body_add_shape(body_rid, conv.get_rid(), c_item["xf"] as Transform3D)

	var bark_mat := StandardMaterial3D.new()
	bark_mat.albedo_texture = load("res://assets/nature/Bark_NormalTree.png") as Texture2D
	bark_mat.normal_enabled = true
	bark_mat.normal_texture = load("res://assets/nature/Bark_NormalTree_Normal.png") as Texture2D
	bark_mat.roughness = 0.92
	bark_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_texture = load("res://assets/nature/Leaves_NormalTree_C.png") as Texture2D
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_mat.alpha_scissor_threshold = 0.45
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.roughness = 0.85
	leaf_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var brow_tree_mesh := _extract_surface_mesh("res://assets/nature/CommonTree_1.gltf", [0, 1], [bark_mat, leaf_mat])
	if brow_tree_mesh != null and brow_tree_xf != Transform3D.IDENTITY:
		var bt := MeshInstance3D.new()
		bt.name = "EntranceBrowTree"
		bt.mesh = brow_tree_mesh
		bt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		bt.transform = brow_tree_xf
		holder.add_child(bt)

	var dead_bark_mat := bark_mat.duplicate() as StandardMaterial3D
	dead_bark_mat.albedo_color = Color(0.76, 0.72, 0.66)
	var dead_trunk_mesh := _extract_surface_mesh("res://assets/nature/CommonTree_1.gltf", [0], [dead_bark_mat])
	if dead_trunk_mesh != null and fallen_log_xf != Transform3D.IDENTITY:
		var log_mi := MeshInstance3D.new()
		log_mi.name = "FallenDeadwoodLog"
		log_mi.mesh = dead_trunk_mesh
		log_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		log_mi.transform = fallen_log_xf
		holder.add_child(log_mi)

		if boulder_body != null and log_cs_xf != Transform3D.IDENTITY:
			var log_cs := CollisionShape3D.new()
			var log_cap := CapsuleShape3D.new()
			log_cap.radius = 0.68
			log_cap.height = 6.2
			log_cs.shape = log_cap
			log_cs.transform = log_cs_xf
			boulder_body.add_child(log_cs)

	return fallen_log_xf


# ==============================================================================
# P3: SUNBEAM SHAFTS, DUST MOTES & WAITOMO GLOWWORMS
# ==============================================================================

func _build_skylight_beams_and_dust() -> void:
	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	var mound_c: Vector3 = CaveLayout.MOUND["c"]
	var p_top := CaveLayout.to_world(Vector3(sky_c.x + 1.5, 50.8, sky_c.z - 1.5))
	var p_bot := CaveLayout.to_world(Vector3(mound_c.x, 19.6, mound_c.z))

	var beam_shader := load("res://terrain/cave_sunbeam.gdshader") as Shader
	if beam_shader != null:
		var specs := [
			[5.0, 10.6, 0.14, Color(1.0, 0.93, 0.74)],
			[3.4, 7.2, 0.18, Color(1.0, 0.94, 0.78)],
			[1.9, 4.0, 0.22, Color(1.0, 0.96, 0.84)],
		]
		var beams := Node3D.new()
		beams.name = "SkylightBeams"
		add_child(beams)
		var dir := (p_bot - p_top)
		var h_len := dir.length()
		var up_a := -dir.normalized()
		var ref := Vector3.FORWARD if absf(up_a.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var rt := ref.cross(up_a).normalized()
		var fw := up_a.cross(rt).normalized()

		for idx in specs.size():
			var sp: Array = specs[idx]
			var r_top: float = float(sp[0])
			var r_bot: float = float(sp[1])
			var segs := 18
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in segs:
				var a0 := (float(i) / float(segs)) * TAU
				var a1 := (float(i + 1) / float(segs)) * TAU
				var vt0 := Vector3(cos(a0) * r_top, 0.0, sin(a0) * r_top)
				var vt1 := Vector3(cos(a1) * r_top, 0.0, sin(a1) * r_top)
				var vb0 := Vector3(cos(a0) * r_bot, -h_len, sin(a0) * r_bot)
				var vb1 := Vector3(cos(a1) * r_bot, -h_len, sin(a1) * r_bot)
				var n0 := Vector3(cos(a0), 0.15, sin(a0)).normalized()
				var n1 := Vector3(cos(a1), 0.15, sin(a1)).normalized()

				st.set_normal(n0); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(vt0)
				st.set_normal(n1); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(vt1)
				st.set_normal(n1); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(vb1)

				st.set_normal(n0); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(vt0)
				st.set_normal(n1); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(vb1)
				st.set_normal(n0); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(vb0)

			var mi := MeshInstance3D.new()
			mi.name = "SunbeamCone%d" % idx
			mi.mesh = st.commit()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = beam_shader
			mat.set_shader_parameter("beam_color", sp[3] as Color)
			mat.set_shader_parameter("beam_intensity", float(sp[2]))
			mi.material_override = mat
			mi.transform = Transform3D(Basis(rt, up_a, fw), p_top)
			beams.add_child(mi)


# ==============================================================================
# P4: MULTI-PART BASALT-SOCKETED QUARTZ CRYSTALS & PROCEDURAL TEXTURES
# ==============================================================================

static func _get_crystal_striation_normal_tex() -> ImageTexture:
	if _crystal_striation_tex != null:
		return _crystal_striation_tex
	var size := 256
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var hfield := PackedFloat32Array()
	hfield.resize(size * size)
	for y in size:
		var v := float(y) / float(size)
		# Crisp, alias-free horizontal quartz growth striations (moderate harmonics prevent Moire)
		var band := sin(v * TAU * 9.0) * 0.36 + sin(v * TAU * 21.0 + 1.1) * 0.22 + sin(v * TAU * 37.0 + 2.4) * 0.11
		var step_notch := sin(v * TAU * 4.0 + sin(v * TAU * 2.0) * 0.35) * 0.28
		var h_row := band + step_notch
		for x in size:
			var u := float(x) / float(size)
			var diag_shear := sin((u * 3.0 + v * 7.0) * TAU) * 0.08
			var micro := sin((u * 11.0 - v * 5.0) * TAU) * 0.04
			var n := sin(float(x * 127 + y * 311)) * 43758.5453
			var grain := (n - floorf(n)) * 0.03
			hfield[y * size + x] = h_row + diag_shear + micro + grain
	for y in size:
		var ym := (y - 1 + size) % size
		var yp := (y + 1) % size
		for x in size:
			var xm := (x - 1 + size) % size
			var xp := (x + 1) % size
			var dx := (hfield[y * size + xp] - hfield[y * size + xm]) * 0.55
			var dy := (hfield[yp * size + x] - hfield[ym * size + x]) * 1.15
			var nrm := Vector3(-dx, -dy, 1.0).normalized()
			img.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5, 1.0))
	img.generate_mipmaps()
	_crystal_striation_tex = ImageTexture.create_from_image(img)
	return _crystal_striation_tex


static func _get_crystal_interior_tex() -> ImageTexture:
	if _crystal_interior_tex != null:
		return _crystal_interior_tex
	if ResourceLoader.exists(CRYSTAL_INTERIOR_TEX_PATH):
		var loaded := load(CRYSTAL_INTERIOR_TEX_PATH) as ImageTexture
		if loaded != null:
			_crystal_interior_tex = loaded
			return _crystal_interior_tex
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42069

	# Two-layer seamless periodic toroidal Voronoi grids (6x6 coarse cleavage + 9x9 secondary crystal panes)
	var n1 := 6
	var pts1: Array[Vector2] = []
	var hash1: Array[float] = []
	for cy in n1:
		for cx in n1:
			pts1.append(Vector2((float(cx) + rng.randf_range(0.14, 0.86)) / float(n1), (float(cy) + rng.randf_range(0.14, 0.86)) / float(n1)))
			hash1.append(rng.randf_range(0.22, 1.0))

	var n2 := 9
	var pts2: Array[Vector2] = []
	var hash2: Array[float] = []
	for cy in n2:
		for cx in n2:
			pts2.append(Vector2((float(cx) + rng.randf_range(0.12, 0.88)) / float(n2), (float(cy) + rng.randf_range(0.12, 0.88)) / float(n2)))
			hash2.append(rng.randf_range(0.20, 1.0))

	var eval_vor := func(u: float, v: float, n: int, pts: Array[Vector2], hashes: Array[float]) -> Vector3:
		var gx := int(floorf(u * float(n))) % n
		var gy := int(floorf(v * float(n))) % n
		var f1 := 9.0
		var f2 := 9.0
		var id_val := 0.5
		for oy in range(-1, 2):
			var ny := (gy + oy + n) % n
			for ox in range(-1, 2):
				var nx := (gx + ox + n) % n
				var idx := ny * n + nx
				var p: Vector2 = pts[idx]
				var dx := u - p.x
				if dx > 0.5: dx -= 1.0
				elif dx < -0.5: dx += 1.0
				var dy := v - p.y
				if dy > 0.5: dy -= 1.0
				elif dy < -0.5: dy += 1.0
				var d := sqrt(dx * dx + dy * dy) * float(n)
				if d < f1:
					f2 = f1
					f1 = d
					id_val = hashes[idx]
				elif d < f2:
					f2 = d
		return Vector3(f1, f2, id_val)

	for y in size:
		var v := float(y) / float(size)
		for x in size:
			var u := float(x) / float(size)
			var v1: Vector3 = eval_vor.call(u, v, n1, pts1, hash1)
			var v2: Vector3 = eval_vor.call(u, v, n2, pts2, hash2)
			var ridge1 := clampf(1.0 - clampf((v1.y - v1.x) / 0.14, 0.0, 1.0), 0.0, 1.0)
			var ridge2 := clampf(1.0 - clampf((v2.y - v2.x) / 0.16, 0.0, 1.0), 0.0, 1.0)
			var cleave := clampf(pow(ridge1, 1.45) * 0.82 + pow(ridge2, 1.8) * 0.55, 0.0, 1.0)
			var cell_bright := clampf(v1.z * 0.65 + v2.z * 0.35, 0.0, 1.0)
			var diag_veil := clampf(0.45 + 0.32 * sin((u * 2.0 + v * 3.0) * TAU + v1.x * 2.2) + 0.23 * (v2.z - 0.5), 0.0, 1.0)
			var h := sin(float(x * 73 + y * 197) + 1.9) * 9183.41
			var basalt_grain := clampf(0.28 + 0.44 * v1.z + 0.18 * v2.z + 0.14 * (h - floorf(h)), 0.0, 1.0)
			img.set_pixel(x, y, Color(cleave, cell_bright, diag_veil, basalt_grain))
	img.generate_mipmaps()
	_crystal_interior_tex = ImageTexture.create_from_image(img)
	_save_cached_res(_crystal_interior_tex, CRYSTAL_INTERIOR_TEX_PATH)
	return _crystal_interior_tex


## Adds one triangle with guaranteed Godot clockwise (CW) outward winding and flat face normal.
static func _add_tri_outward(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, uv0: Vector2, uv1: Vector2, uv2_v: Vector2, ref_center: Vector3, part_u: float = 1.0, col: Color = Color.WHITE, use_col: bool = false, part_v: float = 0.0) -> void:
	var n := (p2 - p0).cross(p1 - p0)
	if n.length_squared() < 1e-10:
		return
	var centroid := (p0 + p1 + p2) * 0.3333333 - ref_center
	var a0 := p0; var a1 := p1; var a2 := p2
	var u0 := uv0; var u1 := uv1; var u2 := uv2_v
	if n.dot(centroid) < 0.0:
		a1 = p2; a2 = p1
		u1 = uv2_v; u2 = uv1
		n = -n
	n = n.normalized()
	if use_col:
		st.set_color(col)
	st.set_uv2(Vector2(part_u, part_v))
	st.set_normal(n); st.set_uv(u0); st.add_vertex(a0)
	if use_col:
		st.set_color(col)
	st.set_uv2(Vector2(part_u, part_v))
	st.set_normal(n); st.set_uv(u1); st.add_vertex(a1)
	if use_col:
		st.set_color(col)
	st.set_uv2(Vector2(part_u, part_v))
	st.set_normal(n); st.set_uv(u2); st.add_vertex(a2)


## Builds a strictly planar-walled asymmetric chunky 6-sided quartz crystal prism (zero barrel bulge, zero needle point).
static func _add_chisel_crystal_to_st(
		st_t: SurfaceTool,
		base_pos: Vector3,
		dir_axis: Vector3,
		r_base: float,
		_r_waist_unused: float,
		r_shoulder: float,
		shaft_h: float,
		tip_h: float,
		twist: float,
		asym_x: float = 1.0,
		asym_z: float = 1.0,
		col: Color = Color.WHITE,
		use_col: bool = false,
		dbl_ended: bool = false,
		bot_tip_h: float = 0.35,
		part_u: float = 1.0,
		sharp_apex: bool = false
) -> void:
	var up_d := dir_axis.normalized()
	var ref := Vector3.FORWARD if absf(up_d.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var rx_ax := up_d.cross(ref).normalized()
	var rz_ax := rx_ax.cross(up_d).normalized()
	var xf := Basis(rx_ax, up_d, rz_ax).rotated(up_d, twist)

	var sides := 6
	# Angles CCW from +X with bold mineral facet variety (wide main slabs + crisp bevel flanks)
	var angs := [0.00, 0.88, 2.04, 3.12, 4.02, 5.18]
	var fmods := [1.10, 0.88, 1.08, 0.90, 1.12, 0.86]

	var sink_y := -0.10 if not dbl_ended else 0.0
	var taper := clampf(r_shoulder / maxf(r_base, 1e-4), 0.36, 0.96)
	var span_y := maxf(shaft_h - sink_y, 0.12)
	var h_cone := sink_y + span_y / (1.0 - taper)
	var cone_apex := Vector3(0.0, h_cone, 0.0)

	var base_loc: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	var ring_u: Array[Vector3] = []
	var max_sh_y := sink_y

	for i in sides:
		var ang: float = angs[i]
		var fm: float = fmods[i]
		var cx := cos(ang) * fm * asym_x
		var cz := sin(ang) * fm * asym_z
		var pb := Vector3(cx * r_base, sink_y, cz * r_base)
		base_loc.append(pb)
		ring_b.append(base_pos + xf * pb)
		# Coplanar edge lerp along pb -> cone_apex guarantees ALL 6 shaft quads remain strictly flat planes
		var base_t := 1.0 - taper
		var obl := 0.16 * cos(ang - 0.18)
		var rhomb := 0.045 if (i % 2 == 0) else -0.045
		var frac := clampf(base_t * (1.0 + obl + rhomb), base_t * 0.78, minf(0.72, base_t * 1.24))
		var pu := pb.lerp(cone_apex, frac)
		max_sh_y = maxf(max_sh_y, pu.y)
		ring_u.append(base_pos + xf * pu)

	var prism_ref := base_pos + up_d * (shaft_h * 0.45)
	var v_bot_uv := 0.28 if dbl_ended else 0.06
	var v_top_uv := 0.76
	for i in sides:
		var nxt := (i + 1) % sides
		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)
		# Single coplanar planar quad per crystal prism wall (part_v = 0.0 for shaft walls)
		_add_tri_outward(st_t, ring_b[i], ring_u[nxt], ring_b[nxt], Vector2(u0, v_bot_uv), Vector2(u1, v_top_uv), Vector2(u1, v_bot_uv), prism_ref, part_u, col, use_col, 0.0)
		_add_tri_outward(st_t, ring_b[i], ring_u[i], ring_u[nxt], Vector2(u0, v_bot_uv), Vector2(u0, v_top_uv), Vector2(u1, v_top_uv), prism_ref, part_u, col, use_col, 0.0)

	var top_y := maxf(tip_h, max_sh_y + r_shoulder * 0.30)
	if sharp_apex:
		var apex_pt := base_pos + xf * Vector3(r_shoulder * 0.20 * asym_x, top_y, -r_shoulder * 0.06 * asym_z)
		for i in sides:
			var nxt := (i + 1) % sides
			var u0 := float(i) / float(sides)
			var u1 := float(i + 1) / float(sides)
			_add_tri_outward(st_t, ring_u[i], apex_pt, ring_u[nxt], Vector2(u0, v_top_uv), Vector2(0.5 * (u0 + u1), 1.0), Vector2(u1, v_top_uv), prism_ref, part_u, col, use_col, 1.0)
	else:
		# Broad convex oblique chisel termination: +X ridge_hi connects {5, 0, 1}, -X ridge_lo connects {2, 3, 4}
		var lo_y := maxf(max_sh_y + 0.05, top_y - r_shoulder * 0.42)
		var ridge_hi := base_pos + xf * Vector3(r_shoulder * 0.30 * asym_x, top_y, -r_shoulder * 0.04 * asym_z)
		var ridge_lo := base_pos + xf * Vector3(-r_shoulder * 0.28 * asym_x, lo_y, r_shoulder * 0.05 * asym_z)
		_add_tri_outward(st_t, ring_u[5], ridge_hi, ring_u[0], Vector2(0.83, v_top_uv), Vector2(0.92, 1.0), Vector2(1.00, v_top_uv), prism_ref, part_u, col, use_col, 1.0)
		_add_tri_outward(st_t, ring_u[0], ridge_hi, ring_u[1], Vector2(0.00, v_top_uv), Vector2(0.10, 1.0), Vector2(0.17, v_top_uv), prism_ref, part_u, col, use_col, 1.0)
		_add_tri_outward(st_t, ring_u[1], ridge_lo, ridge_hi, Vector2(0.17, v_top_uv), Vector2(0.28, 0.96), Vector2(0.18, 1.0), prism_ref, part_u, col, use_col, 1.0)
		_add_tri_outward(st_t, ring_u[1], ring_u[2], ridge_lo, Vector2(0.17, v_top_uv), Vector2(0.33, v_top_uv), Vector2(0.28, 0.96), prism_ref, part_u, col, use_col, 1.0)
		_add_tri_outward(st_t, ring_u[2], ring_u[3], ridge_lo, Vector2(0.33, v_top_uv), Vector2(0.50, v_top_uv), Vector2(0.42, 0.96), prism_ref, part_u, col, use_col, 1.0)
		_add_tri_outward(st_t, ring_u[3], ring_u[4], ridge_lo, Vector2(0.50, v_top_uv), Vector2(0.67, v_top_uv), Vector2(0.58, 0.96), prism_ref, part_u, col, use_col, 1.0)
		_add_tri_outward(st_t, ring_u[4], ring_u[5], ridge_hi, Vector2(0.67, v_top_uv), Vector2(0.83, v_top_uv), Vector2(0.80, 1.0), prism_ref, part_u, col, use_col, 1.0)
		_add_tri_outward(st_t, ring_u[4], ridge_hi, ridge_lo, Vector2(0.67, v_top_uv), Vector2(0.80, 1.0), Vector2(0.64, 0.96), prism_ref, part_u, col, use_col, 1.0)

	if dbl_ended:
		# Stout faceted lower keel with crisp coplanar bevel skirt + chisel/point bottom
		var bot_cone := Vector3(-r_base * 0.08 * asym_x, -bot_tip_h * 1.18, 0.04 * r_base * asym_z)
		var ring_l: Array[Vector3] = []
		var min_kl_y := 0.0
		for i in sides:
			var ang_b: float = angs[i]
			var kl_frac := 0.44 + 0.08 * cos(ang_b + 0.3) + (0.04 if (i % 2 == 1) else -0.04)
			var pl := base_loc[i].lerp(bot_cone, kl_frac)
			min_kl_y = minf(min_kl_y, pl.y)
			ring_l.append(base_pos + xf * pl)
		for i in sides:
			var nxt := (i + 1) % sides
			var u0 := float(i) / float(sides)
			var u1 := float(i + 1) / float(sides)
			_add_tri_outward(st_t, ring_l[i], ring_b[nxt], ring_b[i], Vector2(u0, 0.14), Vector2(u1, v_bot_uv), Vector2(u0, v_bot_uv), prism_ref, part_u, col, use_col, 1.0)
			_add_tri_outward(st_t, ring_l[i], ring_l[nxt], ring_b[nxt], Vector2(u0, 0.14), Vector2(u1, 0.14), Vector2(u1, v_bot_uv), prism_ref, part_u, col, use_col, 1.0)
		var bot_pt := base_pos + xf * Vector3(-r_base * 0.10 * asym_x, minf(-bot_tip_h, min_kl_y - 0.14), 0.04 * r_base * asym_z)
		for i in sides:
			var nxt := (i + 1) % sides
			var u0 := float(i) / float(sides)
			var u1 := float(i + 1) / float(sides)
			_add_tri_outward(st_t, ring_l[nxt], bot_pt, ring_l[i], Vector2(u1, 0.14), Vector2(0.5 * (u0 + u1), 0.0), Vector2(u0, 0.14), prism_ref, part_u, col, use_col, 1.0)


func _get_crystal_material(emission_str: float = 0.92, fresnel_pw: float = 3.4) -> ShaderMaterial:
	var cmat := ShaderMaterial.new()
	cmat.shader = load("res://terrain/cave_crystal.gdshader") as Shader
	cmat.set_shader_parameter("emission_strength", emission_str)
	cmat.set_shader_parameter("fresnel_power", fresnel_pw)
	cmat.set_shader_parameter("striation_normal", _get_crystal_striation_normal_tex())
	cmat.set_shader_parameter("interior_veil_tex", _get_crystal_interior_tex())
	return cmat


func _get_absorbable_crystal_material(tint: Color, emission_str: float = 0.92, fresnel_pw: float = 3.4) -> ShaderMaterial:
	var qtint := Vector4(snappedf(tint.r, 0.02), snappedf(tint.g, 0.02), snappedf(tint.b, 0.02), snappedf(emission_str, 0.05))
	var key := "%s|%.1f" % [str(qtint), fresnel_pw]
	if _crystal_mat_cache.has(key):
		return _crystal_mat_cache[key] as ShaderMaterial
	var cmat := _get_crystal_material(emission_str, fresnel_pw)
	cmat.set_shader_parameter("uTintColor", Vector3(tint.r, tint.g, tint.b))
	cmat.set_shader_parameter("uGlow", Vector3(clampf(tint.r * 0.4 + 0.3, 0.0, 1.0), clampf(tint.g * 0.4 + 0.55, 0.0, 1.0), clampf(tint.b * 0.4 + 0.55, 0.0, 1.0)))
	cmat.set_shader_parameter("uDissolve", 0.0)
	_crystal_mat_cache[key] = cmat
	return cmat


func _build_crystal_stone_mesh() -> ArrayMesh:
	if _cached_crystal_stone_mesh != null:
		return _cached_crystal_stone_mesh as ArrayMesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Chunky Craggy Basalt Matrix Cradle (UV2.x = 0.0 -> substantial faceted rock base left intact after shards are absorbed)
	var rock_sides := 8
	var rock_bot: Array[Vector3] = []
	var rock_mid: Array[Vector3] = []
	var rock_top: Array[Vector3] = []
	var rock_peak := Vector3(0.0, 0.62, 0.0)
	var rock_ref := Vector3(0.0, -0.20, 0.0)
	for i in rock_sides:
		var a := (float(i) / float(rock_sides)) * TAU + 0.14 * sin(float(i) * 2.3)
		var rb := 1.08 + 0.15 * cos(float(i) * 2.9)
		var rm := 0.86 + 0.12 * sin(float(i) * 3.1)
		var rt := 0.56 + 0.08 * cos(float(i) * 2.1)
		var hm := 0.24 + 0.08 * sin(float(i) * 1.9)
		var ht := 0.46 + 0.09 * cos(float(i) * 2.4 + 0.7)
		rock_bot.append(Vector3(cos(a) * rb, -0.75, sin(a) * rb))
		rock_mid.append(Vector3(cos(a) * rm, hm, sin(a) * rm))
		rock_top.append(Vector3(cos(a) * rt, ht, sin(a) * rt))
	for i in rock_sides:
		var nxt := (i + 1) % rock_sides
		var u0 := float(i) / float(rock_sides)
		var u1 := float(i + 1) / float(rock_sides)
		_add_tri_outward(st, rock_bot[i], rock_mid[nxt], rock_bot[nxt], Vector2(u0, 0.0), Vector2(u1, 0.45), Vector2(u1, 0.0), rock_ref, 0.0)
		_add_tri_outward(st, rock_bot[i], rock_mid[i], rock_mid[nxt], Vector2(u0, 0.0), Vector2(u0, 0.45), Vector2(u1, 0.45), rock_ref, 0.0)
		_add_tri_outward(st, rock_mid[i], rock_top[nxt], rock_mid[nxt], Vector2(u0, 0.45), Vector2(u1, 0.85), Vector2(u1, 0.45), rock_ref, 0.0)
		_add_tri_outward(st, rock_mid[i], rock_top[i], rock_top[nxt], Vector2(u0, 0.45), Vector2(u0, 0.85), Vector2(u1, 0.85), rock_ref, 0.0)
		_add_tri_outward(st, rock_top[i], rock_peak, rock_top[nxt], Vector2(u0, 0.85), Vector2(0.5 * (u0 + u1), 1.0), Vector2(u1, 0.85), rock_ref, 0.0)

	st.generate_tangents()
	_cached_crystal_stone_mesh = st.commit()
	_cached_crystal_stone_mesh.surface_set_material(0, _get_crystal_material())
	return _cached_crystal_stone_mesh as ArrayMesh


func _build_crystal_shards_mesh() -> ArrayMesh:
	if _cached_crystal_shards_mesh != null:
		return _cached_crystal_shards_mesh as ArrayMesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Chunky Sculptural Interlocking Mineral Quartz Cluster centered around (0, 0, 0) for clean SlimeProps digestion
	var y_off := Vector3(0.0, -0.68, 0.0)
	_add_chisel_crystal_to_st(st, Vector3(0.00, 0.24, 0.00) + y_off, Vector3(0.06, 1.00, -0.04), 0.320, 0.320, 0.290, 0.78, 1.04, 0.24, 1.24, 0.84, Color.WHITE, false, false, 0.35, 1.0, false)
	_add_chisel_crystal_to_st(st, Vector3(-0.14, 0.23, 0.12) + y_off, Vector3(-0.18, 0.97, 0.15), 0.255, 0.255, 0.230, 0.56, 0.76, 1.45, 0.86, 1.18, Color.WHITE, false, false, 0.35, 1.0, false)
	_add_chisel_crystal_to_st(st, Vector3(0.18, 0.20, 0.05) + y_off, Vector3(0.36, 0.92, 0.12), 0.240, 0.240, 0.214, 0.52, 0.70, 1.05, 0.88, 1.16, Color.WHITE, false, false, 0.35, 1.0, true)
	_add_chisel_crystal_to_st(st, Vector3(-0.18, 0.20, -0.08) + y_off, Vector3(-0.38, 0.91, -0.16), 0.220, 0.220, 0.194, 0.45, 0.61, -0.78, 1.16, 0.86, Color.WHITE, false, false, 0.35, 1.0, true)
	_add_chisel_crystal_to_st(st, Vector3(0.04, 0.19, -0.17) + y_off, Vector3(0.12, 0.89, -0.44), 0.200, 0.200, 0.174, 0.40, 0.54, 2.35, 0.90, 1.14, Color.WHITE, false, false, 0.35, 1.0, false)
	_add_chisel_crystal_to_st(st, Vector3(0.09, 0.19, 0.17) + y_off, Vector3(0.20, 0.89, 0.42), 0.190, 0.190, 0.164, 0.36, 0.50, 0.62, 1.14, 0.88, Color.WHITE, false, false, 0.35, 1.0, true)

	st.generate_tangents()
	_cached_crystal_shards_mesh = st.commit()
	_cached_crystal_shards_mesh.surface_set_material(0, _get_crystal_material())
	return _cached_crystal_shards_mesh as ArrayMesh


static func _basis_align_y(up_dir: Vector3, twist: float) -> Basis:
	var y := up_dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z).rotated(y, twist)


func _build_crystals(_rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	if props_data.is_empty():
		props_data = _load_or_compute_props(null)
	var c_data: Dictionary = props_data.get("crystals", {})
	var xforms: Array = c_data.get("xforms", [])
	var colors: Array = c_data.get("colors", [])
	if xforms.is_empty():
		return

	# 1. Permanent Obsidian-Basalt Stone Cradles (chunked by chamber for frustum & Mobile-light culling)
	var stones_holder := Node3D.new()
	stones_holder.name = "CaveCrystalStones"
	add_child(stones_holder)
	_add_zoned_multimeshes(stones_holder, "CaveCrystalStones", _build_crystal_stone_mesh(), xforms, colors, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, null, 0.0, 0.0, 2.5)

	# 2. Absorbable Mineral Crystal Shards (registered with SlimeProps for physics push-resistance, inside-belly shrink & uDissolve)
	var shards_holder := Node3D.new()
	shards_holder.name = "CaveCrystalShards"
	add_child(shards_holder)
	var shards_mesh := _build_crystal_shards_mesh()
	for i in xforms.size():
		var xf := xforms[i] as Transform3D
		var col := colors[i] as Color
		var rot_b := xf.basis.orthonormalized()
		var sh := xf.basis.y.length()
		var center_lift := 0.46 if sh < 0.72 else 0.68
		var world_center := xf.origin + rot_b.y * (center_lift * sh)
		var mat := _get_absorbable_crystal_material(col, 0.92, 3.4)
		var mi := MeshInstance3D.new()
		mi.name = "CaveCrystalShard_%d" % i
		mi.mesh = shards_mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 105.0
		mi.visibility_range_end_margin = 14.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.transform = Transform3D(rot_b.scaled(Vector3.ONE * sh), world_center)
		shards_holder.add_child(mi)
		_pending_crystal_props.append({
			"mi": mi,
			"mat": mat,
			"shape": SlimeProps.SHAPE_PRISM,
			"half": Vector3(0.46, 0.56, 0.46),
			"base_r": 0.44,
			"sides": 6,
			"vol": clampf(0.56 * sh * sh * sh, 0.025, 1.85),
		})


func _build_abyssal_shard_bundle(boulder_body: StaticBody3D) -> void:
	var sdf := get_sdf()
	var pit_c: Vector3 = CaveLayout.LAKE_ABYSS_PIT["c"]
	var fy_pit := clampf(_sample_floor_y(sdf, pit_c.x, 5.5, pit_c.z), 1.15, 2.25)
	var bundle_pos := CaveLayout.to_world(Vector3(pit_c.x, fy_pit - 0.12, pit_c.z))

	if _cached_abyssal_stone_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		# 1. Tectonic Angular Basalt Fissure Pedestal (10-sided craggy bedrock cradle, ALWAYS stays after shards are absorbed)
		var r_sides := 10
		var rock_bot: Array[Vector3] = []
		var rock_mid: Array[Vector3] = []
		var rock_top: Array[Vector3] = []
		var rock_peak := Vector3(0.0, 0.90, 0.0)
		var rock_ref := Vector3(0.0, -0.45, 0.0)
		var basalt_col := Color(0.06, 0.09, 0.14)
		for i in r_sides:
			var a := (float(i) / float(r_sides)) * TAU + 0.13 * sin(float(i) * 2.3)
			var rb := 3.15 + 0.38 * cos(float(i) * 2.9)
			var rm := 2.34 + 0.28 * sin(float(i) * 3.1)
			var rt := 1.48 + 0.18 * cos(float(i) * 2.1)
			var hm := 0.28 + 0.12 * sin(float(i) * 1.9)
			var ht := 0.70 + 0.16 * cos(float(i) * 2.4 + 0.7)
			rock_bot.append(Vector3(cos(a) * rb, -1.05, sin(a) * rb))
			rock_mid.append(Vector3(cos(a) * rm, hm, sin(a) * rm))
			rock_top.append(Vector3(cos(a) * rt, ht, sin(a) * rt))
		for i in r_sides:
			var nxt := (i + 1) % r_sides
			var u0 := float(i) / float(r_sides)
			var u1 := float(i + 1) / float(r_sides)
			_add_tri_outward(st, rock_bot[i], rock_mid[nxt], rock_bot[nxt], Vector2(u0, 0.0), Vector2(u1, 0.45), Vector2(u1, 0.0), rock_ref, 0.0, basalt_col, true)
			_add_tri_outward(st, rock_bot[i], rock_mid[i], rock_mid[nxt], Vector2(u0, 0.0), Vector2(u0, 0.45), Vector2(u1, 0.45), rock_ref, 0.0, basalt_col, true)
			_add_tri_outward(st, rock_mid[i], rock_top[nxt], rock_mid[nxt], Vector2(u0, 0.45), Vector2(u1, 0.85), Vector2(u1, 0.45), rock_ref, 0.0, basalt_col, true)
			_add_tri_outward(st, rock_mid[i], rock_top[i], rock_top[nxt], Vector2(u0, 0.45), Vector2(u0, 0.85), Vector2(u1, 0.85), rock_ref, 0.0, basalt_col, true)
			_add_tri_outward(st, rock_top[i], rock_peak, rock_top[nxt], Vector2(u0, 0.85), Vector2(0.5 * (u0 + u1), 1.0), Vector2(u1, 0.85), rock_ref, 0.0, basalt_col, true)

		st.generate_tangents()
		_cached_abyssal_stone_mesh = st.commit()
		_cached_abyssal_stone_mesh.surface_set_material(0, _get_crystal_material(1.38, 2.9))

	var mi := MeshInstance3D.new()
	mi.name = "CaveAbyssalShards"
	mi.mesh = _cached_abyssal_stone_mesh
	mi.position = bundle_pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# 2. 20 Individually Absorbable Chunky Crystal Shards seeded atop the Basalt Stone Pedestal
	var brng := RandomNumberGenerator.new()
	brng.seed = 7734
	var shard_palette := [
		Color(0.08, 0.92, 1.0),
		Color(0.14, 0.62, 1.0),
		Color(0.10, 0.96, 0.80),
		Color(0.54, 0.30, 1.0),
	]
	var max_tip_reach := clampf(4.65 - (fy_pit - 0.12), 2.20, 3.25)
	var shard_items: Array[Dictionary] = []

	# Tier 0: 3 Colossal Central Heart Crystal Monoliths
	var hero_specs := [
		[Vector3(0.0, 0.34, 0.0), Vector3(0.08, 0.99, -0.05), 0.66, 0.96, 1.18, 0.86],
		[Vector3(-0.62, 0.28, 0.40), Vector3(-0.22, 0.96, 0.16), 0.56, 0.82, 0.88, 1.16],
		[Vector3(0.64, 0.30, -0.34), Vector3(0.24, 0.95, -0.18), 0.52, 0.74, 1.15, 0.88],
	]
	for hi in hero_specs.size():
		var hs: Array = hero_specs[hi]
		var th_tot := max_tip_reach * float(hs[3])
		var rb := float(hs[2])
		var dir_h := (hs[1] as Vector3).normalized()
		shard_items.append({
			"base": hs[0] as Vector3,
			"dir": dir_h,
			"twist": brng.randf() * TAU,
			"col": shard_palette[hi % shard_palette.size()],
			"h": th_tot,
			"r": rb,
			"ax": float(hs[4]),
			"az": float(hs[5]),
			"vol": 1.35,
		})

	# Tier 1: 7 Heavy Buttress Crystal Blocks tightly ringing the hero monoliths
	for mi_idx in 7:
		var ang_m := (float(mi_idx) / 7.0) * TAU + brng.randf_range(-0.14, 0.14)
		var rad_m := brng.randf_range(0.76, 1.18)
		var tilt_m := brng.randf_range(0.26, 0.46)
		var dir_m := Vector3(cos(ang_m) * sin(tilt_m), cos(tilt_m), sin(ang_m) * sin(tilt_m)).normalized()
		var base_m := Vector3(cos(ang_m) * rad_m, brng.randf_range(0.34, 0.52), sin(ang_m) * rad_m)
		var tot_m := max_tip_reach * brng.randf_range(0.46, 0.68)
		var rb_m := brng.randf_range(0.36, 0.46)
		var ax_m := 1.18 if (mi_idx % 2 == 0) else 0.86
		var az_m := 0.86 if (mi_idx % 2 == 0) else 1.18
		shard_items.append({
			"base": base_m,
			"dir": dir_m,
			"twist": brng.randf() * TAU,
			"col": shard_palette[(mi_idx + 1) % shard_palette.size()],
			"h": tot_m,
			"r": rb_m,
			"ax": ax_m,
			"az": az_m,
			"vol": 0.90,
		})

	# Tier 2: 10 Stout Basal Crystal Chunks forming a dense crystal skirt atop the basalt pedestal
	for oi in 10:
		var ang_o := (float(oi) / 10.0) * TAU + 0.31 + brng.randf_range(-0.12, 0.12)
		var rad_o := brng.randf_range(0.96, 1.42)
		var tilt_o := brng.randf_range(0.38, 0.58)
		var dir_o := Vector3(cos(ang_o) * sin(tilt_o), cos(tilt_o), sin(ang_o) * sin(tilt_o)).normalized()
		var base_o := Vector3(cos(ang_o) * rad_o, brng.randf_range(0.42, 0.60), sin(ang_o) * rad_o)
		var tot_o := max_tip_reach * brng.randf_range(0.34, 0.50)
		var rb_o := brng.randf_range(0.28, 0.38)
		var ax_o := 1.16 if (oi % 2 == 0) else 0.88
		var az_o := 0.88 if (oi % 2 == 0) else 1.16
		shard_items.append({
			"base": base_o,
			"dir": dir_o,
			"twist": brng.randf() * TAU,
			"col": shard_palette[(oi + 2) % shard_palette.size()],
			"h": tot_o,
			"r": rb_o,
			"ax": ax_o,
			"az": az_o,
			"vol": 0.60,
		})

	var abyss_holder := Node3D.new()
	abyss_holder.name = "CaveAbyssalCrystalShards"
	add_child(abyss_holder)
	for si in shard_items.size():
		var item: Dictionary = shard_items[si]
		var rb_s := float(item["r"])
		var h_s := float(item["h"])
		var ax_s := float(item["ax"])
		var az_s := float(item["az"])
		var dir_s := item["dir"] as Vector3
		var twist_s := float(item["twist"])
		var base_s := item["base"] as Vector3
		var col_s := item["col"] as Color

		var st_sh := SurfaceTool.new()
		st_sh.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_chisel_crystal_to_st(st_sh, Vector3(0.0, -0.45 * h_s, 0.0), Vector3.UP, rb_s, rb_s, rb_s * 0.88, 0.74 * h_s, h_s, 0.0, ax_s, az_s, Color.WHITE, false, false, 0.35, 1.0, false)
		st_sh.generate_tangents()
		var sh_mesh := st_sh.commit()
		var mat_s := _get_absorbable_crystal_material(col_s, 1.38, 2.9)

		var sh_mi := MeshInstance3D.new()
		sh_mi.name = "CaveAbyssalCrystalShard_%d" % si
		sh_mi.mesh = sh_mesh
		sh_mi.material_override = mat_s
		sh_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh_mi.visibility_range_end = 105.0
		sh_mi.visibility_range_end_margin = 14.0
		sh_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var world_pos_s := bundle_pos + base_s + dir_s * (0.45 * h_s)
		sh_mi.transform = Transform3D(_basis_align_y(dir_s, twist_s), world_pos_s)
		abyss_holder.add_child(sh_mi)

		var rad_eff := rb_s * maxf(ax_s, az_s)
		_pending_crystal_props.append({
			"mi": sh_mi,
			"mat": mat_s,
			"shape": SlimeProps.SHAPE_PRISM,
			"half": Vector3(rad_eff, h_s * 0.50, rad_eff),
			"base_r": rad_eff,
			"sides": 6,
			"vol": float(item["vol"]),
		})

	# Permanent basalt stone pedestal collider seated below the shards so slimes can reach/eat every shard on top
	if boulder_body != null:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.45
		cyl.height = 1.4
		cs.shape = cyl
		cs.position = bundle_pos + Vector3(0.0, 0.25, 0.0)
		boulder_body.add_child(cs)


# ==============================================================================
# P5: WATER BASIN POOL, DRIP WATERFALL + SPLASH, OUTFLOW STREAM, PEBBLES,
#     SPELEOTHEMS & STRICTLY ZERO-COLLISION ECOLOGICAL CAVE FLORA
# ==============================================================================

func _build_water_features() -> void:
	var holder := Node3D.new()
	holder.name = "CaveWater"
	add_child(holder)

	var water_shader := load("res://terrain/cave_water.gdshader") as Shader
	if water_shader == null:
		return

	var wf_world := CaveLayout.to_world(CaveLayout.WATERFALL)
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = water_shader
	pool_mat.set_shader_parameter("is_waterfall", false)
	pool_mat.set_shader_parameter("waterfall_impact_world", wf_world)

	var wf_mat := ShaderMaterial.new()
	wf_mat.shader = water_shader
	wf_mat.set_shader_parameter("is_waterfall", true)

	var lake_mat := pool_mat.duplicate() as ShaderMaterial
	var lake_sc: Color = water_config.lake_shallow_color if water_config != null else Color(0.10, 0.48, 0.55, 1.0)
	var lake_dc: Color = water_config.lake_deep_color if water_config != null else Color(0.02, 0.08, 0.18, 1.0)
	lake_mat.set_shader_parameter("shallow_color", Vector3(lake_sc.r, lake_sc.g, lake_sc.b))
	lake_mat.set_shader_parameter("deep_color", Vector3(lake_dc.r, lake_dc.g, lake_dc.b))
	lake_mat.set_shader_parameter("foam_color", Vector3(0.72, 0.92, 1.0))

	var stream_mat := pool_mat.duplicate() as ShaderMaterial
	_pool_water_mat = pool_mat
	_lake_water_mat = lake_mat
	_stream_water_mat = stream_mat

	if _cached_water_meshes.is_empty() and ResourceLoader.exists(CAVE_WATER_MESHES_PATH):
		var wc := load(CAVE_WATER_MESHES_PATH) as ArrayMesh
		if wc != null:
			var wkeys: PackedStringArray = wc.get_meta("keys", PackedStringArray())
			if wkeys.size() == wc.get_surface_count():
				for si in wc.get_surface_count():
					var sm := ArrayMesh.new()
					sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wc.surface_get_arrays(si))
					var smat := wc.surface_get_material(si)
					if smat != null:
						sm.surface_set_material(0, smat)
					_cached_water_meshes[wkeys[si]] = sm

	if _cached_water_meshes.has("pool"):
		var p_mi := MeshInstance3D.new()
		p_mi.name = "PoolWater"
		p_mi.mesh = _cached_water_meshes["pool"]
		p_mi.material_override = pool_mat
		p_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(p_mi)

		var l_mi := MeshInstance3D.new()
		l_mi.name = "UndergroundLakeWater"
		l_mi.mesh = _cached_water_meshes["lake"]
		l_mi.material_override = lake_mat
		l_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(l_mi)

		var s_mi := MeshInstance3D.new()
		s_mi.name = "StreamWater"
		s_mi.mesh = _cached_water_meshes["stream"]
		s_mi.material_override = stream_mat
		s_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(s_mi)

		var w_mi := MeshInstance3D.new()
		w_mi.name = "WaterfallRibbon"
		w_mi.mesh = _cached_water_meshes["waterfall"]
		w_mi.material_override = wf_mat
		w_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(w_mi)

		if _cached_water_meshes.has("waterfall_spout"):
			var sp_mi := MeshInstance3D.new()
			sp_mi.name = "WaterfallSpoutRock"
			sp_mi.mesh = _cached_water_meshes["waterfall_spout"]
			sp_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(sp_mi)

		return

	# Build fast spatial hash of actual baked floor + rim triangles across Pool & Stream Grotto
	var bed_bins := _build_pool_stream_bed_bins()

	# 1. Carved Pool Water Surface (contoured tightly into stone banks + smooth East/NE spillway weir)
	var pool_c: Vector3 = CaveLayout.POOL["c"]
	var pool_y: float = float(CaveLayout.POOL["water_y"])
	var rx: float = float(CaveLayout.POOL["rx"]) + 1.45
	var rz: float = float(CaveLayout.POOL["rz"]) + 1.35
	var rings := 22
	var segs := 64

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_verts: Array[Array] = []
	for ir in range(rings + 1):
		var rt := float(ir) / float(rings)
		var arr_row: Array = []
		for iseg in range(segs + 1):
			var th := (float(iseg) / float(segs)) * TAU
			var d_ang := absf(wrapf(th - 0.73, -PI, PI))
			var spill_w := 1.0 - smoothstep(0.16, 0.50, d_ang)
			var lp := Vector3(pool_c.x + cos(th) * rx * rt, pool_y, pool_c.z + sin(th) * rz * rt)
			var wp := CaveLayout.to_world(lp)
			var bed_y := _sample_bed_tri_y(bed_bins, wp.x, wp.z, 21.2, -9999.0)
			if spill_w > 0.005 and rt > 0.72:
				var rt_s := smoothstep(0.72, 1.00, rt)
				var spill_target := maxf(bed_y + 0.065, 16.95) if bed_y > 14.0 else 16.95
				wp.y = lerpf(wp.y, minf(pool_y, spill_target), spill_w * rt_s)
			if ir >= rings - 1 and bed_y > 14.0:
				var wall_embed := bed_y - (0.14 if ir == rings else 0.02)
				if wp.y > wall_embed:
					wp.y = lerpf(wall_embed, wp.y, spill_w * (1.0 if ir == rings - 1 else 0.85))
			var r_col := clampf((1.0 - rt) * 3.8, 0.0, 1.0)
			if ir == rings:
				r_col = 0.0
			arr_row.append({"pos": wp, "uv": Vector2(rt * cos(th) * 0.5 + 0.5, rt * sin(th) * 0.5 + 0.5), "col": Color(r_col, 0.0, 0.0, 1.0)})
		ring_verts.append(arr_row)

	for ir in rings:
		for iseg in segs:
			var a: Dictionary = ring_verts[ir][iseg]
			var b: Dictionary = ring_verts[ir][iseg + 1]
			var c: Dictionary = ring_verts[ir + 1][iseg + 1]
			var d: Dictionary = ring_verts[ir + 1][iseg]
			st.set_normal(Vector3.UP); st.set_color(a["col"]); st.set_uv(a["uv"]); st.add_vertex(a["pos"])
			st.set_normal(Vector3.UP); st.set_color(b["col"]); st.set_uv(b["uv"]); st.add_vertex(b["pos"])
			st.set_normal(Vector3.UP); st.set_color(c["col"]); st.set_uv(c["uv"]); st.add_vertex(c["pos"])
			st.set_normal(Vector3.UP); st.set_color(a["col"]); st.set_uv(a["uv"]); st.add_vertex(a["pos"])
			st.set_normal(Vector3.UP); st.set_color(c["col"]); st.set_uv(c["uv"]); st.add_vertex(c["pos"])
			st.set_normal(Vector3.UP); st.set_color(d["col"]); st.set_uv(d["uv"]); st.add_vertex(d["pos"])

	var pool_mi := MeshInstance3D.new()
	pool_mi.name = "PoolWater"
	pool_mi.mesh = st.commit()
	_cached_water_meshes["pool"] = pool_mi.mesh
	pool_mi.material_override = pool_mat
	pool_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(pool_mi)

	# 1b. Non-Circular Multi-Cove Organic Underground Lake Water Surface
	var lake_c: Vector3 = CaveLayout.UNDERGROUND_LAKE["c"]
	var lake_y: float = float(CaveLayout.UNDERGROUND_LAKE["water_y"])
	var l_rings := 36
	var l_segs := 112

	var st_lake := SurfaceTool.new()
	st_lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lake_ring_verts: Array[Array] = []
	for ir in range(l_rings + 1):
		var rt := float(ir) / float(l_rings)
		var arr_row: Array = []
		for iseg in range(l_segs + 1):
			var th := (float(iseg) / float(l_segs)) * TAU
			var shore_p := CaveLayout.lake_shore_point(th, rt * 1.03)
			var lp := Vector3(shore_p.x, lake_y, shore_p.y)
			var wp := CaveLayout.to_world(lp)
			var r_col := clampf(1.0 - rt, 0.0, 1.0)
			var u_norm := 0.5 + (lp.x - lake_c.x) / 120.0
			var v_norm := 0.5 + (lp.z - lake_c.z) / 120.0
			arr_row.append({"pos": wp, "uv": Vector2(u_norm, v_norm), "col": Color(r_col, 0.0, 0.0, 1.0)})
		lake_ring_verts.append(arr_row)

	for ir in l_rings:
		for iseg in l_segs:
			var a: Dictionary = lake_ring_verts[ir][iseg]
			var b: Dictionary = lake_ring_verts[ir][iseg + 1]
			var c: Dictionary = lake_ring_verts[ir + 1][iseg + 1]
			var d: Dictionary = lake_ring_verts[ir + 1][iseg]
			st_lake.set_normal(Vector3.UP); st_lake.set_color(a["col"]); st_lake.set_uv(a["uv"]); st_lake.add_vertex(a["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(b["col"]); st_lake.set_uv(b["uv"]); st_lake.add_vertex(b["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(c["col"]); st_lake.set_uv(c["uv"]); st_lake.add_vertex(c["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(a["col"]); st_lake.set_uv(a["uv"]); st_lake.add_vertex(a["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(c["col"]); st_lake.set_uv(c["uv"]); st_lake.add_vertex(c["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(d["col"]); st_lake.set_uv(d["uv"]); st_lake.add_vertex(d["pos"])

	var lake_mi := MeshInstance3D.new()
	lake_mi.name = "UndergroundLakeWater"
	lake_mi.mesh = st_lake.commit()
	_cached_water_meshes["lake"] = lake_mi.mesh
	lake_mi.material_override = lake_mat
	lake_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(lake_mi)

	# 2. Outflow Stream Ribbon clinging cleanly onto baked CaveFloorBody riverbed + feathered ends
	var sdf := get_sdf()
	var s_ctrl := CaveLayout.STREAM_CTRL
	var s_pts: Array[Vector3] = []
	for seg_i in range(s_ctrl.size() - 1):
		var p0 := s_ctrl[maxi(seg_i - 1, 0)]
		var p1 := s_ctrl[seg_i]
		var p2 := s_ctrl[seg_i + 1]
		var p3 := s_ctrl[mini(seg_i + 2, s_ctrl.size() - 1)]
		for sub in 6:
			var st_t := float(sub) / 6.0
			s_pts.append(p1.cubic_interpolate(p2, p0, p3, st_t))
	s_pts.append(s_ctrl[s_ctrl.size() - 1])

	var n_st := s_pts.size()
	var dirs: Array[Vector2] = []
	var rights: Array[Vector2] = []
	var center_beds := PackedFloat32Array()
	center_beds.resize(n_st)
	for i in n_st:
		var p := s_pts[i]
		var dir2: Vector2
		if i == 0:
			dir2 = Vector2(s_pts[1].x - p.x, s_pts[1].z - p.z)
		elif i == n_st - 1:
			dir2 = Vector2(p.x - s_pts[i - 1].x, p.z - s_pts[i - 1].z)
		else:
			dir2 = Vector2(s_pts[i + 1].x - s_pts[i - 1].x, s_pts[i + 1].z - s_pts[i - 1].z)
		dir2 = dir2.normalized()
		dirs.append(dir2)
		rights.append(Vector2(-dir2.y, dir2.x))
		var cw := CaveLayout.to_world(p)
		var fallback_c := _sample_floor_y(sdf, p.x, p.y + 3.0, p.z)
		center_beds[i] = _sample_bed_tri_y(bed_bins, cw.x, cw.z, 20.5, fallback_c)

	var st_s := SurfaceTool.new()
	st_s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows_s: Array[Array] = []
	for i in n_st:
		var p := s_pts[i]
		var right2 := rights[i]
		var vfrac := float(i) / float(n_st - 1)
		var bed_c := center_beds[i]
		# Local smoothed riverbed elevation so shallow basins pool deeper (up to 13 cm) while crests stay grounded (+5 cm)
		var bed_avg := 0.0
		var w_sum := 0.0
		for k in range(maxi(0, i - 3), mini(n_st, i + 4)):
			var w_k := 1.0 - absf(float(k - i)) * 0.22
			bed_avg += center_beds[k] * w_k
			w_sum += w_k
		bed_avg /= maxf(w_sum, 1e-4)
		var water_center_y := clampf(bed_avg + 0.068, bed_c + 0.048, bed_c + 0.135)
		# Upstream start sits flatly submerged below PoolWater (-0.10 m) and fades in smoothly at the spillway crest (no tent seam inside Pool)
		var start_tuck := 1.0 - smoothstep(0.025, 0.115, vfrac)
		var r_start := 1.0 - start_tuck
		# Sink gracefully into stone floor at Geode Pocket downstream terminus
		var end_fade := smoothstep(0.86, 1.0, vfrac)
		var r_end := (1.0 - end_fade) * r_start
		if start_tuck > 0.001:
			var sill_y := lerpf(water_center_y, minf(pool_y - 0.10, maxf(bed_c + 0.04, 16.92)), start_tuck)
			water_center_y = sill_y
		if end_fade > 0.001:
			water_center_y = lerpf(water_center_y, bed_c - 0.14, end_fade)
		var hw_cur := lerpf(1.30, 1.48, start_tuck)
		hw_cur = lerpf(hw_cur, 0.58, end_fade)

		var row: Array = []
		for side: float in [-1.0, -0.46, 0.0, 0.46, 1.0]:
			var off := right2 * (hw_cur * side)
			var w_xz := CaveLayout.to_world(Vector3(p.x + off.x, 0.0, p.z + off.y))
			var side_bed := _sample_bed_tri_y(bed_bins, w_xz.x, w_xz.z, 20.5, bed_c)
			var vy: float
			var r_val: float
			if absf(side) < 0.05:
				vy = water_center_y
				r_val = r_end
			elif absf(side) < 0.80:
				var sheet_y := minf(water_center_y - 0.008, side_bed + 0.032)
				vy = lerpf(sheet_y, water_center_y - 0.02, start_tuck)
				vy = lerpf(vy, side_bed - 0.12, end_fade)
				r_val = 0.62 * r_end
			else:
				var outer_y := minf(side_bed, water_center_y) - 0.18
				vy = lerpf(outer_y, water_center_y - 0.06, start_tuck)
				r_val = 0.0
			var wp := CaveLayout.to_world(Vector3(p.x + off.x, vy, p.z + off.y))
			row.append({"pos": wp, "uv": Vector2(side * 0.5 + 0.5, vfrac * 6.0), "col": Color(r_val, 1.0, 0.0, 1.0)})
		rows_s.append(row)

	for r_i in range(rows_s.size() - 1):
		for c_i in 4:
			var a: Dictionary = rows_s[r_i][c_i]
			var b: Dictionary = rows_s[r_i][c_i + 1]
			var c: Dictionary = rows_s[r_i + 1][c_i + 1]
			var d: Dictionary = rows_s[r_i + 1][c_i]
			st_s.set_normal(Vector3.UP); st_s.set_color(a["col"]); st_s.set_uv(a["uv"]); st_s.add_vertex(a["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(b["col"]); st_s.set_uv(b["uv"]); st_s.add_vertex(b["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(c["col"]); st_s.set_uv(c["uv"]); st_s.add_vertex(c["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(a["col"]); st_s.set_uv(a["uv"]); st_s.add_vertex(a["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(c["col"]); st_s.set_uv(c["uv"]); st_s.add_vertex(c["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(d["col"]); st_s.set_uv(d["uv"]); st_s.add_vertex(d["pos"])

	var stream_mi := MeshInstance3D.new()
	stream_mi.name = "StreamWater"
	stream_mi.mesh = st_s.commit()
	_cached_water_meshes["stream"] = stream_mi.mesh
	stream_mi.material_override = stream_mat
	stream_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(stream_mi)

	# 3. Dynamic Multi-Layer Waterfall (Carved Limestone Spring Alcove + U-Channel Spillway + Trough-Connected Cascade)
	var wf_loc := CaveLayout.WATERFALL
	var wf_ceil_y := clampf(_sample_ceiling_y(sdf, wf_loc.x, wf_loc.y + 4.0, wf_loc.z + 0.5, 45.0), wf_loc.y + 9.5, 36.5)
	_cached_wf_ceil_y = wf_ceil_y
	var spout_y := clampf(wf_ceil_y - 2.45, wf_loc.y + 8.5, 31.4)

	# 3A. Closed-Manifold Organic Limestone Spring Alcove & Carved U-Channel Spillway (cave_rock.gdshader + CaveShell-buried crown)
	var st_spout := SurfaceTool.new()
	st_spout.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u_segs := 18
	var half_span_u := 4.65
	var s_back := wf_loc.z + 6.4
	var p_count := 10
	var sp_grid: Array[Array] = []
	var sp_cols: Array[Array] = []
	var sp_uvs: Array[Array] = []
	var sp_outs_local: Array[Array] = []

	for iu in range(u_segs + 1):
		var ut := float(iu) / float(u_segs)
		var u_off := (ut * 2.0 - 1.0) * half_span_u
		var u_world_loc := wf_loc.x + u_off
		var end_w := pow(sin(ut * PI), 0.45)
		var ch_u := smoothstep(0.0, 1.0, clampf(absf(u_off) / 1.28, 0.0, 1.0))
		var crag := 0.26 * sin(u_off * 1.45 + 0.6) + 0.13 * cos(u_off * 3.1 - 0.9)

		var s_lip := lerpf(s_back - 1.2, wf_loc.z + lerpf(0.52, 1.45, ch_u) + crag * 0.34 * ch_u, end_w)
		var recess_depth := lerpf(3.35, 0.15, ch_u) * end_w
		var s_trough_back := s_lip + recess_depth
		var s_chin := lerpf(s_lip + 0.55, s_back - 0.8, 0.15)
		var s_belly := lerpf(s_lip + 1.85, s_back - 0.4, 0.22)
		var s_brow := lerpf(s_lip + 0.85, s_lip + 0.18, ch_u)

		var y_bed_lip := spout_y + lerpf(0.0, 1.05, ch_u) + crag * 0.35 * ch_u
		var y_bed_back := y_bed_lip + lerpf(0.46, 0.10, ch_u)
		var y_chin := spout_y - lerpf(1.20, 1.85, end_w) + crag * 0.40
		var y_belly := spout_y - lerpf(2.75, 3.35, end_w) + crag * 0.28
		var mouth_open_h := lerpf(1.45, 0.08, ch_u)
		var y_brow := spout_y + lerpf(1.75, 2.25, ch_u) + crag * 0.35
		var ceil_front := _sample_ceiling_y(sdf, u_world_loc, wf_loc.y + 4.0, minf(s_brow, wf_loc.z + 3.0), 45.0)
		var y_crown_front := maxf(ceil_front + 2.2, y_brow + 1.4)
		var y_crown_back := maxf(y_crown_front + 0.45, spout_y + 4.6)

		# Simple non-self-intersecting clockwise loop in (S, Y) plane; outward normal = (-dY, dS)
		var prof: Array[Vector2] = [
			Vector2(s_back, y_belly + 0.55),                    # 0: buried lower rear
			Vector2(s_belly, y_belly),                          # 1: recessed lower rock apron
			Vector2(s_chin, y_chin),                            # 2: undercut spillway chin
			Vector2(s_lip, y_bed_lip),                          # 3: rounded wet spillway lip
			Vector2(lerpf(s_lip, s_trough_back, 0.52), lerpf(y_bed_lip, y_bed_back, 0.52)), # 4: mid trough bed
			Vector2(s_trough_back, y_bed_back),                 # 5: deep spring mouth floor
			Vector2(s_trough_back + 0.18 * (1.0 - ch_u), y_bed_back + mouth_open_h), # 6: spring inner back roof
			Vector2(s_brow, y_brow),                            # 7: overhanging spring mouth brow
			Vector2(s_brow - 0.35, y_crown_front),              # 8: front ceiling embed
			Vector2(s_back, y_crown_back),                      # 9: deep rear ceiling embed
		]
		# Vertex COLOR channels for cave_rock.gdshader: R=AO, G=SkyVis (keep <0.25 so no exterior grass!), B=Wetness, A=Curvature
		var wet_trough := lerpf(0.95, 0.28, ch_u) * end_w
		var prof_col: Array[Color] = [
			Color(0.14, 0.04, 0.25, 0.28),
			Color(0.32, 0.06, 0.55, 0.34),
			Color(0.50, 0.08, 0.72, 0.58),
			Color(0.70, 0.10, maxf(wet_trough, 0.55), 0.76),
			Color(0.40, 0.07, wet_trough, 0.44),
			Color(0.18, 0.04, wet_trough, 0.26),
			Color(0.14, 0.04, 0.65, 0.24),
			Color(0.46, 0.09, 0.45, 0.68),
			Color(0.24, 0.05, 0.20, 0.40),
			Color(0.12, 0.03, 0.15, 0.25),
		]

		var row_p: Array[Vector3] = []
		var row_c: Array[Color] = []
		var row_uv: Array[Vector2] = []
		var row_out: Array[Vector3] = []
		for ip in range(p_count):
			var cur_sy: Vector2 = prof[ip]
			var prev_sy: Vector2 = prof[(ip - 1 + p_count) % p_count]
			var nxt_sy: Vector2 = prof[(ip + 1) % p_count]
			var d_sy := nxt_sy - prev_sy
			# Outward normal in (u, y, s) from CW (S, Y) tangent: s' = -dY, y' = +dS
			var out_n_loc := Vector3(0.0, d_sy.x, -d_sy.y).normalized()
			var out_n_w := (CaveLayout.to_world(Vector3(u_world_loc + out_n_loc.x, out_n_loc.y, cur_sy.x + out_n_loc.z)) - CaveLayout.to_world(Vector3(u_world_loc, 0.0, cur_sy.x)))
			out_n_w.y = out_n_loc.y
			out_n_w = out_n_w.normalized()

			row_p.append(CaveLayout.to_world(Vector3(u_world_loc, cur_sy.y, cur_sy.x)))
			row_c.append(prof_col[ip])
			row_uv.append(Vector2(ut, float(ip) / float(p_count)))
			row_out.append(out_n_w)
		sp_grid.append(row_p)
		sp_cols.append(row_c)
		sp_uvs.append(row_uv)
		sp_outs_local.append(row_out)

	var sp_nrms: Array[Array] = []
	for iu in range(u_segs + 1):
		var nrow: Array[Vector3] = []
		for ip in range(p_count):
			var p_l: Vector3 = sp_grid[maxi(iu - 1, 0)][ip]
			var p_r: Vector3 = sp_grid[mini(iu + 1, u_segs)][ip]
			var p_prev: Vector3 = sp_grid[iu][(ip - 1 + p_count) % p_count]
			var p_nxt: Vector3 = sp_grid[iu][(ip + 1) % p_count]
			var tu: Vector3 = p_r - p_l
			var tp: Vector3 = p_nxt - p_prev
			var wn := tp.cross(tu).normalized()
			if wn.length_squared() < 1e-6:
				wn = sp_outs_local[iu][ip]
			elif wn.dot(sp_outs_local[iu][ip]) < 0.0:
				wn = -wn
			nrow.append(wn)
		sp_nrms.append(nrow)

	var add_spout_tri := func(p0: Vector3, p1: Vector3, p2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, c0: Color, c1: Color, c2: Color, uv0: Vector2, uv1: Vector2, uv2: Vector2, hint_out: Vector3) -> void:
		var fn := (p2 - p0).cross(p1 - p0)
		if fn.length_squared() < 1e-10:
			return
		var a1 := p1; var a2 := p2
		var an1 := n1; var an2 := n2
		var ac1 := c1; var ac2 := c2
		var au1 := uv1; var au2 := uv2
		if fn.dot(hint_out) < 0.0:
			a1 = p2; a2 = p1
			an1 = n2; an2 = n1
			ac1 = c2; ac2 = c1
			au1 = uv2; au2 = uv1
		st_spout.set_normal(n0); st_spout.set_color(c0); st_spout.set_uv(uv0); st_spout.add_vertex(p0)
		st_spout.set_normal(an1); st_spout.set_color(ac1); st_spout.set_uv(au1); st_spout.add_vertex(a1)
		st_spout.set_normal(an2); st_spout.set_color(ac2); st_spout.set_uv(au2); st_spout.add_vertex(a2)

	for iu in range(u_segs):
		for ip in range(p_count):
			var ip_nxt := (ip + 1) % p_count
			var hint: Vector3 = (sp_outs_local[iu][ip] + sp_outs_local[iu + 1][ip] + sp_outs_local[iu][ip_nxt] + sp_outs_local[iu + 1][ip_nxt]).normalized()
			add_spout_tri.call(
				sp_grid[iu][ip], sp_grid[iu + 1][ip], sp_grid[iu + 1][ip_nxt],
				sp_nrms[iu][ip], sp_nrms[iu + 1][ip], sp_nrms[iu + 1][ip_nxt],
				sp_cols[iu][ip], sp_cols[iu + 1][ip], sp_cols[iu + 1][ip_nxt],
				sp_uvs[iu][ip], sp_uvs[iu + 1][ip], sp_uvs[iu + 1][ip_nxt],
				hint
			)
			add_spout_tri.call(
				sp_grid[iu][ip], sp_grid[iu + 1][ip_nxt], sp_grid[iu][ip_nxt],
				sp_nrms[iu][ip], sp_nrms[iu + 1][ip_nxt], sp_nrms[iu][ip_nxt],
				sp_cols[iu][ip], sp_cols[iu + 1][ip_nxt], sp_cols[iu][ip_nxt],
				sp_uvs[iu][ip], sp_uvs[iu + 1][ip_nxt], sp_uvs[iu][ip_nxt],
				hint
			)

	st_spout.generate_tangents()
	var spout_mi := MeshInstance3D.new()
	spout_mi.name = "WaterfallSpoutRock"
	spout_mi.mesh = st_spout.commit()
	spout_mi.mesh.surface_set_material(0, _get_cave_rock_material())
	_cached_water_meshes["waterfall_spout"] = spout_mi.mesh
	spout_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(spout_mi)

	# 3B. Dual-Layer Curved Cascade pouring directly out of the Carved Spring Trough into PoolWater
	var st_wf := SurfaceTool.new()
	st_wf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var add_waterfall_sheet := func(col_tag: Color, w_trough: float, w_lip: float, w_bot: float, bow_depth: float, fwd_shift: float) -> void:
		var w_segs := 16
		var h_segs := 30
		var trough_end := 0.18
		var grid: Array[Array] = []
		for iy in range(h_segs + 1):
			var vt := float(iy) / float(h_segs)
			var y_cur := 0.0
			var s_center := 0.0
			var w_half := 0.0
			var bow_k := 0.0
			if vt <= trough_end:
				var k := vt / trough_end
				var ks := smoothstep(0.0, 1.0, k)
				y_cur = lerpf(spout_y + 0.62, spout_y + 0.14, pow(k, 1.25))
				s_center = wf_loc.z + lerpf(3.55, 0.42, k) - fwd_shift * 0.25
				w_half = lerpf(w_trough, w_lip, ks)
				bow_k = 0.28 + 0.42 * ks
			else:
				var u_fall := (vt - trough_end) / (1.0 - trough_end)
				var pitch_arch := smoothstep(0.0, 0.22, u_fall)
				y_cur = lerpf(spout_y + 0.14, wf_loc.y - 0.34, pow(u_fall, 0.86))
				s_center = wf_loc.z + 0.42 - (pitch_arch * 1.48 + (u_fall * u_fall) * 0.72 + fwd_shift)
				w_half = lerpf(w_lip, w_bot, pow(u_fall, 0.78))
				bow_k = 0.70 + 0.30 * u_fall
			var row_wf: Array = []
			for ix in range(w_segs + 1):
				var ut := float(ix) / float(w_segs)
				var u_off := (ut * 2.0 - 1.0) * w_half
				var s_cur := s_center - sin(ut * PI) * bow_depth * bow_k
				var lp := Vector3(wf_loc.x + u_off, y_cur, s_cur)
				row_wf.append({"pos": CaveLayout.to_world(lp), "uv": Vector2(ut, vt)})
			grid.append(row_wf)

		for iy in range(h_segs + 1):
			for ix in range(w_segs + 1):
				var p_left: Vector3 = grid[iy][maxi(ix - 1, 0)]["pos"]
				var p_right: Vector3 = grid[iy][mini(ix + 1, w_segs)]["pos"]
				var p_top: Vector3 = grid[maxi(iy - 1, 0)][ix]["pos"]
				var p_bot: Vector3 = grid[mini(iy + 1, h_segs)][ix]["pos"]
				var tu: Vector3 = p_right - p_left
				var tv: Vector3 = p_bot - p_top
				grid[iy][ix]["nrm"] = tv.cross(tu).normalized()

		for iy in h_segs:
			for ix in w_segs:
				var a: Dictionary = grid[iy][ix]
				var b: Dictionary = grid[iy][ix + 1]
				var c: Dictionary = grid[iy + 1][ix + 1]
				var d: Dictionary = grid[iy + 1][ix]
				st_wf.set_normal(a["nrm"]); st_wf.set_color(col_tag); st_wf.set_uv(a["uv"]); st_wf.add_vertex(a["pos"])
				st_wf.set_normal(b["nrm"]); st_wf.set_color(col_tag); st_wf.set_uv(b["uv"]); st_wf.add_vertex(b["pos"])
				st_wf.set_normal(c["nrm"]); st_wf.set_color(col_tag); st_wf.set_uv(c["uv"]); st_wf.add_vertex(c["pos"])
				st_wf.set_normal(a["nrm"]); st_wf.set_color(col_tag); st_wf.set_uv(a["uv"]); st_wf.add_vertex(a["pos"])
				st_wf.set_normal(c["nrm"]); st_wf.set_color(col_tag); st_wf.set_uv(c["uv"]); st_wf.add_vertex(c["pos"])
				st_wf.set_normal(d["nrm"]); st_wf.set_color(col_tag); st_wf.set_uv(d["uv"]); st_wf.add_vertex(d["pos"])

	# Core Translucent Cascade + Wider Outer Silk Veil
	add_waterfall_sheet.call(Color(0.0, 0.0, 0.0, 1.0), 0.92, 1.02, 1.58, 0.42, 0.0)
	add_waterfall_sheet.call(Color(1.0, 0.0, 0.0, 1.0), 0.98, 1.14, 1.98, 0.56, 0.22)

	st_wf.generate_tangents()
	var wf_mi := MeshInstance3D.new()
	wf_mi.name = "WaterfallRibbon"
	wf_mi.mesh = st_wf.commit()
	_cached_water_meshes["waterfall"] = wf_mi.mesh
	wf_mi.material_override = wf_mat
	wf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(wf_mi)

	if not _cached_water_meshes.is_empty():
		var wc_pack := ArrayMesh.new()
		var wc_keys := PackedStringArray()
		for k in ["pool", "lake", "stream", "waterfall", "waterfall_spout"]:
			var cm := _cached_water_meshes.get(k, null) as Mesh
			if cm != null and cm.get_surface_count() > 0:
				var si_new := wc_pack.get_surface_count()
				wc_pack.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.surface_get_arrays(0))
				var cmat := cm.surface_get_material(0)
				if cmat != null:
					wc_pack.surface_set_material(si_new, cmat)
				wc_keys.append(k)
		if wc_pack.get_surface_count() > 0:
			wc_pack.set_meta("keys", wc_keys)
			_save_cached_res(wc_pack, CAVE_WATER_MESHES_PATH)


func _build_pool_stream_bed_bins() -> Dictionary:
	var bins := {}
	var floor_shape := load(CAVE_FLOOR_SHAPE_PATH) as ConcavePolygonShape3D
	if floor_shape == null:
		return bins
	var faces := floor_shape.get_faces()
	var min_w := CaveLayout.to_world(Vector3(-68.0, 0.0, 52.0))
	var max_w := CaveLayout.to_world(Vector3(14.0, 0.0, 110.0))
	var bx0 := minf(min_w.x, max_w.x) - 22.0
	var bx1 := maxf(min_w.x, max_w.x) + 22.0
	var bz0 := minf(min_w.z, max_w.z) - 22.0
	var bz1 := maxf(min_w.z, max_w.z) + 22.0

	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var minx := minf(a.x, minf(b.x, c.x))
		var maxx := maxf(a.x, maxf(b.x, c.x))
		var minz := minf(a.z, minf(b.z, c.z))
		var maxz := maxf(a.z, maxf(b.z, c.z))
		if maxx < bx0 or minx > bx1 or maxz < bz0 or minz > bz1:
			continue
		if absf((b - a).cross(c - a).y) < 0.04:
			continue
		var tri := [a, b, c]
		var cx0 := int(floor(minx * 0.5))
		var cx1 := int(floor(maxx * 0.5))
		var cz0 := int(floor(minz * 0.5))
		var cz1 := int(floor(maxz * 0.5))
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				var key := Vector2i(cx, cz)
				if not bins.has(key):
					bins[key] = []
				(bins[key] as Array).append(tri)
	return bins


static func _sample_bed_tri_y(bins: Dictionary, wx: float, wz: float, y_max: float, fallback_y: float) -> float:
	if bins.is_empty():
		return fallback_y
	var key := Vector2i(int(floor(wx * 0.5)), int(floor(wz * 0.5)))
	if not bins.has(key):
		return fallback_y
	var tris: Array = bins[key]
	var best_y := -9999.0
	for tri: Array in tris:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var v0x := c.x - a.x
		var v0z := c.z - a.z
		var v1x := b.x - a.x
		var v1z := b.z - a.z
		var v2x := wx - a.x
		var v2z := wz - a.z
		var dot00 := v0x * v0x + v0z * v0z
		var dot01 := v0x * v1x + v0z * v1z
		var dot02 := v0x * v2x + v0z * v2z
		var dot11 := v1x * v1x + v1z * v1z
		var dot12 := v1x * v2x + v1z * v2z
		var denom := dot00 * dot11 - dot01 * dot01
		if absf(denom) < 1e-8:
			continue
		var inv := 1.0 / denom
		var u := (dot11 * dot02 - dot01 * dot12) * inv
		var v := (dot00 * dot12 - dot01 * dot02) * inv
		if u >= -0.002 and v >= -0.002 and (u + v) <= 1.004:
			var hy := a.y + u * (c.y - a.y) + v * (b.y - a.y)
			if hy <= y_max and hy > best_y:
				best_y = hy
	return best_y if best_y > -9000.0 else fallback_y


func _get_pebble_mesh() -> Mesh:
	if _cached_pebble_mesh != null:
		return _cached_pebble_mesh
	var sc := load("res://assets/nature/Pebble_Round_1.gltf") as PackedScene
	if sc == null:
		return null
	var inst := sc.instantiate()
	var pmesh: Mesh = null
	for c in inst.get_children():
		if c is MeshInstance3D and c.mesh != null:
			pmesh = c.mesh.duplicate()
			break
	inst.free()
	if pmesh == null:
		return null

	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = load("res://assets/nature/PathRocks_Diffuse.png") as Texture2D
	pmat.albedo_color = Color(0.68, 0.72, 0.75)
	pmat.roughness = 0.35
	pmat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	pmat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	pmesh.surface_set_material(0, pmat)
	_cached_pebble_mesh = pmesh
	return _cached_pebble_mesh


func _build_pebbles(_rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	if props_data.is_empty():
		props_data = _load_or_compute_props(null)
	var p_data: Dictionary = props_data.get("pebbles", {})
	var xforms: Array = p_data.get("xforms", [])
	if scatter_config != null and scatter_config.pebble_count < xforms.size():
		xforms = xforms.slice(0, maxi(scatter_config.pebble_count, 0))
	if xforms.is_empty():
		return
	var pmesh := _get_pebble_mesh()
	if pmesh == null:
		return

	var pebbles_holder := Node3D.new()
	pebbles_holder.name = "CavePebbles"
	add_child(pebbles_holder)
	_add_zoned_multimeshes(pebbles_holder, "CavePebbles", pmesh, xforms, [], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, null, 105.0, 14.0, 2.5)


func _build_speleothem_mesh() -> ArrayMesh:
	if _cached_speleothem_mesh != null:
		return _cached_speleothem_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 5
	var segs := 8
	var profile_r := [0.42, 0.34, 0.24, 0.16, 0.08, 0.02]
	var profile_y := [0.0, 0.25, 0.55, 0.80, 0.96, 1.05]
	for ir in rings:
		for iseg in segs:
			var a0 := (float(iseg) / float(segs)) * TAU
			var a1 := (float(iseg + 1) / float(segs)) * TAU
			var r0: float = float(profile_r[ir])
			var r1: float = float(profile_r[ir + 1])
			var y0: float = float(profile_y[ir])
			var y1: float = float(profile_y[ir + 1])
			var v00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var v10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var v01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var v11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var n0 := Vector3(cos(a0), 0.2, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), 0.2, sin(a1)).normalized()
			st.set_normal(n0); st.set_uv(Vector2(0, y0)); st.add_vertex(v00)
			st.set_normal(n1); st.set_uv(Vector2(1, y0)); st.add_vertex(v10)
			st.set_normal(n1); st.set_uv(Vector2(1, y1)); st.add_vertex(v11)
			st.set_normal(n0); st.set_uv(Vector2(0, y0)); st.add_vertex(v00)
			st.set_normal(n1); st.set_uv(Vector2(1, y1)); st.add_vertex(v11)
			st.set_normal(n0); st.set_uv(Vector2(0, y1)); st.add_vertex(v01)
	_cached_speleothem_mesh = st.commit()
	var smat := StandardMaterial3D.new()
	smat.albedo_texture = load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
	smat.albedo_color = Color(0.72, 0.70, 0.67)
	smat.roughness = 0.72
	smat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_cached_speleothem_mesh.surface_set_material(0, smat)
	return _cached_speleothem_mesh


func _build_speleothems(boulder_body: StaticBody3D, _rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	if props_data.is_empty():
		props_data = _load_or_compute_props(null)
	var s_data: Dictionary = props_data.get("speleothems", {})
	var xforms: Array = s_data.get("xforms", [])
	var stalagmites: Array = s_data.get("stalagmites", [])
	if xforms.is_empty():
		return
	var smesh := _build_speleothem_mesh()
	var spele_holder := Node3D.new()
	spele_holder.name = "CaveSpeleothems"
	add_child(spele_holder)
	_add_zoned_multimeshes(spele_holder, "CaveSpeleothems", smesh, xforms, [], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, null, 115.0, 16.0, 4.0)

	if boulder_body != null:
		var body_rid := boulder_body.get_rid()
		for col_info: Dictionary in stalagmites:
			var cyl := CylinderShape3D.new()
			cyl.radius = float(col_info.get("radius", 0.4))
			cyl.height = float(col_info.get("height", 2.0))
			_cave_boulder_shapes.append(cyl)
			PhysicsServer3D.body_add_shape(body_rid, cyl.get_rid(), Transform3D(Basis.IDENTITY, col_info.get("pos", Vector3.ZERO) as Vector3))


func _build_vine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	var prev_w := 0.22
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var y0 := -t0 * 1.0
		var y1 := -t1 * 1.0
		var w0 := lerpf(prev_w, 0.03, t0)
		var w1 := lerpf(prev_w, 0.03, t1)
		var x0 := sin(t0 * 4.5) * 0.05
		var x1 := sin(t1 * 4.5) * 0.05
		for ang: float in [0.0, PI * 0.5]:
			var ca := cos(ang); var sa := sin(ang)
			var d0 := Vector3(w0 * ca, 0, w0 * sa)
			var d1 := Vector3(w1 * ca, 0, w1 * sa)
			var n := Vector3(-sa, 0.0, ca)
			var a0 := Vector3(x0, y0, 0.0) - d0
			var b0 := Vector3(x0, y0, 0.0) + d0
			var a1 := Vector3(x1, y1, 0.0) - d1
			var b1 := Vector3(x1, y1, 0.0) + d1
			st.set_normal(n); st.set_uv(Vector2(0.0, t0)); st.add_vertex(a0)
			st.set_normal(n); st.set_uv(Vector2(1.0, t0)); st.add_vertex(b0)
			st.set_normal(n); st.set_uv(Vector2(1.0, t1)); st.add_vertex(b1)
			st.set_normal(n); st.set_uv(Vector2(0.0, t0)); st.add_vertex(a0)
			st.set_normal(n); st.set_uv(Vector2(1.0, t1)); st.add_vertex(b1)
			st.set_normal(n); st.set_uv(Vector2(0.0, t1)); st.add_vertex(a1)
	return st.commit()


func _build_flora(terrain_scene: Node3D, fallen_log_xf: Transform3D, _rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	var flora := Node3D.new()
	flora.name = "CaveFlora"
	add_child(flora)

	if props_data.is_empty():
		props_data = _load_or_compute_props(terrain_scene)

	var f_data: Dictionary = props_data.get("flora", {})
	var grass_xf: Array = f_data.get("grass_xf", [])
	var fern_xf: Array = f_data.get("fern_xf", [])
	var plant_xf: Array = f_data.get("plant_xf", [])
	var bush_xf: Array = f_data.get("bush_xf", [])
	var shelf_xf: Array = f_data.get("shelf_xf", [])
	var grotto_mush_xf: Array = f_data.get("grotto_mush_xf", [])

	var leaves_tex := load("res://assets/nature/Leaves.png") as Texture2D
	var bush_tex := load("res://assets/nature/Leaves_TwistedTree_C.png") as Texture2D
	var mush_tex := load("res://assets/nature/Mushrooms.png") as Texture2D

	var leaves_mat := StandardMaterial3D.new()
	leaves_mat.albedo_texture = leaves_tex
	leaves_mat.albedo_color = Color(0.84, 0.96, 0.72)
	leaves_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaves_mat.alpha_scissor_threshold = 0.42
	leaves_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaves_mat.roughness = 0.85
	leaves_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_texture = bush_tex
	bush_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	bush_mat.alpha_scissor_threshold = 0.45
	bush_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bush_mat.roughness = 0.85
	bush_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	if terrain_scene != null:
		var ov_grass := terrain_scene.get_node_or_null("Grass") as MultiMeshInstance3D
		if ov_grass != null and ov_grass.material_override is ShaderMaterial:
			_grass_shader_mat = (ov_grass.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	if _grass_shader_mat == null:
		_grass_shader_mat = ShaderMaterial.new()
		_grass_shader_mat.shader = load("res://terrain/grass.gdshader") as Shader
		_grass_shader_mat.set_shader_parameter("grass_texture", load("res://assets/nature/Grass.png") as Texture2D)
		_grass_shader_mat.set_shader_parameter("alpha_scissor_threshold", 0.45)

	var fern_mesh := _extract_surface_mesh("res://assets/nature/Fern_1.gltf", [0], [leaves_mat])
	var plant_mesh := _extract_surface_mesh("res://assets/nature/Plant_1.gltf", [0], [leaves_mat])
	var bush_mesh := _extract_surface_mesh("res://assets/nature/Bush_Common.gltf", [0], [bush_mat])
	var grass_mesh := _extract_surface_mesh("res://assets/nature/Grass_Common_Tall.gltf", [0], [])

	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_texture = mush_tex
	shelf_mat.albedo_color = Color(1.0, 0.92, 0.78)
	shelf_mat.roughness = 0.78
	shelf_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var shelf_mesh := _extract_surface_mesh("res://assets/nature/Mushroom_Laetiporus.gltf", [0], [shelf_mat])

	var grotto_mush_mat := StandardMaterial3D.new()
	grotto_mush_mat.albedo_texture = mush_tex
	grotto_mush_mat.albedo_color = Color(0.84, 0.90, 0.95)
	grotto_mush_mat.emission_enabled = true
	grotto_mush_mat.emission = Color(0.14, 0.50, 0.64)
	grotto_mush_mat.emission_energy_multiplier = 0.06
	grotto_mush_mat.roughness = 0.72
	grotto_mush_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var grotto_mush_mesh := _extract_surface_mesh("res://assets/nature/Mushroom_Common.gltf", [0], [grotto_mush_mat])

	var add_mm := func(n_name: String, m: Mesh, mat_ov: Material, xfs: Array, shadows: bool) -> Node3D:
		if m == null or xfs.is_empty():
			return null
		var holder := Node3D.new()
		holder.name = n_name
		flora.add_child(holder)
		var sh := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_zoned_multimeshes(holder, n_name, m, xfs, [], sh, mat_ov, 105.0, 14.0, 2.5)
		return holder

	_flora_grass_node = add_mm.call("MoundGrass", grass_mesh, _grass_shader_mat, grass_xf, false)
	add_mm.call("MoundFerns", fern_mesh, null, fern_xf, false)
	add_mm.call("MoundPlants", plant_mesh, null, plant_xf, false)
	add_mm.call("MoundBushes", bush_mesh, null, bush_xf, false)
	add_mm.call("LogShelfFungi", shelf_mesh, null, shelf_xf, false)
	add_mm.call("GrottoMushrooms", grotto_mush_mesh, null, grotto_mush_xf, false)


# ==============================================================================
# P6: GEODE PRISMATIC CRYSTAL CORE COLLECTIBLE & ACOUSTIC REVERB ZONES
# ==============================================================================

func _build_faceted_icosahedron(radius: float, subdivisions: int = 2) -> ArrayMesh:
	var t_gold := (1.0 + sqrt(5.0)) * 0.5
	var base_v: Array[Vector3] = [
		Vector3(-1,  t_gold,  0).normalized(),
		Vector3( 1,  t_gold,  0).normalized(),
		Vector3(-1, -t_gold,  0).normalized(),
		Vector3( 1, -t_gold,  0).normalized(),
		Vector3( 0, -1,  t_gold).normalized(),
		Vector3( 0,  1,  t_gold).normalized(),
		Vector3( 0, -1, -t_gold).normalized(),
		Vector3( 0,  1, -t_gold).normalized(),
		Vector3( t_gold,  0, -1).normalized(),
		Vector3( t_gold,  0,  1).normalized(),
		Vector3(-t_gold,  0, -1).normalized(),
		Vector3(-t_gold,  0,  1).normalized(),
	]
	var tris: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	for _s in subdivisions:
		var mid_cache: Dictionary = {}
		var new_tris: Array[Vector3i] = []
		var get_mid := func(i0: int, i1: int) -> int:
			var a := mini(i0, i1)
			var b := maxi(i0, i1)
			var key := (a << 16) | b
			if mid_cache.has(key):
				return int(mid_cache[key])
			var vm := (base_v[i0] + base_v[i1]).normalized()
			var nid := base_v.size()
			base_v.append(vm)
			mid_cache[key] = nid
			return nid
		for tri: Vector3i in tris:
			var a: int = get_mid.call(tri.x, tri.y)
			var b: int = get_mid.call(tri.y, tri.z)
			var c: int = get_mid.call(tri.z, tri.x)
			new_tris.append(Vector3i(tri.x, a, c))
			new_tris.append(Vector3i(tri.y, b, a))
			new_tris.append(Vector3i(tri.z, c, b))
			new_tris.append(Vector3i(a, b, c))
		tris = new_tris

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri: Vector3i in tris:
		var p0: Vector3 = base_v[tri.x] * radius
		var p1: Vector3 = base_v[tri.y] * radius
		var p2: Vector3 = base_v[tri.z] * radius
		var uv0 := Vector2(atan2(p0.z, p0.x) / TAU + 0.5, asin(clampf(base_v[tri.x].y, -1.0, 1.0)) / PI + 0.5)
		var uv1 := Vector2(atan2(p1.z, p1.x) / TAU + 0.5, asin(clampf(base_v[tri.y].y, -1.0, 1.0)) / PI + 0.5)
		var uv2_v := Vector2(atan2(p2.z, p2.x) / TAU + 0.5, asin(clampf(base_v[tri.z].y, -1.0, 1.0)) / PI + 0.5)
		_add_tri_outward(st, p0, p1, p2, uv0, uv1, uv2_v, Vector3.ZERO, 1.0)
	return st.commit()


## Sculpted Multi-Blade Sovereign Geode Heart Shard Cluster (chunky interlocking double-terminated crystal blocks).
static func _build_octa_heart_crystal_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Primary Sovereign Core Chunk (bold chunky oblique chisel crystal block + faceted lower keel)
	_add_chisel_crystal_to_st(
		st,
		Vector3(0.0, -0.02, 0.0),
		Vector3(0.08, 1.00, -0.05),
		0.43,
		0.43,
		0.38,
		0.54,
		0.84,
		0.28,
		1.20,
		0.84,
		Color(0.18, 0.90, 1.0),
		true,
		true,
		0.62,
		1.0,
		false
	)
	# 2. Secondary Royal Amethyst Chunk blooming out at +32 deg
	_add_chisel_crystal_to_st(
		st,
		Vector3(0.22, -0.06, 0.14),
		Vector3(0.50, 0.85, 0.22),
		0.295,
		0.295,
		0.255,
		0.38,
		0.62,
		1.15,
		1.16,
		0.86,
		Color(0.76, 0.22, 1.0),
		true,
		true,
		0.44,
		1.0,
		true
	)
	# 3. Counter Turquoise Left-Back Crystal Block
	_add_chisel_crystal_to_st(
		st,
		Vector3(-0.23, -0.02, -0.12),
		Vector3(-0.54, 0.83, -0.20),
		0.275,
		0.275,
		0.235,
		0.34,
		0.56,
		-0.90,
		0.88,
		1.16,
		Color(0.08, 0.98, 0.86),
		true,
		true,
		0.40,
		1.0,
		false
	)
	# 4. Crisp Lower Cobalt-Sapphire Spur Chunk
	_add_chisel_crystal_to_st(
		st,
		Vector3(0.03, -0.14, -0.20),
		Vector3(0.16, 0.76, -0.62),
		0.225,
		0.225,
		0.188,
		0.26,
		0.44,
		2.20,
		1.12,
		0.88,
		Color(0.24, 0.56, 1.0),
		true,
		true,
		0.32,
		1.0,
		true
	)

	st.generate_tangents()
	return st.commit()


func _build_geode_reward() -> void:
	var sdf := get_sdf()
	var gc: Vector3 = CaveLayout.CHAMBERS["geode_pocket"]["c"]
	var altar_fy := _sample_floor_y(sdf, gc.x, gc.y + 3.0, gc.z - 0.4)
	var altar_world := CaveLayout.to_world(Vector3(gc.x, altar_fy - 0.08, gc.z - 0.4))
	var reward_world := CaveLayout.to_world(Vector3(gc.x, altar_fy + 2.02, gc.z - 0.4))

	var crystal_shader := load("res://terrain/cave_crystal.gdshader") as Shader
	var crown_mat := ShaderMaterial.new()
	crown_mat.shader = crystal_shader
	crown_mat.set_shader_parameter("emission_strength", 1.15)
	crown_mat.set_shader_parameter("striation_normal", _get_crystal_striation_normal_tex())
	crown_mat.set_shader_parameter("interior_veil_tex", _get_crystal_interior_tex())

	# 1. Elevated 2-Tier Obsidian Caldera Shrine Plinth + Sleek Radial Quartz Calyx (height ~ 0.98m cradling the floating shard!)
	var st_altar := SurfaceTool.new()
	st_altar.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altar_sides := 10
	var b0: Array[Vector3] = []
	var b1: Array[Vector3] = []
	var b2: Array[Vector3] = []
	var b_rim: Array[Vector3] = []
	for i in altar_sides:
		var a := (float(i) / float(altar_sides)) * TAU + 0.14 * sin(float(i) * 2.7)
		var r0 := 1.48 + 0.16 * cos(float(i) * 3.1)
		var r1 := 1.12 + 0.12 * sin(float(i) * 2.3)
		var r2 := 0.84 + 0.09 * cos(float(i) * 3.7)
		var r3 := 0.56 + 0.05 * sin(float(i) * 2.9)
		var h1 := 0.42 + 0.08 * sin(float(i) * 2.5)
		var h2 := 0.94 + 0.10 * cos(float(i) * 2.0 + 0.5)
		var h3 := 0.72 + 0.05 * cos(float(i) * 3.3)
		b0.append(Vector3(cos(a) * r0, -0.40, sin(a) * r0))
		b1.append(Vector3(cos(a) * r1, h1, sin(a) * r1))
		b2.append(Vector3(cos(a) * r2, h2, sin(a) * r2))
		b_rim.append(Vector3(cos(a) * r3, h3, sin(a) * r3))
	var bowl_center := Vector3(0.0, 0.52, 0.0)
	var plinth_ref := Vector3(0.0, 0.18, 0.0)
	var plinth_col := Color(0.06, 0.09, 0.14)
	for i in altar_sides:
		var nxt := (i + 1) % altar_sides
		var u0 := float(i) / float(altar_sides)
		var u1 := float(i + 1) / float(altar_sides)
		_add_tri_outward(st_altar, b0[i], b1[nxt], b0[nxt], Vector2(u0, 0.0), Vector2(u1, 0.35), Vector2(u1, 0.0), plinth_ref, 0.0, plinth_col, true)
		_add_tri_outward(st_altar, b0[i], b1[i], b1[nxt], Vector2(u0, 0.0), Vector2(u0, 0.35), Vector2(u1, 0.35), plinth_ref, 0.0, plinth_col, true)
		_add_tri_outward(st_altar, b1[i], b2[nxt], b1[nxt], Vector2(u0, 0.35), Vector2(u1, 0.72), Vector2(u1, 0.35), plinth_ref, 0.0, plinth_col, true)
		_add_tri_outward(st_altar, b1[i], b2[i], b2[nxt], Vector2(u0, 0.35), Vector2(u0, 0.72), Vector2(u1, 0.72), plinth_ref, 0.0, plinth_col, true)
		_add_tri_outward(st_altar, b2[i], b_rim[nxt], b2[nxt], Vector2(u0, 0.72), Vector2(u1, 0.88), Vector2(u1, 0.72), Vector3(0.0, 0.25, 0.0), 0.0, plinth_col, true)
		_add_tri_outward(st_altar, b2[i], b_rim[i], b_rim[nxt], Vector2(u0, 0.72), Vector2(u0, 0.88), Vector2(u1, 0.88), Vector3(0.0, 0.25, 0.0), 0.0, plinth_col, true)
		_add_tri_outward(st_altar, b_rim[i], bowl_center, b_rim[nxt], Vector2(u0, 0.88), Vector2(0.5 * (u0 + u1), 1.0), Vector2(u1, 0.88), Vector3(0.0, -0.25, 0.0), 0.0, plinth_col, true)

	# 6 Bold Chunky Quartz Frame Blocks rising around the obsidian plinth shoulder (~1.7:1 mineral proportions)
	var jaw_cols := [
		Color(0.10, 0.86, 1.0),
		Color(0.58, 0.26, 1.0),
		Color(0.16, 0.94, 0.84),
		Color(0.24, 0.58, 1.0),
		Color(0.10, 0.88, 1.0),
		Color(0.64, 0.28, 1.0),
	]
	for ji in 6:
		var th := (float(ji) / 6.0) * TAU + 0.18 * sin(float(ji) * 1.9)
		var r_ring := 0.82 + 0.08 * cos(float(ji) * 2.3)
		var j_pos := Vector3(cos(th) * r_ring, 0.66, sin(th) * r_ring)
		var out_lean := 0.40 + 0.12 * float(ji % 2)
		var tang_lean := 0.10 * (1.0 if ji % 2 == 0 else -1.0)
		var j_dir := Vector3(cos(th) * out_lean - sin(th) * tang_lean, 0.90, sin(th) * out_lean + cos(th) * tang_lean).normalized()
		var h_sc := 0.86 if (ji % 3 == 1) else (1.18 if (ji % 3 == 0) else 1.02)
		_add_chisel_crystal_to_st(
			st_altar,
			j_pos,
			j_dir,
			0.225 * (0.90 + 0.12 * h_sc),
			0.225,
			0.195 * (0.90 + 0.12 * h_sc),
			0.54 * h_sc,
			0.74 * h_sc,
			th * 1.4,
			1.18 if (ji % 2 == 0) else 0.88,
			0.86 if (ji % 2 == 0) else 1.16,
			jaw_cols[ji],
			true,
			false,
			0.35,
			1.0,
			(ji % 2 == 1)
		)
	# Glowing inner crucible chunky crystal seed cluster beneath levitating heart
	for ci in 3:
		var ca := float(ci) * (TAU / 3.0) + 0.40
		_add_chisel_crystal_to_st(
			st_altar,
			Vector3(cos(ca) * 0.20, 0.48, sin(ca) * 0.20),
			Vector3(cos(ca) * 0.24, 0.97, sin(ca) * 0.24),
			0.15,
			0.15,
			0.128,
			0.25,
			0.36,
			ca,
			1.14,
			0.88,
			Color(0.12, 0.94, 1.0),
			true,
			false,
			0.35,
			1.0,
			true
		)

	st_altar.generate_tangents()
	var altar_mesh := st_altar.commit()
	altar_mesh.surface_set_material(0, crown_mat)
	var altar_mi := MeshInstance3D.new()
	altar_mi.name = "GeodeAltarPedestal"
	altar_mi.mesh = altar_mesh
	altar_mi.position = altar_world
	altar_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(altar_mi)

	# 2. Floating Levitating GeodeReward Hero Cluster Centerpiece (clean silhouette, zero black pancake/wire antennae)
	var root_r := Node3D.new()
	root_r.name = "GeodeReward"
	root_r.position = reward_world
	add_child(root_r)
	_geode_reward_node = root_r

	var orb_pivot := Node3D.new()
	orb_pivot.name = "GeodeHeartMesh"
	root_r.add_child(orb_pivot)
	_geode_reward_mesh = orb_pivot

	# 2A. Hero Multi-Blade Sovereign Geode Shard Cluster (`OrbCore`)
	var orb_mat := ShaderMaterial.new()
	orb_mat.shader = load("res://terrain/cave_orb.gdshader") as Shader
	orb_mat.set_shader_parameter("interior_veil_tex", _get_crystal_interior_tex())
	orb_mat.set_shader_parameter("emission_strength", 1.38)
	var orb_mi := MeshInstance3D.new()
	orb_mi.name = "OrbCore"
	orb_mi.mesh = _build_octa_heart_crystal_mesh()
	orb_mi.scale = Vector3(1.10, 1.10, 1.10)
	orb_mi.material_override = orb_mat
	orb_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb_pivot.add_child(orb_mi)

	# 2B. Five Orbiting Radiant Double-Terminated Chunky Gem Shards (part_u = 2.0 -> glowing tips at BOTH ends, zero black bottom AO)
	var sat_cols := [
		Color(0.14, 0.94, 1.0),
		Color(0.68, 0.30, 1.0),
		Color(0.18, 0.96, 0.84),
		Color(0.28, 0.64, 1.0),
		Color(0.56, 0.34, 1.0),
	]
	for si in 5:
		var st_sat := SurfaceTool.new()
		st_sat.begin(Mesh.PRIMITIVE_TRIANGLES)
		var s_sc := 0.86 + 0.24 * float(si % 2)
		_add_chisel_crystal_to_st(st_sat, Vector3.ZERO, Vector3.UP, 0.135 * s_sc, 0.135 * s_sc, 0.112 * s_sc, 0.16 * s_sc, 0.27 * s_sc, float(si) * 0.9, 1.20, 0.82, sat_cols[si], true, true, 0.20 * s_sc, 2.0, (si % 2 == 1))
		st_sat.generate_tangents()
		var sat_mesh := st_sat.commit()
		sat_mesh.surface_set_material(0, crown_mat)
		var sat_mi := MeshInstance3D.new()
		sat_mi.name = "OrbSat%d" % si
		sat_mi.mesh = sat_mesh
		sat_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a0_s := float(si) * (TAU / 5.0)
		sat_mi.position = Vector3(cos(a0_s) * 1.08, sin(a0_s) * 0.28, sin(a0_s) * 1.08)
		orb_pivot.add_child(sat_mi)
		_geode_orb_satellites.append(sat_mi)

	var area := Area3D.new()
	area.name = "GeodeRewardArea"
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.6
	cs.shape = sph
	area.add_child(cs)
	area.body_entered.connect(_on_geode_area_body_entered)
	root_r.add_child(area)
	_geode_reward_area = area


static func _add_smooth_tri_outward(
		st: SurfaceTool,
		p0: Vector3,
		p1: Vector3,
		p2: Vector3,
		n0: Vector3,
		n1: Vector3,
		n2: Vector3,
		uv0: Vector2,
		uv1: Vector2,
		uv2_v: Vector2,
		c0: Color,
		c1: Color,
		c2: Color,
		hint_out: Vector3,
		use_uv2: bool = false,
		uv2_0 := Vector2.ZERO,
		uv2_1 := Vector2.ZERO,
		uv2_2 := Vector2.ZERO
) -> void:
	var fn := (p2 - p0).cross(p1 - p0)
	if fn.length_squared() < 1e-10:
		return
	var a1 := p1; var a2 := p2
	var an1 := n1; var an2 := n2
	var au1 := uv1; var au2 := uv2_v
	var ac1 := c1; var ac2 := c2
	var ax1 := uv2_1; var ax2 := uv2_2
	if fn.dot(hint_out) < 0.0:
		a1 = p2; a2 = p1
		an1 = n2; an2 = n1
		au1 = uv2_v; au2 = uv1
		ac1 = c2; ac2 = c1
		ax1 = uv2_2; ax2 = uv2_1
	st.set_color(c0)
	if use_uv2:
		st.set_uv2(uv2_0)
	st.set_normal(n0.normalized()); st.set_uv(uv0); st.add_vertex(p0)
	st.set_color(ac1)
	if use_uv2:
		st.set_uv2(ax1)
	st.set_normal(an1.normalized()); st.set_uv(au1); st.add_vertex(a1)
	st.set_color(ac2)
	if use_uv2:
		st.set_uv2(ax2)
	st.set_normal(an2.normalized()); st.set_uv(au2); st.add_vertex(a2)


static func _emit_smooth_grid(
		st: SurfaceTool,
		grid_pts: Array,
		grid_uvs: Array,
		grid_cols: Array,
		grid_outs: Array,
		closed_u: bool = false,
		closed_v: bool = false,
		use_uv2: bool = false,
		mat_id: float = 0.0,
		grid_phases: Array = [],
		grid_explicit_nrms: Array = []
) -> void:
	var nu := grid_pts.size()
	if nu < 2:
		return
	var row0: Array = grid_pts[0]
	var nv := row0.size()
	if nv < 2:
		return

	var has_explicit_nrms := grid_explicit_nrms.size() == nu
	var grid_nrms: Array = []
	for iu in nu:
		var nrow: Array[Vector3] = []
		var iu_prev := (iu - 1 + nu) % nu if closed_u else maxi(iu - 1, 0)
		var iu_next := (iu + 1) % nu if closed_u else mini(iu + 1, nu - 1)
		var row_cur: Array = grid_pts[iu]
		var row_prev: Array = grid_pts[iu_prev]
		var row_next: Array = grid_pts[iu_next]
		var out_row: Array = grid_outs[iu]
		var exp_row: Array = grid_explicit_nrms[iu] if has_explicit_nrms else []
		for iv in nv:
			if has_explicit_nrms and iv < exp_row.size():
				nrow.append((exp_row[iv] as Vector3).normalized())
				continue
			var iv_prev := (iv - 1 + nv) % nv if closed_v else maxi(iv - 1, 0)
			var iv_next := (iv + 1) % nv if closed_v else mini(iv + 1, nv - 1)
			var p_u0: Vector3 = row_prev[iv]
			var p_u1: Vector3 = row_next[iv]
			var p_v0: Vector3 = row_cur[iv_prev]
			var p_v1: Vector3 = row_cur[iv_next]
			var tu := p_u1 - p_u0
			var tv := p_v1 - p_v0
			var hint_v: Vector3 = out_row[iv]
			var nrm := tv.cross(tu)
			if nrm.length_squared() < 1e-9:
				nrm = hint_v.normalized()
			else:
				nrm = nrm.normalized()
				if nrm.dot(hint_v) < 0.0:
					nrm = -nrm
			nrow.append(nrm)
		grid_nrms.append(nrow)

	var u_quads := nu if closed_u else (nu - 1)
	var v_quads := nv if closed_v else (nv - 1)
	var has_phases := grid_phases.size() == nu
	for iu in u_quads:
		var iu1 := (iu + 1) % nu
		var pts0: Array = grid_pts[iu]
		var pts1: Array = grid_pts[iu1]
		var nrm0: Array = grid_nrms[iu]
		var nrm1: Array = grid_nrms[iu1]
		var uvs0: Array = grid_uvs[iu]
		var uvs1: Array = grid_uvs[iu1]
		var col0: Array = grid_cols[iu]
		var col1: Array = grid_cols[iu1]
		var out0: Array = grid_outs[iu]
		var out1: Array = grid_outs[iu1]
		var ph0: Array = grid_phases[iu] if has_phases else []
		var ph1: Array = grid_phases[iu1] if has_phases else []
		for iv in v_quads:
			var iv1 := (iv + 1) % nv
			var p00: Vector3 = pts0[iv]
			var p10: Vector3 = pts1[iv]
			var p11: Vector3 = pts1[iv1]
			var p01: Vector3 = pts0[iv1]
			var n00: Vector3 = nrm0[iv]
			var n10: Vector3 = nrm1[iv]
			var n11: Vector3 = nrm1[iv1]
			var n01: Vector3 = nrm0[iv1]
			var uv00: Vector2 = uvs0[iv]
			var uv10: Vector2 = uvs1[iv]
			var uv11: Vector2 = uvs1[iv1]
			var uv01: Vector2 = uvs0[iv1]
			var c00: Color = col0[iv]
			var c10: Color = col1[iv]
			var c11: Color = col1[iv1]
			var c01: Color = col0[iv1]
			var h00: Vector3 = out0[iv]
			var h10: Vector3 = out1[iv]
			var h11: Vector3 = out1[iv1]
			var h01: Vector3 = out0[iv1]
			var q_hint := (h00 + h10 + h11 + h01)
			if q_hint.length_squared() < 1e-8:
				q_hint = Vector3.BACK
			else:
				q_hint = q_hint.normalized()
			var x00 := Vector2(mat_id, float(ph0[iv]) if has_phases else 0.0)
			var x10 := Vector2(mat_id, float(ph1[iv]) if has_phases else 0.0)
			var x11 := Vector2(mat_id, float(ph1[iv1]) if has_phases else 0.0)
			var x01 := Vector2(mat_id, float(ph0[iv1]) if has_phases else 0.0)
			_add_smooth_tri_outward(st, p00, p10, p11, n00, n10, n11, uv00, uv10, uv11, c00, c10, c11, q_hint, use_uv2, x00, x10, x11)
			_add_smooth_tri_outward(st, p00, p11, p01, n00, n11, n01, uv00, uv11, uv01, c00, c11, c01, q_hint, use_uv2, x00, x11, x01)


static func _ogive_half_width_at_y(
		y: float,
		half_span: float = 3.55,
		spring_y: float = 4.60,
		apex_y: float = 11.45,
		y_root: float = -0.55,
		flare_amt: float = 0.56
) -> float:
	if y <= spring_y:
		var root_t := clampf(1.0 - (y - y_root) / maxf(spring_y - y_root, 0.01), 0.0, 1.0)
		return half_span + flare_amt * pow(root_t, 2.15)
	if y >= apex_y:
		return 0.0
	var h_arch := apex_y - spring_y
	var c_off := (h_arch * h_arch - half_span * half_span) / maxf(2.0 * half_span, 0.01)
	var r_arch := half_span + c_off
	var dy := y - spring_y
	var rad_sq := maxf(r_arch * r_arch - dy * dy, 0.0)
	return maxf(sqrt(rad_sq) - c_off, 0.0)


static func _ogive_arch_frame(
		t: float,
		half_span: float = 3.55,
		spring_y: float = 4.60,
		apex_y: float = 11.45,
		y_root: float = -0.55,
		flare_amt: float = 0.56
) -> Dictionary:
	# t in [0..1]: 0.0 = left root, 0.5 = pointed crown apex, 1.0 = right root
	var is_right := t > 0.5
	var u := (1.0 - t) * 2.0 if is_right else (t * 2.0) # u in [0..1] from root -> apex
	var side_s := 1.0 if is_right else -1.0
	var spring_frac := 0.40
	var pos_2d := Vector2.ZERO
	var out_2d := Vector2.ZERO
	if u <= spring_frac:
		var f := u / spring_frac
		var y := lerpf(y_root, spring_y, f)
		var root_t := 1.0 - f
		var hw := half_span + flare_amt * pow(root_t, 2.15)
		var dhw_dy := -flare_amt * 2.15 * pow(maxf(root_t, 0.0), 1.15) / maxf(spring_y - y_root, 0.01)
		pos_2d = Vector2(side_s * hw, y)
		# Curve point (side_s * hw(y), y); outward normal points away from x=0
		out_2d = Vector2(side_s, -dhw_dy).normalized()
	else:
		var fa := (u - spring_frac) / (1.0 - spring_frac)
		var h_arch := apex_y - spring_y
		var c_off := (h_arch * h_arch - half_span * half_span) / maxf(2.0 * half_span, 0.01)
		var r_arch := half_span + c_off
		var alpha_top := acos(clampf(c_off / r_arch, -1.0, 1.0))
		var alpha := fa * alpha_top
		var hw := -c_off + r_arch * cos(alpha)
		var y := spring_y + r_arch * sin(alpha)
		pos_2d = Vector2(side_s * maxf(hw, 0.0), y)
		out_2d = Vector2(side_s * cos(alpha), sin(alpha)).normalized()
		# Blend outward normal smoothly near pointed apex so lofted moldings form a crisp spire hood without pinching
		var apex_blend := smoothstep(0.88, 1.0, fa)
		out_2d = out_2d.lerp(Vector2(0.0, 1.0), apex_blend * 0.86).normalized()
	return {"pos": pos_2d, "out": out_2d}


static func _sculpt_lofted_tube(
		st: SurfaceTool,
		spine_pts: Array[Vector3],
		radii_a: Array[float],
		radii_b: Array[float],
		sides: int,
		mat_id: float,
		phase: float = 0.0,
		ao_start: float = 0.84,
		ao_end: float = 0.96,
		bevel: float = 0.82,
		accent: float = 0.25,
		flute_amp: float = 0.0,
		flute_freq: float = 5.0,
		twist_rad: float = 0.0,
		use_uv2: bool = true,
		rock_wet: float = 0.30,
		rock_curv: float = 0.65
) -> void:
	var n_spine := spine_pts.size()
	if n_spine < 2 or sides < 4:
		return
	var grid_pts: Array = []
	var grid_uvs: Array = []
	var grid_cols: Array = []
	var grid_outs: Array = []
	var grid_phases: Array = []

	var prev_nrm := Vector3.ZERO
	for si in n_spine:
		var f := float(si) / float(n_spine - 1)
		var p_cur: Vector3 = spine_pts[si]
		var tang: Vector3
		if si == 0:
			tang = (spine_pts[1] - spine_pts[0]).normalized()
		elif si == n_spine - 1:
			tang = (spine_pts[n_spine - 1] - spine_pts[n_spine - 2]).normalized()
		else:
			tang = (spine_pts[si + 1] - spine_pts[si - 1]).normalized()
		if tang.length_squared() < 1e-6:
			tang = Vector3.UP

		var frame_n: Vector3
		if si == 0:
			var ref := Vector3.BACK if absf(tang.dot(Vector3.BACK)) < 0.90 else Vector3.RIGHT
			frame_n = (ref - tang * ref.dot(tang)).normalized()
		else:
			frame_n = prev_nrm - tang * prev_nrm.dot(tang)
			if frame_n.length_squared() < 1e-6:
				var ref2 := Vector3.RIGHT if absf(tang.dot(Vector3.RIGHT)) < 0.90 else Vector3.UP
				frame_n = (ref2 - tang * ref2.dot(tang)).normalized()
			else:
				frame_n = frame_n.normalized()
		prev_nrm = frame_n
		var frame_b := tang.cross(frame_n).normalized()

		var ra := radii_a[mini(si, radii_a.size() - 1)]
		var rb := radii_b[mini(si, radii_b.size() - 1)]
		var ao_cur := lerpf(ao_start, ao_end, f)

		var row_p: Array[Vector3] = []
		var row_uv: Array[Vector2] = []
		var row_c: Array[Color] = []
		var row_o: Array[Vector3] = []
		var row_ph: Array[float] = []
		for vi in sides:
			var vf := float(vi) / float(sides)
			var ang := vf * TAU + f * twist_rad
			var flute := 1.0 + flute_amp * cos(vf * TAU * flute_freq)
			var ca := cos(ang)
			var sa := sin(ang)
			var out_dir := (frame_n * (ca * maxf(rb, 0.004)) + frame_b * (sa * maxf(ra, 0.004))).normalized()
			var offset := (frame_n * (ca * ra) + frame_b * (sa * rb)) * flute
			row_p.append(p_cur + offset)
			row_uv.append(Vector2(vf, f))
			var back_ao := lerpf(0.72, 1.0, clampf(0.5 + 0.5 * out_dir.z, 0.0, 1.0))
			if use_uv2:
				row_c.append(Color(ao_cur * back_ao, bevel, accent, 1.0))
			else:
				var rock_back_ao := lerpf(0.88, 1.0, clampf(0.5 + 0.5 * out_dir.z, 0.0, 1.0))
				var curv_v := clampf(rock_curv + flute_amp * cos(vf * TAU * flute_freq) * 0.6, 0.22, 0.92)
				row_c.append(Color(ao_cur * rock_back_ao, 0.0, rock_wet, curv_v))
			row_o.append(out_dir)
			row_ph.append(phase + f * 0.35)
		grid_pts.append(row_p)
		grid_uvs.append(row_uv)
		grid_cols.append(row_c)
		grid_outs.append(row_o)
		grid_phases.append(row_ph)

	_emit_smooth_grid(st, grid_pts, grid_uvs, grid_cols, grid_outs, false, true, use_uv2, mat_id, grid_phases)


static func _sculpt_smooth_torus_arc(
		st: SurfaceTool,
		center: Vector3,
		r_in: float,
		r_out: float,
		depth: float,
		segs: int,
		prof_segs: int,
		mat_id: float,
		phase: float = 0.0,
		ao: float = 0.94,
		bevel: float = 0.88,
		accent: float = 0.32,
		arc_start: float = 0.0,
		arc_span: float = TAU
) -> void:
	var closed := absf(arc_span - TAU) < 1e-3
	var r_mid := (r_in + r_out) * 0.5
	var r_tube := maxf((r_out - r_in) * 0.5, 0.008)
	var z_tube := maxf(depth * 0.5, 0.008)
	var u_count := segs if closed else (segs + 1)
	var v_count := maxi(prof_segs, 6)

	var grid_pts: Array = []
	var grid_uvs: Array = []
	var grid_cols: Array = []
	var grid_outs: Array = []
	var grid_phases: Array = []

	for iu in u_count:
		var uf := float(iu) / float(segs)
		var ang := arc_start + uf * arc_span
		var rad_dir := Vector3(cos(ang), sin(ang), 0.0)
		var ring_c := center + rad_dir * r_mid
		var pinch_end := 1.0
		if not closed:
			pinch_end = clampf(sin(uf * PI) * 2.6, 0.14, 1.0)

		var row_p: Array[Vector3] = []
		var row_uv: Array[Vector2] = []
		var row_c: Array[Color] = []
		var row_o: Array[Vector3] = []
		var row_ph: Array[float] = []
		for iv in v_count:
			var vf := float(iv) / float(v_count)
			var pa := vf * TAU
			var cp := cos(pa)
			var sp := sin(pa)
			# Superellipse almond-bevel profile (smoothly rounded, zero flat box facets)
			var sx := signf(cp) * pow(absf(cp), 0.82)
			var sz := signf(sp) * pow(absf(sp), 0.82)
			var p := ring_c + rad_dir * (sx * r_tube * pinch_end) + Vector3(0.0, 0.0, sz * z_tube * pinch_end)
			var out_v := (rad_dir * (cp / maxf(r_tube, 0.005)) + Vector3(0.0, 0.0, sp / maxf(z_tube, 0.005))).normalized()
			var shade_ao := ao * lerpf(0.76, 1.0, clampf(0.5 + 0.5 * sz, 0.0, 1.0))
			row_p.append(p)
			row_uv.append(Vector2(vf, uf))
			row_c.append(Color(shade_ao, bevel * (0.65 + 0.35 * absf(cp)), accent, 1.0))
			row_o.append(out_v)
			row_ph.append(phase + uf * 0.25)
		grid_pts.append(row_p)
		grid_uvs.append(row_uv)
		grid_cols.append(row_c)
		grid_outs.append(row_o)
		grid_phases.append(row_ph)

	_emit_smooth_grid(st, grid_pts, grid_uvs, grid_cols, grid_outs, closed, true, true, mat_id, grid_phases)


static func _sample_door_wall_z_and_nrm(
		sdf: CaveSDF,
		door_xf: Transform3D,
		inv_basis_door: Basis,
		px: float,
		py: float,
		z_aim: float = 0.6
) -> Dictionary:
	# Cast a 3D radial ray from deep inside open Vault Sanctum chamber air (z = +14.2m) through (px, py_wall, z_aim)
	# into solid rock. Works seamlessly across wide side walls (|px| ~ 16m) and high ceiling domes (py ~ 19m).
	var py_wall := maxf(py, 0.75)
	var p_air := Vector3(clampf(px * 0.14, -2.5, 2.5), clampf(py_wall * 0.44 + 3.0, 2.8, 10.6), 14.2)
	var p_mid := Vector3(px, py_wall, z_aim)
	var p_deep := p_air + (p_mid - p_air) * 2.30

	var step_n := 20
	var prev_p := p_air
	var lp0 := CaveLayout.to_local(door_xf * prev_p)
	var prev_d := sdf.eval_sdf_full(lp0.x, lp0.y, lp0.z, GEOFENCE_OVERWORLD_H)
	var hit_p := p_mid + Vector3(0.0, 0.0, -2.5)
	var found := false
	for si in range(1, step_n + 1):
		var cur_p := p_air.lerp(p_deep, float(si) / float(step_n))
		var lp := CaveLayout.to_local(door_xf * cur_p)
		var cur_d := sdf.eval_sdf_full(lp.x, lp.y, lp.z, GEOFENCE_OVERWORLD_H)
		if prev_d < 0.0 and cur_d >= 0.0:
			var lo_air := prev_p
			var hi_rock := cur_p
			for _bs in 6:
				var mid_p := 0.5 * (lo_air + hi_rock)
				var lpm := CaveLayout.to_local(door_xf * mid_p)
				if sdf.eval_sdf_full(lpm.x, lpm.y, lpm.z, GEOFENCE_OVERWORLD_H) >= 0.0:
					hi_rock = mid_p
				else:
					lo_air = mid_p
			hit_p = 0.5 * (lo_air + hi_rock)
			found = true
			break
		prev_p = cur_p
		prev_d = cur_d
	if not found:
		hit_p = p_air if prev_d >= 0.0 else p_deep

	# Sample relaxed Surface-Nets karst normal (blending eval_sdf_full at 0.66m with smooth chamber gradient)
	var w_hit := door_xf * hit_p
	var l_hit := CaveLayout.to_local(w_hit)
	var eps_f := 0.66
	var gu_f := sdf.eval_sdf_full(l_hit.x + eps_f, l_hit.y, l_hit.z, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(l_hit.x - eps_f, l_hit.y, l_hit.z, GEOFENCE_OVERWORLD_H)
	var gy_f := sdf.eval_sdf_full(l_hit.x, l_hit.y + eps_f, l_hit.z, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(l_hit.x, l_hit.y - eps_f, l_hit.z, GEOFENCE_OVERWORLD_H)
	var gs_f := sdf.eval_sdf_full(l_hit.x, l_hit.y, l_hit.z + eps_f, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(l_hit.x, l_hit.y, l_hit.z - eps_f, GEOFENCE_OVERWORLD_H)
	var grad_f := Vector3(gu_f, gy_f, gs_f)
	var grad_len := maxf(grad_f.length() / (2.0 * eps_f), 0.35)
	var nrm_f := (-grad_f).normalized() if grad_f.length_squared() > 1e-6 else Vector3(0.0, 0.0, 1.0)

	var eps_s := 0.80
	var gu_s := sdf.eval_cave_void_smooth(l_hit.x + eps_s, l_hit.y, l_hit.z) - sdf.eval_cave_void_smooth(l_hit.x - eps_s, l_hit.y, l_hit.z)
	var gy_s := sdf.eval_cave_void_smooth(l_hit.x, l_hit.y + eps_s, l_hit.z) - sdf.eval_cave_void_smooth(l_hit.x, l_hit.y - eps_s, l_hit.z)
	var gs_s := sdf.eval_cave_void_smooth(l_hit.x, l_hit.y, l_hit.z + eps_s) - sdf.eval_cave_void_smooth(l_hit.x, l_hit.y, l_hit.z - eps_s)
	var grad_s := Vector3(gu_s, gy_s, gs_s)
	var nrm_s := (-grad_s).normalized() if grad_s.length_squared() > 1e-6 else nrm_f

	var l_nrm := (nrm_f * 0.68 + nrm_s * 0.32).normalized()
	if l_nrm.dot(nrm_s) < 0.40:
		l_nrm = (l_nrm * 0.40 + nrm_s * 0.60).normalized()

	var w_nrm := Vector3(
		CaveLayout.RIGHT_XZ.x * l_nrm.x + CaveLayout.FWD_XZ.x * l_nrm.z,
		l_nrm.y,
		CaveLayout.RIGHT_XZ.y * l_nrm.x + CaveLayout.FWD_XZ.y * l_nrm.z
	).normalized()
	var d_nrm := (inv_basis_door * w_nrm).normalized()

	# Tangent-ring sample at VOXEL=0.55m matching tools/bake_cave.gd 3-pass Surface-Nets relaxation & Laplacian curvature
	var ref_up := Vector3.UP if absf(l_nrm.y) < 0.85 else Vector3.RIGHT
	var t1 := ref_up.cross(l_nrm).normalized()
	var t2 := l_nrm.cross(t1).normalized()
	var h_vox := 0.55
	var p1 := l_hit + t1 * h_vox
	var p2 := l_hit - t1 * h_vox
	var p3 := l_hit + t2 * h_vox
	var p4 := l_hit - t2 * h_vox
	var f_sum := (
		sdf.eval_sdf_full(p1.x, p1.y, p1.z, GEOFENCE_OVERWORLD_H)
		+ sdf.eval_sdf_full(p2.x, p2.y, p2.z, GEOFENCE_OVERWORLD_H)
		+ sdf.eval_sdf_full(p3.x, p3.y, p3.z, GEOFENCE_OVERWORLD_H)
		+ sdf.eval_sdf_full(p4.x, p4.y, p4.z, GEOFENCE_OVERWORLD_H)
	)
	var avg_delta := 0.25 * f_sum / grad_len
	var relax_shift := clampf(avg_delta * 0.40, -0.15, 0.18)
	var p_relaxed := hit_p + d_nrm * relax_shift
	var sdf_curv := clampf(0.5 - avg_delta * 0.62, 0.18, 0.84)

	# Exact 4-step SDF ambient occlusion matching tools/bake_cave.gd
	var ao_dists := [0.65, 1.45, 2.80, 4.80]
	var occ := 0.0
	var w_sum := 0.0
	for ai in 4:
		var ds: float = ao_dists[ai]
		var sp := l_hit + l_nrm * ds
		var clr := maxf(-sdf.eval_cave_void_smooth(sp.x, sp.y, sp.z), 0.0)
		var wt := 1.0 / float(ai + 1)
		occ += clampf(clr / ds, 0.0, 1.0) * wt
		w_sum += wt
	var sdf_ao := clampf(occ / maxf(w_sum, 0.01), 0.12, 1.0)
	return {"pos": p_relaxed, "nrm": d_nrm, "ao": sdf_ao, "curv": sdf_curv}


static func _build_door_wall_integration_mesh(door_xf: Transform3D, debug_grid: Array = [], use_cache: bool = false) -> ArrayMesh:
	if use_cache:
		if _cached_door_wall_mesh != null:
			var cached_o: Vector3 = _cached_door_wall_mesh.get_meta("door_origin", Vector3.INF)
			if cached_o.distance_to(door_xf.origin) < 0.01:
				return _cached_door_wall_mesh
		if ResourceLoader.exists(DOOR_WALL_MESH_PATH):
			var loaded := load(DOOR_WALL_MESH_PATH) as ArrayMesh
			if loaded != null and loaded.get_meta("door_origin", Vector3.INF).distance_to(door_xf.origin) < 0.01:
				_cached_door_wall_mesh = loaded
				return loaded

	var st_wall := SurfaceTool.new()
	st_wall.begin(Mesh.PRIMITIVE_TRIANGLES)

	var sdf := get_sdf()
	var inv_basis_door := door_xf.basis.inverse()

	# Unified Concave Karst Amphitheater Wall, Overhanging Stalactite Brow & Root Buttresses:
	# Bridges concavely from the carved ogival arch socket directly to CaveShell's forward-curving side walls
	# (|x| ~ 15.2m, z ~ +1.8m) and arched ceiling dome (y ~ 18.2m, z ~ +2.2m) so every rock facet faces inward
	# toward VaultDoorOmni with zero protruding mound and zero grazing shadow halo!
	var u_steps := 92
	var v_steps := 24
	var wall_pts: Array = []
	var wall_uvs: Array = []
	var wall_cols: Array = []
	var wall_outs: Array = []
	var sdf_nrms_grid: Array = []
	var sdf_curv_grid: Array = []
	var blend_grid: Array = []

	for iu in range(u_steps + 1):
		var u := float(iu) / float(u_steps)
		var frame := _round_arch_frame(u, 3.55, 6.20, -1.05)
		var base_xy: Vector2 = frame["pos"]
		var out_xy: Vector2 = frame["out"]
		var crown_w := exp(-pow((u - 0.5) / 0.18, 2.0))
		var floor_skirt_w := pow(clampf(1.0 - minf(u, 1.0 - u) / 0.17, 0.0, 1.0), 1.45)
		var rim_undul := 1.0 + 0.09 * sin(u * 13.0 + 0.5) + 0.06 * cos(u * 23.0 - 1.4) + 0.04 * sin(u * 37.0 + 2.2)

		# Inner rock rim tucks cleanly behind the outer stone pilasters, voussoirs & spandrel masonry (no protruding tube)
		var inner_clasp_wave := 0.12 * sin(u * 19.0 + 0.8) + 0.08 * cos(u * 33.0 - 0.5) + 0.05 * sin(u * 53.0 + 1.7)
		var r_clasping := 0.92 + inner_clasp_wave
		var r_far := (lerpf(11.65, 7.65, crown_w) + 0.72 * floor_skirt_w) * rim_undul
		var y_rad_scale := lerpf(0.86, 1.0, crown_w)

		var row_p: Array[Vector3] = []
		var row_uv: Array[Vector2] = []
		var row_c: Array[Color] = []
		var row_o: Array[Vector3] = []
		var row_sn: Array[Vector3] = []
		var row_sc: Array[float] = []
		var row_bw: Array[float] = []

		for iv in range(v_steps + 1):
			var v := float(iv) / float(v_steps)
			var cliff_bell := smoothstep(0.02, 0.16, v) * (1.0 - smoothstep(0.46, 0.76, v))
			var socket_fade := 1.0 - smoothstep(0.48, 0.76, v)

			# Karst fluting, limestone bedding ledges, root spurs & overhanging crown stalactite draperies
			var crag_a := (sin(u * 23.0 + v * 4.2 + 0.7) * 0.14 + cos(u * 39.0 - v * 6.5 + 1.9) * 0.08) * socket_fade
			var crag_b := (sin(u * 13.0 - v * 3.5 + 2.3) * 0.14 + cos(u * 19.0 + v * 5.2 - 0.8) * 0.08) * socket_fade
			var strata_ledge := sin((base_xy.y + v * 2.8) * 1.65 + crag_a * 1.5) * 0.11 * socket_fade

			var root_buttress := (
				exp(-pow((u - 0.08) / 0.055, 2.0)) * 0.58
				+ exp(-pow((u - 0.92) / 0.058, 2.0)) * 0.55
				+ exp(-pow((u - 0.17) / 0.050, 2.0)) * 0.44
				+ exp(-pow((u - 0.82) / 0.052, 2.0)) * 0.42
			)
			var haunch_spur := (
				exp(-pow((u - 0.29) / 0.055, 2.0)) * 0.36
				+ exp(-pow((u - 0.72) / 0.058, 2.0)) * 0.38
			)
			var brow_drapery := crown_w * (0.36 + 0.24 * pow(0.5 + 0.5 * cos((u - 0.5) * 68.0), 1.6))
			var buttress_lobe := (root_buttress + haunch_spur + brow_drapery) * socket_fade

			var radial_dist := lerpf(r_clasping, r_far, pow(v, 0.94))
			var px_aim := base_xy.x + out_xy.x * radial_dist + crag_a * (0.10 + 0.18 * v)
			var py_aim := base_xy.y + out_xy.y * radial_dist * y_rad_scale + crag_b * 0.10 * v
			py_aim -= floor_skirt_w * (0.46 + 1.35 * v)

			# Inner edge tucks cleanly behind/flush with the carved stone arch perimeter (z ~ 0.50) then swells naturally onto cliff rock
			var start_tuck := (1.0 - smoothstep(0.0, 0.18, v)) * 0.42
			var z_arch_0 := 0.92 - start_tuck + floor_skirt_w * (1.0 - v) * 0.18
			var p_arch_0 := Vector3(base_xy.x + out_xy.x * r_clasping, base_xy.y + out_xy.y * r_clasping * y_rad_scale, z_arch_0)

			# Sample the exact CaveShell rock surface under this (px_aim, py_aim) so the collar is a thin
			# rock-hugging shell: bounded offset from real rock everywhere, zero floating curtain edges.
			var wall_sample := _sample_door_wall_z_and_nrm(sdf, door_xf, inv_basis_door, px_aim, py_aim, z_arch_0)
			var p_cave: Vector3 = wall_sample["pos"]
			var nrm_cave: Vector3 = wall_sample["nrm"]
			var ao_cave: float = float(wall_sample["ao"])
			var curv_cave: float = float(wall_sample["curv"])

			# Blend from the stone-seated socket (v=0) onto the rock-hugging shell by mid wall
			var outer_w := smoothstep(0.04, 0.42, v)
			var p_pos := p_arch_0.lerp(p_cave, outer_w)

			# Sculpt the collar with CaveSDF's exact 3D karst noise & horizontal bedding strata
			var lp_m := CaveLayout.to_local(door_xf * p_pos)
			var n_mac := sdf._noise_macro.get_noise_3d(lp_m.x * 1.1, lp_m.y * 1.35, lp_m.z * 1.1)
			var n_frac := sdf._noise_fracture.get_noise_3d(lp_m.x * 0.9, lp_m.y * 1.15, lp_m.z * 0.9)
			var strata_3d := sin(lp_m.y * 0.85 + n_mac * 2.2 + lp_m.x * 0.10 - lp_m.z * 0.08) * 0.12
			var karst_disp := (n_mac * 0.52 + (n_frac - 0.5) * 0.30 + strata_3d * 0.7) * cliff_bell
			var buttress_disp := (0.16 * buttress_lobe + strata_ledge * 0.30) * cliff_bell

			# Gently step proud of rock across mid-wall without creating a narrow lip at v=0, then tuck behind at v=1
			var proud_h := lerpf(0.06, 0.22, smoothstep(0.0, 0.22, v)) * (1.0 - smoothstep(0.30, 0.86, v)) + 0.07 * smoothstep(0.22, 0.84, v)
			var tuck_start := 0.80 + 0.03 * sin(u * 27.0 + 1.1) + 0.02 * cos(u * 41.0 - 0.7)
			var feather_tuck := smoothstep(tuck_start, 1.0, v) * 0.16
			var cliff_nrm_dir := Vector3(-out_xy.x * 0.22, -out_xy.y * 0.26 * crown_w, 0.96).normalized().lerp(nrm_cave, smoothstep(0.25, 0.70, v)).normalized()
			p_pos += cliff_nrm_dir * (karst_disp + buttress_disp + proud_h - feather_tuck)

			# Concave grotto shrine alcoves carved behind WeirdTorch_L & WeirdTorch_R (x = +-6.05, y = 0..4.8)
			var dx_torch := absf(p_pos.x) - 6.05
			var dy_torch := (p_pos.y - 2.35) / 2.85
			var torch_niche := exp(-(dx_torch * dx_torch) / 2.8 - dy_torch * dy_torch) * smoothstep(0.04, 0.14, v) * (1.0 - smoothstep(0.34, 0.54, v))
			p_pos.z -= torch_niche * 0.24

			# Anchor floor-skirt roots cleanly under the dished sanctuary floor
			if py_aim < -0.10 or floor_skirt_w > 0.12:
				var wp_f := door_xf * Vector3(p_pos.x, 1.5, maxf(p_pos.z, 0.2))
				var floor_w_y := sample_sdf_floor_below(wp_f.x, wp_f.z, wp_f.y + 2.5, GEOFENCE_OVERWORLD_H).w
				var floor_local_y := floor_w_y - door_xf.origin.y
				if py_aim < -0.10:
					p_pos.y = minf(p_pos.y, floor_local_y - 0.28 - 0.48 * v)

			var wp_v := door_xf * p_pos
			row_p.append(p_pos)
			row_uv.append(Vector2(wp_v.x * 0.12, wp_v.z * 0.12))

			# Vertex COLOR = (AO, SkyVis=0, Wetness, Curvature filled via 1-ring Laplacian below)
			var outer_match := smoothstep(0.46, 0.76, v)
			# Carve realistic karst crevice & overhang AO around the sculpted portal socket so rock contrast matches CaveShell!
			var l_pos := CaveLayout.to_local(wp_v)
			var w_cliff_n := (door_xf.basis * cliff_nrm_dir).normalized()
			var l_cliff_n := Vector3(
				w_cliff_n.x * CaveLayout.RIGHT_XZ.x + w_cliff_n.z * CaveLayout.RIGHT_XZ.y,
				w_cliff_n.y,
				w_cliff_n.x * CaveLayout.FWD_XZ.x + w_cliff_n.z * CaveLayout.FWD_XZ.y
			).normalized()
			var ao_pos_occ := 0.0
			var ao_pos_w := 0.0
			var ao_steps_c := [0.65, 1.45, 2.80, 4.80]
			for ai in 4:
				var ds_c: float = ao_steps_c[ai]
				var sp_c := l_pos + l_cliff_n * ds_c
				var clr_c := maxf(-sdf.eval_cave_void_smooth(sp_c.x, sp_c.y, sp_c.z), 0.0)
				var wt_c := 1.0 / float(ai + 1)
				ao_pos_occ += clampf(clr_c / ds_c, 0.0, 1.0) * wt_c
				ao_pos_w += wt_c
			var ao_cliff := clampf(ao_pos_occ / maxf(ao_pos_w, 0.01), 0.56, 0.94)
			var socket_crevice_ao := lerpf(0.74, 0.92, smoothstep(0.0, 0.30, v))
			var karst_pocket_ao := clampf(0.84 + karst_disp * 0.28 + strata_3d * 0.32, 0.62, 1.04)
			var collar_ao := clampf(ao_cliff * socket_crevice_ao * karst_pocket_ao * (1.0 - torch_niche * 0.14), 0.44, 0.90)
			var ao_val := lerpf(collar_ao, ao_cave, outer_match)
			var wet_val := clampf(0.02 * (1.0 - clampf(p_pos.y / 4.5, 0.0, 1.0)) * (1.0 - outer_match), 0.0, 0.03)
			row_c.append(Color(ao_val, 0.0, wet_val, curv_cave))

			row_o.append(cliff_nrm_dir)
			row_sn.append(nrm_cave)
			row_sc.append(curv_cave)
			row_bw.append(outer_match)

		wall_pts.append(row_p)
		wall_uvs.append(row_uv)
		wall_cols.append(row_c)
		wall_outs.append(row_o)
		sdf_nrms_grid.append(row_sn)
		sdf_curv_grid.append(row_sc)
		blend_grid.append(row_bw)

	# Compute 3D karst facet normals & 1-ring Laplacian curvature on the concave cliff wall,
	# keeping normals facing inward toward VaultDoorOmni and reaching 100% CaveShell sdf_n & curv by v = 0.76!
	var explicit_nrms: Array = []
	var nu_w := wall_pts.size()
	var nv_w := (wall_pts[0] as Array).size()
	for iu in nu_w:
		var nrow_e: Array[Vector3] = []
		var iu_prev := maxi(iu - 1, 0)
		var iu_next := mini(iu + 1, nu_w - 1)
		var r_cur: Array = wall_pts[iu]
		var r_prev: Array = wall_pts[iu_prev]
		var r_next: Array = wall_pts[iu_next]
		var c_row: Array = wall_cols[iu]
		var o_row: Array = wall_outs[iu]
		var sn_row: Array = sdf_nrms_grid[iu]
		var sc_row: Array = sdf_curv_grid[iu]
		var bw_row: Array = blend_grid[iu]
		for iv in nv_w:
			var iv_prev := maxi(iv - 1, 0)
			var iv_next := mini(iv + 1, nv_w - 1)
			var p_cur: Vector3 = r_cur[iv]
			var p_u0: Vector3 = r_prev[iv]
			var p_u1: Vector3 = r_next[iv]
			var p_v0: Vector3 = r_cur[iv_prev]
			var p_v1: Vector3 = r_cur[iv_next]
			var tu := p_u1 - p_u0
			var tv := p_v1 - p_v0
			var hint_v: Vector3 = o_row[iv]
			var geo_n := tv.cross(tu)
			if geo_n.length_squared() < 1e-9:
				geo_n = hint_v
			else:
				geo_n = geo_n.normalized()
				if geo_n.dot(hint_v) < 0.0:
					geo_n = -geo_n
			# Preserve crisp 3D karst relief normals on the cliff face (only guard inner clasp_lip at v < 0.14 from grazing self-shadow)
			var lip_guard := 0.34 * (1.0 - smoothstep(0.02, 0.16, float(iv) / float(maxi(nv_w - 1, 1))))
			var cliff_n := (hint_v * lip_guard + geo_n * (1.0 - lip_guard)).normalized()
			var sdf_n: Vector3 = sn_row[iv]
			var bw: float = float(bw_row[iv])
			var final_n := cliff_n.lerp(sdf_n, bw).normalized()
			nrow_e.append(final_n)

			# 1-ring Laplacian curvature normalized to bake_cave.gd's 0.55m voxel scale so ridge_shade matches CaveShell
			var span_u := maxf(0.5 * tu.length(), 0.20)
			var span_v := maxf(0.5 * tv.length(), 0.20)
			var lap_u := (p_cur - 0.5 * (p_u0 + p_u1)).dot(final_n) * clampf(pow(0.55 / span_u, 1.5), 0.5, 2.2)
			var lap_v := (p_cur - 0.5 * (p_v0 + p_v1)).dot(final_n) * clampf(pow(0.55 / span_v, 1.5), 0.5, 2.2)
			var curv_mesh := clampf(0.5 + 0.5 * (lap_u + lap_v) * 0.65, 0.20, 0.82)
			var curv_sdf: float = float(sc_row[iv])
			var col_prev: Color = c_row[iv]
			c_row[iv] = Color(col_prev.r, col_prev.g, col_prev.b, lerpf(curv_mesh, curv_sdf, bw))
		explicit_nrms.append(nrow_e)

	_emit_smooth_grid(st_wall, wall_pts, wall_uvs, wall_cols, wall_outs, false, false, false, 0.0, [], explicit_nrms)
	if debug_grid != null:
		debug_grid.append(wall_pts)

	st_wall.generate_tangents()
	var built_mesh := st_wall.commit()
	if built_mesh != null:
		built_mesh.set_meta("door_origin", door_xf.origin)
		if use_cache:
			_cached_door_wall_mesh = built_mesh
			_save_cached_res(built_mesh, DOOR_WALL_MESH_PATH)
	return built_mesh


static func _build_periodic_lattice(res: int, seed_val: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var arr := PackedFloat32Array()
	arr.resize(res * res)
	for i in res * res:
		arr[i] = rng.randf()
	return arr


static func _sample_periodic_noise(u: float, v: float, grid: PackedFloat32Array, res: int) -> float:
	var gx := fposmod(u, 1.0) * float(res)
	var gy := fposmod(v, 1.0) * float(res)
	var x0 := int(floorf(gx)) % res
	var y0 := int(floorf(gy)) % res
	var x1 := (x0 + 1) % res
	var y1 := (y0 + 1) % res
	var fx := gx - floorf(gx)
	var fy := gy - floorf(gy)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := grid[y0 * res + x0]
	var b := grid[y0 * res + x1]
	var c := grid[y1 * res + x0]
	var d := grid[y1 * res + x1]
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


static func _sample_periodic_fbm(
		u: float,
		v: float,
		g0: PackedFloat32Array, r0: int,
		g1: PackedFloat32Array, r1: int,
		g2: PackedFloat32Array, r2: int
) -> float:
	var n0 := _sample_periodic_noise(u, v, g0, r0)
	var n1 := _sample_periodic_noise(u * 2.0, v * 2.0, g1, r1)
	var n2 := _sample_periodic_noise(u * 4.0, v * 4.0, g2, r2)
	return clampf(n0 * 0.54 + n1 * 0.30 + n2 * 0.16, 0.0, 1.0)


static func _get_fire_noise_tex() -> ImageTexture:
	if _fire_noise_tex != null:
		return _fire_noise_tex
	if ResourceLoader.exists(FIRE_NOISE_TEX_PATH):
		var loaded := load(FIRE_NOISE_TEX_PATH) as ImageTexture
		if loaded != null:
			_fire_noise_tex = loaded
			return _fire_noise_tex
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var g0 := _build_periodic_lattice(8, 7103)
	var g1 := _build_periodic_lattice(16, 7211)
	var g2 := _build_periodic_lattice(32, 7331)
	var g3 := _build_periodic_lattice(32, 7459)
	for y in size:
		var v := float(y) / float(size)
		for x in size:
			var u := float(x) / float(size)
			var r := _sample_periodic_fbm(u, v, g0, 8, g1, 16, g2, 32)
			var g := _sample_periodic_fbm(u + 0.37, v + 0.19, g1, 16, g2, 32, g3, 32)
			var b := _sample_periodic_fbm(u * 2.0 + 0.11, v * 2.0 + 0.63, g2, 32, g3, 32, g0, 8)
			var a := _sample_periodic_noise(u * 3.0, v * 3.0, g3, 32)
			img.set_pixel(x, y, Color(r, g, b, a))
	img.generate_mipmaps()
	_fire_noise_tex = ImageTexture.create_from_image(img)
	_save_cached_res(_fire_noise_tex, FIRE_NOISE_TEX_PATH)
	return _fire_noise_tex


static func _get_fire_flipbook_tex() -> ImageTexture:
	if _fire_flipbook_tex != null:
		return _fire_flipbook_tex
	if ResourceLoader.exists(FIRE_FLIPBOOK_TEX_PATH):
		var loaded := load(FIRE_FLIPBOOK_TEX_PATH) as ImageTexture
		if loaded != null:
			_fire_flipbook_tex = loaded
			return _fire_flipbook_tex
	var tile_sz := 64
	var grid_n := 4
	var total_sz := tile_sz * grid_n # 256x256
	var img := Image.create(total_sz, total_sz, true, Image.FORMAT_RGBA8)
	var g0 := _build_periodic_lattice(8, 9101)
	var g1 := _build_periodic_lattice(16, 9227)
	var g2 := _build_periodic_lattice(32, 9349)

	for fi in 16:
		var phase := float(fi) / 16.0
		var col_i := fi % grid_n
		var row_i := int(floorf(float(fi) / float(grid_n)))
		var ox := col_i * tile_sz
		var oy := row_i * tile_sz
		for ly in tile_sz:
			var v := (float(ly) + 0.5) / float(tile_sz) # 0 = top tip, 1 = bottom base
			var up_t := 1.0 - v
			var edge_v := smoothstep(0.05, 0.22, v) * (1.0 - smoothstep(0.80, 0.95, v))
			for lx in tile_sz:
				var u := (float(lx) + 0.5) / float(tile_sz)
				var x_rel := (u - 0.5) * 2.0
				var edge_u := smoothstep(0.06, 0.20, u) * (1.0 - smoothstep(0.80, 0.94, u))

				var n_coarse := _sample_periodic_fbm(u * 1.0 + 0.15 * sin(phase * TAU), v * 1.0 + phase, g0, 8, g1, 16, g2, 32)
				var n_fine := _sample_periodic_fbm(u * 2.0 - 0.10 * cos(phase * TAU), v * 2.0 + phase * 2.0, g1, 16, g2, 32, g0, 8)

				var width_prof := lerpf(0.68, 0.16, pow(up_t, 0.72)) * (0.86 + 0.14 * sin(minf(up_t * 3.1, PI * 0.5)))
				var warp_x := (n_coarse - 0.5) * (0.28 + 0.34 * up_t) + (n_fine - 0.5) * 0.16
				var dist_x := absf(x_rel + warp_x) / maxf(width_prof, 0.08)

				var rad_mask := 1.0 - smoothstep(0.18, 0.96, dist_x)
				var top_erode := 1.0 - smoothstep(0.32, 0.96, up_t + (1.0 - n_fine) * 0.36)
				var body := rad_mask * edge_v * edge_u * top_erode
				var heat := clampf(body * (0.58 + 0.82 * n_coarse), 0.0, 1.0)
				var alpha := clampf(smoothstep(0.06, 0.65, heat) * edge_v * edge_u, 0.0, 1.0)
				img.set_pixel(ox + lx, oy + ly, Color(heat, n_fine, body, alpha))

	img.generate_mipmaps()
	_fire_flipbook_tex = ImageTexture.create_from_image(img)
	_save_cached_res(_fire_flipbook_tex, FIRE_FLIPBOOK_TEX_PATH)
	return _fire_flipbook_tex


static func _build_crossed_flame_cards_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var card_angles := [0.0, PI / 3.0, 2.0 * PI / 3.0]
	var width := 1.12
	var height := 1.78
	var y_base := -0.04
	var nx := 6
	var ny := 8
	var cup_depth := 0.085

	for ca: float in card_angles:
		var dir_x := Vector3(cos(ca), 0.0, sin(ca))
		var dir_n := Vector3(-sin(ca), 0.0, cos(ca))
		var grid: Array = []
		var nrms: Array = []
		var uvs: Array = []
		for iy in range(ny + 1):
			var vf := float(iy) / float(ny)
			var y := y_base + vf * height
			var row_p: Array[Vector3] = []
			var row_n: Array[Vector3] = []
			var row_uv: Array[Vector2] = []
			for ix in range(nx + 1):
				var uf := float(ix) / float(nx)
				var x_off := (uf - 0.5) * width
				var cup := sin(uf * PI) * cup_depth * (1.0 - 0.35 * vf)
				var slope := cos(uf * PI) * PI * cup_depth / maxf(width, 0.01)
				var p := dir_x * x_off + dir_n * cup + Vector3(0.0, y, 0.0)
				var nrm := (dir_n - dir_x * slope).normalized()
				row_p.append(p)
				row_n.append(nrm)
				row_uv.append(Vector2(uf, vf))
			grid.append(row_p)
			nrms.append(row_n)
			uvs.append(row_uv)

		for iy in ny:
			var r0: Array = grid[iy]
			var r1: Array = grid[iy + 1]
			var n0: Array = nrms[iy]
			var n1: Array = nrms[iy + 1]
			var u0: Array = uvs[iy]
			var u1: Array = uvs[iy + 1]
			for ix in nx:
				st.set_normal(n0[ix]); st.set_uv(u0[ix]); st.add_vertex(r0[ix])
				st.set_normal(n0[ix + 1]); st.set_uv(u0[ix + 1]); st.add_vertex(r0[ix + 1])
				st.set_normal(n1[ix + 1]); st.set_uv(u1[ix + 1]); st.add_vertex(r1[ix + 1])

				st.set_normal(n0[ix]); st.set_uv(u0[ix]); st.add_vertex(r0[ix])
				st.set_normal(n1[ix + 1]); st.set_uv(u1[ix + 1]); st.add_vertex(r1[ix + 1])
				st.set_normal(n1[ix]); st.set_uv(u1[ix]); st.add_vertex(r1[ix])

	return st.commit()


static func _build_brazier_coal_bed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 8
	var segs := 18
	var max_r := 0.62
	var pts: Array = []
	var uvs: Array = []
	var cols: Array = []
	var outs: Array = []

	for ri in range(rings + 1):
		var rf := maxf(float(ri) / float(rings), 0.004)
		var rp: Array[Vector3] = []
		var ruv: Array[Vector2] = []
		var rc: Array[Color] = []
		var ro: Array[Vector3] = []
		for si in segs:
			var uf := float(si) / float(segs)
			var ang := uf * TAU
			var rad := max_r * rf
			var lump := 0.024 * sin(ang * 5.0 + rf * 9.0) + 0.016 * cos(ang * 9.0 - rf * 13.0)
			var dome_h := (1.0 - rf * rf) * 0.11 + lump * sin(rf * PI)
			var px := cos(ang) * rad
			var pz := sin(ang) * rad
			rp.append(Vector3(px, dome_h, pz))
			ruv.append(Vector2(0.5 + 0.5 * cos(ang) * rf, 0.5 + 0.5 * sin(ang) * rf))
			var ao_v := lerpf(0.95, 0.55, pow(rf, 1.8))
			rc.append(Color(ao_v, 1.0, 1.0, 1.0))
			ro.append(Vector3(px * 0.55, 1.0, pz * 0.55).normalized())
		pts.append(rp)
		uvs.append(ruv)
		cols.append(rc)
		outs.append(ro)

	_emit_smooth_grid(st, pts, uvs, cols, outs, false, true, false, 0.0)
	return st.commit()


func _attach_brazier_fire_vfx(
		torch_pivot: Node3D,
		ti: int,
		coal_mesh: ArrayMesh,
		cards_mesh: ArrayMesh,
		coal_shader: Shader,
		card_shader: Shader,
		particle_shader: Shader,
		smoke_shader: Shader,
		ember_shader: Shader,
		haze_shader: Shader,
		noise_tex: ImageTexture,
		flipbook_tex: ImageTexture,
		coal_tex: ImageTexture
) -> void:
	var side_seed := float(ti) * 1.37
	var vfx_bounds := AABB(Vector3(-1.8, -0.5, -1.8), Vector3(3.6, 5.5, 3.6))

	# Brazier glowing coal & ember bed inside the bowl
	var coal_mat := ShaderMaterial.new()
	coal_mat.shader = coal_shader
	coal_mat.set_shader_parameter("veil_tex", coal_tex)
	coal_mat.set_shader_parameter("torch_side_seed", side_seed)
	coal_mat.set_shader_parameter("awaken_amount", _door_awaken_val)
	_torch_flame_mats.append(coal_mat)

	var coal_mi := MeshInstance3D.new()
	coal_mi.name = "BrazierCoalBed"
	coal_mi.mesh = coal_mesh
	coal_mi.material_override = coal_mat
	coal_mi.position = Vector3(0.0, -0.02, 0.0)
	coal_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torch_pivot.add_child(coal_mi)

	# Supporting Effect: Subtle refractive heat haze envelope right above the flames (renders first)
	var haze_mat := ShaderMaterial.new()
	haze_mat.shader = haze_shader
	haze_mat.render_priority = -1
	haze_mat.set_shader_parameter("noise_tex", noise_tex)
	haze_mat.set_shader_parameter("torch_seed", side_seed)
	haze_mat.set_shader_parameter("awaken_amount", _door_awaken_val)
	_torch_haze_mats.append(haze_mat)

	var haze_quad := QuadMesh.new()
	haze_quad.size = Vector2(1.38, 1.92)
	var haze_mi := MeshInstance3D.new()
	haze_mi.name = "HeatHazeEnvelope"
	haze_mi.mesh = haze_quad
	haze_mi.material_override = haze_mat
	haze_mi.position = Vector3(0.0, 1.18, 0.0)
	haze_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze_mi.visibility_range_end = 36.0
	haze_mi.visibility_range_end_margin = 4.0
	haze_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	torch_pivot.add_child(haze_mi)
	_door_haze_meshes.append(haze_mi)

	# Supporting Effect: Rising soot/smoke billboard particles
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = smoke_shader
	smoke_mat.render_priority = 0
	smoke_mat.set_shader_parameter("noise_tex", noise_tex)

	var smoke_quad := QuadMesh.new()
	smoke_quad.size = Vector2(1.22, 1.22)

	var smoke_curve := Curve.new()
	smoke_curve.add_point(Vector2(0.0, 0.42))
	smoke_curve.add_point(Vector2(0.45, 0.88))
	smoke_curve.add_point(Vector2(1.0, 1.42))
	var smoke_curve_tex := CurveTexture.new()
	smoke_curve_tex.curve = smoke_curve

	var smoke_pm := ParticleProcessMaterial.new()
	smoke_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_pm.emission_sphere_radius = 0.24
	smoke_pm.direction = Vector3(0.0, 1.0, 0.0)
	smoke_pm.spread = 12.0
	smoke_pm.initial_velocity_min = 0.72
	smoke_pm.initial_velocity_max = 1.08
	smoke_pm.gravity = Vector3(0.0, 0.14, 0.0)
	smoke_pm.damping_min = 0.15
	smoke_pm.damping_max = 0.30
	smoke_pm.angle_min = -180.0
	smoke_pm.angle_max = 180.0
	smoke_pm.angular_velocity_min = -22.0
	smoke_pm.angular_velocity_max = 22.0
	smoke_pm.scale_min = 0.78
	smoke_pm.scale_max = 1.18
	smoke_pm.scale_curve = smoke_curve_tex
	smoke_pm.turbulence_enabled = true
	smoke_pm.turbulence_noise_strength = 0.28
	smoke_pm.turbulence_noise_scale = 1.6
	smoke_pm.anim_offset_min = 0.0
	smoke_pm.anim_offset_max = 1.0

	var smoke_gp := GPUParticles3D.new()
	smoke_gp.name = "SmokeParticles"
	smoke_gp.amount = 16
	smoke_gp.lifetime = 2.85
	smoke_gp.preprocess = 2.85
	smoke_gp.local_coords = true
	smoke_gp.custom_aabb = vfx_bounds
	smoke_gp.process_material = smoke_pm
	smoke_gp.draw_pass_1 = smoke_quad
	smoke_gp.material_override = smoke_mat
	smoke_gp.position = Vector3(0.0, 0.92, 0.0)
	smoke_gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torch_pivot.add_child(smoke_gp)
	_door_particles.append(smoke_gp)

	# Layer 2: Shader-driven crossed flame cards at the fire core
	var card_mat := ShaderMaterial.new()
	card_mat.shader = card_shader
	card_mat.render_priority = 1
	card_mat.set_shader_parameter("noise_tex", noise_tex)
	card_mat.set_shader_parameter("torch_seed", side_seed)
	card_mat.set_shader_parameter("awaken_amount", _door_awaken_val)
	_torch_card_mats.append(card_mat)

	var cards_mi := MeshInstance3D.new()
	cards_mi.name = "FlameCoreCards"
	cards_mi.mesh = cards_mesh
	cards_mi.material_override = card_mat
	cards_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torch_pivot.add_child(cards_mi)

	# Layer 1: Animated 4x4 (16-frame) flipbook billboard flame particles
	var fp_mat := ShaderMaterial.new()
	fp_mat.shader = particle_shader
	fp_mat.render_priority = 2
	fp_mat.set_shader_parameter("flipbook_tex", flipbook_tex)

	var fp_quad := QuadMesh.new()
	fp_quad.size = Vector2(0.92, 1.15)

	var fp_curve := Curve.new()
	fp_curve.add_point(Vector2(0.0, 0.72))
	fp_curve.add_point(Vector2(0.28, 1.04))
	fp_curve.add_point(Vector2(1.0, 0.28))
	var fp_curve_tex := CurveTexture.new()
	fp_curve_tex.curve = fp_curve

	var fp_pm := ParticleProcessMaterial.new()
	fp_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fp_pm.emission_sphere_radius = 0.26
	fp_pm.direction = Vector3(0.0, 1.0, 0.0)
	fp_pm.spread = 14.0
	fp_pm.initial_velocity_min = 0.92
	fp_pm.initial_velocity_max = 1.55
	fp_pm.gravity = Vector3(0.0, 0.72, 0.0)
	fp_pm.damping_min = 0.35
	fp_pm.damping_max = 0.70
	fp_pm.angle_min = -18.0
	fp_pm.angle_max = 18.0
	fp_pm.angular_velocity_min = -42.0
	fp_pm.angular_velocity_max = 42.0
	fp_pm.scale_min = 0.68
	fp_pm.scale_max = 1.08
	fp_pm.scale_curve = fp_curve_tex
	fp_pm.turbulence_enabled = true
	fp_pm.turbulence_noise_strength = 0.24
	fp_pm.turbulence_noise_scale = 2.4
	fp_pm.anim_speed_min = 0.85
	fp_pm.anim_speed_max = 1.25
	fp_pm.anim_offset_min = 0.0
	fp_pm.anim_offset_max = 1.0

	var fp_gp := GPUParticles3D.new()
	fp_gp.name = "FlameParticles"
	fp_gp.amount = 22
	fp_gp.lifetime = 0.95
	fp_gp.preprocess = 1.5
	fp_gp.local_coords = true
	fp_gp.custom_aabb = vfx_bounds
	fp_gp.process_material = fp_pm
	fp_gp.draw_pass_1 = fp_quad
	fp_gp.material_override = fp_mat
	fp_gp.position = Vector3(0.0, 0.08, 0.0)
	fp_gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torch_pivot.add_child(fp_gp)
	_door_particles.append(fp_gp)

	# Supporting Effect: Rising spiraling ember/spark particles
	var ember_mat := ShaderMaterial.new()
	ember_mat.shader = ember_shader
	ember_mat.render_priority = 3

	var ember_quad := QuadMesh.new()
	ember_quad.size = Vector2(0.085, 0.11)

	var ember_curve := Curve.new()
	ember_curve.add_point(Vector2(0.0, 0.65))
	ember_curve.add_point(Vector2(0.30, 1.0))
	ember_curve.add_point(Vector2(1.0, 0.15))
	var ember_curve_tex := CurveTexture.new()
	ember_curve_tex.curve = ember_curve

	var ember_pm := ParticleProcessMaterial.new()
	ember_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	ember_pm.emission_ring_axis = Vector3.UP
	ember_pm.emission_ring_radius = 0.42
	ember_pm.emission_ring_inner_radius = 0.08
	ember_pm.emission_ring_height = 0.08
	ember_pm.direction = Vector3(0.0, 1.0, 0.0)
	ember_pm.spread = 20.0
	ember_pm.initial_velocity_min = 1.05
	ember_pm.initial_velocity_max = 2.05
	ember_pm.gravity = Vector3(0.0, 0.35, 0.0)
	ember_pm.damping_min = 0.25
	ember_pm.damping_max = 0.55
	ember_pm.scale_min = 0.70
	ember_pm.scale_max = 1.30
	ember_pm.scale_curve = ember_curve_tex
	ember_pm.turbulence_enabled = true
	ember_pm.turbulence_noise_strength = 0.85
	ember_pm.turbulence_noise_scale = 1.8
	ember_pm.turbulence_noise_speed_random = 0.5
	ember_pm.anim_offset_min = 0.0
	ember_pm.anim_offset_max = 1.0

	var ember_gp := GPUParticles3D.new()
	ember_gp.name = "EmberParticles"
	ember_gp.amount = 28
	ember_gp.lifetime = 1.75
	ember_gp.preprocess = 2.0
	ember_gp.local_coords = true
	ember_gp.custom_aabb = vfx_bounds
	ember_gp.process_material = ember_pm
	ember_gp.draw_pass_1 = ember_quad
	ember_gp.material_override = ember_mat
	ember_gp.position = Vector3(0.0, 0.04, 0.0)
	ember_gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torch_pivot.add_child(ember_gp)
	_door_particles.append(ember_gp)


static func _round_arch_y_at_x(x_abs: float, half_span: float = 3.55, spring_y: float = 6.20) -> float:
	var x_c := clampf(x_abs, 0.0, half_span)
	return spring_y + sqrt(maxf(half_span * half_span - x_c * x_c, 0.0))


static func _round_arch_frame(u: float, half_span: float = 3.55, spring_y: float = 6.20, y_root: float = -0.80) -> Dictionary:
	# Inverted-U archway: straight vertical jambs below spring_y, semi-circular arch crown above spring_y
	var jamb_h := spring_y - y_root
	var arch_len := PI * half_span
	var total_len := 2.0 * jamb_h + arch_len
	var s := clampf(u, 0.0, 1.0) * total_len
	if s <= jamb_h:
		return {
			"pos": Vector2(-half_span, y_root + s),
			"out": Vector2(-1.0, 0.0),
		}
	elif s <= jamb_h + arch_len:
		var ang := PI - ((s - jamb_h) / arch_len) * PI
		return {
			"pos": Vector2(cos(ang) * half_span, spring_y + sin(ang) * half_span),
			"out": Vector2(cos(ang), sin(ang)),
		}
	else:
		var ds := s - (jamb_h + arch_len)
		return {
			"pos": Vector2(half_span, spring_y - ds),
			"out": Vector2(1.0, 0.0),
		}


func _add_sculpted_stone_to_st(
	st: SurfaceTool,
	xf: Transform3D,
	hx_bot: float,
	hx_top: float,
	hy: float,
	hz: float,
	roundness: float,
	mat_id: float,
	phase: float,
	ao_front: float,
	ao_back: float,
	accent: float = 0.0,
	chisel_amp: float = 0.022
) -> void:
	# Closed, pillowed superellipsoid stone block with organic hand-chiseled undulation and smooth normals
	var perim_segs := 16
	var prof_y := [-1.0, -0.95, -0.74, 0.0, 0.74, 0.95, 1.0]
	var prof_r := [0.18, 0.78, 0.97, 1.00, 0.97, 0.78, 0.18]
	var p_exp := clampf(roundness, 0.28, 0.70)
	var ref_c := xf * Vector3.ZERO

	var grid_pts: Array = []
	var grid_uvs: Array = []
	var grid_cols: Array = []
	var grid_outs: Array = []
	var grid_phs: Array = []

	for iy in prof_y.size():
		var yn := float(prof_y[iy])
		var rs := float(prof_r[iy])
		var yf := (yn + 1.0) * 0.5
		var hx := lerpf(hx_bot, hx_top, yf)
		var row_p: Array[Vector3] = []
		var row_uv: Array[Vector2] = []
		var row_c: Array[Color] = []
		var row_o: Array[Vector3] = []
		var row_ph: Array[float] = []
		for iu in perim_segs:
			var uf := float(iu) / float(perim_segs)
			var ang := uf * TAU
			var ca := cos(ang)
			var sa := sin(ang)
			var sx := signf(ca) * pow(absf(ca), p_exp)
			var sz := signf(sa) * pow(absf(sa), p_exp)
			var undul := (sin(uf * TAU * 3.0 + phase * 11.0 + yn * 2.4) * 0.6 + cos(uf * TAU * 2.0 - phase * 7.0) * 0.4) * chisel_amp * rs
			var lx := sx * hx * rs + ca * undul
			var ly := yn * hy + sin(uf * TAU * 2.0 + phase * 5.0) * chisel_amp * 0.35 * (1.0 - absf(yn))
			var lz := sz * hz * rs + sa * undul
			var wp := xf * Vector3(lx, ly, lz)
			var ln := Vector3(ca / maxf(hx * rs, 0.05), yn * 0.55 / maxf(hy, 0.05), sa / maxf(hz * rs, 0.05)).normalized()
			var wn := (xf.basis * ln).normalized()
			var front_w := clampf(0.5 + 0.5 * sa, 0.0, 1.0)
			var mortar_ao := lerpf(0.84, 1.0, 1.0 - pow(absf(yn), 2.2))
			var ao_v := lerpf(ao_back, ao_front, front_w) * mortar_ao
			row_p.append(wp)
			row_uv.append(Vector2(uf, yf))
			row_c.append(Color(ao_v, 0.35, accent, 1.0))
			row_o.append(wn)
			row_ph.append(phase)
		grid_pts.append(row_p)
		grid_uvs.append(row_uv)
		grid_cols.append(row_c)
		grid_outs.append(row_o)
		grid_phs.append(row_ph)

	_emit_smooth_grid(st, grid_pts, grid_uvs, grid_cols, grid_outs, false, true, true, mat_id, grid_phs)

	# Cap bottom and top poles cleanly so every sculpted stone is watertight
	var bot_center := xf * Vector3(0.0, -hy, 0.0)
	var top_center := xf * Vector3(0.0, hy, 0.0)
	var bot_row: Array = grid_pts[0]
	var top_row: Array = grid_pts[prof_y.size() - 1]
	var cap_col_b := Color(ao_back * 0.84, 0.25, accent, 1.0)
	var cap_col_t := Color(ao_front * 0.86, 0.25, accent, 1.0)
	for iu in perim_segs:
		var iu_n := (iu + 1) % perim_segs
		_add_tri_outward(st, bot_center, bot_row[iu], bot_row[iu_n], Vector2(0.5, 0.5), Vector2(0.5, 0.1), Vector2(0.7, 0.1), ref_c, mat_id, cap_col_b, true, phase)
		_add_tri_outward(st, top_center, top_row[iu_n], top_row[iu], Vector2(0.5, 0.5), Vector2(0.5, 0.9), Vector2(0.7, 0.9), ref_c, mat_id, cap_col_t, true, phase)


func _add_domed_rivet_to_st(
	st: SurfaceTool,
	center: Vector3,
	out_dir: Vector3,
	radius: float,
	height: float,
	mat_id: float,
	phase: float,
	ao: float = 0.94
) -> void:
	var n_dir := out_dir.normalized()
	var up_ref := Vector3.UP if absf(n_dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var t1 := up_ref.cross(n_dir).normalized()
	var t2 := n_dir.cross(t1).normalized()
	var segs := 10
	var rings := 3
	var grid_pts: Array = []
	var grid_uvs: Array = []
	var grid_cols: Array = []
	var grid_outs: Array = []
	var grid_phs: Array = []
	for ri in range(rings + 1):
		var rf := float(ri) / float(rings)
		var r_cur := maxf(radius * cos(rf * PI * 0.5), 0.004)
		var h_cur := height * sin(rf * PI * 0.5)
		var row_p: Array[Vector3] = []
		var row_uv: Array[Vector2] = []
		var row_c: Array[Color] = []
		var row_o: Array[Vector3] = []
		var row_ph: Array[float] = []
		for si in segs:
			var sf := float(si) / float(segs)
			var ang := sf * TAU
			var rad_v := t1 * cos(ang) + t2 * sin(ang)
			row_p.append(center + rad_v * r_cur + n_dir * h_cur)
			row_uv.append(Vector2(0.5 + 0.4 * cos(ang) * (1.0 - rf), 0.5 + 0.4 * sin(ang) * (1.0 - rf)))
			row_c.append(Color(lerpf(ao * 0.78, ao, rf), 0.35, 0.0, 1.0))
			row_o.append((rad_v * cos(rf * PI * 0.5) + n_dir * sin(rf * PI * 0.5)).normalized())
			row_ph.append(phase)
		grid_pts.append(row_p)
		grid_uvs.append(row_uv)
		grid_cols.append(row_c)
		grid_outs.append(row_o)
		grid_phs.append(row_ph)
	_emit_smooth_grid(st, grid_pts, grid_uvs, grid_cols, grid_outs, false, true, true, mat_id, grid_phs)


func _sculpt_horizontal_ring_to_st(
	st: SurfaceTool,
	center: Vector3,
	r_in: float,
	r_out: float,
	height: float,
	segs: int,
	prof_segs: int,
	mat_id: float,
	phase: float = 0.0,
	ao: float = 0.92,
	bevel: float = 0.45,
	accent: float = 0.0
) -> void:
	# Revolved horizontal torus ring around the Y axis (lies flat in XZ plane!)
	var r_mid := (r_in + r_out) * 0.5
	var r_tube := maxf((r_out - r_in) * 0.5, 0.008)
	var y_tube := maxf(height * 0.5, 0.008)
	var v_cnt := maxi(prof_segs, 6)
	var grid_pts: Array = []
	var grid_uvs: Array = []
	var grid_cols: Array = []
	var grid_outs: Array = []
	var grid_phs: Array = []
	for iu in segs:
		var uf := float(iu) / float(segs)
		var ang := uf * TAU
		var rad_xz := Vector3(cos(ang), 0.0, sin(ang))
		var ring_c := center + rad_xz * r_mid
		var row_p: Array[Vector3] = []
		var row_uv: Array[Vector2] = []
		var row_c: Array[Color] = []
		var row_o: Array[Vector3] = []
		var row_ph: Array[float] = []
		for iv in v_cnt:
			var vf := float(iv) / float(v_cnt)
			var pa := vf * TAU
			var cp := cos(pa)
			var sp := sin(pa)
			var p := ring_c + rad_xz * (cp * r_tube) + Vector3(0.0, sp * y_tube, 0.0)
			var out_n := (rad_xz * (cp / r_tube) + Vector3(0.0, sp / y_tube, 0.0)).normalized()
			row_p.append(p)
			row_uv.append(Vector2(vf, uf * 4.0))
			row_c.append(Color(ao * lerpf(0.84, 1.0, clampf(0.5 + 0.5 * cp, 0.0, 1.0)), bevel, accent, 1.0))
			row_o.append(out_n)
			row_ph.append(phase + uf * 0.25)
		grid_pts.append(row_p)
		grid_uvs.append(row_uv)
		grid_cols.append(row_c)
		grid_outs.append(row_o)
		grid_phs.append(row_ph)
	_emit_smooth_grid(st, grid_pts, grid_uvs, grid_cols, grid_outs, true, true, true, mat_id, grid_phs)


func _add_planked_round_door_leaf_to_st(
	st: SurfaceTool,
	side_f: float,
	half_span: float,
	spring_y: float,
	y_bot: float,
	z_front: float
) -> void:
	# Smooth sculpted monolithic stone-slab door leaf with upper & lower deeply recessed coffered stone panels
	var x_steps := 26
	var y_steps := 28
	var x_in := 0.035
	var x_out := half_span + 0.12

	var grid_pts: Array = []
	var grid_uvs: Array = []
	var grid_cols: Array = []
	var grid_outs: Array = []
	var grid_phs: Array = []

	for iy in range(y_steps + 1):
		var yf := float(iy) / float(y_steps)
		var row_p: Array[Vector3] = []
		var row_uv: Array[Vector2] = []
		var row_c: Array[Color] = []
		var row_o: Array[Vector3] = []
		var row_ph: Array[float] = []
		for ix in range(x_steps + 1):
			var xf := float(ix) / float(x_steps)
			var x_abs := lerpf(x_in, x_out, xf)
			var px := side_f * x_abs
			var y_top := _round_arch_y_at_x(x_abs, half_span, spring_y) + 0.14
			var py := lerpf(y_bot, y_top, yf)

			# Coffered stone slab: thick outer stone stiles + center transom rail + two deeply recessed stone panels
			var bx := smoothstep(0.15, 0.23, xf) * (1.0 - smoothstep(0.77, 0.85, xf))
			var lower_coffer := smoothstep(0.09, 0.15, yf) * (1.0 - smoothstep(0.41, 0.47, yf))
			var upper_coffer := smoothstep(0.53, 0.59, yf) * (1.0 - smoothstep(0.83, 0.89, yf))
			var coffer := bx * maxf(lower_coffer, upper_coffer)
			var panel_recess := coffer * 0.085
			var leaf_bow := cos(clampf(x_abs / half_span, 0.0, 1.0) * PI * 0.45) * 0.10
			var warp_z := (sin(py * 0.75 + px * 0.65) * 0.010 + cos(py * 1.35 - px * 1.05) * 0.007)
			var pz := z_front + 0.02 + leaf_bow - panel_recess + warp_z

			var nrm := Vector3(-side_f * 0.08 * (x_abs / half_span), 0.0, 1.0).normalized()
			var bevel_shadow := coffer * (1.0 - coffer) * 4.0
			var panel_ao := lerpf(0.94, 0.74, coffer * 0.65 + bevel_shadow * 0.35)
			var arch_ao := lerpf(0.86, 0.96, sin(yf * PI))
			var slab_phase := 0.22 + (0.0 if side_f < 0.0 else 0.41)

			row_p.append(Vector3(px, py, pz))
			row_uv.append(Vector2(xf, yf * 2.0))
			row_c.append(Color(panel_ao * arch_ao, 0.38, 0.0, 1.0))
			row_o.append(nrm)
			row_ph.append(slab_phase)
		grid_pts.append(row_p)
		grid_uvs.append(row_uv)
		grid_cols.append(row_c)
		grid_outs.append(row_o)
		grid_phs.append(row_ph)

	# Flip X order for left leaf so grid winding faces strictly +Z outward
	if side_f < 0.0:
		for iy in grid_pts.size():
			(grid_pts[iy] as Array).reverse()
			(grid_uvs[iy] as Array).reverse()
			(grid_cols[iy] as Array).reverse()
			(grid_outs[iy] as Array).reverse()
			(grid_phs[iy] as Array).reverse()

	_emit_smooth_grid(st, grid_pts, grid_uvs, grid_cols, grid_outs, false, false, true, 1.0, grid_phs)


func _build_ancient_big_door() -> void:
	var door_info: Dictionary = CaveLayout.ANCIENT_DOOR
	var door_loc: Vector3 = door_info["pos"]
	var door_w := float(door_info["width"])   # 8.6m
	var door_h := float(door_info["height"])  # 11.0m
	var door_d := float(door_info["depth"])   # 2.4m

	var door_world_pos := CaveLayout.to_world(door_loc)
	# Local facing direction
	var yaw_loc := float(door_info["yaw"])
	var fwd_loc := Vector3(sin(yaw_loc), 0.0, cos(yaw_loc)).normalized()
	var fwd_world := Vector3(
		CaveLayout.FWD_XZ.x * fwd_loc.z + CaveLayout.RIGHT_XZ.x * fwd_loc.x,
		0.0,
		CaveLayout.FWD_XZ.y * fwd_loc.z + CaveLayout.RIGHT_XZ.y * fwd_loc.x
	).normalized()
	var right_world := Vector3.UP.cross(fwd_world).normalized()
	var basis_door := Basis(right_world, Vector3.UP, fwd_world)

	var door_xf := Transform3D(basis_door, door_world_pos)
	var door_root := Node3D.new()
	door_root.name = "AncientBigDoor"
	door_root.transform = door_xf
	add_child(door_root)

	# 1. Custom Multi-Zone Procedural Door & Weird Torch Materials
	var relief_shader := load("res://terrain/cave_door_relief.gdshader") as Shader
	var relief_mat := ShaderMaterial.new()
	relief_mat.shader = relief_shader
	relief_mat.set_shader_parameter("detail_veil_tex", _get_crystal_interior_tex())
	relief_mat.set_shader_parameter("cave_rock_tex", load("res://assets/nature/Rocks_Diffuse.png"))
	_door_relief_mat = relief_mat

	# Living Cavern Cliff & Overhanging Ogival Portal Hood integrated directly into CaveShell rock
	var wall_int_mi := MeshInstance3D.new()
	wall_int_mi.name = "DoorWallIntegrationMesh"
	wall_int_mi.mesh = _build_door_wall_integration_mesh(door_xf, [], true)
	wall_int_mi.material_override = _get_cave_rock_material()
	wall_int_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door_root.add_child(wall_int_mi)

	var torch_shader := load("res://terrain/cave_weird_torch.gdshader") as Shader
	var flame_card_shader := load("res://shaders/torch_flame_card.gdshader") as Shader
	var flame_particle_shader := load("res://shaders/torch_flame_particle.gdshader") as Shader
	var smoke_shader := load("res://shaders/torch_smoke.gdshader") as Shader
	var ember_shader := load("res://shaders/torch_ember.gdshader") as Shader
	var haze_shader := load("res://shaders/torch_heat_haze.gdshader") as Shader

	var torch_x_abs := door_w * 0.5 + 1.75 # 6.05m, centered inside the concave grotto shrine alcoves
	var torch_z := 2.38

	var main_mesh: ArrayMesh = null
	if _cached_door_monolith_mesh != null:
		if _cached_door_monolith_mesh.get_meta("door_origin", Vector3.INF).distance_to(door_world_pos) < 0.01:
			main_mesh = _cached_door_monolith_mesh
	if main_mesh == null and ResourceLoader.exists(DOOR_MONOLITH_MESH_PATH):
		var loaded_mono := load(DOOR_MONOLITH_MESH_PATH) as ArrayMesh
		if loaded_mono != null and loaded_mono.get_meta("door_origin", Vector3.INF).distance_to(door_world_pos) < 0.01:
			_cached_door_monolith_mesh = loaded_mono
			main_mesh = loaded_mono

	if main_mesh == null:
		var st_main := SurfaceTool.new()
		st_main.begin(Mesh.PRIMITIVE_TRIANGLES)

		# 2. Grounded Cut-Stone Threshold Sill & Organic Worn Flagstone Apron (zero glowing circuits or blocky tiles)
		var floor_sdf := CaveSystem.get_sdf()
		var sill_xs := [-2.68, 0.0, 2.68]
		var sill_hx := [1.46, 1.40, 1.46]
		for si in 3:
			var sill_drop := -0.018 if si == 1 else 0.0
			var sill_xf := Transform3D(Basis.IDENTITY, Vector3(float(sill_xs[si]), -0.26 + sill_drop, 0.44))
			_add_sculpted_stone_to_st(st_main, sill_xf, float(sill_hx[si]), float(sill_hx[si]) * 0.98, 0.30, 0.78, 0.38, 0.0, 0.14 + float(si) * 0.23, 0.88, 0.68, 0.08, 0.018)

		# Staggered courses of rounded, weathered flagstone pavers embedded deep into the Sanctum SDF floor
		var apron_courses := [
			# [z_center, half_depth, span_x, count, base_y_lift, outer_rock_blend]
			[1.48, 0.44, 4.65, 5, 0.01, 0.18],
			[2.32, 0.42, 5.05, 6, -0.01, 0.40],
			[3.12, 0.38, 4.15, 5, -0.03, 0.68],
		]
		for ci in apron_courses.size():
			var cspec: Array = apron_courses[ci]
			var zc := float(cspec[0])
			var hz_p := float(cspec[1])
			var span_x := float(cspec[2])
			var p_cnt := int(cspec[3])
			var y_lift := float(cspec[4])
			var rock_bl := float(cspec[5])
			for pi in p_cnt:
				var pf := (float(pi) + 0.5) / float(p_cnt)
				var px := lerpf(-span_x, span_x, pf) + sin(float(ci * 7 + pi) * 1.9) * 0.10
				var pz := zc + cos(float(pi * 5 + ci) * 1.7) * 0.07
				var wp_p := door_world_pos + basis_door * Vector3(px, 0.0, pz)
				var f_sample := CaveSystem.sample_sdf_floor_below(wp_p.x, wp_p.z, door_world_pos.y + 1.4, GEOFENCE_OVERWORLD_H)
				var cave_floor_y := (f_sample.w - door_world_pos.y) if (floor_sdf != null and f_sample.w > -50.0) else (-0.16 - 0.06 * float(ci))
				var stone_top := cave_floor_y + 0.042 + y_lift + sin(float(pi * 3 + ci) * 2.3) * 0.014
				var hy_p := 0.24
				var yaw_p := sin(float(pi * 11 + ci * 3)) * 0.08
				var hx_p := (span_x / float(p_cnt)) * 0.88
				var p_xf := Transform3D(Basis(Vector3.UP, yaw_p), Vector3(px, stone_top - hy_p, pz))
				_add_sculpted_stone_to_st(st_main, p_xf, hx_p, hx_p * 0.94, hy_p, hz_p, 0.56, 0.0, 0.11 + float(pi) * 0.19 + float(ci) * 0.27, 0.86, 0.72, rock_bl, 0.028)

		# 3. Classic Inverted-U (∩) Stone Archway: Vertical Pilasters, Impost Capitals, Rounded Voussoirs, Keystone & Recessed Spandrel Masonry
		var arch_half_span := 3.55
		var arch_spring_y := 6.20

		# Tight inner recessed stone reveal following the clean inverted-U opening (zero wavy dark outer tube!)
		var arch_u_steps := 44
		var arch_v_segs := 10
		var r_rev_off := 0.12
		var r_rev_thk := 0.22
		var z_rev_cen := 0.18
		var z_rev_thk := 0.48
		var rev_pts: Array = []
		var rev_uvs: Array = []
		var rev_cols: Array = []
		var rev_outs: Array = []
		var rev_phs: Array = []
		for iu in range(arch_u_steps + 1):
			var uf := float(iu) / float(arch_u_steps)
			var fr := _round_arch_frame(uf, arch_half_span, arch_spring_y, -0.75)
			var b_xy: Vector2 = fr["pos"]
			var o_xy: Vector2 = fr["out"]
			var ring_c := Vector3(b_xy.x + o_xy.x * r_rev_off, b_xy.y + o_xy.y * r_rev_off, z_rev_cen)
			var rad_3d := Vector3(o_xy.x, o_xy.y, 0.0).normalized()
			var rp: Array[Vector3] = []
			var ruv: Array[Vector2] = []
			var rc: Array[Color] = []
			var ro: Array[Vector3] = []
			var rph: Array[float] = []
			for iv in arch_v_segs:
				var vf := float(iv) / float(arch_v_segs)
				var pa := vf * TAU
				var cp := cos(pa)
				var sp := sin(pa)
				var sx := signf(cp) * pow(absf(cp), 0.76)
				var sz := signf(sp) * pow(absf(sp), 0.76)
				var p := ring_c + rad_3d * (sx * r_rev_thk) + Vector3(0.0, 0.0, sz * z_rev_thk)
				var out_n := (rad_3d * (cp / r_rev_thk) + Vector3(0.0, 0.0, sp / z_rev_thk)).normalized()
				var ao_v := 0.68 * lerpf(0.75, 1.0, clampf(0.5 + 0.5 * sz, 0.0, 1.0))
				rp.append(p)
				ruv.append(Vector2(vf, uf * 4.0))
				rc.append(Color(ao_v, 0.35, 0.04, 1.0))
				ro.append(out_n)
				rph.append(uf * 0.9)
			rev_pts.append(rp)
			rev_uvs.append(ruv)
			rev_cols.append(rc)
			rev_outs.append(ro)
			rev_phs.append(rph)
		_emit_smooth_grid(st_main, rev_pts, rev_uvs, rev_cols, rev_outs, false, true, true, 0.0, rev_phs)

		# Upper spandrel masonry wall sealing cleanly behind/above the semicircular arch into DoorWallIntegrationMesh (no void gaps)
		var spandrel_rows := [
			# [y_center, hy, half_x_span, count, rock_blend]
			[9.75, 0.55, 4.75, 6, 0.36],
			[10.75, 0.58, 4.15, 5, 0.54],
			[11.75, 0.62, 2.95, 4, 0.74],
		]
		for sri in spandrel_rows.size():
			var rspec: Array = spandrel_rows[sri]
			var sy_c := float(rspec[0])
			var hy_s := float(rspec[1])
			var span_s := float(rspec[2])
			var cnt_s := int(rspec[3])
			var r_bl := float(rspec[4])
			for sci in cnt_s:
				var scf := (float(sci) + 0.5) / float(cnt_s)
				var sx := lerpf(-span_s, span_s, scf)
				var hx_s := (span_s / float(cnt_s)) * 1.08
				var sp_xf := Transform3D(Basis.IDENTITY, Vector3(sx, sy_c, 0.34))
				_add_sculpted_stone_to_st(st_main, sp_xf, hx_s, hx_s * 0.96, hy_s, 0.44, 0.46, 0.0, 0.19 + float(sci) * 0.21 + float(sri) * 0.17, 0.84, 0.62, r_bl, 0.028)

		for side_f: float in [-1.0, 1.0]:
			# Outer rock-cheek masonry spandrel tucking cleanly behind DoorWallIntegrationMesh along the straight jambs
			for oji in 6:
				var oy := -0.25 + float(oji) * 1.38
				var o_xf := Transform3D(Basis.IDENTITY, Vector3(side_f * 4.82, oy, 0.32))
				_add_sculpted_stone_to_st(st_main, o_xf, 0.56, 0.54, 0.74, 0.48, 0.50, 0.0, 0.33 + float(oji) * 0.18, 0.82, 0.62, 0.62, 0.032)

			# Heavy carved stone base plinth anchored into cave floor (y = -0.82 .. +0.62m)
			var plinth_xf := Transform3D(Basis.IDENTITY, Vector3(side_f * 4.18, -0.10, 0.48))
			_add_sculpted_stone_to_st(st_main, plinth_xf, 0.74, 0.66, 0.74, 0.68, 0.42, 0.0, 0.18 + side_f * 0.07, 0.88, 0.64, 0.12, 0.024)
			var plinth_cap_xf := Transform3D(Basis.IDENTITY, Vector3(side_f * 4.16, 0.64, 0.50))
			_add_sculpted_stone_to_st(st_main, plinth_cap_xf, 0.68, 0.60, 0.16, 0.70, 0.42, 0.0, 0.34, 0.90, 0.68, 0.06, 0.018)

			# 6 stacked sculpted ashlar jamb pilaster stones rising cleanly vertically from y = 0.78 to y = 5.95
			var pil_y0 := 0.78
			var pil_y1 := 5.95
			var pil_courses := 6
			var pil_step := (pil_y1 - pil_y0) / float(pil_courses)
			for pi in pil_courses:
				var cy := pil_y0 + (float(pi) + 0.5) * pil_step
				var alt := 0.03 if (pi % 2 == 0) else -0.02
				var cx := side_f * (arch_half_span + 0.58 + alt * 0.3)
				var pil_xf := Transform3D(Basis.IDENTITY, Vector3(cx, cy, 0.50 + alt * 0.4))
				_add_sculpted_stone_to_st(st_main, pil_xf, 0.58 + alt, 0.56 - alt * 0.4, pil_step * 0.51, 0.60 + alt * 0.5, 0.44, 0.0, 0.25 + float(pi) * 0.21 + side_f * 0.09, 0.90, 0.68, 0.06, 0.024)

			# Carved projecting impost capital stone at spring line (y = 6.14m)
			var imp_xf := Transform3D(Basis.IDENTITY, Vector3(side_f * (arch_half_span + 0.60), 6.14, 0.54))
			_add_sculpted_stone_to_st(st_main, imp_xf, 0.60, 0.70, 0.22, 0.68, 0.42, 0.0, 0.67, 0.92, 0.70, 0.04, 0.020)

			# 7 wedge-shaped sculpted stone voussoirs sweeping smoothly around the semi-circular arch crown
			var voussoir_count := 7
			var ang_key_half := 0.135
			var ang_start := PI if side_f < 0.0 else 0.0
			var ang_end := (PI * 0.5 + ang_key_half) if side_f < 0.0 else (PI * 0.5 - ang_key_half)
			for vi in voussoir_count:
				var aa := lerpf(ang_start, ang_end, float(vi) / float(voussoir_count))
				var ab := lerpf(ang_start, ang_end, float(vi + 1) / float(voussoir_count))
				var am := 0.5 * (aa + ab)
				var out_2d := Vector2(cos(am), sin(am))
				var r_mid := arch_half_span + 0.58 + (0.025 if (vi % 2 == 0) else -0.015)
				var v_pos := Vector3(out_2d.x * r_mid, arch_spring_y + out_2d.y * r_mid, 0.54 + (0.025 if (vi % 2 == 1) else 0.0))
				var pa_2d := Vector2(cos(aa) * arch_half_span, arch_spring_y + sin(aa) * arch_half_span)
				var pb_2d := Vector2(cos(ab) * arch_half_span, arch_spring_y + sin(ab) * arch_half_span)
				var tang_3d := Vector3(pb_2d.x - pa_2d.x, pb_2d.y - pa_2d.y, 0.0).normalized()
				var out_3d := Vector3(out_2d.x, out_2d.y, 0.0).normalized()
				if tang_3d.cross(out_3d).z < 0.0:
					tang_3d = -tang_3d
				var v_basis := Basis(tang_3d, out_3d, Vector3.BACK)
				var seg_len := (arch_half_span + 0.58) * absf(ab - aa)
				var hx_in := seg_len * 0.45
				var hx_out := seg_len * 0.56
				var v_xf := Transform3D(v_basis, v_pos)
				_add_sculpted_stone_to_st(st_main, v_xf, hx_in, hx_out, 0.40, 0.54, 0.44, 0.0, 0.12 + float(vi) * 0.17 + side_f * 0.05, 0.90, 0.68, 0.06, 0.024)

		# Heavy sculpted center keystone crowning the rounded arch apex (y ~ 10.34m)
		var key_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, arch_spring_y + arch_half_span + 0.60, 0.62))
		_add_sculpted_stone_to_st(st_main, key_xf, 0.44, 0.64, 0.68, 0.62, 0.42, 0.0, 0.89, 0.94, 0.70, 0.04, 0.026)

		# 4. Heavy Kiln-Charred Ancient Oak Double Door Leaves (Inverted-U), Organic Forged Wrought-Iron Hardware
		var door_bot_y := -0.06
		# Solid dark backing slab behind the arch leaves so grooves never reveal empty void
		var back_pts: Array = []
		var back_uvs: Array = []
		var back_cols: Array = []
		var back_outs: Array = []
		var back_phs: Array = []
		for iy in 13:
			var yf := float(iy) / 12.0
			var row_p: Array[Vector3] = []
			var row_uv: Array[Vector2] = []
			var row_c: Array[Color] = []
			var row_o: Array[Vector3] = []
			var row_ph: Array[float] = []
			for ix in 17:
				var xf := float(ix) / 16.0
				var px := lerpf(-arch_half_span - 0.10, arch_half_span + 0.10, xf)
				var y_top := _round_arch_y_at_x(absf(px), arch_half_span, arch_spring_y) + 0.14
				row_p.append(Vector3(px, lerpf(door_bot_y - 0.15, y_top, yf), 0.16))
				row_uv.append(Vector2(xf, yf))
				row_c.append(Color(0.36, 0.15, 0.0, 1.0))
				row_o.append(Vector3.BACK)
				row_ph.append(0.5)
			back_pts.append(row_p)
			back_uvs.append(row_uv)
			back_cols.append(row_c)
			back_outs.append(row_o)
			back_phs.append(row_ph)
		_emit_smooth_grid(st_main, back_pts, back_uvs, back_cols, back_outs, false, false, true, 1.0, back_phs)

		for side_f: float in [-1.0, 1.0]:
			# Sculpted coffered monolithic stone door leaf trimmed cleanly to the inverted-U arch
			_add_planked_round_door_leaf_to_st(st_main, side_f, arch_half_span, arch_spring_y, door_bot_y, 0.34)

			# Carved stone pivot bosses at top & bottom outer corners (authentic stone-door pivot architecture)
			for piv_y: float in [door_bot_y + 0.38, arch_spring_y - 0.28]:
				_add_sculpted_stone_to_st(st_main, Transform3D(Basis.IDENTITY, Vector3(side_f * (arch_half_span - 0.14), piv_y, 0.43)), 0.18, 0.18, 0.24, 0.075, 0.88, 1.0, 0.31, 0.88, 0.55, 0.0, 0.015)

			# Heavy forged-iron drop-ring door handle / knocker (x = +-1.12m, y = 2.65m) mounted on a carved stone rosette
			var ring_x := side_f * 1.12
			var ring_bow := cos(clampf(1.12 / arch_half_span, 0.0, 1.0) * PI * 0.45) * 0.10
			var ring_z := 0.34 + ring_bow
			_add_domed_rivet_to_st(st_main, Vector3(ring_x, 2.65, ring_z), Vector3.BACK, 0.28, 0.065, 1.0, 0.38)
			_add_domed_rivet_to_st(st_main, Vector3(ring_x, 2.65, ring_z + 0.05), Vector3.BACK, 0.095, 0.070, 2.0, 0.52)
			_sculpt_smooth_torus_arc(st_main, Vector3(ring_x, 2.38, ring_z + 0.08), 0.195, 0.285, 0.095, 22, 8, 2.0, 0.62, 0.92, 0.45, 0.0)

		# Carved stone central meeting astragal / rebate molding sealing the center seam
		var seam_pts: Array[Vector3] = []
		var seam_ra: Array[float] = []
		var seam_rb: Array[float] = []
		for si in 13:
			var sy := lerpf(door_bot_y + 0.04, arch_spring_y + arch_half_span - 0.04, float(si) / 12.0)
			seam_pts.append(Vector3(0.0, sy, 0.45))
			seam_ra.append(0.115)
			seam_rb.append(0.065)
		_sculpt_lofted_tube(st_main, seam_pts, seam_ra, seam_rb, 10, 1.0, 0.19, 0.84, 0.90, 0.35, 0.0)

		# Carved Stone Bas-Relief Concentric Seal Medallion across the center of the stone vault doors (y = 5.05m)
		_sculpt_smooth_torus_arc(st_main, Vector3(0.0, 5.05, 0.45), 0.88, 1.06, 0.11, 32, 8, 1.0, 0.27, 0.88, 0.45, 0.0)
		_sculpt_smooth_torus_arc(st_main, Vector3(0.0, 5.05, 0.46), 0.48, 0.62, 0.09, 26, 8, 1.0, 0.41, 0.90, 0.45, 0.0)
		var esc_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 5.05, 0.47))
		_add_sculpted_stone_to_st(st_main, esc_xf, 0.34, 0.34, 0.34, 0.075, 0.92, 3.0, 0.44, 0.92, 0.72, 0.0, 0.008)
		_add_domed_rivet_to_st(st_main, Vector3(0.0, 5.05, 0.56), Vector3.BACK, 0.14, 0.055, 3.0, 0.48)

		# 5. Grounded Carved Stone & Forged Wrought-Iron Standing Braziers (ZERO hoops/bars above y = 3.04m!)
		for side_f: float in [-1.0, 1.0]:
			var tx := side_f * torch_x_abs
			var tc_base := Vector3(tx, 0.0, torch_z)

			# Grounded stepped octagonal stone plinth rooted below Sanctum floor (y = -0.68m .. 0.52m)
			var ped_spine: Array[Vector3] = [
				tc_base + Vector3(0.0, -0.68, 0.0),
				tc_base + Vector3(0.0, -0.10, 0.0),
				tc_base + Vector3(0.0, 0.18, 0.0),
				tc_base + Vector3(0.0, 0.22, 0.0),
				tc_base + Vector3(0.0, 0.48, 0.0),
				tc_base + Vector3(0.0, 0.54, 0.0),
			]
			var ped_ra: Array[float] = [0.90, 0.88, 0.86, 0.68, 0.64, 0.46]
			_sculpt_lofted_tube(st_main, ped_spine, ped_ra, ped_ra, 8, 0.0, 0.22, 0.80, 0.90, 0.45, 0.46)
			_sculpt_horizontal_ring_to_st(st_main, tc_base + Vector3(0.0, 0.56, 0.0), 0.36, 0.54, 0.14, 20, 7, 0.0, 0.28, 0.88, 0.42, 0.08)

			# 12-fluted tapered ancient stone column shaft rising to capital (y = 0.56m .. 2.24m)
			var shaft_spine: Array[Vector3] = [
				tc_base + Vector3(0.0, 0.56, 0.0),
				tc_base + Vector3(0.0, 1.05, 0.0),
				tc_base + Vector3(0.0, 1.65, 0.0),
				tc_base + Vector3(0.0, 2.22, 0.0),
			]
			var shaft_ra: Array[float] = [0.43, 0.40, 0.38, 0.36]
			_sculpt_lofted_tube(st_main, shaft_spine, shaft_ra, shaft_ra, 24, 0.0, 0.16, 0.84, 0.90, 0.40, 0.06, 0.055, 12.0, 0.0)

			# Carved stone column capital & horizontal neck collar (y = 2.18m .. 2.50m)
			_sculpt_horizontal_ring_to_st(st_main, tc_base + Vector3(0.0, 2.20, 0.0), 0.32, 0.46, 0.12, 20, 7, 0.0, 0.36, 0.90, 0.42, 0.04)
			var cap_spine: Array[Vector3] = [
				tc_base + Vector3(0.0, 2.20, 0.0),
				tc_base + Vector3(0.0, 2.36, 0.0),
				tc_base + Vector3(0.0, 2.50, 0.0),
			]
			var cap_ra: Array[float] = [0.37, 0.48, 0.44]
			_sculpt_lofted_tube(st_main, cap_spine, cap_ra, cap_ra, 8, 0.0, 0.42, 0.86, 0.92, 0.42, 0.04)

			# 4 forged-iron scroll/strut brackets flaring underneath from capital to cradle the fire bowl (strictly <= y = 2.94m)
			for bi in 4:
				var ba := PI * 0.25 + float(bi) * (PI * 0.5)
				var b_dir := Vector3(cos(ba), 0.0, sin(ba))
				var lug_pts: Array[Vector3] = [
					tc_base + Vector3(0.0, 2.24, 0.0) + b_dir * 0.36,
					tc_base + Vector3(0.0, 2.44, 0.0) + b_dir * 0.58,
					tc_base + Vector3(0.0, 2.68, 0.0) + b_dir * 0.78,
					tc_base + Vector3(0.0, 2.92, 0.0) + b_dir * 0.86,
				]
				_sculpt_lofted_tube(st_main, lug_pts, [0.068, 0.072, 0.066, 0.056], [0.052, 0.056, 0.052, 0.046], 8, 2.0, float(bi) * 0.22, 0.86, 0.94, 0.45, 0.0)

			# Wide shallow riveted wrought-iron fire cauldron bowl with recessed hollow fire basin (y = 2.48m .. 3.03m)
			var bowl_spine: Array[Vector3] = [
				tc_base + Vector3(0.0, 2.48, 0.0),
				tc_base + Vector3(0.0, 2.64, 0.0),
				tc_base + Vector3(0.0, 2.84, 0.0),
				tc_base + Vector3(0.0, 3.01, 0.0),
				tc_base + Vector3(0.0, 3.03, 0.0),
				tc_base + Vector3(0.0, 2.92, 0.0),
				tc_base + Vector3(0.0, 2.78, 0.0),
				tc_base + Vector3(0.0, 2.73, 0.0),
			]
			var bowl_ra: Array[float] = [0.42, 0.64, 0.80, 0.87, 0.77, 0.69, 0.52, 0.05]
			_sculpt_lofted_tube(st_main, bowl_spine, bowl_ra, bowl_ra, 24, 2.0, 0.45, 0.84, 0.94, 0.45, 0.0)

			# TRUE HORIZONTAL (XZ-plane) iron rim band, tarnished bronze belly band & 12 domed rivets (nothing above rim!)
			_sculpt_horizontal_ring_to_st(st_main, tc_base + Vector3(0.0, 2.97, 0.0), 0.78, 0.90, 0.11, 24, 7, 2.0, 0.55, 0.92, 0.45, 0.0)
			_sculpt_horizontal_ring_to_st(st_main, tc_base + Vector3(0.0, 2.68, 0.0), 0.62, 0.71, 0.08, 24, 6, 3.0, 0.40, 0.90, 0.45, 0.0)
			for ri in 12:
				var ra := float(ri) * (TAU / 12.0)
				var r_dir := Vector3(cos(ra), 0.0, sin(ra))
				_add_domed_rivet_to_st(st_main, tc_base + Vector3(0.0, 2.97, 0.0) + r_dir * 0.885, r_dir, 0.036, 0.026, 2.0, 0.12 + float(ri) * 0.08)

		st_main.generate_tangents()
		main_mesh = st_main.commit()
		if main_mesh != null:
			main_mesh.set_meta("door_origin", door_world_pos)
			_cached_door_monolith_mesh = main_mesh
			_save_cached_res(main_mesh, DOOR_MONOLITH_MESH_PATH)
	var main_mi := MeshInstance3D.new()
	main_mi.name = "DoorMonolithMesh"
	main_mi.mesh = main_mesh
	main_mi.material_override = relief_mat
	main_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door_root.add_child(main_mi)

	_door_astrolabe_outer = null
	_door_astrolabe_inner = null

	# 8. Flanking Brazier Fire VFX: Glowing Coal Bed + 4-Layer Real-Time Fire (Flipbook, Flame Cards, Smoke, Embers, Heat Haze)
	var coal_mesh := _build_brazier_coal_bed_mesh()
	var flame_cards_mesh := _build_crossed_flame_cards_mesh()
	var fire_noise_tex := _get_fire_noise_tex()
	var fire_flipbook_tex := _get_fire_flipbook_tex()
	var coal_tex := _get_crystal_interior_tex()

	for ti in 2:
		var side_f := -1.0 if ti == 0 else 1.0
		var sfx := "L" if ti == 0 else "R"
		var torch_pivot := Node3D.new()
		torch_pivot.name = "WeirdTorch_%s" % sfx
		torch_pivot.position = Vector3(side_f * torch_x_abs, 2.86, torch_z)
		door_root.add_child(torch_pivot)
		_attach_brazier_fire_vfx(
			torch_pivot, ti,
			coal_mesh, flame_cards_mesh,
			torch_shader, flame_card_shader, flame_particle_shader,
			smoke_shader, ember_shader, haze_shader,
			fire_noise_tex, fire_flipbook_tex, coal_tex
		)

	# 9. Physical Obstacle Colliders on Layer 4 (WALLS/OBSTACLES): Portal + Integrated Cliff Flanks + Bridged Torch Pedestals
	var static_body := StaticBody3D.new()
	static_body.name = "AncientDoorBody"
	static_body.collision_layer = 4
	static_body.collision_mask = 0

	var col_portal := CollisionShape3D.new()
	col_portal.name = "PortalCollider"
	var box_portal := BoxShape3D.new()
	box_portal.size = Vector3(door_w + 5.8, door_h + 4.2, door_d + 1.6)
	col_portal.shape = box_portal
	col_portal.position = Vector3(0.0, 6.8, -0.65)
	static_body.add_child(col_portal)

	for side_f: float in [-1.0, 1.0]:
		var sfx := "L" if side_f < 0.0 else "R"

		var col_flank := CollisionShape3D.new()
		col_flank.name = "CliffFlankCollider_%s" % sfx
		var box_flank := BoxShape3D.new()
		box_flank.size = Vector3(9.4, 15.0, 4.6)
		col_flank.shape = box_flank
		col_flank.position = Vector3(side_f * 9.8, 6.6, -1.40)
		col_flank.rotation = Vector3(0.0, -side_f * deg_to_rad(8.0), 0.0)
		static_body.add_child(col_flank)

		var col_torch := CollisionShape3D.new()
		col_torch.name = "TorchPedestalCollider_%s" % sfx
		var cyl_torch := CylinderShape3D.new()
		cyl_torch.radius = 0.92
		cyl_torch.height = 5.0
		col_torch.shape = cyl_torch
		col_torch.position = Vector3(side_f * torch_x_abs, 2.1, torch_z)
		static_body.add_child(col_torch)

		var col_bridge := CollisionShape3D.new()
		col_bridge.name = "TorchRootBridge_%s" % sfx
		var box_bridge := BoxShape3D.new()
		box_bridge.size = Vector3(1.84, 5.0, 1.85)
		col_bridge.shape = box_bridge
		col_bridge.position = Vector3(side_f * torch_x_abs, 2.1, 1.45)
		static_body.add_child(col_bridge)

	door_root.add_child(static_body)


func _build_reverb_zones() -> void:
	if Engine.is_editor_hint():
		return
	var bus_name := &"CaveReverb"
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.82
		rev.damping = 0.45
		rev.wet = 0.42
		AudioServer.add_bus_effect(idx, rev)
	_reverb_bus_idx = idx

	var zones := [
		["HallReverbZone", Vector3(-60.0, 28.0, 72.0), Vector3(72.0, 34.0, 48.0), 0.45],
		["GrottoReverbZone", Vector3(-16.0, 19.0, 82.0), Vector3(44.0, 16.0, 44.0), 0.32],
		["AtriumReverbZone", Vector3(38.0, 13.0, 112.0), Vector3(36.0, 18.0, 42.0), 0.42],
		["LakeReverbZone", Vector3(-5.0, 14.0, 178.0), Vector3(132.0, 26.0, 114.0), 0.58],
		["VaultSanctumReverbZone", Vector3(-179.0, 10.0, 71.0), Vector3(44.0, 22.0, 40.0), 0.44],
	]
	var rz_parent := Node3D.new()
	rz_parent.name = "CaveReverbZones"
	add_child(rz_parent)
	for z: Array in zones:
		var a := Area3D.new()
		a.name = String(z[0])
		a.reverb_bus_enabled = true
		a.reverb_bus_name = bus_name
		a.reverb_bus_amount = float(z[3])
		a.monitoring = false
		a.monitorable = false
		a.position = CaveLayout.to_world(z[1] as Vector3)
		var b_cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = z[2] as Vector3
		b_cs.shape = box
		a.add_child(b_cs)
		rz_parent.add_child(a)
