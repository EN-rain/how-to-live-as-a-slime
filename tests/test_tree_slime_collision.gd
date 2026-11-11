extends SceneTree

func _init() -> void:
	print("--- Running Test Tree Slime Collision & Sizing ---")
	call_deferred("_run")

func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)

	# 1. Load and build terrain
	var terrain_sc: PackedScene = load("res://terrain/terrain.tscn")
	var terrain: TerrainScene = terrain_sc.instantiate()
	root_node.add_child(terrain)
	terrain.rebuild()

	var trees: Array[Dictionary] = terrain.build_tree_data()
	print("Generated %d deterministic trees." % trees.size())
	if trees.is_empty():
		print("ERROR: No trees generated!")
		quit(1)
		return

	# Verify tree scale is larger (average scale > 2.0)
	var avg_scale := 0.0
	for t in trees:
		avg_scale += t.scale_y
	avg_scale /= float(trees.size())
	print("Average tree scale: %.2fx (heights ~%.1fm to ~%.1fm)" % [avg_scale, avg_scale * 7.5, avg_scale * 11.0])
	if avg_scale < 2.0:
		print("ERROR: Trees are not bigger! Expected avg scale > 2.0, got %.2f" % avg_scale)
		quit(2)
		return

	# 2. Find nearest tree to origin (0, 0)
	var nearest_tree: Dictionary = {}
	var min_d := INF
	for t in trees:
		var pos: Vector3 = t.position
		var d := Vector2(pos.x, pos.z).length()
		if d < min_d:
			min_d = d
			nearest_tree = t

	var tree_pos: Vector3 = nearest_tree.position
	var tree_trunk_r: float = 0.55 * nearest_tree.scale_xz
	print("Nearest tree at (%.2f, %.2f, %.2f), distance: %.2fm, trunk radius: %.2fm" % [
		tree_pos.x, tree_pos.y, tree_pos.z, min_d, tree_trunk_r
	])

	# 3. Instantiate Slime and place it 8 meters away from the nearest tree, facing the tree
	var slime_sc: PackedScene = load("res://scenes/slime.tscn")
	var slime: Slime = slime_sc.instantiate()
	root_node.add_child(slime)

	var dir_to_tree := Vector3(tree_pos.x, 0.0, tree_pos.z).normalized()
	var start_pos := tree_pos - dir_to_tree * 8.0
	var ground_y := terrain.sample_height(start_pos.x, start_pos.z)
	start_pos.y = ground_y + 1.5
	slime.global_position = start_pos
	slime.motor.velocity = Vector3.ZERO

	# Settle slime onto ground
	for f in 10:
		slime._physics_process(1.0 / 60.0)

	var body_r := slime.model.body_collision_radius()
	var core_r := slime.model.core_sphere_radius()
	print("Slime initialized. Body collision radius: %.2fm, Core radius: %.2fm" % [body_r, core_r])

	# 4. Drive slime straight into the tree for 120 frames (2 seconds of continuous pushing)
	print("Walking slime directly into tree...")
	var push_velocity := dir_to_tree * 5.0
	var min_dist_to_trunk := INF

	for f in 120:
		slime.motor.velocity = push_velocity
		slime._physics_process(1.0 / 60.0)

		var cur_pos := slime.global_position
		var d_trunk := Vector2(cur_pos.x - tree_pos.x, cur_pos.z - tree_pos.z).length()
		min_dist_to_trunk = minf(min_dist_to_trunk, d_trunk)

	print("Final distance from slime center to tree trunk center: %.3fm (minimum reached: %.3fm)" % [
		Vector2(slime.global_position.x - tree_pos.x, slime.global_position.z - tree_pos.z).length(),
		min_dist_to_trunk
	])

	# Theoretical contact boundary: tree_trunk_r + body_r
	var expected_stop_dist := tree_trunk_r + body_r
	var penetration := expected_stop_dist - min_dist_to_trunk
	print("Expected contact distance: %.3fm, Actual min distance: %.3fm (penetration: %.3fm)" % [
		expected_stop_dist, min_dist_to_trunk, penetration
	])

	# The slime body must stop against the trunk:
	# Penetration into the tree trunk must be less than 0.25m (small squish allowance)
	# Distance from core to trunk surface:
	var core_to_trunk_surface := min_dist_to_trunk - tree_trunk_r - core_r
	print("Clearance between Core and Tree Trunk surface: %.3fm" % core_to_trunk_surface)

	if min_dist_to_trunk < tree_trunk_r + core_r:
		print("FAIL: Slime body completely clipped into tree until core touched! min_dist: %.3f < %.3f" % [
			min_dist_to_trunk, tree_trunk_r + core_r
		])
		quit(3)
		return

	if core_to_trunk_surface < 0.5:
		print("FAIL: Core is too close to tree trunk! Clearance: %.3fm" % core_to_trunk_surface)
		quit(4)
		return

	print("SUCCESS: Slime body firmly collided with tree trunk! The core safely remained %.2fm inside the body!" % core_to_trunk_surface)
	quit(0)

