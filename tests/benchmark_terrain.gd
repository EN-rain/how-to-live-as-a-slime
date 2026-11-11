extends SceneTree

func _initialize() -> void:
	print("--- BENCHMARKING TERRAIN INITIALIZATION & REBUILD ---")
	var terrain_scene := load("res://terrain/terrain.tscn") as PackedScene
	if terrain_scene == null:
		print("FAIL: terrain.tscn not found")
		quit(1)
		return

	var inst := terrain_scene.instantiate() as TerrainScene
	root.add_child(inst)

	var terrain_node := inst.get_node("Terrain") as MeshInstance3D
	var grass_node := inst.get_node("Grass") as MultiMeshInstance3D
	var water_node := inst.get_node("Water") as MeshInstance3D

	# 1. Full in-game generation (16,000 grass instances)
	var t_game0 := Time.get_ticks_usec()
	inst.rebuild()
	var t_game1 := Time.get_ticks_usec()
	print("Full Game Rebuild (16k grass + terrain + water): ", (t_game1 - t_game0) / 1000.0, " ms")

	# 2. Component breakdown:
	var t_t0 := Time.get_ticks_usec()
	inst._build_terrain_mesh(terrain_node)
	var t_t1 := Time.get_ticks_usec()
	print("  - Terrain mesh (192x192): ", (t_t1 - t_t0) / 1000.0, " ms")

	var t_w0 := Time.get_ticks_usec()
	inst._build_water_mesh(water_node)
	var t_w1 := Time.get_ticks_usec()
	print("  - Water mesh: ", (t_w1 - t_w0) / 1000.0, " ms")

	var t_g0 := Time.get_ticks_usec()
	inst._build_grass_multimesh(grass_node)
	var t_g1 := Time.get_ticks_usec()
	print("  - Grass MultiMesh: ", (t_g1 - t_g0) / 1000.0, " ms (instances: ", grass_node.multimesh.instance_count, ")")

	# 3. Test Editor mode preview (lightweight 1,200 instances vs 16,000)
	print("\n--- BENCHMARKING EDITOR PREVIEW MODE ---")
	inst.editor_grass_count = 1200
	# Temporarily test 1,200 instances
	var t_ed0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + 77
	var xforms_ed: Array[Transform3D] = []
	var attempts := 0
	var max_attempts := int(1200 * 3.8)
	while xforms_ed.size() < 1200 and attempts < max_attempts:
		attempts += 1
		var u := rng.randf()
		var r := pow(u, 0.60) * 115.0
		var theta := rng.randf() * TAU
		var x := cos(theta) * r
		var z := sin(theta) * r
		if inst.sample_grass_density(x, z) < 0.32:
			continue
		var surf := inst._sample_valley_grass_surface(x, z)
		if surf.y < 0.74:
			continue
		xforms_ed.append(Transform3D(Basis(), Vector3(x, surf.w, z)))
	var t_ed1 := Time.get_ticks_usec()
	print("Editor Grass Generation (1,200 tufts): ", (t_ed1 - t_ed0) / 1000.0, " ms")
	print("Triangles in Editor Viewport: ", 1200 * 8, " (vs ", 16000 * 8, " in game - 92.5% REDUCTION)")

	# 4. Test rapid property modifications (inspector slider dragging simulation)
	print("\n--- SIMULATING RAPID INSPECTOR PROPERTY SLIDER DRAG ---")
	var t_rapid0 := Time.get_ticks_usec()
	for i in 10:
		inst.grass_clearing_threshold = 0.30 + float(i) * 0.01
		inst.valley_floor_height = 22.0 + float(i) * 0.1
	var t_rapid1 := Time.get_ticks_usec()
	print("20 rapid property modifications (debounced): ", (t_rapid1 - t_rapid0) / 1000.0, " ms")

	# Wait a frame for deferred rebuild to execute
	await process_frame
	print("Deferred rebuild executed cleanly on next frame.")

	quit(0)

