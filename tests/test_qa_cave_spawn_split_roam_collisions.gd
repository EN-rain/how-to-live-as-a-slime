extends SceneTree

const PropSys = preload("res://scripts/props.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> bool:
	if cond:
		print("PASS: ", msg)
		return true
	_failures += 1
	printerr("FAIL: ", msg)
	return false


func _run() -> void:
	print("=== AUDIT: SUPER-SMALL CAVE SPAWN, SMALL CRYSTAL FRAGMENTS, SPLIT/ROAM & WORLD COLLISIONS ===")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for _i in range(30):
		await physics_frame

	var slime := main.get_node_or_null("Slime") as Slime
	var props := main.get_node_or_null("Ecosystem") as PropSys
	var terrain := main.get_node_or_null("TerrainScene")
	if not _check(slime != null and props != null and terrain != null, "Main scene & core nodes loaded"):
		quit(1)
		return

	# 1. Super-Small Cave Spawn Audit
	var spawn_pos := slime.global_position
	var spawn_scale := slime.slime_scale
	var spawn_vol := slime.get_volume()
	_check(spawn_scale <= 0.40 and is_equal_approx(slime.start_scale, 0.36),
		"Slime spawns super small in Crystal Cave (scale=%.2f, vol=%.2f m³, pos=%s)" % [spawn_scale, spawn_vol, str(spawn_pos)])
	_check(slime.motor.on_ground and slime.motor.core_sphere_clear(slime.motor.core_sweep_origin()),
		"Super-small cave spawn is grounded and clear of obstacle overlap (foot_y=%.2f, support_y=%.2f)" % [slime.model.foot.y, slime.motor.support_y])

	# 2. Small Crystal Fragments in Cave Audit
	var total_cave_crystals := 0
	var small_cave_crystals := 0
	var spawn_edible_crystals: Array = []
	for p in props.props:
		if p.external_group == &"cave_crystals" and p.mesh != null and is_instance_valid(p.mesh):
			total_cave_crystals += 1
			if p.real_volume <= 0.25:
				small_cave_crystals += 1
			if p.mesh.global_position.distance_to(spawn_pos) <= 18.0 and props.is_edible_by_push(slime, p):
				spawn_edible_crystals.append(p)

	_check(total_cave_crystals >= 250 and small_cave_crystals >= 45,
		"Crystal Cave populated with small crystal fragments (total=%d, small_fragments=%d)" % [total_cave_crystals, small_cave_crystals])
	_check(spawn_edible_crystals.size() >= 12,
		"Super-small spawn Slime has >=12 immediately push-edible small crystal fragments near spawn (found=%d)" % spawn_edible_crystals.size())

	# Push-eat 3 small crystal fragments near spawn and verify growth
	var eaten_before := int(props.eaten)
	var vol_before_eat := slime.get_volume()
	for idx in range(mini(3, spawn_edible_crystals.size())):
		var cp = spawn_edible_crystals[idx]
		props.devour(cp, slime)
	for _i in range(45):
		await physics_frame
	_check(int(props.eaten) >= eaten_before + 3 and slime.get_volume() > vol_before_eat,
		"Super-small Slime devoured 3 small cave crystal fragments and grew (vol %.2f -> %.2f m³, scale %.2f -> %.2f)" % [vol_before_eat, slime.get_volume(), spawn_scale, slime.slime_scale])

	# 3. Split (Follower & Roamer) + Roam Foraging + Merge Audit Inside Cave
	var pre_split_total_vol := 0.0
	for s in props.registered_slimes:
		if is_instance_valid(s):
			pre_split_total_vol += s.get_volume()

	# Split #1: Follower (E)
	slime.split_clone(Slime.Role.FOLLOWER)
	for _i in range(42):
		await physics_frame
	_check(props.registered_slimes.size() == 2,
		"First split (Follower) succeeded at super-small scale (active_slimes=%d, player_scale=%.2f)" % [props.registered_slimes.size(), slime.slime_scale])

	# Split #2: Roamer (Q)
	slime.split_clone(Slime.Role.ROAMER)
	for _i in range(42):
		await physics_frame
	_check(props.registered_slimes.size() == 3,
		"Second split (Roamer) succeeded at super-small scale (active_slimes=%d, player_scale=%.2f)" % [props.registered_slimes.size(), slime.slime_scale])

	var follower: Slime = null
	var roamer: Slime = null
	var sum_vol := 0.0
	for s in props.registered_slimes:
		if is_instance_valid(s):
			sum_vol += s.get_volume()
			if s.role == Slime.Role.FOLLOWER:
				follower = s
			elif s.role == Slime.Role.ROAMER:
				roamer = s

	_check(follower != null and roamer != null, "Both Follower and Roamer clones active in cave")
	_check(absf(sum_vol - pre_split_total_vol) <= 0.15,
		"Volume conserved across double split (before=%.3f, sum_after=%.3f)" % [pre_split_total_vol, sum_vol])

	var roamer_start_pos := roamer.global_position if roamer != null else Vector3.ZERO
	var follower_start_pos := follower.global_position if follower != null else Vector3.ZERO

	# Drive player across Collapse Hall while Follower trails and Roamer wanders/forages
	for step_i in range(70):
		slime.motor.move_horizontal(Vector3(0.05, 0.0, -0.06))
		await physics_frame

	var roamer_moved := roamer != null and roamer.global_position.distance_to(roamer_start_pos) > 0.6
	var follower_moved := follower != null and follower.global_position.distance_to(follower_start_pos) > 0.6
	var all_clones_clear := true
	for s in props.registered_slimes:
		if is_instance_valid(s):
			if not s.motor.core_sphere_clear(s.motor.core_sweep_origin()) or s.global_position.y < s.motor.support_y - 0.15:
				all_clones_clear = false
	_check(follower_moved and roamer_moved and all_clones_clear,
		"Follower tracked player and Roamer roamed/foraged cleanly in cave with zero wall clipping or floor fall-through")

	# Merge clones (M)
	slime.merge_nearby_clones()
	for _i in range(45):
		await physics_frame
	_check(props.registered_slimes.size() == 1 and slime.get_volume() >= pre_split_total_vol - 0.08,
		"Merge (M) recalled both Follower and Roamer in cave and restored volume (active=%d, vol=%.2f m³)" % [props.registered_slimes.size(), slime.get_volume()])

	# 4. World Object Collisions Audit (Cave Walls, Overworld Boulders/Trunks, Sandbox Props, Village Walls)
	# 4a. Cave Wall / Boulder collision sweep
	var cave_clear_before := slime.motor.core_sphere_clear(slime.motor.core_sweep_origin())
	for _i in range(35):
		slime.motor.move_horizontal(Vector3(-0.35, 0.0, 0.0))
		slime.motor.recover_overlap()
		await physics_frame
	_check(cave_clear_before and slime.motor.core_sphere_clear(slime.motor.core_sweep_origin()) and slime.global_position.y >= slime.motor.support_y - 0.1,
		"Collision Audit A (Cave Walls/Boulders): Super-small Slime slides/stops cleanly with zero penetration")

	# 4b. Overworld Tree Trunk collision sweep
	var tree_list: Array = terrain.get("_cached_tree_data") as Array
	if not tree_list.is_empty():
		var t0: Dictionary = tree_list[0]
		var tpos: Vector3 = t0["position"]
		slime.teleport_to_world(Vector2(tpos.x - 1.8, tpos.z))
		for _i in range(8):
			await physics_frame
		for _i in range(20):
			slime.motor.move_horizontal(Vector3(0.22, 0.0, 0.0))
			slime.motor.recover_overlap()
			await physics_frame
		var d_trunk := Vector2(slime.global_position.x - tpos.x, slime.global_position.z - tpos.z).length()
		_check(d_trunk >= 0.45 and slime.motor.core_sphere_clear(slime.motor.core_sweep_origin()),
			"Collision Audit B (Tree Trunks): Small Slime blocked solidly by trunk collider (dist=%.2f m)" % d_trunk)

	# 4c. Overworld Rock collision sweep
	var rock_list: Array = terrain.call("build_rock_data") as Array
	if not rock_list.is_empty():
		var r0: Dictionary = rock_list[0]
		var rpos: Vector3 = r0["position"]
		slime.teleport_to_world(Vector2(rpos.x - 2.2, rpos.z))
		for _i in range(8):
			await physics_frame
		for _i in range(20):
			slime.motor.move_horizontal(Vector3(0.24, 0.0, 0.0))
			slime.motor.recover_overlap()
			await physics_frame
		_check(slime.motor.core_sphere_clear(slime.motor.core_sweep_origin()) and slime.global_position.y >= slime.motor.support_y - 0.1,
			"Collision Audit C (Overworld Rocks): Small Slime collides & slides cleanly without penetration")

	# 4d. Large Non-Edible Sandbox Prop collision sweep
	slime.teleport_to_world(Vector2(0.0, -14.0))
	for _i in range(10):
		await physics_frame
	for _i in range(20):
		slime.motor.move_horizontal(Vector3(0.22, 0.0, 0.0))
		slime.motor.recover_overlap()
		await physics_frame
	_check(slime.motor.core_sphere_clear(slime.motor.core_sweep_origin()) and slime.global_position.y >= slime.motor.support_y - 0.1,
		"Collision Audit D (Large Sandbox Props): Small Slime collides cleanly against oversized props")

	print("=== AUDIT & QA COMPLETE (failures=%d) ===" % _failures)
	quit(0 if _failures == 0 else 1)
