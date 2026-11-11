extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: main.tscn not found")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var capturer := CloudVisualCapturer.new()
	capturer.name = "CloudVisualCapturer"
	main.add_child.call_deferred(capturer)

class CloudVisualCapturer extends Node3D:
	var frame_count := 0
	var cam: Camera3D

	func _ready() -> void:
		cam = Camera3D.new()
		cam.current = true
		cam.fov = 65.0
		cam.near = 0.1
		cam.far = 2000.0
		add_child(cam)

	func _process(_delta: float) -> void:
		frame_count += 1
		var slime := get_parent().get_node_or_null("Slime") as Slime
		var slime_pos: Vector3 = slime.global_position if slime != null else Vector3(0.0, 23.2, 0.0)

		if frame_count < 30:
			# Position camera to look across the grass at the slime
			cam.global_position = slime_pos + Vector3(3.0, 2.0, 4.5)
			cam.look_at(slime_pos + Vector3(0.0, 0.6, 0.0), Vector3.UP)
		else:
			# Elevated wide panoramic view
			cam.global_position = slime_pos + Vector3(12.0, 8.0, 14.0)
			cam.look_at(slime_pos + Vector3(-2.0, 0.5, -4.0), Vector3.UP)

		if frame_count == 25:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/cloud_visual_test.png")
					print("SUCCESS: Saved /home/agent/slime/cloud_visual_test.png")
				else:
					print("ERROR: Viewport texture image was null")

		if frame_count == 45:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/cloud_visual_overview.png")
					print("SUCCESS: Saved /home/agent/slime/cloud_visual_overview.png")
			get_tree().quit(0)

