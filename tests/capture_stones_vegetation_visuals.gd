extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: main.tscn not found")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var capturer := StoneVegCapturer.new()
	capturer.name = "StoneVegCapturer"
	main.add_child.call_deferred(capturer)

class StoneVegCapturer extends Node3D:
	var frame_count := 0
	var cam: Camera3D
	var slime: Slime
	var target_pos := Vector3.ZERO
	var initial_placed := false

	func _ready() -> void:
		cam = Camera3D.new()
		cam.current = true
		cam.fov = 50.0
		cam.near = 0.1
		cam.far = 1200.0
		add_child(cam)

	func _process(_delta: float) -> void:
		frame_count += 1
		if slime == null:
			slime = get_parent().get_node_or_null("Slime") as Slime

		var terrain := get_parent().get_node_or_null("TerrainScene") as TerrainScene

		if not initial_placed and slime != null and terrain != null:
			var rocks: Array[Dictionary] = terrain.build_rock_data()
			var veg: Array[Dictionary] = terrain.build_vegetation_data()
			if rocks.is_empty() or veg.is_empty():
				return
			initial_placed = true

			# Pick nearest boulder
			var best_rock: Dictionary = rocks[0]
			var min_dist := INF
			for r in rocks:
				var d := Vector2(r.position.x, r.position.z).length()
				if d < min_dist:
					min_dist = d
					best_rock = r

			target_pos = best_rock.position
			var approach_dir := Vector3(target_pos.x, 0.0, target_pos.z).normalized()
			var s_start := target_pos - approach_dir * 7.5
			s_start.y = terrain.sample_height(s_start.x, s_start.z) + 1.2
			slime.global_position = s_start
			print("Framing scene around rock at %s, slime at %s" % [str(target_pos), str(s_start)])

		# Drive slime toward the rock during frames 5..50 to establish firm physical contact
		if slime != null and initial_placed:
			if frame_count >= 5 and frame_count < 50:
				var to_rock := (target_pos - slime.global_position).normalized()
				slime.motor.velocity = Vector3(to_rock.x, 0.0, to_rock.z) * 4.0
			elif frame_count >= 50:
				slime.motor.velocity = Vector3.ZERO

		# Frame 55: Close-up composition showing slime in contact with rock boulder, wildflowers, and bushes
		if frame_count == 55 and slime != null:
			var s_pos := slime.global_position
			var dir := (target_pos - s_pos).normalized()
			var side := dir.cross(Vector3.UP).normalized()
			# Side profile perpendicular to contact line so the contact boundary is 100% visible
			cam.global_position = (s_pos + target_pos) * 0.5 + side * 5.2 + Vector3(0.0, 1.6, 0.0)
			var look_target := (s_pos + target_pos) * 0.5 + Vector3(0.0, 0.6, 0.0)
			cam.look_at(look_target, Vector3.UP)

		if frame_count == 60:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/stones_and_vegetation_closeup.png")
					print("SUCCESS: Saved stones_and_vegetation_closeup.png (%dx%d)" % [img.get_width(), img.get_height()])

		# Frame 65..85: Elevated scenic panoramic view of island with rocks, trees, and vegetation
		if frame_count >= 70 and slime != null:
			var s_pos := slime.global_position
			cam.global_position = s_pos + Vector3(16.0, 10.0, 20.0)
			cam.look_at(s_pos + Vector3(-4.0, 0.5, -8.0), Vector3.UP)

		if frame_count == 85:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/stones_and_vegetation_panoramic.png")
					print("SUCCESS: Saved stones_and_vegetation_panoramic.png (%dx%d)" % [img.get_width(), img.get_height()])
			get_tree().quit(0)
