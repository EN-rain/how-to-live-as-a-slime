extends Node

## Headless smoke test for the prototype loop, scene architecture, NavigationAgent3D, and Pause Menu.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## Exit code is 0 when every check passes.

const STATUE: EdibleData = preload("res://resources/edibles/statue.tres")

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player := main.get_node_or_null("Player") as Slime
	_check(player != null, "main scene spawns a Slime player")
	if player == null:
		_finish()
		return

	var world := main.get_node_or_null("World") as GameWorld
	_check(
		world != null and world.get_node_or_null("NavigationRegion3D/Trees") != null,
		"main scene instances World scene with NavigationRegion3D and obstacle props"
	)
	_check(
		world != null and world.nav_region != null and world.nav_region.navigation_mesh != null and world.nav_region.navigation_mesh.get_polygon_count() > 100,
		"world builds an obstacle-carved NavigationMesh around trees and rocks"
	)
	if world != null:
		var flat_h := world.terrain_height(0.0, 0.0)
		var hill_h := world.terrain_height(28.0, -30.0)
		_check(
			absf(flat_h) < 0.01 and absf(hill_h) > 0.5,
			"world ground is hilly away from a flat spawn (center %.2f, hill %.2f)" % [flat_h, hill_h]
		)
		var nav_min := INF
		var nav_max := -INF
		for v in world.nav_region.navigation_mesh.get_vertices():
			nav_min = minf(nav_min, v.y)
			nav_max = maxf(nav_max, v.y)
		_check(nav_max - nav_min > 1.0, "navmesh follows the terrain height (y range %.2f)" % (nav_max - nav_min))
	_check(
		player.get_node_or_null("Body/LeftEye/Pupil") != null,
		"slime visuals (eyes and pupils) are authored in slime.tscn"
	)

	var menus := main.get_node_or_null("GameMenus") as GameMenus
	_check(
		menus != null and menus is CanvasLayer and menus.resume_button != null and menus.save_button != null and menus.quit_button != null,
		"GameMenus is a CanvasLayer overlay with Resume, Save, and Quit buttons"
	)

	var edibles := _find_edibles(main)
	_check(edibles.size() >= 50, "world spawns >= 50 edibles (got %d)" % edibles.size())
	_check(
		edibles[0].data != null and edibles[0].size > 0.0 and edibles[0].data.visual_scene != null,
		"edibles get their kind and .tscn visual_scene from an EdibleData resource"
	)

	var mobs := _find_mobs(main)
	_check(
		mobs.size() >= 10 and mobs[0].get_node_or_null("NavigationAgent3D") != null,
		"mobs spawn with .tscn visuals and NavigationAgent3D"
	)

	var start_size: float = player.size
	var start_eaten: int = player.eaten_count
	var victims := edibles.slice(0, 5)
	for edible in victims:
		player._eat(edible)
	_check(player.eaten_count == start_eaten + 5, "eating increments eaten_count by 5")
	_check(player.size > start_size, "slime grows after eating (%.3f -> %.3f)" % [start_size, player.size])

	# The absorb tween should free the props after ~0.3s.
	await get_tree().create_timer(1.0).timeout
	var still_alive := 0
	for edible in victims:
		if is_instance_valid(edible):
			still_alive += 1
	_check(still_alive == 0, "eaten props are freed by the dissolve tween")

	# Damage shrinks the slime and never drops it below the floor size.
	var grown_size: float = player.size
	player.take_damage(12.0)
	_check(player.size <= grown_size, "damage shrinks the slime")
	player.take_damage(99999.0)
	_check(player.size >= player.min_size - 0.001, "size never drops below min_size")

	# Input actions must come from Project Settings, not runtime registration.
	var actions := ["move_forward", "move_back", "move_left", "move_right", "jump", "restart", "pause", "quick_save", "quick_load"]
	var missing := 0
	for action in actions:
		if not InputMap.has_action(action):
			missing += 1
	_check(missing == 0, "input actions exist in Project Settings (missing %d)" % missing)

	# Growing into a prop you are already standing on must eat it. The prop only
	# sends `area_entered` once (while it is still too big), so the slime has to
	# re-check its overlaps after a size change.
	var big_meal := (load("res://scenes/edible.tscn") as PackedScene).instantiate() as Edible
	big_meal.data = STATUE
	main.add_child(big_meal)
	big_meal.global_position = player.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not big_meal._being_eaten, "a prop too big to eat is not swallowed on contact")
	player.add_nutrition(600.0)
	await get_tree().create_timer(0.4).timeout
	_check(
		not is_instance_valid(big_meal) or big_meal._being_eaten,
		"growing past an overlapping prop eats it"
	)

	# Pause toggle and Save/load round-trip check.
	if menus != null:
		menus.toggle_pause_menu()
		var paused_ok := get_tree().paused and menus.pause_panel.visible
		menus.toggle_pause_menu()
		_check(paused_ok and not get_tree().paused, "Escape pause menu toggles scene tree pause on and off")

	var saved_eaten: int = player.eaten_count
	var save_ok: bool = main.save_game()
	player.eaten_count = 0
	var load_ok: bool = main.load_game()
	_check(save_ok and load_ok and player.eaten_count == saved_eaten, "save and load round-trip player state")
	main.delete_saved_game()

	_finish()


func _find_edibles(node: Node) -> Array[Edible]:
	var found: Array[Edible] = []
	for child in node.get_children():
		var edible := child as Edible
		if edible != null:
			found.append(edible)
		found.append_array(_find_edibles(child))
	return found


func _find_mobs(node: Node) -> Array[Mob]:
	var found: Array[Mob] = []
	for child in node.get_children():
		var mob := child as Mob
		if mob != null:
			found.append(mob)
		found.append_array(_find_mobs(child))
	return found


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	if _failures == 0:
		print("SMOKE TEST OK")
	else:
		push_error("SMOKE TEST FAILED (%d check(s))" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
