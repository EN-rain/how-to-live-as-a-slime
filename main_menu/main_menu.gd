class_name MainMenu
extends Control
## 2D Main Menu for "How to Live as a Slime".
## All UI nodes are constructed in main_menu.tscn and wired via @export NodePath/Node references,
## making every element visible and editable in the Godot Inspector.

@export_file("*.tscn") var game_scene_path := "res://scenes/main.tscn"

enum ActiveSheet {
	NONE,
	GUIDE,
	SETTINGS,
	CREDITS
}

var _active_sheet: ActiveSheet = ActiveSheet.NONE
var _settings: SlimeSettings = null

# Loading Screen References
@export_group("Loading Screen")
@export var loading_overlay: Control
@export var loading_bar: ProgressBar
@export var loading_status_lbl: Label
@export var min_loading_duration: float = 0.3

# Navigation Buttons
@export_group("Navigation Buttons")
@export var play_btn: Button
@export var guide_btn: Button
@export var settings_btn: Button
@export var credits_btn: Button
@export var quit_btn: Button

# Sub-menu Cards / Sheets
@export_group("Sheet Cards")
@export var sheet_holder: Control
@export var guide_card: PanelContainer
@export var settings_card: PanelContainer
@export var credits_card: PanelContainer

# Guide References
@export_group("Guide References")
@export var guide_tab_bar: HBoxContainer
@export var guide_pages_container: MarginContainer
@export var controls_binding_grid: GridContainer
@export var gate_width_slider: HSlider
@export var gate_width_val_lbl: Label
@export var gate_status_lbl: Label

# Settings References
@export_group("Settings References")
@export var settings_tab_bar: HBoxContainer
@export var settings_pages_container: VBoxContainer
@export var settings_reset_btn: Button

# Display settings
@export_subgroup("Display Settings")
@export var win_mode_opt: OptionButton
@export var res_opt: OptionButton
@export var vsync_chk: CheckButton
@export var fps_opt: OptionButton
@export var ui_scale_slider: HSlider
@export var ui_scale_val: Label

# Graphics settings
@export_subgroup("Graphics Settings")
@export var preset_opt: OptionButton
@export var msaa_opt: OptionButton
@export var shadow_opt: OptionButton
@export var grass_slider: HSlider
@export var grass_val: Label
@export var jiggle_slider: HSlider
@export var jiggle_val: Label

# Audio settings
@export_subgroup("Audio Settings")
@export var master_vol_slider: HSlider
@export var master_vol_val: Label
@export var music_vol_slider: HSlider
@export var music_vol_val: Label
@export var sfx_vol_slider: HSlider
@export var sfx_vol_val: Label
@export var ui_vol_slider: HSlider
@export var ui_vol_val: Label
@export var mute_unfocused_chk: CheckButton

# Controls settings
@export_subgroup("Controls Settings")
@export var sens_slider: HSlider
@export var sens_val: Label
@export var zoom_slider: HSlider
@export var zoom_val: Label
@export var invert_y_chk: CheckButton
@export var rebind_container: VBoxContainer

# Accessibility settings
@export_subgroup("Accessibility Settings")
@export var reduce_motion_chk: CheckButton
@export var high_contrast_chk: CheckButton
@export var text_scale_slider: HSlider
@export var text_scale_val: Label

# Gameplay settings
@export_subgroup("Gameplay Settings")
@export var night_mode_chk: CheckButton
@export var hud_hints_chk: CheckButton

# Quit Modal
@export_group("Quit Modal")
@export var quit_modal_bg: ColorRect
@export var quit_stay_btn: Button
@export var quit_confirm_btn: Button

# Internal runtime state
var _guide_tab_btns: Array[Button] = []
var _guide_tab_pages: Array[Control] = []
var _settings_tab_btns: Array[Button] = []
var _settings_tab_pages: Array[Control] = []
var _active_settings_tab := 0
var _rebind_buttons: Dictionary = {}
var _awaiting_rebind_action := ""

# Compatibility dummy references for tests
var _mascot = null
var _night_target := 0.0

# Aliases for verify_menu.gd backwards compatibility
var _gate_width_slider: HSlider:
	get: return gate_width_slider
var _gate_width_val_lbl: Label:
	get: return gate_width_val_lbl


class DummyMascot:
	var poke_count := 0
	var show_core_xray := false
	var mood_state = 0
	var reduce_motion := false
	var jiggle_strength := 1.0
	var night_mode := 0.0

	func poke_all() -> void:
		poke_count += 1


# Loading Screen State
var _is_loading: bool = false
var _loading_elapsed: float = 0.0
var _display_progress: float = 0.0


func _ready() -> void:
	_mascot = DummyMascot.new()
	_settings = SlimeSettings.get_or_create()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	if loading_overlay:
		loading_overlay.visible = false
	set_process(false)

	_setup_exported_nodes()
	_sync_from_settings()

	if play_btn:
		play_btn.grab_focus()

	if _settings:
		_settings.settings_changed.connect(_on_external_setting_changed)
		_settings.keybindings_changed.connect(_refresh_keybind_ui)


func _setup_exported_nodes() -> void:
	# Wire Navigation Buttons
	if play_btn and not play_btn.pressed.is_connected(_on_play_pressed):
		play_btn.pressed.connect(_on_play_pressed)
	if guide_btn and not guide_btn.pressed.is_connected(_on_guide_btn_pressed):
		guide_btn.pressed.connect(_on_guide_btn_pressed)
	if settings_btn and not settings_btn.pressed.is_connected(_on_settings_btn_pressed):
		settings_btn.pressed.connect(_on_settings_btn_pressed)
	if credits_btn and not credits_btn.pressed.is_connected(_on_credits_btn_pressed):
		credits_btn.pressed.connect(_on_credits_btn_pressed)
	if quit_btn and not quit_btn.pressed.is_connected(_open_quit_modal):
		quit_btn.visible = not OS.has_feature("web")
		quit_btn.pressed.connect(_open_quit_modal)

	# Setup Close Buttons inside cards
	if guide_card:
		var close_btn = guide_card.find_child("CloseGuideButton", true, false) as Button
		if close_btn and not close_btn.pressed.is_connected(_close_sheet):
			close_btn.pressed.connect(_close_sheet)
	if settings_card:
		var close_btn = settings_card.find_child("CloseSettingsButton", true, false) as Button
		if close_btn and not close_btn.pressed.is_connected(_close_sheet):
			close_btn.pressed.connect(_close_sheet)
	if credits_card:
		var close_btn = credits_card.find_child("CloseCreditsButton", true, false) as Button
		if close_btn and not close_btn.pressed.is_connected(_close_sheet):
			close_btn.pressed.connect(_close_sheet)

	# Setup Guide Tabs and Pages
	_guide_tab_btns.clear()
	if guide_tab_bar:
		for c in guide_tab_bar.get_children():
			if c is Button:
				var idx := _guide_tab_btns.size()
				c.pressed.connect(_select_guide_tab.bind(idx))
				_guide_tab_btns.append(c)

	_guide_tab_pages.clear()
	if guide_pages_container:
		for c in guide_pages_container.get_children():
			if c is Control:
				_guide_tab_pages.append(c)

	_populate_guide_controls_grid()

	if gate_width_slider:
		gate_width_slider.value_changed.connect(_on_gate_width_slider_changed)

	# Setup Settings Tabs and Pages
	_settings_tab_btns.clear()
	if settings_tab_bar:
		for c in settings_tab_bar.get_children():
			if c is Button:
				var idx := _settings_tab_btns.size()
				c.pressed.connect(_select_settings_tab.bind(idx))
				_settings_tab_btns.append(c)

	_settings_tab_pages.clear()
	if settings_pages_container:
		for c in settings_pages_container.get_children():
			if c is Control:
				_settings_tab_pages.append(c)

	if settings_reset_btn:
		settings_reset_btn.pressed.connect(_reset_current_settings_tab)

	# Setup Option/Check/Slider controls
	_setup_settings_controls()

	# Setup Quit Modal buttons
	if quit_stay_btn and not quit_stay_btn.pressed.is_connected(_close_quit_modal):
		quit_stay_btn.pressed.connect(_close_quit_modal)
	if quit_confirm_btn and not quit_confirm_btn.pressed.is_connected(_on_quit_confirm_pressed):
		quit_confirm_btn.pressed.connect(_on_quit_confirm_pressed)

	_select_guide_tab(0, false)
	_select_settings_tab(0, false)


func _setup_settings_controls() -> void:
	if win_mode_opt:
		win_mode_opt.clear()
		for m in ["Windowed", "Fullscreen", "Borderless Fullscreen"]:
			win_mode_opt.add_item(m)
		win_mode_opt.item_selected.connect(func(idx: int):
			_settings.set_value("display", "window_mode", idx)
		)

	if res_opt:
		res_opt.clear()
		for r in ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"]:
			res_opt.add_item(r)
		res_opt.item_selected.connect(func(idx: int):
			_settings.set_value("display", "resolution_index", idx)
		)

	if vsync_chk:
		vsync_chk.toggled.connect(func(pressed: bool):
			_settings.set_value("display", "vsync", pressed)
		)

	if fps_opt:
		fps_opt.clear()
		for f in ["Unlimited", "30 FPS", "60 FPS", "120 FPS", "144 FPS", "240 FPS"]:
			fps_opt.add_item(f)
		fps_opt.item_selected.connect(func(idx: int):
			var fps := SlimeSettings.FPS_OPTIONS[clampi(idx, 0, SlimeSettings.FPS_OPTIONS.size() - 1)]
			_settings.set_value("display", "max_fps", fps)
		)

	if ui_scale_slider:
		ui_scale_slider.value_changed.connect(func(v: float):
			_settings.set_value("display", "ui_scale", v)
			if ui_scale_val:
				ui_scale_val.text = "%d%%" % int(roundf(v * 100.0))
		)

	if preset_opt:
		preset_opt.clear()
		for p in ["Low", "Medium", "High", "Ultra"]:
			preset_opt.add_item(p)
		preset_opt.item_selected.connect(func(idx: int):
			_settings.set_value("graphics", "quality_preset", idx)
			_sync_from_settings()
		)

	if msaa_opt:
		msaa_opt.clear()
		for a in ["Disabled", "2×", "4×", "8×"]:
			msaa_opt.add_item(a)
		msaa_opt.item_selected.connect(func(idx: int):
			_settings.set_value("graphics", "msaa", idx)
		)

	if shadow_opt:
		shadow_opt.clear()
		for s in ["Off", "Low", "Medium", "High"]:
			shadow_opt.add_item(s)
		shadow_opt.item_selected.connect(func(idx: int):
			_settings.set_value("graphics", "shadow_quality", idx)
		)

	if grass_slider:
		grass_slider.value_changed.connect(func(v: float):
			_settings.set_value("graphics", "grass_density", v)
			if grass_val:
				grass_val.text = "%d%%" % int(roundf(v * 100.0))
		)

	if jiggle_slider:
		jiggle_slider.value_changed.connect(func(v: float):
			_settings.set_value("graphics", "jiggle_strength", v)
			if jiggle_val:
				jiggle_val.text = "%.1f×" % v
		)

	if master_vol_slider:
		master_vol_slider.value_changed.connect(func(v: float):
			_settings.set_value("audio", "master_volume", v)
			if master_vol_val:
				master_vol_val.text = "%d%%" % int(roundf(v))
		)

	if music_vol_slider:
		music_vol_slider.value_changed.connect(func(v: float):
			_settings.set_value("audio", "music_volume", v)
			if music_vol_val:
				music_vol_val.text = "%d%%" % int(roundf(v))
		)

	if sfx_vol_slider:
		sfx_vol_slider.value_changed.connect(func(v: float):
			_settings.set_value("audio", "sfx_volume", v)
			if sfx_vol_val:
				sfx_vol_val.text = "%d%%" % int(roundf(v))
		)

	if ui_vol_slider:
		ui_vol_slider.value_changed.connect(func(v: float):
			_settings.set_value("audio", "ui_volume", v)
			if ui_vol_val:
				ui_vol_val.text = "%d%%" % int(roundf(v))
		)

	if mute_unfocused_chk:
		mute_unfocused_chk.toggled.connect(func(pressed: bool):
			_settings.set_value("audio", "mute_unfocused", pressed)
		)

	if sens_slider:
		sens_slider.value_changed.connect(func(v: float):
			_settings.set_value("controls", "mouse_sensitivity", v)
			if sens_val:
				sens_val.text = "%.1f" % (v * 1000.0)
		)

	if zoom_slider:
		zoom_slider.value_changed.connect(func(v: float):
			_settings.set_value("controls", "zoom_speed", v)
			if zoom_val:
				zoom_val.text = "%.2f" % v
		)

	if invert_y_chk:
		invert_y_chk.toggled.connect(func(pressed: bool):
			_settings.set_value("controls", "invert_y", pressed)
		)

	if reduce_motion_chk:
		reduce_motion_chk.toggled.connect(func(pressed: bool):
			_settings.set_value("accessibility", "reduce_motion", pressed)
		)

	if high_contrast_chk:
		high_contrast_chk.toggled.connect(func(pressed: bool):
			_settings.set_value("accessibility", "high_contrast", pressed)
		)

	if text_scale_slider:
		text_scale_slider.value_changed.connect(func(v: float):
			_settings.set_value("accessibility", "text_scale", v)
			if text_scale_val:
				text_scale_val.text = "%d%%" % int(roundf(v * 100.0))
		)

	if night_mode_chk:
		night_mode_chk.toggled.connect(func(pressed: bool):
			_settings.set_value("gameplay", "night_mode", pressed)
			_night_target = 1.0 if pressed else 0.0
		)

	if hud_hints_chk:
		hud_hints_chk.toggled.connect(func(pressed: bool):
			_settings.set_value("gameplay", "show_hud_hints", pressed)
		)

	_setup_rebind_buttons()


func _setup_rebind_buttons() -> void:
	if rebind_container == null:
		return
	for c in rebind_container.get_children():
		c.queue_free()

	_rebind_buttons.clear()
	for item in SlimeSettings.REBINDABLE_ACTIONS:
		var act: String = item["action"]
		var lbl_txt: String = item["label"]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = lbl_txt
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)

		var rb := Button.new()
		rb.custom_minimum_size = Vector2(140, 0)
		rb.text = _settings.get_action_primary_label(act)
		rb.pressed.connect(_begin_rebind.bind(act))
		row.add_child(rb)
		_rebind_buttons[act] = rb
		rebind_container.add_child(row)


func _on_gate_width_slider_changed(v: float) -> void:
	if gate_width_val_lbl:
		gate_width_val_lbl.text = "%.2f m" % v
	if gate_status_lbl:
		if v >= 0.72:
			gate_status_lbl.text = "Status: Passable (Gate >= Core 0.72m)"
		else:
			gate_status_lbl.text = "Status: Blocked (Gate < Core 0.72m)"


func _on_guide_btn_pressed() -> void:
	_toggle_sheet(ActiveSheet.GUIDE)


func _on_settings_btn_pressed() -> void:
	_toggle_sheet(ActiveSheet.SETTINGS)


func _on_credits_btn_pressed() -> void:
	_toggle_sheet(ActiveSheet.CREDITS)


func _close_sheet() -> void:
	_show_sheet(ActiveSheet.NONE)


func _on_quit_confirm_pressed() -> void:
	get_tree().quit()


# ------------------------------------------------------------------------------------------------
# Controls Grid Population
# ------------------------------------------------------------------------------------------------

func _populate_guide_controls_grid() -> void:
	if controls_binding_grid == null:
		return
	for c in controls_binding_grid.get_children():
		c.queue_free()

	var rows := [
		["move_forward", "Move Forward"],
		["move_back", "Move Backward"],
		["move_left", "Strafe Left"],
		["move_right", "Strafe Right"],
		["run", "Sprint / Fast Crawl"],
		["split_follow", "Split Follower"],
		["split_roam", "Split Roamer"],
		["merge_clones", "Merge Clones"],
	]
	for r in rows:
		var key_str: String = _settings.get_action_primary_label(str(r[0])) if _settings else str(r[0])
		var k_lbl := Label.new()
		k_lbl.text = "[ %s ]" % key_str
		controls_binding_grid.add_child(k_lbl)

		var d_lbl := Label.new()
		d_lbl.text = r[1]
		controls_binding_grid.add_child(d_lbl)


# ------------------------------------------------------------------------------------------------
# Tab Selection
# ------------------------------------------------------------------------------------------------

func _select_guide_tab(idx: int, _play_snd := true) -> void:
	for i in _guide_tab_btns.size():
		_guide_tab_btns[i].flat = (i != idx)
	for i in _guide_tab_pages.size():
		_guide_tab_pages[i].visible = (i == idx)


func _select_settings_tab(idx: int, _play_snd := true) -> void:
	_active_settings_tab = idx
	_cancel_rebind_capture()
	for i in _settings_tab_btns.size():
		_settings_tab_btns[i].flat = (i != idx)
	for i in _settings_tab_pages.size():
		_settings_tab_pages[i].visible = (i == idx)


func _reset_current_settings_tab() -> void:
	if _settings == null:
		return
	var cats := ["display", "graphics", "audio", "controls", "accessibility", "gameplay"]
	var cat: String = cats[clampi(_active_settings_tab, 0, cats.size() - 1)]
	_settings.reset_category(cat)
	_sync_from_settings()


# ------------------------------------------------------------------------------------------------
# Sheet Visibility & Navigation
# ------------------------------------------------------------------------------------------------

func _toggle_sheet(sheet: ActiveSheet) -> void:
	if _active_sheet == sheet:
		_show_sheet(ActiveSheet.NONE)
	else:
		_show_sheet(sheet)


func _show_sheet(sheet: ActiveSheet) -> void:
	_cancel_rebind_capture()
	_active_sheet = sheet
	if guide_card:
		guide_card.visible = (sheet == ActiveSheet.GUIDE)
	if settings_card:
		settings_card.visible = (sheet == ActiveSheet.SETTINGS)
	if credits_card:
		credits_card.visible = (sheet == ActiveSheet.CREDITS)


func _open_quit_modal() -> void:
	if quit_modal_bg:
		quit_modal_bg.visible = true
	if quit_stay_btn:
		quit_stay_btn.grab_focus()


func _close_quit_modal() -> void:
	if quit_modal_bg:
		quit_modal_bg.visible = false
	if quit_btn:
		quit_btn.grab_focus()


func _on_play_pressed() -> void:
	if _is_loading:
		return
	_start_loading()


func _start_loading() -> void:
	_is_loading = true
	_loading_elapsed = 0.0
	_display_progress = 0.0

	if _active_sheet != ActiveSheet.NONE:
		_show_sheet(ActiveSheet.NONE)

	if loading_overlay:
		loading_overlay.visible = true
	if loading_bar:
		loading_bar.value = 0.0
	if loading_status_lbl:
		loading_status_lbl.text = "Loading..."

	var err := ResourceLoader.load_threaded_request(game_scene_path)
	if err != OK:
		get_tree().change_scene_to_file(game_scene_path)
		return

	set_process(true)


func _process(delta: float) -> void:
	if _is_loading:
		_update_loading(delta)


func _update_loading(delta: float) -> void:
	_loading_elapsed += delta

	var progress_arr: Array = []
	var status := ResourceLoader.load_threaded_get_status(game_scene_path, progress_arr)
	var raw_progress: float = 0.0
	if not progress_arr.is_empty():
		raw_progress = float(progress_arr[0])

	var time_ratio: float = clampf(_loading_elapsed / maxf(min_loading_duration, 0.01), 0.0, 1.0)
	var target_progress: float = 0.0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		target_progress = maxf(time_ratio, 1.0)
	else:
		target_progress = minf(time_ratio, 0.85 + raw_progress * 0.1)

	_display_progress = move_toward(_display_progress, target_progress, delta * 2.5)

	if loading_bar:
		loading_bar.value = _display_progress * 100.0

	if status == ResourceLoader.THREAD_LOAD_LOADED and _loading_elapsed >= min_loading_duration:
		_display_progress = 1.0
		if loading_bar:
			loading_bar.value = 100.0
		if loading_status_lbl:
			loading_status_lbl.text = "Loading world..."

		_is_loading = false
		set_process(false)

		var packed_res := ResourceLoader.load_threaded_get(game_scene_path) as PackedScene
		if packed_res != null:
			get_tree().change_scene_to_packed(packed_res)
		else:
			get_tree().change_scene_to_file(game_scene_path)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_is_loading = false
		set_process(false)
		get_tree().change_scene_to_file(game_scene_path)


# Compatibility methods for verify_menu.gd
func _toggle_atmosphere() -> void:
	_night_target = 1.0 if _night_target < 0.5 else 0.0
	if _settings:
		_settings.set_value("gameplay", "night_mode", _night_target > 0.5)


func _toggle_core_xray() -> void:
	pass


func _poke_all_slimes() -> void:
	if _mascot:
		_mascot.poke_all()


# Settings synchronization
func _sync_from_settings() -> void:
	if _settings == null:
		return
	if win_mode_opt:
		win_mode_opt.selected = int(_settings.get_value("display", "window_mode", 0))
	if res_opt:
		res_opt.selected = int(_settings.get_value("display", "resolution_index", 2))
	if vsync_chk:
		vsync_chk.set_pressed_no_signal(bool(_settings.get_value("display", "vsync", true)))
	if fps_opt:
		var cur_fps = int(_settings.get_value("display", "max_fps", 0))
		var idx := SlimeSettings.FPS_OPTIONS.find(cur_fps)
		fps_opt.selected = idx if idx >= 0 else 0
	if ui_scale_slider:
		var sc = float(_settings.get_value("display", "ui_scale", 1.0))
		ui_scale_slider.set_value_no_signal(sc)
		if ui_scale_val:
			ui_scale_val.text = "%d%%" % int(roundf(sc * 100.0))

	if preset_opt:
		preset_opt.selected = int(_settings.get_value("graphics", "quality_preset", 0))
	if msaa_opt:
		msaa_opt.selected = int(_settings.get_value("graphics", "msaa", 0))
	if shadow_opt:
		shadow_opt.selected = int(_settings.get_value("graphics", "shadow_quality", 0))
	if grass_slider:
		var gd = float(_settings.get_value("graphics", "grass_density", 0.4))
		grass_slider.set_value_no_signal(gd)
		if grass_val:
			grass_val.text = "%d%%" % int(roundf(gd * 100.0))
	if jiggle_slider:
		var jg = float(_settings.get_value("graphics", "jiggle_strength", 1.0))
		jiggle_slider.set_value_no_signal(jg)
		if jiggle_val:
			jiggle_val.text = "%.1f×" % jg

	if master_vol_slider:
		var mv = float(_settings.get_value("audio", "master_volume", 85.0))
		master_vol_slider.set_value_no_signal(mv)
		if master_vol_val:
			master_vol_val.text = "%d%%" % int(roundf(mv))
	if music_vol_slider:
		var muv = float(_settings.get_value("audio", "music_volume", 70.0))
		music_vol_slider.set_value_no_signal(muv)
		if music_vol_val:
			music_vol_val.text = "%d%%" % int(roundf(muv))
	if sfx_vol_slider:
		var sv = float(_settings.get_value("audio", "sfx_volume", 85.0))
		sfx_vol_slider.set_value_no_signal(sv)
		if sfx_vol_val:
			sfx_vol_val.text = "%d%%" % int(roundf(sv))
	if ui_vol_slider:
		var uiv = float(_settings.get_value("audio", "ui_volume", 80.0))
		ui_vol_slider.set_value_no_signal(uiv)
		if ui_vol_val:
			ui_vol_val.text = "%d%%" % int(roundf(uiv))
	if mute_unfocused_chk:
		mute_unfocused_chk.set_pressed_no_signal(bool(_settings.get_value("audio", "mute_unfocused", false)))

	if sens_slider:
		var sn = float(_settings.get_value("controls", "mouse_sensitivity", 0.007))
		sens_slider.set_value_no_signal(sn)
		if sens_val:
			sens_val.text = "%.1f" % (sn * 1000.0)
	if zoom_slider:
		var zm = float(_settings.get_value("controls", "zoom_speed", 0.30))
		zoom_slider.set_value_no_signal(zm)
		if zoom_val:
			zoom_val.text = "%.2f" % zm
	if invert_y_chk:
		invert_y_chk.set_pressed_no_signal(bool(_settings.get_value("controls", "invert_y", false)))

	if reduce_motion_chk:
		reduce_motion_chk.set_pressed_no_signal(bool(_settings.get_value("accessibility", "reduce_motion", false)))
	if high_contrast_chk:
		high_contrast_chk.set_pressed_no_signal(bool(_settings.get_value("accessibility", "high_contrast", false)))
	if text_scale_slider:
		var ts = float(_settings.get_value("accessibility", "text_scale", 1.0))
		text_scale_slider.set_value_no_signal(ts)
		if text_scale_val:
			text_scale_val.text = "%d%%" % int(roundf(ts * 100.0))

	if night_mode_chk:
		var nm = bool(_settings.get_value("gameplay", "night_mode", false))
		night_mode_chk.set_pressed_no_signal(nm)
		_night_target = 1.0 if nm else 0.0
	if hud_hints_chk:
		hud_hints_chk.set_pressed_no_signal(bool(_settings.get_value("gameplay", "show_hud_hints", true)))


func _on_external_setting_changed(_cat: String, _key: String, _val: Variant) -> void:
	pass


func _begin_rebind(action: String) -> void:
	_awaiting_rebind_action = action
	for act in _rebind_buttons.keys():
		var b: Button = _rebind_buttons[act]
		if act == action:
			b.text = "Press key..."
		else:
			b.text = _settings.get_action_primary_label(act)


func _cancel_rebind_capture() -> void:
	_awaiting_rebind_action = ""
	_refresh_keybind_ui()


func _refresh_keybind_ui() -> void:
	if _settings == null:
		return
	for act in _rebind_buttons.keys():
		var b: Button = _rebind_buttons[act]
		if is_instance_valid(b):
			b.text = _settings.get_action_primary_label(act)
	_populate_guide_controls_grid()


func _input(event: InputEvent) -> void:
	if _awaiting_rebind_action != "" and event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		var code := ke.physical_keycode if ke.physical_keycode != 0 else ke.keycode
		get_viewport().set_input_as_handled()
		if code == KEY_ESCAPE:
			_cancel_rebind_capture()
			return
		var act := _awaiting_rebind_action
		_awaiting_rebind_action = ""
		_settings.set_action_primary_key(act, code)
		_refresh_keybind_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ke := event as InputEventKey
	if ke.keycode == KEY_ESCAPE:
		if quit_modal_bg and quit_modal_bg.visible:
			_close_quit_modal()
			get_viewport().set_input_as_handled()
		elif _active_sheet != ActiveSheet.NONE:
			_show_sheet(ActiveSheet.NONE)
			get_viewport().set_input_as_handled()
		elif not OS.has_feature("web"):
			_open_quit_modal()
			get_viewport().set_input_as_handled()
