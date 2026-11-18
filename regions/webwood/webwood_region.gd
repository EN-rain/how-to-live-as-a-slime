class_name WebwoodRegion
extends Node3D
## Authoritative region container for Spider Silk Forest (Webwood).
## Owns per-world layout markers and per-instance sticky web hazard zones.

const WebwoodProfile = preload("res://regions/webwood/webwood_profile.gd")

@export var profile: WebwoodProfile

## World-owned sticky ground web zones (replaces global static state per world instance).
## Each entry: {"xz": Vector2, "radius": float}
var sticky_web_zones: Array[Dictionary] = []


func get_profile() -> WebwoodProfile:
	if profile == null:
		profile = load("res://regions/webwood/webwood_default_profile.tres") as WebwoodProfile
		if profile == null:
			profile = WebwoodProfile.new()
	return profile


func get_effective_layout() -> Dictionary:
	var p := get_profile()
	var layout := p.validated()
	var center: Vector2 = layout["center"]

	# Allow moving Marker3D children in the scene to override trail, snag, and satellite anchors.
	var ts_m := get_node_or_null("TrailStartMarker") as Marker3D
	if ts_m != null:
		layout["trail_start"] = center + Vector2(ts_m.position.x, ts_m.position.z)
	var tb_m := get_node_or_null("TrailBendMarker") as Marker3D
	if tb_m != null:
		layout["trail_bend"] = center + Vector2(tb_m.position.x, tb_m.position.z)

	var snags_root := get_node_or_null("Snags")
	if snags_root != null and snags_root.get_child_count() > 0:
		var snags: Array[Vector2] = []
		for ch in snags_root.get_children():
			if ch is Marker3D:
				var m := ch as Marker3D
				snags.append(Vector2(m.position.x, m.position.z))
		if snags.size() >= 5:
			layout["snag_offsets"] = snags

	var sat_root := get_node_or_null("Satellites")
	if sat_root != null and sat_root.get_child_count() > 0:
		var sats: Array[Vector2] = []
		for ch in sat_root.get_children():
			if ch is Marker3D:
				var m := ch as Marker3D
				sats.append(center + Vector2(m.position.x, m.position.z))
		if not sats.is_empty():
			layout["satellites"] = sats
	if not layout.has("satellites"):
		var sats: Array[Vector2] = []
		for off: Vector2 in layout["satellite_offsets"]:
			sats.append(center + off)
		layout["satellites"] = sats

	return layout


func sync_markers_from_profile() -> void:
	var p := get_profile()
	var c := p.forest_center
	var ts_m := get_node_or_null("TrailStartMarker") as Marker3D
	if ts_m != null:
		ts_m.position = Vector3(p.trail_start.x - c.x, 0.0, p.trail_start.y - c.y)
	var tb_m := get_node_or_null("TrailBendMarker") as Marker3D
	if tb_m != null:
		tb_m.position = Vector3(p.trail_bend.x - c.x, 0.0, p.trail_bend.y - c.y)


func is_in_sticky_web(pos: Vector3) -> bool:
	if sticky_web_zones.is_empty():
		return false
	var layout := get_effective_layout()
	var center: Vector2 = layout["center"]
	var f_rad: float = float(layout["forest_radius"])
	if absf(pos.x - center.x) > f_rad or absf(pos.z - center.y) > f_rad:
		return false
	var pxz := Vector2(pos.x, pos.z)
	for z: Dictionary in sticky_web_zones:
		var zxz: Vector2 = z["xz"]
		var r: float = float(z["radius"])
		if pxz.distance_squared_to(zxz) <= r * r:
			return true
	return false
