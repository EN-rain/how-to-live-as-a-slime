extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("FAIL: could not load main.tscn")
		quit(1)
		return
	var main := packed.instantiate()
	get_root().add_child(main)

	for _i in range(6):
		await process_frame

	var tw := main.get_node_or_null("WorldTimeWeather") as WorldTimeWeather
	var eco: Node = main.get_node_or_null("WorldEcosystem")
	var slime := main.get_node_or_null("Slime") as Slime
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if tw == null or eco == null or slime == null or sun == null:
		printerr("FAIL: missing core nodes tw=%s eco=%s slime=%s sun=%s" % [tw, eco, slime, sun])
		quit(1)
		return

	# Check population counts, materials, equipment, animations
	var n_npc := 0
	var n_animal := 0
	var n_mob := 0
	var n_matte := 0
	var n_armed := 0
	var n_anim_valid := 0
	for a in eco.actors:
		if a == null or not is_instance_valid(a):
			continue
		if a.category == "npc":
			n_npc += 1
		elif a.category == "animal":
			n_animal += 1
		elif a.category == "mob":
			n_mob += 1
		if a._anim != null and a._anim_map.get("idle", "") != "":
			n_anim_valid += 1
		var has_matte := false
		for mi in a._meshes:
			if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var mat: Material = mi.mesh.surface_get_material(0)
				if mat is ShaderMaterial:
					has_matte = true
					break
		if has_matte:
			n_matte += 1
		var skel := _find_skeleton(a)
		if skel != null:
			for ch in skel.get_children():
				if ch is BoneAttachment3D:
					n_armed += 1
					break

	print("VERIFY_POPULATION: total=%d npc=%d animal=%d mob=%d matte=%d armed=%d anim_ok=%d" % [
		eco.actors.size(), n_npc, n_animal, n_mob, n_matte, n_armed, n_anim_valid
	])
	assert(eco.actors.size() >= 38, "Expected ~40 actors")
	assert(n_matte == eco.actors.size(), "All actors must use ShaderMaterial (actor_matte)")
	assert(n_anim_valid == eco.actors.size(), "All actors must have valid anim mapping")

	# Check VillageNavGraph routes from outside wall into plaza through a gatehouse
	var vc_xz := Vector2(VillageBuilder.VILLAGE_CENTER.x, VillageBuilder.VILLAGE_CENTER.z)
	var path: PackedVector2Array = eco.nav_graph.compute_path_2d(vc_xz + Vector2(0.0, 72.0), vc_xz + Vector2(0.0, 8.0))
	print("VERIFY_NAV_PATH_PTS=", path.size())
	assert(path.size() >= 3, "Nav path through gatehouse should produce waypoints")

	# Prepare verification camera & hide HUD cleanly for visual inspection shots
	var hud_layer := main.get_node_or_null("HudLayer")
	if hud_layer != null:
		hud_layer.visible = false
	var cam := Camera3D.new()
	cam.far = 2500.0
	cam.fov = 56.0
	main.add_child(cam)
	cam.make_current()

	var center := VillageBuilder.VILLAGE_CENTER
	# SHOT 1: Noon/Morning Village + New Trees + NPCs + Livestock
	tw.set_time_of_day(0.45)
	tw.set_weather_state(WorldTimeWeather.WeatherState.CLEAR, 120.0)
	for _i in range(4):
		await physics_frame
		await process_frame
	var sun_elev_noon := rad_to_deg(asin(clampf(sun.global_transform.basis.z.y, -1.0, 1.0)))
	print("VERIFY_NOON: time=%s phase=%s sun_energy=%.2f elev=%.1fdeg tod=%.3f" % [
		tw.get_hour_minute_string(), tw.get_phase_label(), sun.light_energy, sun_elev_noon, tw.time_of_day
	])
	cam.global_position = Vector3(center.x - 16.0, center.y + 4.2, center.z + 18.0)
	cam.look_at(Vector3(center.x + 1.5, center.y + 1.6, center.z - 2.0), Vector3.UP)
	await _render_and_save(get_root(), "res://tests/verify_noon_village.png")

	# Measure 10-frame FPS / Render stats looking over active village
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var t0 := Time.get_ticks_usec()
	for _i in range(10):
		await physics_frame
		await process_frame
	var dt_ms := float(Time.get_ticks_usec() - t0) / 10000.0
	print("VERIFY_PERF_VILLAGE: avg_frame_ms=%.2f est_fps=%.1f draw_calls=%d prims=%d" % [
		dt_ms, 1000.0 / maxf(0.01, dt_ms), draw_calls, prims
	])

	# SHOT 2: Cove Rocks, Fisherman Cottage, PierPathway & Dock
	var terrain := main.get_node_or_null("TerrainScene")
	var village := terrain.find_child("Village", true, false) if terrain else null
	var dock := village.get_node_or_null("FishingDock") as Node3D if village else null
	if dock != null:
		var db := Basis(Vector3.UP, dock.rotation.y)
		cam.global_position = dock.global_position + db * Vector3(-26.0, 18.0, -30.0)
		cam.look_at(dock.global_position + db * Vector3(2.0, 1.0, 4.0), Vector3.UP)
		await _render_and_save(get_root(), "res://tests/verify_cove_pier.png")

	# SHOT 3: Storm / Heavy Rain + Sheltering Villagers
	tw.set_time_of_day(0.55)
	tw.set_weather_state(WorldTimeWeather.WeatherState.HEAVY_RAIN, 120.0)
	for _i in range(8):
		tw._process(0.5)
		await physics_frame
		await process_frame
	var sheltering_count := 0
	for a in eco.actors:
		if a != null and a.ai_state == LivingActor.AIState.SHELTER_RAIN:
			sheltering_count += 1
	print("VERIFY_STORM: weather=%s wetness=%.2f rain=%.2f sheltering_villagers=%d" % [
		tw.get_weather_label(), tw.weather_wetness, tw.rain_intensity, sheltering_count
	])
	assert(tw.weather_wetness > 0.65, "Heavy rain should raise wetness")
	assert(sheltering_count >= 1, "Peaceful villagers should shelter during heavy rain")
	cam.global_position = Vector3(center.x + 22.0, center.y + 9.5, center.z + 24.0)
	cam.look_at(Vector3(center.x, center.y + 2.0, center.z), Vector3.UP)
	await _render_and_save(get_root(), "res://tests/verify_storm_rain.png")

	# SHOT 4: Night Raid (01:00 AM, Skeletons vs Guards, Village Lanterns ON)
	tw.set_weather_state(WorldTimeWeather.WeatherState.CLEAR, 120.0)
	tw.weather_wetness = 0.0
	tw.rain_intensity = 0.0
	tw.set_time_of_day(0.04)
	# Bring a raider close to a guard and force awaken completion to verify live combat
	var guard: LivingActor = null
	var raider: LivingActor = null
	for a in eco.actors:
		if a.role == LivingActor.RoleKind.GUARD and guard == null:
			guard = a
		elif a.role == LivingActor.RoleKind.RAIDER and raider == null:
			raider = a
	if guard != null and raider != null:
		raider.respawn(eco)
		raider.ai_state = LivingActor.AIState.CHASE
		raider.global_position = guard.global_position + Vector3(1.8, 0.0, 0.0)
	for _i in range(25):
		await physics_frame
		await process_frame
	print("VERIFY_NIGHT_COMBAT: phase=%s night_lights=%.2f raider_hp=%.1f/%.1f guard_hp=%.1f/%.1f" % [
		tw.get_phase_label(), tw.night_light_strength,
		raider.hp if raider else -1.0, raider.max_hp if raider else -1.0,
		guard.hp if guard else -1.0, guard.max_hp if guard else -1.0
	])
	assert(tw.is_night and tw.night_light_strength > 0.8, "Night lights must illuminate at 01:00")

	# Verify Slime apply_combat_hit reduces volume without touching global_position directly
	var vol_before := slime.get_volume()
	slime.apply_combat_hit(0.18, Vector3(4.0, 2.0, 0.0), "Test Skeleton")
	var vol_after := slime.get_volume()
	print("VERIFY_SLIME_HIT: vol_before=%.3f vol_after=%.3f motor_vx=%.2f" % [
		vol_before, vol_after, slime.motor.velocity.x
	])
	assert(vol_after < vol_before, "Slime combat hit must decrease volume")
	assert(slime.motor.velocity.x > 1.0, "Slime knockback must route through SlimeMotor velocity")

	cam.global_position = Vector3(center.x - 15.0, center.y + 4.5, center.z + 16.0)
	cam.look_at(Vector3(center.x + 1.5, center.y + 1.5, center.z - 2.0), Vector3.UP)
	await _render_and_save(get_root(), "res://tests/verify_night_raid.png")

	print("ALL_LIVING_WORLD_CHECKS_PASSED")
	quit(0)


func _render_and_save(vp: Viewport, res_path: String) -> void:
	for _i in range(4):
		await process_frame
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img != null and not img.is_empty():
		img.save_png(res_path)
		print("SAVED_SHOT: ", res_path, " ", img.get_size())


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for ch in n.get_children():
		var f := _find_skeleton(ch)
		if f != null:
			return f
	return null
