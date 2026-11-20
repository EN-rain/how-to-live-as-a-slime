extends SceneTree

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + msg)
	else:
		print("PASS: " + msg)


func _find_nodes_by_pred(node: Node, pred: Callable, out: Array) -> void:
	if pred.call(node):
		out.append(node)
	for ch in node.get_children():
		_find_nodes_by_pred(ch, pred, out)


func _initialize() -> void:
	print("=== VERIFYING WORLD FIXES ===")
	var scn := load("res://scenes/main.tscn") as PackedScene
	if scn == null:
		print("FAIL: Could not load res://scenes/main.tscn")
		quit(1)
		return
	var main := scn.instantiate()
	root.add_child(main)

	for _i in range(8):
		await physics_frame
		await process_frame

	var slime := main.get_node_or_null("Slime") as Slime
	var terrain := main.get_node_or_null("TerrainScene")
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	var eco := main.get_node_or_null("WorldEcosystem")
	var hud := get_first_node_in_group("hud")
	_check(slime != null and terrain != null and sun != null and eco != null and hud != null, "Core scene nodes present")
	if _fails > 0:
		quit(1)
		return

	# 1. Cutout skirt & skylight shadow isolation
	var skirts: Array = []
	_find_nodes_by_pred(terrain, func(n: Node) -> bool: return n.name == "CutoutSkirtCollider", skirts)
	_check(skirts.is_empty(), "Zero CutoutSkirtCollider nodes remain (count=%d)" % skirts.size())
	var shadow_proxies: Array = []
	_find_nodes_by_pred(terrain, func(n: Node) -> bool: return n is MeshInstance3D and n.name.ends_with("_Shadow"), shadow_proxies)
	_check(not shadow_proxies.is_empty(), "Cave shadow proxy exists for skylight beam")
	for sp_raw in shadow_proxies:
		var sp := sp_raw as MeshInstance3D
		_check(sp.layers == 2, "%s isolated to visual layer 2 (got %d)" % [sp.name, sp.layers])
	_check(sun.light_cull_mask == 1, "Sun light_cull_mask is 1 (got %d)" % sun.light_cull_mask)

	# 2. Neutral-unless-provoked group aggro
	eco.call("clear_all_slime_aggro")
	var actors: Array = eco.get("actors")
	var wolf_sample: LivingActor = null
	var wolf_ally: LivingActor = null
	var spider_sample: LivingActor = null
	var skel_sample: LivingActor = null
	var guard_sample: LivingActor = null
	for a in actors:
		if a == null or not is_instance_valid(a) or not a.is_alive():
			continue
		if a.pack_id == &"wolf_pack":
			if wolf_sample == null:
				wolf_sample = a
			elif wolf_ally == null:
				wolf_ally = a
		elif a.pack_id == &"spider_brood" and spider_sample == null:
			spider_sample = a
		elif a.pack_id == &"skel_gate" and skel_sample == null:
			skel_sample = a
		elif a.faction == LivingActor.Faction.VILLAGE and a.role == LivingActor.RoleKind.GUARD and guard_sample == null:
			guard_sample = a

	_check(wolf_sample != null and wolf_ally != null and spider_sample != null and skel_sample != null and guard_sample != null, "Found sample actors from wolf, spider, skeleton, and human groups")

	if wolf_sample != null:
		slime.teleport_to_world(Vector2(wolf_sample.global_position.x + 3.0, wolf_sample.global_position.z), NAN, false)
		for _f in range(18):
			await physics_frame
			await process_frame
		_check(not bool(eco.call("is_group_provoked", &"wolf_pack")) and wolf_sample.target_slime == null and wolf_ally.target_slime == null, "Unprovoked wolves do NOT target Slime at close range")
		# Kill one wolf -> group must become provoked and ally must attack Slime
		wolf_sample.apply_damage(9999.0, Vector2.ZERO, slime, true)
		for _f in range(4):
			await physics_frame
			await process_frame
		_check(bool(eco.call("is_group_provoked", &"wolf_pack")) and wolf_ally.target_slime == slime, "Lethal attack on one wolf provokes wolf pack & rallies surviving allies")
		eco.call("clear_all_slime_aggro")

	if spider_sample != null:
		slime.teleport_to_world(Vector2(spider_sample.global_position.x + 3.0, spider_sample.global_position.z), NAN, false)
		for _f in range(18):
			await physics_frame
			await process_frame
		_check(not bool(eco.call("is_group_provoked", &"spider_brood")) and spider_sample.target_slime == null, "Unprovoked spiders do NOT target Slime")
		spider_sample.apply_damage(10.0, Vector2.ZERO, slime, true)
		_check(bool(eco.call("is_group_provoked", &"spider_brood")) and spider_sample.target_slime == slime, "Attacking spider provokes spider brood")
		eco.call("clear_all_slime_aggro")

	if skel_sample != null:
		slime.teleport_to_world(Vector2(skel_sample.global_position.x + 3.0, skel_sample.global_position.z), NAN, false)
		for _f in range(18):
			await physics_frame
			await process_frame
		_check(not bool(eco.call("is_group_provoked", &"skel_gate")) and skel_sample.target_slime == null, "Unprovoked skeletons do NOT target Slime")
		skel_sample.apply_damage(9999.0, Vector2.ZERO, slime, true)
		_check(bool(eco.call("is_group_provoked", &"skel_gate")), "Killing one skeleton provokes its skeleton group")
		eco.call("clear_all_slime_aggro")

	if guard_sample != null:
		slime.teleport_to_world(Vector2(guard_sample.global_position.x + 3.0, guard_sample.global_position.z), NAN, false)
		for _f in range(18):
			await physics_frame
			await process_frame
		_check(float(eco.get("_village_provoked_timer")) <= 0.0 and guard_sample.target_slime == null, "Unprovoked human guards do NOT target Slime")
		guard_sample.apply_damage(12.0, Vector2.ZERO, slime, true)
		_check(float(eco.get("_village_provoked_timer")) > 0.0 and guard_sample.target_slime == slime, "Attacking human provokes town guard group")
		eco.call("clear_all_slime_aggro")

	# 3. High-altitude hit / scale-shrink anti-fall-through test
	var crag_pos := WorldLandmarks.WOLF_CRAG_CENTER + Vector2(0.0, 10.0)
	var crag_h := float(terrain.call("sample_height", crag_pos.x, crag_pos.y))
	slime.teleport_to_world(crag_pos, crag_h + 1.8, false)
	slime.apply_combat_hit(0.6, Vector3(4.0, 2.5, -3.0), "test hit")
	for _f in range(36):
		await physics_frame
		await process_frame
	var now_h := float(terrain.call("sample_height", slime.global_position.x, slime.global_position.z))
	_check(slime.global_position.is_finite() and slime.global_position.y > now_h - 0.5, "Slime stays on/above highland terrain after airborne shrink combat hit (y=%.2f vs ground=%.2f)" % [slime.global_position.y, now_h])

	# 4. Wolf territory zero-fire & totem removal audit
	var wolf_crag := terrain.get_node_or_null("BeastTerritories/WolfPackCrag")
	_check(wolf_crag != null, "WolfPackCrag territory node exists")
	if wolf_crag != null:
		var fire_nodes: Array = []
		_find_nodes_by_pred(wolf_crag, func(n: Node) -> bool:
			var nm := n.name.to_lower()
			return (n is GPUParticles3D) or nm.contains("torch") or nm.contains("fire") or nm.contains("flame") or nm.contains("pillar_decorated")
		, fire_nodes)
		_check(fire_nodes.is_empty(), "WolfPackCrag has ZERO fire/torch/totem nodes (count=%d)" % fire_nodes.size())
		var warm_lights: Array = []
		_find_nodes_by_pred(wolf_crag, func(n: Node) -> bool:
			return n is OmniLight3D and (n as OmniLight3D).light_color.r > 0.85 and (n as OmniLight3D).light_color.b < 0.55
		, warm_lights)
		_check(warm_lights.is_empty(), "WolfPackCrag has ZERO warm orange fire lights (count=%d)" % warm_lights.size())

	var way_node := terrain.get_node_or_null("WaystonesRegion")
	if way_node != null and way_node.has_method("get_waystone_markers"):
		var min_wolf_ws := INF
		for mk: Dictionary in way_node.call("get_waystone_markers"):
			min_wolf_ws = minf(min_wolf_ws, (mk["xz"] as Vector2).distance_to(WorldLandmarks.WOLF_CRAG_CENTER))
		_check(min_wolf_ws > 100.0, "Nearest waystone torch is safely outside Wolf territory (min=%.1f m)" % min_wolf_ws)

	# 5. Spider web shader double-flip fix check
	var web_src := FileAccess.get_file_as_string("res://shaders/spider_web.gdshader")
	_check(not web_src.contains("if (!FRONT_FACING)"), "spider_web.gdshader removed double normal flip")
	_check(web_src.contains("void light()"), "spider_web.gdshader implements symmetric translucent light()")

	# 6. Rat <-> Spider territory separation & entrance passability
	var rat_spider_dist := WorldLandmarks.RAT_WARREN_MOUTH.distance_to(WorldLandmarks.SPIDER_FOREST_CENTER)
	_check(rat_spider_dist >= 750.0, "Rat Warren relocated far from Spider Webwood (dist=%.1f m)" % rat_spider_dist)
	slime.teleport_to_world(Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 3.0), 22.05, false)
	for _f in range(55):
		slime.motor.move_horizontal(Vector3(0.0, 0.0, -0.22))
		await physics_frame
	_check(slime.global_position.z < WorldLandmarks.RAT_WARREN_MOUTH.y - 4.0, "Rat Warren entrance passable after rebake (z=%.2f vs mouth=%.2f)" % [slime.global_position.z, WorldLandmarks.RAT_WARREN_MOUTH.y])

	# 7. Procedural Skeleton Catacombs layout & unblocked entrance traversal
	var rooms: Array = WorldLandmarks.skel_dungeon_rooms
	var corrs: Array = WorldLandmarks.skel_dungeon_corridors
	var cols: Dictionary = {}
	var rows: Dictionary = {}
	for rm: Dictionary in rooms:
		var g: Vector2i = rm["grid"]
		cols[g.x] = true
		rows[g.y] = true
	_check(rooms.size() >= 9 and corrs.size() >= 8 and cols.size() >= 3 and rows.size() >= 3, "Skeleton Catacombs generated procedural non-cross layout (rooms=%d corrs=%d cols=%d rows=%d seed=%d)" % [rooms.size(), corrs.size(), cols.size(), rows.size(), WorldLandmarks.skel_dungeon_seed])

	slime.teleport_to_world(Vector2(WorldLandmarks.SKEL_CAVE_MOUTH.x, WorldLandmarks.SKEL_CAVE_MOUTH.y + 7.0), WorldLandmarks.SKEL_FORECOURT_Y + 0.05, false)
	for _f in range(210):
		slime.motor.move_horizontal(Vector3(0.0, 0.0, -0.22))
		await physics_frame
	_check(slime.global_position.z < 292.0 and slime.global_position.y < 16.5, "Slime walked unobstructed through Barrow Portal down into Vestibule (pos=%.2f, %.2f, %.2f)" % [slime.global_position.x, slime.global_position.y, slime.global_position.z])

	for _f in range(18):
		await physics_frame
		await process_frame
	_check(sun.light_energy < 0.25, "Underground Skeleton Catacombs attenuates sunlight cleanly (sun=%.3f)" % sun.light_energy)

	# 8. In-game Teleport & Settings HUD Panel
	hud.call("open_menu", "teleport")
	await process_frame
	_check(bool(hud.call("is_menu_open")), "HUD Menu opens cleanly")
	var dests: Array = hud.call("get_teleport_destinations")
	_check(dests.size() >= 10, "Teleport map lists %d destinations" % dests.size())
	var by_name: Dictionary = {}
	for d: Dictionary in dests:
		by_name[String(d["name"])] = d
	for target_nm: String in ["Slimebrook Village Plaza", "Howlcrest Wolf Territory", "Sunken Swamp Ruins · Rat Territory", "Skeleton Catacombs Interior"]:
		_check(by_name.has(target_nm), "Teleport preset exists: %s" % target_nm)
		if by_name.has(target_nm):
			var d_entry: Dictionary = by_name[target_nm]
			hud.call("teleport_to_destination", d_entry)
			await physics_frame
			await process_frame
			var txz: Vector2 = d_entry["xz"]
			var got_xz := Vector2(slime.global_position.x, slime.global_position.z)
			_check(got_xz.distance_to(txz) < 1.5 and not bool(hud.call("is_menu_open")), "Teleported to %s cleanly (dist=%.2f)" % [target_nm, got_xz.distance_to(txz)])

	# 9. World-to-Slime & Creature Scale Consistency Check
	var slime_h := float(slime.model.rest_full_height) if slime.model != null else 2.55
	var max_guard_h := 0.0
	var max_skel_h := 0.0
	var max_overlord_h := 0.0
	var max_rat_h := 0.0
	var max_rat_king_h := 0.0
	var max_wolf_h := 0.0
	var max_brood_h := 0.0
	for a in actors:
		if a == null or not is_instance_valid(a):
			continue
		var ah := _actor_world_height(a)
		if a.faction == LivingActor.Faction.VILLAGE and a.role in [LivingActor.RoleKind.GUARD, LivingActor.RoleKind.MERCHANT, LivingActor.RoleKind.ARTISAN]:
			max_guard_h = maxf(max_guard_h, ah)
		elif a.role == LivingActor.RoleKind.RAIDER:
			max_skel_h = maxf(max_skel_h, ah)
			if a.display_name.contains("Overlord"):
				max_overlord_h = maxf(max_overlord_h, ah)
		elif a.model_path.ends_with("Rat.glb"):
			if a.display_name.contains("King"):
				max_rat_king_h = maxf(max_rat_king_h, ah)
			else:
				max_rat_h = maxf(max_rat_h, ah)
		elif a.pack_id == &"wolf_pack":
			max_wolf_h = maxf(max_wolf_h, ah)
		elif a.display_name.contains("Broodmother"):
			max_brood_h = maxf(max_brood_h, ah)
	_check(max_guard_h > slime_h + 0.30, "Human height exceeds Slime rest height (guard=%.2f m vs slime=%.2f m)" % [max_guard_h, slime_h])
	_check(max_skel_h > slime_h + 0.40 and max_overlord_h >= 3.80, "Skeleton height exceeds Slime & Overlord towers (skel=%.2f m overlord=%.2f m)" % [max_skel_h, max_overlord_h])
	_check(max_rat_h >= 0.80 and max_rat_king_h >= 1.35, "Dire Rats & Rat King match heroic world scale (rat=%.2f m king=%.2f m)" % [max_rat_h, max_rat_king_h])
	_check(max_wolf_h >= 1.85 and max_brood_h >= 2.00, "Wolves & Broodmother Spider match heroic scale (wolf=%.2f m brood=%.2f m)" % [max_wolf_h, max_brood_h])
	_check(VillageBuilder.STORY_H >= 4.0 and VillageBuilder.CELL >= 2.7, "Slimebrook Village modular scale matches humans (story=%.2f m cell=%.2f m)" % [VillageBuilder.STORY_H, VillageBuilder.CELL])
	_check(DungeonCaveBuilder.CORR_HALF_W * 2.0 >= 9.0 and DungeonCaveBuilder.DOOR_H >= 7.5, "Skeleton Catacombs corridors & doors match Crystal Cave scale (w=%.1f m h=%.1f m)" % [DungeonCaveBuilder.CORR_HALF_W * 2.0, DungeonCaveBuilder.DOOR_H])

	# 10. HUD Tips Removed, Dev Mode on Teleport Panel, Forest Animals & Smaller Slime
	var hint_lbl: Label = hud.get("_hint") as Label
	var dev_pill: Control = hud.get("_dev_pill") as Control
	var dev_chk: CheckButton = hud.get("_dev_chk") as CheckButton
	var tp_page: Control = hud.get("_tab_tp_page") as Control
	_check(hint_lbl != null and not (hint_lbl.get_parent() as Control).visible, "HUD tips row is hidden")
	_check(dev_pill != null and not dev_pill.visible, "Dev mode pill is removed from top HUD")
	_check(dev_chk != null and tp_page != null and tp_page.is_ancestor_of(dev_chk), "Dev Mode controls live on the Teleport panel")
	_check(slime.start_scale <= 0.75, "Slime spawn scale is smaller (start_scale=%.2f)" % slime.start_scale)

	var animal_count := 0
	var small_species := {}
	var bad_small_heights: Array[String] = []
	var road_animals := 0
	for a in actors:
		if a != null and is_instance_valid(a) and a.role == LivingActor.RoleKind.ANIMAL:
			animal_count += 1
			var stem: String = String(a.model_path).get_file().get_basename()
			if stem in ["Bunny", "Squirrel", "Birb", "Frog", "Duck", "Turtle", "Chick", "Pigeon"]:
				small_species[stem] = int(small_species.get(stem, 0)) + 1
				var ah := _actor_world_height(a)
				if ah < 0.25 or ah > 0.95:
					bad_small_heights.append("%s=%.2fm" % [stem, ah])
			if WorldLandmarks.min_dist_to_world_road(a.home_xz.x, a.home_xz.y) < 6.0:
				road_animals += 1
	_check(animal_count >= 60, "Weight-painted wildlife population active (animals=%d, small_species=%s)" % [animal_count, str(small_species)])
	_check(small_species.size() >= 7, "Hybrid Quaternius + Poly Pizza small animals spawned across habitats (species=%d %s)" % [small_species.size(), str(small_species.keys())])
	_check(bad_small_heights.is_empty(), "All small animals have normalized world heights 0.25..0.95m (bad=%s)" % str(bad_small_heights))
	_check(road_animals == 0, "Zero weight-painted animals spawn on roads/trails (found=%d)" % road_animals)

	var cave_sh_src := FileAccess.get_file_as_string("res://terrain/cave_rock.gdshader")
	_check(cave_sh_src.contains("eval_ext_daylight") and cave_sh_src.contains("skirt_tuck"), "cave_rock.gdshader has entrance daylight guard and outer skirt tuck against z-fighting")

	# 11. Continent Roads, Trails, Village Avenues & Harbor Pathway — Zero Grass & Zero Blocking Objects
	if way_node != null and way_node.has_method("get_waystone_markers"):
		var min_ws_road_d := INF
		for mk: Dictionary in way_node.call("get_waystone_markers"):
			var wxz: Vector2 = mk["xz"]
			min_ws_road_d = minf(min_ws_road_d, WorldLandmarks.min_dist_to_world_road(wxz.x, wxz.y))
		_check(min_ws_road_d >= 7.0, "All waystone markers sit off road centerlines on roadside shoulders (min_dist=%.2f m)" % min_ws_road_d)

	var grass_xforms: Array = terrain.call("build_grass_transforms")
	var grass_on_roads := 0
	for xf: Transform3D in grass_xforms:
		var gx := xf.origin.x
		var gz := xf.origin.z
		if WorldLandmarks.min_dist_to_world_road(gx, gz) < 5.4:
			grass_on_roads += 1
	_check(grass_on_roads == 0, "Zero 3D grass blades grow inside continent dirt roads & trails (found=%d)" % grass_on_roads)

	var space := (main as Node3D).get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = sphere
	sq.collision_mask = 4 # LAYER_OBSTACLES
	var road_blockers := 0
	var blocker_details: Array[String] = []
	for seg: Array in WorldLandmarks.get_world_road_segments():
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var seg_len := a.distance_to(b)
		var steps := maxi(2, int(ceil(seg_len / 2.5)))
		for si in range(steps + 1):
			var t := float(si) / float(steps)
			var p2 := a.lerp(b, t)
			var py := float(terrain.call("sample_height", p2.x, p2.y))
			sq.transform = Transform3D(Basis.IDENTITY, Vector3(p2.x, py + 1.05, p2.y))
			var hits: Array[Dictionary] = space.intersect_shape(sq, 4)
			if not hits.is_empty():
				road_blockers += 1
				if blocker_details.size() < 5:
					var hit0: Dictionary = hits[0]
					var col_obj: Variant = hit0.get("collider")
					var col_nm: String = (col_obj as Node).name if (col_obj is Node) else str(col_obj)
					blocker_details.append("%s@(%.1f,%.1f)" % [col_nm, p2.x, p2.y])
	_check(road_blockers == 0, "Zero LAYER_OBSTACLES colliders block any continent road or trail centerline (blockers=%d %s)" % [road_blockers, str(blocker_details)])

	# Also verify Harbor PierPathway centerline is 100% clear of blocking LAYER_OBSTACLES
	var pier_blockers := 0
	var b0 := VillageBuilder._cached_gate_xy
	var b1 := VillageBuilder._cached_ctrl_xy
	var b2 := VillageBuilder._cached_entry_xy
	for si in range(1, 24):
		var ta := float(si) / 24.0
		var omta := 1.0 - ta
		var q := omta * omta * b0 + 2.0 * omta * ta * b1 + ta * ta * b2
		var qy := float(terrain.call("sample_height", q.x, q.y))
		sq.transform = Transform3D(Basis.IDENTITY, Vector3(q.x, qy + 1.05, q.y))
		var hits := space.intersect_shape(sq, 4)
		if not hits.is_empty():
			pier_blockers += 1
	_check(pier_blockers == 0, "Zero LAYER_OBSTACLES colliders block Village Harbor PierPathway (blockers=%d)" % pier_blockers)

	print("=== WORLD FIXES VERIFICATION COMPLETE (%d failures) ===" % _fails)
	quit(0 if _fails == 0 else 1)


func _actor_world_height(actor: LivingActor) -> float:
	var min_y := INF
	var max_y := -INF
	var stack: Array[Node] = [actor]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null and mi.is_inside_tree():
				var ab: AABB = mi.mesh.get_aabb()
				var xf: Transform3D = actor.global_transform.affine_inverse() * mi.global_transform
				for i in range(8):
					var p: Vector3 = xf * ab.get_endpoint(i)
					min_y = minf(min_y, p.y)
					max_y = maxf(max_y, p.y)
		for ch in cur.get_children():
			stack.append(ch)
	if min_y == INF:
		return 0.0
	return max_y - min_y
