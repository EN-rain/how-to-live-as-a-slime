extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sc := load("res://scenes/main.tscn") as PackedScene
	var main := sc.instantiate()
	root.add_child(main)

	for i in 10:
		await process_frame

	var slime := main.get_node("Slime") as Slime
	var cam := Camera3D.new()
	cam.current = true
	cam.near = 0.1
	cam.far = 1000.0
	main.add_child(cam)

	var test_views := [
		# 1. Close-up in front of mouth looking slightly left/forward
		{"slime": Vector3(0.0, 27.2, -6.0), "cam": Vector3(2.0, 28.5, -11.0), "look": Vector3(-1.0, 28.0, 2.0), "fov": 55.0, "name": "view1_front_close"},
		# 2. Right flank looking across the mouth to the left cliff
		{"slime": Vector3(6.0, 27.5, -4.0), "cam": Vector3(9.0, 29.0, -8.0), "look": Vector3(-4.0, 28.5, 2.0), "fov": 55.0, "name": "view2_right_flank"},
		# 3. Inside threshold looking out or across
		{"slime": Vector3(0.0, 26.5, -1.0), "cam": Vector3(1.5, 27.8, -4.5), "look": Vector3(-2.0, 28.0, 6.0), "fov": 55.0, "name": "view3_threshold"},
		# 4. From slightly above looking down at the mouth
		{"slime": Vector3(-2.0, 27.2, -5.0), "cam": Vector3(3.0, 31.0, -12.0), "look": Vector3(-3.0, 28.0, 0.0), "fov": 50.0, "name": "view4_above_front"},
		# 5. On the approach meadow looking up at the entrance
		{"slime": Vector3(0.0, 26.8, -8.0), "cam": Vector3(1.0, 28.0, -14.0), "look": Vector3(-1.0, 29.0, 2.0), "fov": 52.0, "name": "view5_meadow_up"},
		# 6. Slime near right boulder looking left
		{"slime": Vector3(5.0, 27.3, -6.0), "cam": Vector3(7.5, 28.5, -11.0), "look": Vector3(-2.0, 28.0, 0.0), "fov": 52.0, "name": "view6_right_boulder"},
	]

	for tv: Dictionary in test_views:
		var slime_w := CaveLayout.to_world(tv["slime"] as Vector3)
		var cam_w := CaveLayout.to_world(tv["cam"] as Vector3)
		var look_w := CaveLayout.to_world(tv["look"] as Vector3)
		slime.global_position = slime_w + Vector3(0.0, 0.72, 0.0)
		cam.fov = float(tv["fov"])
		cam.global_position = cam_w
		cam.look_at(look_w, Vector3.UP)
		for i in 3:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var fname := "res://" + String(tv["name"]) + ".png"
		img.save_png(fname)
		print("Saved ", fname)

	main.free()
	quit(0)
