extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_sc := load("res://scenes/main.tscn") as PackedScene
	var main := main_sc.instantiate()
	root.add_child(main)

	var slime := main.get_node("Slime") as Slime
	var cam := main.get_node("CameraRig/Camera3D") as Camera3D

	# Wait for terrain and cave generation
	for i in 10:
		await process_frame

	# Slime at entrance mouth meadow: local (0.0, 27.2, -12.0)
	var slime_w := CaveLayout.to_world(Vector3(0.0, 27.2, -12.0))
	slime.global_position = slime_w + Vector3(0.0, 0.72, 0.0)
	slime.motor.velocity = Vector3.ZERO
	slime.motor.support_y = 27.2

	# Position camera behind slime looking forward toward mouth (s = 0..10)
	var cam_w := CaveLayout.to_world(Vector3(1.5, 29.0, -18.0))
	var look_w := CaveLayout.to_world(Vector3(-0.5, 29.0, 0.0))
	cam.global_position = cam_w
	cam.look_at(look_w, Vector3.UP)

	for i in 5:
		await process_frame

	var vp := root.get_viewport()
	var img := vp.get_texture().get_image()
	img.save_png("res://entrance_seam_check.png")
	print("Saved entrance_seam_check.png")
	main.free()
	quit(0)
