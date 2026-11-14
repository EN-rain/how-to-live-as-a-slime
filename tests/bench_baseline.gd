extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var main_sc := load("res://scenes/main.tscn") as PackedScene
	var t_load := Time.get_ticks_usec()
	var root := main_sc.instantiate()
	var t_inst := Time.get_ticks_usec()
	get_root().add_child(root)
	var t_ready := Time.get_ticks_usec()

	print("STARTUP_MS load=%.1f inst=%.1f ready=%.1f total=%.1f" % [
		(t_load - t0) / 1000.0,
		(t_inst - t_load) / 1000.0,
		(t_ready - t_inst) / 1000.0,
		(t_ready - t0) / 1000.0,
	])

	var terrain := root.get_node_or_null("TerrainScene")
	var cave := root.get_node_or_null("TerrainScene/Cave")
	if cave == null and terrain != null:
		cave = terrain.get_node_or_null("Cave")
	var slime := root.get_node_or_null("Slime") as Slime
	var eco := root.get_node_or_null("Ecosystem") as SlimeProps
	var atmo := root.find_child("CaveAtmosphere", true, false)
	var cam := root.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var cam_rig := root.get_node_or_null("CameraRig")

	if cave != null and slime != null:
		# Probe exact SDF rock geometry around CaveLayout.WATERFALL
		var sdf = cave.get_sdf()
		var wf := CaveLayout.WATERFALL
		print("WATERFALL_LOC=%s cached_ceil_y=%.2f" % [str(wf), float(cave._cached_wf_ceil_y)])
		for ds: float in [-2.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
			var s_probe := wf.z + ds
			var ceil_y: float = cave._sample_ceiling_y(sdf, wf.x, wf.y + 2.0, s_probe, 45.0)
			var floor_y: float = cave._sample_floor_y(sdf, wf.x, wf.y + 2.0, s_probe)
			var f_mid: float = sdf.eval_sdf_full(wf.x, ceil_y - 2.0, s_probe, 56.5)
			var f_wall: float = sdf.eval_sdf_full(wf.x, 26.0, s_probe, 56.5)
			print("  probe s=%.1f (wf+%+.1f): floor=%.2f ceil=%.2f sdf(ceil-2)=%.2f sdf(y=26)=%.2f" % [
				s_probe, ds, floor_y, ceil_y, f_mid, f_wall
			])
		for du: float in [-3.0, -1.5, 0.0, 1.5, 3.0]:
			var u_probe := wf.x + du
			var ceil_y: float = cave._sample_ceiling_y(sdf, u_probe, wf.y + 2.0, wf.z + 1.0, 45.0)
			var f_back: float = sdf.eval_sdf_full(u_probe, 28.0, wf.z + 3.5, 56.5)
			print("  probe u=%.1f (wf+%+.1f) @s+1: ceil=%.2f sdf(y=28,s+3.5)=%.2f" % [u_probe, du, ceil_y, f_back])

		# Count meshes & materials & lights
		var mi_count := 0
		var mmi_count := 0
		var light_count := 0
		var shadow_casters := 0
		var queue: Array[Node] = [root]
		while not queue.is_empty():
			var n: Node = queue.pop_back()
			if n is MeshInstance3D:
				mi_count += 1
				if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shadow_casters += 1
			elif n is MultiMeshInstance3D:
				mmi_count += 1
				if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shadow_casters += 1
			elif n is Light3D:
				light_count += 1
			for ch in n.get_children():
				queue.append(ch)
		print("SCENE_NODES MeshInstance3D=%d MultiMesh=%d Lights=%d ShadowCasters=%d EcoProps=%d" % [
			mi_count, mmi_count, light_count, shadow_casters, eco.props.size() if eco != null else 0
		])

	# Let frames render and benchmark 3 locations
	for _i in 8:
		await process_frame

	var measure_loc := func(label: String, world_pos: Vector3, yaw: float) -> void:
		if slime != null:
			slime.global_position = world_pos
			if slime.motor != null:
				slime.motor.velocity = Vector3.ZERO
				slime.motor.vertical_vel = 0.0
			slime._sync_proxy()
		if cam_rig != null and "theta" in cam_rig:
			cam_rig.theta = yaw
			cam_rig.target = world_pos
		for _w in 6:
			await process_frame
		var frame_us_sum := 0
		var phys_us_sum := 0
		var min_fps := 9999.0
		var max_fps := 0.0
		var n_frames := 20
		for _f in n_frames:
			var ft0 := Time.get_ticks_usec()
			await process_frame
			var dt_us := Time.get_ticks_usec() - ft0
			frame_us_sum += dt_us
			var cur_fps := Performance.get_monitor(Performance.TIME_FPS)
			min_fps = minf(min_fps, cur_fps)
			max_fps = maxf(max_fps, cur_fps)
		var avg_ms := float(frame_us_sum) / float(n_frames) / 1000.0
		var objs := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		print("BENCH [%s] avg_frame=%.2fms proc=%.2fms phys=%.2fms objs=%.0f prims=%.0f draws=%.0f fps_mon=%.1f" % [
			label, avg_ms, proc_ms, phys_ms, objs, prims, draws, Performance.get_monitor(Performance.TIME_FPS)
		])

	await measure_loc.call("CAVE_SPAWN", CaveLayout.to_world(CaveLayout.SPAWN), 0.4)
	await measure_loc.call("CAVE_LAKE", CaveLayout.to_world(Vector3(10.9, 8.8, 141.3)), 2.2)
	await measure_loc.call("OUTDOOR_MEADOW", Vector3(0.0, 29.5, 40.0), 0.0)
	await measure_loc.call("OUTDOOR_BEACH", Vector3(0.0, 3.0, -1550.0), 0.0)

	# Micro-benchmark CPU hot paths directly
	if eco != null and slime != null:
		var t_a := Time.get_ticks_usec()
		for _k in 200:
			eco._update_floor_shadows()
		var t_b := Time.get_ticks_usec()
		for _k in 200:
			eco._update_solid_uniforms(slime)
		var t_c := Time.get_ticks_usec()
		if cave != null:
			for _k in 200:
				cave._process(0.016)
		var t_d := Time.get_ticks_usec()
		if atmo != null:
			for _k in 200:
				atmo._process(0.016)
		var t_e := Time.get_ticks_usec()
		print("CPU_HOTSPOTS (per-call avg us): floor_shadow=%.1fus solid_uniforms=%.1fus cave_proc=%.1fus atmo_proc=%.1fus" % [
			float(t_b - t_a) / 200.0,
			float(t_c - t_b) / 200.0,
			float(t_d - t_c) / 200.0,
			float(t_e - t_d) / 200.0,
		])

	quit(0)

