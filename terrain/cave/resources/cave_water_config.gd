@tool
class_name CaveWaterConfig
extends Resource
## Inspector-editable water levels, colors, and flow speeds for cave water bodies.

@export_group("Grotto Pool")
@export var pool_water_y: float = 17.35
@export var pool_shallow_color: Color = Color(0.14, 0.72, 0.78, 1.0)
@export var pool_deep_color: Color = Color(0.04, 0.24, 0.44, 1.0)

@export_group("Underground Lake")
@export var lake_water_y: float = 6.40
@export var lake_shallow_color: Color = Color(0.12, 0.66, 0.76, 1.0)
@export var lake_deep_color: Color = Color(0.03, 0.16, 0.34, 1.0)

@export_group("Outflow Stream")
@export_range(0.1, 5.0, 0.05) var stream_flow_speed: float = 1.35

