extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: main.tscn not found")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var capturer := GrassVisualCapturer.new()
	capturer.name = "GrassVisualCapturer"
	main.add_child.call_deferred(capturer)

class GrassVisualCapturer extends Node3D:
	var frame_count := 0
	var cam: Camera3D
	var slime: Slime

	func _ready() -> void:
		cam = Camera3D.new()
		cam.current = true
		cam.fov = 55.0
		cam.near = 0.1
		cam.far = 1000.0
		add_child(cam)

	func _process(_delta: float) -> void:
		frame_count += 1
		if slime == null:
			slime = get_parent().get_node_or_null("Slime") as Slime

		# Frame 30: Ground-level close-up of grass blades and slime
		if frame_count == 30 and slime != null:
			var s_pos := slime.global_position
			cam.global_position = s_pos + Vector3(2.5, 0.85, 3.2)
			cam.look_at(s_pos + Vector3(-0.3, 0.2, -0.5), Vector3.UP)

		if frame_count == 35:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/industry_grass_closeup.png")
					print("SUCCESS: Saved industry_grass_closeup.png (%dx%d)" % [img.get_width(), img.get_height()])

		# Frame 40..60: Wide eye-level meadow view across the rolling green terrain
		if frame_count >= 45 and slime != null:
			var s_pos := slime.global_position
			cam.global_position = s_pos + Vector3(8.0, 4.2, 12.0)
			cam.look_at(s_pos + Vector3(-6.0, 1.2, -8.0), Vector3.UP)

		if frame_count == 60:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/industry_grass_meadow_view.png")
					print("SUCCESS: Saved industry_grass_meadow_view.png (%dx%d)" % [img.get_width(), img.get_height()])
			get_tree().quit(0)

