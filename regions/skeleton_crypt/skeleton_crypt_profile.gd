class_name SkeletonCryptProfile
extends Resource
## Inspector-editable dressing and torch lighting profile for the Skeleton Crypt.

@export_group("Torch & Sanctum Lighting")
@export var torch_color: Color = Color(1.0, 0.62, 0.26)
@export_range(0.0, 5.0, 0.1) var torch_energy: float = 1.65
@export var abyss_water_color: Color = Color(0.05, 0.24, 0.28)
@export_range(0.5, 4.0, 0.1) var spike_cycle_speed: float = 1.0

@export_group("Procedural Dungeon")
@export var randomize_dungeon_seed: bool = true
@export var fixed_dungeon_seed: int = 0
