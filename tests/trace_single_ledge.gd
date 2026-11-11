extends SceneTree

func _init() -> void:
	var main_sc := load("res://scenes/main.tscn") as PackedScene
	var main := main_sc.instantiate()
	root.add_child(main)
	for _i in 4:
		await physics_frame

	var terrain := main.get_node("TerrainScene") as TerrainScene
	var slime := main.get_node("Slime") as Slime

	var ledge_pts: Array = [
		Vector3(-56.0, 18.6, 54.0),
		Vector3(-73.0, 24.0, 52.0),
		Vector3(-88.0, 30.2, 61.5),
		Vector3(-88.5, 36.8, 78.5),
		Vector3(-76.5, 41.8, 88.5),
		Vector3(-66.0, 45.0, 80.5),
		Vector3(-58.5, 48.8, 76.5),
		Vector3(-54.0, 52.5, 73.0),
		Vector3(-50.0, 56.0, 68.0),
	]
	var w0 := CaveLayout.to_world(ledge_pts[0] as Vector3)
	var fy := terrain.sample_spawn_floor_y(w0.x, w0.z, (ledge_pts[0] as Vector3).y)
	slime.global_position = Vector3(w0.x, fy + slime.tuning.skin + slime.model.rest_half_height, w0.z)
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	slime.motor.support_y = fy
	slime.motor.on_ground = true
	slime._sync_proxy()

	var idx := 1
	for step in 2400:
		if idx >= ledge_pts.size():
			break
		var target_local: Vector3 = ledge_pts[idx]
		var target_w := CaveLayout.to_world(target_local)
		var dx := target_w.x - slime.global_position.x
		var dz := target_w.z - slime.global_position.z
		var dist_xz := sqrt(dx * dx + dz * dz)
		if dist_xz < 2.0:
			var cur_loc := CaveLayout.to_local(slime.global_position)
			print("REACHED WP %d: target=%s cur=(%.2f, y=%.2f, %.2f)" % [
				idx, str(target_local), cur_loc.x, slime.global_position.y, cur_loc.z
			])
			idx += 1
			continue
		var dir := Vector3(dx / dist_xz, 0.0, dz / dist_xz)
		slime.motor.velocity = dir * 10.0
		slime._physics_process(1.0 / 60.0)

	var top_local := CaveLayout.to_local(slime.global_position)
	print("Final ledge position -> local=(%.2f, y=%.2f, %.2f) on_ground=%s" % [
		top_local.x, slime.global_position.y, top_local.z, str(slime.motor.on_ground)
	])
	quit(0)
