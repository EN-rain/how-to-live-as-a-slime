class_name VillageProfile
extends Resource
## Inspector-editable layout and harbor policy for Slimebrook Village & Harbor.

@export_group("Village Core")
@export var village_center: Vector3 = Vector3(590.0, 20.4, 2200.0)
@export var radius_x: float = 76.0
@export var radius_z: float = 66.0
@export_range(0.0, 4.0, 0.1) var street_lantern_energy: float = 1.45

@export_group("Harbor")
@export var harbor_ropes_decorative_only: bool = true
@export_range(0.0, 4.0, 0.1) var harbor_beacon_energy: float = 1.65
