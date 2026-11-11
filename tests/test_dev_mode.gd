extends SceneTree
## Automated Verification Suite for Developer Mode (Fly, Speed Steps, 3D Noclip, OrbitCamera, HUD pill).

func _init() -> void:
	print("--- Running Developer Mode Verification Suite ---")
	call_deferred("_run")


func _run() -> void:
	var main_sc := load("res://scenes/main.tscn") as PackedScene
	if main_sc == null:
		print("FAIL: Could not load res://scenes/main.tscn")
		quit(1)
		return
	var main := main_sc.instantiate()
	root.add_child(main)

	await process_frame
	await physics_frame
	await physics_frame

	var slime := main.get_node_or_null("Slime") as Slime
	var cam_rig := main.get_node_or_null("CameraRig") as OrbitCamera
	var hud := main.get_node_or_null("HudLayer/Hud") as SlimeHud
	if slime == null or cam_rig == null or hud == null:
		print("FAIL: Missing Slime, CameraRig, or Hud in main.tscn!")
		quit(2)
		return

	if slime.dev_mode:
		print("FAIL: dev_mode should be OFF by default!")
		quit(3)
		return

	# 1. Simulate pressing F4 key to toggle Dev Mode ON
	var ev_f4 := InputEventKey.new()
	ev_f4.keycode = KEY_F4
	ev_f4.pressed = true
	slime._unhandled_input(ev_f4)
	if not slime.dev_mode or not slime.dev_fly or not slime.dev_noclip:
		print("FAIL: F4 did not enable dev_mode + dev_fly + dev_noclip! dev_mode=%s fly=%s noclip=%s" % [
			str(slime.dev_mode), str(slime.dev_fly), str(slime.dev_noclip)
		])
		quit(4)
		return

	# 2. Increase speed with ] and decrease with [
	var speed0 := slime.dev_speed
	var ev_fast := InputEventKey.new()
	ev_fast.keycode = KEY_BRACKETRIGHT
	ev_fast.pressed = true
	slime._unhandled_input(ev_fast)
	slime._unhandled_input(ev_fast)
	var speed_up := slime.dev_speed
	var ev_slow := InputEventKey.new()
	ev_slow.keycode = KEY_BRACKETLEFT
	ev_slow.pressed = true
	slime._unhandled_input(ev_slow)
	var speed_back := slime.dev_speed
	if not (speed_up > speed0 and speed_back < speed_up and speed_back >= speed0):
		print("FAIL: Speed adjustment failed! s0=%.1f s_up=%.1f s_back=%.1f" % [speed0, speed_up, speed_back])
		quit(5)
		return
	print("PASS: Key toggles & speed steps verified (%.0f -> %.0f -> %.0f m/s)" % [speed0, speed_up, speed_back])

	# 3. Verify HUD Dev Pill updates cleanly on process
	hud._process(1.0 / 60.0)
	if not hud._dev_pill.visible or not hud._dev_line.text.contains("DEV") or not hud._dev_line.text.contains("NOCLIP ON"):
		print("FAIL: HUD Dev Pill did not display active status! visible=%s text='%s'" % [
			str(hud._dev_pill.visible), hud._dev_line.text
		])
		quit(6)
		return
	print("PASS: HUD Dev Pill active -> '%s'" % hud._dev_line.text)

	# 4. Verify 3D Noclip Fly punches straight upward from inside the cave through the rock roof & into open sky,
	#    and WASD horizontal flight passes smoothly through solid rock walls at boosted speed.
	var start_pos := slime.global_position
	var ev_space := InputEventKey.new()
	ev_space.keycode = KEY_SPACE
	ev_space.physical_keycode = KEY_SPACE
	ev_space.pressed = true
	Input.parse_input_event(ev_space)
	Input.action_press("move_forward")
	Input.flush_buffered_events()
	slime.adjust_dev_speed(2) # jump up to fast flight
	for _i in 45:
		await physics_frame

	var ev_space_up := InputEventKey.new()
	ev_space_up.keycode = KEY_SPACE
	ev_space_up.physical_keycode = KEY_SPACE
	ev_space_up.pressed = false
	Input.parse_input_event(ev_space_up)
	Input.action_release("move_forward")
	Input.flush_buffered_events()

	var sky_pos := slime.global_position
	var horiz_dist := Vector2(sky_pos.x - start_pos.x, sky_pos.z - start_pos.z).length()
	print("Noclip flight: y %.2f -> %.2f (cave roof ~56 m), horiz=%.2f m" % [start_pos.y, sky_pos.y, horiz_dist])
	if sky_pos.y < 60.0 or horiz_dist < 10.0:
		print("FAIL: Dev Fly + Noclip did not pass freely through the cave roof / rock! y=%.2f horiz=%.2f" % [sky_pos.y, horiz_dist])
		quit(7)
		return

	# 5. Verify OrbitCamera bypasses occlusion raycast while noclip is active (test camera behind solid rock)
	cam_rig.camera.global_position = Vector3.ZERO
	slime.global_position = CaveLayout.to_world(Vector3(-40.0, 26.0, 62.0))
	cam_rig.theta = 0.0
	cam_rig.phi = 1.2
	cam_rig.radius = 12.0
	cam_rig.target = slime.global_position
	cam_rig._update_camera()
	var cam_dist_noclip := cam_rig.camera.global_position.distance_to(cam_rig.target)
	if absf(cam_dist_noclip - 12.0) > 0.25:
		print("FAIL: OrbitCamera clamped radius %.2f despite dev_noclip!" % cam_dist_noclip)
		quit(8)
		return
	print("PASS: OrbitCamera noclip bypass verified (dist=%.2f m == 12.0 m)" % cam_dist_noclip)

	# 6. Verify V toggles dev_fly, N toggles dev_noclip, and F4 restores normal gameplay cleanly
	var ev_n := InputEventKey.new()
	ev_n.keycode = KEY_N
	ev_n.pressed = true
	slime._unhandled_input(ev_n)
	if slime.dev_noclip:
		print("FAIL: N did not toggle dev_noclip OFF!")
		quit(9)
		return

	var ev_v := InputEventKey.new()
	ev_v.keycode = KEY_V
	ev_v.pressed = true
	slime._unhandled_input(ev_v)
	if slime.dev_fly:
		print("FAIL: V did not toggle dev_fly OFF!")
		quit(10)
		return

	slime._unhandled_input(ev_f4)
	if slime.dev_mode:
		print("FAIL: Second F4 did not disable dev_mode!")
		quit(11)
		return
	hud._process(1.0 / 60.0)
	if hud._dev_pill.visible:
		print("FAIL: HUD Dev Pill stayed visible after turning dev_mode OFF!")
		quit(12)
		return

	main.free()
	print("--- ALL DEVELOPER MODE TESTS PASSED! ---")
	quit(0)

