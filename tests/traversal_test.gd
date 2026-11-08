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
	# Force the ecosystem's authored seed: world generation, prop detail RNG and the
	# slime-local clone streams all derive from it, so every run is reproducible.
	var props := main.get_node_or_null("Ecosystem") as SlimeProps
	if props != null:
		props.spawn_seed = 20240607
	root.add_child(main)

	var driver: Node = (load("res://tests/traversal_driver.gd") as GDScript).new()
	driver.name = "TraversalDriver"
	main.add_child(driver)
