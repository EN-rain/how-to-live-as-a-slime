extends SceneTree
## Headless fixture runner: loads the real main scene and hands control to the
## traversal driver, which builds deterministic gates/roofs and drives the inputs.

func _initialize() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		push_error("traversal_test: cannot load main.tscn")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)

	var driver: Node = (load("res://tests/traversal_driver.gd") as GDScript).new()
	driver.name = "TraversalDriver"
	main.add_child(driver)
