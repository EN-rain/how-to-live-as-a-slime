extends SceneTree

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
var _out_dir := "C:/Users/LENOVO/.gemini/antigravity/brain/07d0fa09-ecf3-44df-97c3-1a96c4ed9f7f/"


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("TEST_FAIL: ", msg)
		quit(1)
		return false
	return true


func _place_slime(slime: Slime, foot_pos: Vector3) -> void:
	var hh := slime.model.rest_half_height * slime.slime_scale + slime.tuning.skin
	slime.global_position = foot_pos + Vector3(0.0, hh, 0.0)
	slime.model.set_foot(foot_pos)
	slime.motor.velocity = Vector3.ZERO
	slime.motor.on_ground = true
	slime.motor._sync_foot()


func _render_and_save(vp: Viewport, rel_name: String) -> void:
	var abs_path := _out_dir + rel_name if not rel_name.is_absolute_path() else rel_name
	for _i in range(4):
		await physics_frame
		await process_frame
	var tex := vp.get_texture()
	if tex == null:
		printerr("RENDER_FAIL: viewport texture missing for ", abs_path)
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		printerr("RENDER_FAIL: viewport image empty for ", abs_path)
		return
	var save_err := img.save_png(abs_path)
	if save_err != OK:
		printerr("RENDER_FAIL: save error ", save_err, " for ", abs_path)
		return
	print("SAVED_SHOT: ", abs_path, " ", img.get_size())


func _run() -> void:
	if DirAccess.dir_exists_absolute("/home/agent/slime"):
		_out_dir = "/home/agent/slime/webwood_previews/"
	var dir_err := DirAccess.make_dir_recursive_absolute(_out_dir)
	if dir_err != OK:
		printerr("Could not create screenshot output directory: ", _out_dir, " error=", dir_err)
		quit(1)
		return
	print("--- VERIFYING SECOND CAVE (SKELETON CRYPT) & BEAST TERRITORIES ---")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if not _check(packed != null, "could not load main.tscn"):
		return
	var main := packed.instantiate()
	get_root().add_child(main)

	for _i in range(6):
		await physics_frame
		await process_frame

	var terrain := main.get_node_or_null("TerrainScene")
	var eco := main.get_node_or_null("WorldEcosystem")
	var slime := main.get_node_or_null("Slime") as Slime
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	var tw := main.get_node_or_null("WorldTimeWeather") as WorldTimeWeather
	var cave_atm := terrain.find_child("CaveAtmosphere", true, false) if terrain else null

	if not _check(terrain != null and eco != null and slime != null and sun != null, "Missing core nodes"):
		return
	var skel_dungeon := terrain.get_node_or_null("SkeletonDungeonCave")
	if skel_dungeon == null:
		skel_dungeon = terrain.get_node_or_null("SkeletonCryptRegion/SkeletonDungeonCave")
	var territories := terrain.get_node_or_null("BeastTerritories")
	if not _check(skel_dungeon != null, "SkeletonDungeonCave node missing"):
		return
	if not _check(territories != null, "BeastTerritories node missing"):
		return

	var spider_trees: Array = terrain.get_spider_forest_trees() if terrain.has_method("get_spider_forest_trees") else []
	print("SPIDER_FOREST_TREES=", spider_trees.size(), " STICKY_WEB_ZONES=", WorldLandmarks.sticky_web_zones.size())
	if not _check(spider_trees.size() >= 60, "Webwood Spider Forest should have >=60 trees"):
		return
	var inner_tree_count := 0
	var fringe_tree_count := 0
	var hollow_tree_count := 0
	var trail_tree_count := 0
	for tree: Dictionary in spider_trees:
		var tree_pos: Vector3 = tree["position"]
		var xz := Vector2(tree_pos.x, tree_pos.z)
		var tree_dist := xz.distance_to(WorldLandmarks.SPIDER_FOREST_CENTER)
		var trail_point := Geometry2D.get_closest_point_to_segment(xz, WorldLandmarks.SPIDER_TRAIL_START, WorldLandmarks.SPIDER_TRAIL_BEND)
		if xz.distance_to(trail_point) < 3.7:
			trail_tree_count += 1
		if tree_dist < 33.0:
			hollow_tree_count += 1
		if tree_dist >= 24.0 and tree_dist < 64.0:
			inner_tree_count += 1
		elif tree_dist >= 116.0 and tree_dist < 148.0:
			fringe_tree_count += 1
	var inner_density := float(inner_tree_count) / (PI * (64.0 * 64.0 - 24.0 * 24.0))
	var fringe_density := float(fringe_tree_count) / (PI * (148.0 * 148.0 - 116.0 * 116.0))
	if not _check(hollow_tree_count >= 8, "The brood hollow should sit inside the woods, not a circular clearing (trees=%d)" % hollow_tree_count):
		return
	if not _check(trail_tree_count == 0, "Webwood trunks must leave the approach trail clear"):
		return
	var grove := territories.get_node_or_null("SpiderWebwood")
	var silk_batches := 0
	var brood_orbs := 0
	if grove != null:
		for child in grove.get_children():
			if String(child.name).begins_with("WebwoodCanopy_"):
				silk_batches += 1
			elif String(child.name).begins_with("WebwoodBroodOrb_"):
				brood_orbs += 1
	if not _check(silk_batches == 4, "Webwood needs an overhead silk layer across all four forest quadrants"):
		return
	if not _check(brood_orbs == 1, "The brood hollow should have one focal orb web, separate from the forest silk"):
		return
	print("WEBWOOD_DENSITY inner=%d (%.5f) fringe=%d (%.5f) ratio=%.3f" % [inner_tree_count, inner_density, fringe_tree_count, fringe_density, inner_density / maxf(fringe_density, 0.00001)])
	if not _check(inner_density > fringe_density * 1.35, "Webwood should progress from a sparse fringe into denser inner woods"):
		return
	if not _check(WorldLandmarks.sticky_web_zones.size() >= 6, "Webwood should have sticky ground web patches"):
		return
	if not _check(WorldLandmarks.sticky_web_zones.size() <= 17, "Webwood ground webs should remain selective hazards, not blanket the forest"):
		return

	var wolves := 0
	var spiders := 0
	var rats := 0
	var crypt_skels := 0
	var overlord_found := false
	var rat_king_found := false
	for a in eco.actors:
		if a == null or not is_instance_valid(a):
			continue
		if a.pack_id == &"wolf_pack":
			wolves += 1
		elif a.pack_id == &"spider_brood":
			spiders += 1
		elif a.pack_id == &"rat_swarm" or "Rat" in a.display_name:
			rats += 1
		elif a.subterranean_kind == 1 or a.pack_id == &"skel_gate":
			crypt_skels += 1
			if "Overlord" in a.display_name:
				overlord_found = true
		if "Rat King" in a.display_name:
			rat_king_found = true

	print("ACTORS: wolves=%d spiders=%d rats=%d crypt_skeletons=%d overlord=%s rat_king=%s total=%d" % [
		wolves, spiders, rats, crypt_skels, str(overlord_found), str(rat_king_found), eco.actors.size()
	])
	if not _check(wolves >= 4 and spiders >= 5 and rats >= 5 and crypt_skels >= 8 and overlord_found and rat_king_found, "Territory/dungeon actors missing"):
		return

	if tw != null:
		tw.set_time_of_day(0.45)
		tw.set_weather_state(WorldTimeWeather.WeatherState.CLEAR, 240.0)
	var hud_layer := main.get_node_or_null("HudLayer")
	if hud_layer != null:
		hud_layer.visible = false
	var cam := Camera3D.new()
	cam.far = 2500.0
	cam.fov = 58.0
	main.add_child(cam)
	cam.make_current()

	# ==========================================================================
	# 1. SKELETON CRYPT EXTERIOR SUNKEN STAIRCASE (-820, 26->8, 326->298) - 2 Angles
	# ==========================================================================
	var ext_h := float(terrain.sample_height(-820.0, 336.0))
	_place_slime(slime, Vector3(-820.0, ext_h + 0.05, 332.0))
	cam.global_position = Vector3(-804.0, ext_h + 11.5, 344.5)
	cam.look_at(Vector3(-820.0, ext_h - 4.0, 313.5), Vector3.UP)
	for _i in range(10):
		await physics_frame
		await process_frame
	print("EXT_MOUTH: slime_y=%.2f expected_h=%.2f" % [slime.global_position.y, ext_h])
	if not _check(slime.global_position.y > ext_h - 1.0, "Slime fell at Skeleton Cave exterior"):
		return
	await _render_and_save(get_root(), _out_dir + "skel_cave_ext_wide.png")

	cam.global_position = Vector3(-820.0, ext_h + 4.8, 329.5)
	cam.look_at(Vector3(-820.0, 14.5, 305.5), Vector3.UP)
	await _render_and_save(get_root(), _out_dir + "skel_cave_ext_front.png")

	# Verify Skeleton Crypt sunken staircase & Gothic portal archway are smoothly passable
	var p_start_y: float = WorldLandmarks.sample_skeleton_cave_floor(-820.0, 307.2).w + 0.06
	_place_slime(slime, Vector3(-820.0, p_start_y, 307.2))
	for _i in range(45):
		slime.motor.move_horizontal(Vector3(0.0, 0.0, -0.20))
		await physics_frame
	print("PORTAL_PASS_SKEL: z=%.2f y=%.2f (must cross z=304.2 -> <302.5)" % [slime.global_position.z, slime.global_position.y])
	if not _check(slime.global_position.z < 302.5, "Skeleton Cave portal doorway is blocked"):
		return

	# ==========================================================================
	# 2. SKELETON CAVE INTERIOR: ATRIUM, CISTERN SQUEEZE GATE, OSSUARY (y=8.0)
	# ==========================================================================
	_place_slime(slime, Vector3(-820.0, 8.05, 282.0))
	cam.global_position = Vector3(-820.0, 12.6, 297.5)
	cam.look_at(Vector3(-820.0, 9.4, 272.0), Vector3.UP)
	for _i in range(18):
		await physics_frame
		await process_frame
	print("ATRIUM: slime_y=%.2f sun=%.3f eco_vis=%s" % [slime.global_position.y, sun.light_energy, str(eco.visible)])
	if not _check(slime.global_position.y > 7.2 and slime.global_position.y < 10.5, "Slime floor support failed in Atrium"):
		return
	if not _check(sun.light_energy < 0.25, "Sun light should attenuate inside Skeleton Cave (got %.3f)" % sun.light_energy):
		return
	if not _check(eco.visible, "WorldEcosystem must stay visible inside Skeleton Cave"):
		return
	await _render_and_save(get_root(), _out_dir + "skel_cave_atrium_wide.png")

	# Squeeze Gate Verification (Full 1.0x blocked vs Split 0.52x passes under 1.55m portcullis gate!)
	slime.target_scale = 1.0
	slime.slime_scale = 1.0
	slime.liquid_amt = 0.0
	slime.height_ratio = 1.0
	slime.model.resolve(1.0, 0.0, 1.0, 1.0, Vector3.UP)
	_place_slime(slime, Vector3(-851.0, 8.05, 263.5))
	for _i in range(25):
		slime.motor.move_horizontal(Vector3(-0.18, 0.0, 0.0))
		await physics_frame
	var blocked_x: float = slime.global_position.x
	print("SQUEEZE_GATE_FULL (1.0x): stopped at x=%.2f (gate x=-854.0)" % blocked_x)
	if not _check(blocked_x > -853.9, "Full 1.0x slime must NOT fit under 1.55m Portcullis Gate"):
		return

	slime.target_scale = 0.52
	slime.slime_scale = 0.52
	slime.liquid_amt = 0.0
	slime.height_ratio = 1.0
	slime.model.resolve(0.52, 0.0, 1.0, 1.0, Vector3.UP)
	_place_slime(slime, Vector3(-851.0, 8.05, 263.5))
	for _i in range(45):
		slime.motor.move_horizontal(Vector3(-0.18, 0.0, 0.0))
		await physics_frame
	var squeezed_x: float = slime.global_position.x
	print("SQUEEZE_GATE_SPLIT (0.52x): squeezed to x=%.2f (vault x<-855)" % squeezed_x)
	if not _check(squeezed_x < -855.0, "Split 0.52x slime must pass under 1.55m West Cistern gate"):
		return
	slime.target_scale = 1.0
	slime.slime_scale = 1.0
	slime.model.resolve(1.0, 0.0, 1.0, 1.0, Vector3.UP)

	# West Cistern & Squeeze Gate Angle (camera overlooking sunken cistern water pool + 1.55m iron portcullis)
	cam.global_position = Vector3(-866.5, 11.4, 279.0)
	cam.look_at(Vector3(-852.0, 8.8, 267.0), Vector3.UP)
	await _render_and_save(get_root(), _out_dir + "skel_cave_cistern_squeeze.png")

	# East Ossuary Crypt & Spike Traps Angle (camera clear of slime overlooking twin spike traps)
	_place_slime(slime, Vector3(-795.5, 8.05, 274.5))
	cam.global_position = Vector3(-799.5, 11.5, 280.5)
	cam.look_at(Vector3(-788.0, 8.8, 270.0), Vector3.UP)
	await _render_and_save(get_root(), _out_dir + "skel_cave_ossuary_traps.png")

	# ==========================================================================
	# 3. SKELETON OVERLORD SANCTUM (-820, 4.0, 238) - 2 Angles
	# ==========================================================================
	_place_slime(slime, Vector3(-820.0, 4.05, 238.0))
	cam.global_position = Vector3(-820.0, 8.2, 246.5)
	cam.look_at(Vector3(-820.0, 6.2, 215.0), Vector3.UP)
	for _i in range(12):
		await physics_frame
		await process_frame
	print("SANCTUM: slime_y=%.2f zone=%s" % [slime.global_position.y, WorldLandmarks.describe_zone(slime.global_position, 45.0)])
	if not _check(slime.global_position.y > 3.2 and slime.global_position.y < 7.0, "Slime floor support failed in Sanctum"):
		return
	await _render_and_save(get_root(), _out_dir + "skel_cave_sanctum_throne.png")

	cam.global_position = Vector3(-813.8, 12.2, 248.5)
	cam.look_at(Vector3(-821.8, 5.2, 224.0), Vector3.UP)
	await _render_and_save(get_root(), _out_dir + "skel_cave_sanctum_overview.png")

	# ==========================================================================
	# 4. SPIDER SILK FOREST (WEBWOOD, -410, y, 480) - 2 Angles
	# ==========================================================================
	var sp_h := float(terrain.sample_height(-410.0, 480.0))
	_place_slime(slime, Vector3(-410.0, sp_h + 0.05, 480.0))
	var sticky_hit := false
	if WorldLandmarks.sticky_web_zones.size() > 0:
		var wz: Vector2 = WorldLandmarks.sticky_web_zones[0]["xz"]
		sticky_hit = WorldLandmarks.is_in_sticky_web(Vector3(wz.x, sp_h, wz.y))
	if not _check(sticky_hit, "Sticky web slow query should return true inside sticky web patch"):
		return

	cam.global_position = Vector3(-388.0, sp_h + 11.5, 498.0)
	cam.look_at(Vector3(-412.0, sp_h + 3.0, 476.0), Vector3.UP)
	for _i in range(18):
		await physics_frame
		await process_frame
	print("SPIDER_FOREST: y=%.2f (sample_h=%.2f) sun=%.3f sticky_hit=%s" % [slime.global_position.y, sp_h, sun.light_energy, str(sticky_hit)])
	if not _check(absf(slime.global_position.y - sp_h) < 1.5, "Slime must stand on solid Spider Forest terrain (got %.2f vs %.2f)" % [slime.global_position.y, sp_h]):
		return
	if not _check(sun.light_energy > 0.6, "Sun energy must recover on surface at Spider Forest (got %.3f)" % sun.light_energy):
		return
	await _render_and_save(get_root(), _out_dir + "spider_forest_canopy.png")

	cam.global_position = Vector3(-403.5, sp_h + 3.0, 489.5)
	cam.look_at(Vector3(-411.5, sp_h + 2.0, 477.5), Vector3.UP)
	await _render_and_save(get_root(), _out_dir + "spider_forest_ground.png")

	# ==========================================================================
	# 5. WOLF PACK CRAG (HOWLCREST, 290, y, -240) - 2 Angles
	# ==========================================================================
	var wf_h := float(terrain.sample_height(290.0, -240.0))
	_place_slime(slime, Vector3(290.0, wf_h + 0.05, -240.0))
	cam.global_position = Vector3(296.5, wf_h + 3.8, -229.0)
	cam.look_at(Vector3(289.5, wf_h + 2.2, -246.0), Vector3.UP)
	for _i in range(10):
		await physics_frame
		await process_frame
	print("WOLF_CRAG: y=%.2f (sample_h=%.2f)" % [slime.global_position.y, wf_h])
	if not _check(absf(slime.global_position.y - wf_h) < 1.5, "Slime must stand on solid Wolf Crag terrain (got %.2f vs %.2f)" % [slime.global_position.y, wf_h]):
		return
	await _render_and_save(get_root(), _out_dir + "wolf_crag_den.png")

	cam.global_position = Vector3(279.0, wf_h + 5.2, -233.0)
	cam.look_at(Vector3(293.0, wf_h + 1.8, -242.5), Vector3.UP)
	await _render_and_save(get_root(), _out_dir + "wolf_crag_overview.png")

	# ==========================================================================
	# 6. UNDERGROUND RAT WARREN (-240, y, 287 -> 244) - 3 Angles + Pass Check
	# ==========================================================================
	# The Warren lives at RAT_WARREN_MOUTH now, while its baked interior coords still
	# use the -240/280 frame, so every probe below is offset into world space.
	var rw_off := WorldLandmarks.RAT_WARREN_OFFSET
	var rw_ext_h := float(terrain.sample_height(WorldLandmarks.RAT_WARREN_MOUTH.x, 422.0))
	_place_slime(slime, Vector3(WorldLandmarks.RAT_WARREN_MOUTH.x, rw_ext_h + 0.05, 422.0))
	cam.global_position = Vector3(WorldLandmarks.RAT_WARREN_MOUTH.x + 6.0, rw_ext_h + 6.8, 434.0)
	cam.look_at(Vector3(WorldLandmarks.RAT_WARREN_MOUTH.x, rw_ext_h + 1.5, 410.0), Vector3.UP)
	for _i in range(10):
		await physics_frame
		await process_frame
	await _render_and_save(get_root(), _out_dir + "rat_warren_ext_mouth.png")

	# Verify Rat Warren mouth doorway is physically passable
	var rw_mouth_world_z := 415.5
	_place_slime(slime, Vector3(WorldLandmarks.RAT_WARREN_MOUTH.x, 22.05, rw_mouth_world_z))
	for _i in range(45):
		slime.motor.move_horizontal(Vector3(0.0, 0.0, -0.20))
		await physics_frame
	print("PORTAL_PASS_RAT: z=%.2f (must cross cutout z=414.0 -> <409)" % slime.global_position.z)
	if not _check(slime.global_position.z < 409.0, "Rat Warren doorway is blocked"):
		return

	_place_slime(slime, Vector3(-240.0 + rw_off.x, 14.55, 244.0 + rw_off.y))
	cam.global_position = Vector3(-233.5 + rw_off.x, 18.0, 255.5 + rw_off.y)
	cam.look_at(Vector3(-240.0 + rw_off.x, 15.6, 235.0 + rw_off.y), Vector3.UP)
	for _i in range(18):
		await physics_frame
		await process_frame
	if cave_atm != null and sun.light_energy >= 0.25:
		print("DIAG_RAT_ATM: cur_cam=", get_root().get_camera_3d().name, " cam_pos=", cam.global_position, " extra_cf=", cave_atm._extra_cave_factor, " cf=", cave_atm._cave_factor, " settled=", cave_atm._settled)
	print("RAT_WARREN_UNDERGROUND: y=%.2f sun=%.3f eco_vis=%s" % [slime.global_position.y, sun.light_energy, str(eco.visible)])
	if not _check(slime.global_position.y > 13.5 and slime.global_position.y < 17.5, "Slime floor support failed inside Rat Warren"):
		return
	if not _check(sun.light_energy < 0.25, "Sun light should attenuate inside Underground Rat Warren (got %.3f)" % sun.light_energy):
		return
	await _render_and_save(get_root(), _out_dir + "rat_warren_vault_front.png")

	cam.global_position = Vector3(-247.5 + rw_off.x, 17.6, 235.0 + rw_off.y)
	cam.look_at(Vector3(-238.0 + rw_off.x, 15.6, 252.0 + rw_off.y), Vector3.UP)
	await _render_and_save(get_root(), _out_dir + "rat_warren_vault_side.png")

	# Expanded North Rat King's Under-Vault Cathedral (y = 10.0)
	_place_slime(slime, Vector3(-240.0 + rw_off.x, 10.05, 196.0 + rw_off.y))
	cam.global_position = Vector3(-232.0 + rw_off.x, 14.2, 211.0 + rw_off.y)
	cam.look_at(Vector3(-240.0 + rw_off.x, 11.4, 184.0 + rw_off.y), Vector3.UP)
	for _i in range(14):
		await physics_frame
		await process_frame
	print("RAT_SANCTUM: y=%.2f zone=%s" % [slime.global_position.y, WorldLandmarks.describe_zone(slime.global_position, 26.0)])
	if not _check(slime.global_position.y > 9.0 and slime.global_position.y < 12.0, "Rat Sanctum Cathedral floor support failed"):
		return
	await _render_and_save(get_root(), _out_dir + "rat_warren_sanctum.png")

	# Expanded West Smuggler Cistern Wing (-276, 14.5, 243) & Squeeze Gate
	_place_slime(slime, Vector3(-272.0 + rw_off.x, 14.55, 243.0 + rw_off.y))
	cam.global_position = Vector3(-262.0 + rw_off.x, 17.6, 248.5 + rw_off.y)
	cam.look_at(Vector3(-277.0 + rw_off.x, 15.2, 241.5 + rw_off.y), Vector3.UP)
	for _i in range(12):
		await physics_frame
		await process_frame
	await _render_and_save(get_root(), _out_dir + "rat_warren_west_cistern.png")

	# Expanded East Root & Fungal Burrow Nest (-203, 14.5, 242)
	_place_slime(slime, Vector3(-206.0 + rw_off.x, 14.55, 242.0 + rw_off.y))
	cam.global_position = Vector3(-216.0 + rw_off.x, 17.5, 248.0 + rw_off.y)
	cam.look_at(Vector3(-200.0 + rw_off.x, 15.6, 240.0 + rw_off.y), Vector3.UP)
	for _i in range(12):
		await physics_frame
		await process_frame
	await _render_and_save(get_root(), _out_dir + "rat_warren_east_burrow.png")

	if cave_atm != null:
		print("CAVE_ATM_OK=", cave_atm.name)
	print("ALL_CAVE_DUNGEON_TERRITORY_CHECKS_PASSED")
	quit(0)
