class_name Edible
extends Area3D

## A chewable prop. Assign an `EdibleData` resource (`resources/edibles/*.tres`)
## in the Inspector; _ready() instantiates its `.tscn` 3D model scene (`data.visual_scene`),
## scales it to `data.size`, and applies the shared cel-shaded `ToonMaterial`.
##
## Eating contract used by Slime:
##   try_eat(player_size) -> bool   (size gate)
##   absorb(target)                 (dissolve animation, then free)

static var _shape_cache: Dictionary = {}

const DEFAULT_VISUAL_SCENE: PackedScene = preload("res://scenes/edibles/berry.tscn")
const SHADOW_MIN_SIZE := 1.5
const OUTLINE_SCALE := 0.03
const COLLISION_RADIUS_RATIO := 0.8
const ABSORB_DURATION := 0.3

## Which food this is. Assigning a .tres makes a new edible a data change, not
## a code change.
@export var data: EdibleData

@export_group("Nodes")
@export var visual_root: Node3D
@export var collision_node: CollisionShape3D

var size := 0.3
var nutrition := 3.0
var color := Color.WHITE

var _visual_root: Node3D
var _collision: CollisionShape3D
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

	_visual_root = visual_root if visual_root != null else ($VisualRoot as Node3D)
	_collision = collision_node if collision_node != null else ($Collision as CollisionShape3D)

	_instantiate_visual_scene()
	_configure_collision()


static func _shape_for(edible: EdibleData) -> SphereShape3D:
	var key := String(edible.id)
	if _shape_cache.has(key):
		return _shape_cache[key]
	var shape := SphereShape3D.new()
	shape.radius = edible.size * COLLISION_RADIUS_RATIO
	_shape_cache[key] = shape
	return shape


func _instantiate_visual_scene() -> void:
	_parts.clear()
	if _visual_root == null:
		return
	for child in _visual_root.get_children():
		child.queue_free()

	var scene_to_spawn: PackedScene = data.visual_scene if data.visual_scene != null else DEFAULT_VISUAL_SCENE
	if scene_to_spawn == null:
		return

	var instance := scene_to_spawn.instantiate()
	_visual_root.add_child(instance)
	_visual_root.scale = Vector3.ONE * size

	# Shared per kind: one material for all 10 bugs, 8 berries, ...
	var mat := ToonMaterial.shared(color, size * OUTLINE_SCALE)
	var shadow_mode := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if size >= SHADOW_MIN_SIZE
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	var vis_end := clampf(32.0 + size * 14.0, 32.0, 75.0)
	_collect_mesh_parts(instance, mat, shadow_mode, vis_end)


func _collect_mesh_parts(
		node: Node,
		mat: ShaderMaterial,
		shadow_mode: GeometryInstance3D.ShadowCastingSetting,
		vis_end: float
	) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		mi.material_override = mat
		mi.cast_shadow = shadow_mode
		mi.visibility_range_end = vis_end
		_parts.append(mi)
	for child in node.get_children():
		_collect_mesh_parts(child, mat, shadow_mode, vis_end)


## Instance-level dissolve, so the material stays shared between props.
func _set_dissolve(value: float) -> void:
	for part in _parts:
		if is_instance_valid(part):
			part.set_instance_shader_parameter("dissolve", value)


func _configure_collision() -> void:
	if _collision != null:
		_collision.shape = _shape_for(data)


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
	if _collision != null:
		_collision.set_deferred("disabled", true)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target.global_position, ABSORB_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, ABSORB_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_method(_set_dissolve, 0.0, 1.0, ABSORB_DURATION)
	tween.chain().tween_callback(queue_free)
