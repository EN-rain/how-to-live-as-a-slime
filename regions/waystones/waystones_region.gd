class_name WaystonesRegion
extends Node3D
## Authoritative marker container for Continent Trail Waystones.


func get_waystone_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ch in get_children():
		if ch is Marker3D:
			var m := ch as Marker3D
			out.append({
				"xz": Vector2(m.position.x, m.position.z),
				"yaw": m.rotation.y,
			})
	return out
