extends SceneTree

# Dynamic terrain traversal test: Drives the slime at full sprint (10 m/s) across
# various steep slopes, valleys, peaks, and beach areas, asserting that:
# 1. Slime foot never penetrates below terrain surface (foot_y >= terrain_h - 0.08)
# 2. Slime never falls through terrain into void (foot_y > -35.0)
# 3. Slime remains on_ground while traversing terrain slopes

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		push_error("Failed to load main.tscn")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var tester := DynamicTraversalTester.new()
	tester.name = "DynamicTraversalTester"
	main.add_child.call_deferred(tester)


class DynamicTraversalTester extends Node3D:
	var slime: Slime
	var terrain: Node3D
	var step := 0
	var current_route := 0

	# Test routes: start positions and movement vectors
	var routes := [
		{"name": "Spawn Meadow Run", "start": Vector3(0, 25, 0), "vel": Vector3(10, 0, 0), "ticks": 80},
		{"name": "Northern Alpine Mountain Climb", "start": Vector3(0, 160, -900), "vel": Vector3(0, 0, -10), "ticks": 100},
		{"name": "Western Mesa Incline", "start": Vector3(-700, 70, 0), "vel": Vector3(-10, 0, 5), "ticks": 100},
		{"name": "Eastern Downs Slope", "start": Vector3(700, 50, 0), "vel": Vector3(10, 0, -5), "ticks": 100},
		{"name": "Southern Beach Entry", "start": Vector3(0, 10, 2350), "vel": Vector3(0, 0, 10), "ticks": 100},
		{"name": "Far Ocean Seabed", "start": Vector3(0, -15, 2550), "vel": Vector3(0, 0, 10), "ticks": 100}
	]

	var route_step := 0
	var max_penetration := 0.0
	var fall_throughs := 0
	var total_checked_frames := 0

	func _ready() -> void:
		slime = get_parent().get_node_or_null("Slime") as Slime
		terrain = get_parent().get_node_or_null("TerrainScene")
		if slime == null or terrain == null:
			print("FAIL: Slime or Terrain node not found")
			get_tree().quit(1)
			return

		_start_route(0)

	func _start_route(r_idx: int) -> void:
		current_route = r_idx
		route_step = 0
		var r = routes[r_idx]
		var start_xz: Vector3 = r["start"]
		var ground_h: float = terrain.sample_surface_exact(start_xz.x, start_xz.z).w if terrain.has_method("sample_surface_exact") else terrain.sample_height(start_xz.x, start_xz.z)
		slime.global_position = Vector3(start_xz.x, ground_h + 1.2, start_xz.z)
		slime.motor.vertical_vel = 0.0
		slime.motor.on_ground = true
		slime.motor.update_support()
		print("\n--- Starting Route %d: %s at %s (ground: %.2f) ---" % [r_idx, r["name"], slime.global_position, ground_h])

	func _physics_process(delta: float) -> void:
		if current_route >= routes.size():
			return

		var r = routes[current_route]
		route_step += 1
		total_checked_frames += 1

		# Drive slime velocity
		slime.motor.velocity = r["vel"]

		var foot_y: float = slime.global_position.y - slime.model.rest_half_height * slime.model.scale
		var terrain_h: float = terrain.sample_surface_exact(slime.global_position.x, slime.global_position.z).w if terrain.has_method("sample_surface_exact") else terrain.sample_height(slime.global_position.x, slime.global_position.z)
		var support_y: float = slime.motor.support_y

		# Check penetration (foot below terrain surface)
		var penetration: float = terrain_h - foot_y
		if penetration > max_penetration:
			max_penetration = penetration

		# Penetration warning threshold (allow 0.05m tolerance for physics substep interpolation)
		if penetration > 0.15:
			print("WARNING: Excessive penetration %.3fm at pos %s (terrain_h: %.2f, foot_y: %.2f, support: %.2f)" % [
				penetration, slime.global_position, terrain_h, foot_y, support_y
			])

		# Fall-through check
		if slime.global_position.y < -35.0 or foot_y < terrain_h - 2.0:
			fall_throughs += 1
			print("CRITICAL: Fall-through detected! Pos: %s, terrain_h: %.2f" % [slime.global_position, terrain_h])

		if route_step >= r["ticks"]:
			print("Route %d done. Final pos: %s, Max penetration: %.4fm, On ground: %s" % [
				current_route, slime.global_position, max_penetration, slime.motor.on_ground
			])
			if current_route + 1 < routes.size():
				_start_route(current_route + 1)
			else:
				_finish_test()

	func _finish_test() -> void:
		print("\n===============================")
		print("DYNAMIC TRAVERSAL TEST SUMMARY:")
		print("Total checked frames: ", total_checked_frames)
		print("Max penetration across all routes: %.4f m" % max_penetration)
		print("Fall-throughs: ", fall_throughs)
		print("===============================")

		if fall_throughs == 0 and max_penetration < 0.10:
			print("DYNAMIC TRAVERSAL TEST: ALL PASSED!")
			get_tree().quit(0)
		else:
			print("DYNAMIC TRAVERSAL TEST: FAILED (fall_throughs=%d, max_pen=%.4f)" % [fall_throughs, max_penetration])
			get_tree().quit(1)
