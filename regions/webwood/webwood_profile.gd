class_name WebwoodProfile
extends Resource
## Inspector-editable layout, silk art, and scatter profile for the Spider Silk Forest (Webwood).

@export_group("Layout")
@export var forest_center: Vector2 = Vector2(-410.0, 480.0)
@export var trail_start: Vector2 = Vector2(-335.0, 390.0)
@export var trail_bend: Vector2 = Vector2(-396.0, 468.0)
@export_range(40.0, 300.0, 1.0) var forest_radius: float = 165.0
@export_range(30.0, 260.0, 1.0) var territory_radius: float = 125.0
@export_range(40.0, 300.0, 1.0) var leash_radius: float = 158.0
@export var nest_snag_offsets: Array[Vector2] = [
	Vector2(-12.0, -6.0),
	Vector2(2.0, -13.0),
	Vector2(12.0, 2.0),
	Vector2(5.0, 13.0),
	Vector2(-8.0, 9.0),
]
@export var nest_satellite_offsets: Array[Vector2] = [
	Vector2(48.0, -75.0),
	Vector2(-88.0, -14.0),
	Vector2(-6.0, 86.0),
	Vector2(82.0, 34.0),
]

@export_group("Art & Silk")
@export var canopy_color: Color = Color(0.77, 0.86, 0.91, 0.80)
@export var veil_color: Color = Color(0.75, 0.84, 0.89, 0.74)
@export var shroud_color: Color = Color(0.76, 0.84, 0.89, 0.82)
@export_range(0.0, 0.25, 0.005) var canopy_sway_amp: float = 0.020
@export_range(0.3, 1.5, 0.02) var shroud_height_scale: float = 0.88
@export_range(6.0, 40.0, 0.5) var silk_neighbor_range: float = 23.0
@export_range(0, 16, 1) var cocoon_count: int = 8
## Each Vector4: (offset_x, offset_z, size_m, seed_f) relative to forest_center.
@export var ground_web_patches: Array[Vector4] = [
	Vector4(0.0, 0.0, 9.6, 0.4),
	Vector4(-7.8, -5.4, 7.4, 1.3),
	Vector4(10.2, -1.8, 6.8, 2.2),
	Vector4(-6.0, 7.8, 7.2, 3.1),
	Vector4(7.2, 6.8, 6.6, 4.0),
	Vector4(-14.5, 1.5, 6.4, 5.2),
	Vector4(14.0, 11.5, 6.2, 6.1),
	Vector4(-2.0, -13.5, 6.5, 7.0),
	Vector4(19.5, -12.0, 5.8, 7.8),
	Vector4(-21.0, -14.0, 5.8, 8.4),
	Vector4(-22.0, 16.0, 6.0, 9.2),
]

@export_group("Tree & Grass Scatter")
@export_range(4.0, 32.0, 0.2) var tree_grid_spacing: float = 8.6
@export_range(4.0, 30.0, 0.5) var tree_min_radius: float = 10.0
@export_range(6.0, 40.0, 0.5) var tree_glade_clearance: float = 11.0
@export_range(2.0, 16.0, 0.2) var tree_trail_clearance: float = 3.8
@export_range(30.0, 240.0, 1.0) var grass_radius: float = 145.0
@export_range(0, 30000, 100) var grass_count: int = 14500


func validated() -> Dictionary:
	var r_forest := maxf(forest_radius, 30.0)
	return {
		"center": forest_center,
		"trail_start": trail_start,
		"trail_bend": trail_bend,
		"forest_radius": r_forest,
		"territory_radius": clampf(territory_radius, 20.0, r_forest),
		"leash_radius": maxf(leash_radius, 30.0),
		"snag_offsets": nest_snag_offsets,
		"satellite_offsets": nest_satellite_offsets,
		"canopy_color": canopy_color,
		"veil_color": veil_color,
		"shroud_color": shroud_color,
		"canopy_sway_amp": clampf(canopy_sway_amp, 0.0, 0.25),
		"shroud_height_scale": clampf(shroud_height_scale, 0.3, 1.5),
		"silk_neighbor_range": maxf(silk_neighbor_range, 4.0),
		"cocoon_count": clampi(cocoon_count, 0, 16),
		"ground_web_patches": ground_web_patches,
		"tree_grid_spacing": maxf(tree_grid_spacing, 6.0),
		"tree_min_radius": maxf(tree_min_radius, 4.0),
		"tree_glade_clearance": maxf(tree_glade_clearance, 8.0),
		"tree_trail_clearance": maxf(tree_trail_clearance, 2.0),
		"grass_radius": maxf(grass_radius, 20.0),
		"grass_count": maxi(grass_count, 0),
	}
