extends SceneTree

func _initialize() -> void:
	print("--- STARTING QUALITY PRESETS AND STARTUP TESTS ---")
	var settings := SlimeSettings.get_or_create()
	if settings == null:
		print("FAIL: SettingsManager not created")
		quit(1)
		return

	# -------------------------------------------------------------
	# Test 1: Verify 4 Quality Presets Definitions
	# -------------------------------------------------------------
	print("\n[Test 1] Quality Presets Definitions:")
	for i in 4:
		var p := settings.get_quality_preset(i)
		print("Preset %d: %s -> Scale: %.2f, MSAA idx: %d, Shadows: %s (dist: %.0f), Grass: %.2f, DOF: %s" % [
			i, p["name"], p["render_scale"], p["msaa_idx"], p["shadow_enabled"], p["shadow_distance"], p["grass_mult"], p.get("dof_far", false)
		])
	assert(settings.get_quality_preset(0)["name"] == "Low", "Preset 0 must be Low")
	assert(settings.get_quality_preset(1)["name"] == "Medium", "Preset 1 must be Medium")
	assert(settings.get_quality_preset(2)["name"] == "High", "Preset 2 must be High")
	assert(settings.get_quality_preset(3)["name"] == "Ultra", "Preset 3 must be Ultra")

	assert(is_equal_approx(float(settings.get_quality_preset(0)["render_scale"]), 1.00), "Low render scale should be 1.00")
	assert(is_equal_approx(float(settings.get_quality_preset(1)["render_scale"]), 1.00), "Medium render scale should be 1.00")
	assert(is_equal_approx(float(settings.get_quality_preset(2)["render_scale"]), 1.00), "High render scale should be 1.00")
	assert(is_equal_approx(float(settings.get_quality_preset(3)["render_scale"]), 1.00), "Ultra render scale should be 1.00")

	assert(is_equal_approx(float(settings.get_quality_preset(0)["grass_mult"]), 0.4), "Low grass_mult 0.4")
	assert(is_equal_approx(float(settings.get_quality_preset(1)["grass_mult"]), 0.7), "Medium grass_mult 0.7")
	assert(is_equal_approx(float(settings.get_quality_preset(2)["grass_mult"]), 1.0), "High grass_mult 1.0")
	assert(is_equal_approx(float(settings.get_quality_preset(3)["grass_mult"]), 1.3), "Ultra grass_mult 1.3")

	assert(bool(settings.get_quality_preset(3)["dof_far"]) == true, "Ultra dof_far enabled")
	assert(bool(settings.get_quality_preset(2)["dof_far"]) == false, "High dof_far disabled")
	assert(int(settings.get_value("graphics", "quality_preset")) == 0, "Default preset must be Low (0)")
	print("PASS: Quality presets dictionary matches specs and default is Low.")

	# -------------------------------------------------------------
	# Test 2: Instantiate Main Scene & Verify Startup Single Rebuild
	# -------------------------------------------------------------
	print("\n[Test 2] Main Scene Startup & Double-Rebuild Check:")
	var scn := load("res://scenes/main.tscn") as PackedScene
	var main_scene := scn.instantiate()
	root.add_child(main_scene)
	current_scene = main_scene

	var terrain := main_scene.get_node_or_null("TerrainScene")
	assert(terrain != null, "TerrainScene must exist")

	# Wait a couple of frames for deferred calls
	for f in 3:
		await process_frame

	# Check terrain rebuild pending
	assert(bool(terrain.get("_rebuild_pending")) == false, "No rebuild should be pending after startup")
	print("PASS: Main scene initialized without duplicate deferred rebuild.")

	# -------------------------------------------------------------
	# Test 3: HUD Node Path and Hint Visibility
	# -------------------------------------------------------------
	print("\n[Test 3] HUD Node Path:")
	var hud := main_scene.get_node_or_null("HudLayer/Hud") as SlimeHud
	assert(hud != null, "HudLayer/Hud must be resolved correctly")
	assert(hud._hint != null, "Hud _hint must exist")
	print("PASS: HudLayer/Hud successfully found and verified.")

	# -------------------------------------------------------------
	# Test 4: Clean Properties and Baseline Lighting
	# -------------------------------------------------------------
	print("\n[Test 4] Baseline Lighting & Dead Property Cleanup:")
	var sun := main_scene.get_node_or_null("Sun") as DirectionalLight3D
	assert(sun != null, "Sun must exist")
	var world_env := main_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(world_env != null and world_env.environment != null, "WorldEnvironment must exist")

	# Daytime baseline lighting
	settings.set_value("gameplay", "night_mode", false, false)
	settings._apply_to_active_scene()

	print("Sun light_energy: ", sun.light_energy)
	print("Ambient light_energy: ", world_env.environment.ambient_light_energy)
	assert(is_equal_approx(sun.light_energy, 1.35), "Sun light_energy must be 1.35 during day")
	assert(is_equal_approx(world_env.environment.ambient_light_energy, 0.95), "Ambient light energy must be 0.95 during day")
	print("PASS: Baseline lighting preserved (Sun=1.35, Amb=0.95).")

	# -------------------------------------------------------------
	# Test 5: Switching Quality Presets (Low, Medium, High, Ultra)
	# -------------------------------------------------------------
	print("\n[Test 5] Switching Quality Presets:")

	# Switch to Low (0)
	settings.set_quality_preset(0, false)
	await process_frame
	assert(is_equal_approx(root.scaling_3d_scale, 1.00), "Low scaling_3d_scale should be 1.00")
	assert(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "Low screen_space_aa should be FXAA")
	assert(root.msaa_3d == Viewport.MSAA_DISABLED, "Low msaa_3d should be DISABLED")
	assert(sun.shadow_enabled == false, "Low shadows should be false")
	assert(int(terrain.get("grass_count")) == int(roundf(38000.0 * 0.4)), "Low grass count should be 15200")
	if world_env.camera_attributes:
		assert(world_env.camera_attributes.dof_blur_far_enabled == false, "Low DOF should be disabled")
	print("PASS: Preset 0 (Low) applied correctly.")

	# Switch to Medium (1)
	settings.set_quality_preset(1, false)
	await process_frame
	assert(is_equal_approx(root.scaling_3d_scale, 1.00), "Medium scaling_3d_scale should be 1.00")
	assert(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "Medium screen_space_aa should be FXAA")
	assert(sun.shadow_enabled == true, "Medium shadows should be true")
	assert(is_equal_approx(sun.directional_shadow_max_distance, 60.0), "Medium shadow dist should be 60m")
	assert(int(terrain.get("grass_count")) == int(roundf(38000.0 * 0.7)), "Medium grass count should be 26600")
	print("PASS: Preset 1 (Medium) applied correctly.")

	# Switch to High (2)
	settings.set_quality_preset(2, false)
	await process_frame
	assert(is_equal_approx(root.scaling_3d_scale, 1.00), "High scaling_3d_scale should be 1.00")
	assert(root.msaa_3d == Viewport.MSAA_2X, "High msaa_3d should be 2X")
	assert(sun.shadow_enabled == true, "High shadows should be true")
	assert(is_equal_approx(sun.directional_shadow_max_distance, 120.0), "High shadow dist should be 120m")
	assert(int(terrain.get("grass_count")) == 38000, "High grass count should be 38000")
	print("PASS: Preset 2 (High) applied correctly.")

	# Switch to Ultra (3)
	settings.set_quality_preset(3, false)
	await process_frame
	assert(is_equal_approx(root.scaling_3d_scale, 1.00), "Ultra scaling_3d_scale should be 1.00")
	assert(root.msaa_3d == Viewport.MSAA_4X, "Ultra msaa_3d should be 4X")
	assert(sun.shadow_enabled == true, "Ultra shadows should be true")
	assert(is_equal_approx(sun.directional_shadow_max_distance, 200.0), "Ultra shadow dist should be 200m")
	assert(int(terrain.get("grass_count")) == int(roundf(38000.0 * 1.3)), "Ultra grass count should be 49400")
	assert(world_env.camera_attributes != null and world_env.camera_attributes.dof_blur_far_enabled == true, "Ultra DOF far blur should be enabled")
	print("PASS: Preset 3 (Ultra) applied correctly.")

	# -------------------------------------------------------------
	# Test 6: Hotkeys (F5, F6, F7, F8, F10)
	# -------------------------------------------------------------
	print("\n[Test 6] Quality Hotkeys:")
	var ev_f5 := InputEventKey.new()
	ev_f5.keycode = KEY_F5
	ev_f5.pressed = true
	settings._unhandled_key_input(ev_f5)
	assert(int(settings.get_value("graphics", "quality_preset")) == 0, "F5 should switch to Low")

	var ev_f7 := InputEventKey.new()
	ev_f7.keycode = KEY_F7
	ev_f7.pressed = true
	settings._unhandled_key_input(ev_f7)
	assert(int(settings.get_value("graphics", "quality_preset")) == 2, "F7 should switch to High")

	var ev_f8 := InputEventKey.new()
	ev_f8.keycode = KEY_F8
	ev_f8.pressed = true
	settings._unhandled_key_input(ev_f8)
	assert(int(settings.get_value("graphics", "quality_preset")) == 3, "F8 should switch to Ultra")

	var ev_f6 := InputEventKey.new()
	ev_f6.keycode = KEY_F6
	ev_f6.pressed = true
	settings._unhandled_key_input(ev_f6)
	assert(int(settings.get_value("graphics", "quality_preset")) == 1, "F6 should switch to Medium")

	var ev_f10 := InputEventKey.new()
	ev_f10.keycode = KEY_F10
	ev_f10.pressed = true
	settings._unhandled_key_input(ev_f10)
	assert(int(settings.get_value("graphics", "quality_preset")) == 2, "F10 should cycle from Medium (1) to High (2)")
	print("PASS: F5, F6, F7, F8, and F10 hotkeys work.")

	print("\n=== ALL TESTS PASSED SUCCESSFULLY! ===")
	quit(0)
