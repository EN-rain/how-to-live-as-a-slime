@tool
class_name CaveTunnelNode
extends Path3D
## Authorable 3D cave passage node. Edit its Curve3D points in the 3D viewport
## and tune per-waypoint clear widths/heights in the Inspector.

@export var tunnel_id: String = "twilight_passage"
@export var is_crawlway: bool = false
@export var is_ledge_route: bool = false
@export var is_stream_path: bool = false
@export_range(-0.5, 0.5, 0.01) var bedding_lean: float = 0.0
@export var default_width: float = 11.0
@export var default_height: float = 8.0
@export var widths: PackedFloat32Array = PackedFloat32Array()
@export var heights: PackedFloat32Array = PackedFloat32Array()
@export var show_editor_gizmo: bool = true:
	set(v):
		show_editor_gizmo = v
		_refresh_gizmo()

var _gizmo_mesh_inst: MeshInstance3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		if not curve_changed.is_connected(_refresh_gizmo):
			curve_changed.connect(_refresh_gizmo)
		_refresh_gizmo()


func to_tunnel_nodes() -> Array:
	var out: Array = []
	if curve == null:
		return out
	var cnt := curve.point_count
	for i in cnt:
		var local_p := position + curve.get_point_position(i)
		var w := widths[i] if i < widths.size() else default_width
		var h := heights[i] if i < heights.size() else default_height
		out.append({"p": local_p, "w": w, "h": h})
	return out


func to_point_array() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if curve == null:
		return out
	for i in curve.point_count:
		out.append(position + curve.get_point_position(i))
	return out


func set_from_tunnel_nodes(nodes: Array, lean: float = 0.0) -> void:
	bedding_lean = lean
	var c := Curve3D.new()
	var ws := PackedFloat32Array()
	var hs := PackedFloat32Array()
	for n in nodes:
		var d: Dictionary = n
		c.add_point(d["p"] as Vector3)
		ws.append(float(d.get("w", default_width)))
		hs.append(float(d.get("h", default_height)))
	curve = c
	widths = ws
	heights = hs
	_refresh_gizmo()


func set_from_points(pts: Array, lean: float = 0.0) -> void:
	bedding_lean = lean
	var c := Curve3D.new()
	for p in pts:
		c.add_point(p as Vector3)
	curve = c
	_refresh_gizmo()


func _refresh_gizmo() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var edited_root := get_tree().edited_scene_root
	var in_cave_view := edited_root != null and (edited_root is CaveSystem or edited_root is CaveOriginNode)
	if not show_editor_gizmo or not in_cave_view or curve == null or curve.point_count < 2:
		if _gizmo_mesh_inst != null:
			_gizmo_mesh_inst.visible = false
		return
	if _gizmo_mesh_inst == null:
		_gizmo_mesh_inst = MeshInstance3D.new()
		_gizmo_mesh_inst.name = "_EditorGizmo"
		_gizmo_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.25, 0.90, 1.0, 0.9) if not is_crawlway else Color(1.0, 0.55, 0.2, 0.9)
		_gizmo_mesh_inst.material_override = mat
		add_child(_gizmo_mesh_inst)
	_gizmo_mesh_inst.visible = true
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in curve.point_count - 1:
		var a := curve.get_point_position(i)
		var b := curve.get_point_position(i + 1)
		var wa := widths[i] if i < widths.size() else default_width
		var ha := heights[i] if i < heights.size() else default_height
		var wb := widths[i + 1] if i + 1 < widths.size() else default_width
		var hb := heights[i + 1] if i + 1 < heights.size() else default_height
		var dir := (b - a)
		dir.y = 0.0
		var side := Vector3.RIGHT
		if dir.length_squared() > 1e-4:
			side = dir.normalized().cross(Vector3.UP).normalized()
		# Centerline + ceiling + side rails
		im.surface_add_vertex(a)
		im.surface_add_vertex(b)
		im.surface_add_vertex(a + Vector3(0, ha, 0))
		im.surface_add_vertex(b + Vector3(0, hb, 0))
		im.surface_add_vertex(a + side * (wa * 0.5))
		im.surface_add_vertex(b + side * (wb * 0.5))
		im.surface_add_vertex(a - side * (wa * 0.5))
		im.surface_add_vertex(b - side * (wb * 0.5))
	im.surface_end()
	_gizmo_mesh_inst.mesh = im

