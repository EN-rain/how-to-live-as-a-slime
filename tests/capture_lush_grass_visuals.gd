extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: main.tscn not found")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var capturer := LushGrassCapturer.new()
	capturer.name = "LushGrassCapturer"
	main.add_child(capturer)

class LushGrassCapturer extends Node3D:
	var frame_count := 0
	var cam: Camera3D
	var slime: Slime

	func _ready() -> void:
		cam = Camera3D.new()
		cam.current = true
		cam.fov = 52.0
		cam.near = 0.1
		cam.far = 1800.0
		add_child(cam)

	func _process(_delta: float) -> void:
		frame_count += 1
		if slime == null:
			slime = get_parent().get_node_or_null("Slime") as Slime

		var terrain := get_parent().get_node_or_null("TerrainScene") as TerrainScene

		if frame_count == 1 and slime != null and terrain != null:
			var s_pos := Vector3(15.0, 0.0, 18.0)
			s_pos.y = terrain.sample_height(s_pos.x, s_pos.z) + 1.2
			slime.global_position = s_pos
			slime.motor.velocity = Vector3.ZERO
			cam.global_position = s_pos + Vector3(0.0, 2.2, 5.8)
			cam.look_at(s_pos + Vector3(0.0, 0.6, -1.0), Vector3.UP)

		if frame_count == 3:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/lush_grass_ground_closeup.png")
					print("SUCCESS: Saved lush_grass_ground_closeup.png (%dx%d)" % [img.get_width(), img.get_height()])
			if slime != null:
				var s_pos := slime.global_position
				cam.global_position = s_pos + Vector3(28.0, 22.0, 36.0)
				cam.look_at(s_pos + Vector3(-8.0, 2.0, -18.0), Vector3.UP)

		if frame_count == 5:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/lush_grass_meadow_panoramic.png")
					print("SUCCESS: Saved lush_grass_meadow_panoramic.png (%dx%d)" % [img.get_width(), img.get_height()])
			get_tree().quit(0)
