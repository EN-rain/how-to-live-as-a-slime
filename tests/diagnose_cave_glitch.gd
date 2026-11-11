extends SceneTree

func _init() -> void:
	print("--- Diagnosing Cave Snapping & Floor Queries ---")
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
	var cave := terrain.get_node_or_null("Cave") as CaveSystem

	print("1. Tracing support query along entrance corridor (u=0.0, s=-15.0 -> +15.0):")
	for s_val in range(-15, 16):
		var s := float(s_val)
		var local_pt := Vector3(0.0, 26.0, s)
		var w := CaveLayout.to_world(local_pt)
		var over_surf := terrain.sample_surface_exact(w.x, w.z)
		var is_sub := CaveSystem.is_subterranean_or_cutout(w.x, w.z, 26.0, over_surf.w)
		var sup_floor := terrain.sample_support_floor(w.x, w.z, 26.0)

		# Move slime there and test update_support
		slime.global_position = Vector3(w.x, 26.0 + 1.0, w.z)
		slime.motor.velocity = Vector3.ZERO
		slime.motor.support_y = 26.0
		slime._sync_proxy()
		slime.motor.update_support()

		print("  s=%5.1f | over_y=%5.1f | is_sub=%5s | sup_floor.w=%5.1f | motor.support_y=%5.1f | diff=%5.1f" % [
			s, over_surf.w, str(is_sub), sup_floor.w, slime.motor.support_y, slime.motor.support_y - 26.0
		])

	print("\n2. Tracing support query inside Collapse Hall (u=-60.0, s=72.0) and walls:")
	var test_points := [
		Vector3(-60.0, 18.5, 72.0), # Hall center
		Vector3(-75.0, 18.5, 76.0), # Hall south-west
		Vector3(-85.0, 18.5, 76.0), # Near west wall
		Vector3(-90.0, 18.5, 76.0), # Touching wall
		Vector3(-44.0, 18.5, 88.5), # Grotto entrance
		Vector3(-25.0, 17.5, 96.0), # Inside grotto
		Vector3(-70.0, 18.0, 78.0), # Deep descent mouth
		Vector3(-80.0, 15.0, 88.0), # Deep descent ramp
		Vector3(-94.0, 9.8, 106.0), # Atrium center
		Vector3(-105.0, 9.8, 106.0), # Near atrium wall
		Vector3(-48.0, 8.2, 138.0), # Lake shore
		Vector3(-136.0, 10.4, 82.0), # Vault door approach
	]
	for pt: Vector3 in test_points:
		var w := CaveLayout.to_world(pt)
		var over_surf := terrain.sample_surface_exact(w.x, w.z)
		var is_sub := CaveSystem.is_subterranean_or_cutout(w.x, w.z, pt.y, over_surf.w)
		var sup_floor := terrain.sample_support_floor(w.x, w.z, pt.y)

		slime.global_position = Vector3(w.x, pt.y + 1.0, w.z)
		slime.motor.velocity = Vector3.ZERO
		slime.motor.support_y = pt.y
		slime._sync_proxy()
		slime.motor.update_support()

		print("  local=(%5.1f, %4.1f, %5.1f) | over_y=%5.1f | is_sub=%5s | sup_w=%5.1f | motor.sup_y=%5.1f | diff=%5.1f" % [
			pt.x, pt.y, pt.z, over_surf.w, str(is_sub), sup_floor.w, slime.motor.support_y, slime.motor.support_y - pt.y
		])

	main.free()
	quit(0)

