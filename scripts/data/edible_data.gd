class_name EdibleData
extends Resource

## One edible kind. Saved as a `.tres` in `resources/edibles/` and assigned to
## an `Edible` node in the Inspector; the spawner just points at the resource.
## Keeping this in data means a new edible is a new file, not a code edit.

## Stable identifier. Also the mesh-cache key, so keep it unique.
@export var id: StringName = &"berry"
## Primitive shape configured on the `.tscn` nodes unless `visual_scene` is set.
@export_enum("sphere", "box", "capsule", "cylinder", "house") var shape: String = "sphere"
## Optional custom `.tscn` visual prefab to instance inside the Edible.
@export var visual_scene: PackedScene
## Visual diameter in metres. The size gate compares this with the slime.
@export_range(0.05, 10.0, 0.01) var size: float = 0.3
## Nutrition added when eaten.
@export_range(1.0, 500.0, 1.0) var nutrition: float = 3.0
@export var color: Color = Color.WHITE
