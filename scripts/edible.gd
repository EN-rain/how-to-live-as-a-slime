class_name Edible
extends Area3D

## A chewable prop. The spawner sets `kind` before adding the node to the tree;
## _ready() builds the mesh, collision and colour for that kind.
##
## Eating contract used by Slime:
##   try_eat(player_size) -> bool   (size gate)
##   absorb(target)                 (dissolve animation, then free)

## Every edible kind: primitive shape, visual size (metres), nutrition, colour.
const KINDS := {
	"bug": {"shape": "sphere", "size": 0.22, "nutrition": 3.0, "color": Color(0.45, 0.3, 0.22)},
	"berry": {"shape": "sphere", "size": 0.28, "nutrition": 4.0, "color": Color(0.85, 0.16, 0.3)},
	"crumb": {"shape": "box", "size": 0.2, "nutrition": 2.0, "color": Color(0.9, 0.75, 0.5)},
	"pebble": {"shape": "sphere", "size": 0.32, "nutrition": 3.0, "color": Color(0.55, 0.58, 0.62)},
	"fruit": {"shape": "sphere", "size": 0.75, "nutrition": 10.0, "color": Color(0.95, 0.6, 0.15)},
	"critter": {"shape": "capsule", "size": 0.85, "nutrition": 12.0, "color": Color(0.55, 0.42, 0.3)},
	"barrel": {"shape": "cylinder", "size": 1.0, "nutrition": 14.0, "color": Color(0.55, 0.35, 0.18)},
	"chicken": {"shape": "capsule", "size": 0.7, "nutrition": 9.0, "color": Color(0.95, 0.93, 0.85)},
	"statue": {"shape": "capsule", "size": 2.4, "nutrition": 55.0, "color": Color(0.62, 0.63, 0.68)},
	"cart": {"shape": "box", "size": 2.0, "nutrition": 40.0, "color": Color(0.6, 0.42, 0.2)},
	"house": {"shape": "house", "size": 3.0, "nutrition": 90.0, "color": Color(0.82, 0.75, 0.62)},
}

@export var kind := "berry"

var size := 0.3
var nutrition := 3.0
var color := Color.WHITE

var _mesh: MeshInstance3D
var _being_eaten := false


func _ready() -> void:
	var cfg: Dictionary = KINDS.get(kind, KINDS["berry"])
	size = float(cfg["size"])
	nutrition = float(cfg["nutrition"])
	color = cfg["color"]
	rotation.y = randf() * TAU
	_mesh = $Mesh
	_build_visuals(cfg)
	_build_collision()


func _build_visuals(cfg: Dictionary) -> void:
	var mat := ToonMaterial.make(color, size * 0.03)
	match String(cfg["shape"]):
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = size * 0.5
			sphere.height = size
			sphere.radial_segments = 16
			sphere.rings = 8
			_mesh.mesh = sphere
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(size, size * 1.1, size)
			_mesh.mesh = box
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = size * 0.35
			capsule.height = size * 0.9
			_mesh.mesh = capsule
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size * 0.35
			cylinder.bottom_radius = size * 0.4
			cylinder.height = size * 1.1
			_mesh.mesh = cylinder
		"house":
			var house := BoxMesh.new()
			house.size = Vector3(size, size * 0.9, size * 0.8)
			_mesh.mesh = house
			var roof := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(size * 1.1, size * 0.5, size * 0.9)
			roof.mesh = prism
			roof.material_override = mat
			roof.position.y = size * 0.7
			_mesh.add_child(roof)
	_mesh.material_override = mat


func _build_collision() -> void:
	var shape := SphereShape3D.new()
	shape.radius = size * 0.8
	$Collision.shape = shape


## Size gate: you can only swallow things you already outgrow.
func try_eat(player_size: float) -> bool:
	return not _being_eaten and size <= player_size


func absorb(target: Node3D) -> void:
	if _being_eaten:
		return
	_being_eaten = true
	monitorable = false
	set_deferred("monitoring", false)
	$Collision.set_deferred("disabled", true)

	var mat := _mesh.material_override as ShaderMaterial
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target.global_position, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if mat:
		tween.tween_method(
			func(value: float) -> void: mat.set_shader_parameter("dissolve", value),
			0.0, 1.0, 0.3
		)
	tween.chain().tween_callback(queue_free)
