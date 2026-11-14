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
	var terrain := main.get_node_or_null("TerrainScene") as TerrainScene
	var props := slime.props

	# Place slime right next to the right entrance boulder (local ~ (5.0, 27.3, -5.0)) and push into it
	var start_w := CaveLayout.to_world(Vector3(4.2, 27.3, -5.0))
	start_w.y = terrain.sample_height(start_w.x, start_w.z) + 1.3
	var target_w := CaveLayout.to_world(Vector3(6.8, 27.3, -3.5))
	var dir := Vector3(target_w.x - start_w.x, 0.0, target_w.z - start_w.z).normalized()

	slime.global_position = start_w
	slime._prev_global_pos = start_w
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.update_support()

	var dt := 1.0 / 60.0
	var t_rec1 := 0
	var t_horiz := 0
	var t_sup := 0
	var t_vert := 0
	var t_rec2 := 0
	var t_props := 0
	var t_solid := 0
	var total_casts := 0
	var total_rests := 0
	var total_intersects := 0

	for tick in 60:
		slime.motor.debug_cast_count = 0
		slime.motor.debug_rest_count = 0
		slime.motor.debug_intersect_count = 0
		var desired := dir * slime.tuning.run_speed
		slime.motor.velocity = slime.motor.velocity.lerp(desired, 1.0 - exp(-slime.tuning.velocity_response * dt))

		var t0 := Time.get_ticks_usec()
		slime.motor.recover_overlap()
		var t1 := Time.get_ticks_usec()
		slime.motor.move_horizontal(Vector3(slime.motor.velocity.x, 0.0, slime.motor.velocity.z) * dt)
		var t2 := Time.get_ticks_usec()
		slime.motor.update_support()
		var t3 := Time.get_ticks_usec()
		slime.motor.move_vertical(dt, slime.target_scale)
		var t4 := Time.get_ticks_usec()
		slime.motor.recover_overlap()
		var t5 := Time.get_ticks_usec()
		slime._sync_proxy()
		if props != null:
			props._physics_process(dt)
		var t6 := Time.get_ticks_usec()
		if props != null:
			props._update_solid_uniforms(slime, true)
		var t7 := Time.get_ticks_usec()

		t_rec1 += (t1 - t0)
		t_horiz += (t2 - t1)
		t_sup += (t3 - t2)
		t_vert += (t4 - t3)
		t_rec2 += (t5 - t4)
		t_props += (t6 - t5)
		t_solid += (t7 - t6)
		total_casts += slime.motor.debug_cast_count
		total_rests += slime.motor.debug_rest_count
		total_intersects += slime.motor.debug_intersect_count

	print("=== Rock Collision Profile (60 ticks avg usec) ===")
	print("  rec1=%.1f, horiz=%.1f, sup=%.1f, vert=%.1f, rec2=%.1f, props=%.1f, solid_uni=%.1f" % [
		float(t_rec1) / 60.0, float(t_horiz) / 60.0, float(t_sup) / 60.0,
		float(t_vert) / 60.0, float(t_rec2) / 60.0, float(t_props) / 60.0, float(t_solid) / 60.0
	])
	print("  casts=%d, rests=%d, intersects=%d, end_pos=%s" % [total_casts, total_rests, total_intersects, slime.global_position])

	# Breakdown of update_support() at end_pos
	var reach := lerpf(slime.tuning.climb_reach, slime.tuning.liquid_climb_reach, slime.model.liquid) * slime.model.scale
	var drop := reach + 2.0 * slime.model.scale
	var start := slime.model.foot + Vector3(0, reach, 0)
	var b0 := Time.get_ticks_usec()
	var fr1 := slime.motor._cast(start, Vector3(0, -drop, 0), false, null, 1 | 4)
	var b1 := Time.get_ticks_usec()
	var core_r := slime.model.core_sphere_radius()
	var core_sph := slime.motor.core_sphere_shape(core_r)
	var fr2 := slime.motor._cast(slime.model.foot + Vector3(0, reach + core_r, 0), Vector3(0, -drop, 0), false, core_sph, 1 | 4)
	var b2 := Time.get_ticks_usec()
	var fr3 := slime.motor.ceiling_clearance_up(0.2)
	var b3 := Time.get_ticks_usec()
	print("  sup breakdown: hull_cast=%d us (fr=%s), core_cast=%d us (fr=%s), ceil_cast=%d us (clr=%s)" % [
		b1 - b0, str(fr1), b2 - b1, str(fr2), b3 - b2, str(fr3)
	])

	main.free()
	quit(0)
