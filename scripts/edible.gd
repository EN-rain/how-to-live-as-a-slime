class_name Edible
extends Area3D

## A chewable prop. Assign an `EdibleData` resource (`resources/edibles/*.tres`)
## in the Inspector; _ready() builds the mesh, collision and colour from it.
##
## Eating contract used by Slime:
##   try_eat(player_size) -> bool   (size gate)
##   absorb(target)                 (dissolve animation, then free)

static var _mesh_cache: Dictionary = {}

## Which food this is. Assigning a .tres makes a new edible a data change, not
## a code change.
@export var data: EdibleData

var size := 0.3
var nutrition := 3.0
var color := Color.WHITE

var _mesh: MeshInstance3D
var _parts: Array[MeshInstance3D] = []
var _being_eaten := false


func _ready() -> void:
	add_to_group("edible")
	# Sensible fallback so a freshly placed Edible still runs unset.
	if data == null:
		data = EdibleData.new()
	size = data.size
	nutrition = data.nutrition
	color = data.color
	rotation.y = randf() * TAU
	_mesh = $Mesh
	_build_visuals()
	_build_collision()


static func _mesh_for(edible: EdibleData) -> Mesh:
	var key := String(edible.id)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh_size := edible.size
	var mesh: Mesh
	match edible.shape:
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
	_mesh_cache[key] = mesh
	return mesh


func _build_visuals() -> void:
	# Shared per kind: one material for all 10 bugs, 8 berries, ...
	var mat := ToonMaterial.shared(color, size * 0.03)
	_mesh.mesh = _mesh_for(data)
	_mesh.material_override = mat
	# Only big props cast shadows; 66 tiny props would just cost shadow-map time.
	_mesh.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if size >= 1.5
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_mesh.visibility_range_end = clampf(32.0 + size * 14.0, 32.0, 75.0)
	_parts.append(_mesh)
	if data.shape == "house":
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
