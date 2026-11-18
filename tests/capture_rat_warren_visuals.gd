extends SceneTree
## Multi-angle visual capture of the Underground Rat Warren territory.
## Saves PNGs to res://tests/rat_warren_*.png and prints objective luminance/color metrics.
## Run: godot --path d:\slime --script res://tests/capture_rat_warren_visuals.gd [tag]

var _cam: Camera3D = null
var _idx := 0
var _frames := 0
var _tag := "before"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_tag = String(args[0])
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("FAIL: main.tscn missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	var capturer := Capturer.new()
	capturer.name = "RatWarrenCapturer"
	main.add_child(capturer)


class Capturer extends Node3D:
	const SHOTS: Array[Dictionary] = [
		{"name": "01_surface_forecourt", "pos": Vector3(-235.0, 56.0, 536.0), "look": Vector3(-235.0, 22.0, 448.0), "fov": 64.0},
		{"name": "02_burrow_mouth", "pos": Vector3(-235.0, 29.5, 442.0), "look": Vector3(-235.0, 22.8, 412.0), "fov": 60.0},
		{"name": "03_descent_tunnel", "pos": Vector3(-235.0, 21.5, 409.0), "look": Vector3(-235.0, 14.8, 387.0), "fov": 62.0},
		{"name": "04_hub_overview", "pos": Vector3(-235.0, 21.8, 397.0), "look": Vector3(-235.0, 14.0, 372.0), "fov": 66.0},
		{"name": "05_hub_eye", "pos": Vector3(-248.0, 17.0, 388.0), "look": Vector3(-231.0, 14.6, 369.0), "fov": 64.0},
		{"name": "06_hub_rear", "pos": Vector3(-223.0, 18.5, 363.0), "look": Vector3(-241.0, 14.4, 385.0), "fov": 64.0},
		{"name": "07_west_cistern", "pos": Vector3(-257.0, 18.0, 386.0), "look": Vector3(-274.0, 14.4, 377.0), "fov": 62.0},
		{"name": "08_east_burrow", "pos": Vector3(-210.0, 18.0, 384.0), "look": Vector3(-194.0, 15.4, 374.0), "fov": 62.0},
		{"name": "09_north_canyon", "pos": Vector3(-223.0, 15.2, 363.5), "look": Vector3(-224.0, 11.4, 343.0), "fov": 62.0},
		{"name": "10_sanctum_approach", "pos": Vector3(-231.0, 13.8, 343.5), "look": Vector3(-235.0, 11.2, 316.0), "fov": 60.0},
		{"name": "11_sanctum_rear", "pos": Vector3(-246.0, 14.5, 334.0), "look": Vector3(-234.0, 11.0, 320.0), "fov": 62.0},
		{"name": "12_aerial_top", "pos": Vector3(-235.0, 128.0, 548.0), "look": Vector3(-235.0, 20.0, 452.0), "fov": 58.0},
		{"name": "13_west_crystals", "pos": Vector3(-269.0, 16.2, 381.0), "look": Vector3(-282.0, 14.2, 378.5), "fov": 58.0},
		{"name": "14_east_crystals", "pos": Vector3(-203.0, 17.2, 381.0), "look": Vector3(-192.0, 15.6, 377.0), "fov": 58.0},
		{"name": "15_sanctum_crystals", "pos": Vector3(-231.0, 13.8, 323.0), "look": Vector3(-235.5, 11.4, 315.5), "fov": 58.0},
		{"name": "16_hub_crystals", "pos": Vector3(-268.0, 31.0, 476.0), "look": Vector3(-220.0, 22.0, 444.0), "fov": 62.0},
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

	func _apply(idx_i: int) -> void:
		var s: Dictionary = SHOTS[idx_i]
		cam.fov = float(s["fov"])
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)

	func _save(idx_i: int) -> void:
		var s: Dictionary = SHOTS[idx_i]
		var vp := get_viewport()
		if vp == null:
			return
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			print("EMPTY_IMG ", s["name"])
			return
		var fname := "res://tests/rat_warren_%s_%s.png" % [tag, String(s["name"])]
		var out := ProjectSettings.globalize_path(fname)
		img.save_png(out)
		# Objective metrics: luminance, warm/cool split, saturation proxy, dark fraction
		var w := img.get_width()
		var h := img.get_height()
		var lum_sum := 0.0
		var sat_sum := 0.0
		var dark := 0
		var n := 0
		var lum_max := 0.0
		for y in range(0, h, 12):
			for x in range(0, w, 12):
				var c := img.get_pixel(x, y)
				var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				lum_sum += lum
				lum_max = maxf(lum_max, lum)
				var mx := maxf(c.r, maxf(c.g, c.b))
				var mn := minf(c.r, minf(c.g, c.b))
				sat_sum += (mx - mn) / maxf(mx, 0.02)
				if lum < 0.05:
					dark += 1
				n += 1
		print("SHOT %s lum=%.3f sat=%.3f dark=%.1f%% max=%.2f" % [
			String(s["name"]), lum_sum / float(maxi(n, 1)), sat_sum / float(maxi(n, 1)),
			100.0 * float(dark) / float(maxi(n, 1)), lum_max
		])

	func _process(_d: float) -> void:
		frames += 1
		if frames == 1:
			_apply(0)
			return
		if frames < 90:
			return
		if frames >= 90 and ((frames - 90) % 4 == 0):
			_save(idx)
			idx += 1
			if idx >= SHOTS.size():
				get_tree().quit(0)
				return
			_apply(idx)
