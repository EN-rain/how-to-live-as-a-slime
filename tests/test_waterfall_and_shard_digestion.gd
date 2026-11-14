extends SceneTree
## Verifies:
## 1) Zero splash domes / particle spray clouds on the cave waterfall.
## 2) Crystal shards (both Geode clusters and Abyssal Pit shards) absorb via
##    SlimeProps (push contact -> inside_props shrink -> uDissolve -> volume gain -> stone stays).

func _init() -> void:
	call_deferred("_run")


func _find_prop_by_prefix(eco: SlimeProps, prefix: String) -> SlimeProps.PropData:
	for p: SlimeProps.PropData in eco.props:
		if p.state == SlimeProps.STATE_IDLE and p.mesh != null and p.mesh.name.begins_with(prefix):
			if eco.is_edible_by_push(eco.player_slime, p):
				return p
	return null


func _test_absorb_prop(slime: Slime, eco: SlimeProps, target_prop: SlimeProps.PropData, label: String, on_water: bool = false) -> bool:
	var shard_pos := target_prop.mesh.global_position
	var orig_mat := target_prop.material
	var orig_scale := target_prop.base_scale
	var vol_before := slime.get_volume()

	# Place slime right beside the shard on its plane
	var start_dir := Vector3(1.0, 0.0, 0.2).normalized()
	slime.global_position = shard_pos + start_dir * 2.2
	if on_water:
		slime.global_position.y = shard_pos.y + 0.35
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.on_ground = not on_water
	slime._sync_proxy()

	var dt := 1.0 / 60.0
	var entered_eating := false
	var saw_inside_belly := false
	var min_shrink_ratio := 1.0
	var max_dissolve := 0.0
	var saw_mat_duplicated := false

	for step in 360:
		if target_prop.state == SlimeProps.STATE_GONE:
			break
		if target_prop.state == SlimeProps.STATE_IDLE and target_prop.mesh != null:
			var to_shard := target_prop.mesh.global_position - slime.global_position
			to_shard.y = 0.0
			if to_shard.length() > 0.05:
				slime.motor.velocity = to_shard.normalized() * 8.5
		else:
			slime.motor.velocity = Vector3.ZERO
		if on_water:
			# Keep underwater slime aligned vertically near shard base so submerged absorption runs cleanly
			slime.global_position.y = lerpf(slime.global_position.y, shard_pos.y, 0.25)
			slime.motor.vertical_vel = 0.0

		slime._physics_process(dt)
		eco.step(dt)

		if target_prop.state == SlimeProps.STATE_EATING:
			entered_eating = true
			if slime.inside_props.has(target_prop):
				saw_inside_belly = true
			if target_prop.material != null and target_prop.material != orig_mat:
				saw_mat_duplicated = true
			if target_prop.mesh != null and is_instance_valid(target_prop.mesh):
				min_shrink_ratio = minf(min_shrink_ratio, target_prop.mesh.scale.x / maxf(orig_scale.x, 1e-4))
			if target_prop.material != null and is_instance_valid(target_prop.material):
				max_dissolve = maxf(max_dissolve, float(target_prop.material.get_shader_parameter("uDissolve")))

	var vol_after := slime.get_volume()
	print("[%s] state=%d eating=%s inside=%s dup_mat=%s min_shrink=%.3f max_dissolve=%.3f vol=%.2f->%.2f" % [
		label, target_prop.state, str(entered_eating), str(saw_inside_belly),
		str(saw_mat_duplicated), min_shrink_ratio, max_dissolve, vol_before, vol_after
	])

	if not entered_eating or not saw_inside_belly or not saw_mat_duplicated:
		print("FAIL [%s]: Did not go through full SlimeProps eating + belly + lazy material duplicate lifecycle!" % label)
		return false
	if min_shrink_ratio < 0.999:
		print("FAIL [%s]: Object scale changed during digestion (min_scale_ratio=%.3f); objects must NOT shrink!" % [label, min_shrink_ratio])
		return false
	if max_dissolve < 0.75:
		print("FAIL [%s]: Shard uDissolve did not animate toward 1.0 (max=%.3f)!" % [label, max_dissolve])
		return false
	if target_prop.state != SlimeProps.STATE_GONE:
		print("FAIL [%s]: Shard did not finish digesting to STATE_GONE!" % label)
		return false
	if vol_after <= vol_before + 0.20:
		print("FAIL [%s]: Slime volume did not increase smoothly!" % label)
		return false
	return true


func _run() -> void:
	print("--- Testing Waterfall Splash Removal & Canonical Crystal Digestion ---")
	var main_sc := load("res://scenes/main.tscn") as PackedScene
	var main := main_sc.instantiate()
	root.add_child(main)

	await process_frame
	await process_frame
	await physics_frame

	var terrain := main.get_node("TerrainScene") as TerrainScene
	var cave := terrain.get_node("Cave") as CaveSystem
	var eco := main.get_node("Ecosystem") as SlimeProps
	var slime := main.get_node("Slime") as Slime

	# 1. Waterfall splash removal check
	var water_holder := cave.get_node_or_null("CaveWater") as Node3D
	if water_holder == null:
		print("FAIL: Missing CaveWater node")
		quit(1)
		return
	if water_holder.get_node_or_null("WaterfallPlungeMist") != null or water_holder.get_node_or_null("WaterfallCrestMist") != null:
		print("FAIL: Waterfall splash GPUParticles3D mist still present!")
		quit(2)
		return
	var wf_mi := water_holder.get_node_or_null("WaterfallRibbon") as MeshInstance3D
	if wf_mi == null or wf_mi.mesh == null:
		print("FAIL: Missing WaterfallRibbon!")
		quit(3)
		return
	var mdt := MeshDataTool.new()
	mdt.create_from_surface(wf_mi.mesh as ArrayMesh, 0)
	for vi in mdt.get_vertex_count():
		if mdt.get_vertex_color(vi).b >= 0.5:
			print("FAIL: WaterfallRibbon still contains plunge splash crown vertices (col.b >= 0.5)!")
			quit(4)
			return
	print("PASS: Waterfall has 0 mist particles and 0 plunge splash crown vertices (%d ribbon verts)." % mdt.get_vertex_count())

	# 2. Check registered crystal shard count & stone count
	var cluster_shards := 0
	var abyss_shards := 0
	for p: SlimeProps.PropData in eco.props:
		if p.external_group == &"cave_crystals":
			if p.mesh.name.begins_with("CaveCrystalShard_"):
				cluster_shards += 1
			elif p.mesh.name.begins_with("CaveAbyssalCrystalShard_"):
				abyss_shards += 1
	var stones_mmi := cave.get_node_or_null("CaveCrystalStones") as MultiMeshInstance3D
	var abyss_stone := cave.get_node_or_null("CaveAbyssalShards") as MeshInstance3D
	print("Registered crystal props: cluster=%d abyss=%d | stone_cradles=%d" % [
		cluster_shards, abyss_shards, stones_mmi.multimesh.instance_count if stones_mmi else -1
	])
	if cluster_shards == 0 or abyss_shards != 20 or stones_mmi == null or abyss_stone == null:
		print("FAIL: Crystal shards or stone bases missing!")
		quit(5)
		return

	# 3. Digest a regular cave crystal cluster and verify its stone cradle remains untouched
	var c_prop := _find_prop_by_prefix(eco, "CaveCrystalShard_")
	if c_prop == null:
		print("FAIL: Could not find any edible CaveCrystalShard_ prop!")
		quit(6)
		return
	var stones_before := stones_mmi.multimesh.instance_count
	if not _test_absorb_prop(slime, eco, c_prop, "CaveClusterShard", false):
		quit(7)
		return
	if not is_instance_valid(stones_mmi) or stones_mmi.multimesh.instance_count != stones_before:
		print("FAIL: CaveCrystalStones changed or removed after shard digestion!")
		quit(8)
		return

	# 4. Digest an underwater Abyssal Crystal Shard and verify CaveAbyssalShards pedestal stays intact
	var a_prop := _find_prop_by_prefix(eco, "CaveAbyssalCrystalShard_")
	if a_prop == null:
		print("FAIL: Could not find any edible CaveAbyssalCrystalShard_ prop!")
		quit(9)
		return
	if not _test_absorb_prop(slime, eco, a_prop, "AbyssalShard", true):
		quit(10)
		return
	if not is_instance_valid(abyss_stone) or not abyss_stone.visible:
		print("FAIL: CaveAbyssalShards basalt pedestal missing/hidden after shard digestion!")
		quit(11)
		return

	main.free()
	print("--- PASS: Waterfall cleanly splash-free & Crystals shrink/dissolve inside slime while stones remain! ---")
	quit(0)

