extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sdf := CaveSDF.new(1337)
	var terrain_sc := load("res://terrain/terrain.tscn") as PackedScene
	var terrain := terrain_sc.instantiate() as TerrainScene
	terrain.enable_cave = true
	root.add_child(terrain)
	await process_frame

	print("Checking karst_h vs SDF surface y around mouth perimeter (u, s):")
	var angles := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, -0.5, -1.0, -1.5, -2.0]
	for ang: float in angles:
		for r: float in [0.55, 0.64, 0.68, 0.75, 0.85]:
			var u := cos(ang) * 16.5 * r
			var s := 3.5 + sin(ang) * 13.5 * r
			var w := CaveLayout.to_world(Vector3(u, 0.0, s))
			var th := terrain.sample_height(w.x, w.z)
			var pt := CaveSDF.eval_mouth_patch_t(u, s)
			# Find SDF y=0 crossing near th
			var sdf_y := -999.0
			var prev_d := sdf.eval_sdf_full(u, th + 3.0, s, th)
			for step in range(1, 120):
				var yy := th + 3.0 - float(step) * 0.1
				var d := sdf.eval_sdf_full(u, yy, s, th)
				if prev_d < 0.0 and d >= 0.0:
					sdf_y = yy + 0.1 * (d / maxf(d - prev_d, 1e-4))
					break
				prev_d = d
			if absf(th - sdf_y) > 0.4 or r == 0.64:
				print("  ang=%4.1f r=%4.2f (u=%5.1f, s=%5.1f) pt=%4.2f | terrain_y=%5.2f | sdf_y=%5.2f | diff=%5.2f" % [
					ang, r, u, s, pt, th, sdf_y, sdf_y - th
				])

	terrain.free()
	quit(0)
