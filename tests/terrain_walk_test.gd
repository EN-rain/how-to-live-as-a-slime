extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		push_error("Failed to load main.tscn")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var driver := TerrainWalkDriver.new()
	driver.name = "TerrainWalkDriver"
	main.add_child.call_deferred(driver)

class TerrainWalkDriver extends Node3D:
	var slime: Slime
	var step_count := 0
	var min_y := 999.0
	var max_y := -999.0
	var saw_sloped_normal := false
	var saw_visual_tilt := false
	var detached_from_ground := false

	func _ready() -> void:
		slime = get_parent().get_node_or_null("Slime") as Slime
		if slime == null:
			print("Slime node not found")
			get_tree().quit(1)
			return

		# Test raycast at (0, 0)
		var space := get_world_3d().direct_space_state
		var test_ray := PhysicsRayQueryParameters3D.new()
		test_ray.from = Vector3(0.0, 250.0, 0.0)
		test_ray.to = Vector3(0.0, -20.0, 0.0)
		test_ray.collision_mask = SlimeMotor.LAYER_OBSTACLES
		var test_hit := space.intersect_ray(test_ray)
		print("RAYCAST AT (0,0): hit=", not test_hit.is_empty(), " pos=", test_hit.get("position", null), " collider=", test_hit.get("collider", null))

		# Find exact terrain surface at (300.0, 300.0) on the continental foothills
		var test_pos := Vector3(300.0, 0.0, 300.0)
		var ray := PhysicsRayQueryParameters3D.new()
		ray.from = Vector3(test_pos.x, 250.0, test_pos.z)
		ray.to = Vector3(test_pos.x, -20.0, test_pos.z)
		ray.collision_mask = SlimeMotor.LAYER_OBSTACLES
		var hit := space.intersect_ray(ray)
		var surface_y := 35.0
		if not hit.is_empty():
			surface_y = (hit.position as Vector3).y

		slime.global_position = Vector3(test_pos.x, surface_y + slime.model.rest_half_height + 0.05, test_pos.z)
		slime.motor.support_y = surface_y
		slime.motor.on_ground = true
		print("Spawned slime cleanly on terrain surface at: ", slime.global_position, " (surface y = ", surface_y, ")")

	func _physics_process(delta: float) -> void:
		step_count += 1

		# Run across hills at 8 m/s in a figure 8 / circle path
		var angle := float(step_count) * 0.03
		var dir := Vector3(cos(angle), 0.0, sin(angle * 2.0)) * 7.0
		slime.motor.velocity = dir

		var y := slime.global_position.y
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)

		var gn := slime.motor.ground_normal
		# Slopes with angle >= 5 degrees have normal.y < 0.996
		if gn.y < 0.995 and gn.y > 0.4:
			saw_sloped_normal = true
			if slime._visual_up.dot(gn) > 0.90:
				saw_visual_tilt = true

		if not slime.motor.on_ground:
			detached_from_ground = true

		if step_count >= 300: # 5 seconds of active running
			print("Terrain walk results after %d steps:" % step_count)
			print("  Min Y: %.2f, Max Y: %.2f (Elevation delta: %.2f m)" % [min_y, max_y, max_y - min_y])
			print("  Saw sloped normal (terrain angles detected): ", saw_sloped_normal)
			print("  Saw visual tilt conforming to slope: ", saw_visual_tilt)
			print("  Detached from ground: ", detached_from_ground)
			print("  Final ground normal: ", slime.motor.ground_normal)
			print("  Final visual up: ", slime._visual_up)

			if saw_sloped_normal and saw_visual_tilt and not detached_from_ground and (max_y - min_y) > 0.3:
				print("TERRAIN TRAVERSAL TEST: PASS")
				get_tree().quit(0)
			else:
				print("TERRAIN TRAVERSAL TEST: FAIL")
				get_tree().quit(1)
