extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sc := load("res://scenes/main.tscn") as PackedScene
	var main := sc.instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame

	var terrain := main.get_node("TerrainScene") as TerrainScene
	var sdf := CaveSDF.new()
	var space := main.get_viewport().world_3d.direct_space_state

	print("=== Skylight Rim Diagnostic around (-51.77, 71.38) ===")
	var pts := [
		Vector2(-51.8, 71.4),
		Vector2(-53.5, 70.8),
		Vector2(-55.0, 70.0),
		Vector2(-58.0, 68.0),
		Vector2(-62.8, 78.5),
		Vector2(-62.8, 57.5),
		Vector2(-73.5, 68.0),
	]
	for p: Vector2 in pts:
		var w := CaveLayout.to_world(Vector3(p.x, 55.0, p.y))
		var h_ow := terrain.sample_height(w.x, w.z)
		var wp := Vector3(w.x, h_ow, w.z)
		var cut := CaveSDF.is_quad_in_cave_cutout(wp, wp, wp, wp)
		var pt := CaveSDF.eval_sky_patch_t(p.x, p.y)
		# Raycast Terrain (layer 1) vs CaveFloor/CaveWall (layer 1|4) from y=70 down
		var rq := PhysicsRayQueryParameters3D.create(Vector3(w.x, 70.0, w.z), Vector3(w.x, 40.0, w.z), 1 | 4)
		var hit := space.intersect_ray(rq)
		var hit_y := float((hit.position as Vector3).y) if not hit.is_empty() else -1.0
		var hit_name := String(hit.collider.name) if not hit.is_empty() else "NONE"
		# Also find SDF surface y near h_ow
		var sdf_y := -1.0
		for yi in range(480, 620):
			var y := float(yi) * 0.1
			if sdf.eval_sdf_full(p.x, y, p.y, h_ow) < 0.0:
				sdf_y = y
				break
		print("u=%5.1f s=%5.1f | cut=%5s pt=%.3f | ow_h=%5.2f | sdf_y=%5.2f | ray_y=%5.2f (%s)" % [
			p.x, p.y, str(cut), pt, h_ow, sdf_y, hit_y, hit_name
		])

	main.free()
	quit(0)

