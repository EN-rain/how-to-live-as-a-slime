extends SceneTree

func _initialize() -> void:
	print("--- DIAGNOSING TERRAIN.TSCN PREVIEW LAG ---")
	var terrain_scene := load("res://terrain/terrain.tscn") as PackedScene
	if terrain_scene == null:
		print("FAIL: terrain.tscn not found")
		quit(1)
		return

	var inst := terrain_scene.instantiate() as TerrainScene
	root.add_child(inst)

	# Set up a camera similar to the Godot 3D Editor viewport camera
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 4000.0
	# Add camera to tree first so look_at works
	root.add_child(cam)
	cam.position = Vector3(150.0, 80.0, 150.0)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	# Warmup / shader pipeline compile (first 5 frames)
	print("Warming up shaders...")
	for i in 5:
		await process_frame

	var frame_times := []
	var total_frames := 60

	print("Simulating 60 editor viewport frames with zero-noise fragment shader...")
	for f in total_frames:
		var t0 := Time.get_ticks_usec()
		var angle := float(f) * 0.05
		cam.position = Vector3(cos(angle) * 150.0, 80.0, sin(angle) * 150.0)
		cam.look_at(Vector3.ZERO, Vector3.UP)

		await process_frame
		var t1 := Time.get_ticks_usec()
		frame_times.append((t1 - t0) / 1000.0)

	var avg_ms := 0.0
	var max_ms := 0.0
	for t in frame_times:
		avg_ms += t
		max_ms = maxf(max_ms, t)
	avg_ms /= float(frame_times.size())

	print("Results over 60 frames:")
	print("  Average frame time: ", avg_ms, " ms (", 1000.0 / avg_ms, " FPS)")
	print("  Max frame time (spike): ", max_ms, " ms")

	quit(0)

