extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		quit(1)

func _run() -> void:
	print("--- Testing Jump & Charge-Hold Mechanics ---")
	_check(InputMap.has_action("jump"), "InputMap missing 'jump' action")

	var sc := load("res://scenes/main.tscn") as PackedScene
	var main := sc.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	var slime := main.get_node("Slime") as Slime
	var terrain := main.get_node_or_null("TerrainScene") as TerrainScene
	var dt := 1.0 / 60.0

	# Place on flat meadow at (0, 0)
	var start_w := Vector3(0.0, terrain.sample_height(0.0, 0.0) + slime.model.rest_half_height * slime.slime_scale + slime.tuning.skin, 0.0)
	slime.global_position = start_w
	slime._prev_global_pos = start_w
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.update_support()
	slime.motor.move_vertical(dt, slime.target_scale)

	# 1. Tap jump (charge=0.0 -> ~1.8 m apex)
	var base_y := slime.global_position.y
	slime._execute_jump(0.0)
	var tap_apex := 0.0
	for tick in 90:
		slime.motor.update_support()
		slime.motor.move_vertical(dt, slime.target_scale)
		tap_apex = maxf(tap_apex, slime.global_position.y - base_y)
		if tick > 5 and slime.motor.on_ground:
			break
	print("Tap jump apex = %.3f m (expected ~1.80 m)" % tap_apex)
	_check(tap_apex >= 1.50 and tap_apex <= 2.05, "Tap jump apex out of range: %.3f" % tap_apex)

	# 2. Full charged jump (charge=1.0 -> ~4.0 m apex)
	base_y = slime.global_position.y
	slime._execute_jump(1.0)
	var full_apex := 0.0
	for tick in 140:
		slime.motor.update_support()
		slime.motor.move_vertical(dt, slime.target_scale)
		full_apex = maxf(full_apex, slime.global_position.y - base_y)
		if tick > 5 and slime.motor.on_ground:
			break
	print("Full charged jump apex = %.3f m (expected ~4.00 m)" % full_apex)
	_check(full_apex >= 3.60 and full_apex <= 4.35, "Full jump apex out of range: %.3f" % full_apex)

	# 3. Gentle size scaling (scale=2.0, charge=0.0 -> ~1.8 * sqrt(2) = 2.55 m)
	slime.slime_scale = 2.0
	slime.target_scale = 2.0
	slime._resolve_model()
	var scaled_w := Vector3(0.0, terrain.sample_height(0.0, 0.0) + slime.model.rest_half_height * slime.slime_scale + slime.tuning.skin, 0.0)
	slime.global_position = scaled_w
	slime._prev_global_pos = scaled_w
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.update_support()
	slime.motor.move_vertical(dt, 2.0)
	base_y = slime.global_position.y
	slime._execute_jump(0.0)
	var scaled_apex := 0.0
	for tick in 110:
		slime.motor.update_support()
		slime.motor.move_vertical(dt, slime.target_scale)
		scaled_apex = maxf(scaled_apex, slime.global_position.y - base_y)
		if tick > 5 and slime.motor.on_ground:
			break
	print("Scaled (2.0x) tap jump apex = %.3f m (expected ~2.55 m)" % scaled_apex)
	_check(scaled_apex >= 2.15 and scaled_apex <= 2.95, "Scaled jump apex out of range: %.3f" % scaled_apex)

	# 4. Ceiling clip inside cave entrance (s=10, low roof)
	slime.slime_scale = 1.0
	slime.target_scale = 1.0
	slime._resolve_model()
	var cave_w := CaveLayout.to_world(Vector3(0.0, 26.5, 10.0))
	slime.global_position = cave_w
	slime._prev_global_pos = cave_w
	slime.motor.update_support()
	slime.motor.move_vertical(dt, 1.0)
	var cave_floor_y := slime.global_position.y
	slime._execute_jump(1.0)
	var cave_max_y := cave_floor_y
	for tick in 100:
		slime.motor.update_support()
		slime.motor.move_vertical(dt, 1.0)
		cave_max_y = maxf(cave_max_y, slime.global_position.y)
		if tick > 5 and slime.motor.on_ground:
			break
	print("Cave ceiling clip: floor=%.2f, max_y=%.2f, landed_on_ground=%s" % [cave_floor_y, cave_max_y, str(slime.motor.on_ground)])
	_check(slime.motor.on_ground, "Slime failed to land cleanly after cave jump")

	# 5. Forward arc jump when holding WASD direction
	slime.global_position = start_w
	slime._prev_global_pos = start_w
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.update_support()
	slime.motor.move_vertical(dt, 1.0)
	var arc_start_z := slime.global_position.z
	slime._execute_jump(1.0, Vector3(0.0, 0.0, -1.0))
	for tick in 140:
		slime.motor.move_horizontal(Vector3(slime.motor.velocity.x, 0.0, slime.motor.velocity.z) * dt)
		slime.motor.update_support()
		slime.motor.move_vertical(dt, 1.0)
		if tick > 5 and slime.motor.on_ground:
			break
	var arc_dist := arc_start_z - slime.global_position.z
	print("Forward arc leap distance (charge=1.0, W held) = %.2f m" % arc_dist)
	_check(arc_dist >= 8.0, "Forward arc jump distance too short: %.2f" % arc_dist)

	print("--- ALL JUMP MECHANICS TESTS PASSED! ---")
	main.free()
	quit(0)

