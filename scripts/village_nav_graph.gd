class_name VillageNavGraph
extends RefCounted
## Lightweight deterministic AStar2D navigation graph built directly from
## VillageBuilder geometry (Gatehouses, Plaza, Stalls, Ring Road, Pier & Paddocks).

var astar := AStar2D.new()
var _center_xz := Vector2(590.0, 2200.0)
var _gate_out_ids: Array[int] = []
var _gate_in_ids: Array[int] = []
var _plaza_ids: Array[int] = []
var _ring_ids: Array[int] = []
var _stall_spots: Array[Dictionary] = []
var _social_spots: Array[Dictionary] = []
var _guard_posts: Array[Vector2] = []
var _shelter_spots: Array[Vector2] = []
var _fisherman_route: Array[Vector2] = []
var _paddock_spots: Array[Vector2] = []
var _next_id: int = 1


func build(village_root: Node) -> void:
	astar.clear()
	_next_id = 1
	_gate_out_ids.clear()
	_gate_in_ids.clear()
	_plaza_ids.clear()
	_ring_ids.clear()
	_stall_spots.clear()
	_social_spots.clear()
	_guard_posts.clear()
	_shelter_spots.clear()
	_fisherman_route.clear()
	_paddock_spots.clear()

	# Inner Plaza Quadrants (routing around the central VillageWell)
	var p_n := _add_pt(_off(0.0, -7.0))
	var p_s := _add_pt(_off(0.0, 7.0))
	var p_w := _add_pt(_off(-7.0, 0.0))
	var p_e := _add_pt(_off(7.0, 0.0))
	var p_nw := _add_pt(_off(-15.5, -15.5))
	var p_ne := _add_pt(_off(15.5, -15.5))
	var p_sw := _add_pt(_off(-15.5, 15.5))
	var p_se := _add_pt(_off(15.5, 15.5))
	_plaza_ids = [p_n, p_s, p_w, p_e, p_nw, p_ne, p_sw, p_se]
	_connect_chain([p_n, p_ne, p_e, p_se, p_s, p_sw, p_w, p_nw], true)
	_connect(p_n, p_nw)
	_connect(p_e, p_ne)
	_connect(p_s, p_se)
	_connect(p_w, p_sw)

	# Cardinal Avenue Midpoints & Ring Road Loop
	var r_n := _add_pt(_off(0.0, -32.0))
	var r_s := _add_pt(_off(0.0, 32.0))
	var r_w := _add_pt(_off(-36.0, 0.0))
	var r_e := _add_pt(_off(36.0, 0.0))
	var r_nw := _add_pt(_off(-36.0, -32.0))
	var r_ne := _add_pt(_off(36.0, -32.0))
	var r_sw := _add_pt(_off(-36.0, 32.0))
	var r_se := _add_pt(_off(36.0, 32.0))
	_ring_ids = [r_n, r_ne, r_e, r_se, r_s, r_sw, r_w, r_nw]
	_connect_chain(_ring_ids, true)
	_connect(p_n, r_n)
	_connect(p_s, r_s)
	_connect(p_w, r_w)
	_connect(p_e, r_e)
	_connect(p_nw, r_nw)
	_connect(p_ne, r_ne)
	_connect(p_sw, r_sw)
	_connect(p_se, r_se)

	# 4 Town Gatehouses (only legal wall crossings!)
	var gates := [
		{"in": Vector2(0.0, -45.0), "gate": Vector2(0.0, -52.5), "out": Vector2(0.0, -70.0), "ring": r_n},
		{"in": Vector2(0.0, 45.0),  "gate": Vector2(0.0, 52.5),  "out": Vector2(0.0, 68.0),  "ring": r_s},
		{"in": Vector2(-49.0, 0.0), "gate": Vector2(-58.5, 0.0), "out": Vector2(-76.0, 0.0), "ring": r_w},
		{"in": Vector2(49.0, 0.0),  "gate": Vector2(58.5, 0.0),  "out": Vector2(76.0, 0.0),  "ring": r_e},
	]
	for g in gates:
		var gin := _add_pt(_off_v(g["in"]))
		var gmid := _add_pt(_off_v(g["gate"]))
		var gout := _add_pt(_off_v(g["out"]))
		_connect(g["ring"], gin)
		_connect(gin, gmid)
		_connect(gmid, gout)
		_gate_in_ids.append(gin)
		_gate_out_ids.append(gout)
		_guard_posts.append(_off_v(g["gate"]))
		_shelter_spots.append(_off_v(g["gate"]))

	# Outer Ring connecting approaches outside curtain walls
	var out_nw := _add_pt(_off(-74.0, -64.0))
	var out_ne := _add_pt(_off(74.0, -64.0))
	var out_sw := _add_pt(_off(-74.0, 66.0))
	var out_se := _add_pt(_off(74.0, 66.0))
	_connect_chain([_gate_out_ids[0], out_ne, _gate_out_ids[3], out_se, _gate_out_ids[1], out_sw, _gate_out_ids[2], out_nw], true)

	# Outer Gatehouse Guard Patrol & Paddocks
	_guard_posts.append_array([
		_off(0.0, -14.0), _off(0.0, 14.0), _off(-36.0, 0.0), _off(36.0, 0.0),
		_off(-36.0, -32.0), _off(36.0, 32.0)
	])
	_paddock_spots = [
		_off(-44.0, 68.0), _off(44.0, 68.0), _off(-78.0, -28.0), _off(78.0, -28.0),
		_off(-32.0, -72.0), _off(32.0, -72.0),
	]

	# Market Stalls & Civic Hangouts (connected to Plaza)
	var stalls := [
		{"pos": _off(-11.0, -9.0), "yaw": 0.4},
		{"pos": _off(11.0, -9.0), "yaw": -0.4},
		{"pos": _off(-11.0, 9.0), "yaw": 2.7},
		{"pos": _off(11.0, 9.0), "yaw": -2.7},
	]
	for st in stalls:
		_stall_spots.append(st)
		_shelter_spots.append(st["pos"])

	_social_spots = [
		{"pos": _off(-6.0, -20.0), "yaw": 0.0, "anim": "Sit_Chair_Idle"},
		{"pos": _off(15.0, -22.0), "yaw": 0.3, "anim": "Cheer"},
		{"pos": _off(-22.0, 14.0), "yaw": 1.2, "anim": "Interact"},
		{"pos": _off(22.0, 14.0), "yaw": -1.2, "anim": "Use_Item"},
		{"pos": _off(-4.2, 4.2), "yaw": -0.8, "anim": "Idle"},
		{"pos": _off(4.2, -4.2), "yaw": 2.3, "anim": "PickUp"},
	]
	_shelter_spots.append_array([_off(-14.0, -21.0), _off(16.0, -22.0), _off(25.0, 12.0), _off(-25.0, 12.0)])

	# Pier Pathway + Boardwalk + Wharf + T-Head Pier Route (from South Gate out to sea)
	var shore_xy: Vector2 = _off(240.0, 210.0)
	var cottage_xy: Vector2 = _off(200.0, 180.0)
	var dock_yaw: float = 0.72
	if village_root != null and village_root.has_meta("dock_shore_xy"):
		shore_xy = village_root.get_meta("dock_shore_xy") as Vector2
		cottage_xy = village_root.get_meta("dock_cottage_xy") as Vector2
		dock_yaw = float(village_root.get_meta("dock_yaw", 0.72))

	var fwd_dock := Vector2(sin(dock_yaw), cos(dock_yaw)).normalized()
	var gate_s_xz := _off(0.0, 55.0)
	var entry_xz := shore_xy - fwd_dock * 30.6
	var ctrl_xz := Vector2(entry_xz.x - fwd_dock.x * 58.0, lerpf(gate_s_xz.y, entry_xz.y, 0.52))
	var prev_pier_id := _gate_out_ids[1]
	for t_step: float in [0.25, 0.50, 0.75, 1.0]:
		var omt: float = 1.0 - t_step
		var pt: Vector2 = omt * omt * gate_s_xz + 2.0 * omt * t_step * ctrl_xz + t_step * t_step * entry_xz
		var pid := _add_pt(pt)
		_connect(prev_pier_id, pid)
		_fisherman_route.append(pt)
		prev_pier_id = pid
	var wharf_pt := shore_xy - fwd_dock * 8.35
	var pier_end_pt := shore_xy + fwd_dock * 17.5
	var cottage_pt := cottage_xy - Vector2(-fwd_dock.y, fwd_dock.x) * 3.8
	var wid := _add_pt(wharf_pt)
	var peid := _add_pt(pier_end_pt)
	var cid := _add_pt(cottage_pt)
	_connect(prev_pier_id, wid)
	_connect(wid, peid)
	_connect(prev_pier_id, cid)
	_fisherman_route.append_array([wharf_pt, pier_end_pt, wharf_pt, cottage_pt])
	var pier_shelter := pier_end_pt - Vector2(-fwd_dock.y, fwd_dock.x) * 2.5
	_shelter_spots.append(pier_shelter)
	_shelter_spots.append(cottage_pt)


func _off(dx: float, dz: float) -> Vector2:
	return _center_xz + Vector2(dx, dz)


func _off_v(v: Vector2) -> Vector2:
	return _center_xz + v


func _add_pt(pos: Vector2) -> int:
	var id := _next_id
	_next_id += 1
	astar.add_point(id, pos)
	return id


func _connect(a: int, b: int) -> void:
	if a > 0 and b > 0 and a != b:
		astar.connect_points(a, b, true)


func _connect_chain(ids: Array[int], closed: bool) -> void:
	for i in range(ids.size() - 1):
		_connect(ids[i], ids[i + 1])
	if closed and ids.size() > 2:
		_connect(ids[ids.size() - 1], ids[0])


func is_inside_village(pos_xz: Vector2) -> bool:
	var rel := pos_xz - _center_xz
	return absf(rel.x) < 62.0 and absf(rel.y) < 56.0


func compute_path_2d(from_xz: Vector2, to_xz: Vector2) -> PackedVector2Array:
	# Direct straight walk when both start & end are open meadows/outdoors
	if not is_inside_village(from_xz) and not is_inside_village(to_xz):
		var direct := from_xz.lerp(to_xz, 0.5)
		if not is_inside_village(direct):
			return PackedVector2Array([to_xz])
	var id_a := astar.get_closest_point(from_xz)
	var id_b := astar.get_closest_point(to_xz)
	if id_a == -1 or id_b == -1:
		return PackedVector2Array([to_xz])
	var pts := astar.get_point_path(id_a, id_b)
	if pts.is_empty():
		return PackedVector2Array([to_xz])
	pts.append(to_xz)
	return pts


func get_nearest_shelter(from_xz: Vector2) -> Vector2:
	var best := _center_xz
	var best_d := INF
	for s in _shelter_spots:
		var d := from_xz.distance_squared_to(s)
		if d < best_d:
			best_d = d
			best = s
	return best


func get_guard_posts() -> Array[Vector2]:
	return _guard_posts


func get_stall_spots() -> Array[Dictionary]:
	return _stall_spots


func get_social_spots() -> Array[Dictionary]:
	return _social_spots


func get_fisherman_route() -> Array[Vector2]:
	return _fisherman_route


func get_paddock_spots() -> Array[Vector2]:
	return _paddock_spots


func get_gate_approaches() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for gid in _gate_out_ids:
		out.append(astar.get_point_position(gid))
	return out
