extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)

	var terrain := main.get_node("TerrainScene") as TerrainScene
	var slime := main.get_node("Slime") as Slime

	var rocks := terrain.build_rock_data()
	var test_rock: Dictionary = rocks[0]
	var min_d := INF
	for r in rocks:
		var d := Vector2(r.position.x, r.position.z).length()
		if d < min_d:
			min_d = d
			test_rock = r

	var rock_pos: Vector3 = test_rock.position
	print("--- TEST PRODUCTION ROCK COLLISION (ARCHETYPE 0) ACROSS ALL 8 ANGLES ---")
	print("Testing rock at: ", rock_pos, " archetype: ", test_rock.archetype, " scale_xz: ", test_rock.scale_xz, " scale_y: ", test_rock.scale_y)

	var space := slime.get_world_3d().direct_space_state
	var failures := 0

	for angle_idx in 8:
		var angle := float(angle_idx) * TAU / 8.0
		var approach_dir := Vector3(cos(angle), 0.0, sin(angle))
		var angle_deg := rad_to_deg(angle)

		var start_p := rock_pos + approach_dir * 8.0
		start_p.y = terrain.sample_height(start_p.x, start_p.z) + 1.2
		slime.global_position = start_p
		slime.motor.velocity = Vector3.ZERO
		for f in 5:
			slime._physics_process(1.0 / 60.0)

		var push_dir := -approach_dir
		var min_dist_to_surface := INF
		var max_penetration := 0.0
		var stopped_dist := 0.0

		for f in 100:
			slime.motor.velocity = push_dir * 4.0
			slime._physics_process(1.0 / 60.0)
			slime._process(1.0 / 60.0)

			var ray := PhysicsRayQueryParameters3D.new()
			ray.from = slime.global_position
			ray.to = rock_pos
			ray.collision_mask = 4 # LAYER_OBSTACLES
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				var d_surf: float = (hit.position - slime.global_position).length()
				min_dist_to_surface = minf(min_dist_to_surface, d_surf)
				var body_r := slime.model.body_collision_radius()
				if d_surf < body_r:
					max_penetration = maxf(max_penetration, body_r - d_surf)

		stopped_dist = Vector2(slime.global_position.x - rock_pos.x, slime.global_position.z - rock_pos.z).length()
		var body_r := slime.model.body_collision_radius()
		var core_r := slime.model.core_sphere_radius()

		print("Angle %d (%3.0f°): stop_d_center=%.2fm min_d_surf=%.3fm body_r=%.2fm pen=%.3fm core_clear=%.3fm" % [
			angle_idx, angle_deg, stopped_dist, min_dist_to_surface, body_r, max_penetration,
			(min_dist_to_surface - core_r)
		])

		if max_penetration > 0.05:
			print("  FAIL: Angle %d penetrated rock by %.3fm!" % [angle_idx, max_penetration])
			failures += 1

	if failures > 0:
		print("TOTAL FAILURES: %d" % failures)
		quit(1)
	else:
		print("--- ALL 8 PRODUCTION ANGLES PASSED WITH ZERO PENETRATION! ---")
		quit(0)
