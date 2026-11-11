extends SceneTree

func _initialize() -> void:
	print("--- TESTING MAIN MENU RUNTIME ---")
	var scn := load("res://main_menu/main_menu.tscn") as PackedScene
	if scn == null:
		print("FAIL: Cannot load main_menu.tscn")
		quit(1)
		return
	var menu := scn.instantiate()
	root.add_child(menu)
	print("Main menu instantiated into scene tree.")
	
	for f in range(60):
		await process_frame
	
	print("Main menu ran for 60 frames without crashing.")
	quit(0)

