class_name MobData
extends Resource

## One mob kind. Saved as a `.tres` in `resources/mobs/` and assigned to a
## `Mob` node in the Inspector. Behaviours (flies, bite) are data too, so a new
## mob type does not need a new script.

## Stable identifier used for debugging and the mesh cache.
@export var id: StringName = &"villager"
## Visual diameter in metres. Bigger than the slime means it can bite you.
@export_range(0.05, 6.0, 0.01) var size: float = 1.1
## Nutrition added when the slime eats it.
@export_range(1.0, 500.0, 1.0) var nutrition: float = 30.0
@export var speed: float = 2.2
@export var flee_speed: float = 4.4
## Hovers and ignores gravity; also builds wings instead of a head.
@export var flies: bool = false
@export var color: Color = Color(0.55, 0.36, 0.45)
@export var attack_range: float = 1.6
@export var bite_damage: float = 9.0
@export var bite_cooldown: float = 1.1
