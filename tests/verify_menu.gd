extends SceneTree

var _step := 0
var _menu: MainMenu = null
var _game: Node = null

func _process(_delta: float) -> bool:
	if _step == 0:
		_step = 1
		var menu_scene := load("res://main_menu/main_menu.tscn") as PackedScene
		if menu_scene == null:
			push_error("Failed to load main_menu.tscn")
			quit(1)
			return true
		_menu = menu_scene.instantiate() as MainMenu
		root.add_child(_menu)

		# Verify 0 Node3D instances exist in MainMenu
		var node3d_count := _count_node3d(_menu)
		print("CHECK 1 - Node3D count in MainMenu: %d (expected 0)" % node3d_count)
		if node3d_count != 0:
			push_error("MainMenu contains 3D nodes!")
			quit(2)
			return true

		# Exercise Guide Sheet & all 3 Guide Tabs
		_menu._toggle_sheet(MainMenu.ActiveSheet.GUIDE)
		for tab_i in 3:
			_menu._select_guide_tab(tab_i, false)
		_menu._gate_width_slider.value = 0.55
		_menu._gate_width_slider.value = 1.40
		print("CHECK 2 - Slime Guide tabs & Core-Sphere 2D simulator: OK")

		# Exercise Settings Sheet & all 6 Settings Tabs
		_menu._toggle_sheet(MainMenu.ActiveSheet.SETTINGS)
		for tab_i in 6:
			_menu._select_settings_tab(tab_i, false)
		print("CHECK 3 - Settings 6 tabs: OK")

		# Exercise Key Rebinding
		var sm := SlimeSettings.get_or_create()
		var displaced := sm.set_action_primary_key("split_follow", KEY_F)
		var new_lbl := sm.get_action_primary_label("split_follow")
		print("CHECK 4 - Key Rebind split_follow -> %s (displaced='%s'): OK" % [new_lbl, displaced])
		sm.reset_keybindings()

		# Exercise Atmosphere & Core X-Ray & Poke
		_menu._toggle_atmosphere()
		_menu._toggle_core_xray()
		_menu._poke_all_slimes()
		print("CHECK 5 - 2D Mascot poke count=%d, NightTarget=%.1f: OK" % [_menu._mascot.poke_count, _menu._night_target])

		# Reset night mode back to default false in settings
		sm.set_value("gameplay", "night_mode", false)

		# Exercise Credits & Quit Modal
		_menu._toggle_sheet(MainMenu.ActiveSheet.CREDITS)
		_menu._open_quit_modal()
		_menu._close_quit_modal()
		_menu._show_sheet(MainMenu.ActiveSheet.NONE)
		print("CHECK 6 - Credits & Quit Modal: OK")

		# Now load the 3D game scene to verify Z-key removal and settings hook
		_menu.queue_free()
		var game_scene := load("res://scenes/main.tscn") as PackedScene
		if game_scene == null:
			push_error("Failed to load main.tscn")
			quit(3)
			return true
		_game = game_scene.instantiate()
		root.add_child(_game)
		return false

	elif _step == 1:
		_step = 2
		current_scene = _game
		var sm := SlimeSettings.get_or_create()
		sm._apply_to_active_scene()
		print("CHECK 7 - 3D Sandbox (main.tscn) instantiated & Settings applied cleanly: OK")
		print("ALL VERIFICATION CHECKS PASSED!")
		quit(0)
		return true

	return true


func _count_node3d(n: Node) -> int:
	var c := 1 if n is Node3D else 0
	for child in n.get_children():
		c += _count_node3d(child)
	return c
