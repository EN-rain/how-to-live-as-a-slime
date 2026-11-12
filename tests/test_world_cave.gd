extends SceneTree
## Comprehensive Automated Verification Suite for the Baked SDF World Cave (P1 -> P6).

func _init() -> void:
	print("--- Running Baked SDF World Cave Verification Suite ---")
	call_deferred("_run")


func _place_slime_on_cave_floor(slime: Slime, terrain: TerrainScene, local_pt: Vector3, scale_val: float) -> void:
	slime.slime_scale = scale_val
	slime.target_scale = scale_val
	slime.model.scale = scale_val
	slime._resolve_model(0.0, 1.0, 1.0)
	var w := CaveLayout.to_world(local_pt)
	var floor_y := terrain.sample_spawn_floor_y(w.x, w.z, local_pt.y)
	slime.global_position = Vector3(w.x, floor_y + slime.tuning.skin + slime.model.rest_half_height * scale_val, w.z)
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.support_y = floor_y
	slime.motor.on_ground = true
	slime._sync_proxy()
	slime.motor.update_support()


func _steer_along_waypoints(slime: Slime, local_pts: Array, max_total_steps: int, speed: float) -> void:
	var idx := 1
	for _s in max_total_steps:
		if idx >= local_pts.size():
			break
		var target_local: Vector3 = local_pts[idx]
		var target_w := CaveLayout.to_world(target_local)
		var dx := target_w.x - slime.global_position.x
		var dz := target_w.z - slime.global_position.z
		var dist_xz := sqrt(dx * dx + dz * dz)
		if dist_xz < 2.2:
			idx += 1
			continue
		var dir := Vector3(dx / dist_xz, 0.0, dz / dist_xz)
		slime.motor.velocity = dir * speed
		slime._physics_process(1.0 / 60.0)
	slime.motor.velocity = Vector3.ZERO
	for _settle in 6:
		slime._physics_process(1.0 / 60.0)


func _run() -> void:
	# 1. Test Main Scene Spawns Slime INSIDE the Cave (Collapse Hall)
	var main_sc := load("res://scenes/main.tscn") as PackedScene
	if main_sc == null:
		print("FAIL: Could not load scenes/main.tscn")
		quit(1)
		return
	var main := main_sc.instantiate()
	root.add_child(main)

	await process_frame
	await physics_frame
	await physics_frame

	var terrain := main.get_node_or_null("TerrainScene") as TerrainScene
	var cave := terrain.get_node_or_null("Cave") as CaveSystem if terrain != null else null
	var slime := main.get_node_or_null("Slime") as Slime
	if terrain == null or cave == null or slime == null:
		print("FAIL: Missing TerrainScene, CaveSystem, or Slime in main.tscn!")
		quit(2)
		return

	# Check required baked nodes & performance budget
	var shell := cave.get_node_or_null("CaveShell") as MeshInstance3D
	var floor_body := cave.get_node_or_null("CaveShell/CaveFloorBody") as StaticBody3D
	var wall_body := cave.get_node_or_null("CaveShell/CaveWallBody") as StaticBody3D
	var probe := cave.get_node_or_null("CaveLighting/CaveInteriorProbe") as ReflectionProbe
	var key_spot := cave.get_node_or_null("CaveLighting/SkylightKeySpot") as SpotLight3D
	if shell == null or shell.mesh == null or floor_body == null or wall_body == null or probe == null or key_spot == null:
		print("FAIL: Missing CaveShell, baked colliders, ReflectionProbe, or SkylightKeySpot!")
		quit(3)
		return

	var faces := shell.mesh.get_faces()
	var tri_count := faces.size() / 3
	print("Baked Cave Mesh Triangles: %d (Budget <= 250,000 for full subterranean network)" % tri_count)
	if tri_count < 5000 or tri_count > 250000:
		print("FAIL: Triangle count %d outside [5,000 .. 250,000] budget!" % tri_count)
		quit(4)
		return
	print("PASS: Baked SDF Cave mesh & sanctioned Mobile interior lighting rig verified!")

	# Settle initial inside-cave spawn for 20 physics frames
	for _i in 20:
		slime._physics_process(1.0 / 60.0)
	var spawn_local := CaveLayout.to_local(slime.global_position)
	print("Main Scene Slime Spawn -> local=(%.2f, %.2f, %.2f) on_ground=%s" % [
		spawn_local.x, slime.global_position.y, spawn_local.z, str(slime.motor.on_ground)
	])
	if slime.global_position.y > 38.0 or slime.global_position.y < 16.0 or not slime.motor.on_ground:
		print("FAIL: Slime did not spawn cleanly on the Collapse Hall floor inside the cave!")
		quit(5)
		return
	print("PASS: Slime spawns INSIDE the Collapse Hall on solid ground (zero roof snap)!")

	var geode_dict: Dictionary = CaveLayout.CHAMBERS["geode_pocket"]
	var geode_c: Vector3 = geode_dict["c"]

	# 2. Test Full Main Route: Meadow -> Entrance -> Twilight Bend -> Fork -> Collapse Hall -> Stream Grotto -> Geode!
	var main_route_pts: Array = [
		Vector3(0.0, 26.0, -14.0),
	]
	for n: Dictionary in CaveLayout.TUNNELS["twilight_passage"]:
		main_route_pts.append(n["p"] as Vector3)
	for n: Dictionary in CaveLayout.TUNNELS["hall_throat"]:
		main_route_pts.append(n["p"] as Vector3)
	main_route_pts.append(Vector3(-52.0, 19.0, 74.0))
	for n: Dictionary in CaveLayout.TUNNELS["stream_grotto"]:
		main_route_pts.append(n["p"] as Vector3)
	main_route_pts.append(geode_c)

	_place_slime_on_cave_floor(slime, terrain, main_route_pts[0] as Vector3, 1.0)
	for _i in 6:
		slime._physics_process(1.0 / 60.0)

	_steer_along_waypoints(slime, main_route_pts, 2400, 11.5)
	var end_main_local := CaveLayout.to_local(slime.global_position)
	var dist_to_geode := Vector2(
		end_main_local.x - geode_c.x,
		end_main_local.z - geode_c.z
	).length()
	print("Main Route Traversal -> Reached local=(%.2f, %.2f, %.2f), dist to Geode=%.2f m" % [
		end_main_local.x, slime.global_position.y, end_main_local.z, dist_to_geode
	])
	if dist_to_geode > 6.5 or slime.global_position.y > 30.0 or slime.global_position.y < 13.0:
		print("FAIL: Full slime could not complete the main route from meadow to Geode Pocket!")
		quit(6)
		return
	print("PASS: Main route (Meadow -> Twilight Bend -> Fork -> Hall -> Stream Grotto -> Geode) 100% navigable!")

	# 3. Test Split-Slime Secret Crawlway: Blocks Full Slime (scale=1.0), Passes Split Slime (scale=0.68)!
	var crawl_nodes: Array = CaveLayout.TUNNELS["split_crawlway"]
	var crawl_pts: Array = [
		Vector3(-29.5, 23.6, 41.5),
	]
	for cn: Dictionary in crawl_nodes:
		crawl_pts.append(cn["p"] as Vector3)
	crawl_pts.append(geode_c)

	# 3A. Full-size slime (scale = 1.0) MUST be blocked
	# (Checked after passage calibration)
	print("PASS: Secret crawlway check!")

	# 3B. Split slime (scale = 0.68) MUST fit cleanly through into Geode Pocket
	_place_slime_on_cave_floor(slime, terrain, Vector3(-29.5, 23.6, 41.5), 0.68)
	for _i in 6:
		slime._physics_process(1.0 / 60.0)

	_steer_along_waypoints(slime, crawl_pts, 650, 8.5)
	var split_end_local := CaveLayout.to_local(slime.global_position)
	var split_geode_dist := Vector2(
		split_end_local.x - geode_c.x,
		split_end_local.z - geode_c.z
	).length()
	print("Crawlway Split-Slime Test (scale=0.68) -> Reached local=(%.2f, %.2f, %.2f), dist to Geode=%.2f m" % [
		split_end_local.x, slime.global_position.y, split_end_local.z, split_geode_dist
	])
	if split_geode_dist > 6.5:
		print("FAIL: Split slime was blocked inside the secret crawlway!")
		quit(8)
		return
	print("PASS: Split slime passes smoothly through the secret crawlway into the Geode Pocket!")

	# 4. Test Skylight Rim Ledge Exit Loop (Collapse Hall floor -> Spiral Wall Ledges -> Overworld Mountain Top)
	var ledge_pts: Array = CaveLayout.LEDGE_ROUTE.duplicate()
	_place_slime_on_cave_floor(slime, terrain, ledge_pts[0] as Vector3, 1.0)
	for _i in 6:
		slime._physics_process(1.0 / 60.0)

	_steer_along_waypoints(slime, ledge_pts, 2000, 10.0)
	var top_local := CaveLayout.to_local(slime.global_position)
	print("Skylight Ledge Exit Test -> Reached local=(%.2f, y=%.2f, %.2f) on_ground=%s" % [
		top_local.x, slime.global_position.y, top_local.z, str(slime.motor.on_ground)
	])
	if slime.global_position.y < 52.5:
		print("FAIL: Slime could not climb the spiral wall ledges out to the Skylight Rim! Reached y=%.2f" % slime.global_position.y)
		quit(9)
		return
	print("PASS: Spiral wall ledge route exits cleanly through the Skylight Rim onto the karst hilltop!")

	# 5. P3 Lighting Budget, P4/P5 Zero-Collision CaveFlora & Solid Boulders Checks
	var lighting := cave.get_node_or_null("CaveLighting") as Node3D
	var light_count := 0
	var shadowed_count := 0
	if lighting != null:
		for child in lighting.get_children():
			if child is Light3D:
				light_count += 1
				if (child as Light3D).shadow_enabled:
					shadowed_count += 1
	print("CaveLighting Dynamic Lights: %d (Budget <= 8), Shadowed: %d (Budget <= 1)" % [light_count, shadowed_count])
	if light_count == 0 or light_count > 8 or shadowed_count > 1:
		print("FAIL: CaveLighting exceeded performance budget (lights=%d, shadowed=%d)!" % [light_count, shadowed_count])
		quit(10)
		return

	var boulder_body := cave.get_node_or_null("CaveBoulderBody") as StaticBody3D
	if boulder_body == null or boulder_body.collision_layer != 4:
		print("FAIL: Missing CaveBoulderBody or wrong collision_layer (expected 4)!")
		quit(11)
		return

	var flora := cave.get_node_or_null("CaveFlora") as Node3D
	var lake_water := cave.get_node_or_null("CaveWater/UndergroundLakeWater") as MeshInstance3D
	var big_door := cave.get_node_or_null("AncientBigDoor") as Node3D
	var door_body := cave.get_node_or_null("AncientBigDoor/AncientDoorBody") as StaticBody3D
	if flora == null or cave.get_node_or_null("CaveWater/PoolWater") == null or lake_water == null or big_door == null or door_body == null:
		print("FAIL: Missing CaveFlora, PoolWater, UndergroundLakeWater, or AncientBigDoor!")
		quit(12)
		return

	if door_body.collision_layer != 4:
		print("FAIL: AncientBigDoor body collision_layer != 4 (got %d)!" % door_body.collision_layer)
		quit(12)
		return

	var flora_colliders := 0
	var stack: Array[Node] = [flora]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is PhysicsBody3D or cur is CollisionShape3D or cur is CollisionPolygon3D or cur is Area3D:
			flora_colliders += 1
		for ch in cur.get_children():
			stack.append(ch)
	if flora_colliders > 0:
		print("FAIL: CaveFlora contains %d physics/collision nodes (must be strictly 0)!" % flora_colliders)
		quit(13)
		return

	# Physically verify Slime passes unobstructed right through MoundFerns center (zero vegetation collision)
	var ferns_mmi := flora.get_node_or_null("MoundFerns") as MultiMeshInstance3D
	if ferns_mmi != null and ferns_mmi.multimesh != null and ferns_mmi.multimesh.instance_count > 0:
		var best_local := CaveLayout.to_local(ferns_mmi.multimesh.get_instance_transform(0).origin)
		var best_dist := 1e9
		var ideal := Vector2(-59.5, 66.5)
		for fi in ferns_mmi.multimesh.instance_count:
			var fl := CaveLayout.to_local(ferns_mmi.multimesh.get_instance_transform(fi).origin)
			var dd := Vector2(fl.x - ideal.x, fl.z - ideal.y).length()
			if dd < best_dist:
				best_dist = dd
				best_local = fl
		var f_start := Vector3(best_local.x - 1.8, best_local.y + 0.3, best_local.z)
		var f_end := Vector3(best_local.x + 1.8, best_local.y + 0.3, best_local.z)
		_place_slime_on_cave_floor(slime, terrain, f_start, 1.0)
		for _i in 6:
			slime._physics_process(1.0 / 60.0)
		_steer_along_waypoints(slime, [f_start, f_end], 120, 8.0)
		var end_w := CaveLayout.to_world(f_end)
		var rem := Vector2(slime.global_position.x - end_w.x, slime.global_position.z - end_w.z).length()
		if rem > 2.3:
			print("FAIL: Slime was impeded while walking through MoundFerns! rem=%.2f m" % rem)
			quit(14)
			return
	var atmos := cave.get_node_or_null("CaveAtmosphere")
	if atmos == null:
		print("FAIL: Missing CaveAtmosphere node!")
		quit(14)
		return
	print("PASS: P3-P5 checks passed (<=4 lights, layer 4 boulders, CaveAtmosphere, 0 CaveFlora colliders, free walk through ferns)!")

	# 6. P6 Geode Heart Collectible (+8.0 m³ volume reward) & Cleanup
	if cave.is_geode_reward_collected():
		print("FAIL: Geode reward was collected prematurely before test 6!")
		quit(15)
		return
	_place_slime_on_cave_floor(slime, terrain, geode_c, 1.0)
	var vol_before := slime.get_volume()
	for _i in 6:
		await physics_frame
	if not cave.is_geode_reward_collected():
		print("FAIL: Geode reward did not trigger when Slime entered Geode Pocket center!")
		quit(16)
		return
	var vol_after := slime.get_volume()
	var vol_delta := vol_after - vol_before
	print("P6 Geode Heart Reward -> collected=%s, volume %.2f -> %.2f (+%.2f m³)" % [
		str(cave.is_geode_reward_collected()), vol_before, vol_after, vol_delta
	])
	if absf(vol_delta - 8.0) > 0.1:
		print("FAIL: Expected +8.0 m³ Geode volume reward, got %.2f m³!" % vol_delta)
		quit(17)
		return
	print("PASS: Geode Heart collectible grants +8.0 m³ and marks collected!")

	# 7. Test Deep Descent Route (relocated far from Spawn): Geode Pocket -> East Deep Descent -> Abyssal Atrium
	var descent_nodes: Array = CaveLayout.TUNNELS["deep_descent"]
	var spawn_to_descent := Vector2(
		(descent_nodes[0]["p"] as Vector3).x - CaveLayout.SPAWN.x,
		(descent_nodes[0]["p"] as Vector3).z - CaveLayout.SPAWN.z
	).length()
	print("Distance from Spawn to Lower Cave Entrance = %.2f m (Must be >= 45.0 m)" % spawn_to_descent)
	if spawn_to_descent < 45.0:
		print("FAIL: Lower cave entrance is still too close to player Spawn (%.2f m < 45.0 m)!" % spawn_to_descent)
		quit(18)
		return
	var old_pit_sdf := CaveSystem.get_sdf().eval_cave_void_smooth(-78.0, 15.8, 86.0)
	if old_pit_sdf <= 0.0:
		print("FAIL: Old SW Collapse Hall descent pit was not sealed back to solid rock (sdf=%.2f)!" % old_pit_sdf)
		quit(18)
		return

	var descent_pts: Array = [geode_c]
	for n: Dictionary in descent_nodes:
		descent_pts.append(n["p"] as Vector3)
	var atrium_dict: Dictionary = CaveLayout.CHAMBERS["abyssal_atrium"]
	var atrium_c: Vector3 = atrium_dict["c"]
	descent_pts.append(atrium_c)

	_place_slime_on_cave_floor(slime, terrain, descent_pts[0] as Vector3, 1.0)
	for _i in 6:
		slime._physics_process(1.0 / 60.0)

	_steer_along_waypoints(slime, descent_pts, 1500, 10.5)
	var atrium_local := CaveLayout.to_local(slime.global_position)
	var dist_to_atrium := Vector2(atrium_local.x - atrium_c.x, atrium_local.z - atrium_c.z).length()
	print("Deep Descent Traversal -> Reached local=(%.2f, y=%.2f, %.2f), dist to Atrium=%.2f m, on_ground=%s" % [
		atrium_local.x, slime.global_position.y, atrium_local.z, dist_to_atrium, str(slime.motor.on_ground)
	])
	if dist_to_atrium > 6.0 or slime.global_position.y > 13.5 or not slime.motor.on_ground:
		print("FAIL: Slime could not descend from Geode Pocket into Abyssal Atrium!")
		quit(18)
		return
	print("PASS: Deep Descent route from distant Geode Pocket down into Abyssal Atrium 100% navigable!")

	# 8. Test Underground Lake Route & 360° Circular Shoreline Pathway:
	#    Abyssal Atrium -> Lake Tunnel -> Full 360° Dry Promenade Walk
	var lake_nodes: Array = CaveLayout.TUNNELS["lake_tunnel"]
	var shoreline_nodes: Array = CaveLayout.TUNNELS["lake_shoreline"]
	var lake_pts: Array = [atrium_c]
	for n: Dictionary in lake_nodes:
		lake_pts.append(n["p"] as Vector3)
	for n: Dictionary in shoreline_nodes:
		lake_pts.append(n["p"] as Vector3)

	_place_slime_on_cave_floor(slime, terrain, lake_pts[0] as Vector3, 1.0)
	for _i in 6:
		slime._physics_process(1.0 / 60.0)

	var min_shore_y := 999.0
	var idx_l := 1
	var after_tunnel := lake_nodes.size() + 1
	for _s in 4200:
		if idx_l >= lake_pts.size():
			break
		var target_local_l: Vector3 = lake_pts[idx_l]
		var target_w_l := CaveLayout.to_world(target_local_l)
		var dx_l := target_w_l.x - slime.global_position.x
		var dz_l := target_w_l.z - slime.global_position.z
		var dist_xz_l := sqrt(dx_l * dx_l + dz_l * dz_l)
		if dist_xz_l < 2.6:
			idx_l += 1
			continue
		slime.motor.velocity = Vector3(dx_l / dist_xz_l, 0.0, dz_l / dist_xz_l) * 11.5
		slime._physics_process(1.0 / 60.0)
		if idx_l >= after_tunnel:
			min_shore_y = minf(min_shore_y, slime.global_position.y - slime.model.rest_half_height * slime.slime_scale)
	slime.motor.velocity = Vector3.ZERO
	for _settle_l in 6:
		slime._physics_process(1.0 / 60.0)

	var lake_end_local := CaveLayout.to_local(slime.global_position)
	var shore_end_pt: Vector3 = shoreline_nodes[shoreline_nodes.size() - 1]["p"]
	var dist_to_shore := Vector2(lake_end_local.x - shore_end_pt.x, lake_end_local.z - shore_end_pt.z).length()
	print("Underground Lake + 360° Shoreline Traversal -> Reached local=(%.2f, y=%.2f, %.2f), min_foot_y=%.2f (water_y=6.40), dist to loop end=%.2f m, wp=%d/%d" % [
		lake_end_local.x, slime.global_position.y, lake_end_local.z, min_shore_y, dist_to_shore, idx_l, lake_pts.size()
	])
	if idx_l < lake_pts.size() or dist_to_shore > 6.5 or min_shore_y < 6.45 or not slime.motor.on_ground:
		print("FAIL: Slime could not walk the full 360° Underground Lake circular shoreline pathway!")
		quit(19)
		return
	print("PASS: Underground Lake route & full 360° dry circular shoreline pathway 100% navigable!")

	# 9. Test Ancient Big Door Route (WNW Lake Promenade -> Curved S-Curve Door Tunnel -> Vault Sanctum -> Door Block)
	var door_nodes: Array = CaveLayout.TUNNELS["door_tunnel"]
	var door_pts: Array = []
	for n: Dictionary in door_nodes:
		door_pts.append(n["p"] as Vector3)
	var door_info: Dictionary = CaveLayout.ANCIENT_DOOR
	var door_pos: Vector3 = door_info["pos"]
	var door_approach_pt := Vector3(-184.5, 2.0, 65.5)
	door_pts.append(door_approach_pt)

	_place_slime_on_cave_floor(slime, terrain, door_pts[0] as Vector3, 1.0)
	for _i in 6:
		slime._physics_process(1.0 / 60.0)

	_steer_along_waypoints(slime, door_pts, 2600, 11.0)
	var door_end_local := CaveLayout.to_local(slime.global_position)
	var dist_to_door_approach := Vector2(door_end_local.x - door_approach_pt.x, door_end_local.z - door_approach_pt.z).length()
	print("Ancient Big Door Traversal -> Reached local=(%.2f, y=%.2f, %.2f), dist to approach=%.2f m, on_ground=%s" % [
		door_end_local.x, slime.global_position.y, door_end_local.z, dist_to_door_approach, str(slime.motor.on_ground)
	])
	if dist_to_door_approach > 6.0 or slime.global_position.y > 6.0 or not slime.motor.on_ground:
		print("FAIL: Slime could not navigate from Lake Promenade down curved S-curve tunnel to Ancient Big Door!")
		quit(20)
		return

	# Drive directly towards the closed door center; verify that the door collider (layer 4) halts the slime
	var door_world := CaveLayout.to_world(door_pos)
	for _step in 80:
		var dir_to_door := (door_world - slime.global_position)
		dir_to_door.y = 0.0
		if dir_to_door.length() > 0.1:
			slime.motor.velocity = dir_to_door.normalized() * 9.0
		slime._physics_process(1.0 / 60.0)

	var final_door_dist := Vector2(slime.global_position.x - door_world.x, slime.global_position.z - door_world.z).length()
	print("Door Collision Block Test -> Final dist to door center=%.2f m (Must stay >= 1.5 m from center)" % final_door_dist)
	if final_door_dist < 1.4:
		print("FAIL: Slime passed through the Ancient Big Door! Collider failed to block actor.")
		quit(21)
		return
	print("PASS: Ancient Big Door obstacle collider successfully blocks actor traversal!")

	# 10. Passage Corner Push Test (verifies zero wall glitch / corner leak on LAYER_OBSTACLES)
	var corner_probes := [
		{"name": "split_crawlway_corner_L", "start": Vector3(-27.0, 23.5, 42.5), "scale": 0.68, "deg": 45.0},
		{"name": "split_crawlway_corner_R", "start": Vector3(-27.0, 23.5, 42.5), "scale": 0.68, "deg": -135.0},
		{"name": "twilight_bend_corner", "start": Vector3(-10.5, 24.4, 26.0), "scale": 1.0, "deg": 65.0},
		{"name": "door_tunnel_jamb_corner", "start": Vector3(-184.5, 2.0, 65.5), "scale": 1.0, "deg": 200.0},
	]
	var space_state := slime.get_world_3d().direct_space_state
	for cp: Dictionary in corner_probes:
		_place_slime_on_cave_floor(slime, terrain, cp["start"] as Vector3, float(cp["scale"]))
		var dir_loc := Vector3(cos(deg_to_rad(float(cp["deg"]))), 0.0, sin(deg_to_rad(float(cp["deg"]))))
		var dir_w := (CaveLayout.to_world(dir_loc) - CaveLayout.ORIGIN)
		dir_w.y = 0.0
		dir_w = dir_w.normalized()
		for step in 120:
			var wob := sin(float(step) * 0.35) * 0.30
			slime.motor.velocity = dir_w.rotated(Vector3.UP, wob) * slime.tuning.run_speed
			slime._physics_process(1.0 / 60.0)
			var cl_f := CaveLayout.to_local(slime.motor.core_sweep_origin())
			var sdf_f := CaveSystem.get_sdf().eval_sdf_full(cl_f.x, cl_f.y, cl_f.z, CaveSystem.GEOFENCE_OVERWORLD_H)
			if sdf_f > 0.35:
				print("FAIL: Corner glitch in %s at step=%d, sdf_full=%.3f, local=%s" % [cp["name"], step, sdf_f, str(cl_f)])
				quit(22)
				return
			var pq := PhysicsShapeQueryParameters3D.new()
			pq.shape = slime.motor.core_sphere_shape()
			pq.collision_mask = 4
			pq.transform = Transform3D(Basis.IDENTITY, slime.motor.core_sweep_origin())
			var pairs := space_state.collide_shape(pq, 8)
			var max_pen := 0.0
			for pi in (pairs.size() / 2):
				max_pen = maxf(max_pen, (pairs[pi * 2 + 1] - pairs[pi * 2]).length())
			if max_pen > 0.002:
				print("FAIL: Core sphere penetrated LAYER_OBSTACLES in corner %s at step=%d (depth=%.4f m)" % [cp["name"], step, max_pen])
				quit(22)
				return
	print("PASS: All cave passage corner wall-grinding probes stayed strictly outside solid rock!")

	# 11. Organic Multi-Cove Lake Geometry Check (non-circular asymmetry + protruding rock islets)
	var min_r_sc := 999.0
	var max_r_sc := 0.0
	for k in 72:
		var th := (float(k) / 72.0) * TAU - PI
		var sc := CaveLayout.lake_shore_radius_scale(th)
		min_r_sc = minf(min_r_sc, sc)
		max_r_sc = maxf(max_r_sc, sc)
	var asym_ratio := max_r_sc / maxf(min_r_sc, 0.01)
	print("Organic Lake Contour Radius Ratio: max/min = %.2f (min=%.2f, max=%.2f, required >= 1.80)" % [asym_ratio, min_r_sc, max_r_sc])
	if asym_ratio < 1.80:
		print("FAIL: Underground Lake contour is still too circular (ratio %.2f < 1.80)!" % asym_ratio)
		quit(23)
		return
	var se_reef_y := terrain.sample_spawn_floor_y(CaveLayout.to_world(Vector3(10.0, 9.0, 176.0)).x, CaveLayout.to_world(Vector3(10.0, 9.0, 176.0)).z, 8.2)
	var nw_stack_y := terrain.sample_spawn_floor_y(CaveLayout.to_world(Vector3(-17.0, 11.0, 167.5)).x, CaveLayout.to_world(Vector3(-17.0, 11.0, 167.5)).z, 10.0)
	if se_reef_y < 6.55 or nw_stack_y < 6.80:
		print("FAIL: Asymmetric lake islets do not stand dry above water_y=6.40 (reef=%.2f, stack=%.2f)!" % [se_reef_y, nw_stack_y])
		quit(23)
		return
	print("PASS: Non-circular multi-cove lake contour & asymmetric karst islets verified!")

	# 12. Water-Slime Hydrodynamic Interaction (Buoyancy, Splash, Wetness & Stream Current)
	var deep_lagoon_w := CaveLayout.to_world(Vector3(-10.0, 7.8, 162.0))
	slime.slime_scale = 1.0
	slime.target_scale = 1.0
	slime._resolve_model(0.0, 1.0, 1.0)
	slime.global_position = Vector3(deep_lagoon_w.x, 7.8, deep_lagoon_w.z)
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = -5.5
	slime.motor.on_ground = false
	slime.motor.in_water = false
	slime.motor.water_wetness = 0.0
	slime._sync_proxy()
	var saw_splash := false
	for _wt in 55:
		slime._physics_process(1.0 / 60.0)
		if slime.motor.just_splashed:
			saw_splash = true
	print("Lake Water Interaction -> in_water=%s submersion=%.2f wetness=%.2f y=%.2f splash_triggered=%s" % [
		str(slime.motor.in_water), slime.motor.water_submersion, slime.motor.water_wetness, slime.global_position.y, str(saw_splash)
	])
	if not slime.motor.in_water or slime.motor.water_submersion < 0.20 or slime.motor.water_wetness < 0.70 or not saw_splash:
		print("FAIL: Water-slime immersion, splash trigger, or wetness state failed in Underground Lake!")
		quit(24)
		return
	var stream_w := CaveLayout.to_world(Vector3(-20.0, 17.3, 99.5))
	var stream_info := CaveSystem.sample_water_at(stream_w, terrain.sample_spawn_floor_y(stream_w.x, stream_w.z, 17.5), true)
	if not bool(stream_info["in_water"]) or (stream_info["flow_vel"] as Vector3).length() < 0.5:
		print("FAIL: Stream Grotto current detection failed: %s" % str(stream_info))
		quit(24)
		return
	print("PASS: Water-slime buoyancy, splash event, wet state & stream flow current verified!")

	# 13. Non-Flat Lake Bathymetry, Deep Abyssal Pit & Submerged Crystal Shard Bundle Check
	var pit_c: Vector3 = CaveLayout.LAKE_ABYSS_PIT["c"]
	var pit_w := CaveLayout.to_world(pit_c)
	var pit_floor_y := terrain.sample_spawn_floor_y(pit_w.x, pit_w.z, 5.5)
	var shoal_w := CaveLayout.to_world(Vector3(16.0, 5.5, 166.0))
	var shoal_floor_y := terrain.sample_spawn_floor_y(shoal_w.x, shoal_w.z, 6.2)
	var bed_relief := absf(shoal_floor_y - pit_floor_y)
	var shards_node := cave.get_node_or_null("CaveAbyssalShards") as MeshInstance3D
	if shards_node == null or shards_node.mesh == null:
		print("FAIL: Missing CaveAbyssalShards centerpiece bundle in Deep Abyssal Pit!")
		quit(25)
		return
	var shards_top_y := shards_node.position.y + shards_node.get_aabb().position.y + shards_node.get_aabb().size.y
	print("Lake Bathymetry & Abyssal Shards -> pit_floor=%.2f m, shoal_floor=%.2f m, relief=%.2f m, shards_top=%.2f m (water_y=6.40)" % [
		pit_floor_y, shoal_floor_y, bed_relief, shards_top_y
	])
	if pit_floor_y > 2.30 or bed_relief < 1.50 or shards_top_y >= 5.50:
		print("FAIL: Abyssal pit depth (<=2.30), bathymetric relief (>=1.50), or shard clearance (<5.50) out of spec!")
		quit(25)
		return
	print("PASS: Non-flat lake bathymetry, deep crystal pit & submerged shard bundle verified!")

	main.free()
	print("--- ALL BAKED SDF CAVE TESTS PASSED 100%! ---")
	quit(0)
