extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)

	var terrain := main.get_node("TerrainScene") as TerrainScene
	var slime := main.get_node("Slime") as Slime

	# Configure collision layers
	var rocks_node := terrain.get_node("Rocks")
	var rock_col := rocks_node.get_node("RockColliders") as StaticBody3D
	rock_col.collision_layer = 4 # LAYER_OBSTACLES

	var trees_node := terrain.get_node("Trees")
	var tree_col := trees_node.get_node_or_null("TrunkColliders") as StaticBody3D
	if tree_col: tree_col.collision_layer = 4

	var veg_node := terrain.get_node("Vegetation")
	var veg_col := veg_node.get_node_or_null("VegetationColliders") as StaticBody3D
	if veg_col: veg_col.collision_layer = 4

	var rocks := terrain.build_rock_data()
	# Find first archetype 1 rock
	var test_rock: Dictionary = {}
	for r in rocks:
		if r.archetype == 1:
			test_rock = r
			break

	var rock_pos: Vector3 = test_rock.position
	print("--- VALIDATION TEST ARCHETYPE 1: ZERO PENETRATION ACROSS ALL 8 ANGLES ---")
	print("Rock position: ", rock_pos, " archetype: ", test_rock.archetype)

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

		for f in 100:
			var dt := 1.0 / 60.0
			var motion := push_dir * 4.0 * dt
			var sphere := slime.motor.body_sphere_shape()
			var r := slime.model.body_collision_radius()
			var sweep_pos := slime.global_position

			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = sphere
			q.transform = Transform3D(Basis.IDENTITY, sweep_pos)
			q.motion = motion
			q.collision_mask = 4
			q.collide_with_bodies = true
			q.collide_with_areas = false
			var fr := space.cast_motion(q)

			if float(fr[1]) >= 0.999999 and motion.length_squared() > 1e-8:
				q.motion = Vector3.ZERO
				var overlaps := space.intersect_shape(q, 1)
				if not overlaps.is_empty():
					fr = [0.0, 0.0]

			var safe: float = fr[0]
			var unsafe: float = fr[1]
			if unsafe < 0.999999:
				slime.global_position += motion * safe
				q.transform = Transform3D(Basis.IDENTITY, sweep_pos + motion * unsafe)
				var rest := space.get_rest_info(q)
				if not rest.is_empty():
					var n: Vector3 = rest.normal
					n.y = 0.0
					if n.length_squared() > 1e-6:
						n = n.normalized()
						slime.global_position += n * 0.005
			else:
				slime.global_position += motion

			slime.motor._sync_foot()
			slime.motor.update_support()
			slime.motor.move_vertical(dt, slime.target_scale)

			var ray := PhysicsRayQueryParameters3D.new()
			ray.from = slime.global_position
			ray.to = rock_pos
			ray.collision_mask = 4
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				var d_surf: float = (hit.position - slime.global_position).length()
				min_dist_to_surface = minf(min_dist_to_surface, d_surf)
				if d_surf < r:
					max_penetration = maxf(max_penetration, r - d_surf)

		var cur_r := slime.model.body_collision_radius()
		var cur_core := slime.model.core_sphere_radius()
		var stopped_d := Vector2(slime.global_position.x - rock_pos.x, slime.global_position.z - rock_pos.z).length()

		print("Angle %d (%3.0f°): stop_d_center=%.2fm min_d_surf=%.3fm body_r=%.2fm pen=%.3fm core_clear=%.3fm" % [
			angle_idx, angle_deg, stopped_d, min_dist_to_surface, cur_r, max_penetration,
			(min_dist_to_surface - cur_core)
		])

		if max_penetration > 0.05:
			print("  FAIL: Angle %d penetrated by %.3fm!" % [angle_idx, max_penetration])
			failures += 1

	if failures > 0:
		print("TOTAL FAILURES: %d" % failures)
		quit(1)
	else:
		print("--- ALL 8 APPROACH ANGLES PASSED PERFECTLY! ZERO PENETRATION! ---")
		quit(0)
