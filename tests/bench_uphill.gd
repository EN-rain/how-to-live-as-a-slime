extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sc := load("res://scenes/main.tscn") as PackedScene
	var main := sc.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	var slime := main.get_node("Slime") as Slime
	var props := main.get_node_or_null("Props")
	var terrain := main.get_node_or_null("TerrainScene") as TerrainScene

	# Test 1: Uphill slope near cave entrance approach (s=-16 -> s=0, climbing toward mouth)
	var start_w := CaveLayout.to_world(Vector3(0.0, 26.5, -18.0))
	var target_w := CaveLayout.to_world(Vector3(0.0, 27.2, 2.0))
	var dir := Vector3(target_w.x - start_w.x, 0.0, target_w.z - start_w.z).normalized()
	start_w.y = terrain.sample_height(start_w.x, start_w.z) + 1.3
	slime.global_position = start_w
	slime._prev_global_pos = start_w
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.update_support()

	var dt := 1.0 / 60.0
	var total_casts := 0
	var total_rests := 0
	var total_intersects := 0
	var prev_y := slime.global_position.y
	var min_dy := 999.0
	var max_dy := -999.0
	var stalled_ticks := 0
	var total_usec := 0

	for tick in 90:
		slime.motor.debug_cast_count = 0
		slime.motor.debug_rest_count = 0
		slime.motor.debug_intersect_count = 0
		var t0 := Time.get_ticks_usec()
		# Simulate running uphill
		var desired := dir * slime.tuning.run_speed
		slime.motor.velocity = slime.motor.velocity.lerp(desired, 1.0 - exp(-slime.tuning.velocity_response * dt))
		slime.motor.recover_overlap()
		slime.motor.move_horizontal(Vector3(slime.motor.velocity.x, 0.0, slime.motor.velocity.z) * dt)
		slime.motor.update_support()
		slime.motor.move_vertical(dt, slime.target_scale)
		slime.motor.recover_overlap()
		slime._sync_proxy()
		var t1 := Time.get_ticks_usec()
		total_usec += (t1 - t0)
		total_casts += slime.motor.debug_cast_count
		total_rests += slime.motor.debug_rest_count
		total_intersects += slime.motor.debug_intersect_count
		var dy := slime.global_position.y - prev_y
		var horiz_spd := Vector2(slime.motor.velocity.x, slime.motor.velocity.z).length()
		if tick > 15:
			min_dy = minf(min_dy, dy)
			max_dy = maxf(max_dy, dy)
			if horiz_spd < slime.tuning.run_speed * 0.7:
				stalled_ticks += 1
		prev_y = slime.global_position.y

	print("TEST 1 (Entrance uphill run 90 ticks):")
	print("  avg_motor_usec=%.1f, casts=%d, rests=%d, intersects=%d" % [float(total_usec) / 90.0, total_casts, total_rests, total_intersects])
	print("  end_pos=%s, dy_range=[%.4f, %.4f], stalled_ticks=%d" % [slime.global_position, min_dy, max_dy, stalled_ticks])

	# Test 2: Spiral Ledge uphill climb (local u=-68.. around ledge)
	var ledge_start := CaveLayout.to_world(Vector3(-73.0, 21.5, 62.0))
	var ledge_dir_w := (CaveLayout.to_world(Vector3(-60.0, 24.0, 56.0)) - ledge_start)
	ledge_dir_w.y = 0.0
	ledge_dir_w = ledge_dir_w.normalized()
	slime.global_position = ledge_start + Vector3(0.0, 1.3, 0.0)
	slime._prev_global_pos = slime.global_position
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.update_support()

	total_casts = 0
	total_rests = 0
	total_intersects = 0
	total_usec = 0
	stalled_ticks = 0
	prev_y = slime.global_position.y
	min_dy = 999.0
	max_dy = -999.0
	for tick in 60:
		slime.motor.debug_cast_count = 0
		slime.motor.debug_rest_count = 0
		slime.motor.debug_intersect_count = 0
		var t0 := Time.get_ticks_usec()
		var desired := ledge_dir_w * slime.tuning.run_speed
		slime.motor.velocity = slime.motor.velocity.lerp(desired, 1.0 - exp(-slime.tuning.velocity_response * dt))
		slime.motor.recover_overlap()
		slime.motor.move_horizontal(Vector3(slime.motor.velocity.x, 0.0, slime.motor.velocity.z) * dt)
		slime.motor.update_support()
		slime.motor.move_vertical(dt, slime.target_scale)
		slime.motor.recover_overlap()
		slime._sync_proxy()
		var t1 := Time.get_ticks_usec()
		total_usec += (t1 - t0)
		total_casts += slime.motor.debug_cast_count
		total_rests += slime.motor.debug_rest_count
		total_intersects += slime.motor.debug_intersect_count
		var dy := slime.global_position.y - prev_y
		var horiz_spd := Vector2(slime.motor.velocity.x, slime.motor.velocity.z).length()
		if tick > 15:
			min_dy = minf(min_dy, dy)
			max_dy = maxf(max_dy, dy)
			if horiz_spd < slime.tuning.run_speed * 0.7:
				stalled_ticks += 1
		prev_y = slime.global_position.y

	print("TEST 2 (Spiral Ledge uphill run 60 ticks):")
	print("  avg_motor_usec=%.1f, casts=%d, rests=%d, intersects=%d" % [float(total_usec) / 60.0, total_casts, total_rests, total_intersects])
	print("  end_pos=%s, dy_range=[%.4f, %.4f], stalled_ticks=%d" % [slime.global_position, min_dy, max_dy, stalled_ticks])

	# Test 3: Measure full props._physics_process(dt) if available
	if props != null and props.has_method("_physics_process"):
		var pt0 := Time.get_ticks_usec()
		for tick in 30:
			props._physics_process(dt)
		var pt1 := Time.get_ticks_usec()
		print("TEST 3 (props._physics_process avg_usec=%.1f)" % [float(pt1 - pt0) / 30.0])

	main.free()
	quit(0)
