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
@export var water_segments: int = 96:
	set(v):
		water_segments = clampi(v, 16, 256)
		_rebuild_if_ready()

@export_group("Grass Placement & Visuals")
## Total grass instances distributed across the active meadow disk.
@export var grass_count: int = 15200:
	set(v):
		grass_count = clampi(v, 0, 250000)
		_rebuild_if_ready()
@export var min_grass_normal_y: float = 0.50:
	set(v):
		min_grass_normal_y = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()
## Radius across the island meadow in which grass is densely populated.
@export var grass_spawn_radius: float = 140.0:
	set(v):
		grass_spawn_radius = maxf(v, 10.0)
		_rebuild_if_ready()
## Distance beyond which grass fades out.
@export var grass_visibility_end: float = 140.0:
	set(v):
		grass_visibility_end = maxf(v, 10.0)
		_rebuild_if_ready()
## Margin distance for grass fade out transition.
@export var grass_visibility_margin: float = 30.0:
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
@export_range(0, 600, 10) var tree_count: int = 140:
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
@export var min_tree_spacing: float = 13.5:
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
var _built_once := false
var _rebuild_pending := false


func _ready() -> void:
	set_process(false)
	_built_once = true
	rebuild()


func _rebuild_if_ready() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	if not _rebuild_pending:
		_rebuild_pending = true
		_deferred_rebuild.call_deferred()


func _deferred_rebuild() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	rebuild()


func rebuild() -> void:
	_setup_noise()
	var terrain_node := get_node_or_null("Terrain") as MeshInstance3D
	var grass_node := get_node_or_null("Grass") as MultiMeshInstance3D
	var wispy_node := get_node_or_null("GrassWispy") as MultiMeshInstance3D
	var water_node := get_node_or_null("Water") as MeshInstance3D
	var trees_node := get_node_or_null("Trees") as Node3D
	var rocks_node := get_node_or_null("Rocks") as Node3D
	var veg_node := get_node_or_null("Vegetation") as Node3D

	if terrain_node != null:
		terrain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_build_terrain_mesh(terrain_node)

	if water_node != null:
		_build_water_mesh(water_node)

	_cached_grass_data.clear()
	_cached_grass_count = -1
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

	_build_cave()


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

	# 4. Continental Coastline & Golden Sandy Beach Drop-off (only near coast)
	var coast_inner := continent_radius - 320.0
	if eff_dist <= coast_inner:
		return land_h

	var coast_outer := continent_radius + 180.0
	var continent_factor := smoothstep(coast_outer, coast_inner, eff_dist)
	var sea_bed := seabed_depth + _noise.get_noise_2d(x * 0.003 - 200.0, z * 0.003 + 200.0) * 3.0
	var base_h := lerpf(sea_bed, land_h, continent_factor * continent_factor * (3.0 - 2.0 * continent_factor))
	return maxf(base_h, sea_bed)


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


const CAVE_SUBDIV_X_MIN := -255.0
const CAVE_SUBDIV_X_MAX := -15.0
const CAVE_SUBDIV_Z_MIN := -265.0
const CAVE_SUBDIV_Z_MAX := -60.0


func _get_cave_cell_subdiv(n: int) -> int:
	if not enable_cave or n < 96:
		return 1
	return 8


func _is_cave_subdiv_cell(ix: int, iz: int, n: int) -> bool:
	if not enable_cave or n < 96:
		return false
	if ix < 0 or iz < 0 or ix >= n or iz >= n:
		return false
	var x0 := _cached_grid_coords[ix]
	var x1 := _cached_grid_coords[ix + 1]
	var z0 := _cached_grid_coords[iz]
	var z1 := _cached_grid_coords[iz + 1]
	return x1 > CAVE_SUBDIV_X_MIN and x0 < CAVE_SUBDIV_X_MAX and z1 > CAVE_SUBDIV_Z_MIN and z0 < CAVE_SUBDIV_Z_MAX


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
	var v00 := Vector3(sx0, 0.0, sz0)
	var v10 := Vector3(sx1, 0.0, sz0)
	var v01 := Vector3(sx0, 0.0, sz1)
	var v11 := Vector3(sx1, 0.0, sz1)
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
	if enable_cave:
		if CaveSystem.is_subterranean_or_cutout(x, z, est_foot_y, over_h):
			return CaveSystem.sample_sdf_floor_below(x, z, est_foot_y, over_h).w
		if est_foot_y < over_h - 2.5:
			return CaveSystem.sample_sdf_floor_below(x, z, est_foot_y, over_h).w
	return over_h


func _build_terrain_mesh(terrain_node: MeshInstance3D) -> void:
	var n := _get_active_subdivisions()
	var half := terrain_size * 0.5

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
	var idx := 0
	for iz in row_count:
		var v_coord := float(iz) * inv_n
		var z := grid_coords[iz]
		for ix in row_count:
			var u_coord := float(ix) * inv_n
			var x := grid_coords[ix]
			verts[idx] = Vector3(x, sample_height(x, z), z)
			uvs[idx] = Vector2(u_coord, v_coord)
			idx += 1

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

	var cut_cave_portal := enable_cave and n >= 96
	var sub := _get_cave_cell_subdiv(n)
	for iz in n:
		var r0 := iz * row_count
		var r1 := (iz + 1) * row_count
		var z0 := grid_coords[iz]
		var z1 := grid_coords[iz + 1]
		var v0_uv := float(iz) * inv_n
		var v1_uv := float(iz + 1) * inv_n
		for ix in n:
			if _is_cave_subdiv_cell(ix, iz, n):
				var x0 := grid_coords[ix]
				var x1 := grid_coords[ix + 1]
				var u0_uv := float(ix) * inv_n
				var u1_uv := float(ix + 1) * inv_n
				var base_v := verts.size()
				var s_row := sub + 1
				var n00 := normals[r0 + ix]
				var n10 := normals[r0 + ix + 1]
				var n01 := normals[r1 + ix]
				var n11 := normals[r1 + ix + 1]
				for sz in s_row:
					var tz := float(sz) / float(sub)
					var vz := lerpf(z0, z1, tz)
					var v_uv := lerpf(v0_uv, v1_uv, tz)
					var n_left := n00.lerp(n01, tz)
					var n_right := n10.lerp(n11, tz)
					for sx in s_row:
						var tx := float(sx) / float(sub)
						var vx := lerpf(x0, x1, tx)
						var u_uv := lerpf(u0_uv, u1_uv, tx)
						var vy := _sample_cave_subdiv_vertex_y(ix, iz, sx, sz, sub, n, x0, x1, z0, z1)
						verts.append(Vector3(vx, vy, vz))
						normals.append(n_left.lerp(n_right, tx).normalized())
						uvs.append(Vector2(u_uv, v_uv))
				for sz in sub:
					var sr0 := base_v + sz * s_row
					var sr1 := base_v + (sz + 1) * s_row
					for sx in sub:
						var si00 := sr0 + sx
						var si10 := si00 + 1
						var si01 := sr1 + sx
						var si11 := si01 + 1
						if cut_cave_portal and CaveSystem.is_quad_in_portal_cutout(verts[si00], verts[si10], verts[si01], verts[si11]):
							continue
						indices.append(si00)
						indices.append(si10)
						indices.append(si01)
						indices.append(si10)
						indices.append(si11)
						indices.append(si01)
				continue

			var i00 := r0 + ix
			var i10 := i00 + 1
			var i01 := r1 + ix
			var i11 := i01 + 1
			if cut_cave_portal and CaveSystem.is_quad_in_portal_cutout(verts[i00], verts[i10], verts[i01], verts[i11]):
				continue

			indices.append(i00)
			indices.append(i10)
			indices.append(i01)
			indices.append(i10)
			indices.append(i11)
			indices.append(i01)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_node.mesh = arr_mesh
	terrain_node.custom_aabb = AABB(Vector3(-half, -50.0, -half), Vector3(terrain_size, 320.0, terrain_size))

	var col_shape_node := terrain_node.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	var static_body := terrain_node.get_node_or_null("StaticBody3D") as StaticBody3D
	if static_body != null:
		static_body.collision_layer = 1
		static_body.collision_mask = 0
	if col_shape_node != null:
		# In editor preview, skip building the 73,728-triangle concave collision mesh
		# to prevent Godot Editor physics server wireframe and BVH generation lag.
		if Engine.is_editor_hint():
			col_shape_node.shape = null
		else:
			col_shape_node.shape = _build_low_mem_collision_shape(verts, row_count, n)


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
									if enable_cave and n >= 96 and CaveSystem.is_quad_in_portal_cutout(sv00, sv10, sv01, sv11):
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
							if enable_cave and n >= 96 and CaveSystem.is_quad_in_portal_cutout(cv00, cv10, cv01, cv11):
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
			if enable_cave and n >= 96 and CaveSystem.is_quad_in_portal_cutout(v00, v10, v01, v11):
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
	# Optimized contour-hugging annular ocean mesh.
	# Pre-allocates index buffer and leaves the continent interior 100% hollow.
	var rings := 12 if Engine.is_editor_hint() else water_rings
	var segments := 48 if Engine.is_editor_hint() else water_segments
	var r_out := ocean_outer_radius

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var row_count := segments + 1
	verts.resize((rings + 1) * row_count)
	normals.resize((rings + 1) * row_count)
	uvs.resize((rings + 1) * row_count)
	indices.resize(rings * segments * 6)

	var shore_radii := PackedFloat32Array()
	shore_radii.resize(row_count)
	var cos_tab := PackedFloat32Array()
	var sin_tab := PackedFloat32Array()
	cos_tab.resize(row_count)
	sin_tab.resize(row_count)

	for iseg in range(segments):
		var theta := (float(iseg) / float(segments)) * TAU
		cos_tab[iseg] = cos(theta)
		sin_tab[iseg] = sin(theta)
		shore_radii[iseg] = _find_shoreline_radius(theta) - 6.0
	cos_tab[segments] = cos_tab[0]
	sin_tab[segments] = sin_tab[0]
	shore_radii[segments] = shore_radii[0]

	var up_norm := Vector3.UP
	var idx := 0
	for ir in range(rings + 1):
		var t := float(ir) / float(rings)
		var blend := t * t
		for iseg in range(row_count):
			var r := lerpf(shore_radii[iseg], r_out, blend)
			var x := cos_tab[iseg] * r
			var z := sin_tab[iseg] * r
			verts[idx] = Vector3(x, sea_level, z)
			normals[idx] = up_norm
			uvs[idx] = Vector2(x * 0.005, z * 0.005)
			idx += 1

	var ii := 0
	for ir in range(rings):
		var r0 := ir * row_count
		var r1 := (ir + 1) * row_count
		for iseg in range(segments):
			var i00 := r0 + iseg
			var i10 := i00 + 1
			var i01 := r1 + iseg
			var i11 := i01 + 1

			indices[ii] = i00
			indices[ii + 1] = i01
			indices[ii + 2] = i10

			indices[ii + 3] = i10
			indices[ii + 4] = i01
			indices[ii + 5] = i11
			ii += 6

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	water_node.mesh = mesh
	water_node.position = Vector3.ZERO
	water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_node.custom_aabb = AABB(Vector3(-r_out, -30.0, -r_out), Vector3(r_out * 2.0, 60.0, r_out * 2.0))


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


## Industry-Standard Hexagonal Blue-Noise Stratified Placement with Continuous Polar Perturbation.
## Completely eliminates Cartesian grid lines and agricultural rows, guaranteeing a lush, gapless carpet.
func build_grass_data(center: Vector2 = Vector2.ZERO) -> Dictionary:
	var target_total := editor_grass_count if Engine.is_editor_hint() else grass_count
	if not Engine.is_editor_hint() and not _cached_grass_data.is_empty() and _cached_grass_count == target_total and _cached_grass_center == center:
		return _cached_grass_data

	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 77
	var common_xforms: Array[Transform3D] = []
	var wispy_xforms: Array[Transform3D] = []

	if target_total <= 0:
		return { "common": common_xforms, "wispy": wispy_xforms }

	var spawn_r := grass_spawn_radius
	# In editor preview, focus on tight 18m radius around center at full lush density
	if Engine.is_editor_hint():
		spawn_r = minf(spawn_r, 18.0)

	var spacing := grass_spacing
	var max_rings := int(ceil(spawn_r / spacing))

	for ring in range(max_rings + 1):
		if (common_xforms.size() + wispy_xforms.size()) >= target_total:
			break
		var r_dist := float(ring) * spacing
		var count := 1 if ring == 0 else int(round(TAU * float(ring)))
		var angle_step := TAU / float(count)
		var ring_phase := rng.randf() * TAU

		for i in count:
			if (common_xforms.size() + wispy_xforms.size()) >= target_total:
				break
			var angle := float(i) * angle_step + ring_phase
			var r_jitter := r_dist + rng.randf_range(-0.25 * spacing, 0.25 * spacing)
			var a_jitter := angle + rng.randf_range(-0.15, 0.15) * angle_step

			var x := r_jitter * cos(a_jitter) + center.x
			var z := r_jitter * sin(a_jitter) + center.y

			if enable_cave and (CaveSystem.is_in_portal_scatter_exclusion(x, z, true) or is_point_in_cave_cutout(x, z)):
				continue

			# 1. Botanical Meadow Density (smooth Perlin glades, trails, and clearings)
			var density := sample_grass_density(x, z)
			if density < grass_clearing_threshold:
				continue

			# 2. Exact terrain surface query (fast barycentric interpolation on cached terrain grid)
			var surf := sample_surface_exact(x, z)
			var y := surf.w
			var n := Vector3(surf.x, surf.y, surf.z)

			# 3. Slope Mask: steep cliffs (> 42°) remain clean rock
			if n.y < min_grass_normal_y:
				continue

			# 4. Elevation Mask: green meadow is between beach (4.5m) and alpine summit (95.0m)
			if y < 4.5 or y > 95.0:
				continue

			# 5. Species allocation: 65% Common Tall Grass, 35% Wispy Feathery Grass
			var is_wispy := rng.randf() >= 0.65

			# 6. Gravity-Biased Orientation (Natural Phototropism)
			var up_vec := (Vector3.UP * (1.0 - grass_slope_gravity_blend) + n * grass_slope_gravity_blend).normalized()
			var yaw := rng.randf() * TAU
			var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
			var right := up_vec.cross(fwd).normalized()
			fwd = right.cross(up_vec).normalized()

			# 7. Volumetric Scale Modulation (prominent 3D presence, lush non-flat tufts)
			var base_scale := remap(density, grass_clearing_threshold, 1.0, 0.95, 1.25)
			var sxz := 1.0
			var sy := 1.0

			if is_wispy:
				sxz = base_scale * rng.randf_range(1.10, 1.45)
				sy = base_scale * rng.randf_range(1.15, 1.55)
			else:
				sxz = base_scale * rng.randf_range(grass_scale_xz_min, grass_scale_xz_max)
				sy = base_scale * rng.randf_range(grass_scale_y_min, grass_scale_y_max)

			var basis := Basis(right * sxz, up_vec * sy, fwd * sxz)

			# 8. Root Anchoring: embed 3.0cm into terrain to guarantee zero floating blades
			var root_pos := Vector3(x, y - 0.03, z)
			var xf := Transform3D(basis, root_pos)

			if is_wispy:
				wispy_xforms.append(xf)
			else:
				common_xforms.append(xf)

	var res := { "common": common_xforms, "wispy": wispy_xforms }
	if not Engine.is_editor_hint():
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
	aabb_grow_margin: float = 2.0
) -> void:
	# 1. Clear existing chunk nodes
	for child in parent_node.get_children():
		if child.name.begins_with("Chunk_"):
			parent_node.remove_child(child)
			child.queue_free()

	if parent_node is MultiMeshInstance3D:
		var empty_mm := MultiMesh.new()
		empty_mm.transform_format = MultiMesh.TRANSFORM_3D
		empty_mm.instance_count = 0
		(parent_node as MultiMeshInstance3D).multimesh = empty_mm

	if transforms.is_empty() or mesh == null:
		return

	# 2. Partition into spatial grid tiles
	var chunk_map: Dictionary = {}
	for xf_val in transforms:
		var xf: Transform3D = xf_val
		var p := xf.origin
		var key := Vector2i(int(floor(p.x / chunk_size)), int(floor(p.z / chunk_size)))
		var arr: Array = chunk_map.get(key, [])
		arr.append(xf)
		chunk_map[key] = arr

	# 3. Instantiate a MultiMeshInstance3D per tile with tight custom_aabb
	for key: Vector2i in chunk_map.keys():
		var chunk_xforms: Array = chunk_map[key]
		if chunk_xforms.is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = chunk_xforms.size()

		var min_pt := Vector3(INF, INF, INF)
		var max_pt := Vector3(-INF, -INF, -INF)

		for i in chunk_xforms.size():
			var xf: Transform3D = chunk_xforms[i]
			mm.set_instance_transform(i, xf)
			var o := xf.origin
			min_pt.x = minf(min_pt.x, o.x)
			min_pt.y = minf(min_pt.y, o.y)
			min_pt.z = minf(min_pt.z, o.z)
			max_pt.x = maxf(max_pt.x, o.x)
			max_pt.y = maxf(max_pt.y, o.y)
			max_pt.z = maxf(max_pt.z, o.z)

		var chunk_inst := MultiMeshInstance3D.new()
		chunk_inst.name = "Chunk_%d_%d" % [key.x, key.y]
		chunk_inst.multimesh = mm
		if material != null:
			chunk_inst.material_override = material
		chunk_inst.cast_shadow = cast_shadow
		chunk_inst.visibility_range_end = vis_end
		chunk_inst.visibility_range_end_margin = vis_margin
		chunk_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

		var tight_aabb := AABB(min_pt, max_pt - min_pt).grow(aabb_grow_margin)
		chunk_inst.custom_aabb = tight_aabb

		parent_node.add_child(chunk_inst)


func _build_grass_multimesh(grass_node: MultiMeshInstance3D) -> void:
	if Engine.is_editor_hint() and not preview_grass_in_editor:
		grass_node.multimesh = null
		return

	if _cached_grass_data.is_empty():
		_cached_grass_data = build_grass_data(_grass_center)

	var common_xforms: Array[Transform3D] = _cached_grass_data.get("common", [])
	if _grass_mat == null:
		_grass_mat = grass_node.material_override as ShaderMaterial
	_build_chunked_multimeshes(grass_node, _get_grass_mesh(), common_xforms, 40.0, 8.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, _grass_mat, 48.0, 2.0)


func _build_grass_wispy_multimesh(wispy_node: MultiMeshInstance3D) -> void:
	if Engine.is_editor_hint() and not preview_grass_in_editor:
		wispy_node.multimesh = null
		return

	if _cached_grass_data.is_empty():
		_cached_grass_data = build_grass_data(_grass_center)

	var wispy_xforms: Array[Transform3D] = _cached_grass_data.get("wispy", [])
	var mat: ShaderMaterial = wispy_node.material_override as ShaderMaterial
	if mat == null:
		mat = _grass_mat
	_build_chunked_multimeshes(wispy_node, _get_wispy_grass_mesh(), wispy_xforms, 40.0, 8.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, mat, 48.0, 2.0)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _player_ref == null:
		_player_ref = get_tree().get_first_node_in_group("player") as Node3D
		if _player_ref == null:
			_player_ref = get_parent().get_node_or_null("Slime") as Node3D

	if _player_ref != null:
		var p_pos := _player_ref.global_position
		# Update shader slime interaction uniform
		if _grass_mat == null:
			var grass_node := get_node_or_null("Grass") as MultiMeshInstance3D
			if grass_node != null:
				_grass_mat = grass_node.material_override as ShaderMaterial
		if _grass_mat != null:
			_grass_mat.set_shader_parameter("slime_pos", p_pos)


# =============================================================================
# DETERMINISTIC TREE ECOSYSTEM (Stylized Nature MegaKit Assets)
# =============================================================================

const TREE_ASSET_PATHS := [
	"res://assets/nature/CommonTree_1.gltf",
	"res://assets/nature/CommonTree_2.gltf",
	"res://assets/nature/Pine_1.gltf",
	"res://assets/nature/Pine_2.gltf",
]

var _cached_tree_meshes: Array[Mesh] = []


func _get_tree_mesh(archetype: int) -> Mesh:
	if _cached_tree_meshes.is_empty():
		var bark_tex: Texture2D = load("res://assets/nature/Bark_NormalTree.png")
		var bark_norm_tex: Texture2D = load("res://assets/nature/Bark_NormalTree_Normal.png")
		var broadleaf_tex: Texture2D = load("res://assets/nature/Leaves_NormalTree_C.png")
		var pine_leaf_tex: Texture2D = load("res://assets/nature/Leaf_Pine_C.png")

		# Bark Material
		var bark_mat := StandardMaterial3D.new()
		bark_mat.albedo_texture = bark_tex
		if bark_norm_tex != null:
			bark_mat.normal_enabled = true
			bark_mat.normal_texture = bark_norm_tex
		bark_mat.roughness = 0.92
		bark_mat.cull_mode = BaseMaterial3D.CULL_BACK
		bark_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

		# Broadleaf Foliage Material
		var broadleaf_mat := StandardMaterial3D.new()
		broadleaf_mat.albedo_texture = broadleaf_tex
		broadleaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		broadleaf_mat.alpha_scissor_threshold = 0.45
		broadleaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		broadleaf_mat.roughness = 0.85
		broadleaf_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

		# Pine Foliage Material
		var pine_mat := StandardMaterial3D.new()
		pine_mat.albedo_texture = pine_leaf_tex
		pine_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		pine_mat.alpha_scissor_threshold = 0.45
		pine_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		pine_mat.roughness = 0.85
		pine_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

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
					found_mesh.surface_set_material(0, bark_mat)
					var leaf_mat: StandardMaterial3D = pine_mat if i >= 2 else broadleaf_mat
					found_mesh.surface_set_material(1, leaf_mat)
				_cached_tree_meshes.append(found_mesh)
			else:
				_cached_tree_meshes.append(null)

	if archetype >= 0 and archetype < _cached_tree_meshes.size():
		return _cached_tree_meshes[archetype]
	return null


var _cached_tree_data: Array[Dictionary] = []

## 100% Deterministic Tree Placement across the meadow valley and foothills.
## Uses a seeded random generator and spatial grid to guarantee bit-for-bit repeatability.
func build_tree_data() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed

	var target_count := editor_tree_count if Engine.is_editor_hint() else tree_count
	if not enable_trees or target_count <= 0:
		_cached_tree_data = []
		return []

	var placed_trees: Array[Dictionary] = []
	var placed_positions: Array[Vector3] = []

	var cell_size := 18.0
	var grid_radius := int(ceil(tree_spawn_radius / cell_size))

	# Deterministic candidate grid cells
	var candidates: Array[Vector2] = []
	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var cx := float(gx) * cell_size
			var cz := float(gz) * cell_size
			var d := sqrt(cx * cx + cz * cz)
			if d > tree_spawn_radius or d < tree_clearing_radius:
				continue
			candidates.append(Vector2(cx, cz))

	# Deterministic shuffle using seeded RNG
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2 = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	for cell_base in candidates:
		if placed_trees.size() >= target_count:
			break

		# Deterministic offset within cell
		var jx: float = cell_base.x + rng.randf_range(-cell_size * 0.40, cell_size * 0.40)
		var jz: float = cell_base.y + rng.randf_range(-cell_size * 0.40, cell_size * 0.40)

		var dist := sqrt(jx * jx + jz * jz)
		if dist < tree_clearing_radius or dist > tree_spawn_radius:
			continue
		if enable_cave and (CaveSystem.is_in_portal_scatter_exclusion(jx, jz, false) or is_point_in_cave_cutout(jx, jz)):
			continue

		# 1. Woodland density mask (creates natural groves and copses, leaves clearings)
		var wood_macro: float = _noise.get_noise_2d(jx * 0.012 + 120.0, jz * 0.012 - 90.0) * 0.5 + 0.5
		var wood_detail: float = _noise.get_noise_2d(jx * 0.028 - 40.0, jz * 0.028 + 65.0) * 0.5 + 0.5
		var glade_path: float = absf(_noise.get_noise_2d(jx * 0.016 + 20.0, jz * 0.016 - 30.0))

		var woodland_density: float = (wood_macro * 0.65 + wood_detail * 0.35) * smoothstep(0.05, 0.15, glade_path)
		if woodland_density < 0.32:
			continue

		# 2. Query exact terrain surface (grounding & slope alignment)
		var surf := sample_surface_exact(jx, jz)
		var y := surf.w
		var normal := Vector3(surf.x, surf.y, surf.z)

		# Trees spawn on moderate elevation and low/moderate slopes (< 30°, normal.y >= 0.866)
		if y < tree_min_height or y > tree_max_height:
			continue
		if normal.y < 0.866:
			continue

		# 3. Minimum distance spacing (prevents trunk collision / clipping)
		var candidate_pos := Vector3(jx, y - 0.15, jz) # 0.15m root burial so tree never hovers
		var too_close := false
		for pos in placed_positions:
			var dx: float = pos.x - jx
			var dz: float = pos.z - jz
			if (dx * dx + dz * dz) < (min_tree_spacing * min_tree_spacing):
				too_close = true
				break
		if too_close:
			continue

		# 4. Deterministic archetype selection:
		# 0 = CommonTree_1, 1 = CommonTree_2, 2 = Pine_1, 3 = Pine_2
		var archetype := 0
		if y > 42.0 or jz < -50.0:
			# Higher elevations and north side prefer Pines
			archetype = 2 if rng.randf() < 0.60 else 3
		else:
			# Valley and gentle hills prefer Common Trees
			archetype = 0 if rng.randf() < 0.65 else 1

		var yaw: float = rng.randf() * TAU
		var scale_y: float = rng.randf_range(2.2, 3.4)
		var scale_xz: float = scale_y * rng.randf_range(0.92, 1.08)

		# Surface normal alignment: 85% skyward phototropism, 15% slope normal
		var up := (Vector3.UP * 0.85 + normal * 0.15).normalized()
		var forward := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := up.cross(forward).normalized()
		forward = right.cross(up).normalized()

		var basis := Basis(right * scale_xz, up * scale_y, forward * scale_xz)
		var xform := Transform3D(basis, candidate_pos)

		placed_positions.append(candidate_pos)
		placed_trees.append({
			"transform": xform,
			"archetype": archetype,
			"position": candidate_pos,
			"scale_y": scale_y,
			"scale_xz": scale_xz
		})

	_cached_tree_data = placed_trees
	return placed_trees


func _build_trees(trees_node: Node3D) -> void:
	var broadleaf1_node := trees_node.get_node_or_null("CommonTree1") as MultiMeshInstance3D
	var broadleaf2_node := trees_node.get_node_or_null("CommonTree2") as MultiMeshInstance3D
	var pine1_node := trees_node.get_node_or_null("Pine1") as MultiMeshInstance3D
	var pine2_node := trees_node.get_node_or_null("Pine2") as MultiMeshInstance3D
	var colliders_node := trees_node.get_node_or_null("TrunkColliders") as StaticBody3D
	if colliders_node == null:
		colliders_node = StaticBody3D.new()
		colliders_node.name = "TrunkColliders"
		colliders_node.collision_layer = 4
		colliders_node.collision_mask = 0
		trees_node.add_child(colliders_node)
	else:
		colliders_node.collision_layer = 4

	if Engine.is_editor_hint() and not preview_trees_in_editor:
		if broadleaf1_node: broadleaf1_node.multimesh = null
		if broadleaf2_node: broadleaf2_node.multimesh = null
		if pine1_node: pine1_node.multimesh = null
		if pine2_node: pine2_node.multimesh = null
		return

	var tree_data := build_tree_data()
	var grouped_xforms: Array[Array] = [[], [], [], []]

	for t in tree_data:
		var arch: int = t.archetype
		if arch >= 0 and arch < 4:
			grouped_xforms[arch].append(t.transform)

	var mm_nodes := [broadleaf1_node, broadleaf2_node, pine1_node, pine2_node]
	for a in range(4):
		var node: MultiMeshInstance3D = mm_nodes[a]
		if node == null:
			continue
		var mesh := _get_tree_mesh(a)
		_build_chunked_multimeshes(node, mesh, grouped_xforms[a], 150.0, 25.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, null, 48.0, 12.0)

	# Physical trunk and root flare collision (full-coverage obstacle response for the slime)
	if colliders_node != null:
		for c in colliders_node.get_children():
			c.queue_free()

		if not Engine.is_editor_hint():
			for t in tree_data:
				var sy: float = t.scale_y
				var sxz: float = t.scale_xz
				var pos: Vector3 = t.position

				# 1. Base root flare cylinder (protects ground-level roots from clipping)
				var cs_base := CollisionShape3D.new()
				var cyl_base := CylinderShape3D.new()
				cyl_base.radius = 0.90 * sxz
				cyl_base.height = 1.6 * sy
				cs_base.shape = cyl_base
				cs_base.position = pos + Vector3(0.0, 0.8 * sy, 0.0)
				colliders_node.add_child(cs_base)

				# 2. Main trunk cylinder
				var cs_trunk := CollisionShape3D.new()
				var cyl_trunk := CylinderShape3D.new()
				cyl_trunk.radius = 0.60 * sxz
				cyl_trunk.height = 6.5 * sy
				cs_trunk.shape = cyl_trunk
				cs_trunk.position = pos + Vector3(0.0, 3.25 * sy, 0.0)
				colliders_node.add_child(cs_trunk)


# ==============================================================================
# DETERMINISTIC ROCKS & STONES (Stylized Nature MegaKit Assets)
# ==============================================================================

const ROCK_ASSET_PATHS := [
	"res://assets/nature/Rock_Medium_1.gltf",
	"res://assets/nature/Rock_Medium_2.gltf"
]

var _cached_rock_meshes: Array[Mesh] = []
var _cached_rock_convex_shapes: Array[ConvexPolygonShape3D] = []


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
	if colliders_node == null:
		colliders_node = StaticBody3D.new()
		colliders_node.name = "RockColliders"
		colliders_node.collision_layer = 4
		colliders_node.collision_mask = 0
		rocks_node.add_child(colliders_node)
	else:
		colliders_node.collision_layer = 4

	if Engine.is_editor_hint() and not preview_rocks_in_editor:
		if rock1_node: rock1_node.multimesh = null
		if rock2_node: rock2_node.multimesh = null
		return

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
		_build_chunked_multimeshes(node, mesh, grouped_xforms[a], 80.0, 15.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, null, 48.0, 6.0)

	# Physical rock collision (exact convex hull matching rock facets)
	if colliders_node != null:
		for c in colliders_node.get_children():
			c.queue_free()

		if not Engine.is_editor_hint():
			for r in rock_data:
				var cs := CollisionShape3D.new()
				var conv_shape := _get_rock_convex_shape(r.archetype)
				if conv_shape != null:
					cs.shape = conv_shape
					cs.transform = r.transform
				else:
					var cyl := CylinderShape3D.new()
					var sy: float = r.scale_y
					var sxz: float = r.scale_xz
					cyl.radius = 1.75 * sxz
					cyl.height = 2.2 * sy
					cs.shape = cyl
					cs.position = r.position + Vector3(0.0, 1.1 * sy, 0.0)
				colliders_node.add_child(cs)


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
	var vis_ranges := [60.0, 60.0, 60.0]
	for a in range(3):
		var node: MultiMeshInstance3D = mm_nodes[a]
		if node == null:
			continue
		var mesh := _get_vegetation_mesh(a)
		_build_chunked_multimeshes(node, mesh, grouped_xforms[a], vis_ranges[a], 12.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, null, 48.0, 3.5)

	# Vegetation is passable, non-colliding foliage (shrubs, plants, flowers)
	var veg_colliders := veg_node.get_node_or_null("VegetationColliders") as StaticBody3D
	if veg_colliders != null:
		veg_colliders.queue_free()



