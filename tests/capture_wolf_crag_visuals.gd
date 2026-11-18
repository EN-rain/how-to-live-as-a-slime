extends SceneTree
## Multi-angle Vulkan visual capture of Wolf Pack Crag (290, y, -240).
## Run: godot --path d:\slime --script res://tests/capture_wolf_crag_visuals.gd [tag]

func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("FAIL: main.tscn missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	var capturer := Capturer.new()
	capturer.name = "WolfCragCapturer"
	main.add_child(capturer)


class Capturer extends Node3D:
	const SHOTS: Array[Dictionary] = [
		{"name": "01_den_front", "pos": Vector3(291.5, 81.2, -224.5), "look": Vector3(290.0, 79.2, -245.0), "fov": 62.0},
		{"name": "02_overview_sw", "pos": Vector3(276.0, 85.5, -221.0), "look": Vector3(291.0, 79.0, -241.0), "fov": 64.0},
		{"name": "03_overview_se", "pos": Vector3(306.5, 85.5, -222.0), "look": Vector3(289.0, 79.0, -241.0), "fov": 64.0},
		{"name": "04_hearth_and_larder", "pos": Vector3(282.0, 80.8, -231.0), "look": Vector3(298.0, 78.8, -238.5), "fov": 62.0},
		{"name": "05_approach_trail", "pos": Vector3(275.0, 82.5, -218.0), "look": Vector3(290.0, 79.2, -240.0), "fov": 60.0},
		{"name": "06_aerial_top", "pos": Vector3(290.0, 152.0, -176.0), "look": Vector3(290.0, 77.5, -242.0), "fov": 58.0},
	]
	var cam: Camera3D
	var idx := 0
	var frames := 0
	var tag := "before"

	func _ready() -> void:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			tag = String(args[0])
		cam = Camera3D.new()
		cam.current = true
		cam.near = 0.1
		cam.far = 2500.0
		add_child(cam)
		var hud := get_parent().get_node_or_null("HudLayer") as CanvasLayer
		if hud != null:
			hud.visible = false
		var tw := get_parent().get_node_or_null("WorldTimeWeather")
		if tw != null and tw.has_method("set_time_of_day"):
			tw.call("set_time_of_day", 0.42)
		if tw != null and tw.has_method("set_weather_state"):
			var ws = tw.get("WeatherState")
			if ws != null:
				tw.call("set_weather_state", ws.get("CLEAR"), 240.0)

	func _process(_delta: float) -> void:
		if idx >= SHOTS.size():
			get_tree().quit(0)
			return
		var s: Dictionary = SHOTS[idx]
		if frames == 0:
			cam.fov = float(s["fov"])
			cam.global_position = s["pos"]
			cam.look_at(s["look"], Vector3.UP)
		frames += 1
		if frames >= 5:
			var img := get_viewport().get_texture().get_image()
			var out_path := "res://tests/wolf_crag_%s_%s.png" % [tag, s["name"]]
			img.save_png(out_path)
			print("SHOT %s saved" % s["name"])
			idx += 1
			frames = 0
