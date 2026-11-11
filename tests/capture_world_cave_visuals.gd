extends SceneTree
## Renders the 8 fixed benchmark camera shots defined in CaveLayout.BENCHMARK_SHOTS
## and logs objective grayscale luminance metrics for honest phase-to-phase review.

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: main.tscn not found")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var capturer := BenchmarkCaveCapturer.new()
	capturer.name = "BenchmarkCaveCapturer"
	main.add_child(capturer)


class BenchmarkCaveCapturer extends Node3D:
	var frame_count := 0
	var shot_idx := 0
	var cam: Camera3D
	var slime: Slime
	var hud: CanvasLayer

	func _ready() -> void:
		cam = Camera3D.new()
		cam.current = true
		cam.near = 0.1
		cam.far = 2000.0
		add_child(cam)

	func _apply_shot(idx: int) -> void:
		var s: Dictionary = CaveLayout.BENCHMARK_SHOTS[idx]
		var slime_w := CaveLayout.to_world(s["slime"] as Vector3)
		var cam_w := CaveLayout.to_world(s["cam"] as Vector3)
		var look_w := CaveLayout.to_world(s["look"] as Vector3)
		if slime != null:
			slime.global_position = slime_w + Vector3(0.0, slime.model.rest_half_height * slime.slime_scale + 0.04, 0.0)
			slime.motor.velocity = Vector3.ZERO
			# Face slime toward look target so eyes read naturally in player-cam shots
			var d := look_w - slime_w
			if d.length_squared() > 0.01:
				slime._facing_yaw = atan2(d.x, d.z)
				slime.set_shader_param("uFacing", slime._facing_yaw)
		cam.fov = float(s["fov"])
		cam.global_position = cam_w
		cam.look_at(look_w, Vector3.UP)

	func _save_and_measure_shot(idx: int) -> void:
		var s: Dictionary = CaveLayout.BENCHMARK_SHOTS[idx]
		var fname: String = String(s["file"])
		var vp := get_viewport()
		if vp == null:
			return
		var img := vp.get_texture().get_image()
		if img == null:
			return
		var out_path := ProjectSettings.globalize_path("res://" + fname)
		if out_path.is_empty() or out_path.begins_with("res://"):
			out_path = fname
		img.save_png(out_path)

		# Compute objective grayscale value metrics (sampled on a 16-pixel stride)
		var w := img.get_width()
		var h := img.get_height()
		var lum_sum := 0.0
		var lum_center_sum := 0.0
		var lum_perim_sum := 0.0
		var n_tot := 0
		var n_cen := 0
		var n_per := 0
		var lum_max := 0.0
		for y in range(48, h, 16):
			var ny := float(y) / float(h)
			for x in range(0, w, 16):
				var nx := float(x) / float(w)
				var c := img.get_pixel(x, y)
				var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				lum_sum += lum
				lum_max = maxf(lum_max, lum)
				n_tot += 1
				if nx > 0.28 and nx < 0.72 and ny > 0.22 and ny < 0.78:
					lum_center_sum += lum
					n_cen += 1
				else:
					lum_perim_sum += lum
					n_per += 1

		print("SHOT %d [%s] -> mean_lum=%.3f | center_lum=%.3f | margin_wall_lum=%.3f | peak_lum=%.3f" % [
			idx + 1, fname,
			lum_sum / float(maxi(n_tot, 1)),
			lum_center_sum / float(maxi(n_cen, 1)),
			lum_perim_sum / float(maxi(n_per, 1)),
			lum_max
		])

	func _process(_delta: float) -> void:
		frame_count += 1
		if slime == null:
			slime = get_parent().get_node_or_null("Slime") as Slime
		if hud == null:
			hud = get_parent().get_node_or_null("HudLayer") as CanvasLayer

		# Frame 1 sets up Shot 0; every 2 frames saves current shot and advances to next (total 17 frames = ~25s!)
		if frame_count == 1:
			_apply_shot(0)
			return

		if frame_count >= 3 and (frame_count % 2 == 1):
			_save_and_measure_shot(shot_idx)
			shot_idx += 1
			if shot_idx >= CaveLayout.BENCHMARK_SHOTS.size():
				get_tree().quit(0)
				return
			_apply_shot(shot_idx)
