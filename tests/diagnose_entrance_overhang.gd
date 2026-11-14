extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sc := load("res://scenes/main.tscn") as PackedScene
	var main := sc.instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame

	var terrain := main.get_node("TerrainScene") as TerrainScene
	var sdf := CaveSDF.new()

	print("=== Entrance Cross-Section (u=0, s=-8..22) ===")
	for s_i in range(-8, 23, 2):
		var s := float(s_i)
		var u := 0.0
		var w := CaveLayout.to_world(Vector3(u, 27.2, s))
		var h_ow := terrain.sample_height(w.x, w.z)
		var pt := CaveSDF.eval_mouth_patch_t(u, s)
		var wp := Vector3(w.x, h_ow, w.z)
		var cut := CaveSDF.is_quad_in_cave_cutout(wp, wp, wp, wp)
		# Find cave void ceiling/floor at u=0, s
		var ceil_y := -1.0
		var floor_y := -1.0
		for y_i in range(240, 400):
			var y := float(y_i) * 0.1
			var d := sdf.eval_sdf_full(u, y, s, h_ow)
			if d < 0.0:
				if floor_y < 0.0:
					floor_y = y
				ceil_y = y
		print("s=%4.1f | karst_h=%5.2f | patch_t=%.3f | cut=%5s | cave_air=[%5.2f .. %5.2f]" % [s, h_ow, pt, str(cut), floor_y, ceil_y])

	main.free()
	quit(0)
