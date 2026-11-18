extends SceneTree
## Multi-angle Vulkan visual capture of Spider Silk Forest (Webwood, -410, y, 480).
## Run: godot --path d:\slime --script res://tests/capture_spider_webwood_visuals.gd [tag]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var tag := String(args[0]) if args.size() > 0 else "current"
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("FAIL: main.tscn missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	call_deferred("_run_shots", main, tag)


func _run_shots(main: Node, tag: String) -> void:
	for _i in range(8):
		await physics_frame
		await process_frame

	var terrain := main.get_node_or_null("TerrainScene")
	var hud := main.get_node_or_null("HudLayer") as CanvasLayer
	if hud != null:
		hud.visible = false
	var tw := main.get_node_or_null("WorldTimeWeather")
	if tw != null and tw.has_method("set_time_of_day"):
		tw.call("set_time_of_day", 0.42)
	if tw != null and tw.has_method("set_weather_state"):
		var ws = tw.get("WeatherState")
		if ws != null:
			tw.call("set_weather_state", ws.get("CLEAR"), 240.0)

	var cam := Camera3D.new()
	cam.current = true
	cam.near = 0.1
	cam.far = 2500.0
	main.add_child(cam)

	var cx := -410.0
	var cz := 480.0
	var cy := float(terrain.sample_height(cx, cz)) if terrain != null else 54.5
	var app_pt := Vector2(-335.0, 390.0).lerp(Vector2(-396.0, 468.0), 0.70)
	var app_y := float(terrain.sample_height(app_pt.x, app_pt.y)) if terrain != null else cy

	var shots: Array[Dictionary] = [
		{"name": "01_trail_tunnel", "pos": Vector3(app_pt.x, app_y + 3.2, app_pt.y), "look": Vector3(-406.0, cy + 5.8, 476.0), "fov": 64.0},
		{"name": "02_brood_hollow_nave", "pos": Vector3(-397.5, cy + 3.8, 467.5), "look": Vector3(-412.5, cy + 5.0, 483.5), "fov": 64.0},
		{"name": "03_canopy_vault", "pos": Vector3(-414.0, cy + 2.8, 485.5), "look": Vector3(-404.0, cy + 10.5, 474.5), "fov": 66.0},
		{"name": "04_tangled_trunks_and_ground", "pos": Vector3(-419.0, cy + 3.6, 472.5), "look": Vector3(-405.5, cy + 2.6, 482.5), "fov": 64.0},
		{"name": "05_egg_cache_and_shrouds", "pos": Vector3(-403.5, cy + 3.8, 489.0), "look": Vector3(-413.2, cy + 1.8, 481.5), "fov": 62.0},
		{"name": "06_aerial_overview", "pos": Vector3(-410.0, cy + 78.0, 552.0), "look": Vector3(-410.0, cy + 4.0, 480.0), "fov": 58.0},
	]

	for s: Dictionary in shots:
		cam.fov = float(s["fov"])
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)
		for _f in range(5):
			await physics_frame
			await process_frame
		var img := cam.get_viewport().get_texture().get_image()
		var out_path := "res://tests/spider_webwood_%s_%s.png" % [tag, String(s["name"])]
		img.save_png(out_path)
		print("SHOT %s saved" % String(s["name"]))

	quit(0)
