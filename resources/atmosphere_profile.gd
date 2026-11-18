class_name AtmosphereProfile
extends Resource
## Inspector-editable regional ambient colors, fog tints, and fade ranges.

@export_group("Interior Ambient & Fog")
@export var hall_ambient_color: Color = Color(0.30, 0.30, 0.32, 1.0)
@export var grotto_ambient_color: Color = Color(0.16, 0.23, 0.33, 1.0)
@export var hall_fog_color: Color = Color(0.15, 0.16, 0.19, 1.0)
@export var grotto_fog_color: Color = Color(0.06, 0.12, 0.19, 1.0)

@export_group("Exterior Regional Tints")
@export var alpine_fog_color: Color = Color(0.84, 0.90, 0.97, 1.0)
@export var webwood_ambient_tint: Color = Color(0.25, 0.39, 0.43, 1.0)
@export var webwood_fog_tint: Color = Color(0.24, 0.37, 0.41, 1.0)
@export var ruins_ambient_tint: Color = Color(0.42, 0.53, 0.45, 1.0)
@export var wolf_ambient_tint: Color = Color(0.62, 0.72, 0.84, 1.0)
@export var wolf_fog_tint: Color = Color(0.54, 0.63, 0.72, 1.0)

@export_group("Blend Distances")
@export var webwood_fade_range: Vector2 = Vector2(75.0, 165.0)
@export var ruins_fade_range: Vector2 = Vector2(68.0, 156.0)
@export var wolf_fade_range: Vector2 = Vector2(48.0, 124.0)
