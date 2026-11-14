extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sc := load("res://scenes/main.tscn") as PackedScene
	var main := sc.instantiate()
	root.add_child(main)

	for i in 12:
		await process_frame

	var slime := main.get_node("Slime") as Slime
	var cam := Camera3D.new()
	cam.current = true
	cam.near = 0.1
	cam.far = 1000.0
	main.add_child(cam)

	var views := [
		# Looking out from inside entrance s=8 toward s=-20
		{"slime": Vector3(0.0, 26.2, 6.0), "cam": Vector3(0.0, 27.6, 9.5), "look": Vector3(0.0, 28.0, -15.0), "fov": 65.0, "name": "user_out_s9"},
		# Looking out from s=14 toward s=-15, slightly up
		{"slime": Vector3(0.0, 25.5, 11.0), "cam": Vector3(0.0, 27.2, 15.0), "look": Vector3(1.0, 29.0, -15.0), "fov": 65.0, "name": "user_out_s15"},
		# Looking up/out from upper Spiral Ledge toward Skylight (-62, 56.5, 68)
		{"slime": Vector3(-58.0, 50.0, 78.0), "cam": Vector3(-56.0, 51.5, 81.0), "look": Vector3(-62.0, 56.5, 68.0), "fov": 65.0, "name": "user_skylight_up"},
		# Outside Skylight rim looking across it (above grass blades)
		{"slime": Vector3(-62.0, 56.5, 52.0), "cam": Vector3(-62.0, 62.0, 45.0), "look": Vector3(-62.0, 55.5, 70.0), "fov": 60.0, "name": "user_skylight_rim"},
		# Exact user Pos (-102.5, 55.5, -93.4) -> local (-53.45, 55.5, 70.84) looking across Skylight
		{"slime": Vector3(-53.45, 55.5, 70.84), "cam": Vector3(-49.0, 58.2, 73.0), "look": Vector3(-63.0, 55.5, 67.5), "fov": 60.0, "name": "user_exact_pos"},
	]

	for tv: Dictionary in views:
		var slime_w := CaveLayout.to_world(tv["slime"] as Vector3)
		var cam_w := CaveLayout.to_world(tv["cam"] as Vector3)
		var look_w := CaveLayout.to_world(tv["look"] as Vector3)
		slime.global_position = slime_w + Vector3(0.0, 0.72, 0.0)
		cam.fov = float(tv["fov"])
		cam.global_position = cam_w
		cam.look_at(look_w, Vector3.UP)
		for i in 4:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var fname := "res://" + String(tv["name"]) + ".png"
		img.save_png(fname)
		print("Saved ", fname)

	main.free()
	quit(0)

