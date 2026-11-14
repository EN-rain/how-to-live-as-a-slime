@tool
class_name CaveFeatureNode
extends Node3D
## Authorable geological / water / landmark feature node for the cave SDF & set-dressing.

enum FeatureType {
	POOL,
	SKYLIGHT,
	MOUND,
	RUBBLE_CREST,
	WATERFALL,
	UNDERGROUND_LAKE,
	LAKE_ABYSS_PIT,
	ALCOVE,
	PILLAR,
}

@export var feature_type: FeatureType = FeatureType.ALCOVE:
	set(v):
		feature_type = v
		_refresh_gizmo()
@export var radius_x: float = 6.0:
	set(v):
		radius_x = v
		_refresh_gizmo()
@export var radius_y: float = 4.0:
	set(v):
		radius_y = v
		_refresh_gizmo()
@export var radius_z: float = 6.0:
	set(v):
		radius_z = v
		_refresh_gizmo()
@export var radius_top: float = 2.0
@export var water_y: float = 17.35
@export var rise: float = 2.0
@export var yaw: float = 0.0
@export var top_y: float = 30.0
@export var show_editor_gizmo: bool = true:
	set(v):
		show_editor_gizmo = v
		_refresh_gizmo()

var _gizmo_mesh_inst: MeshInstance3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_gizmo()


func _refresh_gizmo() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var edited_root := get_tree().edited_scene_root
	var in_cave_view := edited_root != null and (edited_root is CaveSystem or edited_root is CaveOriginNode)
	if not show_editor_gizmo or not in_cave_view:
		if _gizmo_mesh_inst != null:
			_gizmo_mesh_inst.visible = false
		return
	if _gizmo_mesh_inst == null:
		_gizmo_mesh_inst = MeshInstance3D.new()
		_gizmo_mesh_inst.name = "_EditorGizmo"
		_gizmo_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.45, 0.95, 0.55, 0.9)
		_gizmo_mesh_inst.material_override = mat
		add_child(_gizmo_mesh_inst)
	_gizmo_mesh_inst.visible = true
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var segs := 16
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		im.surface_add_vertex(Vector3(cos(a0) * radius_x, 0.0, sin(a0) * radius_z))
		im.surface_add_vertex(Vector3(cos(a1) * radius_x, 0.0, sin(a1) * radius_z))
	im.surface_end()
	_gizmo_mesh_inst.mesh = im

