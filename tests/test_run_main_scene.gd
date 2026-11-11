extends SceneTree

func _initialize() -> void:
	print("--- TESTING MAIN GAME RUNTIME ---")
	var scn := load("res://scenes/main.tscn") as PackedScene
	if scn == null:
		print("FAIL: Cannot load scenes/main.tscn")
		quit(1)
		return
	var main := scn.instantiate()
	root.add_child(main)
	print("Main game instantiated into scene tree.")
	
	for f in range(60):
		await process_frame
	
	print("Main game ran for 60 frames successfully.")
	quit(0)

