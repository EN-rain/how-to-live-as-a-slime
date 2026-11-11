extends SceneTree

func _init() -> void:
	print("--- Running Test Stones & Vegetation ---")
	call_deferred("_run")

func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)

	# 1. Instantiate Terrain
	var terrain_sc: PackedScene = load("res://terrain/terrain.tscn")
	var terrain: TerrainScene = terrain_sc.instantiate()
	root_node.add_child(terrain)
	terrain.rebuild()

	# 2. Test Determinism of build_rock_data()
	print("Testing Stones/Rocks Determinism...")
	var rocks_run1: Array[Dictionary] = terrain.build_rock_data()
	var rocks_run2: Array[Dictionary] = terrain.build_rock_data()

	if rocks_run1.is_empty():
		print("ERROR: No rocks generated!")
		quit(1)
		return

	if rocks_run1.size() != rocks_run2.size():
		print("ERROR: Rock counts differ: %d vs %d" % [rocks_run1.size(), rocks_run2.size()])
		quit(2)
		return

	for i in rocks_run1.size():
		var r1 := rocks_run1[i]
		var r2 := rocks_run2[i]
		if r1.archetype != r2.archetype or r1.position != r2.position or r1.transform != r2.transform:
			print("ERROR: Non-deterministic rock at index %d!" % i)
			quit(3)
			return

	print("PASS: Placed %d deterministic stones & boulders across the island (100%% identical across runs)!" % rocks_run1.size())

	# 3. Test Determinism of build_vegetation_data()
	print("Testing Vegetation Determinism...")
	var veg_run1: Array[Dictionary] = terrain.build_vegetation_data()
	var veg_run2: Array[Dictionary] = terrain.build_vegetation_data()

	if veg_run1.is_empty():
		print("ERROR: No vegetation generated!")
		quit(4)
		return

	if veg_run1.size() != veg_run2.size():
		print("ERROR: Vegetation counts differ: %d vs %d" % [veg_run1.size(), veg_run2.size()])
		quit(5)
		return

	var archetype_counts := [0, 0, 0]
	for i in veg_run1.size():
		var v1 := veg_run1[i]
		var v2 := veg_run2[i]
		if v1.archetype != v2.archetype or v1.position != v2.position or v1.transform != v2.transform:
			print("ERROR: Non-deterministic vegetation at index %d!" % i)
			quit(6)
			return
		if v1.archetype >= 0 and v1.archetype < 3:
			archetype_counts[v1.archetype] += 1

	print("PASS: Placed %d deterministic vegetation instances (Bushes: %d, Plants: %d, Wildflowers: %d)!" % [
		veg_run1.size(), archetype_counts[0], archetype_counts[1], archetype_counts[2]
	])

	# 4. Test Slime Collision against a Boulder
	print("Testing Slime Collision with nearest boulder...")
	var nearest_rock: Dictionary = {}
	var min_d := INF
	for r in rocks_run1:
		var pos: Vector3 = r.position
		var d := Vector2(pos.x, pos.z).length()
		if d < min_d:
			min_d = d
			nearest_rock = r

	var rock_pos: Vector3 = nearest_rock.position
	var rock_r: float = 1.10 * nearest_rock.scale_xz
	print("Nearest rock at (%.2f, %.2f, %.2f), distance: %.2fm, rock facet radius: %.2fm" % [
		rock_pos.x, rock_pos.y, rock_pos.z, min_d, rock_r
	])

	var slime_sc: PackedScene = load("res://scenes/slime.tscn")
	var slime: Slime = slime_sc.instantiate()
	root_node.add_child(slime)

	var dir_to_rock := Vector3(rock_pos.x, 0.0, rock_pos.z).normalized()
	var start_pos := rock_pos - dir_to_rock * 8.0
	start_pos.y = terrain.sample_height(start_pos.x, start_pos.z) + 1.2
	print("dir_to_rock: ", dir_to_rock, " start_pos: ", start_pos)
	slime.global_position = start_pos
	slime.motor.velocity = Vector3.ZERO

	# Settle slime
	for f in 10:
		slime._physics_process(1.0 / 60.0)
	print("After settle: slime pos=", slime.global_position, " on_ground=", slime.motor.on_ground)

	var body_r := slime.model.body_collision_radius()
	var core_r := slime.model.core_sphere_radius()

	# Drive slime into rock for 90 frames
	var push_velocity := dir_to_rock * 4.5
	var min_dist_to_rock := INF

	for f in 90:
		slime.motor.velocity = push_velocity
		slime._physics_process(1.0 / 60.0)

		var cur_pos := slime.global_position
		var d_rock := Vector2(cur_pos.x - rock_pos.x, cur_pos.z - rock_pos.z).length()
		min_dist_to_rock = minf(min_dist_to_rock, d_rock)

	var expected_stop_dist := rock_r + body_r
	var penetration := expected_stop_dist - min_dist_to_rock
	var core_clearance := min_dist_to_rock - rock_r - core_r
	print("Rock collision test - Expected stop dist: %.3fm, Actual min dist: %.3fm (penetration: %.3fm)" % [
		expected_stop_dist, min_dist_to_rock, penetration
	])
	print("Core clearance to rock surface: %.3fm" % core_clearance)

	if core_clearance < 0.3:
		print("FAIL: Slime body clipped into rock too far! Clearance: %.3fm" % core_clearance)
		quit(7)
		return

	print("SUCCESS: Slime body collided properly with boulder! All tests PASSED!")
	quit(0)

