extends SceneTree

func _initialize() -> void:
	print("--- PROFILING COMPONENT RENDER COST ---")
	var terrain_scene := load("res://terrain/terrain.tscn") as PackedScene
	var inst := terrain_scene.instantiate() as TerrainScene
	root.add_child(inst)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.position = Vector3(150.0, 80.0, 150.0)
	cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)

	var terrain_node := inst.get_node("Terrain") as MeshInstance3D
	var grass_node := inst.get_node("Grass") as MultiMeshInstance3D
	var water_node := inst.get_node("Water") as MeshInstance3D

	# Warmup
	for i in 5:
		await process_frame

	# Test 1: Terrain ONLY (Water hidden, Grass hidden)
	water_node.visible = false
	grass_node.visible = false
	terrain_node.visible = true
	var t1 := await _measure_frames(30)
	print("1. Terrain ONLY: ", t1, " ms (", 1000.0 / t1, " FPS)")

	# Test 2: Terrain + Water (Grass hidden)
	water_node.visible = true
	grass_node.visible = false
	terrain_node.visible = true
	var t2 := await _measure_frames(30)
	print("2. Terrain + Water: ", t2, " ms (", 1000.0 / t2, " FPS)")

	# Test 3: Terrain + Grass (Water hidden)
	water_node.visible = false
	grass_node.visible = true
	terrain_node.visible = true
	var t3 := await _measure_frames(30)
	print("3. Terrain + Grass: ", t3, " ms (", 1000.0 / t3, " FPS)")

	# Test 4: EVERYTHING (Terrain + Water + Grass)
	water_node.visible = true
	grass_node.visible = true
	terrain_node.visible = true
	var t4 := await _measure_frames(30)
	print("4. ALL (Terrain + Water + Grass): ", t4, " ms (", 1000.0 / t4, " FPS)")

	quit(0)

func _measure_frames(count: int) -> float:
	var total := 0.0
	for i in count:
		var t0 := Time.get_ticks_usec()
		await process_frame
		var t1 := Time.get_ticks_usec()
		total += (t1 - t0) / 1000.0
	return total / float(count)

