extends SceneTree

func _init() -> void:
	print("--- Benchmarking Concentric Ring Grass Generation ---")
	call_deferred("_run")

func _run() -> void:
	var scn := load("res://scenes/main.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	var terrain := inst.get_node("TerrainScene") as TerrainScene

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337

	var target_total := 50000
	var spacing := 0.82
	var spawn_r := 140.0
	var center := Vector2(-150.0, -159.0)

	var t0 := Time.get_ticks_msec()
	var common_xforms: Array[Transform3D] = []
	var wispy_xforms: Array[Transform3D] = []

	var max_rings := int(ceil(spawn_r / spacing))
	for ring in range(max_rings + 1):
		if (common_xforms.size() + wispy_xforms.size()) >= target_total:
			break
		var r_dist := float(ring) * spacing
		var count := 1 if ring == 0 else int(round(TAU * float(ring)))
		var angle_step := TAU / float(count)
		var ring_phase := rng.randf() * TAU

		for i in count:
			if (common_xforms.size() + wispy_xforms.size()) >= target_total:
				break
			var angle := float(i) * angle_step + ring_phase
			var r_jitter := r_dist + rng.randf_range(-0.25 * spacing, 0.25 * spacing)
			var a_jitter := angle + rng.randf_range(-0.15, 0.15) * angle_step

			var x := r_jitter * cos(a_jitter) + center.x
			var z := r_jitter * sin(a_jitter) + center.y

			if terrain.enable_cave and (CaveSystem.is_in_portal_scatter_exclusion(x, z, true) or terrain.is_point_in_cave_cutout(x, z)):
				continue

			var density := terrain.sample_grass_density(x, z)
			if density < terrain.grass_clearing_threshold:
				continue

			var surf := terrain.sample_surface_exact(x, z)
			var y := surf.w
			var n := Vector3(surf.x, surf.y, surf.z)

			if n.y < terrain.min_grass_normal_y or y < 4.5 or y > 95.0:
				continue

			var is_wispy := rng.randf() >= 0.65
			var up_vec := (Vector3.UP * (1.0 - terrain.grass_slope_gravity_blend) + n * terrain.grass_slope_gravity_blend).normalized()
			var yaw := rng.randf() * TAU
			var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
			var right := up_vec.cross(fwd).normalized()
			fwd = right.cross(up_vec).normalized()

			var base_scale := remap(density, terrain.grass_clearing_threshold, 1.0, 0.95, 1.25)
			var sxz := base_scale * (rng.randf_range(1.10, 1.45) if is_wispy else rng.randf_range(terrain.grass_scale_xz_min, terrain.grass_scale_xz_max))
			var sy := base_scale * (rng.randf_range(1.15, 1.55) if is_wispy else rng.randf_range(terrain.grass_scale_y_min, terrain.grass_scale_y_max))
			var basis := Basis(right * sxz, up_vec * sy, fwd * sxz)
			var xf := Transform3D(basis, Vector3(x, y - 0.03, z))

			if is_wispy:
				wispy_xforms.append(xf)
			else:
				common_xforms.append(xf)

	var elapsed := Time.get_ticks_msec() - t0
	print("Concentric ring grass built in %d ms! Total generated: %d" % [elapsed, common_xforms.size() + wispy_xforms.size()])

	inst.free()
	quit(0)

