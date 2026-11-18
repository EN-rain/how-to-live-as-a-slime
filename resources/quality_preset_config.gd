class_name QualityPresetConfig
extends Resource
## Inspector-editable graphics quality preset scaling authored terrain budgets.

@export var preset_name: String = "High"
@export_range(0.4, 1.0, 0.02) var render_scale: float = 1.0
@export_range(0, 3, 1) var msaa_idx: int = 1
@export var shadow_enabled: bool = true
@export_range(10.0, 300.0, 5.0) var shadow_distance: float = 120.0
@export_range(0.05, 2.0, 0.05) var grass_mult: float = 1.0
@export var dof_far: bool = false
@export_range(40.0, 400.0, 10.0) var vis_grass: float = 160.0
@export_range(100.0, 1200.0, 25.0) var vis_trees: float = 550.0
@export_range(100.0, 1000.0, 25.0) var vis_rocks: float = 450.0
@export_range(100.0, 1000.0, 25.0) var vis_veg: float = 400.0
