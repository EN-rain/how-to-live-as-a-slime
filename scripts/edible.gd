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

static var _mesh_cache: Dictionary = {}

@export var kind := "berry"

var size := 0.3
var nutrition := 3.0
var color := Color.WHITE

var _mesh: MeshInstance3D
var _parts: Array[MeshInstance3D] = []
var _being_eaten := false


func _ready() -> void:
	add_to_group("edible")
	var cfg: Dictionary = KINDS.get(kind, KINDS["berry"])
	size = float(cfg["size"])
	nutrition = float(cfg["nutrition"])
	color = cfg["color"]
	rotation.y = randf() * TAU
	_mesh = $Mesh
	_build_visuals(cfg)
	_build_collision()


static func _mesh_for(edible_kind: String, cfg: Dictionary) -> Mesh:
	if _mesh_cache.has(edible_kind):
		return _mesh_cache[edible_kind]
	var mesh_size := float(cfg["size"])
	var mesh: Mesh
	match String(cfg["shape"]):
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = mesh_size * 0.5
			sphere.height = mesh_size
			sphere.radial_segments = 16
			sphere.rings = 8
			mesh = sphere
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(mesh_size, mesh_size * 1.1, mesh_size)
			mesh = box
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = mesh_size * 0.35
			capsule.height = mesh_size * 0.9
			mesh = capsule
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = mesh_size * 0.35
			cylinder.bottom_radius = mesh_size * 0.4
			cylinder.height = mesh_size * 1.1
			mesh = cylinder
		"house":
			var house := BoxMesh.new()
			house.size = Vector3(mesh_size, mesh_size * 0.9, mesh_size * 0.8)
			mesh = house
		_:
			var fallback := SphereMesh.new()
			fallback.radius = mesh_size * 0.5
			fallback.height = mesh_size
			mesh = fallback
	_mesh_cache[edible_kind] = mesh
	return mesh


func _build_visuals(cfg: Dictionary) -> void:
	# Shared per kind: one material for all 10 bugs, 8 berries, ...
	var mat := ToonMaterial.shared(color, size * 0.03)
	_mesh.mesh = _mesh_for(kind, cfg)
	_mesh.material_override = mat
	# Only big props cast shadows; 66 tiny props would just cost shadow-map time.
	_mesh.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if size >= 1.5
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_mesh.visibility_range_end = clampf(32.0 + size * 14.0, 32.0, 75.0)
	_parts.append(_mesh)
	if String(cfg["shape"]) == "house":
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(size * 1.1, size * 0.5, size * 0.9)
		roof.mesh = prism
		roof.material_override = mat
		roof.position.y = size * 0.7
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_mesh.add_child(roof)
		_parts.append(roof)


## Instance-level dissolve, so the material stays shared between props.
func _set_dissolve(value: float) -> void:
	for part in _parts:
		part.set_instance_shader_parameter("dissolve", value)


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
	# Deferred: absorb() runs inside an area_entered callback, and Godot blocks
	# monitorable changes during physics signal flushing.
	set_deferred("monitorable", false)
	$Collision.set_deferred("disabled", true)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target.global_position, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_method(_set_dissolve, 0.0, 1.0, 0.3)
	tween.chain().tween_callback(queue_free)
