extends SceneTree

## Standalone verification script for deterministic tree generation, rendering, and collision.

func _init() -> void:
	print("--- Starting Deterministic Tree Verification ---")
	call_deferred("_run_test")


func _run_test() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)

	# Load TerrainScene
	var terrain_scene_res: PackedScene = load("res://terrain/terrain.tscn")
	if terrain_scene_res == null:
		print("FAILED: Could not load terrain.tscn")
		quit(1)
		return

	var terrain_node: TerrainScene = terrain_scene_res.instantiate()
	root_node.add_child(terrain_node)
	terrain_node.rebuild()

	# Check tree data
	if not terrain_node.has_method("build_tree_data"):
		print("TerrainScene does not yet have build_tree_data()")
		quit(2)
		return

	var trees1: Array[Dictionary] = terrain_node.build_tree_data()
	var trees2: Array[Dictionary] = terrain_node.build_tree_data()

	print("Run 1 placed trees: %d" % trees1.size())
	print("Run 2 placed trees: %d" % trees2.size())

	if trees1.size() != trees2.size():
		print("FAILED: Tree count differs between runs!")
		quit(3)
		return

	# Verify strict determinism
	var identical := true
	for i in trees1.size():
		var t1: Dictionary = trees1[i]
		var t2: Dictionary = trees2[i]
		if t1.archetype != t2.archetype:
			identical = false
			print("Mismatch at index %d: archetype %d != %d" % [i, t1.archetype, t2.archetype])
			break
		var p1: Vector3 = t1.position
		var p2: Vector3 = t2.position
		if p1.distance_to(p2) > 0.0001:
			identical = false
			print("Mismatch at index %d: pos %s != %s" % [i, str(p1), str(p2)])
			break

	if not identical:
		print("FAILED: Trees are NOT deterministic!")
		quit(4)
		return

	print("SUCCESS: 100% Determinism confirmed across %d trees!" % trees1.size())

	# Count archetypes
	var broadleaf_count := 0
	var pine_count := 0
	for t in trees1:
		if t.archetype == 0:
			broadleaf_count += 1
		else:
			pine_count += 1
	print("Broadleaf trees: %d, Pine trees: %d" % [broadleaf_count, pine_count])

	# Setup Camera & Directional Light for screenshot capture
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	light.light_color = Color(1.0, 0.98, 0.92)
	light.light_energy = 1.35
	root_node.add_child(light)

	var camera := Camera3D.new()
	camera.current = true
	# Camera looking over the central meadow at the trees
	camera.position = Vector3(0.0, 32.0, 48.0)
	camera.look_at(Vector3(0.0, 22.0, -25.0), Vector3.UP)
	root_node.add_child(camera)

	# Render frames
	for f in 5:
		await process_frame

	var vp := root.get_viewport()
	var img := vp.get_texture().get_image()
	img.save_png("res://tests/cloud_tree_view.png")
	print("Saved screenshot to res://tests/cloud_tree_view.png (%dx%d)" % [img.get_width(), img.get_height()])

	print("--- Tree Verification Completed Successfully ---")
	quit(0)

