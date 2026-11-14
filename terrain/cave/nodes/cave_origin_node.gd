@tool
class_name CaveOriginNode
extends Node3D
## Root coordinate frame for cave-local (u, y, s) authoring nodes.
## Child CaveTunnelNode, CaveChamberNode, CaveFeatureNode, and Marker3D nodes
## are serialized into CaveLayoutData (res://terrain/cave/cave_layout.tres).

@export var layout_output_path: String = "res://terrain/cave/cave_layout.tres"
@export_tool_button("Populate Nodes from CaveLayout") var btn_populate := populate_from_constants
@export_tool_button("Export Layout to cave_layout.tres") var btn_export := export_layout_resource


func populate_from_constants() -> void:
	for c in get_children():
		c.queue_free()

	var owner_node := get_tree().edited_scene_root if Engine.is_editor_hint() and get_tree() != null else self

	var leans := {
		"twilight_passage": -0.22,
		"hall_throat": 0.18,
		"stream_grotto": -0.20,
		"deep_descent": -0.16,
		"lake_tunnel": 0.14,
		"door_tunnel": -0.12,
	}
	for tname: String in CaveLayout.TUNNELS:
		var tn := CaveTunnelNode.new()
		tn.name = "Tunnel_" + tname
		tn.tunnel_id = tname
		tn.is_crawlway = (tname == "split_crawlway")
		add_child(tn)
		if owner_node != null:
			tn.owner = owner_node
		tn.set_from_tunnel_nodes(CaveLayout.TUNNELS[tname], float(leans.get(tname, 0.04)))

	var ledge_tn := CaveTunnelNode.new()
	ledge_tn.name = "Path_LedgeRoute"
	ledge_tn.tunnel_id = "ledge_route"
	ledge_tn.is_ledge_route = true
	ledge_tn.default_width = CaveLayout.LEDGE_WIDTH
	ledge_tn.default_height = CaveLayout.LEDGE_HEADROOM
	add_child(ledge_tn)
	if owner_node != null:
		ledge_tn.owner = owner_node
	ledge_tn.set_from_points(CaveLayout.LEDGE_ROUTE)

	var stream_tn := CaveTunnelNode.new()
	stream_tn.name = "Path_Stream"
	stream_tn.tunnel_id = "stream_ctrl"
	stream_tn.is_stream_path = true
	add_child(stream_tn)
	if owner_node != null:
		stream_tn.owner = owner_node
	stream_tn.set_from_points(CaveLayout.STREAM_CTRL)

	var ch_leans := {
		"breakdown_fork": -0.15,
		"collapse_hall": 0.14,
		"geode_pocket": -0.10,
		"abyssal_atrium": 0.08,
		"underground_lake": -0.12,
		"vault_sanctum": 0.0,
	}
	for cname: String in CaveLayout.CHAMBERS:
		var ch: Dictionary = CaveLayout.CHAMBERS[cname]
		var cn := CaveChamberNode.new()
		cn.name = "Chamber_" + cname
		cn.chamber_id = cname
		cn.position = ch["c"] as Vector3
		cn.radius_x = float(ch["rx"])
		cn.radius_z = float(ch["rz"])
		cn.height = float(ch["h"])
		cn.bedding_lean = float(ch_leans.get(cname, 0.0))
		add_child(cn)
		if owner_node != null:
			cn.owner = owner_node

	var spawn_m := Marker3D.new()
	spawn_m.name = "SpawnMarker"
	spawn_m.position = CaveLayout.SPAWN
	add_child(spawn_m)
	if owner_node != null:
		spawn_m.owner = owner_node

	var look_m := Marker3D.new()
	look_m.name = "SpawnLookAtMarker"
	look_m.position = CaveLayout.SPAWN_LOOK_AT
	add_child(look_m)
	if owner_node != null:
		look_m.owner = owner_node


func collect_layout_data() -> CaveLayoutData:
	var data := CaveLayout.build_default_layout_data()
	var t_dict: Dictionary = {}
	var t_leans: Dictionary = {}
	var c_dict: Dictionary = {}
	var c_leans: Dictionary = {}
	var alc_arr: Array = []
	var pil_arr: Array = []

	for child in get_children():
		if child is CaveTunnelNode:
			var tn := child as CaveTunnelNode
			if tn.is_ledge_route:
				data.ledge_route = tn.to_point_array()
				data.ledge_width = tn.default_width
				data.ledge_headroom = tn.default_height
			elif tn.is_stream_path:
				data.stream_ctrl = tn.to_point_array()
			else:
				t_dict[tn.tunnel_id] = tn.to_tunnel_nodes()
				t_leans[tn.tunnel_id] = tn.bedding_lean
		elif child is CaveChamberNode:
			var cn := child as CaveChamberNode
			c_dict[cn.chamber_id] = cn.to_chamber_dict()
			c_leans[cn.chamber_id] = cn.bedding_lean
		elif child is CaveFeatureNode:
			var fn := child as CaveFeatureNode
			match fn.feature_type:
				CaveFeatureNode.FeatureType.POOL:
					data.pool = {"c": fn.position, "rx": fn.radius_x, "rz": fn.radius_z, "water_y": fn.water_y}
				CaveFeatureNode.FeatureType.SKYLIGHT:
					data.skylight = {"c": fn.position, "r": fn.radius_x}
				CaveFeatureNode.FeatureType.MOUND:
					data.mound = {"c": fn.position, "r": fn.radius_x, "rise": fn.rise}
				CaveFeatureNode.FeatureType.RUBBLE_CREST:
					data.rubble_crest = {"c": fn.position, "r": fn.radius_x, "rise": fn.rise}
				CaveFeatureNode.FeatureType.WATERFALL:
					data.waterfall = fn.position
				CaveFeatureNode.FeatureType.UNDERGROUND_LAKE:
					data.underground_lake = {"c": fn.position, "rx": fn.radius_x, "rz": fn.radius_z, "water_y": fn.water_y}
				CaveFeatureNode.FeatureType.LAKE_ABYSS_PIT:
					data.lake_abyss_pit = {"c": fn.position, "rx": fn.radius_x, "rz": fn.radius_z, "yaw": fn.yaw}
				CaveFeatureNode.FeatureType.ALCOVE:
					alc_arr.append({"c": fn.position, "rx": fn.radius_x, "ry": fn.radius_y, "rz": fn.radius_z})
				CaveFeatureNode.FeatureType.PILLAR:
					pil_arr.append({"u": fn.position.x, "s": fn.position.z, "y0": fn.position.y, "y1": fn.top_y, "r_bot": fn.radius_x, "r_top": fn.radius_top})
		elif child is Marker3D:
			if child.name == "SpawnMarker":
				data.spawn = child.position
			elif child.name == "SpawnLookAtMarker":
				data.spawn_look_at = child.position

	if not t_dict.is_empty():
		data.tunnels = t_dict
		data.tunnel_leans = t_leans
	if not c_dict.is_empty():
		data.chambers = c_dict
		data.chamber_leans = c_leans
	if not alc_arr.is_empty():
		data.alcoves = alc_arr
	if not pil_arr.is_empty():
		data.pillars = pil_arr
	return data


func export_layout_resource() -> void:
	var data := collect_layout_data()
	var err := ResourceSaver.save(data, layout_output_path)
	if err == OK:
		print("[CaveOriginNode] Saved CaveLayoutData to %s" % layout_output_path)
	else:
		push_error("[CaveOriginNode] Failed to save CaveLayoutData: %s" % err)

