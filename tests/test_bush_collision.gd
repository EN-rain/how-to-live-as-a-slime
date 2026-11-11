extends SceneTree

func _init() -> void:
	print("--- Running Test Vegetation Passability (Zero Collision) ---")
	call_deferred("_run")

func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)

	var terrain_sc: PackedScene = load("res://terrain/terrain.tscn")
	var terrain: TerrainScene = terrain_sc.instantiate()
	root_node.add_child(terrain)
	terrain.rebuild()

	var veg_node := terrain.get_node_or_null("Vegetation")
	if veg_node != null:
		for child in veg_node.get_children():
			if child is PhysicsBody3D or child is CollisionShape3D:
				print("FAIL: Vegetation node still contains collision body %s!" % child.name)
				quit(1)
				return

	var veg: Array[Dictionary] = terrain.build_vegetation_data()
	var rocks: Array[Dictionary] = terrain.build_rock_data()
	var nearest_bush: Dictionary = {}
	var min_d := INF
	for v in veg:
		if v.archetype == 0: # Bush
			var bp_cand: Vector3 = v.position
			var clear_of_rocks := true
			for rk in rocks:
				if (rk.position as Vector3).distance_to(bp_cand) < 10.5:
					clear_of_rocks = false
					break
			if not clear_of_rocks:
				continue
			var d := Vector2(bp_cand.x, bp_cand.z).length()
			if d < min_d:
				min_d = d
				nearest_bush = v

	if nearest_bush.is_empty():
		print("FAIL: No bushes found!")
		quit(1)
		return

	var bush_pos: Vector3 = nearest_bush.position
	var bush_r: float = 0.95 * nearest_bush.scale
	print("Nearest bush at: %s radius: %.2fm scale: %.2f" % [str(bush_pos), bush_r, nearest_bush.scale])

	var slime_sc: PackedScene = load("res://scenes/slime.tscn")
	var slime: Slime = slime_sc.instantiate()
	root_node.add_child(slime)

	var dir_to_bush := Vector3(bush_pos.x, 0.0, bush_pos.z).normalized()
	var start_p := bush_pos - dir_to_bush * (bush_r + 4.0)
	start_p.y = terrain.sample_height(start_p.x, start_p.z) + 1.2
	slime.global_position = start_p
	slime.motor.velocity = Vector3.ZERO
	for f in 10:
		slime._physics_process(1.0 / 60.0)

	var push_velocity := dir_to_bush * 5.0
	var min_d_center := INF
	for f in 90:
		slime.motor.velocity = push_velocity
		slime._physics_process(1.0 / 60.0)
		var cur_d := Vector2(slime.global_position.x - bush_pos.x, slime.global_position.z - bush_pos.z).length()
		min_d_center = minf(min_d_center, cur_d)

	print("Min distance reached to bush center: %.3fm (bush radius: %.3fm)" % [min_d_center, bush_r])

	# Since vegetation has NO collision, the slime must pass freely through the bush!
	if min_d_center > bush_r * 0.8:
		print("FAIL: Slime was blocked by bush! Vegetation still has collision: min_dist = %.3fm" % min_d_center)
		quit(2)
		return

	print("SUCCESS: Slime glided freely through the bush! Vegetation has ZERO collision!")
	terrain.free()
	root_node.free()
	quit(0)
