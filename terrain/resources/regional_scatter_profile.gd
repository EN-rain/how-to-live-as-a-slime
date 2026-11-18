class_name RegionalScatterProfile
extends Resource
## Typed scatter budgets and spacing profiles for non-Webwood regions.

@export_group("Regional Grass Passes")
@export_range(20.0, 220.0, 1.0) var wolf_grass_radius: float = 125.0
@export_range(0, 30000, 100) var wolf_grass_count: int = 14000
@export_range(20.0, 220.0, 1.0) var rat_grass_radius: float = 162.0
@export_range(0, 30000, 100) var rat_grass_count: int = 19500
@export_range(20.0, 160.0, 1.0) var skel_grass_radius: float = 74.0
@export_range(0, 20000, 100) var skel_grass_count: int = 8200
@export_range(20.0, 180.0, 1.0) var village_grass_radius: float = 96.0
@export_range(0, 20000, 100) var village_grass_count: int = 6800

@export_group("Regional Tree Passes")
@export_range(40.0, 180.0, 1.0) var wolf_tree_radius: float = 105.0
@export_range(6.0, 24.0, 0.5) var wolf_tree_spacing: float = 11.5
