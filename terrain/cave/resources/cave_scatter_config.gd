@tool
class_name CaveScatterConfig
extends Resource
## Inspector-editable procedural set-dressing densities & scales for the cave interior.

@export_group("Prop Counts & Densities")
@export_range(0, 1000, 10) var pebble_count: int = 380
@export_range(0.0, 2.5, 0.05) var speleothem_density: float = 1.0
@export_range(0.0, 2.5, 0.05) var crystal_density: float = 1.0
@export_range(0.0, 2.5, 0.05) var fern_density: float = 1.0
@export_range(0, 40, 1) var boulder_count: int = 14

@export_group("Scale & Clearance")
@export_range(0.2, 2.0, 0.05) var min_crystal_scale: float = 0.65
@export_range(0.5, 4.0, 0.05) var max_crystal_scale: float = 1.65
@export_range(1.0, 15.0, 0.5) var spawn_exclusion_radius: float = 5.5

