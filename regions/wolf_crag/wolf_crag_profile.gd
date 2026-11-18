class_name WolfCragProfile
extends Resource
## Inspector-editable art, light, and decorative set-dressing profile for Howlcrest Wolf Crag.

@export_group("Layout")
@export var crag_center: Vector2 = Vector2(290.0, -240.0)
@export_range(30.0, 180.0, 1.0) var grove_radius: float = 105.0
@export_range(20.0, 100.0, 1.0) var territory_radius: float = 54.0
@export_range(40.0, 180.0, 1.0) var leash_radius: float = 105.0

@export_group("Hearth Lighting & Palette")
@export var hearth_light_color: Color = Color(1.0, 0.56, 0.22)
@export_range(0.0, 6.0, 0.1) var hearth_light_energy: float = 1.9
@export_range(4.0, 32.0, 0.5) var hearth_light_range: float = 14.0
@export var rock_warm_tint: Color = Color(0.56, 0.54, 0.50)
@export var rock_cool_tint: Color = Color(0.36, 0.40, 0.45)

@export_group("Decorative Offsets")
@export var lookout_offset: Vector3 = Vector3(13.5, 2.4, -14.0)
@export var hearth_offset: Vector3 = Vector3(-11.0, 0.0, 11.5)
