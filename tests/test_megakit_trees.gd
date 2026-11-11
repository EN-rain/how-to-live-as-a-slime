extends SceneTree

func _init() -> void:
	print("--- Testing Stylized Nature MegaKit Trees ---")
	call_deferred("_run")

func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)

	# 1. Verify MegaKit models load and have meshes
	var models: Dictionary = {}
	var model_paths := {
		"common_1": "res://assets/nature/CommonTree_1.gltf",
		"common_2": "res://assets/nature/CommonTree_2.gltf",
		"pine_1": "res://assets/nature/Pine_1.gltf",
		"pine_2": "res://assets/nature/Pine_2.gltf"
	}

	for key in model_paths:
		var p: String = model_paths[key]
		var sc: PackedScene = load(p)
		if sc == null:
			print("ERROR: Failed to load %s" % p)
			quit(1)
			return
		var inst: Node3D = sc.instantiate()
		var mesh: Mesh = null
		for c in inst.get_children():
			if c is MeshInstance3D and c.mesh != null:
				mesh = c.mesh
				break
		inst.free()
		if mesh == null:
			print("ERROR: No Mesh found in %s" % p)
			quit(2)
			return
		models[key] = mesh
		print("Loaded %s mesh: %s (%d surfaces)" % [key, mesh.get_class(), mesh.get_surface_count()])

	print("All 4 tree archetypes extracted successfully!")

	# 2. Instantiate TerrainScene
	var terrain_sc: PackedScene = load("res://terrain/terrain.tscn")
	var terrain: TerrainScene = terrain_sc.instantiate()
	root_node.add_child(terrain)
	terrain.rebuild()

	# 3. Check determinism of build_tree_data()
	if not terrain.has_method("build_tree_data"):
		print("terrain.gd needs build_tree_data()")
		quit(3)
		return

	var run1: Array[Dictionary] = terrain.build_tree_data()
	var run2: Array[Dictionary] = terrain.build_tree_data()

	if run1.size() != run2.size():
		print("ERROR: Run sizes differ: %d vs %d" % [run1.size(), run2.size()])
		quit(4)
		return

	for i in run1.size():
		var t1: Dictionary = run1[i]
		var t2: Dictionary = run2[i]
		if t1.archetype != t2.archetype or t1.position != t2.position or t1.transform != t2.transform:
			print("ERROR: Non-deterministic tree at index %d!" % i)
			quit(5)
			return

	print("100%% DETERMINISTIC! Placed %d trees identically across runs." % run1.size())

	# 4. Setup Lighting and Camera
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	sun.light_color = Color(1.0, 0.98, 0.92)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root_node.add_child(sun)

	var cam := Camera3D.new()
	root_node.add_child(cam)
	cam.position = Vector3(0.0, 26.0, 35.0)
	cam.look_at(Vector3(15.0, 22.0, -15.0), Vector3.UP)
	cam.current = true

	# Render frames
	for f in 6:
		await process_frame

	# If rendering device is active (non-headless or xvfb), capture preview
	var vp_tex := root.get_viewport().get_texture()
	if vp_tex != null:
		var img := vp_tex.get_image()
		if img != null:
			img.save_png("res://tests/megakit_trees_preview.png")
			print("Saved preview to res://tests/megakit_trees_preview.png (%dx%d)" % [img.get_width(), img.get_height()])

	print("--- test_megakit_trees completed successfully! ---")
	quit(0)
