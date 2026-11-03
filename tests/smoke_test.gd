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

	_finish()


func _find_edibles(node: Node) -> Array:
	var found := []
	for child in node.get_children():
		if child is Edible:
			found.append(child)
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
