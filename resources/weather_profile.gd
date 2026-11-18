class_name WeatherProfile
extends Resource
## Inspector-editable weather state durations and transition probabilities.

@export_group("State Durations (Seconds)")
@export var clear_duration_range: Vector2 = Vector2(95.0, 165.0)
@export var cloudy_duration_range: Vector2 = Vector2(35.0, 55.0)
@export var light_rain_duration_range: Vector2 = Vector2(40.0, 75.0)
@export var heavy_rain_duration_range: Vector2 = Vector2(30.0, 55.0)
@export var clearing_duration_range: Vector2 = Vector2(25.0, 40.0)

@export_group("Transitions")
@export_range(0.0, 1.0, 0.05) var cloudy_to_rain_chance: float = 0.65
@export_range(0.0, 1.0, 0.05) var light_to_heavy_chance: float = 0.45
