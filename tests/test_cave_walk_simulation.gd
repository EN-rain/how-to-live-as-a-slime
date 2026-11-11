extends SceneTree

func _init() -> void:
	print("--- Running Cave Entrance Walk Simulation ---")
	call_deferred("_run")

func _run() -> void:
	var main_sc := load("res://scenes/main.tscn") as PackedScene
	var main := main_sc.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	await physics_frame

	var terrain := main.get_node_or_null("TerrainScene") as TerrainScene
	var slime := main.get_node_or_null("Slime") as Slime

	# Start outside the cave entrance at local (u=0.0, s=-18.0)
	var start_local := Vector3(0.0, 26.0, -18.0)
	var start_w := CaveLayout.to_world(start_local)
	var start_floor := terrain.sample_spawn_floor_y(start_w.x, start_w.z, 26.0)
	slime.global_position = Vector3(start_w.x, start_floor + 0.5, start_w.z)
	slime.motor.velocity = Vector3.ZERO
	slime.motor.support_y = start_floor
	slime.motor.on_ground = true
	slime._sync_proxy()

	print("Initial spawn at world: ", slime.global_position, " local: ", CaveLayout.to_local(slime.global_position))

	# Walk forward into the cave towards s = +25.0
	var fwd_3d := Vector3(CaveLayout.FWD_XZ.x, 0.0, CaveLayout.FWD_XZ.y).normalized()
	var prev_y := slime.global_position.y
	var max_y_jump := 0.0
	var snapped_to_roof := false

	for frame in range(400):
		slime.motor.velocity = fwd_3d * 5.0
		slime._physics_process(1.0 / 60.0)
		var cur_pos := slime.global_position
		var cur_local := CaveLayout.to_local(cur_pos)
		var dy := cur_pos.y - prev_y
		if dy > max_y_jump:
			max_y_jump = dy
		if cur_pos.y > 35.0:
			snapped_to_roof = true
			print("GLITCH TRIGGERED at frame %d: local=(%.2f, %.2f, %.2f) dy=%.2f support_y=%.2f" % [
				frame, cur_local.x, cur_pos.y, cur_local.z, dy, slime.motor.support_y
			])
			break
		if frame % 30 == 0:
			print("frame %3d | local=(%5.1f, %4.1f, %5.1f) | sup_y=%4.1f | on_gnd=%5s | dy=%+4.2f" % [
				frame, cur_local.x, cur_pos.y, cur_local.z, slime.motor.support_y, str(slime.motor.on_ground), dy
			])
		prev_y = cur_pos.y

	print("Walk forward result: snapped_to_roof=%s, max_y_jump=%.2f" % [str(snapped_to_roof), max_y_jump])

	# Now test walking in reverse (inside cave s = +25.0 back outside to s = -18.0)
	if not snapped_to_roof:
		print("\nTesting walking backward out of the cave:")
		for frame in range(400):
			slime.motor.velocity = -fwd_3d * 5.0
			slime._physics_process(1.0 / 60.0)
			var cur_pos := slime.global_position
			var cur_local := CaveLayout.to_local(cur_pos)
			var dy := cur_pos.y - prev_y
			if cur_pos.y > 35.0:
				snapped_to_roof = true
				print("GLITCH TRIGGERED WALKING OUT at frame %d: local=(%.2f, %.2f, %.2f) dy=%.2f" % [
					frame, cur_local.x, cur_pos.y, cur_local.z, dy
				])
				break
			if frame % 30 == 0:
				print("out frame %3d | local=(%5.1f, %4.1f, %5.1f) | sup_y=%4.1f | on_gnd=%5s" % [
					frame, cur_local.x, cur_pos.y, cur_local.z, slime.motor.support_y, str(slime.motor.on_ground)
				])
			prev_y = cur_pos.y

	main.free()
	quit(1 if snapped_to_roof else 0)

