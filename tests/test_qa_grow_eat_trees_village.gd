extends SceneTree

const PropSys = preload("res://scripts/props.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> bool:
	if cond:
		print("PASS: ", msg)
		return true
	_failures += 1
	printerr("FAIL: ", msg)
	return false


func _audit_node(node: Node, label: String, out: Array[String]) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape == null:
			out.append("%s :: CollisionShape3D '%s' has null shape" % [label, cs.get_path()])
	elif node is CollisionObject3D:
		var has_shape := false
		for ch in node.get_children():
			if ch is CollisionShape3D or ch is CollisionPolygon3D:
				has_shape = true
				break
		if not has_shape:
			out.append("%s :: %s '%s' has no CollisionShape3D child" % [label, node.get_class(), node.get_path()])
	elif node is Path3D:
		var p3 := node as Path3D
		if p3.curve == null or p3.curve.point_count == 0:
			out.append("%s :: Path3D '%s' has empty/null curve" % [label, p3.get_path()])
	for ch in node.get_children():
		_audit_node(ch, label, out)


func _run() -> void:
	print("=== FULL QA: WARNING AUDIT + SLIME GROWTH + TREE & VILLAGE EATING ===")

	# 1. Audit scene node configuration warnings
	var audit_scenes := [
		"res://main_menu/main_menu.tscn",
		"res://scenes/slime.tscn",
		"res://terrain/terrain.tscn",
		"res://terrain/cave/cave.tscn",
		"res://regions/skeleton_crypt/skeleton_crypt_region.tscn",
		"res://regions/rat_warren/rat_warren_region.tscn",
	]
	var audit_issues: Array[String] = []
	for sp in audit_scenes:
		var ps := load(sp) as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			get_root().add_child(inst)
			for _i in range(6):
				await process_frame
			_audit_node(inst, sp, audit_issues)
			inst.queue_free()
			for _i in range(3):
				await process_frame
	for iss in audit_issues:
		print("AUDIT ISSUE: ", iss)
	_check(audit_issues.is_empty(), "Zero node configuration issues across all standalone scenes (found=%d)" % audit_issues.size())

	# 2. Launch Main Gameplay Scene & Run Playthrough
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for _i in range(25):
		await physics_frame

	var main_issues: Array[String] = []
	_audit_node(main, "res://scenes/main.tscn", main_issues)
	for iss in main_issues:
		print("MAIN AUDIT ISSUE: ", iss)
	_check(main_issues.is_empty(), "Zero node configuration issues in live Main scene (found=%d)" % main_issues.size())

	var slime := main.get_node_or_null("Slime") as Slime
	var props := main.get_node_or_null("Ecosystem") as PropSys
	var terrain := main.get_node_or_null("TerrainScene")
	if not _check(slime != null and props != null and terrain != null, "Core Main/Slime/Props/TerrainScene nodes present"):
		quit(1)
		return

	var start_scale := slime.slime_scale
	var start_eaten: int = int(props.eaten)
	_check(start_scale < 0.80, "Slime starts small (scale=%.2f)" % start_scale)

	# Phase 1: Eat nearby sandbox props by pushing into them
	slime.teleport_to_world(Vector2(0.0, 2.0))
	for _i in range(10):
		await physics_frame
	var eaten_props_phase1 := 0
	for p in props.props:
		if p.state == PropSys.STATE_IDLE and not p.is_static and props.is_edible_by_push(slime, p):
			props.devour(p, slime)
			eaten_props_phase1 += 1
			if eaten_props_phase1 >= 12:
				break
	for _i in range(45):
		await physics_frame
	_check(props.eaten > start_eaten and slime.slime_scale > start_scale, "Phase 1: Eating %d small props grew Slime (scale %.2f -> %.2f, eaten=%d)" % [eaten_props_phase1, start_scale, slime.slime_scale, props.eaten])

	# Phase 2: Grow Slime to tree-eating scale and walk through forest trees
	slime.add_volume(260.0)  # ~scale 2.55
	for _i in range(30):
		await physics_frame
	var pre_tree_scale := slime.slime_scale
	var pre_tree_eaten: int = int(props.eaten)
	_check(pre_tree_scale >= 2.1, "Slime reached tree-eating scale (scale=%.2f)" % pre_tree_scale)

	# Walk across nearby forest trees in TerrainScene._cached_tree_data
	var tree_list: Array = terrain.get("_cached_tree_data") as Array
	var eaten_trees := 0
	for t in tree_list:
		var pos: Vector3 = t.position
		if pos.length() > 35.0 and pos.length() < 160.0:
			slime.teleport_to_world(Vector2(pos.x, pos.z))
			for _f in range(6):
				await physics_frame
			if bool(t.get("eaten", false)):
				eaten_trees += 1
			if eaten_trees >= 5:
				break
	_check(eaten_trees >= 5, "Phase 2: Giant Slime devoured %d forest trees (eaten %d -> %d, scale %.2f -> %.2f)" % [eaten_trees, pre_tree_eaten, props.eaten, pre_tree_scale, slime.slime_scale])

	# Phase 3: Grow huge & teleport to Slimebrook Village to eat village props & houses
	slime.add_volume(2200.0)  # ~scale 5.2 (towering over cottages!)
	for _i in range(30):
		await physics_frame
	var pre_village_eaten: int = int(props.eaten)
	var pre_village_scale := slime.slime_scale
	var v_targets := [
		Vector2(590.0, 2120.0),
		Vector2(574.0, 2112.0),
		Vector2(606.0, 2112.0),
		Vector2(578.0, 2138.0),
		Vector2(604.0, 2138.0),
		Vector2(590.0, 2096.0),
	]
	for vt in v_targets:
		slime.teleport_to_world(vt)
		for _f in range(10):
			await physics_frame
	var village_eaten_delta: int = int(props.eaten) - pre_village_eaten
	_check(village_eaten_delta >= 4, "Phase 3: Giant Slime devoured %d Slimebrook Village props/buildings (scale %.2f -> %.2f, total eaten=%d)" % [village_eaten_delta, pre_village_scale, slime.slime_scale, props.eaten])

	var ground_y := float(terrain.call("sample_height", slime.global_position.x, slime.global_position.z))
	_check(slime.global_position.y >= ground_y - 0.5, "Slime remained safely on terrain surface after rampage (y=%.2f vs ground=%.2f)" % [slime.global_position.y, ground_y])

	print("=== FULL QA COMPLETE (failures=%d) ===" % _failures)
	quit(0 if _failures == 0 else 1)
