extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		push_error("Failed to load main.tscn")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var capturer := ContinentCapturer.new()
	capturer.name = "ContinentCapturer"
	main.add_child.call_deferred(capturer)

class ContinentCapturer extends Node3D:
	var frame_count := 0
	var scenic_cam: Camera3D

	func _ready() -> void:
		scenic_cam = Camera3D.new()
		scenic_cam.current = true
		scenic_cam.fov = 55.0
		scenic_cam.near = 1.0
		scenic_cam.far = 30000.0
		add_child(scenic_cam)

		# 1. Stratospheric panoramic shot of the entire continent surrounded by open ocean
		scenic_cam.global_position = Vector3(2600.0, 2500.0, 2600.0)
		scenic_cam.look_at(Vector3(0.0, 40.0, 0.0), Vector3.UP)

	func _process(_delta: float) -> void:
		frame_count += 1
		var vp := get_viewport()
		if vp == null:
			return

		if frame_count == 15:
			var img := vp.get_texture().get_image()
			if img != null:
				img.save_png("d:/slime/tests/continent_overview.png")
				print("Saved tests/continent_overview.png")

			# 2. Scenic vista looking across the rolling meadows toward the Northern Peaks and Western Mesas
			scenic_cam.global_position = Vector3(0.0, 56.0, 75.0)
			scenic_cam.look_at(Vector3(-40.0, 72.0, -680.0), Vector3.UP)

		if frame_count == 28:
			var img := vp.get_texture().get_image()
			if img != null:
				img.save_png("d:/slime/tests/continent_mountains.png")
				print("Saved tests/continent_mountains.png")

			# 3. Third-person view right behind the slime looking across the vast continental plains
			var slime := get_parent().get_node_or_null("Slime") as Slime
			var slime_pos: Vector3 = slime.global_position if slime != null else Vector3(0.0, 22.0, 0.0)
			scenic_cam.global_position = slime_pos + Vector3(0.0, 2.5, 6.5)
			scenic_cam.look_at(slime_pos + Vector3(0.0, 1.2, -30.0), Vector3.UP)

		if frame_count == 40:
			var slime := get_parent().get_node_or_null("Slime") as Slime
			if slime != null:
				print("Slime ground pos: ", slime.global_position, " support_y: ", slime.motor.support_y, " on_ground: ", slime.motor.on_ground)
			var img := vp.get_texture().get_image()
			if img != null:
				img.save_png("d:/slime/tests/player_continent_view.png")
				print("Saved tests/player_continent_view.png")

			# 4. Angled meadow view highlighting the grass clearings, dense thickets, and sparse transitions
			var pos: Vector3 = slime.global_position if slime != null else Vector3(0.0, 22.0, 0.0)
			scenic_cam.global_position = pos + Vector3(12.0, 9.0, 14.0)
			scenic_cam.look_at(pos + Vector3(-5.0, 0.0, -8.0), Vector3.UP)

		if frame_count == 52:
			var img := vp.get_texture().get_image()
			if img != null:
				img.save_png("d:/slime/tests/grass_clustering_view.png")
				print("Saved tests/grass_clustering_view.png")
			get_tree().quit(0)
