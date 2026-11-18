extends SceneTree

const PREVIEW_DIR := "/home/agent/slime/webwood_previews"
const WorldLandmarks = preload("res://scripts/world_landmarks.gd")

var capture_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _get_preview_dir() -> String:
	if OS.get_name() == "Linux" and DirAccess.dir_exists_absolute("/home/agent/slime"):
		return PREVIEW_DIR
	return ProjectSettings.globalize_path("res://tests/webwood_previews")


func _run() -> void:
	var out_dir := _get_preview_dir()
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		printerr("PREVIEW_FAIL: could not create ", out_dir)
		quit(1)
		return

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("PREVIEW_FAIL: could not load main scene")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	for _i in range(8):
		await physics_frame
		await process_frame

	var terrain := main.get_node_or_null("TerrainScene")
	var slime := main.get_node_or_null("Slime") as Slime
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	var weather := main.get_node_or_null("WorldTimeWeather") as WorldTimeWeather
	if terrain == null or slime == null or sun == null:
		printerr("PREVIEW_FAIL: missing terrain, slime, or sun")
		quit(1)
		return
	if weather != null:
		weather.set_time_of_day(0.45)
		weather.set_weather_state(WorldTimeWeather.WeatherState.CLEAR, 240.0)
	var hud := main.get_node_or_null("HudLayer")
	if hud != null:
		hud.visible = false

	var center := WorldLandmarks.SPIDER_FOREST_CENTER
	var ground_y := float(terrain.sample_height(center.x, center.y))
	slime.global_position = Vector3(center.x, ground_y + 3.0, center.y)
	var cam := Camera3D.new()
	cam.name = "WebwoodPreviewCamera"
	cam.fov = 62.0
	cam.far = 1800.0
	main.add_child(cam)
	cam.make_current()

	# Broad territorial read, from the forest approach toward the broodmother nave.
	# Ground-level approach: the flanked NE dirt trail is the canonical way in, so this
	# is what the cathedral silhouette has to sell from the player's first sight of it.
	var approach := WorldLandmarks.SPIDER_TRAIL_START.lerp(WorldLandmarks.SPIDER_TRAIL_BEND, 0.23)
	var app_x := approach.x
	var app_z := approach.y
	var app_y := float(terrain.sample_height(app_x, app_z))
	cam.global_position = Vector3(app_x, app_y + 3.2, app_z)
	cam.look_at(Vector3(center.x, ground_y + 9.0, center.y), Vector3.UP)
	await _capture(cam, "preview_01_overview.png")

	# Look into the brood hollow from its approach, with the silk ceiling in frame.
	cam.global_position = Vector3(center.x + 11.0, ground_y + 3.6, center.y - 12.0)
	cam.look_at(Vector3(center.x - 2.0, ground_y + 6.0, center.y + 4.0), Vector3.UP)
	await _capture(cam, "preview_02_cathedral_inside.png")

	# Look up from beneath the silk instead of judging forest density from the air.
	cam.global_position = Vector3(center.x - 4.0, ground_y + 2.6, center.y + 6.0)
	cam.look_at(Vector3(center.x + 7.0, ground_y + 11.5, center.y - 6.0), Vector3.UP)
	await _capture(cam, "preview_03_cathedral_canopy.png")

	print("WEBWOOD_PREVIEWS_COMPLETE: ", capture_count)
	quit(0 if capture_count == 3 else 1)


func _capture(cam: Camera3D, file_name: String) -> void:
	for _i in range(5):
		await physics_frame
		await process_frame
	var viewport := cam.get_viewport()
	if viewport == null or viewport.get_texture() == null:
		printerr("PREVIEW_FAIL: no viewport for ", file_name)
		return
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("PREVIEW_FAIL: empty image for ", file_name)
		return
	var path := _get_preview_dir().path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		printerr("PREVIEW_FAIL: save error ", error, " for ", path)
		return
	capture_count += 1
	print("SAVED_WEBWOOD_PREVIEW: ", path, " ", image.get_size())
