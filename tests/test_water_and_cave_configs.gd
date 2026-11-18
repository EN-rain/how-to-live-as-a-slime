extends SceneTree

func _initialize() -> void:
	print("--- VERIFYING SHARED SURFACE WATER LEVEL & CAVE CONFIGS ---")
	var terrain_ps := load("res://terrain/terrain.tscn") as PackedScene
	var ts := terrain_ps.instantiate()
	ts.set("sea_level", 3.5)
	root.add_child(ts)
	call_deferred("_run", ts)

func _run(ts: Node) -> void:
	for _i in range(3):
		await physics_frame
		await process_frame

	var t_mat := (ts.get_node("Terrain") as MeshInstance3D).material_override as ShaderMaterial
	assert(is_equal_approx(float(t_mat.get_shader_parameter("sea_level")), 3.5), "Terrain shader sea_level must match 3.5")
	var cave := ts.get_node("Cave") as CaveSystem
	assert(cave != null, "Cave node missing")
	# Test ocean sample at far coast (x=2800, z=0)
	var ow := cave.sample_world_water_at(Vector3(2800.0, 1.0, 0.0), -10.0, false)
	assert(bool(ow["in_water"]) == true, "Ocean sample must detect water at sea_level=3.5")
	assert(is_equal_approx(float(ow["water_y"]), 3.5), "Ocean water_y must equal 3.5 (got %.2f)" % float(ow["water_y"]))

	# Test CaveWaterConfig stream_flow_speed wiring
	var wc := (cave.water_config as CaveWaterConfig).duplicate(true) as CaveWaterConfig
	wc.stream_flow_speed = 2.25
	cave.water_config = wc
	var w0 := CaveLayout.to_world(CaveLayout.STREAM_CTRL[1])
	var w1 := CaveLayout.to_world(CaveLayout.STREAM_CTRL[2])
	var smid := w0.lerp(w1, 0.5)
	var sw := cave.sample_world_water_at(Vector3(smid.x, smid.y, smid.z), smid.y - 0.5, true)
	assert(bool(sw["in_water"]) == true, "Stream sample must detect water")
	var fspd := Vector2((sw["flow_vel"] as Vector3).x, (sw["flow_vel"] as Vector3).z).length()
	assert(is_equal_approx(fspd, 2.25), "Stream flow speed must match CaveWaterConfig (expected 2.25, got %.2f)" % fspd)

	print("WATER_AND_CAVE_CONFIGS_PASSED")
	quit(0)
