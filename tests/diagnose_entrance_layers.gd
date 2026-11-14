extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sc := load("res://scenes/main.tscn") as PackedScene
	var main := sc.instantiate()
	root.add_child(main)

	for i in 10:
		await process_frame

	var terrain := main.get_node("TerrainScene") as TerrainScene
	var terrain_mesh := terrain.get_node("Terrain") as MeshInstance3D
	var cave_system := terrain.get_node("Cave") as CaveSystem
	var cave_shell := cave_system.get_node_or_null("CaveShell") as MeshInstance3D
	var slime := main.get_node("Slime") as Slime

	var cam := Camera3D.new()
	cam.current = true
	cam.near = 0.1
	cam.far = 1000.0
	main.add_child(cam)

	var s_shot: Dictionary = CaveLayout.BENCHMARK_SHOTS[1] # shot 2
	var slime_w := CaveLayout.to_world(s_shot["slime"] as Vector3)
	var cam_w := CaveLayout.to_world(s_shot["cam"] as Vector3)
	var look_w := CaveLayout.to_world(s_shot["look"] as Vector3)
	slime.global_position = slime_w + Vector3(0.0, 0.72, 0.0)
	cam.fov = float(s_shot["fov"])
	cam.global_position = cam_w
	cam.look_at(look_w, Vector3.UP)

	# 1. Both visible
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://diag_both.png")

	# 2. Only Terrain (CaveShell hidden)
	if cave_shell != null:
		cave_shell.visible = false
	for i in 3:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	img.save_png("res://diag_only_terrain.png")

	# 3. Only CaveShell (Terrain hidden)
	terrain_mesh.visible = false
	if cave_shell != null:
		cave_shell.visible = true
	for i in 3:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	img.save_png("res://diag_only_cave.png")

	print("Diagnostic shots saved!")
	main.free()
	quit(0)
