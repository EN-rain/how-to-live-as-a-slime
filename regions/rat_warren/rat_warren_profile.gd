class_name RatWarrenProfile
extends Resource
## Inspector-editable dressing, swamp-rim, and lighting profile for the Rat Warren.

@export_group("Swamp & Atmosphere")
@export var swamp_water_color: Color = Color(0.14, 0.28, 0.16, 0.88)
@export_range(0.0, 4.0, 0.1) var brazier_light_energy: float = 1.45
@export var brazier_light_color: Color = Color(0.95, 0.62, 0.28)
@export var spore_glow_color: Color = Color(0.32, 0.86, 0.56)

@export_group("Dressing Density")
@export_range(0.0, 2.0, 0.05) var ruin_vegetation_scale: float = 1.0
