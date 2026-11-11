extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	var runner := Runner.new()
	main.add_child.call_deferred(runner)

class Runner extends Node3D:
	func _ready() -> void:
		var slime: Slime = get_parent().get_node("Slime")
		var cam_rig: OrbitCamera = get_parent().get_node("CameraRig")
		print("--- WSAD DIAGNOSTIC & VERIFICATION TEST ---")
		print("Slime initial pos: ", slime.global_position)
		print("Slime camera: ", slime.camera)
		print("Slime active camera: ", slime.get_active_camera())
		assert(slime.camera != null, "FAIL: Slime camera is null!")

		# 1. Test InputMap events
		for act in ["move_forward", "move_back", "move_left", "move_right", "run"]:
			var evs = InputMap.action_get_events(act)
			var keys: Array[String] = []
			for ev in evs:
				if ev is InputEventKey:
					keys.append("phys:%d key:%d" % [ev.physical_keycode, ev.keycode])
			print("Action [%s] events: %s" % [act, str(keys)])

		# 2. Test hardware key event matching for physical vs logical events
		print("\n--- Testing Physical Keyboard Event Dispatch ---")
		var phys_w := InputEventKey.new()
		phys_w.physical_keycode = KEY_W
		phys_w.keycode = 0
		phys_w.pressed = true
		Input.parse_input_event(phys_w)
		Input.flush_buffered_events()
		var pressed_w = Input.is_action_pressed("move_forward")
		print("Physical scan code W (phys=KEY_W, key=0) -> is_action_pressed('move_forward'): ", pressed_w)
		assert(pressed_w, "FAIL: Physical scan code W was not matched by InputMap!")
		phys_w.pressed = false
		Input.parse_input_event(phys_w)
		Input.flush_buffered_events()

		var log_w := InputEventKey.new()
		log_w.physical_keycode = 0
		log_w.keycode = KEY_W
		log_w.pressed = true
		Input.parse_input_event(log_w)
		Input.flush_buffered_events()
		pressed_w = Input.is_action_pressed("move_forward")
		print("Logical keycode W (phys=0, key=KEY_W) -> is_action_pressed('move_forward'): ", pressed_w)
		assert(pressed_w, "FAIL: Logical keycode W was not matched by InputMap!")
		log_w.pressed = false
		Input.parse_input_event(log_w)
		Input.flush_buffered_events()

		# Settle on terrain
		print("\n--- Settling on terrain ---")
		for i in 30:
			await get_tree().physics_frame
		print("Settled pos: ", slime.global_position, " on_ground: ", slime.motor.on_ground)

		# 3. Test Camera-Relative Forward Movement (W)
		print("\n--- Testing W (Forward) ---")
		var p0 := slime.global_position
		var cam: Camera3D = slime.get_active_camera()
		var cam_fwd := -cam.global_transform.basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized()
		print("Camera horizontal forward: ", cam_fwd)

		Input.action_press("move_forward")
		for i in 60:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		for i in 10:
			await get_tree().physics_frame

		var p_after_w := slime.global_position
		var move_w := p_after_w - p0
		var move_w_horiz := Vector3(move_w.x, 0.0, move_w.z)
		print("W delta horiz: ", move_w_horiz, " length: ", move_w_horiz.length())
		var dot_w := move_w_horiz.normalized().dot(cam_fwd)
		print("W alignment with camera forward (dot): ", dot_w)
		assert(move_w_horiz.length() > 0.5, "FAIL: Slime did not move when pressing W!")
		assert(dot_w > 0.95, "FAIL: Slime did not move along camera forward vector!")

		# 4. Test Camera-Relative Right Movement (D)
		print("\n--- Testing D (Right) ---")
		p0 = slime.global_position
		var cam_right := cam.global_transform.basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		print("Camera horizontal right: ", cam_right)

		Input.action_press("move_right")
		for i in 60:
			await get_tree().physics_frame
		Input.action_release("move_right")
		for i in 10:
			await get_tree().physics_frame

		var p_after_d := slime.global_position
		var move_d := p_after_d - p0
		var move_d_horiz := Vector3(move_d.x, 0.0, move_d.z)
		print("D delta horiz: ", move_d_horiz, " length: ", move_d_horiz.length())
		var dot_d := move_d_horiz.normalized().dot(cam_right)
		print("D alignment with camera right (dot): ", dot_d)
		assert(move_d_horiz.length() > 0.5, "FAIL: Slime did not move when pressing D!")
		assert(dot_d > 0.95, "FAIL: Slime did not move along camera right vector!")

		# 5. Test Camera-Relative Backward Movement (S)
		print("\n--- Testing S (Backward) ---")
		p0 = slime.global_position
		Input.action_press("move_back")
		for i in 60:
			await get_tree().physics_frame
		Input.action_release("move_back")
		for i in 10:
			await get_tree().physics_frame

		var p_after_s := slime.global_position
		var move_s := p_after_s - p0
		var move_s_horiz := Vector3(move_s.x, 0.0, move_s.z)
		print("S delta horiz: ", move_s_horiz, " length: ", move_s_horiz.length())
		var dot_s := move_s_horiz.normalized().dot(-cam_fwd)
		print("S alignment with camera backward (dot): ", dot_s)
		assert(move_s_horiz.length() > 0.5, "FAIL: Slime did not move when pressing S!")
		assert(dot_s > 0.95, "FAIL: Slime did not move along camera backward vector!")

		# 6. Test Camera-Relative Left Movement (A)
		print("\n--- Testing A (Left) ---")
		p0 = slime.global_position
		Input.action_press("move_left")
		for i in 60:
			await get_tree().physics_frame
		Input.action_release("move_left")
		for i in 10:
			await get_tree().physics_frame

		var p_after_a := slime.global_position
		var move_a := p_after_a - p0
		var move_a_horiz := Vector3(move_a.x, 0.0, move_a.z)
		print("A delta horiz: ", move_a_horiz, " length: ", move_a_horiz.length())
		var dot_a := move_a_horiz.normalized().dot(-cam_right)
		print("A alignment with camera left (dot): ", dot_a)
		assert(move_a_horiz.length() > 0.5, "FAIL: Slime did not move when pressing A!")
		assert(dot_a > 0.95, "FAIL: Slime did not move along camera left vector!")

		# 7. Test Movement After Camera Orbit (Rotate 90 degrees)
		print("\n--- Testing Movement After 90 Degree Camera Orbit ---")
		cam_rig.theta += PI * 0.5
		cam_rig._update_camera()
		await get_tree().physics_frame
		await get_tree().physics_frame

		var new_cam_fwd := -cam.global_transform.basis.z
		new_cam_fwd.y = 0.0
		new_cam_fwd = new_cam_fwd.normalized()
		print("Rotated camera forward: ", new_cam_fwd)
		print("Difference from old camera forward (dot): ", new_cam_fwd.dot(cam_fwd))

		p0 = slime.global_position
		Input.action_press("move_forward")
		for i in 60:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		for i in 10:
			await get_tree().physics_frame

		var p_rotated_w := slime.global_position
		var move_rot := p_rotated_w - p0
		var move_rot_horiz := Vector3(move_rot.x, 0.0, move_rot.z)
		var dot_rot := move_rot_horiz.normalized().dot(new_cam_fwd)
		print("W after rotation alignment with NEW camera forward (dot): ", dot_rot)
		assert(dot_rot > 0.95, "FAIL: W did not follow new camera direction after orbit!")

		# 8. Test Sprint / Run speed (Shift + W)
		print("\n--- Testing Sprint (Shift + W) ---")
		p0 = slime.global_position
		Input.action_press("move_forward")
		Input.action_press("run")
		for i in 60:
			await get_tree().physics_frame
		Input.action_release("run")
		Input.action_release("move_forward")
		for i in 10:
			await get_tree().physics_frame

		var p_sprint := slime.global_position
		var sprint_dist := (Vector3(p_sprint.x, 0, p_sprint.z) - Vector3(p0.x, 0, p0.z)).length()
		print("Sprint 60 ticks distance: ", sprint_dist, " vs Normal walk distance: ", move_rot_horiz.length())
		assert(sprint_dist > move_rot_horiz.length() * 1.25, "FAIL: Sprint was not noticeably faster than walk!")

		print("\nALL WSAD TESTS PASSED SUCCESSFULLY!")
		get_tree().quit(0)
