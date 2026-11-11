extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: main.tscn not found")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var capturer := TreeVisualCapturer.new()
	capturer.name = "TreeVisualCapturer"
	main.add_child.call_deferred(capturer)

class TreeVisualCapturer extends Node3D:
	var frame_count := 0
	var cam: Camera3D
	var target_tree_pos := Vector3.ZERO
	var target_trunk_r := 1.2
	var slime: Slime
	var dir_to_tree := Vector3.FORWARD
	var initial_placed := false

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

		var terrain := get_parent().get_node_or_null("TerrainScene") as TerrainScene

		if not initial_placed and slime != null and terrain != null:
			var trees: Array[Dictionary] = terrain.build_tree_data()
			if trees.is_empty():
				return
			initial_placed = true
			# Find nearest tree to slime
			var min_d := INF
			var best_t: Dictionary = {}
			for t in trees:
				var d := Vector2(t.position.x, t.position.z).length()
				if d < min_d:
					min_d = d
					best_t = t

			target_tree_pos = best_t.position
			target_trunk_r = 0.55 * best_t.scale_xz

			dir_to_tree = Vector3(target_tree_pos.x, 0.0, target_tree_pos.z).normalized()
			var body_r: float = slime.model.body_collision_radius()
			# Place slime 3.5m away from tree trunk
			var approach_dist := target_trunk_r + body_r + 2.5
			var start_pos := target_tree_pos - dir_to_tree * approach_dist
			start_pos.y = terrain.sample_height(start_pos.x, start_pos.z) + 1.2
			slime.global_position = start_pos
			slime.motor.velocity = dir_to_tree * 4.0
			print("Found target tree at %s (r=%.2f), spawned slime at %s" % [str(target_tree_pos), target_trunk_r, str(start_pos)])

		# During frames 1..40, drive slime into tree trunk
		if slime != null and initial_placed and frame_count < 40:
			slime.motor.velocity = dir_to_tree * 4.5

		# Frame 40: Capture close-up contact view
		if frame_count == 40 and slime != null:
			var s_pos := slime.global_position
			var t_pos := target_tree_pos
			# Camera to the side of the slime and tree to clearly see the contact line and profile
			var side_vec := dir_to_tree.cross(Vector3.UP).normalized()
			cam.global_position = s_pos + side_vec * 3.8 + Vector3(0.0, 1.2, 0.0) - dir_to_tree * 0.8
			var look_target := (s_pos + t_pos) * 0.5 + Vector3(0.0, 0.5, 0.0)
			cam.look_at(look_target, Vector3.UP)

		if frame_count == 45:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/tree_collision_contact.png")
					print("SUCCESS: Saved tree_collision_contact.png (%dx%d)" % [img.get_width(), img.get_height()])

		# Frame 46..65: Move camera to panoramic overview showing the big trees towering over the slime
		if frame_count >= 50 and slime != null:
			var s_pos := slime.global_position
			# Elevated wide angle
			cam.global_position = s_pos - dir_to_tree * 14.0 + Vector3(0.0, 9.5, 0.0)
			cam.look_at(s_pos + dir_to_tree * 6.0 + Vector3(0.0, 4.0, 0.0), Vector3.UP)

		if frame_count == 65:
			var vp := get_viewport()
			if vp != null:
				var img := vp.get_texture().get_image()
				if img != null:
					img.save_png("/home/agent/slime/tree_collision_forest_view.png")
					print("SUCCESS: Saved tree_collision_forest_view.png (%dx%d)" % [img.get_width(), img.get_height()])
			get_tree().quit(0)

