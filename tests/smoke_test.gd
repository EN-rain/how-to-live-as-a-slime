extends Node

## Headless smoke test for the prototype loop.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## Exit code is 0 when every check passes.

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

	var edibles := _find_edibles(main)
	_check(edibles.size() >= 50, "world spawns >= 50 edibles (got %d)" % edibles.size())

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
	_check(player.size >= Slime.MIN_SIZE - 0.001, "size never drops below MIN_SIZE")

	# Restart reloads the scene, so _setup_input() runs again on a live InputMap.
	# Re-registering must not pile up duplicate key bindings.
	var jump_events := InputMap.action_get_events("jump").size()
	main._setup_input()
	main._setup_input()
	_check(
		InputMap.action_get_events("jump").size() == jump_events,
		"re-running input setup does not duplicate bindings"
	)

	# Growing into a prop you are already standing on must eat it. The prop only
	# sends `area_entered` once (while it is still too big), so the slime has to
	# re-check its overlaps after a size change.
	var big_meal := (load("res://scenes/edible.tscn") as PackedScene).instantiate() as Edible
	big_meal.kind = "statue"
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

	_finish()


func _find_edibles(node: Node) -> Array[Edible]:
	var found: Array[Edible] = []
	for child in node.get_children():
		var edible := child as Edible
		if edible != null:
			found.append(edible)
		found.append_array(_find_edibles(child))
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
