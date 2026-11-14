@tool
class_name CaveBakeConfig
extends Resource
## Inspector-editable SDF noise & voxel grid settings for offline/editor cave baking.

@export_group("SDF Noise")
@export var seed_val: int = 1337
@export_range(0.005, 0.25, 0.001) var macro_frequency: float = 0.048
@export_range(1, 5, 1) var macro_octaves: int = 2
@export_range(0.01, 0.30, 0.001) var fracture_frequency: float = 0.095
@export_range(1, 5, 1) var fracture_octaves: int = 2

@export_group("Voxel Grid")
@export_range(0.4, 2.0, 0.05) var voxel_size: float = 0.80
@export_range(2, 8, 1) var brick_size: int = 4
@export var u_min: float = -220.0
@export var u_max: float = 74.0
@export var y_min: float = -1.0
@export var y_max: float = 66.0
@export var s_min: float = -34.0
@export var s_max: float = 240.0

