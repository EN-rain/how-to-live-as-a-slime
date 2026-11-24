@tool
class_name TerrainScene
extends Node3D
## Self-contained 3D Continent-Scale Landmass + Contour-Hugging Annular Ocean + Lush Meadow Grass.
## Optimized for fast startup and high FPS:
## - Spatial early-out fast paths in sample_height() (skips 85% of noise calls in central valley)
## - Direct barycentric/bilinear grid interpolation for grass placement (zero noise calls for height/normal)
## - Non-linear 192x192 focused mesh (~9.7m resolution near player, 24% fewer triangles)
## - Seabed-culled ConcavePolygonShape3D BVH collision mesh
## - Pre-allocated index buffers for terrain and contour-hugging annular ocean.

const VillageBuilder = preload("res://terrain/village_builder.gd")
const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
const DungeonCaveBuilder = preload("res://scripts/dungeon_cave_builder.gd")
const TerritoryBuilder = preload("res://scripts/territory_builder.gd")
const WebwoodRegion = preload("res://regions/webwood/webwood_region.gd")
const WebwoodProfile = preload("res://regions/webwood/webwood_profile.gd")
const RegionalScatterProfile = preload("res://terrain/resources/regional_scatter_profile.gd")

@export_group("Regions")
@export var webwood_scene: PackedScene = preload("res://regions/webwood/webwood_region.tscn")
@export var webwood_profile_override: WebwoodProfile = null
@export var wolf_crag_scene: PackedScene = preload("res://regions/wolf_crag/wolf_crag_region.tscn")
@export var waystones_scene: PackedScene = preload("res://regions/waystones/waystones_region.tscn")
@export var rat_warren_scene: PackedScene = preload("res://regions/rat_warren/rat_warren_region.tscn")
@export var skeleton_crypt_scene: PackedScene = preload("res://regions/skeleton_crypt/skeleton_crypt_region.tscn")
@export var village_scene: PackedScene = preload("res://regions/village/village_region.tscn")
@export var regional_scatter: RegionalScatterProfile = preload("res://terrain/resources/default_regional_scatter.tres")
var _webwood_layout: Dictionary = {}

@export_group("Continent & Terrain")
@export var terrain_size: float = 7200.0:
	set(v):
		terrain_size = maxf(v, 100.0)
		_cached_grid_coords.clear()
		_rebuild_if_ready()
@export var terrain_subdivisions: int = 192:
	set(v):
		terrain_subdivisions = clampi(v, 24, 256)
		_cached_grid_coords.clear()
		_rebuild_if_ready()
@export var continent_radius: float = 2600.0:
	set(v):
		continent_radius = maxf(v, 100.0)
		_rebuild_if_ready()
@export var flat_center_radius: float = 45.0:
	set(v):
		flat_center_radius = maxf(v, 0.0)
		_rebuild_if_ready()
@export var sea_level: float = 0.0:
	set(v):
		sea_level = v
		_rebuild_if_ready()
@export var terrain_seed: int = 1337:
	set(v):
		terrain_seed = v
		_rebuild_if_ready()

@export_group("Heights & Biomes")
## Base elevation of the central spawn meadow amphitheater.
@export var valley_floor_height: float = 22.0:
	set(v):
		valley_floor_height = v
		_rebuild_if_ready()
## Depth of the deep ocean seabed around the continental shelf.
@export var seabed_depth: float = -22.0:
	set(v):
		seabed_depth = v
		_rebuild_if_ready()
## Height multiplier for northern alpine mountain peaks.
@export_range(0.0, 3.0, 0.05) var mountain_height_multiplier: float = 1.0:
	set(v):
		mountain_height_multiplier = maxf(v, 0.0)
		_rebuild_if_ready()
## Height multiplier for western layered mesas.
@export_range(0.0, 3.0, 0.05) var mesa_height_multiplier: float = 1.0:
	set(v):
		mesa_height_multiplier = maxf(v, 0.0)
		_rebuild_if_ready()
## Height multiplier for eastern downs and central meadow hills.
@export_range(0.0, 3.0, 0.05) var hills_height_multiplier: float = 1.0:
	set(v):
		hills_height_multiplier = maxf(v, 0.0)
		_rebuild_if_ready()

@export_group("Ocean & Water")
## Outer radius of the annular ocean ring mesh.
@export var ocean_outer_radius: float = 14000.0:
	set(v):
		ocean_outer_radius = maxf(v, 1000.0)
		_rebuild_if_ready()
## Radial concentric rings in the contour-hugging water mesh.
@export var water_rings: int = 28:
	set(v):
		water_rings = clampi(v, 4, 128)
		_rebuild_if_ready()
## Angular segments in the water mesh.
@export var water_segments: int = 192:
	set(v):
		water_segments = clampi(v, 16, 256)
		_rebuild_if_ready()

@export_group("Grass Placement & Visuals")
## Total grass instances distributed across the active meadow disk.
@export var grass_count: int = 24000:
	set(v):
		grass_count = clampi(v, 0, 250000)
		_rebuild_if_ready()
@export var min_grass_normal_y: float = 0.50:
	set(v):
		min_grass_normal_y = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()
## Radius across the island meadow in which grass is densely populated.
@export var grass_spawn_radius: float = 220.0:
	set(v):
		grass_spawn_radius = maxf(v, 10.0)
		_rebuild_if_ready()
## Distance beyond which grass fades out.
@export var grass_visibility_end: float = 220.0:
	set(v):
		grass_visibility_end = maxf(v, 10.0)
		_rebuild_if_ready()
## Margin distance for grass fade out transition.
@export var grass_visibility_margin: float = 40.0:
	set(v):
		grass_visibility_margin = maxf(v, 0.0)
		_rebuild_if_ready()
## Average spacing between hexagonal blue-noise lattice nodes.
@export var grass_spacing: float = 0.82:
	set(v):
		grass_spacing = clampf(v, 0.25, 3.0)
		_rebuild_if_ready()
## Minimum vertical scale multiplier for grass tufts.
@export var grass_scale_y_min: float = 1.15:
	set(v):
		grass_scale_y_min = maxf(v, 0.1)
		_rebuild_if_ready()
## Maximum vertical scale multiplier for grass tufts.
@export var grass_scale_y_max: float = 1.65:
	set(v):
		grass_scale_y_max = maxf(v, 0.1)
		_rebuild_if_ready()
## Minimum horizontal scale multiplier for grass tufts.
@export var grass_scale_xz_min: float = 1.10:
	set(v):
		grass_scale_xz_min = maxf(v, 0.1)
		_rebuild_if_ready()
## Maximum horizontal scale multiplier for grass tufts.
@export var grass_scale_xz_max: float = 1.50:
	set(v):
		grass_scale_xz_max = maxf(v, 0.1)
		_rebuild_if_ready()
## Half-width of individual grass blades at the base.
@export var grass_blade_base_half_w: float = 0.22:
	set(v):
		grass_blade_base_half_w = maxf(v, 0.01)
		_rebuild_if_ready()

@export_group("Grass Clustering & Clearings")
## Density threshold below which grass is completely absent.
@export_range(0.1, 0.6, 0.01) var grass_clearing_threshold: float = 0.40:
	set(v):
		grass_clearing_threshold = clampf(v, 0.05, 0.8)
		_rebuild_if_ready()
## Gravity blend factor: 0.0 = pure skyward (0,1,0), 1.0 = pure terrain normal.
## 0.18 gives natural phototropism (plants grow predominantly upward toward the sun with gentle 18% slope lean).
@export_range(0.0, 0.6, 0.02) var grass_slope_gravity_blend: float = 0.18:
	set(v):
		grass_slope_gravity_blend = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()

@export_group("Grass Map (Terrain Mask)")
## Painted RGB terrain grass map texture (R=density, G=height multiplier, B=species bias).
## When null, a multi-channel procedural grass map is generated automatically.
@export var grass_map_override: Texture2D = null:
	set(v):
		grass_map_override = v
		_grass_map_image = null
		_grass_map_tex = null
		_grass_map_rgba = PackedByteArray()
		_rebuild_if_ready()
## World-space coverage rect (X, Z origin and width, depth) mapped by grass_map UV [0..1].
@export var grass_map_bounds: Rect2 = Rect2(-1200.0, -900.0, 2600.0, 3800.0)
## Minimum height scale when the grass map G channel is 0.0 (cropped meadow lawns).
@export_range(0.15, 1.0, 0.02) var grass_height_map_min: float = 0.36:
	set(v):
		grass_height_map_min = v
		_rebuild_if_ready()
## Maximum height scale when the grass map G channel is 1.0 (tall wildgrass swells).
@export_range(1.0, 3.5, 0.05) var grass_height_map_max: float = 1.65:
	set(v):
		grass_height_map_max = v
		_rebuild_if_ready()

@export_group("Collision")
## Grid sampling stride for concave collision mesh (1 = exact 1:1 match with visual terrain).
@export var collision_stride: int = 1:
	set(v):
		collision_stride = clampi(v, 1, 8)
		_rebuild_if_ready()

@export_group("Trees & Woodlands")
## Enable deterministic tree generation using the Stylized Nature MegaKit assets.
@export var enable_trees: bool = true:
	set(v):
		enable_trees = v
		_rebuild_if_ready()
## Fixed seed for 100% deterministic tree placement, scale, rotation, and species.
@export var tree_seed: int = 42:
	set(v):
		tree_seed = v
		_rebuild_if_ready()
## Total number of trees placed across the valley and surrounding hills.
@export_range(0, 600, 10) var tree_count: int = 340:
	set(v):
		tree_count = clampi(v, 0, 1200)
		_rebuild_if_ready()
## Radius around origin in which trees can grow.
@export var tree_spawn_radius: float = 280.0:
	set(v):
		tree_spawn_radius = maxf(v, 20.0)
		_rebuild_if_ready()
## Clearing around player spawn point kept completely open.
@export var tree_clearing_radius: float = 32.0:
	set(v):
		tree_clearing_radius = maxf(v, 0.0)
		_rebuild_if_ready()
## Minimum spacing between tree trunks (prevents overlap).
@export var min_tree_spacing: float = 10.5:
	set(v):
		min_tree_spacing = maxf(v, 2.0)
		_rebuild_if_ready()
## Minimum ground normal Y (trees only grow on walkable slopes).
@export var min_tree_normal_y: float = 0.78:
	set(v):
		min_tree_normal_y = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()
## Minimum elevation above sea level.
@export var tree_min_height: float = 6.0:
	set(v):
		tree_min_height = v
		_rebuild_if_ready()
## Maximum elevation (alpine tree line).
@export var tree_max_height: float = 95.0:
	set(v):
		tree_max_height = v
		_rebuild_if_ready()

@export_group("Rocks & Stones")
## Enable deterministic rocks & boulders using the Stylized Nature MegaKit assets.
@export var enable_rocks: bool = true:
	set(v):
		enable_rocks = v
		_rebuild_if_ready()
## Fixed seed for 100% deterministic rock placement, scale, and rotation.
@export var rock_seed: int = 101:
	set(v):
		rock_seed = v
		_rebuild_if_ready()
## Total number of rocks and boulders placed across the landscape.
@export_range(0, 500, 10) var rock_count: int = 120:
	set(v):
		rock_count = clampi(v, 0, 800)
		_rebuild_if_ready()
## Radius around origin in which rocks can spawn.
@export var rock_spawn_radius: float = 290.0:
	set(v):
		rock_spawn_radius = maxf(v, 10.0)
		_rebuild_if_ready()
## Clearing radius around origin (0, 0) free of large rocks.
@export var rock_clearing_radius: float = 8.0:
	set(v):
		rock_clearing_radius = maxf(v, 0.0)
		_rebuild_if_ready()
## Minimum spacing between rocks.
@export var min_rock_spacing: float = 9.0:
	set(v):
		min_rock_spacing = maxf(v, 1.0)
		_rebuild_if_ready()
## Minimum ground normal Y (rocks can cling to steeper slopes than trees).
@export var min_rock_normal_y: float = 0.42:
	set(v):
		min_rock_normal_y = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()
## Minimum elevation for rocks (can spawn down to beach shore).
@export var rock_min_height: float = 1.5:
	set(v):
		rock_min_height = v
		_rebuild_if_ready()
## Maximum elevation for rocks (can spawn up to mountain summits).
@export var rock_max_height: float = 135.0:
	set(v):
		rock_max_height = v
		_rebuild_if_ready()

@export_group("Vegetation & Wildflowers")
## Enable deterministic bushes, plants, and wildflowers using the Stylized Nature MegaKit assets.
@export var enable_vegetation: bool = true:
	set(v):
		enable_vegetation = v
		_rebuild_if_ready()
## Fixed seed for 100% deterministic vegetation placement, scale, and species.
@export var vegetation_seed: int = 202:
	set(v):
		vegetation_seed = v
		_rebuild_if_ready()
## Total number of bushes, plants, and wildflower patches placed across the meadows.
@export_range(0, 1000, 20) var vegetation_count: int = 350:
	set(v):
		vegetation_count = clampi(v, 0, 1500)
		_rebuild_if_ready()
## Radius around origin in which vegetation can grow.
@export var vegetation_spawn_radius: float = 270.0:
	set(v):
		vegetation_spawn_radius = maxf(v, 10.0)
		_rebuild_if_ready()
## Clearing radius around origin free of thick bushes.
@export var vegetation_clearing_radius: float = 5.0:
	set(v):
		vegetation_clearing_radius = maxf(v, 0.0)
		_rebuild_if_ready()
## Minimum spacing between vegetation items.
@export var min_vegetation_spacing: float = 3.2:
	set(v):
		min_vegetation_spacing = maxf(v, 0.5)
		_rebuild_if_ready()
## Minimum ground normal Y (vegetation grows on walkable slopes).
@export var min_vegetation_normal_y: float = 0.80:
	set(v):
		min_vegetation_normal_y = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()
## Minimum elevation for vegetation.
@export var vegetation_min_height: float = 4.0:
	set(v):
		vegetation_min_height = v
		_rebuild_if_ready()
## Maximum elevation for vegetation (subalpine meadows).
@export var vegetation_max_height: float = 95.0:
	set(v):
		vegetation_max_height = v
		_rebuild_if_ready()

@export_group("Editor Preview")
## If true, renders a lightweight grass preview in the editor 3D viewport (disabled by default for instant zero-lag editor preview).
@export var preview_grass_in_editor: bool = false:
	set(v):
		preview_grass_in_editor = v
		_rebuild_if_ready()
## Maximum grass tufts rendered in editor preview when preview_grass_in_editor is turned on.
## 4,000 instances within an 18m radius yields the full dense commercial carpet in the editor preview.
@export_range(0, 8000, 100) var editor_grass_count: int = 4000:
	set(v):
		editor_grass_count = v
		_rebuild_if_ready()
## If true, renders trees in the editor preview (disabled by default for instant zero-lag editor preview).
@export var preview_trees_in_editor: bool = false:
	set(v):
		preview_trees_in_editor = v
		_rebuild_if_ready()
## Maximum trees rendered in editor preview when preview_trees_in_editor is turned on.
@export_range(0, 100, 10) var editor_tree_count: int = 40:
	set(v):
		editor_tree_count = v
		_rebuild_if_ready()
## If true, renders rocks in the editor preview (disabled by default for instant zero-lag editor preview).
@export var preview_rocks_in_editor: bool = false:
	set(v):
		preview_rocks_in_editor = v
		_rebuild_if_ready()
## Maximum rocks rendered in editor preview when preview_rocks_in_editor is turned on.
@export_range(0, 100, 5) var editor_rock_count: int = 25:
	set(v):
		editor_rock_count = v
		_rebuild_if_ready()
## If true, renders vegetation in the editor preview (disabled by default for instant zero-lag editor preview).
@export var preview_vegetation_in_editor: bool = false:
	set(v):
		preview_vegetation_in_editor = v
		_rebuild_if_ready()
## Maximum vegetation rendered in editor preview when preview_vegetation_in_editor is turned on.
@export_range(0, 100, 10) var editor_vegetation_count: int = 40:
	set(v):
		editor_vegetation_count = v
		_rebuild_if_ready()
## Terrain subdivisions used in editor preview. 48x48 is instant (<8ms) and silky smooth.
@export_range(24, 128, 8) var editor_subdivisions: int = 48:
	set(v):
		editor_subdivisions = clampi(v, 24, 256)
		_cached_grid_coords.clear()
		_rebuild_if_ready()

@export_group("Mountain Mist & Fog")
## Enable drifting 3D cloud and mist layers over high alpine mountain peaks.
@export var enable_mountain_fog: bool = true:
	set(v):
		enable_mountain_fog = v
		_rebuild_if_ready()
## Minimum terrain height (meters) where mountain-top mist sheets spawn.
@export_range(70.0, 220.0, 2.0) var mountain_fog_min_height: float = 108.0:
	set(v):
		mountain_fog_min_height = v
		_rebuild_if_ready()
## Maximum number of mist sheet instances placed across high alpine ridges and peaks.
@export_range(0, 320, 10) var mountain_fog_count: int = 160:
	set(v):
		mountain_fog_count = v
		_rebuild_if_ready()
## Base opacity of the mountain-top mist sheets.
@export_range(0.05, 0.85, 0.02) var mountain_fog_opacity: float = 0.34:
	set(v):
		mountain_fog_opacity = v
		_rebuild_if_ready()
## Color tint of the mountain-top mist sheets.
@export var mountain_fog_color: Color = Color(0.90, 0.94, 0.99, 1.0):
	set(v):
		mountain_fog_color = v
		_rebuild_if_ready()

@export_group("Colossal World Cave")
## Enable the 168m-deep Starlight Crystal Cavern in the NNW mountain massif.
@export var enable_cave: bool = true:
	set(v):
		enable_cave = v
		_rebuild_if_ready()
## If true, builds the 3D cave preview in the editor viewport.
@export var preview_cave_in_editor: bool = false:
	set(v):
		preview_cave_in_editor = v
		_rebuild_if_ready()

var _noise: FastNoiseLite
var _cached_grid_coords := PackedFloat32Array()
var _cached_grid_heights := PackedFloat32Array()
var _cached_grid_heights_n: int = -1
var _built_once := false
var _rebuild_pending := false


func _ready() -> void:
	set_process(not Engine.is_editor_hint())
	if not Engine.is_editor_hint():
		var authored_base := grass_count
		if not has_meta("authored_grass_count"):
			set_meta("authored_grass_count", authored_base)
		var settings := SlimeSettings.get_or_create()
		if settings != null:
			var q_idx := clampi(int(settings.get_value("graphics", "quality_preset", 0)), 0, SlimeSettings.QUALITY_PRESETS.size() - 1)
			var preset: Dictionary = SlimeSettings.QUALITY_PRESETS[q_idx]
			var g_mult := float(settings.get_value("graphics", "grass_density", preset["grass_mult"]))
			grass_count = clampi(int(roundf(float(authored_base) * g_mult)), 0, 250000)
			_active_grass_vis_end = clampf(float(preset.get("vis_grass", 160.0)) * 0.56, 28.0, 95.0)
		if get_parent() != null:
			var slime_node := get_parent().get_node_or_null("Slime") as Node3D
			if slime_node != null:
				_grass_center = Vector2(slime_node.position.x, slime_node.position.z)
	_built_once = true
	rebuild()


func _rebuild_if_ready() -> void:
	if not is_inside_tree() or not is_node_ready() or not _built_once:
		return
	if not _rebuild_pending:
		_rebuild_pending = true
		_deferred_rebuild.call_deferred()


func _deferred_rebuild() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	rebuild()


func get_webwood_region() -> WebwoodRegion:
	var reg := get_node_or_null("WebwoodRegion") as WebwoodRegion
	if reg == null and webwood_scene != null:
		reg = webwood_scene.instantiate() as WebwoodRegion
		if reg != null:
			reg.name = "WebwoodRegion"
			add_child(reg)
	if reg != null and webwood_profile_override != null:
		reg.set("profile", webwood_profile_override)
	return reg


func get_webwood_layout() -> Dictionary:
	var reg := get_webwood_region()
	if reg != null:
		return reg.get_effective_layout()
	return {}


func get_webwood_center() -> Vector2:
	if not _webwood_layout.is_empty():
		return _webwood_layout.get("center", WorldLandmarks.SPIDER_FOREST_CENTER)
	var reg := get_node_or_null("WebwoodRegion") as WebwoodRegion
	if reg != null:
		return reg.get_effective_layout().get("center", WorldLandmarks.SPIDER_FOREST_CENTER)
	return WorldLandmarks.SPIDER_FOREST_CENTER


func _apply_webwood_shader_uniforms(mat: ShaderMaterial, layout: Dictionary) -> void:
	if mat == null or layout.is_empty():
		return
	mat.set_shader_parameter("u_webwood_center", layout.get("center", WorldLandmarks.SPIDER_FOREST_CENTER))
	mat.set_shader_parameter("u_webwood_trail_start", layout.get("trail_start", WorldLandmarks.SPIDER_TRAIL_START))
	mat.set_shader_parameter("u_webwood_trail_bend", layout.get("trail_bend", WorldLandmarks.SPIDER_TRAIL_BEND))


func rebuild() -> void:
	_setup_noise()
	_webwood_layout = get_webwood_layout()
	var terrain_node := get_node_or_null("Terrain") as MeshInstance3D
	var grass_node := get_node_or_null("Grass") as MultiMeshInstance3D
	var wispy_node := get_node_or_null("GrassWispy") as MultiMeshInstance3D
	var distant_node := get_node_or_null("GrassDistant") as MultiMeshInstance3D
	if terrain_node != null:
		_apply_webwood_shader_uniforms(terrain_node.material_override as ShaderMaterial, _webwood_layout)
		if terrain_node.material_override is ShaderMaterial:
			var tmat := terrain_node.material_override as ShaderMaterial
			tmat.set_shader_parameter("sea_level", sea_level)
			var rtex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
			if rtex != null:
				tmat.set_shader_parameter("detail_rock_tex", rtex)
			_sync_trail_map_to_material(tmat)
	if grass_node != null:
		_apply_webwood_shader_uniforms(grass_node.material_override as ShaderMaterial, _webwood_layout)
	if wispy_node != null:
		_apply_webwood_shader_uniforms(wispy_node.material_override as ShaderMaterial, _webwood_layout)
	if distant_node != null:
		_apply_webwood_shader_uniforms(distant_node.material_override as ShaderMaterial, _webwood_layout)
	var water_node := get_node_or_null("Water") as MeshInstance3D
	var trees_node := get_node_or_null("Trees") as Node3D
	var rocks_node := get_node_or_null("Rocks") as Node3D
	var veg_node := get_node_or_null("Vegetation") as Node3D

	if terrain_node != null:
		terrain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_build_terrain_mesh(terrain_node)
		if not Engine.is_editor_hint():
			_build_terrain_occluder()

	VillageBuilder.ensure_dock_layout(self)

	if water_node != null:
		_build_water_mesh(water_node)

	_cached_grass_data.clear()
	_cached_regional_grass_data.clear()
	_cached_grass_count = -1
	if not Engine.is_editor_hint() and _active_grass_vis_end <= 0.0:
		var settings_r := SlimeSettings.get_or_create()
		if settings_r != null:
			var q_idx_r := clampi(int(settings_r.get_value("graphics", "quality_preset", 0)), 0, SlimeSettings.QUALITY_PRESETS.size() - 1)
			_active_grass_vis_end = clampf(float(SlimeSettings.QUALITY_PRESETS[q_idx_r].get("vis_grass", 160.0)) * 0.56, 28.0, 95.0)
	if grass_node != null:
		grass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_build_grass_multimesh(grass_node)

	if wispy_node != null:
		wispy_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_build_grass_wispy_multimesh(wispy_node)

	if trees_node != null:
		_build_trees(trees_node)

	if rocks_node != null:
		_build_rocks(rocks_node)

	if veg_node != null:
		_build_vegetation(veg_node)

	_build_mountain_fog()
	_build_cave()
	_build_village()
	_build_landmarks()


func _build_village() -> void:
	if Engine.is_editor_hint():
		return
	var v_reg := _ensure_region_node("VillageRegion", village_scene)
	VillageBuilder.build_village(self, v_reg)


func _ensure_region_node(node_name: String, scene_res: PackedScene) -> Node:
	var n := get_node_or_null(node_name)
	if n == null and scene_res != null:
		n = scene_res.instantiate()
		if n != null:
			n.name = node_name
			add_child(n)
	return n


func _build_landmarks() -> void:
	if Engine.is_editor_hint():
		return
	var crypt_reg := _ensure_region_node("SkeletonCryptRegion", skeleton_crypt_scene)
	var skel_cave := get_node_or_null("SkeletonDungeonCave") as DungeonCaveBuilder
	if skel_cave == null and crypt_reg != null:
		skel_cave = crypt_reg.get_node_or_null("SkeletonDungeonCave") as DungeonCaveBuilder
	if skel_cave == null:
		skel_cave = DungeonCaveBuilder.new()
		skel_cave.set("crypt_region", crypt_reg)
		if crypt_reg != null:
			crypt_reg.add_child(skel_cave)
		else:
			add_child(skel_cave)
	else:
		skel_cave.set("crypt_region", crypt_reg)
	var wolf_reg := _ensure_region_node("WolfCragRegion", wolf_crag_scene)
	var waystones_reg := _ensure_region_node("WaystonesRegion", waystones_scene)
	var rat_reg := _ensure_region_node("RatWarrenRegion", rat_warren_scene)
	var terr_b := get_node_or_null("BeastTerritories") as TerritoryBuilder
	if terr_b == null:
		terr_b = TerritoryBuilder.new()
		terr_b.name = "BeastTerritories"
		add_child(terr_b)
		terr_b.setup_territories(self, _spider_forest_trees, get_webwood_region(), wolf_reg, waystones_reg, rat_reg)


func _build_cave() -> void:
	var cave_node := get_node_or_null("Cave") as CaveSystem
	if not enable_cave:
		if cave_node != null:
			cave_node._clear_generated_children()
		return
	if Engine.is_editor_hint() and not preview_cave_in_editor:
		if cave_node != null:
			cave_node._clear_generated_children()
		return
	if cave_node == null:
		cave_node = CaveSystem.new()
		cave_node.name = "Cave"
		add_child(cave_node)
	cave_node.rebuild_cave(self, terrain_seed, not Engine.is_editor_hint())


func _setup_noise() -> void:
	_cached_grid_heights.clear()
	_cached_grid_heights_n = -1
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.48


## Smooth ridge function (avoids sharp 1-vertex creases on coarse grids).
func _smooth_ridge(n: float) -> float:
	return 1.0 - sqrt(n * n + 0.025)


## Sculpted anisotropic mountain peak with fast bounding-box rejection.
func _sculpted_peak(x: float, z: float, px: float, pz: float, radius: float, height: float, ridge_angle: float) -> float:
	var dx := x - px
	var bound := radius * 1.55
	if dx > bound or dx < -bound:
		return 0.0
	var dz := z - pz
	if dz > bound or dz < -bound:
		return 0.0
	var d2 := dx * dx + dz * dz
	var r2 := radius * radius
	if d2 >= r2 * 2.4:
		return 0.0
	var ca := cos(ridge_angle)
	var sa := sin(ridge_angle)
	var rx := dx * ca - dz * sa
	var rz := dx * sa + dz * ca
	var ellip_d2 := (rx * rx) / (r2 * 1.35) + (rz * rz) / (r2 * 0.65)
	if ellip_d2 >= 2.2:
		return 0.0
	var base_falloff := exp(-ellip_d2 * 1.45)
	var ridge_spine := _smooth_ridge(_noise.get_noise_2d(rx * 0.0035 + px * 0.01, rz * 0.0055 + pz * 0.01))
	var sub_ridge := _smooth_ridge(_noise.get_noise_2d(x * 0.006 - 30.0, z * 0.006 + 40.0))
	var sculpt := clampf(0.55 + 0.42 * ridge_spine + 0.18 * sub_ridge, 0.0, 1.25)
	return height * base_falloff * sculpt


func sample_height(x: float, z: float) -> float:
	if _noise == null:
		_setup_noise()
	var dist_sq := x * x + z * z

	# Fast-path rejects points deep in the outer ocean
	var max_outer_r := continent_radius + 950.0
	if dist_sq > max_outer_r * max_outer_r:
		return seabed_depth

	var dist := sqrt(dist_sq)

	# 1. Continental Silhouette & Shoreline Warp (only needed outside core interior r > 1100m)
	var eff_dist := dist
	var interior_mask := 1.0
	if dist > 1100.0:
		var warp_macro := _noise.get_noise_2d(x * 0.00055 + 120.0, z * 0.00055 - 180.0) * 480.0
		var warp_bays := _noise.get_noise_2d(x * 0.0014 - 250.0, z * 0.0014 + 210.0) * 160.0
		eff_dist = dist + warp_macro + warp_bays
		if eff_dist >= continent_radius + 185.0:
			return seabed_depth + _noise.get_noise_2d(x * 0.003 - 200.0, z * 0.003 + 200.0) * 3.0
		interior_mask = smoothstep(continent_radius - 160.0, continent_radius - 820.0, eff_dist)

	# 2. Spawn Meadow Amphitheater & Foreground Hills
	var valley_floor := valley_floor_height
	var inner_gentle := _noise.get_noise_2d(x * 0.010 + 15.0, z * 0.010 - 12.0) * 1.2
	var meadow_hills := 0.0
	if dist > 26.0:
		var fg_blend := smoothstep(26.0, 105.0, dist)
		var hill_n1 := _noise.get_noise_2d(x * 0.0052 + 40.0, z * 0.0052 - 30.0) * 0.5 + 0.5
		var hill_n2 := _noise.get_noise_2d(x * 0.0105 - 70.0, z * 0.0105 + 85.0) * 0.5 + 0.5
		meadow_hills = (hill_n1 * 18.0 + hill_n2 * 6.5) * fg_blend * hills_height_multiplier

	# 3. Regional Highland Biomes (spatial bounding checks skip inactive quadrants)
	var highland_features := 0.0
	if interior_mask > 0.001:
		# Northern Alpine Crown & Ridges (only active when z < 40m)
		if z < 40.0:
			var p1 := _sculpted_peak(x, z, -310.0, -520.0, 360.0, 142.0, 0.45)
			var p2 := _sculpted_peak(x, z, 340.0, -550.0, 380.0, 155.0, -0.42)
			var p3 := _sculpted_peak(x, z, 20.0, -1120.0, 520.0, 188.0, 0.12)
			var p4 := _sculpted_peak(x, z, -820.0, -920.0, 540.0, 168.0, 0.65)
			var p5 := _sculpted_peak(x, z, 860.0, -940.0, 550.0, 162.0, -0.60)
			var p6 := _sculpted_peak(x, z, -1350.0, -450.0, 480.0, 130.0, 0.95)
			var p7 := _sculpted_peak(x, z, 1380.0, -380.0, 490.0, 125.0, -0.85)
			highland_features += (p1 + p2 + p3 + p4 + p5 + p6 + p7) * mountain_height_multiplier

			if z < -280.0:
				var north_bias := smoothstep(-280.0, -850.0, z)
				var valley_carve := clampf(_noise.get_noise_2d(x * 0.0016 - 40.0, z * 0.0016 + 90.0) * 1.15 + 0.20, 0.0, 1.0)
				if valley_carve > 0.001:
					var r1 := _smooth_ridge(_noise.get_noise_2d(x * 0.0022 + 80.0, z * 0.0022 - 120.0))
					highland_features += pow(clampf(r1, 0.0, 1.0), 2.5) * 95.0 * north_bias * valley_carve * mountain_height_multiplier

		# Western Amber Mesas (only active when x < -120m and z > -500m)
		if x < -120.0 and z > -500.0:
			var west_bias := smoothstep(-120.0, -480.0, x) * smoothstep(-500.0, 900.0, z)
			var mesa_env := clampf(_noise.get_noise_2d(x * 0.0015 + 150.0, z * 0.0015 - 70.0) * 1.35 + 0.25, 0.0, 1.0)
			var mesa_raw := mesa_env * 3.2
			var mesa_tier := floorf(mesa_raw) + smoothstep(0.15, 0.85, mesa_raw - floorf(mesa_raw))
			highland_features += mesa_tier * 28.0 * west_bias * mesa_height_multiplier

		# Eastern Jade Downs (only active when x > 100m)
		if x > 100.0:
			var east_bias := smoothstep(100.0, 480.0, x)
			var downs_wave := (_noise.get_noise_2d(x * 0.0024 - 110.0, z * 0.0018 + 110.0) * 0.5 + 0.5)
			var east_ridge := 0.0
			if z > -100.0:
				east_ridge = pow(_smooth_ridge(_noise.get_noise_2d(x * 0.0018 + 200.0, z * 0.0018 - 140.0)), 2.2) * 48.0 * smoothstep(-100.0, 800.0, z)
			highland_features += (downs_wave * 36.0 + east_ridge) * east_bias * hills_height_multiplier

		# Southern Sunlit Highlands (only active when z > 200m and x > -600m)
		if z > 200.0 and x > -600.0:
			var south_bias := smoothstep(200.0, 700.0, z) * smoothstep(-600.0, 600.0, x)
			highland_features += pow(_smooth_ridge(_noise.get_noise_2d(x * 0.0020 - 60.0, z * 0.0020 + 180.0)), 2.0) * 52.0 * south_bias * hills_height_multiplier

		highland_features *= interior_mask

	var land_h := maxf(valley_floor + inner_gentle + meadow_hills * (0.35 + 0.65 * interior_mask) + highland_features, 20.0)
	if enable_cave:
		land_h = CaveSystem.apply_overworld_mountain_and_plaza(x, z, land_h, _noise)
	land_h = WorldLandmarks.apply_landmark_terrain_grading(x, z, land_h, get_webwood_center())

	# 4. Continental Coastline, Sweeping Golden Sandy Beach Shelf & Soft Coastal Dunes
	var coast_inner := continent_radius - 295.0
	var base_h := land_h
	if eff_dist > coast_inner:
		var coast_outer := continent_radius + 205.0
		var cf := clampf((coast_outer - eff_dist) / (coast_outer - coast_inner), 0.0, 1.0)
		var dev := cf - 0.42
		var cf_shelf := clampf(cf - 0.50 * dev * exp(-(dev * dev) / 0.0361), 0.0, 1.0)
		var smooth_f := cf_shelf * cf_shelf * (3.0 - 2.0 * cf_shelf)
		var sea_bed := seabed_depth + _noise.get_noise_2d(x * 0.003 - 200.0, z * 0.003 + 200.0) * 3.0
		base_h = maxf(lerpf(sea_bed, land_h, smooth_f), sea_bed)

		# Gentle wind-carved sand dunes on dry beach (0.8..7.2m, faded cleanly around harbor approach)
		var dune_mask := smoothstep(0.6, 2.0, base_h) * (1.0 - smoothstep(4.8, 7.6, base_h))
		if dune_mask > 0.001:
			var dock_clear := smoothstep(14.0, 36.0, Vector2(x - 655.0, z - 2430.0).length())
			var dune_n := _noise.get_noise_2d(x * 0.024 + 310.0, z * 0.024 - 270.0) * 0.5 + 0.5
			base_h += dune_n * 0.90 * dune_mask * dock_clear

	# 5. Seaside Village Terrace Grading (Slimebrook at (590, 2200), walking distance to southern coast)
	var vdx := x - 590.0
	var vdz := z - 2200.0
	if absf(vdx) < 136.0 and absf(vdz) < 124.0:
		var vn := sqrt((vdx * vdx) / (110.0 * 110.0) + (vdz * vdz) / (98.0 * 98.0))
		if vn < 1.25:
			var v_flat := 1.0 - smoothstep(0.75, 1.25, vn)
			var terrace_h := 20.0 + (1.0 - clampf(vn, 0.0, 1.0)) * 0.45
			base_h = lerpf(base_h, terrace_h, v_flat * 0.92)
	return base_h


func sample_coast_distance(x: float, z: float) -> float:
	var dist := Vector2(x, z).length()
	var eff_dist := dist
	if dist > 1100.0:
		var warp_macro := _noise.get_noise_2d(x * 0.00055 + 120.0, z * 0.00055 - 180.0) * 480.0
		var warp_bays := _noise.get_noise_2d(x * 0.0014 - 250.0, z * 0.0014 + 210.0) * 160.0
		eff_dist = dist + warp_macro + warp_bays
	return eff_dist - (continent_radius + 180.0)


func sample_normal(x: float, z: float) -> Vector3:
	var eps := 4.0
	var hL := sample_height(x - eps, z)
	var hR := sample_height(x + eps, z)
	var hD := sample_height(x, z - eps)
	var hU := sample_height(x, z + eps)
	return Vector3(hL - hR, 2.0 * eps, hD - hU).normalized()


## Maps normalized grid coordinate u in [-1, 1] to world coordinate in [-half, +half].
func _grid_to_world(u: float, half: float) -> float:
	var au := absf(u)
	var warped := 0.27 * au + 0.73 * au * au
	return signf(u) * warped * half


func _get_active_subdivisions() -> int:
	return editor_subdivisions if Engine.is_editor_hint() else terrain_subdivisions


func _ensure_grid_coords() -> void:
	var n := _get_active_subdivisions()
	var row_count := n + 1
	if _cached_grid_coords.size() == row_count:
		return
	var half := terrain_size * 0.5
	_cached_grid_coords.resize(row_count)
	for i in row_count:
		var u := (float(i) / float(n)) * 2.0 - 1.0
		_cached_grid_coords[i] = _grid_to_world(u, half)


func _find_grid_index(val: float) -> int:
	var n := _get_active_subdivisions()
	if val <= _cached_grid_coords[0]:
		return 0
	if val >= _cached_grid_coords[n]:
		return n - 1
	var lo := 0
	var hi := n
	while lo + 1 < hi:
		var mid := (lo + hi) >> 1
		if _cached_grid_coords[mid] <= val:
			lo = mid
		else:
			hi = mid
	return lo


const CAVE_SUBDIV_X_MIN := -140.0
const CAVE_SUBDIV_X_MAX := 5.0
const CAVE_SUBDIV_Z_MIN := -120.0
const CAVE_SUBDIV_Z_MAX := -30.0


func _get_cave_cell_subdiv(n: int) -> int:
	if n < 96:
		return 1
	return 8


func _is_cave_subdiv_cell(ix: int, iz: int, n: int) -> bool:
	if n < 96:
		return false
	if ix < 0 or iz < 0 or ix >= n or iz >= n:
		return false
	var x0 := _cached_grid_coords[ix]
	var x1 := _cached_grid_coords[ix + 1]
	var z0 := _cached_grid_coords[iz]
	var z1 := _cached_grid_coords[iz + 1]
	var in_cave_box := enable_cave and x1 > CAVE_SUBDIV_X_MIN and x0 < CAVE_SUBDIV_X_MAX and z1 > CAVE_SUBDIV_Z_MIN and z0 < CAVE_SUBDIV_Z_MAX
	var in_village_box := x1 > 455.0 and x0 < 735.0 and z1 > 2075.0 and z0 < 2520.0
	var in_landmark_box := WorldLandmarks.is_in_extra_subdiv_box(x0, x1, z0, z1)
	return in_cave_box or in_village_box or in_landmark_box


func _is_quad_in_any_cutout(v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3) -> bool:
	if enable_cave and CaveSystem.is_quad_in_portal_cutout(v00, v10, v01, v11):
		return true
	return WorldLandmarks.is_quad_in_extra_cutout(v00, v10, v01, v11)


func _sample_cave_subdiv_vertex_y(ix: int, iz: int, sx: int, sz: int, sub: int, n: int, x0: float, x1: float, z0: float, z1: float) -> float:
	var tx := float(sx) / float(sub)
	var tz := float(sz) / float(sub)
	if sx == 0 and not _is_cave_subdiv_cell(ix - 1, iz, n):
		return lerpf(sample_height(x0, z0), sample_height(x0, z1), tz)
	if sx == sub and not _is_cave_subdiv_cell(ix + 1, iz, n):
		return lerpf(sample_height(x1, z0), sample_height(x1, z1), tz)
	if sz == 0 and not _is_cave_subdiv_cell(ix, iz - 1, n):
		return lerpf(sample_height(x0, z0), sample_height(x1, z0), tx)
	if sz == sub and not _is_cave_subdiv_cell(ix, iz + 1, n):
		return lerpf(sample_height(x0, z1), sample_height(x1, z1), tx)
	var vx := lerpf(x0, x1, tx)
	var vz := lerpf(z0, z1, tz)
	return sample_height(vx, vz)


## Returns true if the active terrain sub-quad containing (x, z) is removed by the cave cutout.
func is_point_in_cave_cutout(x: float, z: float) -> bool:
	if not enable_cave:
		return false
	if x < CAVE_SUBDIV_X_MIN or x > CAVE_SUBDIV_X_MAX or z < CAVE_SUBDIV_Z_MIN or z > CAVE_SUBDIV_Z_MAX:
		return false
	_ensure_grid_coords()
	var n := _get_active_subdivisions()
	var ix := _find_grid_index(x)
	var iz := _find_grid_index(z)
	var x0 := _cached_grid_coords[ix]
	var x1 := _cached_grid_coords[ix + 1]
	var z0 := _cached_grid_coords[iz]
	var z1 := _cached_grid_coords[iz + 1]
	var sub := _get_cave_cell_subdiv(n) if _is_cave_subdiv_cell(ix, iz, n) else 1
	var u_cell := clampf((x - x0) / maxf(x1 - x0, 1e-6), 0.0, 1.0)
	var v_cell := clampf((z - z0) / maxf(z1 - z0, 1e-6), 0.0, 1.0)
	var sx := clampi(int(floor(u_cell * float(sub))), 0, sub - 1)
	var sz := clampi(int(floor(v_cell * float(sub))), 0, sub - 1)
	var sx0 := lerpf(x0, x1, float(sx) / float(sub))
	var sx1 := lerpf(x0, x1, float(sx + 1) / float(sub))
	var sz0 := lerpf(z0, z1, float(sz) / float(sub))
	var sz1 := lerpf(z0, z1, float(sz + 1) / float(sub))
	var v00 := Vector3(sx0, sample_height(sx0, sz0), sz0)
	var v10 := Vector3(sx1, sample_height(sx1, sz0), sz0)
	var v01 := Vector3(sx0, sample_height(sx0, sz1), sz1)
	var v11 := Vector3(sx1, sample_height(sx1, sz1), sz1)
	return CaveSystem.is_quad_in_portal_cutout(v00, v10, v01, v11)


## Returns exact height and surface normal on the terrain triangle mesh (Vector4(nx, ny, nz, height)).
## Matches both the visual ArrayMesh and physics ConcavePolygonShape3D with < 0.5mm precision.
func sample_surface_exact(x: float, z: float) -> Vector4:
	_ensure_grid_coords()
	var n := _get_active_subdivisions()
	var ix := _find_grid_index(x)
	var iz := _find_grid_index(z)

	var x0 := _cached_grid_coords[ix]
	var x1 := _cached_grid_coords[ix + 1]
	var z0 := _cached_grid_coords[iz]
	var z1 := _cached_grid_coords[iz + 1]

	var y00: float
	var y10: float
	var y01: float
	var y11: float
	var dx: float
	var dz: float
	var u: float
	var v: float

	if _is_cave_subdiv_cell(ix, iz, n):
		var sub := _get_cave_cell_subdiv(n)
		var u_cell := clampf((x - x0) / maxf(x1 - x0, 1e-6), 0.0, 1.0)
		var v_cell := clampf((z - z0) / maxf(z1 - z0, 1e-6), 0.0, 1.0)
		var sx := clampi(int(floor(u_cell * float(sub))), 0, sub - 1)
		var sz := clampi(int(floor(v_cell * float(sub))), 0, sub - 1)
		var sx0 := lerpf(x0, x1, float(sx) / float(sub))
		var sx1 := lerpf(x0, x1, float(sx + 1) / float(sub))
		var sz0 := lerpf(z0, z1, float(sz) / float(sub))
		var sz1 := lerpf(z0, z1, float(sz + 1) / float(sub))
		dx = sx1 - sx0
		dz = sz1 - sz0
		u = clampf((x - sx0) / maxf(dx, 1e-6), 0.0, 1.0)
		v = clampf((z - sz0) / maxf(dz, 1e-6), 0.0, 1.0)
		y00 = _sample_cave_subdiv_vertex_y(ix, iz, sx, sz, sub, n, x0, x1, z0, z1)
		y10 = _sample_cave_subdiv_vertex_y(ix, iz, sx + 1, sz, sub, n, x0, x1, z0, z1)
		y01 = _sample_cave_subdiv_vertex_y(ix, iz, sx, sz + 1, sub, n, x0, x1, z0, z1)
		y11 = _sample_cave_subdiv_vertex_y(ix, iz, sx + 1, sz + 1, sub, n, x0, x1, z0, z1)
	else:
		dx = x1 - x0
		dz = z1 - z0
		u = clampf((x - x0) / maxf(dx, 1e-6), 0.0, 1.0)
		v = clampf((z - z0) / maxf(dz, 1e-6), 0.0, 1.0)
		var row_c := n + 1
		if _cached_grid_heights_n == n and _cached_grid_heights.size() == row_c * row_c:
			var r0 := iz * row_c
			var r1 := r0 + row_c
			y00 = _cached_grid_heights[r0 + ix]
			y10 = _cached_grid_heights[r0 + ix + 1]
			y01 = _cached_grid_heights[r1 + ix]
			y11 = _cached_grid_heights[r1 + ix + 1]
		else:
			y00 = sample_height(x0, z0)
			y10 = sample_height(x1, z0)
			y01 = sample_height(x0, z1)
			y11 = sample_height(x1, z1)

	var h := 0.0
	var norm := Vector3.UP
	if u + v <= 1.0:
		# Triangle 1: (v00, v01, v10)
		h = y00 + u * (y10 - y00) + v * (y01 - y00)
		var nx := -dz * (y10 - y00)
		var ny := dz * dx
		var nz := -dx * (y01 - y00)
		norm = Vector3(nx, ny, nz).normalized()
	else:
		# Triangle 2: (v10, v01, v11)
		h = y11 + (1.0 - u) * (y01 - y11) + (1.0 - v) * (y10 - y11)
		var nx := dz * (y01 - y11)
		var ny := dx * dz
		var nz := -dx * (y11 - y10)
		norm = Vector3(nx, ny, nz).normalized()

	return Vector4(norm.x, norm.y, norm.z, h)


## Authoritative floor support query for SlimeMotor:
## Returns the subterranean SDF cave/ledge floor when the actor is inside the cave or portal/skylight cutout,
## and returns the overworld terrain surface everywhere else (including on top of the karst mountain roof).
func sample_support_floor(x: float, z: float, actor_foot_y: float) -> Vector4:
	var over_surf := sample_surface_exact(x, z)
	if WorldLandmarks.is_in_extra_cave(x, z, actor_foot_y, over_surf.w):
		var ec_surf := WorldLandmarks.sample_extra_cave_floor(x, z, actor_foot_y, over_surf.w)
		return Vector4(ec_surf.x, ec_surf.y, ec_surf.z, ec_surf.w - 0.30)
	if enable_cave:
		if CaveSystem.is_subterranean_or_cutout(x, z, actor_foot_y, over_surf.w):
			var c_surf := CaveSystem.sample_sdf_floor_below(x, z, actor_foot_y, over_surf.w)
			# Allow 0.30 m chord slack so CaveFloorBody triangle raycast is primary while guaranteeing zero fall-through
			return Vector4(c_surf.x, c_surf.y, c_surf.z, c_surf.w - 0.30)
		# Critical safeguard: when actor is subterranean (well below the mountain roof),
		# NEVER return over_surf.w (mountain top)! Return subterranean floor below or safe foot level.
		if actor_foot_y < over_surf.w - 2.5:
			var c_surf := CaveSystem.sample_sdf_floor_below(x, z, actor_foot_y, over_surf.w)
			if c_surf.w > -50.0 and c_surf.w <= actor_foot_y + 1.0:
				return Vector4(c_surf.x, c_surf.y, c_surf.z, c_surf.w - 0.30)
			return Vector4(0.0, 1.0, 0.0, actor_foot_y - 0.30)
	return over_surf


## Exact initial spawn floor height query for Slime._ready() (supports both inside-cave and overworld spawns).
func sample_spawn_floor_y(x: float, z: float, est_foot_y: float) -> float:
	var over_h := sample_height(x, z)
	if WorldLandmarks.is_in_extra_cave(x, z, est_foot_y, over_h):
		return WorldLandmarks.sample_extra_cave_floor(x, z, est_foot_y, over_h).w
	if enable_cave:
		if CaveSystem.is_subterranean_or_cutout(x, z, est_foot_y, over_h):
			return CaveSystem.sample_sdf_floor_below(x, z, est_foot_y, over_h).w
		if est_foot_y < over_h - 2.5:
			return CaveSystem.sample_sdf_floor_below(x, z, est_foot_y, over_h).w
	return over_h


func _build_terrain_mesh_cache_sig(n: int) -> String:
	return "tm_v8|%d|%.1f|%d|%.1f|%.1f|%.1f|%.1f|%.2f|%.2f|%.2f|%d|%s|%s|%s|%s" % [
		terrain_seed, terrain_size, n, continent_radius, flat_center_radius,
		valley_floor_height, seabed_depth, mountain_height_multiplier,
		hills_height_multiplier, mesa_height_multiplier, collision_stride,
		str(enable_cave), str(_webwood_layout.get("center", WorldLandmarks.SPIDER_FOREST_CENTER)),
		str(WorldLandmarks.RAT_WARREN_MOUTH), str(WorldLandmarks.SKEL_CAVE_MOUTH),
	]


func _sample_cutout_tuck(vx: float, vz: float, vy: float) -> float:
	if enable_cave and vx >= CAVE_SUBDIV_X_MIN and vx <= CAVE_SUBDIV_X_MAX and vz >= CAVE_SUBDIV_Z_MIN and vz <= CAVE_SUBDIV_Z_MAX:
		var cl_v := CaveLayout.to_local(Vector3(vx, 0.0, vz))
		var patch_t := minf(CaveSDF.eval_sky_patch_t(cl_v.x, cl_v.z), CaveSDF.eval_mouth_patch_t(cl_v.x, cl_v.z))
		if patch_t < 0.70:
			var tuck_w := clampf((0.70 - patch_t) / 0.06, 0.0, 1.0)
			tuck_w = tuck_w * tuck_w * (3.0 - 2.0 * tuck_w)
			return vy - tuck_w * 0.65
	return vy


func _build_terrain_mesh(terrain_node: MeshInstance3D) -> void:
	var n := _get_active_subdivisions()
	var half := terrain_size * 0.5
	_ensure_grid_coords()

	var tcache_path := ""
	if not Engine.is_editor_hint():
		tcache_path = "user://cache/terrain_mesh_%s.res" % _build_terrain_mesh_cache_sig(n).md5_text()
		if ResourceLoader.exists(tcache_path):
			var cached_pack := load(tcache_path) as ArrayMesh
			if cached_pack != null and int(cached_pack.get_meta("grid_n", -1)) == n:
				var c_heights: PackedFloat32Array = cached_pack.get_meta("heights", PackedFloat32Array())
				var c_coords: Array = cached_pack.get_meta("chunk_coords", [])
				var c_aabbs: Array = cached_pack.get_meta("chunk_aabbs", [])
				var c_col: ConcavePolygonShape3D = cached_pack.get_meta("col_shape", null) as ConcavePolygonShape3D
				if c_heights.size() == (n + 1) * (n + 1) and c_coords.size() == cached_pack.get_surface_count() and c_aabbs.size() == cached_pack.get_surface_count():
					_cached_grid_heights = c_heights
					_cached_grid_heights_n = n
					var old_c := terrain_node.get_node_or_null("TerrainChunks")
					if old_c != null:
						terrain_node.remove_child(old_c)
						old_c.free()
					var cr := Node3D.new()
					cr.name = "TerrainChunks"
					terrain_node.add_child(cr)
					var m_ov := terrain_node.material_override
					var sh_m := terrain_node.cast_shadow
					var gi_m := terrain_node.gi_mode
					for si in cached_pack.get_surface_count():
						var cm := ArrayMesh.new()
						cm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cached_pack.surface_get_arrays(si))
						var coord := c_coords[si] as Vector2i
						var cmi := MeshInstance3D.new()
						cmi.name = "TerrainChunk_%d_%d" % [coord.x, coord.y]
						cmi.mesh = cm
						cmi.material_override = m_ov
						cmi.cast_shadow = sh_m
						cmi.gi_mode = gi_m
						cmi.custom_aabb = c_aabbs[si] as AABB
						cr.add_child(cmi)
					terrain_node.mesh = null
					terrain_node.custom_aabb = AABB()
					var csn := terrain_node.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
					var sb := terrain_node.get_node_or_null("StaticBody3D") as StaticBody3D
					if sb != null:
						sb.collision_layer = 1
						sb.collision_mask = 0
						var old_sc := sb.get_node_or_null("CutoutSkirtCollider")
						if old_sc != null:
							old_sc.queue_free()
					if csn != null:
						if c_col != null:
							csn.disabled = false
							csn.shape = c_col
						elif Engine.is_editor_hint():
							if csn.shape == null or csn.shape is ConcavePolygonShape3D:
								var ph := BoxShape3D.new()
								ph.size = Vector3(terrain_size, 1.0, terrain_size)
								csn.shape = ph
							csn.disabled = true
						else:
							csn.shape = null
					return

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var row_count := n + 1
	verts.resize(row_count * row_count)
	normals.resize(row_count * row_count)
	uvs.resize(row_count * row_count)

	# Precompute 1D grid coordinates (symmetric for X and Z)
	_ensure_grid_coords()
	var grid_coords := _cached_grid_coords

	var inv_n := 1.0 / float(n)
	var heights := PackedFloat32Array()
	heights.resize(row_count * row_count)
	var idx := 0
	for iz in row_count:
		var v_coord := float(iz) * inv_n
		var z := grid_coords[iz]
		for ix in row_count:
			var u_coord := float(ix) * inv_n
			var x := grid_coords[ix]
			var h_val := sample_height(x, z)
			heights[idx] = h_val
			verts[idx] = Vector3(x, h_val, z)
			uvs[idx] = Vector2(u_coord, v_coord)
			idx += 1
	_cached_grid_heights = heights
	_cached_grid_heights_n = n

	# Compute smooth vertex normals directly from mesh grid neighbors
	for iz in row_count:
		var r_cur := iz * row_count
		var r_prev := maxi(iz - 1, 0) * row_count
		var r_next := mini(iz + 1, n) * row_count
		for ix in row_count:
			var ix_prev := maxi(ix - 1, 0)
			var ix_next := mini(ix + 1, n)
			var dx := verts[r_cur + ix_next] - verts[r_cur + ix_prev]
			var dz := verts[r_next + ix] - verts[r_prev + ix]
			normals[r_cur + ix] = dz.cross(dx).normalized()

	var old_chunks := terrain_node.get_node_or_null("TerrainChunks")
	if old_chunks != null:
		terrain_node.remove_child(old_chunks)
		old_chunks.free()

	var chunks_root := Node3D.new()
	chunks_root.name = "TerrainChunks"
	terrain_node.add_child(chunks_root)

	var cut_cave_portal := n >= 96
	var sub := _get_cave_cell_subdiv(n)
	var grid_chunks := 8
	var cell_step := maxi(1, int(ceil(float(n) / float(grid_chunks))))
	var vmap_local := PackedInt32Array()
	vmap_local.resize(verts.size())
	var vmap_stamp := PackedInt32Array()
	vmap_stamp.resize(verts.size())
	var cur_stamp := 0

	var mat_ov := terrain_node.material_override
	var shadow_mode := terrain_node.cast_shadow
	var gi := terrain_node.gi_mode
	var cache_pack := ArrayMesh.new() if not Engine.is_editor_hint() else null
	var cache_coords: Array[Vector2i] = []
	var cache_aabbs: Array[AABB] = []

	for cz in grid_chunks:
		var iz0 := cz * cell_step
		if iz0 >= n:
			break
		var iz1 := mini(iz0 + cell_step, n)
		for cx in grid_chunks:
			var ix0 := cx * cell_step
			if ix0 >= n:
				break
			var ix1 := mini(ix0 + cell_step, n)

			cur_stamp += 1
			var c_verts := PackedVector3Array()
			var c_normals := PackedVector3Array()
			var c_uvs := PackedVector2Array()
			var c_indices := PackedInt32Array()
			var min_pt := Vector3(INF, INF, INF)
			var max_pt := Vector3(-INF, -INF, -INF)

			for iz in range(iz0, iz1):
				var r0 := iz * row_count
				var r1 := (iz + 1) * row_count
				var z0 := grid_coords[iz]
				var z1 := grid_coords[iz + 1]
				var v0_uv := float(iz) * inv_n
				var v1_uv := float(iz + 1) * inv_n
				for ix in range(ix0, ix1):
					if _is_cave_subdiv_cell(ix, iz, n):
						var x0 := grid_coords[ix]
						var x1 := grid_coords[ix + 1]
						var u0_uv := float(ix) * inv_n
						var u1_uv := float(ix + 1) * inv_n
						var base_v := c_verts.size()
						var s_row := sub + 1
						var n00 := normals[r0 + ix]
						var n10 := normals[r0 + ix + 1]
						var n01 := normals[r1 + ix]
						var n11 := normals[r1 + ix + 1]
						var step_x := (x1 - x0) / float(sub)
						var step_z := (z1 - z0) / float(sub)
						var edge_l := _is_cave_subdiv_cell(ix - 1, iz, n)
						var edge_r := _is_cave_subdiv_cell(ix + 1, iz, n)
						var edge_u := _is_cave_subdiv_cell(ix, iz - 1, n)
						var edge_d := _is_cave_subdiv_cell(ix, iz + 1, n)
						for sz in s_row:
							var tz := float(sz) / float(sub)
							var vz := lerpf(z0, z1, tz)
							var v_uv := lerpf(v0_uv, v1_uv, tz)
							var n_left := n00.lerp(n01, tz)
							var n_right := n10.lerp(n11, tz)
							var on_z_seam := (sz == 0 and not edge_u) or (sz == sub and not edge_d)
							for sx in s_row:
								var tx := float(sx) / float(sub)
								var vx := lerpf(x0, x1, tx)
								var u_uv := lerpf(u0_uv, u1_uv, tx)
								var vy := _sample_cave_subdiv_vertex_y(ix, iz, sx, sz, sub, n, x0, x1, z0, z1)
								var on_x_seam := (sx == 0 and not edge_l) or (sx == sub and not edge_r)
								var nrm := n_left.lerp(n_right, tx).normalized()
								if not on_x_seam and not on_z_seam:
									vy = _sample_cutout_tuck(vx, vz, vy)
									var hL := _sample_cutout_tuck(vx - step_x, vz, sample_height(vx - step_x, vz))
									var hR := _sample_cutout_tuck(vx + step_x, vz, sample_height(vx + step_x, vz))
									var hD := _sample_cutout_tuck(vx, vz - step_z, sample_height(vx, vz - step_z))
									var hU := _sample_cutout_tuck(vx, vz + step_z, sample_height(vx, vz + step_z))
									nrm = Vector3((hL - hR) * (2.0 * step_z), 4.0 * step_x * step_z, (hD - hU) * (2.0 * step_x)).normalized()
								var vp := Vector3(vx, vy, vz)
								c_verts.append(vp)
								c_normals.append(nrm)
								c_uvs.append(Vector2(u_uv, v_uv))
								min_pt.x = minf(min_pt.x, vp.x)
								min_pt.y = minf(min_pt.y, vp.y)
								min_pt.z = minf(min_pt.z, vp.z)
								max_pt.x = maxf(max_pt.x, vp.x)
								max_pt.y = maxf(max_pt.y, vp.y)
								max_pt.z = maxf(max_pt.z, vp.z)
						var cut_flags := PackedByteArray()
						cut_flags.resize(sub * sub)
						if cut_cave_portal:
							for sz in sub:
								var sr0 := base_v + sz * s_row
								var sr1 := base_v + (sz + 1) * s_row
								for sx in sub:
									var si00 := sr0 + sx
									var si10 := si00 + 1
									var si01 := sr1 + sx
									var si11 := si01 + 1
									if _is_quad_in_any_cutout(c_verts[si00], c_verts[si10], c_verts[si01], c_verts[si11]):
										cut_flags[sz * sub + sx] = 1
						for sz in sub:
							var sr0 := base_v + sz * s_row
							var sr1 := base_v + (sz + 1) * s_row
							for sx in sub:
								if cut_flags[sz * sub + sx] != 0:
									continue
								var si00 := sr0 + sx
								var si10 := si00 + 1
								var si01 := sr1 + sx
								var si11 := si01 + 1
								c_indices.append(si00)
								c_indices.append(si10)
								c_indices.append(si01)
								c_indices.append(si10)
								c_indices.append(si11)
								c_indices.append(si01)
						continue

					var g00 := r0 + ix
					var g10 := g00 + 1
					var g01 := r1 + ix
					var g11 := g01 + 1
					if cut_cave_portal and _is_quad_in_any_cutout(verts[g00], verts[g10], verts[g01], verts[g11]):
						continue

					var l00: int
					if vmap_stamp[g00] == cur_stamp:
						l00 = vmap_local[g00]
					else:
						l00 = c_verts.size()
						var vp00 := verts[g00]
						c_verts.append(vp00); c_normals.append(normals[g00]); c_uvs.append(uvs[g00])
						vmap_stamp[g00] = cur_stamp; vmap_local[g00] = l00
						min_pt.x = minf(min_pt.x, vp00.x); min_pt.y = minf(min_pt.y, vp00.y); min_pt.z = minf(min_pt.z, vp00.z)
						max_pt.x = maxf(max_pt.x, vp00.x); max_pt.y = maxf(max_pt.y, vp00.y); max_pt.z = maxf(max_pt.z, vp00.z)
					var l10: int
					if vmap_stamp[g10] == cur_stamp:
						l10 = vmap_local[g10]
					else:
						l10 = c_verts.size()
						var vp10 := verts[g10]
						c_verts.append(vp10); c_normals.append(normals[g10]); c_uvs.append(uvs[g10])
						vmap_stamp[g10] = cur_stamp; vmap_local[g10] = l10
						min_pt.x = minf(min_pt.x, vp10.x); min_pt.y = minf(min_pt.y, vp10.y); min_pt.z = minf(min_pt.z, vp10.z)
						max_pt.x = maxf(max_pt.x, vp10.x); max_pt.y = maxf(max_pt.y, vp10.y); max_pt.z = maxf(max_pt.z, vp10.z)
					var l01: int
					if vmap_stamp[g01] == cur_stamp:
						l01 = vmap_local[g01]
					else:
						l01 = c_verts.size()
						var vp01 := verts[g01]
						c_verts.append(vp01); c_normals.append(normals[g01]); c_uvs.append(uvs[g01])
						vmap_stamp[g01] = cur_stamp; vmap_local[g01] = l01
						min_pt.x = minf(min_pt.x, vp01.x); min_pt.y = minf(min_pt.y, vp01.y); min_pt.z = minf(min_pt.z, vp01.z)
						max_pt.x = maxf(max_pt.x, vp01.x); max_pt.y = maxf(max_pt.y, vp01.y); max_pt.z = maxf(max_pt.z, vp01.z)
					var l11: int
					if vmap_stamp[g11] == cur_stamp:
						l11 = vmap_local[g11]
					else:
						l11 = c_verts.size()
						var vp11 := verts[g11]
						c_verts.append(vp11); c_normals.append(normals[g11]); c_uvs.append(uvs[g11])
						vmap_stamp[g11] = cur_stamp; vmap_local[g11] = l11
						min_pt.x = minf(min_pt.x, vp11.x); min_pt.y = minf(min_pt.y, vp11.y); min_pt.z = minf(min_pt.z, vp11.z)
						max_pt.x = maxf(max_pt.x, vp11.x); max_pt.y = maxf(max_pt.y, vp11.y); max_pt.z = maxf(max_pt.z, vp11.z)
					c_indices.append(l00)
					c_indices.append(l10)
					c_indices.append(l01)
					c_indices.append(l10)
					c_indices.append(l11)
					c_indices.append(l01)

			if c_indices.is_empty():
				continue

			var c_arrays := []
			c_arrays.resize(Mesh.ARRAY_MAX)
			c_arrays[Mesh.ARRAY_VERTEX] = c_verts
			c_arrays[Mesh.ARRAY_NORMAL] = c_normals
			c_arrays[Mesh.ARRAY_TEX_UV] = c_uvs
			c_arrays[Mesh.ARRAY_INDEX] = c_indices

			var c_mesh := ArrayMesh.new()
			c_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c_arrays)
			var chunk_aabb := c_mesh.get_aabb().grow(0.5)
			var chunk_mi := MeshInstance3D.new()
			chunk_mi.name = "TerrainChunk_%d_%d" % [cx, cz]
			chunk_mi.mesh = c_mesh
			chunk_mi.material_override = mat_ov
			chunk_mi.cast_shadow = shadow_mode
			chunk_mi.gi_mode = gi
			chunk_mi.custom_aabb = chunk_aabb
			chunks_root.add_child(chunk_mi)
			if cache_pack != null:
				cache_pack.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c_arrays)
				cache_coords.append(Vector2i(cx, cz))
				cache_aabbs.append(chunk_aabb)

	terrain_node.mesh = null
	terrain_node.custom_aabb = AABB()

	var col_shape_node := terrain_node.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	var static_body := terrain_node.get_node_or_null("StaticBody3D") as StaticBody3D
	if static_body != null:
		static_body.collision_layer = 1
		static_body.collision_mask = 0
	if static_body != null:
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		var old_skirt_col := static_body.get_node_or_null("CutoutSkirtCollider")
		if old_skirt_col != null:
			old_skirt_col.queue_free()
	var built_col: ConcavePolygonShape3D = null
	if not Engine.is_editor_hint() and (col_shape_node != null or cache_pack != null):
		built_col = _build_low_mem_collision_shape(verts, row_count, n)
	if col_shape_node != null:
		# In editor preview, skip building the 73,728-triangle concave collision mesh
		# to prevent Godot Editor physics server wireframe and BVH generation lag.
		if Engine.is_editor_hint():
			if col_shape_node.shape == null or col_shape_node.shape is ConcavePolygonShape3D:
				var ph := BoxShape3D.new()
				ph.size = Vector3(terrain_size, 1.0, terrain_size)
				col_shape_node.shape = ph
			col_shape_node.disabled = true
		else:
			col_shape_node.disabled = false
			col_shape_node.shape = built_col
	if cache_pack != null and not tcache_path.is_empty() and cache_pack.get_surface_count() > 0:
		var dir_abs := ProjectSettings.globalize_path(tcache_path.get_base_dir())
		DirAccess.make_dir_recursive_absolute(dir_abs)
		if DirAccess.dir_exists_absolute(dir_abs):
			cache_pack.set_meta("grid_n", n)
			cache_pack.set_meta("heights", heights)
			cache_pack.set_meta("chunk_coords", cache_coords)
			cache_pack.set_meta("chunk_aabbs", cache_aabbs)
			cache_pack.set_meta("col_shape", built_col)
			ResourceSaver.save(cache_pack, tcache_path, ResourceSaver.FLAG_COMPRESS)


func _build_low_mem_collision_shape(verts: PackedVector3Array, row_count: int, n: int) -> ConcavePolygonShape3D:
	var stride := collision_stride
	var faces := PackedVector3Array()
	var cull_floor := seabed_depth - 15.0
	var sub := _get_cave_cell_subdiv(n)
	for iz in range(0, n, stride):
		for ix in range(0, n, stride):
			var has_cave_subdiv := false
			for ciz in range(iz, mini(iz + stride, n)):
				for cix in range(ix, mini(ix + stride, n)):
					if _is_cave_subdiv_cell(cix, ciz, n):
						has_cave_subdiv = true
						break
				if has_cave_subdiv:
					break

			if has_cave_subdiv:
				for ciz in range(iz, mini(iz + stride, n)):
					var z0 := _cached_grid_coords[ciz]
					var z1 := _cached_grid_coords[ciz + 1]
					for cix in range(ix, mini(ix + stride, n)):
						var x0 := _cached_grid_coords[cix]
						var x1 := _cached_grid_coords[cix + 1]
						if _is_cave_subdiv_cell(cix, ciz, n):
							for sz in sub:
								var sz0 := lerpf(z0, z1, float(sz) / float(sub))
								var sz1 := lerpf(z0, z1, float(sz + 1) / float(sub))
								for sx in sub:
									var sx0 := lerpf(x0, x1, float(sx) / float(sub))
									var sx1 := lerpf(x0, x1, float(sx + 1) / float(sub))
									var sv00 := Vector3(sx0, _sample_cave_subdiv_vertex_y(cix, ciz, sx, sz, sub, n, x0, x1, z0, z1), sz0)
									var sv10 := Vector3(sx1, _sample_cave_subdiv_vertex_y(cix, ciz, sx + 1, sz, sub, n, x0, x1, z0, z1), sz0)
									var sv01 := Vector3(sx0, _sample_cave_subdiv_vertex_y(cix, ciz, sx, sz + 1, sub, n, x0, x1, z0, z1), sz1)
									var sv11 := Vector3(sx1, _sample_cave_subdiv_vertex_y(cix, ciz, sx + 1, sz + 1, sub, n, x0, x1, z0, z1), sz1)
									if n >= 96 and _is_quad_in_any_cutout(sv00, sv10, sv01, sv11):
										continue
									faces.append(sv00)
									faces.append(sv01)
									faces.append(sv10)
									faces.append(sv10)
									faces.append(sv01)
									faces.append(sv11)
						else:
							var cv00 := verts[ciz * row_count + cix]
							var cv10 := verts[ciz * row_count + cix + 1]
							var cv01 := verts[(ciz + 1) * row_count + cix]
							var cv11 := verts[(ciz + 1) * row_count + cix + 1]
							if n >= 96 and _is_quad_in_any_cutout(cv00, cv10, cv01, cv11):
								continue
							faces.append(cv00)
							faces.append(cv01)
							faces.append(cv10)
							faces.append(cv10)
							faces.append(cv01)
							faces.append(cv11)
				continue

			var r0 := iz * row_count
			var r1 := (iz + stride) * row_count
			var v00 := verts[r0 + ix]
			var v10 := verts[r0 + ix + stride]
			var v01 := verts[r1 + ix]
			var v11 := verts[r1 + ix + stride]
			# Cull abyss quads deeper than the active seabed (below seabed_depth - 15m)
			if v00.y < cull_floor and v10.y < cull_floor and v01.y < cull_floor and v11.y < cull_floor:
				continue
			if n >= 96 and _is_quad_in_any_cutout(v00, v10, v01, v11):
				continue
			# Counter-clockwise winding: face normals point UPWARD towards the sky
			faces.append(v00)
			faces.append(v01)
			faces.append(v10)
			faces.append(v10)
			faces.append(v01)
			faces.append(v11)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


## Finds the exact shoreline radius along angle theta where the continent meets sea level.
func _find_shoreline_radius(theta: float) -> float:
	var ct := cos(theta)
	var st := sin(theta)
	var r_lo := continent_radius - 850.0
	var r_hi := continent_radius + 850.0
	for _iter in 10:
		var r_mid := 0.5 * (r_lo + r_hi)
		var h := sample_height(ct * r_mid, st * r_mid)
		if h > sea_level + 0.15:
			r_lo = r_mid
		else:
			r_hi = r_mid
	return r_lo


func _build_water_mesh(water_node: MeshInstance3D) -> void:
	# Optimized seamless annular ocean mesh:
	# Starts safely inland beneath solid highland terrain (r >= 1480m where h >= +20m, well outside cave)
	# with dense coastal rings across 1480..3250m so steep peninsulas and deep coves never form cutoff chords.
	var rings := 16 if Engine.is_editor_hint() else maxi(water_rings, 32)
	var segments := 64 if Engine.is_editor_hint() else maxi(water_segments, 192)
	var r_out := ocean_outer_radius
	var r_in := maxf(1480.0, continent_radius - 1120.0)
	var r_coast_end := maxf(r_in + 600.0, continent_radius + 650.0)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var row_count := segments + 1
	verts.resize((rings + 1) * row_count)
	normals.resize((rings + 1) * row_count)
	uvs.resize((rings + 1) * row_count)
	indices.resize(rings * segments * 6)

	var cos_tab := PackedFloat32Array()
	var sin_tab := PackedFloat32Array()
	cos_tab.resize(row_count)
	sin_tab.resize(row_count)

	for iseg in range(segments):
		var theta := (float(iseg) / float(segments)) * TAU
		cos_tab[iseg] = cos(theta)
		sin_tab[iseg] = sin(theta)
	cos_tab[segments] = cos_tab[0]
	sin_tab[segments] = sin_tab[0]

	var up_norm := Vector3.UP
	var idx := 0
	for ir in range(rings + 1):
		var t := float(ir) / float(rings)
		var r: float
		if t <= 0.55:
			r = lerpf(r_in, r_coast_end, t / 0.55)
		else:
			var u := (t - 0.55) / 0.45
			r = lerpf(r_coast_end, r_out, u * u)
		for iseg in range(row_count):
			var x := cos_tab[iseg] * r
			var z := sin_tab[iseg] * r
			verts[idx] = Vector3(x, sea_level, z)
			normals[idx] = up_norm
			uvs[idx] = Vector2(x * 0.005, z * 0.005)
			idx += 1

	var coast_split_ring := clampi(int(round(float(rings) * 0.55)), 1, rings - 1)
	var near_indices := PackedInt32Array()
	var far_indices := PackedInt32Array()
	near_indices.resize(coast_split_ring * segments * 6)
	far_indices.resize((rings - coast_split_ring) * segments * 6)

	var nii := 0
	var fii := 0
	for ir in range(rings):
		var r0 := ir * row_count
		var r1 := (ir + 1) * row_count
		var is_far := ir >= coast_split_ring
		for iseg in range(segments):
			var i00 := r0 + iseg
			var i10 := i00 + 1
			var i01 := r1 + iseg
			var i11 := i01 + 1
			if is_far:
				far_indices[fii] = i00
				far_indices[fii + 1] = i01
				far_indices[fii + 2] = i10
				far_indices[fii + 3] = i10
				far_indices[fii + 4] = i01
				far_indices[fii + 5] = i11
				fii += 6
			else:
				near_indices[nii] = i00
				near_indices[nii + 1] = i01
				near_indices[nii + 2] = i10
				near_indices[nii + 3] = i10
				near_indices[nii + 4] = i01
				near_indices[nii + 5] = i11
				nii += 6

	var near_arr := []
	near_arr.resize(Mesh.ARRAY_MAX)
	near_arr[Mesh.ARRAY_VERTEX] = verts
	near_arr[Mesh.ARRAY_NORMAL] = normals
	near_arr[Mesh.ARRAY_TEX_UV] = uvs
	near_arr[Mesh.ARRAY_INDEX] = near_indices
	var near_mesh := ArrayMesh.new()
	near_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, near_arr)
	water_node.mesh = near_mesh
	water_node.position = Vector3.ZERO
	water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_node.custom_aabb = AABB(Vector3(-r_coast_end, -30.0, -r_coast_end), Vector3(r_coast_end * 2.0, 60.0, r_coast_end * 2.0))

	# Outer horizon rings without hint_depth_texture (skips depth buffer copy when inland)
	var far_arr := []
	far_arr.resize(Mesh.ARRAY_MAX)
	far_arr[Mesh.ARRAY_VERTEX] = verts
	far_arr[Mesh.ARRAY_NORMAL] = normals
	far_arr[Mesh.ARRAY_TEX_UV] = uvs
	far_arr[Mesh.ARRAY_INDEX] = far_indices
	var far_mesh := ArrayMesh.new()
	far_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, far_arr)
	var far_node := get_node_or_null("WaterFar") as MeshInstance3D
	if far_node == null:
		far_node = MeshInstance3D.new()
		far_node.name = "WaterFar"
		add_child(far_node)
	far_node.mesh = far_mesh
	far_node.position = Vector3.ZERO
	far_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far_node.custom_aabb = AABB(Vector3(-r_out, -30.0, -r_out), Vector3(r_out * 2.0, 60.0, r_out * 2.0))
	var far_shader := load("res://terrain/water_far.gdshader") as Shader
	if far_shader != null:
		var far_mat := far_node.material_override as ShaderMaterial
		if far_mat == null or far_mat.shader != far_shader:
			far_mat = ShaderMaterial.new()
			far_mat.shader = far_shader
		var near_mat := water_node.material_override as ShaderMaterial
		if near_mat != null:
			for pname in [&"deep_color", &"wave_speed", &"roughness_val"]:
				var pval = near_mat.get_shader_parameter(pname)
				if pval != null:
					far_mat.set_shader_parameter(pname, pval)
		far_node.material_override = far_mat


func _make_grass_tuft_mesh() -> ArrayMesh:
	# Lush stylized grass tuft with 8 intercrossing blades providing rich 360-degree volume
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var blade_count := 8
	var base_half_w := grass_blade_base_half_w
	# Alternating layered heights: canopy blades (0.88-0.96m) and dense undergrowth (0.64-0.78m)
	var heights := [0.92, 0.68, 0.96, 0.74, 0.88, 0.64, 0.94, 0.78]
	# Outward flares to produce a bushy, rounded tuft silhouette
	var leans := [0.24, 0.28, 0.16, 0.26, 0.22, 0.27, 0.15, 0.25]
	var offsets := [
		Vector3(0.00, 0.0, 0.04),
		Vector3(0.06, 0.0, -0.03),
		Vector3(-0.06, 0.0, -0.04),
		Vector3(0.03, 0.0, 0.06),
		Vector3(-0.04, 0.0, 0.03),
		Vector3(0.05, 0.0, 0.02),
		Vector3(-0.02, 0.0, -0.06),
		Vector3(0.02, 0.0, -0.05),
	]
	# Radially distributed around 360 degrees (~45 degrees apart with organic jitter)
	var angles := [0.08, 0.85, 1.64, 2.42, 3.21, 3.99, 4.78, 5.56]

	for b in blade_count:
		var rot := Basis(Vector3.UP, angles[b])
		var offset: Vector3 = offsets[b]
		var h: float = heights[b]
		var lean: float = leans[b]
		var base_vert := verts.size()
		var up_norm := Vector3.UP

		verts.append(offset + rot * Vector3(-base_half_w, 0.0, 0.0))
		verts.append(offset + rot * Vector3(base_half_w, 0.0, 0.0))
		verts.append(offset + rot * Vector3(0.0, h, lean))

		normals.append(up_norm)
		normals.append(up_norm)
		normals.append(up_norm)

		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(0.5, 1.0))

		indices.append(base_vert + 0)
		indices.append(base_vert + 1)
		indices.append(base_vert + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Exact height & surface normal on the terrain triangle mesh for grass placement.
## Anchors 100% of grass tufts directly to the triangle plane (< 0.5mm precision).
func _sample_valley_grass_surface(x: float, z: float) -> Vector4:
	return sample_surface_exact(x, z)


## Organic botanical grass density [0.0 .. 1.0] across macro glades, clumping thickets, and paths.
func sample_grass_density(x: float, z: float) -> float:
	if _noise == null:
		_setup_noise()
	# 1. Macro meadow wave (wavelength ~45m)
	var macro: float = _noise.get_noise_2d(x * 0.022 + 45.0, z * 0.022 - 60.0) * 0.5 + 0.5
	# 2. Medium clump clustering (wavelength ~15m)
	var clump: float = _noise.get_noise_2d(x * 0.065 - 30.0, z * 0.065 + 80.0) * 0.5 + 0.5
	# 3. Continuous lush density across all green areas (ranging 0.70 to 1.0)
	var base_density := 0.72 + macro * 0.16 + clump * 0.12
	# Walking trails smoothly carve clear paths through the grass below threshold
	var path_val: float = absf(_noise.get_noise_2d(x * 0.014 + 15.0, z * 0.014 - 25.0))
	var path_factor: float = smoothstep(0.015, 0.070, path_val)
	# Meadow clearings / glades
	var glade_val: float = _noise.get_noise_2d(x * 0.018 - 85.0, z * 0.018 + 110.0) * 0.5 + 0.5
	var glade_factor: float = smoothstep(0.16, 0.36, glade_val)
	return clampf(base_density * path_factor * glade_factor, 0.0, 1.0)


var _cached_grass_mesh: Mesh = null
var _cached_wispy_grass_mesh: Mesh = null
static var _cached_grass_data: Dictionary = {}
static var _cached_grass_count: int = -1
static var _cached_grass_center: Vector2 = Vector2(INF, INF)
var _grass_center: Vector2 = Vector2.ZERO
var _player_ref: Node3D = null
var _grass_mat: ShaderMaterial = null
var _grass_map_image: Image = null
var _grass_map_tex: Texture2D = null
var _grass_map_rgba: PackedByteArray = PackedByteArray()
var _grass_map_w: int = 0
var _grass_map_h: int = 0


func _build_terrain_occluder() -> void:
	var occ_inst := get_node_or_null("TerrainOccluder") as OccluderInstance3D
	if occ_inst == null:
		occ_inst = OccluderInstance3D.new()
		occ_inst.name = "TerrainOccluder"
		add_child(occ_inst)
	const OCC_N := 48
	var half := terrain_size * 0.5
	var step := terrain_size / float(OCC_N)
	var row := OCC_N + 1
	var verts := PackedVector3Array()
	verts.resize(row * row)
	for iz in range(row):
		var vz := -half + float(iz) * step
		for ix in range(row):
			var vx := -half + float(ix) * step
			# Conservative lower-bound height so coarse occluder triangles never poke above terrain valleys
			var hs := step * 0.5
			var vy := minf(
				minf(sample_height(vx, vz), sample_height(vx - hs, vz)),
				minf(sample_height(vx + hs, vz), minf(sample_height(vx, vz - hs), sample_height(vx, vz + hs)))
			) - 8.0
			verts[iz * row + ix] = Vector3(vx, vy, vz)
	var indices := PackedInt32Array()
	indices.resize(OCC_N * OCC_N * 6)
	var ii := 0
	for iz in range(OCC_N):
		var z0 := -half + float(iz) * step
		var z1 := z0 + step
		for ix in range(OCC_N):
			var x0 := -half + float(ix) * step
			var x1 := x0 + step
			if enable_cave and (is_point_in_cave_cutout(x0, z0) or is_point_in_cave_cutout(x1, z0) or is_point_in_cave_cutout(x0, z1) or is_point_in_cave_cutout(x1, z1)):
				continue
			var i00 := iz * row + ix
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			indices[ii] = i00; indices[ii + 1] = i10; indices[ii + 2] = i01
			indices[ii + 3] = i10; indices[ii + 4] = i11; indices[ii + 5] = i01
			ii += 6
	indices.resize(ii)
	var arr_occ := ArrayOccluder3D.new()
	arr_occ.set_arrays(verts, indices)
	occ_inst.occluder = arr_occ


var _trail_map_tex: ImageTexture = null
var _trail_map_sig: String = ""


static func _seg_dist_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var h := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * h)


func _sync_trail_map_to_material(tmat: ShaderMaterial) -> void:
	if tmat == null:
		return
	var w_c: Vector2 = _webwood_layout.get("center", WorldLandmarks.SPIDER_FOREST_CENTER)
	var w_s: Vector2 = _webwood_layout.get("trail_start", WorldLandmarks.SPIDER_TRAIL_START)
	var w_b: Vector2 = _webwood_layout.get("trail_bend", WorldLandmarks.SPIDER_TRAIL_BEND)
	var sig := "%d|%.1f,%.1f|%.1f,%.1f|%.1f,%.1f" % [terrain_seed, w_c.x, w_c.y, w_s.x, w_s.y, w_b.x, w_b.y]
	if _trail_map_tex == null or _trail_map_sig != sig:
		_trail_map_sig = sig
		const TRES := 512
		var segs: Array[Array] = [
			[Vector2(-6.0, -17.0), Vector2(-16.0, -28.0)],
			[Vector2(-6.0, 15.0), Vector2(-105.0, 140.0)],
			[Vector2(-105.0, 140.0), Vector2(-220.0, 260.0)],
			[Vector2(-220.0, 260.0), w_s],
			[w_s, w_b],
			[w_b, w_c],
			[Vector2(12.0, 15.0), Vector2(215.0, 185.0)],
			[Vector2(215.0, 185.0), Vector2(375.0, 442.0)],
			[Vector2(375.0, 442.0), Vector2(460.0, 442.0)],
			[Vector2(460.0, 442.0), Vector2(460.0, 490.0)],
			[Vector2(460.0, 442.0), Vector2(460.0, 434.0)],
			[w_s, Vector2(-530.0, 316.0)],
			[Vector2(-530.0, 316.0), Vector2(-820.0, 344.0)],
			[Vector2(-820.0, 344.0), Vector2(-820.0, 326.0)],
			[Vector2(18.0, -14.0), Vector2(150.0, -125.0)],
			[Vector2(150.0, -125.0), Vector2(286.0, -218.0)],
			[Vector2(286.0, -218.0), Vector2(290.0, -240.0)],
		]
		var n_macro := FastNoiseLite.new()
		n_macro.seed = terrain_seed + 313
		n_macro.frequency = 0.025
		var n_med := FastNoiseLite.new()
		n_med.seed = terrain_seed + 617
		n_med.frequency = 0.25
		var rg := PackedByteArray()
		rg.resize(TRES * TRES * 2)
		var bx := grass_map_bounds.position.x
		var bz := grass_map_bounds.position.y
		var bw := grass_map_bounds.size.x
		var bh := grass_map_bounds.size.y
		for py in range(TRES):
			var wz := bz + (float(py) / float(TRES - 1)) * bh
			for px in range(TRES):
				var wx := bx + (float(px) / float(TRES - 1)) * bw
				var p := Vector2(wx, wz)
				var d_path := 1e6
				for s in segs:
					d_path = minf(d_path, _seg_dist_2d(p, s[0] as Vector2, s[1] as Vector2))
				var o := (py * TRES + px) * 2
				if d_path < 8.5:
					var wobble := n_macro.get_noise_2d(wx, wz) * 4.0 + n_med.get_noise_2d(wx, wz) * 1.6
					var pd := d_path + wobble * 0.14
					var tmask := 1.0 - smoothstep(2.2, 4.4, pd)
					var rcore := 1.0 - smoothstep(0.6, 2.2, pd)
					rg[o] = int(round(clampf(tmask, 0.0, 1.0) * 255.0))
					rg[o + 1] = int(round(clampf(rcore, 0.0, 1.0) * 255.0))
				else:
					rg[o] = 0
					rg[o + 1] = 0
		var img := Image.create_from_data(TRES, TRES, false, Image.FORMAT_RG8, rg)
		_trail_map_tex = ImageTexture.create_from_image(img)
	tmat.set_shader_parameter(&"u_trail_map", _trail_map_tex)
	tmat.set_shader_parameter(&"u_trail_map_bounds", Vector4(grass_map_bounds.position.x, grass_map_bounds.position.y, grass_map_bounds.size.x, grass_map_bounds.size.y))
	tmat.set_shader_parameter(&"u_has_trail_map", 1.0)


func _is_grass_static_excluded(x: float, z: float) -> bool:
	if enable_cave and (CaveSystem.is_in_portal_scatter_exclusion(x, z, true) or is_point_in_cave_cutout(x, z)):
		return true
	if VillageBuilder.is_in_village_exclusion(x, z, true):
		return true
	if WorldLandmarks.is_in_landmark_exclusion(x, z, true):
		return true
	return false


func _ensure_grass_map() -> void:
	if _grass_map_tex != null and not _grass_map_rgba.is_empty():
		return
	if grass_map_override != null:
		_grass_map_tex = grass_map_override
		var img := grass_map_override.get_image()
		if img != null:
			_grass_map_image = img.duplicate() as Image
			_grass_map_image.convert(Image.FORMAT_RGBA8)
			_grass_map_w = _grass_map_image.get_width()
			_grass_map_h = _grass_map_image.get_height()
			_grass_map_rgba = _grass_map_image.get_data()
			return

	const RES := 512
	var n_d := FastNoiseLite.new()
	n_d.seed = terrain_seed + 401
	n_d.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_d.fractal_octaves = 3
	n_d.frequency = 0.15

	var n_h := FastNoiseLite.new()
	n_h.seed = terrain_seed + 709
	n_h.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_h.fractal_octaves = 3
	n_h.frequency = 0.11

	var n_hd := FastNoiseLite.new()
	n_hd.seed = terrain_seed + 911
	n_hd.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_hd.fractal_octaves = 2
	n_hd.frequency = 0.26

	var img_d := n_d.get_image(RES, RES, false, false, false)
	var img_h := n_h.get_image(RES, RES, false, false, false)
	var img_hd := n_hd.get_image(RES, RES, false, false, false)
	img_d.convert(Image.FORMAT_L8)
	img_h.convert(Image.FORMAT_L8)
	img_hd.convert(Image.FORMAT_L8)

	var db := img_d.get_data()
	var hb := img_h.get_data()
	var hdb := img_hd.get_data()
	var total := RES * RES
	var rgba := PackedByteArray()
	rgba.resize(total * 4)
	for i in range(total):
		var d_raw := float(db[i]) / 255.0
		var h_raw := float(hb[i]) / 255.0 + (float(hdb[i]) / 255.0 - 0.5) * 0.34
		var dens := clampf(0.45 + smoothstep(0.20, 0.78, d_raw) * 0.55, 0.0, 1.0)
		var h_val := clampf(smoothstep(0.24, 0.76, clampf(h_raw, 0.0, 1.0)), 0.0, 1.0)
		var t_val := clampf(h_val * 0.74 + dens * 0.26, 0.0, 1.0)
		var o := i * 4
		rgba[o] = int(round(dens * 255.0))
		rgba[o + 1] = int(round(h_val * 255.0))
		rgba[o + 2] = int(round(t_val * 255.0))
		rgba[o + 3] = 255

	# Bake 3-state static exclusion mask into alpha (0=excluded, 128=boundary, 255=clear)
	var bx := grass_map_bounds.position.x
	var bz := grass_map_bounds.position.y
	var bw := grass_map_bounds.size.x
	var bh := grass_map_bounds.size.y
	var inv_res := 1.0 / float(RES - 1)
	for py in range(RES):
		var wz := bz + float(py) * inv_res * bh
		for px in range(RES):
			var wx := bx + float(px) * inv_res * bw
			var c_ex := _is_grass_static_excluded(wx, wz)
			var n_ex := _is_grass_static_excluded(wx + 10.0, wz) or _is_grass_static_excluded(wx - 10.0, wz) or _is_grass_static_excluded(wx, wz + 10.0) or _is_grass_static_excluded(wx, wz - 10.0)
			var n_cl := (not _is_grass_static_excluded(wx + 10.0, wz)) or (not _is_grass_static_excluded(wx - 10.0, wz)) or (not _is_grass_static_excluded(wx, wz + 10.0)) or (not _is_grass_static_excluded(wx, wz - 10.0))
			var alpha_v := 128
			if c_ex and not n_cl:
				alpha_v = 0
			elif not c_ex and not n_ex:
				alpha_v = 255
			rgba[(py * RES + px) * 4 + 3] = alpha_v

	_grass_map_w = RES
	_grass_map_h = RES
	_grass_map_rgba = rgba
	_grass_map_image = Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, rgba)
	_grass_map_tex = ImageTexture.create_from_image(_grass_map_image)


func get_grass_map_texture() -> Texture2D:
	_ensure_grass_map()
	return _grass_map_tex


## Bilinearly samples the terrain Grass Map at world (x, z):
## returns Vector3(density [0..1], height_multiplier [min..max], species_bias [0..1]).
func sample_grass_map(x: float, z: float) -> Vector3:
	_ensure_grass_map()
	if _grass_map_rgba.is_empty() or _grass_map_w <= 1 or _grass_map_h <= 1:
		return Vector3(1.0, 1.0, 0.35)
	var u := clampf((x - grass_map_bounds.position.x) / maxf(1.0, grass_map_bounds.size.x), 0.0, 1.0)
	var v := clampf((z - grass_map_bounds.position.y) / maxf(1.0, grass_map_bounds.size.y), 0.0, 1.0)
	var fx := u * float(_grass_map_w - 1)
	var fy := v * float(_grass_map_h - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, _grass_map_w - 1)
	var y1 := mini(y0 + 1, _grass_map_h - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)

	var i00 := (y0 * _grass_map_w + x0) * 4
	var i10 := (y0 * _grass_map_w + x1) * 4
	var i01 := (y1 * _grass_map_w + x0) * 4
	var i11 := (y1 * _grass_map_w + x1) * 4

	var inv255 := 1.0 / 255.0
	var r0 := lerpf(float(_grass_map_rgba[i00]), float(_grass_map_rgba[i10]), tx)
	var r1 := lerpf(float(_grass_map_rgba[i01]), float(_grass_map_rgba[i11]), tx)
	var dens := lerpf(r0, r1, ty) * inv255

	var g0 := lerpf(float(_grass_map_rgba[i00 + 1]), float(_grass_map_rgba[i10 + 1]), tx)
	var g1 := lerpf(float(_grass_map_rgba[i01 + 1]), float(_grass_map_rgba[i11 + 1]), tx)
	var h_norm := lerpf(g0, g1, ty) * inv255

	var b0 := lerpf(float(_grass_map_rgba[i00 + 2]), float(_grass_map_rgba[i10 + 2]), tx)
	var b1 := lerpf(float(_grass_map_rgba[i01 + 2]), float(_grass_map_rgba[i11 + 2]), tx)
	var type_bias := lerpf(b0, b1, ty) * inv255

	return Vector3(dens, lerpf(grass_height_map_min, grass_height_map_max, h_norm), type_bias)


## Paint a circular brush stroke onto the terrain grass map (density/height_norm/type_bias in [0..1]) and refresh GPU textures.
func paint_grass_map(world_xz: Vector2, radius: float, density: float, height_norm: float, type_bias: float, opacity: float = 1.0) -> void:
	_ensure_grass_map()
	if _grass_map_image == null or _grass_map_w <= 1 or _grass_map_h <= 1:
		return
	var uv := Vector2(
		(world_xz.x - grass_map_bounds.position.x) / maxf(1.0, grass_map_bounds.size.x),
		(world_xz.y - grass_map_bounds.position.y) / maxf(1.0, grass_map_bounds.size.y)
	)
	var rx := int(ceil((radius / maxf(1.0, grass_map_bounds.size.x)) * float(_grass_map_w)))
	var ry := int(ceil((radius / maxf(1.0, grass_map_bounds.size.y)) * float(_grass_map_h)))
	var cx := int(round(uv.x * float(_grass_map_w - 1)))
	var cy := int(round(uv.y * float(_grass_map_h - 1)))
	var rad_sq := radius * radius
	var dens_c := clampf(density, 0.0, 1.0)
	var h_c := clampf(height_norm, 0.0, 1.0)
	var t_c := clampf(type_bias, 0.0, 1.0)
	var op := clampf(opacity, 0.0, 1.0)
	for py in range(maxi(0, cy - ry), mini(_grass_map_h, cy + ry + 1)):
		var wz := grass_map_bounds.position.y + (float(py) / float(_grass_map_h - 1)) * grass_map_bounds.size.y
		for px in range(maxi(0, cx - rx), mini(_grass_map_w, cx + rx + 1)):
			var wx := grass_map_bounds.position.x + (float(px) / float(_grass_map_w - 1)) * grass_map_bounds.size.x
			var d_sq := Vector2(wx - world_xz.x, wz - world_xz.y).length_squared()
			if d_sq > rad_sq:
				continue
			var falloff := (1.0 - smoothstep(0.35, 1.0, sqrt(d_sq) / maxf(0.01, radius))) * op
			var o := (py * _grass_map_w + px) * 4
			var cr := float(_grass_map_rgba[o]) / 255.0
			var cg := float(_grass_map_rgba[o + 1]) / 255.0
			var cb := float(_grass_map_rgba[o + 2]) / 255.0
			_grass_map_rgba[o] = int(round(lerpf(cr, dens_c, falloff) * 255.0))
			_grass_map_rgba[o + 1] = int(round(lerpf(cg, h_c, falloff) * 255.0))
			_grass_map_rgba[o + 2] = int(round(lerpf(cb, t_c, falloff) * 255.0))
	_grass_map_image = Image.create_from_data(_grass_map_w, _grass_map_h, false, Image.FORMAT_RGBA8, _grass_map_rgba)
	if _grass_map_tex is ImageTexture:
		(_grass_map_tex as ImageTexture).update(_grass_map_image)
	else:
		_grass_map_tex = ImageTexture.create_from_image(_grass_map_image)
	_sync_grass_map_to_materials()


func _sync_grass_map_to_materials() -> void:
	_ensure_grass_map()
	var bounds_v := Vector4(grass_map_bounds.position.x, grass_map_bounds.position.y, grass_map_bounds.size.x, grass_map_bounds.size.y)
	for gm: ShaderMaterial in [_grass_mat, _grass_far_mat, _grass_wispy_mat, _grass_wispy_far_mat]:
		if gm != null:
			gm.set_shader_parameter(&"grass_map", _grass_map_tex)
			gm.set_shader_parameter(&"grass_map_bounds", bounds_v)


func _get_grass_mesh() -> Mesh:
	if _cached_grass_mesh == null:
		var sc: PackedScene = load("res://assets/nature/Grass_Common_Tall.gltf")
		if sc == null:
			sc = load("res://assets/nature/Grass_Common_Short.gltf")
		if sc != null:
			var inst: Node = sc.instantiate()
			for c in inst.get_children():
				if c is MeshInstance3D and c.mesh != null:
					_cached_grass_mesh = c.mesh.duplicate()
					break
			inst.free()
	if _cached_grass_mesh != null:
		return _cached_grass_mesh
	return _make_grass_tuft_mesh()


func _get_wispy_grass_mesh() -> Mesh:
	if _cached_wispy_grass_mesh == null:
		var sc: PackedScene = load("res://assets/nature/Grass_Wispy_Tall.gltf")
		if sc == null:
			sc = load("res://assets/nature/Grass_Wispy_Short.gltf")
		if sc != null:
			var inst: Node = sc.instantiate()
			for c in inst.get_children():
				if c is MeshInstance3D and c.mesh != null:
					_cached_wispy_grass_mesh = c.mesh.duplicate()
					break
			inst.free()
	if _cached_wispy_grass_mesh != null:
		return _cached_wispy_grass_mesh
	return _get_grass_mesh()


const GRASS_CACHE_PREFIX := "user://cache/grass_"

func _grass_cache_path(target_total: int, cache_sig: String) -> String:
	return "%s%d_%s.dat" % [GRASS_CACHE_PREFIX, target_total, cache_sig.md5_text().left(12)]

static var _cached_regional_grass_data: Dictionary = {}
static var _cached_regional_grass_sig: String = ""
var _active_grass_vis_end: float = -1.0


func _get_effective_grass_vis_end() -> float:
	return _active_grass_vis_end if _active_grass_vis_end > 0.0 else grass_visibility_end


func _compute_dynamic_grass_radius(raw_cap: int) -> float:
	var spawn_r := grass_spawn_radius
	if Engine.is_editor_hint():
		spawn_r = minf(spawn_r, 18.0)
	return minf(spawn_r, sqrt(maxf(float(raw_cap), 400.0) * grass_spacing * grass_spacing / PI) * 1.18)


func _build_regional_grass_cache_sig() -> String:
	var rs := regional_scatter if regional_scatter != null else RegionalScatterProfile.new()
	var lm_md5 := FileAccess.get_md5("res://scripts/world_landmarks.gd").left(8)
	var vb_md5 := FileAccess.get_md5("res://terrain/village_builder.gd").left(8)
	return "reg_v1|%s|%s|%d|%.1f|%d|%.1f|%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%.1f,%d,%.1f,%d,%.1f,%d,%.1f,%d" % [
		lm_md5, vb_md5,
		terrain_seed, terrain_size, terrain_subdivisions, continent_radius, str(enable_cave),
		grass_spacing, grass_clearing_threshold,
		min_grass_normal_y, grass_slope_gravity_blend, grass_height_map_min, grass_height_map_max,
		str(_webwood_layout),
		rs.wolf_grass_radius, rs.wolf_grass_count, rs.rat_grass_radius, rs.rat_grass_count,
		rs.skel_grass_radius, rs.skel_grass_count, rs.village_grass_radius, rs.village_grass_count,
	]


func _build_grass_cache_sig(center: Vector2, target_total: int) -> String:
	var rs := regional_scatter if regional_scatter != null else RegionalScatterProfile.new()
	var lm_md5 := FileAccess.get_md5("res://scripts/world_landmarks.gd").left(8)
	var vb_md5 := FileAccess.get_md5("res://terrain/village_builder.gd").left(8)
	return "v3_road_clear|%s|%s|%d|%.1f|%d|%.1f|%s|%.1f,%.1f|%d|%.1f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%.1f,%d,%.1f,%d,%.1f,%d,%.1f,%d" % [
		lm_md5, vb_md5,
		terrain_seed, terrain_size, terrain_subdivisions, continent_radius, str(enable_cave),
		center.x, center.y, target_total, grass_spawn_radius, grass_spacing, grass_clearing_threshold,
		min_grass_normal_y, grass_slope_gravity_blend, grass_height_map_min, grass_height_map_max,
		str(_webwood_layout),
		rs.wolf_grass_radius, rs.wolf_grass_count, rs.rat_grass_radius, rs.rat_grass_count,
		rs.skel_grass_radius, rs.skel_grass_count, rs.village_grass_radius, rs.village_grass_count,
	]


func _get_regional_pass_defs() -> Array:
	var pass_defs: Array = []
	if Engine.is_editor_hint():
		return pass_defs
	if enable_cave:
		var mouth_c := Vector2(CaveLayout.ORIGIN.x, CaveLayout.ORIGIN.z)
		var sky_w := CaveLayout.to_world(CaveLayout.SKYLIGHT["c"])
		var sky_c := Vector2(sky_w.x, sky_w.z)
		pass_defs.append([mouth_c, 72.0, 8000, -1.0])
		pass_defs.append([sky_c, 64.0, 5600, -1.0])
	pass_defs.append([Vector2(0.0, 10.0), 58.0, 5800, -1.0])
	var web_c: Vector2 = _webwood_layout.get("center", WorldLandmarks.SPIDER_FOREST_CENTER)
	var web_gr_r: float = float(_webwood_layout.get("grass_radius", 145.0))
	var web_gr_n: int = int(_webwood_layout.get("grass_count", 14500))
	pass_defs.append([web_c, web_gr_r, web_gr_n, -1.0])
	var rs := regional_scatter if regional_scatter != null else RegionalScatterProfile.new()
	pass_defs.append([WorldLandmarks.WOLF_CRAG_CENTER, rs.wolf_grass_radius, rs.wolf_grass_count, -1.0])
	pass_defs.append([Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 44.0), rs.rat_grass_radius, rs.rat_grass_count, -1.0])
	pass_defs.append([WorldLandmarks.SKEL_CAVE_MOUTH, rs.skel_grass_radius, rs.skel_grass_count, -1.0])
	pass_defs.append([Vector2(590.0, 2200.0), rs.village_grass_radius * 1.35, rs.village_grass_count, -1.0])
	return pass_defs


func _build_grass_pass_transforms(pass_defs: Array, seed_offset: int, skip_center: Vector2 = Vector2.ZERO, skip_radius: float = -1.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + seed_offset
	var common_xforms: Array[Transform3D] = []
	var wispy_xforms: Array[Transform3D] = []
	var spacing := grass_spacing

	for pass_i in pass_defs.size():
		var pc: Vector2 = pass_defs[pass_i][0]
		var raw_cap := int(pass_defs[pass_i][2])
		var pass_r := float(pass_defs[pass_i][1])
		if raw_cap <= 0 or pass_r <= 0.0:
			continue
		var max_rings := int(ceil(pass_r / spacing))
		var pass_cap := common_xforms.size() + wispy_xforms.size() + raw_cap

		for ring in range(max_rings + 1):
			if (common_xforms.size() + wispy_xforms.size()) >= pass_cap:
				break
			var r_dist := float(ring) * spacing
			var outer_keep := 1.0
			var feather_start := pass_r * 0.62
			if r_dist > feather_start:
				outer_keep = clampf(1.0 - smoothstep(feather_start, pass_r, r_dist), 0.0, 1.0)
			var count := 1 if ring == 0 else int(round(TAU * float(ring)))
			var angle_step := TAU / float(count)
			var ring_phase := rng.randf() * TAU

			for i in count:
				if (common_xforms.size() + wispy_xforms.size()) >= pass_cap:
					break
				if outer_keep < 0.999 and rng.randf() > outer_keep:
					continue
				var angle := float(i) * angle_step + ring_phase
				var r_jitter := r_dist + rng.randf_range(-0.25 * spacing, 0.25 * spacing)
				var a_jitter := angle + rng.randf_range(-0.15, 0.15) * angle_step

				var x := r_jitter * cos(a_jitter) + pc.x
				var z := r_jitter * sin(a_jitter) + pc.y

				if skip_radius > 0.0 and Vector2(x, z).distance_to(skip_center) <= skip_radius:
					continue
				if not _grass_map_rgba.is_empty() and _grass_map_w > 1 and _grass_map_h > 1:
					var gu := clampf((x - grass_map_bounds.position.x) / maxf(1.0, grass_map_bounds.size.x), 0.0, 1.0)
					var gv := clampf((z - grass_map_bounds.position.y) / maxf(1.0, grass_map_bounds.size.y), 0.0, 1.0)
					var gpx := clampi(int(round(gu * float(_grass_map_w - 1))), 0, _grass_map_w - 1)
					var gpy := clampi(int(round(gv * float(_grass_map_h - 1))), 0, _grass_map_h - 1)
					var excl_a := _grass_map_rgba[(gpy * _grass_map_w + gpx) * 4 + 3]
					if excl_a == 0:
						continue
					if excl_a < 255 and _is_grass_static_excluded(x, z):
						continue
				elif _is_grass_static_excluded(x, z):
					continue

				# 1. Botanical Meadow Density + Terrain Grass Map (glades, trails, height zones & species bias)
				var gm := sample_grass_map(x, z)
				var density := clampf(sample_grass_density(x, z) * lerpf(0.76, 1.12, gm.x), 0.0, 1.0)
				if density < grass_clearing_threshold:
					continue

				# 2. Exact terrain surface query (fast barycentric interpolation on cached terrain grid)
				var surf := sample_surface_exact(x, z)
				var y := surf.w
				var n := Vector3(surf.x, surf.y, surf.z)

				# 3. Slope Mask: steep cliffs (> 42°) remain clean rock
				if n.y < min_grass_normal_y:
					continue

				# 4. Elevation Mask: green meadow begins cleanly above coastal golden beach dunes (5.8m to 95.0m),
				# and skip submerged grass blades beneath the Sunken Rat Swamp Lagoon
				if y < 5.8 or y > 95.0:
					continue
				if z > WorldLandmarks.RAT_WARREN_MOUTH.y and z < WorldLandmarks.RAT_WARREN_MOUTH.y + 141.0 and absf(x - WorldLandmarks.RAT_WARREN_MOUTH.x) < 95.0 and y < WorldLandmarks.RAT_SWAMP_WATER_Y - 0.04:
					continue

				# 5. Species allocation driven by Grass Map B channel (short lawns=Common, wild swells=Wispy plumes)
				var is_wispy := rng.randf() < lerpf(0.18, 0.72, gm.z)

				# 6. Gravity-Biased Orientation (Natural Phototropism)
				var up_vec := (Vector3.UP * (1.0 - grass_slope_gravity_blend) + n * grass_slope_gravity_blend).normalized()
				var yaw := rng.randf() * TAU
				var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
				var right := up_vec.cross(fwd).normalized()
				fwd = right.cross(up_vec).normalized()

				# 7. Volumetric Scale Modulation driven by Grass Map G channel (~0.36x short turf .. ~2.20x tall swells)
				var height_norm := clampf((gm.y - grass_height_map_min) / maxf(0.01, grass_height_map_max - grass_height_map_min), 0.0, 1.0)
				var sxz := lerpf(0.78, 1.32, height_norm) * rng.randf_range(0.86, 1.14)
				var sy := gm.y * rng.randf_range(0.84, 1.16)

				var basis := Basis(right * sxz, up_vec * sy, fwd * sxz)

				# 8. Root Anchoring: embed 3.0cm into terrain to guarantee zero floating blades
				var root_pos := Vector3(x, y - 0.03, z)
				var xf := Transform3D(basis, root_pos)

				if is_wispy:
					wispy_xforms.append(xf)
				else:
					common_xforms.append(xf)

	return { "common": common_xforms, "wispy": wispy_xforms }


func build_dynamic_grass_data(center: Vector2 = Vector2.ZERO) -> Dictionary:
	var target_total := editor_grass_count if Engine.is_editor_hint() else grass_count
	if target_total <= 0:
		return { "common": [] as Array[Transform3D], "wispy": [] as Array[Transform3D] }
	var pass_r := _compute_dynamic_grass_radius(target_total)
	return _build_grass_pass_transforms([[center, pass_r, target_total, 0.0]], 77)


func build_regional_grass_data() -> Dictionary:
	var empty_res := { "common": [] as Array[Transform3D], "wispy": [] as Array[Transform3D] }
	if Engine.is_editor_hint() or grass_count <= 0:
		return empty_res

	var reg_sig := _build_regional_grass_cache_sig()
	if not _cached_regional_grass_data.is_empty() and _cached_regional_grass_sig == reg_sig:
		return _cached_regional_grass_data

	var reg_path := "%sreg_%s.dat" % [GRASS_CACHE_PREFIX, reg_sig.md5_text().left(12)]
	if FileAccess.file_exists(reg_path):
		var f_in := FileAccess.open(reg_path, FileAccess.READ)
		if f_in != null:
			var d = f_in.get_var(false)
			f_in.close()
			if d is Dictionary and String(d.get("sig", "")) == reg_sig:
				var c_typed: Array[Transform3D] = []
				var w_typed: Array[Transform3D] = []
				c_typed.assign(d.get("common", []))
				w_typed.assign(d.get("wispy", []))
				var loaded_res := { "common": c_typed, "wispy": w_typed }
				_cached_regional_grass_data = loaded_res
				_cached_regional_grass_sig = reg_sig
				return loaded_res

	var reg_res := _build_grass_pass_transforms(_get_regional_pass_defs(), 177)
	_cached_regional_grass_data = reg_res
	_cached_regional_grass_sig = reg_sig
	var dir_abs := ProjectSettings.globalize_path(reg_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir_abs)
	if DirAccess.dir_exists_absolute(dir_abs):
		var f_out := FileAccess.open(reg_path, FileAccess.WRITE)
		if f_out != null:
			f_out.store_var({"sig": reg_sig, "common": reg_res["common"], "wispy": reg_res["wispy"]}, false)
			f_out.close()
	return reg_res


## Industry-Standard Hexagonal Blue-Noise Stratified Placement with Continuous Polar Perturbation.
## Completely eliminates Cartesian grid lines and agricultural rows, guaranteeing a lush, gapless carpet.
func build_grass_data(center: Vector2 = Vector2.ZERO, store_in_cache: bool = true) -> Dictionary:
	var is_ed := Engine.is_editor_hint()
	var target_total := editor_grass_count if is_ed else grass_count
	if store_in_cache and not is_ed and not _cached_grass_data.is_empty() and _cached_grass_count == target_total and _cached_grass_center == center:
		return _cached_grass_data

	var dyn := build_dynamic_grass_data(center)
	var common_xforms: Array[Transform3D] = []
	var wispy_xforms: Array[Transform3D] = []
	common_xforms.append_array(dyn.get("common", []))
	wispy_xforms.append_array(dyn.get("wispy", []))

	if not is_ed and target_total > 0:
		var reg := build_regional_grass_data()
		common_xforms.append_array(reg.get("common", []))
		wispy_xforms.append_array(reg.get("wispy", []))

	var res := { "common": common_xforms, "wispy": wispy_xforms }
	if store_in_cache and not is_ed:
		_cached_grass_data = res
		_cached_grass_count = target_total
		_cached_grass_center = center
	return res


## Convenience wrapper for test compatibility. Returns all generated grass transforms.
func build_grass_transforms() -> Array[Transform3D]:
	var data := build_grass_data(_grass_center)
	var xforms: Array[Transform3D] = []
	var common_arr: Array[Transform3D] = data.get("common", [])
	var wispy_arr: Array[Transform3D] = data.get("wispy", [])
	xforms.append_array(common_arr)
	xforms.append_array(wispy_arr)
	return xforms


## Partitions scattered transforms into spatial grid chunks (48m x 48m) with tight custom_aabb
## and distance culling for optimal GPU frustum and occlusion culling.
func _build_chunked_multimeshes(
	parent_node: Node3D,
	mesh: Mesh,
	transforms: Array,
	vis_end: float,
	vis_margin: float,
	cast_shadow: GeometryInstance3D.ShadowCastingSetting,
	material: Material = null,
	chunk_size: float = 48.0,
	aabb_grow_margin: float = 2.0,
	chunk_prefix: String = "Chunk_",
	vis_begin: float = 0.0,
	vis_begin_margin: float = 0.0,
	custom_data: Array = []
) -> void:
	# 1. Clear existing chunk nodes matching chunk_prefix
	for child in parent_node.get_children():
		if child.name.begins_with(chunk_prefix):
			parent_node.remove_child(child)
			child.queue_free()

	if parent_node is MultiMeshInstance3D:
		var empty_mm := MultiMesh.new()
		empty_mm.transform_format = MultiMesh.TRANSFORM_3D
		empty_mm.instance_count = 0
		(parent_node as MultiMeshInstance3D).multimesh = empty_mm

	if transforms.is_empty() or mesh == null:
		return

	var has_custom := not custom_data.is_empty() and custom_data.size() == transforms.size()

	# 2. Partition into spatial grid tiles
	var chunk_map: Dictionary = {}
	var custom_map: Dictionary = {}
	for idx_t in range(transforms.size()):
		var xf: Transform3D = transforms[idx_t]
		var p := xf.origin
		var key := Vector2i(int(floor(p.x / chunk_size)), int(floor(p.z / chunk_size)))
		var arr: Array = chunk_map.get(key, [])
		arr.append(xf)
		chunk_map[key] = arr
		if has_custom:
			var carr: Array = custom_map.get(key, [])
			carr.append(custom_data[idx_t])
			custom_map[key] = carr

	# 3. Instantiate a MultiMeshInstance3D per tile centered at its tight AABB so Godot's native distance culling works accurately
	for key: Vector2i in chunk_map.keys():
		var chunk_xforms: Array = chunk_map[key]
		if chunk_xforms.is_empty():
			continue

		var min_pt := Vector3(INF, INF, INF)
		var max_pt := Vector3(-INF, -INF, -INF)
		for i in chunk_xforms.size():
			var o: Vector3 = (chunk_xforms[i] as Transform3D).origin
			min_pt.x = minf(min_pt.x, o.x)
			min_pt.y = minf(min_pt.y, o.y)
			min_pt.z = minf(min_pt.z, o.z)
			max_pt.x = maxf(max_pt.x, o.x)
			max_pt.y = maxf(max_pt.y, o.y)
			max_pt.z = maxf(max_pt.z, o.z)

		var tight_aabb := AABB(min_pt, max_pt - min_pt).grow(aabb_grow_margin)
		var center := tight_aabb.get_center()
		var half_diag := tight_aabb.size.length() * 0.5

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		if has_custom:
			mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = chunk_xforms.size()

		var chunk_custom: Array = custom_map.get(key, []) if has_custom else []
		for i in chunk_xforms.size():
			var xf: Transform3D = chunk_xforms[i]
			xf.origin -= center
			mm.set_instance_transform(i, xf)
			if has_custom:
				mm.set_instance_custom_data(i, chunk_custom[i] as Color)

		var chunk_inst := MultiMeshInstance3D.new()
		chunk_inst.name = "%s%d_%d" % [chunk_prefix, key.x, key.y]
		chunk_inst.position = center
		chunk_inst.multimesh = mm
		if material != null:
			chunk_inst.material_override = material
		chunk_inst.cast_shadow = cast_shadow
		chunk_inst.set_meta("half_diag", half_diag)
		if vis_begin > 0.0:
			chunk_inst.visibility_range_begin = vis_begin
			chunk_inst.visibility_range_begin_margin = vis_begin_margin
		else:
			chunk_inst.visibility_range_begin = 0.0
			chunk_inst.visibility_range_begin_margin = 0.0
		if vis_end > 0.0:
			chunk_inst.visibility_range_end = vis_end + half_diag
			chunk_inst.visibility_range_end_margin = vis_margin
		else:
			chunk_inst.visibility_range_end = 0.0
			chunk_inst.visibility_range_end_margin = 0.0
		chunk_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

		tight_aabb.position -= center
		chunk_inst.custom_aabb = tight_aabb

		parent_node.add_child(chunk_inst)


var _cached_grass_lod_mesh: Mesh = null
var _cached_wispy_grass_lod_mesh: Mesh = null


func _make_grass_lod_mesh(wispy: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var blade_count := 8
	var heights := [1.56, 1.24, 1.72, 1.32, 1.62, 1.18, 1.76, 1.38] if not wispy else [1.46, 1.16, 1.58, 1.22, 1.48, 1.10, 1.54, 1.26]
	var leans := [0.28, 0.36, 0.22, 0.34, 0.30, 0.38, 0.24, 0.32] if not wispy else [0.46, 0.58, 0.38, 0.54, 0.44, 0.62, 0.40, 0.52]
	var rads := [0.16, 0.22, 0.14, 0.24, 0.18, 0.20, 0.12, 0.22] if not wispy else [0.22, 0.30, 0.18, 0.32, 0.24, 0.28, 0.18, 0.30]
	var angles := [0.12, 0.91, 1.68, 2.47, 3.24, 4.03, 4.81, 5.59]
	var u0: float = 0.024 if wispy else 0.185
	var u1: float = 0.034 if wispy else 0.197
	var um: float = (u0 + u1) * 0.5
	var w0: float = 0.072 if not wispy else 0.068
	var w1: float = w0 * 0.56

	for b in blade_count:
		var ang: float = angles[b]
		var rot := Basis(Vector3.UP, ang)
		var off := rot * Vector3(0.0, 0.0, rads[b])
		var h: float = heights[b]
		var lean: float = leans[b]
		var bv := verts.size()
		verts.append(off + rot * Vector3(-w0, 0.0, 0.0))
		verts.append(off + rot * Vector3(w0, 0.0, 0.0))
		verts.append(off + rot * Vector3(-w1, h * 0.54, lean * 0.42))
		verts.append(off + rot * Vector3(w1, h * 0.54, lean * 0.42))
		verts.append(off + rot * Vector3(0.0, h, lean))
		for _ni in 5:
			normals.append(Vector3.UP)
		uvs.append(Vector2(u0, 0.96))
		uvs.append(Vector2(u1, 0.96))
		uvs.append(Vector2(u0, 0.48))
		uvs.append(Vector2(u1, 0.48))
		uvs.append(Vector2(um, 0.04))
		indices.append(bv + 0); indices.append(bv + 1); indices.append(bv + 2)
		indices.append(bv + 1); indices.append(bv + 3); indices.append(bv + 2)
		indices.append(bv + 2); indices.append(bv + 3); indices.append(bv + 4)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _get_grass_lod_mesh() -> Mesh:
	if _cached_grass_lod_mesh == null:
		_cached_grass_lod_mesh = _make_grass_lod_mesh(false)
	return _cached_grass_lod_mesh


func _get_wispy_grass_lod_mesh() -> Mesh:
	if _cached_wispy_grass_lod_mesh == null:
		_cached_wispy_grass_lod_mesh = _make_grass_lod_mesh(true)
	return _cached_wispy_grass_lod_mesh


func _build_grass_multimesh(grass_node: MultiMeshInstance3D, rebuild_regional: bool = true) -> void:
	if Engine.is_editor_hint() and not preview_grass_in_editor:
		grass_node.multimesh = null
		return

	if _grass_mat == null:
		_grass_mat = grass_node.material_override as ShaderMaterial
	_sync_grass_map_to_materials()
	var eff_vis := _get_effective_grass_vis_end()

	if rebuild_regional:
		var reg_data := build_regional_grass_data()
		var reg_xforms: Array[Transform3D] = reg_data.get("common", [])
		_build_chunked_multimeshes(grass_node, _get_grass_mesh(), reg_xforms, eff_vis, grass_visibility_margin, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, _grass_mat, 32.0, 2.0, "RegChunk_")

	if _cached_grass_data.is_empty() or _cached_grass_count != grass_count or _cached_grass_center != _grass_center:
		_cached_grass_data = build_dynamic_grass_data(_grass_center)
		_cached_grass_count = grass_count
		_cached_grass_center = _grass_center

	var common_xforms: Array[Transform3D] = _cached_grass_data.get("common", [])
	_build_chunked_multimeshes(grass_node, _get_grass_mesh(), common_xforms, eff_vis, grass_visibility_margin, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, _grass_mat, 32.0, 2.0, "Chunk_")


func _build_grass_wispy_multimesh(wispy_node: MultiMeshInstance3D, rebuild_regional: bool = true) -> void:
	if Engine.is_editor_hint() and not preview_grass_in_editor:
		wispy_node.multimesh = null
		return

	var mat: ShaderMaterial = wispy_node.material_override as ShaderMaterial
	if mat == null:
		mat = _grass_mat
	else:
		_grass_wispy_mat = mat
	_sync_grass_map_to_materials()
	var eff_vis := _get_effective_grass_vis_end()

	if rebuild_regional:
		var reg_data := build_regional_grass_data()
		var reg_xforms: Array[Transform3D] = reg_data.get("wispy", [])
		_build_chunked_multimeshes(wispy_node, _get_wispy_grass_mesh(), reg_xforms, eff_vis, grass_visibility_margin, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, mat, 32.0, 2.0, "RegChunk_")

	if _cached_grass_data.is_empty() or _cached_grass_count != grass_count or _cached_grass_center != _grass_center:
		_cached_grass_data = build_dynamic_grass_data(_grass_center)
		_cached_grass_count = grass_count
		_cached_grass_center = _grass_center

	var wispy_xforms: Array[Transform3D] = _cached_grass_data.get("wispy", [])
	_build_chunked_multimeshes(wispy_node, _get_wispy_grass_mesh(), wispy_xforms, eff_vis, grass_visibility_margin, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, mat, 32.0, 2.0, "Chunk_")


var _grass_wispy_mat: ShaderMaterial = null
var _grass_far_mat: ShaderMaterial = null
var _grass_wispy_far_mat: ShaderMaterial = null
var _grass_far_shader: Shader = null
var _last_grass_lod_cam_pos := Vector3(1e9, 1e9, 1e9)
var _grass_holder_ref: Node3D = null
var _grass_wispy_holder_ref: Node3D = null
var _tree_chunks_arr: Array[MultiMeshInstance3D] = []
var _last_tree_shadow_cam := Vector3(1e9, 1e9, 1e9)
var _grass_worker_task_id: int = -1
var _grass_worker_center: Vector2 = Vector2.ZERO
var _grass_worker_res: Dictionary = {}


func _exit_tree() -> void:
	if _grass_worker_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_grass_worker_task_id)
		_grass_worker_task_id = -1


func _collect_tree_chunks(trees_node: Node3D) -> void:
	_tree_chunks_arr.clear()
	_last_tree_shadow_cam = Vector3(1e9, 1e9, 1e9)
	if trees_node == null:
		return
	for ch in trees_node.get_children():
		for sub in ch.get_children():
			if sub is MultiMeshInstance3D and sub.name.begins_with("Chunk_"):
				_tree_chunks_arr.append(sub as MultiMeshInstance3D)


func _update_tree_shadow_cull(cam_pos: Vector3) -> void:
	if _tree_chunks_arr.is_empty():
		return
	if cam_pos.distance_squared_to(_last_tree_shadow_cam) < 64.0:
		return
	_last_tree_shadow_cam = cam_pos
	const TREE_SHADOW_DIST := 54.0
	for tmi in _tree_chunks_arr:
		if tmi == null or not is_instance_valid(tmi):
			continue
		var hd := float(tmi.get_meta("half_diag", 20.0))
		var r_max := TREE_SHADOW_DIST + hd
		var want_sh := tmi.position.distance_squared_to(cam_pos) <= r_max * r_max
		var target_sh := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if want_sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if tmi.cast_shadow != target_sh:
			tmi.cast_shadow = target_sh


func _grass_recenter_worker(target_c: Vector2) -> void:
	# Compute only dynamic player-ring grass off-thread; static regional grass stays intact.
	_grass_worker_res = build_dynamic_grass_data(target_c)
var _grass_recenter_cooldown: float = 0.0

func _ensure_grass_far_materials() -> void:
	if _grass_far_shader == null:
		_grass_far_shader = load("res://terrain/grass_far.gdshader") as Shader
	if _grass_far_shader == null:
		return
	if _grass_mat != null and _grass_far_mat == null:
		_grass_far_mat = _grass_mat.duplicate() as ShaderMaterial
		_grass_far_mat.shader = _grass_far_shader
	if _grass_wispy_mat != null and _grass_wispy_mat != _grass_mat and _grass_wispy_far_mat == null:
		_grass_wispy_far_mat = _grass_wispy_mat.duplicate() as ShaderMaterial
		_grass_wispy_far_mat.shader = _grass_far_shader
	elif _grass_wispy_mat == _grass_mat:
		_grass_wispy_far_mat = _grass_far_mat
	_sync_grass_map_to_materials()


func _update_grass_chunk_lod(holder: Node3D, near_mat: ShaderMaterial, far_mat: ShaderMaterial, near_mesh: Mesh, far_mesh: Mesh, cam_pos: Vector3) -> void:
	if holder == null or near_mat == null or far_mat == null:
		return
	for ch in holder.get_children():
		var mmi := ch as MultiMeshInstance3D
		if mmi == null:
			continue
		var center := mmi.position + mmi.custom_aabb.get_center()
		var d_sq := cam_pos.distance_squared_to(center)
		var target_mat := far_mat if d_sq > 1024.0 else near_mat
		if mmi.material_override != target_mat:
			mmi.material_override = target_mat
		if near_mesh != null and far_mesh != null and mmi.multimesh != null:
			var target_mesh := far_mesh if d_sq > 2304.0 else near_mesh
			if mmi.multimesh.mesh != target_mesh:
				mmi.multimesh.mesh = target_mesh


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _grass_holder_ref == null:
		_grass_holder_ref = get_node_or_null("Grass") as Node3D
	if _grass_wispy_holder_ref == null:
		_grass_wispy_holder_ref = get_node_or_null("GrassWispy") as Node3D
	if _grass_holder_ref != null and not _grass_holder_ref.visible:
		return

	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player") as Node3D
		if _player_ref == null and get_parent() != null:
			_player_ref = get_parent().get_node_or_null("Slime") as Node3D

	if _player_ref != null:
		var p_pos := _player_ref.global_position
		if _grass_mat == null:
			var grass_node := _grass_holder_ref as MultiMeshInstance3D
			if grass_node != null:
				_grass_mat = grass_node.material_override as ShaderMaterial
		if _grass_wispy_mat == null:
			var wn_ref := _grass_wispy_holder_ref as MultiMeshInstance3D
			if wn_ref != null:
				_grass_wispy_mat = wn_ref.material_override as ShaderMaterial
		_ensure_grass_far_materials()

		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		var lod_pos := cam.global_position if cam != null else p_pos
		if lod_pos.distance_squared_to(_last_grass_lod_cam_pos) > 16.0:
			_last_grass_lod_cam_pos = lod_pos
			_update_grass_chunk_lod(_grass_holder_ref, _grass_mat, _grass_far_mat, _get_grass_mesh(), _get_grass_lod_mesh(), lod_pos)
			_update_grass_chunk_lod(_grass_wispy_holder_ref, _grass_wispy_mat if _grass_wispy_mat != null else _grass_mat, _grass_wispy_far_mat if _grass_wispy_far_mat != null else _grass_far_mat, _get_wispy_grass_mesh(), _get_wispy_grass_lod_mesh(), lod_pos)
			_update_tree_shadow_cull(lod_pos)

		var dyn_r := _compute_dynamic_grass_radius(grass_count)
		var trigger_dist := clampf(dyn_r * 0.36, 18.0, 48.0)
		var urgent_dist := clampf(dyn_r * 0.58, 30.0, 72.0)

		# Apply finished async grass recentering without stalling a frame or tearing down static regional chunks
		if _grass_worker_task_id >= 0 and WorkerThreadPool.is_task_completed(_grass_worker_task_id):
			WorkerThreadPool.wait_for_task_completion(_grass_worker_task_id)
			_grass_worker_task_id = -1
			if not _grass_worker_res.is_empty():
				_grass_center = _grass_worker_center
				_cached_grass_data = _grass_worker_res
				_cached_grass_count = grass_count
				_cached_grass_center = _grass_worker_center
				_grass_worker_res = {}
				var gn_a := _grass_holder_ref as MultiMeshInstance3D
				var wn_a := _grass_wispy_holder_ref as MultiMeshInstance3D
				if gn_a != null:
					_build_grass_multimesh(gn_a, false)
				if wn_a != null:
					_build_grass_wispy_multimesh(wn_a, false)
				_last_grass_lod_cam_pos = Vector3(1e9, 1e9, 1e9)
				if Vector2(p_pos.x, p_pos.z).distance_to(_grass_center) > trigger_dist:
					_grass_recenter_cooldown = 0.0

		_grass_recenter_cooldown = maxf(0.0, _grass_recenter_cooldown - delta)
		var p_xz := Vector2(p_pos.x, p_pos.z)
		var jump_dist := p_xz.distance_to(_grass_center)
		if _grass_worker_task_id < 0 and grass_count > 0 and ((jump_dist > urgent_dist) or (_grass_recenter_cooldown <= 0.0 and jump_dist > trigger_dist)) and p_pos.y > 5.0:
			_ensure_grid_coords()
			_ensure_grass_map()
			_grass_recenter_cooldown = 0.25
			_grass_worker_center = p_xz
			_grass_worker_res = {}
			_grass_worker_task_id = WorkerThreadPool.add_task(_grass_recenter_worker.bind(p_xz), false, "GrassRecenter")


# =============================================================================
# DETERMINISTIC TREE ECOSYSTEM (Stylized Nature MegaKit Assets)
# =============================================================================

const TREE_ASSET_PATHS := [
	"res://assets/nature/CommonTree_1.gltf",
	"res://assets/nature/CommonTree_2.gltf",
	"res://assets/nature/Pine_1.gltf",
	"res://assets/nature/Pine_2.gltf",
	"res://assets/nature_extra/BirchTree_1.gltf",
	"res://assets/nature_extra/BirchTree_3.gltf",
	"res://assets/nature_extra/MapleTree_1.gltf",
	"res://assets/nature_extra/MapleTree_2.gltf",
	"res://assets/nature_extra/DeadTree_1.gltf",
]

const TREE_NODE_NAMES := [
	"CommonTree1",
	"CommonTree2",
	"Pine1",
	"Pine2",
	"BirchTree1",
	"BirchTree3",
	"MapleTree1",
	"MapleTree2",
	"DeadTree1",
]

const TREE_IMPOSTOR_STYLES := [0, 0, 1, 1, 2, 2, 3, 3, 4]
const TREE_BARK_TEX_PATHS := [
	"res://assets/nature/Bark_NormalTree.png",
	"res://assets/nature/Bark_NormalTree.png",
	"res://assets/nature/Bark_NormalTree.png",
	"res://assets/nature/Bark_NormalTree.png",
	"res://assets/nature_extra/BirchTree_Bark.jpg",
	"res://assets/nature_extra/BirchTree_Bark.jpg",
	"res://assets/nature_extra/MapleTree_Bark.jpg",
	"res://assets/nature_extra/MapleTree_Bark.jpg",
	"res://assets/nature_extra/NormalTree_Bark.jpg",
]
const TREE_LEAF_TEX_PATHS := [
	"res://assets/nature/Leaves_NormalTree_C.png",
	"res://assets/nature/Leaves_NormalTree_C.png",
	"res://assets/nature/Leaf_Pine_C.png",
	"res://assets/nature/Leaf_Pine_C.png",
	"res://assets/nature_extra/BirchTree_Leaves.png",
	"res://assets/nature_extra/BirchTree_Leaves.png",
	"res://assets/nature_extra/MapleTree_Leaves.png",
	"res://assets/nature_extra/MapleTree_Leaves.png",
	"",
]

var _cached_tree_meshes: Array[Mesh] = []
var _cached_merged_tree_impostor_mesh: Mesh = null
var _cached_tree_impostor_dims: Array[Vector3] = []
var _tree_impostor_shader: Shader = null
var _tree_eat_grid: Dictionary = {}
var _tree_eat_grid_built: bool = false
var _tree_trunk_body_rid: RID = RID()


func _make_tree_bark_mat(albedo_path: String, normal_path: String = "") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(albedo_path) as Texture2D
	if not normal_path.is_empty():
		var norm_tex := load(normal_path) as Texture2D
		if norm_tex != null:
			mat.normal_enabled = true
			mat.normal_texture = norm_tex
			mat.normal_scale = 0.65
	mat.metallic = 0.0
	mat.metallic_specular = 0.08
	mat.roughness = 0.90
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return mat


func _make_tree_leaf_mat(albedo_path: String, alpha_scissor: float = 0.42) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://terrain/tree_foliage.gdshader")
	mat.set_shader_parameter("leaf_texture", load(albedo_path) as Texture2D)
	mat.set_shader_parameter("alpha_scissor", alpha_scissor)
	mat.set_shader_parameter("u_webwood_center", get_webwood_center())
	return mat


func _get_tree_mesh(archetype: int) -> Mesh:
	if _cached_tree_meshes.is_empty():
		var bark_mat := _make_tree_bark_mat("res://assets/nature/Bark_NormalTree.png", "res://assets/nature/Bark_NormalTree_Normal.png")
		var birch_bark_mat := _make_tree_bark_mat("res://assets/nature_extra/BirchTree_Bark.jpg", "res://assets/nature_extra/BirchTree_Bark_Normal.png")
		var maple_bark_mat := _make_tree_bark_mat("res://assets/nature_extra/MapleTree_Bark.jpg", "res://assets/nature_extra/MapleTree_Bark_Normal.png")
		var dead_bark_mat := _make_tree_bark_mat("res://assets/nature_extra/NormalTree_Bark.jpg", "res://assets/nature_extra/NormalTree_Bark_Normal.png")

		var broadleaf_mat := _make_tree_leaf_mat("res://assets/nature/Leaves_NormalTree_C.png", 0.44)
		var pine_mat := _make_tree_leaf_mat("res://assets/nature/Leaf_Pine_C.png", 0.44)
		var birch_leaf_mat := _make_tree_leaf_mat("res://assets/nature_extra/BirchTree_Leaves.png", 0.38)
		var maple_leaf_mat := _make_tree_leaf_mat("res://assets/nature_extra/MapleTree_Leaves.png", 0.40)

		var bark_mats := [
			bark_mat, bark_mat, bark_mat, bark_mat,
			birch_bark_mat, birch_bark_mat,
			maple_bark_mat, maple_bark_mat,
			dead_bark_mat,
		]
		var leaf_mats := [
			broadleaf_mat, broadleaf_mat, pine_mat, pine_mat,
			birch_leaf_mat, birch_leaf_mat,
			maple_leaf_mat, maple_leaf_mat,
			null,
		]

		for i in range(TREE_ASSET_PATHS.size()):
			var path: String = TREE_ASSET_PATHS[i]
			var sc: PackedScene = load(path)
			if sc != null:
				var inst: Node = sc.instantiate()
				var found_mesh: Mesh = null
				for c in inst.get_children():
					if c is MeshInstance3D and c.mesh != null:
						found_mesh = c.mesh.duplicate()
						break
				inst.free()
				if found_mesh != null:
					found_mesh.surface_set_material(0, bark_mats[i])
					if found_mesh.get_surface_count() > 1 and leaf_mats[i] != null:
						found_mesh.surface_set_material(1, leaf_mats[i])
				_cached_tree_meshes.append(found_mesh)
			else:
				_cached_tree_meshes.append(null)

	if archetype >= 0 and archetype < _cached_tree_meshes.size():
		return _cached_tree_meshes[archetype]
	return null


func _build_tex_array(paths: Array, fallback_color: Color) -> Texture2DArray:
	const TEX_SZ := 256
	var imgs: Array[Image] = []
	for p in paths:
		var img: Image = null
		var path_s: String = String(p)
		if not path_s.is_empty():
			var tex := load(path_s) as Texture2D
			if tex != null:
				img = tex.get_image()
				if img != null:
					img = img.duplicate() as Image
					if img.is_compressed():
						img.decompress()
					if img.get_width() != TEX_SZ or img.get_height() != TEX_SZ:
						img.resize(TEX_SZ, TEX_SZ, Image.INTERPOLATE_BILINEAR)
					img.convert(Image.FORMAT_RGBA8)
					img.generate_mipmaps()
		if img == null:
			img = Image.create(TEX_SZ, TEX_SZ, true, Image.FORMAT_RGBA8)
			img.fill(fallback_color)
			img.generate_mipmaps()
		imgs.append(img)
	var arr_tex := Texture2DArray.new()
	if arr_tex.create_from_images(imgs) == OK:
		return arr_tex
	return null


func _ensure_tree_impostor_assets() -> void:
	if _cached_merged_tree_impostor_mesh != null and not _cached_tree_impostor_dims.is_empty():
		return
	if _tree_impostor_shader == null:
		_tree_impostor_shader = load("res://terrain/tree_impostor.gdshader") as Shader
	_cached_tree_impostor_dims.clear()
	var max_hw := 1.4
	var max_h := 4.0
	for i in range(TREE_ASSET_PATHS.size()):
		var m3d := _get_tree_mesh(i)
		var half_w := 3.2
		var min_y := 0.0
		var max_y := 9.0
		if m3d != null:
			var aabb := m3d.get_aabb()
			half_w = maxf(maxf(absf(aabb.position.x), absf(aabb.end.x)), maxf(absf(aabb.position.z), absf(aabb.end.z)))
			half_w = maxf(half_w * 1.05, 1.4)
			min_y = minf(aabb.position.y, 0.0)
			max_y = maxf(aabb.end.y, 4.0)
		max_hw = maxf(max_hw, half_w)
		max_h = maxf(max_h, max_y)
		_cached_tree_impostor_dims.append(Vector3(half_w, min_y, max_y))

	if _tree_impostor_shader == null:
		return
	# Unit quad: X in [-1, 1], Y in [0, 1]; shader scales by INSTANCE_CUSTOM (arch, half_w, min_y, max_y)
	var verts := PackedVector3Array([
		Vector3(-1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(-1.0, 1.0, 0.0),
	])
	var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var uvs := PackedVector2Array([
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, 0.0),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var imp_mesh := ArrayMesh.new()
	imp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	imp_mesh.custom_aabb = AABB(Vector3(-max_hw, -0.5, -max_hw), Vector3(max_hw * 2.0, max_h + 1.0, max_hw * 2.0))

	var mat := ShaderMaterial.new()
	mat.shader = _tree_impostor_shader
	mat.set_shader_parameter(&"u_webwood_center", get_webwood_center())
	var bark_arr := _build_tex_array(TREE_BARK_TEX_PATHS, Color(0.36, 0.28, 0.22, 1.0))
	if bark_arr != null:
		mat.set_shader_parameter(&"bark_textures", bark_arr)
	var leaf_arr := _build_tex_array(TREE_LEAF_TEX_PATHS.slice(0, 8), Color(0.28, 0.48, 0.22, 0.0))
	if leaf_arr != null:
		mat.set_shader_parameter(&"leaf_textures", leaf_arr)
	imp_mesh.surface_set_material(0, mat)
	_cached_merged_tree_impostor_mesh = imp_mesh


func _get_merged_tree_impostor_mesh() -> Mesh:
	_ensure_tree_impostor_assets()
	return _cached_merged_tree_impostor_mesh


func _get_tree_impostor_dims(archetype: int) -> Vector3:
	_ensure_tree_impostor_assets()
	if archetype >= 0 and archetype < _cached_tree_impostor_dims.size():
		return _cached_tree_impostor_dims[archetype]
	return Vector3(3.2, 0.0, 9.0)


var _cached_tree_data: Array[Dictionary] = []
var _spider_forest_trees: Array[Dictionary] = []


func get_spider_forest_trees() -> Array[Dictionary]:
	return _spider_forest_trees

func _try_place_tree(
	jx: float,
	jz: float,
	spacing: float,
	min_norm_y: float,
	archetype: int,
	rng: RandomNumberGenerator,
	placed_positions: Array[Vector3],
	placed_trees: Array[Dictionary],
	ignore_spawn_radius: bool = false,
	min_h_override: float = -1e9
) -> bool:
	if not ignore_spawn_radius:
		var dist := sqrt(jx * jx + jz * jz)
		if dist < tree_clearing_radius or dist > tree_spawn_radius:
			return false
	if enable_cave and (CaveSystem.is_in_portal_scatter_exclusion(jx, jz, false) or is_point_in_cave_cutout(jx, jz)):
		return false
	if VillageBuilder.is_in_village_exclusion(jx, jz, false):
		return false
	if WorldLandmarks.is_in_landmark_exclusion(jx, jz, false):
		return false

	var surf := sample_surface_exact(jx, jz)
	var y := surf.w
	var normal := Vector3(surf.x, surf.y, surf.z)
	var eff_min_h := maxf(tree_min_height, min_h_override)
	if y < eff_min_h or y > tree_max_height:
		return false
	if normal.y < min_norm_y:
		return false

	var candidate_pos := Vector3(jx, y - 0.15, jz)
	var spacing_sq := spacing * spacing
	for pos in placed_positions:
		var dx: float = pos.x - jx
		var dz: float = pos.z - jz
		if (dx * dx + dz * dz) < spacing_sq:
			return false

	var yaw: float = rng.randf() * TAU
	var scale_y: float = rng.randf_range(2.2, 3.4)
	var scale_xz: float = scale_y * rng.randf_range(0.92, 1.08)

	var up := (Vector3.UP * 0.85 + normal * 0.15).normalized()
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := up.cross(forward).normalized()
	forward = right.cross(up).normalized()

	var basis := Basis(right * scale_xz, up * scale_y, forward * scale_xz)
	placed_positions.append(candidate_pos)
	placed_trees.append({
		"transform": Transform3D(basis, candidate_pos),
		"archetype": archetype,
		"position": candidate_pos,
		"scale_y": scale_y,
		"scale_xz": scale_xz
	})
	return true


func _pick_forest_archetype(y: float, jz: float, rng: RandomNumberGenerator, allow_dead: bool) -> int:
	if allow_dead and rng.randf() < 0.08:
		return 8
	var r := rng.randf()
	if y > 42.0 or jz < -65.0:
		if r < 0.45:
			return 2 if rng.randf() < 0.60 else 3 # Pine
		elif r < 0.78:
			return 4 if rng.randf() < 0.55 else 5 # Birch
		else:
			return 6 if rng.randf() < 0.50 else 7 # Maple
	else:
		if r < 0.36:
			return 0 if rng.randf() < 0.60 else 1 # Common
		elif r < 0.68:
			return 4 if rng.randf() < 0.55 else 5 # Birch
		elif r < 0.92:
			return 6 if rng.randf() < 0.50 else 7 # Maple
		else:
			return 2 if rng.randf() < 0.60 else 3 # Pine


## 100% Deterministic Tree Placement across the cave entrance forest, meadow valley, and foothills.
## Uses a seeded random generator and spatial grid to guarantee bit-for-bit repeatability.
func build_tree_data() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed

	var target_count := editor_tree_count if Engine.is_editor_hint() else tree_count
	if not enable_trees or target_count <= 0:
		_cached_tree_data = []
		return []

	var tcache_sig := ""
	var tcache_path := ""
	if not Engine.is_editor_hint():
		tcache_sig = "tr_v1|%d|%d|%d|%.1f|%.1f|%.1f|%s|%s" % [
			terrain_seed, tree_seed, target_count, tree_clearing_radius, tree_spawn_radius,
			tree_min_height, str(enable_cave), str(_webwood_layout)
		]
		tcache_path = "user://cache/trees_%s.dat" % tcache_sig.md5_text().left(12)
		if FileAccess.file_exists(tcache_path):
			var f_in := FileAccess.open(tcache_path, FileAccess.READ)
			if f_in != null:
				var d = f_in.get_var(false)
				f_in.close()
				if d is Dictionary and String(d.get("sig", "")) == tcache_sig:
					var typed_t: Array[Dictionary] = []
					typed_t.assign(d.get("trees", []))
					var typed_s: Array[Dictionary] = []
					typed_s.assign(d.get("spider", []))
					_cached_tree_data = typed_t
					_spider_forest_trees = typed_s
					return typed_t

	var placed_trees: Array[Dictionary] = []
	var placed_positions: Array[Vector3] = []

	# Pass 1: Dense mixed forest framing the cave entrance & flanking hills (keeps mouth trail clear)
	if enable_cave:
		var cave_cx := CaveLayout.ORIGIN.x
		var cave_cz := CaveLayout.ORIGIN.z
		var cave_cell := 10.5
		var cave_radius := 112.0
		var cave_grid_r := int(ceil(cave_radius / cave_cell))
		var cave_candidates: Array[Vector2] = []
		for gx in range(-cave_grid_r, cave_grid_r + 1):
			for gz in range(-cave_grid_r, cave_grid_r + 1):
				var cx := float(gx) * cave_cell
				var cz := float(gz) * cave_cell
				var d := sqrt(cx * cx + cz * cz)
				if d < 14.0 or d > cave_radius:
					continue
				cave_candidates.append(Vector2(cave_cx + cx, cave_cz + cz))
		for i in range(cave_candidates.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Vector2 = cave_candidates[i]
			cave_candidates[i] = cave_candidates[j]
			cave_candidates[j] = tmp

		var cave_forest_cap := int(float(target_count) * 0.58)
		for cell_base in cave_candidates:
			if placed_trees.size() >= cave_forest_cap:
				break
			var jx: float = cell_base.x + rng.randf_range(-cave_cell * 0.40, cave_cell * 0.40)
			var jz: float = cell_base.y + rng.randf_range(-cave_cell * 0.40, cave_cell * 0.40)
			var surf_y := sample_height(jx, jz)
			var arch := _pick_forest_archetype(surf_y, jz, rng, true)
			_try_place_tree(jx, jz, 9.2, min_tree_normal_y, arch, rng, placed_positions, placed_trees)

	# Pass 2: Overworld valley and foothill woodlands
	var cell_size := 18.0
	var grid_radius := int(ceil(tree_spawn_radius / cell_size))

	var candidates: Array[Vector2] = []
	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var cx := float(gx) * cell_size
			var cz := float(gz) * cell_size
			var d := sqrt(cx * cx + cz * cz)
			if d > tree_spawn_radius or d < tree_clearing_radius:
				continue
			candidates.append(Vector2(cx, cz))

	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2 = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	for cell_base in candidates:
		if placed_trees.size() >= target_count:
			break

		var jx: float = cell_base.x + rng.randf_range(-cell_size * 0.40, cell_size * 0.40)
		var jz: float = cell_base.y + rng.randf_range(-cell_size * 0.40, cell_size * 0.40)

		var wood_macro: float = _noise.get_noise_2d(jx * 0.012 + 120.0, jz * 0.012 - 90.0) * 0.5 + 0.5
		var wood_detail: float = _noise.get_noise_2d(jx * 0.028 - 40.0, jz * 0.028 + 65.0) * 0.5 + 0.5
		var glade_path: float = absf(_noise.get_noise_2d(jx * 0.016 + 20.0, jz * 0.016 - 30.0))

		var woodland_density: float = (wood_macro * 0.65 + wood_detail * 0.35) * smoothstep(0.05, 0.15, glade_path)
		if woodland_density < 0.32:
			continue

		var surf_y := sample_height(jx, jz)
		var arch := _pick_forest_archetype(surf_y, jz, rng, false)
		_try_place_tree(jx, jz, min_tree_spacing, 0.866, arch, rng, placed_positions, placed_trees)

	# Pass 3: Seaside Bluffs & Slimebrook Perimeter Woodlands (deterministic coastal groves)
	var coast_rng := RandomNumberGenerator.new()
	coast_rng.seed = tree_seed + 409
	var vc := Vector2(VillageBuilder.VILLAGE_CENTER.x, VillageBuilder.VILLAGE_CENTER.z)
	var coast_cell := 13.5
	var coast_r := 285.0
	var coast_grid := int(ceil(coast_r / coast_cell))
	var coast_candidates: Array[Vector2] = []
	for gx in range(-coast_grid, coast_grid + 1):
		for gz in range(-coast_grid, coast_grid + 1):
			var off := Vector2(float(gx) * coast_cell, float(gz) * coast_cell)
			var d := off.length()
			if d < 110.0 or d > coast_r:
				continue
			coast_candidates.append(vc + off)
	for i in range(coast_candidates.size() - 1, 0, -1):
		var j := coast_rng.randi_range(0, i)
		var tmp := coast_candidates[i]
		coast_candidates[i] = coast_candidates[j]
		coast_candidates[j] = tmp

	var coast_trees_added := 0
	for cell_base in coast_candidates:
		if coast_trees_added >= 210:
			break
		var jx := cell_base.x + coast_rng.randf_range(-coast_cell * 0.42, coast_cell * 0.42)
		var jz := cell_base.y + coast_rng.randf_range(-coast_cell * 0.42, coast_cell * 0.42)
		var wood_n := _noise.get_noise_2d(jx * 0.011 - 65.0, jz * 0.011 + 140.0) * 0.5 + 0.5
		if wood_n < 0.22:
			continue
		var surf_y := sample_height(jx, jz)
		var arch := _pick_forest_archetype(surf_y, jz, coast_rng, false)
		if _try_place_tree(jx, jz, 9.2, 0.84, arch, coast_rng, placed_positions, placed_trees, true, 6.8):
			coast_trees_added += 1

	# Pass 4: Wide Webwood Spider Domain with flanked forest approach path
	_spider_forest_trees = []
	var sp_rng := RandomNumberGenerator.new()
	sp_rng.seed = tree_seed + 811
	var sp_c: Vector2 = _webwood_layout.get("center", WorldLandmarks.SPIDER_FOREST_CENTER)
	var sp_f_rad: float = float(_webwood_layout.get("forest_radius", WorldLandmarks.SPIDER_FOREST_RADIUS))
	var sp_cell: float = float(_webwood_layout.get("tree_grid_spacing", 8.6))
	var sp_min_r: float = float(_webwood_layout.get("tree_min_radius", 10.0))
	var sp_glade_r: float = float(_webwood_layout.get("tree_glade_clearance", 11.0))
	var sp_trail_r: float = float(_webwood_layout.get("tree_trail_clearance", 3.8))
	var sp_snags: Array = _webwood_layout.get("snag_offsets", WorldLandmarks.SPIDER_NEST_SNAGS)
	var sp_grid := int(ceil(sp_f_rad / sp_cell))
	var sp_cells: Array[Vector2] = []
	for gx in range(-sp_grid, sp_grid + 1):
		for gz in range(-sp_grid, sp_grid + 1):
			var off := Vector2(float(gx) * sp_cell, float(gz) * sp_cell)
			var d := off.length()
			if d < sp_min_r or d > sp_f_rad:
				continue
			sp_cells.append(sp_c + off)
	for i in range(sp_cells.size() - 1, 0, -1):
		var j := sp_rng.randi_range(0, i)
		var tmp := sp_cells[i]
		sp_cells[i] = sp_cells[j]
		sp_cells[j] = tmp

	var sp_road_a: Vector2 = _webwood_layout.get("trail_start", WorldLandmarks.SPIDER_TRAIL_START)
	var sp_road_b: Vector2 = _webwood_layout.get("trail_bend", WorldLandmarks.SPIDER_TRAIL_BEND)
	var sp_added := 0
	for cell_base in sp_cells:
		if sp_added >= 460:
			break
		var jx := cell_base.x + sp_rng.randf_range(-sp_cell * 0.42, sp_cell * 0.42)
		var jz := cell_base.y + sp_rng.randf_range(-sp_cell * 0.42, sp_cell * 0.42)
		var jv := Vector2(jx, jz)
		# Keep a narrow flanked footpath along the NE dirt trail so trees frame it on both sides
		if jv.distance_to(Geometry2D.get_closest_point_to_segment(jv, sp_road_a, sp_road_b)) < sp_trail_r \
				or jv.distance_to(Geometry2D.get_closest_point_to_segment(jv, sp_road_b, sp_c)) < sp_trail_r:
			continue
		var d_glade := jv.distance_to(sp_c)
		if d_glade < sp_glade_r:
			continue
		if d_glade < 20.0 and sp_snags.any(func(off: Vector2) -> bool: return jv.distance_squared_to(sp_c + off) < 12.25):
			continue
		# Make the tree silhouettes tell the same progression as the webs: a broken,
		# unsettling outer fringe growing into a dense wall around the broodmother's heart.
		var tree_probability := 0.38 if d_glade > 118.0 else (0.76 if d_glade > 72.0 else 0.97)
		if sp_rng.randf() > tree_probability:
			continue
		var r_pick := sp_rng.randf()
		var arch := 8 if r_pick < 0.34 else (2 if r_pick < 0.68 else (3 if r_pick < 0.92 else (1 if d_glade > 44.0 else 2)))
		var min_spacing := 8.0 if d_glade > 112.0 else (6.8 if d_glade > 68.0 else 5.8)
		if _try_place_tree(jx, jz, min_spacing, 0.77, arch, sp_rng, placed_positions, placed_trees, true, 6.4):
			sp_added += 1
			var rec: Dictionary = placed_trees[placed_trees.size() - 1]
			if d_glade <= 152.0:
				_spider_forest_trees.append(rec)

	# Pass 5: Howlcrest Pine Grove wrapping Wolf Pack Crag ((290, -240), R = 68m)
	var rs_tree := regional_scatter if regional_scatter != null else RegionalScatterProfile.new()
	var wf_rng := RandomNumberGenerator.new()
	wf_rng.seed = tree_seed + 929
	var wf_c := WorldLandmarks.WOLF_CRAG_CENTER
	var wf_cell := maxf(rs_tree.wolf_tree_spacing, 4.0)
	var wf_grid := int(ceil(rs_tree.wolf_tree_radius / wf_cell))
	var wf_cells: Array[Vector2] = []
	for gx in range(-wf_grid, wf_grid + 1):
		for gz in range(-wf_grid, wf_grid + 1):
			var off := Vector2(float(gx) * wf_cell, float(gz) * wf_cell)
			var d := off.length()
			if d < 15.0 or d > WorldLandmarks.WOLF_GROVE_RADIUS:
				continue
			wf_cells.append(wf_c + off)
	for i in range(wf_cells.size() - 1, 0, -1):
		var j := wf_rng.randi_range(0, i)
		var tmp := wf_cells[i]
		wf_cells[i] = wf_cells[j]
		wf_cells[j] = tmp

	var wf_added := 0
	for cell_base in wf_cells:
		if wf_added >= 115:
			break
		var jx := cell_base.x + wf_rng.randf_range(-wf_cell * 0.40, wf_cell * 0.40)
		var jz := cell_base.y + wf_rng.randf_range(-wf_cell * 0.40, wf_cell * 0.40)
		var surf_y := sample_height(jx, jz)
		var r_w := wf_rng.randf()
		var arch := 2 if r_w < 0.52 else (3 if r_w < 0.80 else (8 if r_w < 0.90 else (4 if r_w < 0.96 else 6)))
		if _try_place_tree(jx, jz, 8.8, 0.78, arch, wf_rng, placed_positions, placed_trees, true, 8.0):
			wf_added += 1

	# Pass 6: Distant Continent Woodlands (Skeleton Crypt Moorland Hills, Rat Ruins Ring & Western Trail Corridor)
	var cont_rng := RandomNumberGenerator.new()
	cont_rng.seed = tree_seed + 1103
	var rat_ruins_hub := Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 44.0)
	var biome_hubs: Array = [
		[WorldLandmarks.SKEL_CAVE_MOUTH, 28.0, 145.0, 14.5, 58],
		[rat_ruins_hub, 56.0, 162.0, 12.5, 92],
		[Vector2(-520.0, 315.0), 12.0, 110.0, 18.0, 36],
	]
	for hub in biome_hubs:
		var hc: Vector2 = hub[0]
		var r_min: float = float(hub[1])
		var r_max: float = float(hub[2])
		var h_cell: float = float(hub[3])
		var h_cap: int = int(hub[4])
		var h_grid := int(ceil(r_max / h_cell))
		var h_cells: Array[Vector2] = []
		for gx in range(-h_grid, h_grid + 1):
			for gz in range(-h_grid, h_grid + 1):
				var off := Vector2(float(gx) * h_cell, float(gz) * h_cell)
				var d := off.length()
				if d < r_min or d > r_max:
					continue
				h_cells.append(hc + off)
		for i in range(h_cells.size() - 1, 0, -1):
			var j := cont_rng.randi_range(0, i)
			var tmp := h_cells[i]
			h_cells[i] = h_cells[j]
			h_cells[j] = tmp
		var added_h := 0
		for cell_base in h_cells:
			if added_h >= h_cap:
				break
			var jx := cell_base.x + cont_rng.randf_range(-h_cell * 0.42, h_cell * 0.42)
			var jz := cell_base.y + cont_rng.randf_range(-h_cell * 0.42, h_cell * 0.42)
			# Keep Skeleton Crypt south causeway vista & Rat Warren south trail unobstructed
			if hc == WorldLandmarks.SKEL_CAVE_MOUTH and absf(jx - hc.x) < 18.0 and jz > 322.0:
				continue
			if hc == rat_ruins_hub and absf(jx - hc.x) < 16.0 and jz > 409.0 and jz < 525.0:
				continue
			var surf_y := sample_height(jx, jz)
			if hc == rat_ruins_hub and surf_y < WorldLandmarks.RAT_SWAMP_WATER_Y - 0.28:
				continue
			var grove_n := _noise.get_noise_2d(jx * 0.015 + 75.0, jz * 0.015 - 40.0) * 0.5 + 0.5
			if grove_n < (0.26 if hc == rat_ruins_hub else 0.34):
				continue
			var r_p := cont_rng.randf()
			var arch := 2 if r_p < 0.45 else (3 if r_p < 0.72 else (8 if r_p < 0.85 else (1 if r_p < 0.94 else 4)))
			if hc == rat_ruins_hub:
				arch = 8 if r_p < 0.40 else (0 if r_p < 0.68 else (1 if r_p < 0.88 else (4 if r_p < 0.95 else 6)))
			if _try_place_tree(jx, jz, 10.5, 0.82, arch, cont_rng, placed_positions, placed_trees, true, 8.0):
				added_h += 1

	_cached_tree_data = placed_trees
	if not Engine.is_editor_hint() and not tcache_path.is_empty():
		var dir_abs := ProjectSettings.globalize_path(tcache_path.get_base_dir())
		DirAccess.make_dir_recursive_absolute(dir_abs)
		if DirAccess.dir_exists_absolute(dir_abs):
			var f_out := FileAccess.open(tcache_path, FileAccess.WRITE)
			if f_out != null:
				f_out.store_var({"sig": tcache_sig, "trees": placed_trees, "spider": _spider_forest_trees}, false)
				f_out.close()
	return placed_trees


func _build_trees(trees_node: Node3D) -> void:
	var mm_nodes: Array[MultiMeshInstance3D] = []
	for node_name in TREE_NODE_NAMES:
		var mm_node := trees_node.get_node_or_null(node_name) as MultiMeshInstance3D
		if mm_node == null:
			mm_node = MultiMeshInstance3D.new()
			mm_node.name = node_name
			trees_node.add_child(mm_node)
		mm_nodes.append(mm_node)

	if Engine.is_editor_hint() and not preview_trees_in_editor:
		for n in mm_nodes:
			n.multimesh = null
		var existing_tc := trees_node.get_node_or_null("TrunkColliders")
		if existing_tc != null:
			existing_tc.queue_free()
		return

	var colliders_node := trees_node.get_node_or_null("TrunkColliders") as StaticBody3D
	if colliders_node == null:
		colliders_node = StaticBody3D.new()
		colliders_node.name = "TrunkColliders"
		colliders_node.collision_layer = 4
		colliders_node.collision_mask = 0
		var ph_cs := CollisionShape3D.new()
		var ph_box := BoxShape3D.new()
		ph_box.size = Vector3(0.01, 0.01, 0.01)
		ph_cs.shape = ph_box
		ph_cs.disabled = true
		colliders_node.add_child(ph_cs)
		trees_node.add_child(colliders_node)
	else:
		colliders_node.collision_layer = 4

	var tree_data := build_tree_data()
	var grouped_xforms: Array[Array] = []
	for _i in range(TREE_ASSET_PATHS.size()):
		grouped_xforms.append([])

	for t in tree_data:
		var arch: int = t.archetype
		if arch >= 0 and arch < grouped_xforms.size():
			grouped_xforms[arch].append(t.transform)

	var vis_3d := 115.0
	var vis_impostor := 420.0
	if not Engine.is_editor_hint():
		var settings_t := SlimeSettings.get_or_create()
		if settings_t != null:
			var q_idx_t := clampi(int(settings_t.get_value("graphics", "quality_preset", 0)), 0, SlimeSettings.QUALITY_PRESETS.size() - 1)
			var preset_t: Dictionary = SlimeSettings.QUALITY_PRESETS[q_idx_t]
			vis_3d = float(preset_t.get("vis_trees_3d", 115.0))
			vis_impostor = float(preset_t.get("vis_trees", 420.0))

	for a in range(TREE_ASSET_PATHS.size()):
		var node: MultiMeshInstance3D = mm_nodes[a]
		var mesh := _get_tree_mesh(a)
		for ch in node.get_children():
			if ch.name.begins_with("ImpostorChunk_"):
				node.remove_child(ch)
				ch.queue_free()
		_build_chunked_multimeshes(node, mesh, grouped_xforms[a], vis_3d, 10.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, null, 72.0, 12.0, "Chunk_", 0.0, 0.0)

	# Merged single-draw-call impostor chunks across all 9 tree archetypes via Texture2DArray + INSTANCE_CUSTOM
	var imp_holder := trees_node.get_node_or_null("ImpostorForest") as MultiMeshInstance3D
	if imp_holder == null:
		imp_holder = MultiMeshInstance3D.new()
		imp_holder.name = "ImpostorForest"
		trees_node.add_child(imp_holder)
	var imp_mesh := _get_merged_tree_impostor_mesh()
	if imp_mesh != null:
		var all_imp_xforms: Array[Transform3D] = []
		var all_imp_custom: Array[Color] = []
		for t in tree_data:
			var arch: int = t.archetype
			if arch < 0 or arch >= TREE_ASSET_PATHS.size():
				continue
			var dims := _get_tree_impostor_dims(arch)
			all_imp_xforms.append(t.transform)
			all_imp_custom.append(Color(float(arch), dims.x, dims.y, dims.z))
		_build_chunked_multimeshes(imp_holder, imp_mesh, all_imp_xforms, vis_impostor, 25.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, null, 72.0, 12.0, "ImpostorChunk_", vis_3d, 10.0, all_imp_custom)

	_collect_tree_chunks(trees_node)
	_update_tree_shadow_cull(Vector3(_grass_center.x, 22.0, _grass_center.y))

	# Physical trunk and root flare collision (registered directly via PhysicsServer3D without SceneTree nodes)
	if colliders_node != null:
		var body_rid := colliders_node.get_rid()
		var base_shape_idx := 0
		# Preserve any disabled editor placeholder CollisionShape3D if present
		for c in colliders_node.get_children():
			if c is CollisionShape3D:
				base_shape_idx += 1
		if base_shape_idx == 0:
			PhysicsServer3D.body_clear_shapes(body_rid)
		_tree_collider_shapes.clear()
		_tree_trunk_body_rid = body_rid

		if not Engine.is_editor_hint():
			for t_idx in range(tree_data.size()):
				var t: Dictionary = tree_data[t_idx]
				var sy: float = t.scale_y
				var sxz: float = t.scale_xz
				var pos: Vector3 = t.position
				t["shape_idx"] = base_shape_idx + t_idx * 2

				# 1. Base root flare cylinder (protects ground-level roots from clipping)
				var cyl_base := CylinderShape3D.new()
				cyl_base.radius = 0.90 * sxz
				cyl_base.height = 1.6 * sy
				_tree_collider_shapes.append(cyl_base)
				PhysicsServer3D.body_add_shape(body_rid, cyl_base.get_rid(), Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.8 * sy, 0.0)))

				# 2. Main trunk cylinder
				var cyl_trunk := CylinderShape3D.new()
				cyl_trunk.radius = 0.60 * sxz
				cyl_trunk.height = 6.5 * sy
				_tree_collider_shapes.append(cyl_trunk)
				PhysicsServer3D.body_add_shape(body_rid, cyl_trunk.get_rid(), Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 3.25 * sy, 0.0)))


func _ensure_tree_eat_grid() -> void:
	if _tree_eat_grid_built:
		return
	_tree_eat_grid_built = true
	_tree_eat_grid.clear()
	for i in range(_cached_tree_data.size()):
		var t: Dictionary = _cached_tree_data[i]
		var pos: Vector3 = t.position
		var cell := Vector2i(int(floor(pos.x / 32.0)), int(floor(pos.z / 32.0)))
		if not _tree_eat_grid.has(cell):
			_tree_eat_grid[cell] = []
		(_tree_eat_grid[cell] as Array).append(i)


func _hide_tree_multimesh_instance(tree_pos: Vector3, arch: int) -> void:
	var trees_node := get_node_or_null("Trees")
	if trees_node == null:
		return
	if arch < 0 or arch >= TREE_NODE_NAMES.size():
		return
	var type_node := trees_node.get_node_or_null(TREE_NODE_NAMES[arch])
	if type_node == null:
		return
	var zero_xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -9999.0, 0.0))
	for ch in type_node.get_children():
		if ch is MultiMeshInstance3D and ch.name.begins_with("Chunk_"):
			var mmi := ch as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null:
				continue
			for idx in range(mm.instance_count):
				var xf := mm.get_instance_transform(idx)
				var world_o := mmi.position + xf.origin
				if absf(world_o.x - tree_pos.x) < 0.08 and absf(world_o.z - tree_pos.z) < 0.08:
					mm.set_instance_transform(idx, zero_xf)
					break
	var imp_holder := trees_node.get_node_or_null("ImpostorForest")
	if imp_holder != null:
		for ch in imp_holder.get_children():
			if ch is MultiMeshInstance3D and ch.name.begins_with("ImpostorChunk_"):
				var mmi := ch as MultiMeshInstance3D
				var mm := mmi.multimesh
				if mm == null:
					continue
				for idx in range(mm.instance_count):
					var xf := mm.get_instance_transform(idx)
					var world_o := mmi.position + xf.origin
					if absf(world_o.x - tree_pos.x) < 0.08 and absf(world_o.z - tree_pos.z) < 0.08:
						mm.set_instance_transform(idx, zero_xf)
						return


func try_eat_nearby_trees(slime: Node3D, props_sys: Node) -> int:
	if slime == null or not is_instance_valid(slime):
		return 0
	var sl_scale: float = float(slime.get("slime_scale"))
	if sl_scale < 1.65:
		return 0
	_ensure_tree_eat_grid()
	var sp := slime.global_position
	var sl_vol: float = float(slime.call("get_volume"))
	var sl_h: float = 2.55 * sl_scale
	var vis_r: float = 2.0 * sl_scale * 1.15
	var reach := vis_r + 1.4
	var c0 := Vector2i(int(floor(sp.x / 32.0)), int(floor(sp.z / 32.0)))
	var span := int(ceil(reach / 32.0)) + 1
	var eaten_now := 0
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var bucket: Variant = _tree_eat_grid.get(Vector2i(c0.x + dx, c0.y + dz))
			if bucket == null:
				continue
			for ti in (bucket as Array):
				var t: Dictionary = _cached_tree_data[int(ti)]
				if bool(t.get("eaten", false)):
					continue
				var tpos: Vector3 = t.position
				if Vector2(tpos.x - sp.x, tpos.z - sp.z).length() > reach:
					continue
				var sy: float = t.scale_y
				var sxz: float = t.scale_xz
				var tree_vol := 14.0 * sxz * sxz * sy
				if sl_vol < tree_vol / 0.85 or sl_h < 2.6 * sy:
					continue
				t["eaten"] = true
				if _tree_trunk_body_rid.is_valid() and t.has("shape_idx"):
					var sidx := int(t["shape_idx"])
					PhysicsServer3D.body_set_shape_disabled(_tree_trunk_body_rid, sidx, true)
					PhysicsServer3D.body_set_shape_disabled(_tree_trunk_body_rid, sidx + 1, true)
				var arch: int = int(t.archetype)
				_hide_tree_multimesh_instance(tpos, arch)
				if props_sys != null and props_sys.has_method("spawn_transient_eat_visual"):
					props_sys.call("spawn_transient_eat_visual", _get_tree_mesh(arch), t.transform, slime)
				if props_sys != null and props_sys.has_method("record_external_eat"):
					props_sys.call("record_external_eat", 1)
				if slime.has_method("add_volume"):
					slime.call("add_volume", tree_vol)
				eaten_now += 1
	return eaten_now


# ==============================================================================
# DETERMINISTIC ROCKS & STONES (Stylized Nature MegaKit Assets)
# ==============================================================================

const ROCK_ASSET_PATHS := [
	"res://assets/nature/Rock_Medium_1.gltf",
	"res://assets/nature/Rock_Medium_2.gltf"
]

var _cached_rock_meshes: Array[Mesh] = []
var _cached_rock_convex_shapes: Array[ConvexPolygonShape3D] = []
var _tree_collider_shapes: Array[Shape3D] = []
var _rock_collider_shapes: Array[Shape3D] = []


func _get_rock_convex_shape(archetype: int) -> ConvexPolygonShape3D:
	if _cached_rock_convex_shapes.is_empty():
		for i in range(ROCK_ASSET_PATHS.size()):
			var m := _get_rock_mesh(i)
			if m != null:
				var conv := m.create_convex_shape(true, true)
				_cached_rock_convex_shapes.append(conv)
			else:
				_cached_rock_convex_shapes.append(null)
	if archetype >= 0 and archetype < _cached_rock_convex_shapes.size():
		return _cached_rock_convex_shapes[archetype]
	return null


func _get_rock_mesh(archetype: int) -> Mesh:
	if _cached_rock_meshes.is_empty():
		var rock_tex: Texture2D = load("res://assets/nature/Rocks_Diffuse.png")
		var rock_mat := StandardMaterial3D.new()
		rock_mat.albedo_texture = rock_tex
		rock_mat.roughness = 0.94
		rock_mat.cull_mode = BaseMaterial3D.CULL_BACK
		rock_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

		for i in range(ROCK_ASSET_PATHS.size()):
			var path: String = ROCK_ASSET_PATHS[i]
			var sc: PackedScene = load(path)
			if sc != null:
				var inst: Node = sc.instantiate()
				var found_mesh: Mesh = null
				for c in inst.get_children():
					if c is MeshInstance3D and c.mesh != null:
						found_mesh = c.mesh.duplicate()
						break
				inst.free()
				if found_mesh != null:
					found_mesh.surface_set_material(0, rock_mat)
				_cached_rock_meshes.append(found_mesh)
			else:
				_cached_rock_meshes.append(null)

	if archetype >= 0 and archetype < _cached_rock_meshes.size():
		return _cached_rock_meshes[archetype]
	return null


## 100% Deterministic Rock & Boulder Placement across the island.
## Rocks spawn on steeper slopes and ridge lines, mutually excluded from trees.
func build_rock_data() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed

	var target_count := editor_rock_count if Engine.is_editor_hint() else rock_count
	if not enable_rocks or target_count <= 0:
		return []

	var rcache_sig := ""
	var rcache_path := ""
	if not Engine.is_editor_hint():
		rcache_sig = "rk_v1|%d|%d|%d|%.1f|%s|%s" % [
			terrain_seed, rock_seed, target_count, rock_spawn_radius,
			str(enable_cave), str(_webwood_layout)
		]
		rcache_path = "user://cache/rocks_%s.dat" % rcache_sig.md5_text().left(12)
		if FileAccess.file_exists(rcache_path):
			var f_in := FileAccess.open(rcache_path, FileAccess.READ)
			if f_in != null:
				var d = f_in.get_var(false)
				f_in.close()
				if d is Dictionary and String(d.get("sig", "")) == rcache_sig:
					var typed_r: Array[Dictionary] = []
					typed_r.assign(d.get("rocks", []))
					return typed_r

	# Obtain tree positions for mutual exclusion (rocks must never spawn inside trees)
	var tree_data := _cached_tree_data if not _cached_tree_data.is_empty() else build_tree_data()
	var tree_positions: Array[Vector3] = []
	for t in tree_data:
		tree_positions.append(t.position)

	var placed_rocks: Array[Dictionary] = []
	var cell_size := 12.0
	var grid_radius := int(ceil(rock_spawn_radius / cell_size))
	var candidate_cells: Array[Vector2i] = []

	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var d := Vector2(gx * cell_size, gz * cell_size).length()
			if d > rock_spawn_radius or d < rock_clearing_radius:
				continue
			candidate_cells.append(Vector2i(gx, gz))

	# Deterministic shuffle
	for i in range(candidate_cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidate_cells[i]
		candidate_cells[i] = candidate_cells[j]
		candidate_cells[j] = tmp

	for cell in candidate_cells:
		if placed_rocks.size() >= target_count:
			break

		var ox := rng.randf_range(-cell_size * 0.45, cell_size * 0.45)
		var oz := rng.randf_range(-cell_size * 0.45, cell_size * 0.45)
		var x := cell.x * cell_size + ox
		var z := cell.y * cell_size + oz

		var dist := Vector2(x, z).length()
		if dist < rock_clearing_radius or dist > rock_spawn_radius:
			continue
		if enable_cave and (CaveSystem.is_in_portal_scatter_exclusion(x, z, false) or is_point_in_cave_cutout(x, z)):
			continue
		if VillageBuilder.is_in_village_exclusion(x, z, false):
			continue
		if WorldLandmarks.is_in_landmark_exclusion(x, z, false):
			continue

		# Exact terrain surface query (replaces rough sample_height / sample_normal)
		var surf := sample_surface_exact(x, z)
		var y := surf.w
		var normal := Vector3(surf.x, surf.y, surf.z)

		if y < rock_min_height or y > rock_max_height:
			continue
		if normal.y < min_rock_normal_y:
			continue

		# Masked Scatter: Rocks spawn on steeper slopes (normal.y <= 0.94) and ridge lines.
		# Flat lush meadow ground (normal.y > 0.94 without ridge) is reserved for vegetation.
		var ridge_val: float = 1.0 - absf(_noise.get_noise_2d(x * 0.015 + 40.0, z * 0.015 - 70.0))
		var is_steep: bool = normal.y <= 0.94
		var is_ridge: bool = ridge_val >= 0.62
		if not (is_steep or is_ridge):
			continue

		# Mutual exclusion: ensure rocks do not spawn inside trees (minimum 5.5m distance)
		var collides_with_tree := false
		for tp in tree_positions:
			var tdx: float = tp.x - x
			var tdz: float = tp.z - z
			if (tdx * tdx + tdz * tdz) < 30.25: # 5.5m squared
				collides_with_tree = true
				break
		if collides_with_tree:
			continue

		# Spacing check against existing rocks
		var too_close := false
		for rk in placed_rocks:
			var dx: float = rk.position.x - x
			var dz: float = rk.position.z - z
			if (dx * dx + dz * dz) < (min_rock_spacing * min_rock_spacing):
				too_close = true
				break
		if too_close:
			continue

		var archetype := rng.randi_range(0, 1)
		var scale_factor := rng.randf_range(1.5, 3.2)
		var sxz := scale_factor
		var sy := scale_factor * rng.randf_range(0.85, 1.2)

		var yaw := rng.randf_range(0.0, TAU)
		var pitch := rng.randf_range(-0.12, 0.12)
		var roll := rng.randf_range(-0.12, 0.12)

		# Grounding: embed -0.18m * sy into terrain so rocks never hover on slopes
		var pos := Vector3(x, y - 0.18 * sy, z)

		# Surface normal alignment: 60% skyward, 40% slope normal
		var up := (Vector3.UP * 0.60 + normal * 0.40).normalized()
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := up.cross(fwd).normalized()
		fwd = right.cross(up).normalized()

		var basis := Basis(right * sxz, up * sy, fwd * sxz)
		basis = basis.rotated(right, pitch).rotated(fwd, roll)
		var t := Transform3D(basis, pos)

		placed_rocks.append({
			"archetype": archetype,
			"position": pos,
			"scale_xz": sxz,
			"scale_y": sy,
			"transform": t
		})

	# Pass 2: Coastal Headland Boulders & Seaside Hillside Outcrops around Slimebrook / Cove
	var coast_rock_rng := RandomNumberGenerator.new()
	coast_rock_rng.seed = rock_seed + 733
	var vc_r := Vector2(VillageBuilder.VILLAGE_CENTER.x, VillageBuilder.VILLAGE_CENTER.z)
	var cr_cell := 11.5
	var cr_max := 295.0
	var cr_grid := int(ceil(cr_max / cr_cell))
	var cr_cells: Array[Vector2] = []
	for gx in range(-cr_grid, cr_grid + 1):
		for gz in range(-cr_grid, cr_grid + 1):
			var off := Vector2(float(gx) * cr_cell, float(gz) * cr_cell)
			var d := off.length()
			if d < 110.0 or d > cr_max:
				continue
			cr_cells.append(vc_r + off)
	for i in range(cr_cells.size() - 1, 0, -1):
		var j := coast_rock_rng.randi_range(0, i)
		var tmp := cr_cells[i]
		cr_cells[i] = cr_cells[j]
		cr_cells[j] = tmp

	var coast_rocks_added := 0
	for cell_w in cr_cells:
		if coast_rocks_added >= 130:
			break
		var x := cell_w.x + coast_rock_rng.randf_range(-cr_cell * 0.45, cr_cell * 0.45)
		var z := cell_w.y + coast_rock_rng.randf_range(-cr_cell * 0.45, cr_cell * 0.45)
		if VillageBuilder.is_in_village_exclusion(x, z, false):
			continue
		if WorldLandmarks.is_in_landmark_exclusion(x, z, false):
			continue
		var surf := sample_surface_exact(x, z)
		var y := surf.w
		var normal := Vector3(surf.x, surf.y, surf.z)
		if y < -0.5 or y > 55.0 or normal.y < 0.45:
			continue
		# Favor coastal shoreline shelves (y < 9m) and hilltop ridges
		var is_shore_boulder := y < 8.5 and coast_rock_rng.randf() < 0.65
		var is_hill_outcrop := y >= 8.5 and (normal.y <= 0.94 or (1.0 - absf(_noise.get_noise_2d(x * 0.014 + 30.0, z * 0.014 - 50.0))) >= 0.62)
		if not (is_shore_boulder or is_hill_outcrop):
			continue
		var hits_tree := false
		for tp in tree_positions:
			var tdx := tp.x - x
			var tdz := tp.z - z
			if tdx * tdx + tdz * tdz < 30.25:
				hits_tree = true
				break
		if hits_tree:
			continue
		var too_close := false
		for rk in placed_rocks:
			var dx: float = rk.position.x - x
			var dz: float = rk.position.z - z
			if dx * dx + dz * dz < 144.0:
				too_close = true
				break
		if too_close:
			continue

		var archetype := coast_rock_rng.randi_range(0, 1)
		var scale_factor := coast_rock_rng.randf_range(1.6, 3.6) if y < 6.0 else coast_rock_rng.randf_range(1.4, 2.8)
		var sxz := scale_factor
		var sy := scale_factor * coast_rock_rng.randf_range(0.75, 1.15)
		var yaw := coast_rock_rng.randf_range(0.0, TAU)
		var pitch := coast_rock_rng.randf_range(-0.14, 0.14)
		var roll := coast_rock_rng.randf_range(-0.14, 0.14)
		var pos := Vector3(x, y - 0.24 * sy, z)
		var up := (Vector3.UP * 0.65 + normal * 0.35).normalized()
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := up.cross(fwd).normalized()
		fwd = right.cross(up).normalized()
		var basis := Basis(right * sxz, up * sy, fwd * sxz).rotated(right, pitch).rotated(fwd, roll)
		placed_rocks.append({
			"archetype": archetype,
			"position": pos,
			"scale_xz": sxz,
			"scale_y": sy,
			"transform": Transform3D(basis, pos)
		})
		coast_rocks_added += 1

	# Pass 3: Highland & Moorland Boulders around Wolf Crag, Rat Warren, Webwood & Skeleton Crypt Ridges
	var high_rock_rng := RandomNumberGenerator.new()
	high_rock_rng.seed = rock_seed + 977
	var rock_hubs: Array = [
		[WorldLandmarks.WOLF_CRAG_CENTER, 22.0, 125.0, 13.0, 56],
		[Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 44.0), 56.0, 150.0, 14.5, 38],
		[WorldLandmarks.SPIDER_FOREST_CENTER, 24.0, 158.0, 16.0, 42],
		[WorldLandmarks.SKEL_CAVE_MOUTH, 30.0, 120.0, 16.0, 28],
	]
	for rhub in rock_hubs:
		var hc: Vector2 = rhub[0]
		var r_min: float = float(rhub[1])
		var r_max: float = float(rhub[2])
		var r_cell: float = float(rhub[3])
		var r_cap: int = int(rhub[4])
		var r_grid := int(ceil(r_max / r_cell))
		var cells_h: Array[Vector2] = []
		for gx in range(-r_grid, r_grid + 1):
			for gz in range(-r_grid, r_grid + 1):
				var off := Vector2(float(gx) * r_cell, float(gz) * r_cell)
				var d := off.length()
				if d < r_min or d > r_max:
					continue
				cells_h.append(hc + off)
		for i in range(cells_h.size() - 1, 0, -1):
			var j := high_rock_rng.randi_range(0, i)
			var tmp := cells_h[i]
			cells_h[i] = cells_h[j]
			cells_h[j] = tmp
		var added_r := 0
		for cell_w in cells_h:
			if added_r >= r_cap:
				break
			var x := cell_w.x + high_rock_rng.randf_range(-r_cell * 0.42, r_cell * 0.42)
			var z := cell_w.y + high_rock_rng.randf_range(-r_cell * 0.42, r_cell * 0.42)
			if WorldLandmarks.is_in_landmark_exclusion(x, z, false):
				continue
			var surf := sample_surface_exact(x, z)
			var y := surf.w
			var normal := Vector3(surf.x, surf.y, surf.z)
			if y < 6.0 or y > 135.0 or normal.y < 0.44:
				continue
			var ridge_n: float = 1.0 - absf(_noise.get_noise_2d(x * 0.015 + 40.0, z * 0.015 - 70.0))
			if normal.y > 0.94 and ridge_n < 0.56:
				continue
			var hits_tree := false
			for tp in tree_positions:
				var tdx := tp.x - x
				var tdz := tp.z - z
				if tdx * tdx + tdz * tdz < 30.25:
					hits_tree = true
					break
			if hits_tree:
				continue
			var too_close := false
			for rk in placed_rocks:
				var dx: float = rk.position.x - x
				var dz: float = rk.position.z - z
				if dx * dx + dz * dz < 100.0:
					too_close = true
					break
			if too_close:
				continue
			var archetype := high_rock_rng.randi_range(0, 1)
			var scale_factor := high_rock_rng.randf_range(1.6, 3.2)
			var sxz := scale_factor
			var sy := scale_factor * high_rock_rng.randf_range(0.75, 1.18)
			var yaw := high_rock_rng.randf_range(0.0, TAU)
			var pos := Vector3(x, y - 0.24 * sy, z)
			var up := (Vector3.UP * 0.65 + normal * 0.35).normalized()
			var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
			var right := up.cross(fwd).normalized()
			fwd = right.cross(up).normalized()
			var basis := Basis(right * sxz, up * sy, fwd * sxz)
			placed_rocks.append({
				"archetype": archetype,
				"position": pos,
				"scale_xz": sxz,
				"scale_y": sy,
				"transform": Transform3D(basis, pos)
			})
			added_r += 1

	if not Engine.is_editor_hint() and not rcache_path.is_empty():
		var dir_abs := ProjectSettings.globalize_path(rcache_path.get_base_dir())
		DirAccess.make_dir_recursive_absolute(dir_abs)
		if DirAccess.dir_exists_absolute(dir_abs):
			var f_out := FileAccess.open(rcache_path, FileAccess.WRITE)
			if f_out != null:
				f_out.store_var({"sig": rcache_sig, "rocks": placed_rocks}, false)
				f_out.close()
	return placed_rocks


func _build_rocks(rocks_node: Node3D) -> void:
	var rock1_node := rocks_node.get_node_or_null("Rock1") as MultiMeshInstance3D
	var rock2_node := rocks_node.get_node_or_null("Rock2") as MultiMeshInstance3D
	var colliders_node := rocks_node.get_node_or_null("RockColliders") as StaticBody3D

	if rock1_node == null:
		rock1_node = MultiMeshInstance3D.new()
		rock1_node.name = "Rock1"
		rocks_node.add_child(rock1_node)
	if rock2_node == null:
		rock2_node = MultiMeshInstance3D.new()
		rock2_node.name = "Rock2"
		rocks_node.add_child(rock2_node)

	if Engine.is_editor_hint() and not preview_rocks_in_editor:
		if rock1_node: rock1_node.multimesh = null
		if rock2_node: rock2_node.multimesh = null
		if colliders_node != null:
			colliders_node.queue_free()
		return

	if colliders_node == null:
		colliders_node = StaticBody3D.new()
		colliders_node.name = "RockColliders"
		colliders_node.collision_layer = 4
		colliders_node.collision_mask = 0
		var ph_cs := CollisionShape3D.new()
		var ph_box := BoxShape3D.new()
		ph_box.size = Vector3(0.01, 0.01, 0.01)
		ph_cs.shape = ph_box
		ph_cs.disabled = true
		colliders_node.add_child(ph_cs)
		rocks_node.add_child(colliders_node)
	else:
		colliders_node.collision_layer = 4

	var rock_data := build_rock_data()
	var grouped_xforms: Array[Array] = [[], []]

	for r in rock_data:
		var arch: int = r.archetype
		if arch >= 0 and arch < 2:
			grouped_xforms[arch].append(r.transform)

	var mm_nodes := [rock1_node, rock2_node]
	for a in range(2):
		var node: MultiMeshInstance3D = mm_nodes[a]
		if node == null:
			continue
		var mesh := _get_rock_mesh(a)
		_build_chunked_multimeshes(node, mesh, grouped_xforms[a], 115.0, 20.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, null, 112.0, 6.0)

	# Physical rock collision (exact convex hull matching rock facets, via PhysicsServer3D)
	if colliders_node != null:
		var body_rid := colliders_node.get_rid()
		PhysicsServer3D.body_clear_shapes(body_rid)
		_rock_collider_shapes.clear()

		if not Engine.is_editor_hint():
			for r in rock_data:
				var conv_shape := _get_rock_convex_shape(r.archetype)
				if conv_shape != null:
					_rock_collider_shapes.append(conv_shape)
					PhysicsServer3D.body_add_shape(body_rid, conv_shape.get_rid(), r.transform)
				else:
					var cyl := CylinderShape3D.new()
					var sy: float = r.scale_y
					var sxz: float = r.scale_xz
					cyl.radius = 1.75 * sxz
					cyl.height = 2.2 * sy
					_rock_collider_shapes.append(cyl)
					PhysicsServer3D.body_add_shape(body_rid, cyl.get_rid(), Transform3D(Basis.IDENTITY, r.position + Vector3(0.0, 1.1 * sy, 0.0)))


# ==============================================================================
# DETERMINISTIC VEGETATION (Stylized Nature MegaKit Assets)
# ==============================================================================

const VEGETATION_ASSET_PATHS := [
	"res://assets/nature/Bush_Common.gltf",
	"res://assets/nature/Plant_1.gltf",
	"res://assets/nature/Flower_3_Group.gltf"
]

var _cached_vegetation_meshes: Array[Mesh] = []


func _get_vegetation_mesh(archetype: int) -> Mesh:
	if _cached_vegetation_meshes.is_empty():
		var bush_tex: Texture2D = load("res://assets/nature/Leaves_TwistedTree_C.png")
		var leaves_tex: Texture2D = load("res://assets/nature/Leaves.png")
		var flowers_tex: Texture2D = load("res://assets/nature/Flowers.png")

		# Bush Material
		var bush_mat := StandardMaterial3D.new()
		bush_mat.albedo_texture = bush_tex
		bush_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		bush_mat.alpha_scissor_threshold = 0.45
		bush_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bush_mat.roughness = 0.85
		bush_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

		# Leaves / Foliage Material
		var leaves_mat := StandardMaterial3D.new()
		leaves_mat.albedo_texture = leaves_tex
		leaves_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		leaves_mat.alpha_scissor_threshold = 0.45
		leaves_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaves_mat.roughness = 0.85
		leaves_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

		# Flower Petals Material
		var flowers_mat := StandardMaterial3D.new()
		flowers_mat.albedo_texture = flowers_tex
		flowers_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		flowers_mat.alpha_scissor_threshold = 0.45
		flowers_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		flowers_mat.roughness = 0.80
		flowers_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

		for i in range(VEGETATION_ASSET_PATHS.size()):
			var path: String = VEGETATION_ASSET_PATHS[i]
			var sc: PackedScene = load(path)
			if sc != null:
				var inst: Node = sc.instantiate()
				var found_mesh: Mesh = null
				for c in inst.get_children():
					if c is MeshInstance3D and c.mesh != null:
						found_mesh = c.mesh.duplicate()
						break
				inst.free()
				if found_mesh != null:
					if i == 0:
						found_mesh.surface_set_material(0, bush_mat)
					elif i == 1:
						found_mesh.surface_set_material(0, leaves_mat)
					elif i == 2:
						found_mesh.surface_set_material(0, leaves_mat)
						if found_mesh.get_surface_count() > 1:
							found_mesh.surface_set_material(1, flowers_mat)
				_cached_vegetation_meshes.append(found_mesh)
			else:
				_cached_vegetation_meshes.append(null)

	if archetype >= 0 and archetype < _cached_vegetation_meshes.size():
		return _cached_vegetation_meshes[archetype]
	return null


## 100% Deterministic Vegetation Placement across the island meadows.
func build_vegetation_data() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = vegetation_seed

	var target_count := editor_vegetation_count if Engine.is_editor_hint() else vegetation_count
	if not enable_vegetation or target_count <= 0:
		return []

	# Obtain tree positions for mutual exclusion (vegetation does not clip inside tree trunks)
	var tree_data := _cached_tree_data if not _cached_tree_data.is_empty() else build_tree_data()
	var tree_positions: Array[Vector3] = []
	for t in tree_data:
		tree_positions.append(t.position)

	var placed_veg: Array[Dictionary] = []
	var cell_size := 6.5
	var grid_radius := int(ceil(vegetation_spawn_radius / cell_size))
	var candidate_cells: Array[Vector2i] = []

	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var d := Vector2(gx * cell_size, gz * cell_size).length()
			if d > vegetation_spawn_radius or d < vegetation_clearing_radius:
				continue
			candidate_cells.append(Vector2i(gx, gz))

	# Deterministic shuffle
	for i in range(candidate_cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidate_cells[i]
		candidate_cells[i] = candidate_cells[j]
		candidate_cells[j] = tmp

	for cell in candidate_cells:
		if placed_veg.size() >= target_count:
			break

		var ox := rng.randf_range(-cell_size * 0.45, cell_size * 0.45)
		var oz := rng.randf_range(-cell_size * 0.45, cell_size * 0.45)
		var x := cell.x * cell_size + ox
		var z := cell.y * cell_size + oz

		var dist := Vector2(x, z).length()
		if dist < vegetation_clearing_radius or dist > vegetation_spawn_radius:
			continue
		if enable_cave and CaveSystem.is_in_portal_scatter_exclusion(x, z, false):
			continue
		if VillageBuilder.is_in_village_exclusion(x, z, false):
			continue
		if WorldLandmarks.is_in_landmark_exclusion(x, z, false):
			continue

		# Exact terrain surface query (replaces rough sample_height / sample_normal)
		var surf := sample_surface_exact(x, z)
		var y := surf.w
		var normal := Vector3(surf.x, surf.y, surf.z)

		# Moderate elevation (beach 4.0m to subalpine meadow 75.0m)
		if y < vegetation_min_height or y > 75.0:
			continue

		# Low/moderate slopes (< 30°): normal.y >= 0.866
		if normal.y < 0.866:
			continue

		# Mutual exclusion against trees (cannot spawn directly inside tree trunk)
		var collides_with_tree := false
		for tp in tree_positions:
			var tdx: float = tp.x - x
			var tdz: float = tp.z - z
			if (tdx * tdx + tdz * tdz) < 7.84: # 2.8m squared
				collides_with_tree = true
				break
		if collides_with_tree:
			continue

		# Spacing check against existing vegetation
		var too_close := false
		for v in placed_veg:
			var dx: float = v.position.x - x
			var dz: float = v.position.z - z
			if (dx * dx + dz * dz) < (min_vegetation_spacing * min_vegetation_spacing):
				too_close = true
				break
		if too_close:
			continue

		# Archetype: 0 = Bush (40%), 1 = Plant (30%), 2 = Wildflowers (30%)
		var pick := rng.randf()
		var archetype := 0
		var scale_val := 1.0
		if pick < 0.40:
			archetype = 0
			scale_val = rng.randf_range(1.2, 2.4)
		elif pick < 0.70:
			archetype = 1
			scale_val = rng.randf_range(0.9, 1.7)
		else:
			archetype = 2
			scale_val = rng.randf_range(1.1, 2.2)

		var yaw := rng.randf_range(0.0, TAU)

		# Grounding: root burial -0.12m so shrubs never hover
		var pos := Vector3(x, y - 0.12, z)

		# Surface normal alignment: phototropic upright bias (80% skyward, 20% terrain normal)
		var up := (Vector3.UP * 0.80 + normal * 0.20).normalized()
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := up.cross(fwd).normalized()
		fwd = right.cross(up).normalized()

		var basis := Basis(right * scale_val, up * scale_val, fwd * scale_val)
		var t := Transform3D(basis, pos)

		placed_veg.append({
			"archetype": archetype,
			"position": pos,
			"scale": scale_val,
			"transform": t
		})

	# Pass 2: Seaside Meadow, Road Verge & Dune Scrub Vegetation around Slimebrook / Cove
	var coast_veg_rng := RandomNumberGenerator.new()
	coast_veg_rng.seed = vegetation_seed + 521
	var vc_v := Vector2(VillageBuilder.VILLAGE_CENTER.x, VillageBuilder.VILLAGE_CENTER.z)
	var cv_cell := 6.5
	var cv_max := 285.0
	var cv_grid := int(ceil(cv_max / cv_cell))
	var cv_cells: Array[Vector2] = []
	for gx in range(-cv_grid, cv_grid + 1):
		for gz in range(-cv_grid, cv_grid + 1):
			var off := Vector2(float(gx) * cv_cell, float(gz) * cv_cell)
			var d := off.length()
			if d < 108.0 or d > cv_max:
				continue
			cv_cells.append(vc_v + off)
	for i in range(cv_cells.size() - 1, 0, -1):
		var j := coast_veg_rng.randi_range(0, i)
		var tmp := cv_cells[i]
		cv_cells[i] = cv_cells[j]
		cv_cells[j] = tmp

	var coast_veg_added := 0
	for cell_w in cv_cells:
		if coast_veg_added >= 380:
			break
		var x := cell_w.x + coast_veg_rng.randf_range(-cv_cell * 0.45, cv_cell * 0.45)
		var z := cell_w.y + coast_veg_rng.randf_range(-cv_cell * 0.45, cv_cell * 0.45)
		if VillageBuilder.is_in_village_exclusion(x, z, false):
			continue
		if WorldLandmarks.is_in_landmark_exclusion(x, z, false):
			continue
		var surf := sample_surface_exact(x, z)
		var y := surf.w
		var normal := Vector3(surf.x, surf.y, surf.z)
		if y < 5.6 or y > 55.0 or normal.y < 0.84:
			continue
		var hits_tree := false
		for tp in tree_positions:
			var tdx := tp.x - x
			var tdz := tp.z - z
			if tdx * tdx + tdz * tdz < 7.84:
				hits_tree = true
				break
		if hits_tree:
			continue
		var too_close := false
		for v in placed_veg:
			var dx: float = v.position.x - x
			var dz: float = v.position.z - z
			if dx * dx + dz * dz < 16.0:
				too_close = true
				break
		if too_close:
			continue

		var pick := coast_veg_rng.randf()
		var archetype := 0 if pick < 0.48 else (1 if pick < 0.78 else 2)
		var scale_val := coast_veg_rng.randf_range(1.2, 2.3) if archetype == 0 else coast_veg_rng.randf_range(1.0, 2.0)
		var yaw := coast_veg_rng.randf_range(0.0, TAU)
		var pos := Vector3(x, y - 0.12, z)
		var up := (Vector3.UP * 0.80 + normal * 0.20).normalized()
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := up.cross(fwd).normalized()
		fwd = right.cross(up).normalized()
		var basis := Basis(right * scale_val, up * scale_val, fwd * scale_val)
		placed_veg.append({
			"archetype": archetype,
			"position": pos,
			"scale": scale_val,
			"transform": Transform3D(basis, pos)
		})
		coast_veg_added += 1

	return placed_veg


func _build_vegetation(veg_node: Node3D) -> void:
	var bush_node := veg_node.get_node_or_null("Bush") as MultiMeshInstance3D
	var plant_node := veg_node.get_node_or_null("Plant") as MultiMeshInstance3D
	var flower_node := veg_node.get_node_or_null("Flowers") as MultiMeshInstance3D

	if bush_node == null:
		bush_node = MultiMeshInstance3D.new()
		bush_node.name = "Bush"
		veg_node.add_child(bush_node)
	if plant_node == null:
		plant_node = MultiMeshInstance3D.new()
		plant_node.name = "Plant"
		veg_node.add_child(plant_node)
	if flower_node == null:
		flower_node = MultiMeshInstance3D.new()
		flower_node.name = "Flowers"
		veg_node.add_child(flower_node)

	if Engine.is_editor_hint() and not preview_vegetation_in_editor:
		if bush_node: bush_node.multimesh = null
		if plant_node: plant_node.multimesh = null
		if flower_node: flower_node.multimesh = null
		return

	var veg_data := build_vegetation_data()
	var grouped_xforms: Array[Array] = [[], [], []]

	for v in veg_data:
		var arch: int = v.archetype
		if arch >= 0 and arch < 3:
			grouped_xforms[arch].append(v.transform)

	var mm_nodes := [bush_node, plant_node, flower_node]
	var vis_ranges := [75.0, 75.0, 65.0]
	var shadows_cfg := [
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
	]
	for a in range(3):
		var node: MultiMeshInstance3D = mm_nodes[a]
		if node == null:
			continue
		var mesh := _get_vegetation_mesh(a)
		_build_chunked_multimeshes(node, mesh, grouped_xforms[a], vis_ranges[a], 12.0, shadows_cfg[a], null, 112.0, 3.5)

	# Vegetation is passable, non-colliding foliage (shrubs, plants, flowers)
	var veg_colliders := veg_node.get_node_or_null("VegetationColliders") as StaticBody3D
	if veg_colliders != null:
		veg_colliders.queue_free()


func _make_mountain_fog_mesh() -> ArrayMesh:
	# Three intersecting, slightly tilted quads so summit mist looks volumetric
	# both from the valley looking up at the peaks and while walking inside a cloud bank.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var sheet_rots := [
		Basis.IDENTITY,
		Basis(Vector3(1.0, 0.0, 0.25).normalized(), 0.28),
		Basis(Vector3(-0.35, 0.0, 1.0).normalized(), -0.24),
	]
	var y_offsets := [0.0, 0.14, -0.14]

	for s_i in range(sheet_rots.size()):
		var rot: Basis = sheet_rots[s_i]
		var y_off: float = y_offsets[s_i]
		var base_idx := verts.size()
		var corners := [
			Vector3(-0.5, 0.0, -0.5),
			Vector3(0.5, 0.0, -0.5),
			Vector3(0.5, 0.0, 0.5),
			Vector3(-0.5, 0.0, 0.5),
		]
		var corner_uvs := [
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
			Vector2(1.0, 1.0),
			Vector2(0.0, 1.0),
		]
		var nrm := (rot * Vector3.UP).normalized()
		for c_i in range(4):
			verts.append(rot * corners[c_i] + Vector3(0.0, y_off, 0.0))
			normals.append(nrm)
			uvs.append(corner_uvs[c_i])
		indices.append_array([
			base_idx, base_idx + 1, base_idx + 2,
			base_idx, base_idx + 2, base_idx + 3,
		])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _build_mountain_fog() -> void:
	var fog_node := get_node_or_null("MountainFog") as MultiMeshInstance3D
	if not enable_mountain_fog or mountain_fog_count <= 0:
		if fog_node != null:
			fog_node.multimesh = null
			fog_node.visible = false
		return

	if fog_node == null:
		fog_node = MultiMeshInstance3D.new()
		fog_node.name = "MountainFog"
		add_child(fog_node)

	fog_node.visible = true
	fog_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed ^ 0x4D464F47

	# Scan the alpine perimeter and high northern ridge for peaks above mountain_fog_min_height
	var candidates: Array[Vector3] = []
	var scan_half := 1800.0
	var scan_step := 90.0
	var gx := -scan_half
	while gx <= scan_half:
		var gz := -scan_half
		while gz <= scan_half:
			var h := sample_height(gx, gz)
			if h >= mountain_fog_min_height:
				candidates.append(Vector3(gx, h, gz))
			gz += scan_step
		gx += scan_step

	var xforms: Array[Transform3D] = []
	if not candidates.is_empty():
		# Shuffle candidates deterministically so capped counts stay evenly spread across all peaks
		for i in range(candidates.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = tmp

		var pass_idx := 0
		while xforms.size() < mountain_fog_count and pass_idx < 4:
			for c in candidates:
				if xforms.size() >= mountain_fog_count:
					break
				var px := c.x + rng.randf_range(-52.0, 52.0)
				var pz := c.z + rng.randf_range(-52.0, 52.0)
				if enable_cave and is_point_in_cave_cutout(px, pz):
					continue
				var py := sample_height(px, pz)
				if py < mountain_fog_min_height:
					continue
				var alt_factor := clampf((py - mountain_fog_min_height) / 70.0, 0.0, 1.0)
				var fog_y := py + lerpf(2.5, 16.0, rng.randf()) + alt_factor * 6.0
				var yaw := rng.randf() * TAU
				var sxz := rng.randf_range(85.0, 165.0) * lerpf(0.85, 1.20, alt_factor)
				var sy := rng.randf_range(12.0, 26.0)
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sxz, sy, sxz))
				xforms.append(Transform3D(basis, Vector3(px, fog_y, pz)))
			pass_idx += 1

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _make_mountain_fog_mesh()
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])

	var fog_shader := load("res://shaders/mountain_fog.gdshader") as Shader
	if fog_shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = fog_shader
		mat.set_shader_parameter("fog_color", Vector3(mountain_fog_color.r, mountain_fog_color.g, mountain_fog_color.b))
		mat.set_shader_parameter("fog_opacity", mountain_fog_opacity)
		mat.set_shader_parameter("far_fade_dist", 2600.0)
		mm.mesh.surface_set_material(0, mat)

	fog_node.multimesh = mm
	fog_node.custom_aabb = AABB(Vector3(-2500.0, -50.0, -2500.0), Vector3(5000.0, 550.0, 5000.0))
	fog_node.visibility_range_begin = 0.0
	fog_node.visibility_range_end = 2800.0
	fog_node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

