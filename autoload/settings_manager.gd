class_name SlimeSettings
extends Node
## Centralized persistent settings manager and procedural UI sound synthesizer.
##
## Saves and loads user preferences from `user://settings.cfg`, applies display,
## graphics, audio, keybinding, accessibility, and gameplay settings globally,
## and synchronizes with both the 2D Main Menu and the 3D Sandbox scene.

static var _instance: SlimeSettings = null

static func get_or_create() -> SlimeSettings:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		var existing := loop.root.get_node_or_null("SettingsManager") as SlimeSettings
		if existing:
			_instance = existing
			return _instance
		var created := SlimeSettings.new()
		created.name = "SettingsManager"
		loop.root.add_child.call_deferred(created)
		created._ensure_initialized()
		_instance = created
		return _instance
	return null

signal settings_changed(category: String, key: String, value: Variant)
signal keybindings_changed()

const SAVE_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const FPS_OPTIONS: Array[int] = [0, 30, 60, 120, 144, 240]

const QUALITY_PRESETS: Array[Dictionary] = [
	{
		"index": 0,
		"name": "Low",
		"render_scale": 1.0,
		"scaling_mode": Viewport.SCALING_3D_MODE_FSR,
		"fxaa": true,
		"msaa": Viewport.MSAA_DISABLED,
		"msaa_idx": 0,
		"shadow_enabled": false,
		"shadow_distance": 30.0,
		"shadow_splits": DirectionalLight3D.SHADOW_ORTHOGONAL,
		"shadow_idx": 0,
		"grass_mult": 0.4,
		"vis_grass": 90.0,
		"vis_trees": 260.0,
		"vis_rocks": 200.0,
		"vis_veg": 180.0,
		"dof_far": false,
	},
	{
		"index": 1,
		"name": "Medium",
		"render_scale": 1.0,
		"scaling_mode": Viewport.SCALING_3D_MODE_FSR,
		"fxaa": true,
		"msaa": Viewport.MSAA_DISABLED,
		"msaa_idx": 0,
		"shadow_enabled": true,
		"shadow_distance": 60.0,
		"shadow_splits": DirectionalLight3D.SHADOW_ORTHOGONAL,
		"shadow_idx": 1,
		"grass_mult": 0.7,
		"vis_grass": 130.0,
		"vis_trees": 420.0,
		"vis_rocks": 340.0,
		"vis_veg": 300.0,
		"dof_far": false,
	},
	{
		"index": 2,
		"name": "High",
		"render_scale": 1.0,
		"scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"fxaa": false,
		"msaa": Viewport.MSAA_2X,
		"msaa_idx": 1,
		"shadow_enabled": true,
		"shadow_distance": 120.0,
		"shadow_splits": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"shadow_idx": 2,
		"grass_mult": 1.0,
		"vis_grass": 160.0,
		"vis_trees": 550.0,
		"vis_rocks": 450.0,
		"vis_veg": 400.0,
		"dof_far": false,
	},
	{
		"index": 3,
		"name": "Ultra",
		"render_scale": 1.0,
		"scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"fxaa": false,
		"msaa": Viewport.MSAA_4X,
		"msaa_idx": 2,
		"shadow_enabled": true,
		"shadow_distance": 200.0,
		"shadow_splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"shadow_idx": 3,
		"grass_mult": 1.3,
		"vis_grass": 220.0,
		"vis_trees": 750.0,
		"vis_rocks": 600.0,
		"vis_veg": 550.0,
		"dof_far": true,
	},
]

const BASE_GRASS_COUNT: int = 38000

const REBINDABLE_ACTIONS: Array[Dictionary] = [
	{"action": "move_forward", "label": "Move Forward"},
	{"action": "move_back", "label": "Move Backward"},
	{"action": "move_left", "label": "Move Left"},
	{"action": "move_right", "label": "Move Right"},
	{"action": "run", "label": "Sprint / Fast Crawl"},
	{"action": "split_follow", "label": "Split Follower Clone"},
	{"action": "split_roam", "label": "Split Roamer Clone"},
	{"action": "merge_clones", "label": "Merge Nearby Clones"},
]

const DEFAULTS: Dictionary = {
	"display": {
		"window_mode": 0,       # 0 = Windowed, 1 = Fullscreen, 2 = Borderless
		"resolution_index": 2,  # 1920x1080
		"vsync": true,
		"max_fps": 0,           # 0 = Unlimited
		"ui_scale": 1.0,
	},
	"graphics": {
		"quality_preset": 0,    # 0 = Low, 1 = Medium, 2 = High, 3 = Ultra
		"msaa": 0,              # 0 = Off, 1 = 2x, 2 = 4x, 3 = 8x
		"shadow_quality": 0,    # 0 = Off, 1 = Low, 2 = Medium, 3 = High
		"grass_density": 0.4,   # Multiplier for procedural grass count
		"jiggle_strength": 1.0, # Shader uJiggleStrength (0.2 .. 2.2)
	},
	"audio": {
		"master_volume": 85.0,
		"music_volume": 70.0,
		"sfx_volume": 85.0,
		"ui_volume": 80.0,
		"mute_unfocused": true,
		"muted": false,
	},
	"controls": {
		"mouse_sensitivity": 0.007,
		"invert_y": false,
		"zoom_speed": 0.30,
	},
	"accessibility": {
		"reduce_motion": false,
		"high_contrast": false,
		"text_scale": 1.0,
	},
	"gameplay": {
		"night_mode": false,
		"show_hud_hints": true,
	}
}

var _data: Dictionary = {}
var _default_bindings: Dictionary = {}
var _custom_bindings: Dictionary = {}
var _audio_players: Array[AudioStreamPlayer] = []
var _audio_idx := 0
var _sound_bank: Dictionary = {}
var _window_focused := true
var _initialized := false
var _last_applied_scene_id: int = 0


func _ready() -> void:
	_instance = self
	_ensure_initialized()
	if get_tree() and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_capture_default_bindings()
	_reset_all_to_defaults_in_memory()
	_setup_ui_sound_bank()
	load_settings()
	_check_cli_and_project_settings_overrides()
	_sync_preset_data()
	apply_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true
		_apply_audio()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		_apply_audio()


func _capture_default_bindings() -> void:
	for item in REBINDABLE_ACTIONS:
		var act: String = item["action"]
		if not InputMap.has_action(act):
			continue
		var codes: Array[int] = []
		for ev in InputMap.action_get_events(act):
			if ev is InputEventKey:
				var ke := ev as InputEventKey
				var code := ke.physical_keycode if ke.physical_keycode != 0 else ke.keycode
				if code != 0 and not codes.has(code):
					codes.append(code)
		_default_bindings[act] = codes.duplicate()
		_custom_bindings[act] = codes.duplicate()


func _reset_all_to_defaults_in_memory() -> void:
	_data.clear()
	for cat in DEFAULTS.keys():
		_data[cat] = (DEFAULTS[cat] as Dictionary).duplicate(true)


func get_value(category: String, key: String, fallback: Variant = null) -> Variant:
	if _data.has(category) and (_data[category] as Dictionary).has(key):
		return _data[category][key]
	if DEFAULTS.has(category) and (DEFAULTS[category] as Dictionary).has(key):
		return DEFAULTS[category][key]
	return fallback


func set_value(category: String, key: String, value: Variant, save_now := true) -> void:
	if category == "graphics" and key == "quality_preset":
		set_quality_preset(int(value), save_now)
		return
	if not _data.has(category):
		_data[category] = {}
	var prev = _data[category].get(key)
	_data[category][key] = value
	_apply_category(category)
	if prev != value:
		settings_changed.emit(category, key, value)
	if save_now:
		save_settings()


func get_quality_preset(idx: int = -1) -> Dictionary:
	if idx < 0:
		idx = int(get_value("graphics", "quality_preset", 0))
	idx = clampi(idx, 0, QUALITY_PRESETS.size() - 1)
	return QUALITY_PRESETS[idx]


func get_quality_preset_name(idx: int = -1) -> String:
	return String(get_quality_preset(idx).get("name", "Low"))


func set_quality_preset(idx: int, save_now: bool = true) -> void:
	idx = clampi(idx, 0, QUALITY_PRESETS.size() - 1)
	var preset: Dictionary = QUALITY_PRESETS[idx]
	if not _data.has("graphics"):
		_data["graphics"] = {}
	_data["graphics"]["quality_preset"] = idx
	_data["graphics"]["msaa"] = preset["msaa_idx"]
	_data["graphics"]["shadow_quality"] = preset["shadow_idx"]
	_data["graphics"]["grass_density"] = preset["grass_mult"]
	_apply_graphics()
	if save_now:
		save_settings()
	settings_changed.emit("graphics", "quality_preset", idx)
	settings_changed.emit("graphics", "msaa", preset["msaa_idx"])
	settings_changed.emit("graphics", "shadow_quality", preset["shadow_idx"])
	settings_changed.emit("graphics", "grass_density", preset["grass_mult"])

	var st := _scene_tree()
	if st and st.current_scene:
		var hud := st.current_scene.get_node_or_null("HudLayer/Hud") as SlimeHud
		if hud == null:
			hud = st.current_scene.get_node_or_null("CanvasLayer/HUD") as SlimeHud
		if hud:
			hud.show_toast("Quality Preset: %s (F%d)" % [preset["name"], 5 + idx], Color(0.62, 0.96, 1.0), 2.2)
	play_ui_sound("poke")


func cycle_quality_preset(save_now: bool = true) -> void:
	var current: int = int(get_value("graphics", "quality_preset", 0))
	var next_idx := (current + 1) % QUALITY_PRESETS.size()
	set_quality_preset(next_idx, save_now)


func _unhandled_key_input(event: InputEvent) -> void:
	var kev := event as InputEventKey
	if kev == null or not kev.pressed or kev.echo:
		return
	var key: int = int(kev.keycode if kev.keycode != KEY_NONE else kev.physical_keycode)
	match key:
		KEY_F5:
			set_quality_preset(0)
			_mark_input_handled()
		KEY_F6:
			set_quality_preset(1)
			_mark_input_handled()
		KEY_F7:
			set_quality_preset(2)
			_mark_input_handled()
		KEY_F8:
			set_quality_preset(3)
			_mark_input_handled()
		KEY_F10:
			cycle_quality_preset()
			_mark_input_handled()


func _mark_input_handled() -> void:
	var st := _scene_tree()
	if st and st.root:
		st.root.set_input_as_handled()


func _check_cli_and_project_settings_overrides() -> void:
	if ProjectSettings.has_setting("slime/graphics/quality_preset"):
		var p = ProjectSettings.get_setting("slime/graphics/quality_preset")
		var idx := _parse_preset_name_or_index(str(p))
		if idx >= 0:
			_data["graphics"]["quality_preset"] = idx
	elif ProjectSettings.has_setting("rendering/quality/preset"):
		var p = ProjectSettings.get_setting("rendering/quality/preset")
		var idx := _parse_preset_name_or_index(str(p))
		if idx >= 0:
			_data["graphics"]["quality_preset"] = idx

	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for i in args.size():
		var arg := args[i].to_lower()
		var val := ""
		if arg.begins_with("--preset=") or arg.begins_with("-preset=") or arg.begins_with("--quality=") or arg.begins_with("-quality="):
			val = arg.get_slice("=", 1).strip_edges()
		elif (arg == "--preset" or arg == "-preset" or arg == "--quality" or arg == "-quality") and i + 1 < args.size():
			val = args[i + 1].to_lower().strip_edges()

		if not val.is_empty():
			var p_idx := _parse_preset_name_or_index(val)
			if p_idx >= 0:
				_data["graphics"]["quality_preset"] = p_idx


func _parse_preset_name_or_index(val: String) -> int:
	val = val.to_lower().strip_edges()
	match val:
		"0", "low":
			return 0
		"1", "med", "medium":
			return 1
		"2", "high":
			return 2
		"3", "ultra":
			return 3
	if val.is_valid_int():
		return clampi(val.to_int(), 0, QUALITY_PRESETS.size() - 1)
	return -1


func _sync_preset_data() -> void:
	if not _data.has("graphics"):
		_data["graphics"] = {}
	var q_idx: int = clampi(int(get_value("graphics", "quality_preset", 0)), 0, QUALITY_PRESETS.size() - 1)
	var preset: Dictionary = QUALITY_PRESETS[q_idx]
	_data["graphics"]["quality_preset"] = q_idx
	if not _data["graphics"].has("msaa"):
		_data["graphics"]["msaa"] = preset["msaa_idx"]
	if not _data["graphics"].has("shadow_quality"):
		_data["graphics"]["shadow_quality"] = preset["shadow_idx"]
	if not _data["graphics"].has("grass_density"):
		_data["graphics"]["grass_density"] = preset["grass_mult"]


func reset_category(category: String) -> void:
	if DEFAULTS.has(category):
		_data[category] = (DEFAULTS[category] as Dictionary).duplicate(true)
		_apply_category(category)
		for k in _data[category].keys():
			settings_changed.emit(category, k, _data[category][k])
	if category == "controls":
		reset_keybindings()
	save_settings()


func get_action_keys(action: String) -> Array[int]:
	if _custom_bindings.has(action):
		var arr: Array[int] = []
		for c in _custom_bindings[action]:
			arr.append(int(c))
		return arr
	return []


func get_action_primary_label(action: String) -> String:
	var codes := get_action_keys(action)
	if codes.is_empty():
		return "Unbound"
	var parts: Array[String] = []
	for i in mini(codes.size(), 2):
		parts.append(OS.get_keycode_string(codes[i]))
	return " / ".join(parts)


func set_action_primary_key(action: String, keycode: int) -> String:
	if keycode == 0:
		return ""
	var displaced_action := ""
	# Check for conflicts across other rebindable actions
	for item in REBINDABLE_ACTIONS:
		var other: String = item["action"]
		if other == action:
			continue
		var other_codes := get_action_keys(other)
		if other_codes.has(keycode):
			other_codes.erase(keycode)
			_custom_bindings[other] = other_codes
			_rebuild_input_map_action(other)
			displaced_action = item["label"]
	var new_codes: Array[int] = [keycode]
	_custom_bindings[action] = new_codes
	_rebuild_input_map_action(action)
	keybindings_changed.emit()
	save_settings()
	return displaced_action


func reset_keybindings() -> void:
	for act in _default_bindings.keys():
		_custom_bindings[act] = (_default_bindings[act] as Array).duplicate()
		_rebuild_input_map_action(act)
	keybindings_changed.emit()
	save_settings()


func _rebuild_input_map_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var non_key_events: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey):
			non_key_events.append(ev)
	InputMap.action_erase_events(action)
	for ev in non_key_events:
		InputMap.action_add_event(action, ev)
	var codes := get_action_keys(action)
	for code in codes:
		var k_phys := InputEventKey.new()
		k_phys.physical_keycode = code as Key
		InputMap.action_add_event(action, k_phys)

		var k_log := InputEventKey.new()
		k_log.keycode = code as Key
		InputMap.action_add_event(action, k_log)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for cat in _data.keys():
		var section: Dictionary = _data[cat]
		for k in section.keys():
			cfg.set_value(cat, k, section[k])
	for act in _custom_bindings.keys():
		cfg.set_value("keybindings", act, _custom_bindings[act])
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for cat in DEFAULTS.keys():
		if not cfg.has_section(cat):
			continue
		var def_sec: Dictionary = DEFAULTS[cat]
		for k in def_sec.keys():
			if cfg.has_section_key(cat, k):
				_data[cat][k] = cfg.get_value(cat, k, def_sec[k])
	if cfg.has_section("keybindings"):
		for act in _default_bindings.keys():
			if cfg.has_section_key("keybindings", act):
				var loaded = cfg.get_value("keybindings", act, _default_bindings[act])
				if loaded is Array and not loaded.is_empty():
					var typed: Array[int] = []
					for c in loaded:
						typed.append(int(c))
					_custom_bindings[act] = typed
					_rebuild_input_map_action(act)


func apply_all() -> void:
	for cat in DEFAULTS.keys():
		_apply_category(cat)


func _apply_category(category: String) -> void:
	match category:
		"display":
			_apply_display()
		"graphics":
			_apply_graphics()
		"audio":
			_apply_audio()
		"controls":
			_apply_to_active_scene()
		"accessibility":
			_apply_accessibility()
		"gameplay":
			_apply_to_active_scene()


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var st := _scene_tree()
	var root_win: Window = st.root if st != null else null
	var is_embedded_win: bool = root_win != null and root_win.is_embedded()

	if not is_embedded_win:
		var mode: int = int(get_value("display", "window_mode", 0))
		var cur_mode := DisplayServer.window_get_mode()
		var cur_borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
		match mode:
			0:
				if cur_borderless:
					DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				if cur_mode != DisplayServer.WINDOW_MODE_WINDOWED:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var res_idx: int = clampi(int(get_value("display", "resolution_index", 2)), 0, RESOLUTIONS.size() - 1)
				var target_size: Vector2i = RESOLUTIONS[res_idx]
				if DisplayServer.window_get_size() != target_size:
					DisplayServer.window_set_size(target_size)
			1:
				if cur_borderless:
					DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				if cur_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			2:
				if not cur_borderless:
					DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
				if cur_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

		var vsync: bool = bool(get_value("display", "vsync", true))
		var target_vsync := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode() != target_vsync:
			DisplayServer.window_set_vsync_mode(target_vsync)

	var fps: int = int(get_value("display", "max_fps", 0))
	Engine.max_fps = maxi(0, fps)

	_apply_ui_scale()


func _scene_tree() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree


func _apply_ui_scale() -> void:
	var st := _scene_tree()
	if st == null or st.root == null:
		return
	var ui_s: float = clampf(float(get_value("display", "ui_scale", 1.0)), 0.80, 1.35)
	var txt_s: float = clampf(float(get_value("accessibility", "text_scale", 1.0)), 0.85, 1.25)
	st.root.content_scale_factor = clampf(ui_s * txt_s, 0.80, 1.40)


func _apply_graphics() -> void:
	var st := _scene_tree()
	if st and st.root:
		var q_idx: int = clampi(int(get_value("graphics", "quality_preset", 0)), 0, QUALITY_PRESETS.size() - 1)
		var preset: Dictionary = QUALITY_PRESETS[q_idx]

		var target_scale: float = float(preset["render_scale"])
		var target_mode: Viewport.Scaling3DMode = preset["scaling_mode"] as Viewport.Scaling3DMode
		var renderer_method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile")
		if renderer_method != "forward_plus" and target_mode == Viewport.SCALING_3D_MODE_FSR:
			target_mode = Viewport.SCALING_3D_MODE_BILINEAR
		var msaa_val: Viewport.MSAA = preset["msaa"] as Viewport.MSAA
		var screen_aa: Viewport.ScreenSpaceAA = Viewport.SCREEN_SPACE_AA_FXAA if preset["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED

		# Check if custom MSAA was requested
		var custom_msaa = get_value("graphics", "msaa", -1)
		if custom_msaa != null and int(custom_msaa) != int(preset["msaa_idx"]):
			msaa_val = clampi(int(custom_msaa), 0, 3) as Viewport.MSAA
			if msaa_val != Viewport.MSAA_DISABLED:
				screen_aa = Viewport.SCREEN_SPACE_AA_DISABLED

		st.root.scaling_3d_scale = target_scale
		st.root.scaling_3d_mode = target_mode
		st.root.msaa_3d = msaa_val
		st.root.screen_space_aa = screen_aa

		if st.current_scene and st.current_scene.is_inside_tree():
			var vp := st.current_scene.get_viewport()
			if vp and vp != st.root:
				vp.scaling_3d_scale = target_scale
				vp.scaling_3d_mode = target_mode
				vp.msaa_3d = msaa_val
				vp.screen_space_aa = screen_aa

	_apply_to_active_scene()


func _apply_audio() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	var muted: bool = bool(get_value("audio", "muted", false))
	var mute_unfocused: bool = bool(get_value("audio", "mute_unfocused", true))
	var should_mute := muted or (mute_unfocused and not _window_focused)
	AudioServer.set_bus_mute(master_idx, should_mute)

	var master_v: float = clampf(float(get_value("audio", "master_volume", 85.0)) / 100.0, 0.0, 1.0)
	AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_v, 0.0001)))


func _apply_accessibility() -> void:
	_apply_ui_scale()
	_apply_to_active_scene()


func _on_tree_node_added(node: Node) -> void:
	var st := _scene_tree()
	if st and node == st.current_scene:
		call_deferred("_apply_to_active_scene")


func _apply_to_active_scene() -> void:
	var st := _scene_tree()
	if st == null:
		return
	var scene := st.current_scene
	if scene == null or not is_instance_valid(scene):
		return

	var scene_id := scene.get_instance_id()
	var is_scene_first_run := (_last_applied_scene_id != scene_id)
	_last_applied_scene_id = scene_id

	var q_idx: int = clampi(int(get_value("graphics", "quality_preset", 0)), 0, QUALITY_PRESETS.size() - 1)
	var preset: Dictionary = QUALITY_PRESETS[q_idx]

	var jiggle: float = float(get_value("graphics", "jiggle_strength", 1.0))
	if bool(get_value("accessibility", "reduce_motion", false)):
		jiggle = minf(jiggle, 0.35)
	var night: float = 1.0 if bool(get_value("gameplay", "night_mode", false)) else 0.0
	var sens: float = float(get_value("controls", "mouse_sensitivity", 0.007))
	var zoom_spd: float = float(get_value("controls", "zoom_speed", 0.30))
	var show_hints: bool = bool(get_value("gameplay", "show_hud_hints", true))
	var grass_mult: float = float(get_value("graphics", "grass_density", preset["grass_mult"]))
	var shadow_q: int = int(get_value("graphics", "shadow_quality", preset["shadow_idx"]))

	# Apply to 3D Sandbox nodes if present
	var props := scene.get_node_or_null("Ecosystem") as SlimeProps
	if props:
		for s in props.registered_slimes:
			if is_instance_valid(s):
				s.set_shader_param("uJiggleStrength", jiggle)
				s.set_shader_param("uNightMode", night)

	var player_slime := scene.get_node_or_null("Slime") as Slime
	if player_slime:
		player_slime.set_shader_param("uJiggleStrength", jiggle)
		player_slime.set_shader_param("uNightMode", night)

	var cam_rig := scene.get_node_or_null("CameraRig") as OrbitCamera
	if cam_rig:
		if "drag_sensitivity" in cam_rig:
			cam_rig.drag_sensitivity = sens
		if "zoom_step" in cam_rig:
			cam_rig.zoom_step = zoom_spd
		if "invert_y" in cam_rig:
			cam_rig.invert_y = bool(get_value("controls", "invert_y", false))

	# HUD Node Path (checks HudLayer/Hud first, falls back to CanvasLayer/HUD)
	var hud := scene.get_node_or_null("HudLayer/Hud") as SlimeHud
	if hud == null:
		hud = scene.get_node_or_null("CanvasLayer/HUD") as SlimeHud
	if hud:
		if hud.has_method("set_hint_visible"):
			hud.set_hint_visible(show_hints)
		elif hud._hint and hud._hint.get_parent():
			hud._hint.get_parent().visible = show_hints

	# DirectionalLight3D Sun: shadows and outdoor baseline lighting
	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		var shadow_on: bool = bool(preset["shadow_enabled"]) and (shadow_q > 0)
		sun.shadow_enabled = shadow_on
		sun.directional_shadow_max_distance = float(preset["shadow_distance"])
		sun.directional_shadow_mode = preset["shadow_splits"] as DirectionalLight3D.ShadowMode

		# Preserve outdoor baseline lighting: 1.35 when daytime is active
		var day_sun_energy := 1.35
		sun.light_energy = lerpf(day_sun_energy, 0.34, night)

	# WorldEnvironment: clean up dead properties and support Ultra DOF far blur
	var world_env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		var env: Environment = world_env.environment
		var day_amb := Color(0.86, 0.93, 1.0, 1.0)
		var night_amb := Color(0.28, 0.48, 0.78, 1.0)
		env.ambient_light_color = day_amb.lerp(night_amb, night)
		var day_amb_energy := 0.95
		env.ambient_light_energy = lerpf(day_amb_energy, 0.42, night)

		# DOF far blur (Ultra preset via CameraAttributesPractical)
		var dof_enabled: bool = bool(preset.get("dof_far", false))
		var cap := world_env.camera_attributes as CameraAttributesPractical
		if cap == null and dof_enabled:
			cap = CameraAttributesPractical.new()
			world_env.camera_attributes = cap
		if cap != null:
			cap.dof_blur_far_enabled = dof_enabled
			if dof_enabled:
				cap.dof_blur_far_distance = 180.0
				cap.dof_blur_far_transition = 80.0

	# Terrain Scene: visibility ranges and grass density
	var terrain := scene.get_node_or_null("TerrainScene")
	if terrain:
		_apply_terrain_visibility_ranges(terrain, preset)

		if "grass_count" in terrain:
			var target_grass := int(roundf(float(BASE_GRASS_COUNT) * grass_mult))
			var current_grass := int(terrain.get("grass_count"))

			if is_scene_first_run:
				# Prevent Startup Double-Rebuild Bug:
				# If grass_count matches target (e.g. default 38000 at High preset),
				# Terrain._ready() already built once, do not touch or re-trigger.
				if current_grass != target_grass:
					_fast_update_terrain_grass(terrain, target_grass)
			else:
				# Runtime preset switch: update grass smoothly without full continent rebuild
				if current_grass != target_grass:
					_fast_update_terrain_grass(terrain, target_grass)


func _apply_terrain_visibility_ranges(terrain: Node, preset: Dictionary) -> void:
	var vis_grass: float = float(preset.get("vis_grass", 160.0))
	var vis_trees: float = float(preset.get("vis_trees", 550.0))
	var vis_rocks: float = float(preset.get("vis_rocks", 450.0))
	var vis_veg: float = float(preset.get("vis_veg", 400.0))

	# Grass & Wispy grass
	var grass_node := terrain.get_node_or_null("Grass") as GeometryInstance3D
	if grass_node:
		grass_node.visibility_range_end = vis_grass
	var wispy_node := terrain.get_node_or_null("GrassWispy") as GeometryInstance3D
	if wispy_node:
		wispy_node.visibility_range_end = vis_grass

	# Trees
	var trees_node := terrain.get_node_or_null("Trees")
	if trees_node:
		for child in trees_node.get_children():
			if child is GeometryInstance3D:
				child.visibility_range_end = vis_trees

	# Rocks
	var rocks_node := terrain.get_node_or_null("Rocks")
	if rocks_node:
		for child in rocks_node.get_children():
			if child is GeometryInstance3D:
				child.visibility_range_end = vis_rocks

	# Vegetation
	var veg_node := terrain.get_node_or_null("Vegetation")
	if veg_node:
		for child in veg_node.get_children():
			if child is GeometryInstance3D:
				child.visibility_range_end = vis_veg


func _fast_update_terrain_grass(terrain: Node, target_grass: int) -> void:
	# 1. Update the property
	terrain.set("grass_count", target_grass)
	# 2. Cancel any pending deferred full-rebuild of continent/caves
	if terrain.get("_rebuild_pending") != null:
		terrain.set("_rebuild_pending", false)

	# 3. Perform fast grass-only rebuild
	var grass_node := terrain.get_node_or_null("Grass") as MultiMeshInstance3D
	var wispy_node := terrain.get_node_or_null("GrassWispy") as MultiMeshInstance3D
	if grass_node != null or wispy_node != null:
		if "_cached_grass_data" in terrain:
			var cache_dict: Dictionary = terrain.get("_cached_grass_data")
			if cache_dict != null:
				cache_dict.clear()
		if grass_node != null and terrain.has_method("_build_grass_multimesh"):
			grass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			terrain.call("_build_grass_multimesh", grass_node)
		if wispy_node != null and terrain.has_method("_build_grass_wispy_multimesh"):
			wispy_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			terrain.call("_build_grass_wispy_multimesh", wispy_node)


# ------------------------------------------------------------------------------------------------
# Procedural UI Sound Synthesizer (zero external asset dependency)
# ------------------------------------------------------------------------------------------------

func _setup_ui_sound_bank() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_audio_players.append(p)

	_sound_bank["hover"] = _synth_tone(520.0, 660.0, 0.045, 0.18)
	_sound_bank["click"] = _synth_tone(440.0, 780.0, 0.075, 0.32)
	_sound_bank["tab"] = _synth_tone(480.0, 620.0, 0.060, 0.25)
	_sound_bank["back"] = _synth_tone(540.0, 340.0, 0.080, 0.28)
	_sound_bank["poke"] = _synth_jelly_boing(290.0, 580.0, 0.16, 0.38)
	_sound_bank["confirm"] = _synth_jelly_boing(380.0, 860.0, 0.20, 0.40)


func play_ui_sound(kind: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if bool(get_value("audio", "muted", false)):
		return
	if not _sound_bank.has(kind) or _audio_players.is_empty():
		return
	var ui_vol: float = clampf(float(get_value("audio", "ui_volume", 80.0)) / 100.0, 0.0, 1.0)
	var master_vol: float = clampf(float(get_value("audio", "master_volume", 85.0)) / 100.0, 0.0, 1.0)
	var combined := ui_vol * master_vol
	if combined <= 0.005:
		return
	var p := _audio_players[_audio_idx % _audio_players.size()]
	_audio_idx += 1
	p.stream = _sound_bank[kind]
	p.volume_db = linear_to_db(combined)
	p.pitch_scale = randf_range(0.96, 1.04)
	p.play()


func _synth_tone(f_start: float, f_end: float, duration: float, amp: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var samples := int(duration * float(mix_rate))
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var phase := 0.0
	for i in samples:
		var t := float(i) / float(maxi(samples - 1, 1))
		var freq := lerpf(f_start, f_end, pow(t, 0.7))
		phase += TAU * freq / float(mix_rate)
		var env := sin(minf(t / 0.12, 1.0) * PI * 0.5) * pow(1.0 - t, 1.8)
		var sig := (sin(phase) * 0.8 + sin(phase * 2.0) * 0.2) * amp * env
		var pcm := clampi(int(sig * 32767.0), -32768, 32767)
		bytes[i * 2] = pcm & 0xFF
		bytes[i * 2 + 1] = (pcm >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _synth_jelly_boing(f_base: float, f_peak: float, duration: float, amp: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var samples := int(duration * float(mix_rate))
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var phase := 0.0
	for i in samples:
		var t := float(i) / float(maxi(samples - 1, 1))
		var wobble := sin(t * TAU * 4.5) * exp(-t * 3.0)
		var freq := lerpf(f_base, f_peak, clampf(t * 1.4 + wobble * 0.35, 0.0, 1.0))
		phase += TAU * freq / float(mix_rate)
		var env := sin(minf(t / 0.08, 1.0) * PI * 0.5) * pow(1.0 - t, 1.5)
		var sig := (sin(phase) * 0.75 + sin(phase * 1.5) * 0.25) * amp * env
		var pcm := clampi(int(sig * 32767.0), -32768, 32767)
		bytes[i * 2] = pcm & 0xFF
		bytes[i * 2 + 1] = (pcm >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = bytes
	return wav
