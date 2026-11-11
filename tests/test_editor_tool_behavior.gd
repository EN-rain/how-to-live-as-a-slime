extends SceneTree

# Test what happens in tool mode when terrain.tscn is loaded
func _initialize() -> void:
	print("--- TESTING EDITOR TOOL MODE BEHAVIOR ---")
	var terrain_scene := load("res://terrain/terrain.tscn") as PackedScene
	var terrain := terrain_scene.instantiate() as TerrainScene
	root.add_child(terrain)

	# Simulate 10 frames of editor processing
	for f in 10:
		# Process frame
		pass

	print("Finished 10 frames.")
	quit(0)

