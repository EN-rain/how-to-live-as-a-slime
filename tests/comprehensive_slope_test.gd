extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)

	var tester := ComprehensiveSlopeTester.new()
	main.add_child.call_deferred(tester)

class ComprehensiveSlopeTester extends Node3D:
	var slime: Slime
	var step := 0
	var current_test := 0
	# Tests:
	# 0: Gentle hill (15 deg) uphill
	# 1: Gentle hill (15 deg) downhill
	# 2: Moderate hill (25 deg) uphill
	# 3: Moderate hill (25 deg) downhill
	# 4: Steep hill (35 deg) uphill
	# 5: Steep hill (35 deg) downhill

	var tests_passed := 0
	var test_ticks := 0

	func _ready() -> void:
		slime = get_parent().get_node_or_null("Slime") as Slime
		if slime == null:
			get_tree().quit(1)
			return
		_start_test(0)

	func _start_test(idx: int) -> void:
		current_test = idx
		test_ticks = 0

		var angle_deg := 15.0
		var downhill := false
		match idx:
			0: angle_deg = 15.0; downhill = false
			1: angle_deg = 15.0; downhill = true
			2: angle_deg = 25.0; downhill = false
			3: angle_deg = 25.0; downhill = true
			4: angle_deg = 35.0; downhill = false
			5: angle_deg = 35.0; downhill = true

		var angle_rad := deg_to_rad(angle_deg)
		# Clean previous ramp if any
		var old_ramp := get_node_or_null("TestRamp")
		if old_ramp != null:
			old_ramp.free()

		var ramp := StaticBody3D.new()
		ramp.name = "TestRamp"
		ramp.collision_layer = SlimeMotor.LAYER_OBSTACLES
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(12.0, 1.0, 24.0)
		cs.shape = box
		ramp.add_child(cs)
		add_child(ramp)

		var base_y := 35.0
		var ramp_center_y := base_y + 12.0 * sin(angle_rad) * 0.5
		ramp.rotation.x = -angle_rad
		ramp.position = Vector3(0.0, ramp_center_y, 6.0)

		# Sync physics frame
		await get_tree().physics_frame

		if not downhill:
			# Start at bottom
			var dz := -3.0 - 6.0
			var surface_y := ramp_center_y + dz * tan(angle_rad) + 0.5 / cos(angle_rad)
			slime.global_position = Vector3(0.0, surface_y + slime.model.rest_half_height + 0.05, -3.0)
			slime.motor.velocity = Vector3(0.0, 0.0, 6.0)
		else:
			# Start at top of ramp
			var dz := 12.0 - 6.0
			var surface_y := ramp_center_y + dz * tan(angle_rad) + 0.5 / cos(angle_rad)
			slime.global_position = Vector3(0.0, surface_y + slime.model.rest_half_height + 0.05, 12.0)
			slime.motor.velocity = Vector3(0.0, 0.0, -6.0)

		slime.motor.update_support()

	func _physics_process(delta: float) -> void:
		test_ticks += 1
		var downhill := (current_test % 2 == 1)
		var target_vel := Vector3(0.0, 0.0, -6.0 if downhill else 6.0)
		slime.motor.velocity = target_vel

		# Run each test for 60 ticks (1 second)
		if test_ticks == 60:
			var ok := slime.motor.on_ground
			var normal_y := slime.motor.ground_normal.y
			var tilt_dot := slime._visual_up.dot(slime.motor.ground_normal)
			print("Test %d (angle %s, downhill %s): on_ground=%s, normal_y=%.3f, tilt_dot=%.3f, pos=%s" % [
				current_test,
				[15, 15, 25, 25, 35, 35][current_test],
				downhill,
				ok,
				normal_y,
				tilt_dot,
				slime.global_position
			])
			if ok and tilt_dot > 0.80:
				tests_passed += 1

			if current_test < 5:
				_start_test(current_test + 1)
			else:
				print("Comprehensive slope test result: %d/6 tests passed" % tests_passed)
				if tests_passed == 6:
					print("ALL SLOPE TESTS PASSED!")
					get_tree().quit(0)
				else:
					print("SOME SLOPE TESTS FAILED")
					get_tree().quit(1)

