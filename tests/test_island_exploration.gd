extends SceneTree

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		push_error("Failed to load main.tscn")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var explorer := ContinentExplorer.new()
	explorer.name = "ContinentExplorer"
	main.add_child.call_deferred(explorer)

class ContinentExplorer extends Node3D:
	var slime: Slime
	var step := 0
	var min_y := 999.0
	var max_y := -999.0
	var fell_through := false

	func _ready() -> void:
		slime = get_parent().get_node_or_null("Slime") as Slime
		if slime == null:
			print("Slime node not found")
			get_tree().quit(1)
			return
		print("Continent Explorer started. Initial slime pos: ", slime.global_position)

	func _physics_process(delta: float) -> void:
		step += 1
		if slime == null:
			return

		# Drive slime across the central continental plains
		var move_dir := Vector3(0.5, 0.0, -1.0).normalized()
		slime.motor.velocity = move_dir * 8.0

		var pos := slime.global_position
		min_y = minf(min_y, pos.y)
		max_y = maxf(max_y, pos.y)

		# Fall-through check
		if pos.y < -35.0:
			fell_through = true

		if step >= 240:
			print("=== CONTINENT EXPLORATION REPORT ===")
			print("Steps: ", step)
			print("Final pos: ", pos, " support_y: ", slime.motor.support_y)
			print("Min Y: ", min_y, " Max Y: ", max_y, " (Elevation delta: ", max_y - min_y, " m)")
			print("Fell through: ", fell_through)
			print("On ground: ", slime.motor.on_ground)

			var success := not fell_through and slime.motor.on_ground
			if success:
				print("CONTINENT EXPLORATION TEST: PASS")
				get_tree().quit(0)
			else:
				print("CONTINENT EXPLORATION TEST: FAIL")
				get_tree().quit(1)
