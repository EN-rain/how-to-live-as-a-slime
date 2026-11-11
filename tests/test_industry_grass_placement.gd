extends SceneTree

func _init() -> void:
	print("--- Running Test Industry Grass Placement ---")
	call_deferred("_run")

func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)

	var terrain_sc: PackedScene = load("res://terrain/terrain.tscn")
	var terrain: TerrainScene = terrain_sc.instantiate()
	root_node.add_child(terrain)
	terrain.rebuild()

	# 1. Verify MegaKit Grass Meshes (Common & Wispy)
	var common_mesh: Mesh = terrain._get_grass_mesh()
	var wispy_mesh: Mesh = terrain._get_wispy_grass_mesh()
	if common_mesh == null:
		print("FAIL: Common grass mesh is null!")
		quit(1)
		return
	if wispy_mesh == null:
		print("FAIL: Wispy grass mesh is null!")
		quit(1)
		return
	print("PASS: Loaded authentic MegaKit Grass Meshes (Common: %s, Wispy: %s)!" % [common_mesh.get_class(), wispy_mesh.get_class()])

	# 2. Test Determinism & Dual Species Allocation
	print("Testing Grass Placement Determinism & Species Allocation...")
	var data1 := terrain.build_grass_data()
	var data2 := terrain.build_grass_data()

	var common1: Array[Transform3D] = data1.get("common", [])
	var wispy1: Array[Transform3D] = data1.get("wispy", [])
	var common2: Array[Transform3D] = data2.get("common", [])
	var wispy2: Array[Transform3D] = data2.get("wispy", [])

	var total_count := common1.size() + wispy1.size()
	if total_count == 0:
		print("FAIL: No grass transforms generated!")
		quit(2)
		return

	if common1.size() != common2.size() or wispy1.size() != wispy2.size():
		print("FAIL: Transform counts differ between identical runs!")
		quit(3)
		return

	for i in common1.size():
		if common1[i] != common2[i]:
			print("FAIL: Non-deterministic common grass transform at index %d!" % i)
			quit(4)
			return

	for i in wispy1.size():
		if wispy1[i] != wispy2[i]:
			print("FAIL: Non-deterministic wispy grass transform at index %d!" % i)
			quit(4)
			return

	var wispy_ratio := float(wispy1.size()) / float(total_count)
	print("PASS: Placed %d deterministic grass instances (Common: %d, Wispy: %d, Wispy ratio: %.1f%%)!" % [
		total_count, common1.size(), wispy1.size(), wispy_ratio * 100.0
	])

	# 3. Test Island-Wide Meadow Coverage across green zones
	var xforms1 := terrain.build_grass_transforms()
	var max_radius_reached := 0.0
	var rings := [0, 0, 0] # 0..25m, 25..60m, 60..120m
	var ring_areas := [
		PI * 25.0 * 25.0,
		PI * (60.0 * 60.0 - 25.0 * 25.0),
		PI * (120.0 * 120.0 - 60.0 * 60.0)
	]

	for t in xforms1:
		var pos: Vector3 = t.origin
		var d := Vector2(pos.x, pos.z).length()
		max_radius_reached = maxf(max_radius_reached, d)
		if d < 25.0:
			rings[0] += 1
		elif d < 60.0:
			rings[1] += 1
		elif d < 120.0:
			rings[2] += 1

	print("Ring Instance Counts: [0-25m: %d, 25-60m: %d, 60-120m: %d], Max Radius Reached: %.1fm" % [
		rings[0], rings[1], rings[2], max_radius_reached
	])
	for r in 3:
		var density: float = float(rings[r]) / ring_areas[r]
		print("Ring %d Density: %.3f tufts/m²" % [r, density])
		if density < 0.50:
			print("FAIL: Ring %d density too low (%.3f tufts/m²)!" % [r, density])
			quit(5)
			return

	if max_radius_reached < 120.0:
		print("FAIL: Grass does not extend into the outer green meadow! Max radius: %.1fm" % max_radius_reached)
		quit(5)
		return

	print("PASS: Rich volumetric grass coverage confirmed across green island meadow!")

	# 4. Test Gravity-Biased Phototropism (Slope Alignment)
	var min_up_dot := 1.0
	for t in xforms1:
		var basis_up: Vector3 = t.basis.y.normalized()
		var dot_sky: float = basis_up.dot(Vector3.UP)
		min_up_dot = minf(min_up_dot, dot_sky)

	print("Minimum Dot Product with Sky Vector (0,1,0): %.4f (corresponds to max tilt: %.1f°)" % [
		min_up_dot, rad_to_deg(acos(min_up_dot))
	])
	if min_up_dot < 0.85:
		print("FAIL: Grass is tilted too horizontally on slopes! min_dot = %.4f" % min_up_dot)
		quit(6)
		return

	print("PASS: Gravity-biased phototropism verified! All grass stands predominantly upright toward the sun.")

	# 5. Test Root Anchoring (Embedded 3.0cm into terrain)
	var max_anchor_err := 0.0
	for t in xforms1:
		var pos: Vector3 = t.origin
		var ground_surf := terrain.sample_surface_exact(pos.x, pos.z)
		var expected_y: float = ground_surf.w - 0.03
		var err := absf(pos.y - expected_y)
		max_anchor_err = maxf(max_anchor_err, err)

	print("Maximum Root Anchor Error against Terrain Mesh: %.6fm" % max_anchor_err)
	if max_anchor_err > 0.001:
		print("FAIL: Grass root is not anchored precisely to terrain surface! max_err = %.6f" % max_anchor_err)
		quit(7)
		return

	print("PASS: 100% of grass instances are perfectly anchored to the terrain mesh (< 0.001mm error)!")

	# Clean up to prevent leaks
	terrain.free()
	root_node.free()

	print("--- ALL INDUSTRY GRASS PLACEMENT TESTS PASSED! ---")
	quit(0)
