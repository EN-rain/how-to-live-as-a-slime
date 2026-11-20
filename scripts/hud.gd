class_name SlimeHud
extends Control
## HUD display for eaten stats, mass/volume, clone count, active status, and controls hints.

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
const CaveLayout = preload("res://tools/cave_layout.gd")

@export var slime: Slime
@export var props: SlimeProps
@export var hint_text := "WASD move · Space jump (hold) · Shift run · E split · Q roam · M merge · T time · Y weather · F4 dev · Esc menu/teleport"
@export var debug_posture := false

@export_group("Pill Styling")
@export var stat_color: Color = Color("eaf4fb")
@export var hint_color: Color = Color("bcd3e4")
@export var debug_color: Color = Color("a6f0c4")
@export var dev_color: Color = Color("ffd97d")
@export var pill_bg_color: Color = Color(16.0 / 255.0, 32.0 / 255.0, 48.0 / 255.0, 0.55)
@export var pill_corner_radius: int = 999
@export var pill_font_size: int = 12
@export var hud_padding_left: float = 12.0
@export var hud_padding_top: float = 12.0
@export var h_separation: int = 10
@export var v_separation: int = 6

var _stat: Label
var _perf_line: Label
var _perf_pill: PanelContainer
var _env_line: Label
var _env_pill: PanelContainer
var _hint: Label
var _dev_line: Label
var _dev_pill: PanelContainer
var _debug_line: Label
var _debug_pill: PanelContainer
var _toast_line: Label
var _toast_pill: PanelContainer
var _toast_timer: float = 0.0
var _last := ""
var _last_env := ""
var _last_dev := ""
var _last_dbg := ""
var _time_weather: Node
var _terrain_node: Node

var _perf_accum_dt: float = 0.0
var _perf_accum_frames: int = 0
var _perf_cpu_ms_smooth: float = 0.0
var _perf_dt_ms_smooth: float = 16.67

var _dark_overlay: ColorRect
var _dark_alpha: float = 0.0
var _death_backdrop: Control
var _death_title_label: Label
var _death_reason_label: Label
var _btn_new_game: Button
var _btn_retry: Button
var _btn_exit: Button

const DBG_RING_SIZE := 300
var _frames_ms := PackedFloat32Array()
var _phys_ms := PackedFloat32Array()
var _ring_head: int = 0
var _ring_count: int = 0
var _ring_sort_buf: Array[float] = []
var _stat_accum_dt: float = 0.2
var _stat_last_eaten: int = -1
var _stat_last_clones: int = -1
var _prev_pframe := 0
## [rebuild, baked_points, set_points, cast, intersect, rest] totals at the last sample.
var _prev_counts: Array = [0, 0, 0, 0, 0, 0]
var _rates: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

var _dbg_mesh: MeshInstance3D
var _dbg_im: ImmediateMesh

var _menu_btn: Button
var _menu_backdrop: ColorRect
var _menu_open: bool = false
var _tab_tp_btn: Button
var _tab_set_btn: Button
var _tab_tp_page: Control
var _tab_set_page: Control
var _quality_btns: Array[Button] = []
var _time_btns: Dictionary = {}
var _weather_btns: Dictionary = {}
var _master_slider: HSlider
var _master_val_lbl: Label
var _sfx_slider: HSlider
var _sfx_val_lbl: Label
var _sens_slider: HSlider
var _sens_val_lbl: Label
var _invert_y_chk: CheckButton
var _dev_chk: CheckButton
var _fly_chk: CheckButton
var _noclip_chk: CheckButton
var _dev_panel_status_lbl: Label
var _syncing_menu_controls: bool = false


func _ready() -> void:
	add_to_group("hud")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("h_separation", h_separation)
	row.add_theme_constant_override("v_separation", v_separation)
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = hud_padding_left
	row.offset_top = hud_padding_top
	row.offset_right = -hud_padding_left
	add_child(row)

	_stat = _make_pill(stat_color)
	row.add_child(_stat.get_parent())

	_perf_line = _make_pill(Color("a6f0c4"))
	_perf_line.text = "FPS --  ·  CPU --%"
	_perf_pill = _perf_line.get_parent()
	row.add_child(_perf_pill)

	_env_line = _make_pill(Color("f4dca4"))
	_env_line.text = "10:05 Day · Clear"
	_env_pill = _env_line.get_parent()
	row.add_child(_env_pill)

	_hint = _make_pill(hint_color)
	_hint.text = hint_text
	_hint.get_parent().visible = false
	row.add_child(_hint.get_parent())

	_menu_btn = _make_menu_pill_button("Menu · Teleport (Esc)")
	_menu_btn.pressed.connect(func(): _set_menu_open(not _menu_open))
	_menu_btn.visible = false
	row.add_child(_menu_btn)

	_dev_line = _make_pill(dev_color)
	_dev_pill = _dev_line.get_parent()
	_dev_pill.visible = false
	row.add_child(_dev_pill)

	_debug_line = _make_pill(debug_color)
	_debug_pill = _debug_line.get_parent()
	_debug_pill.visible = debug_posture
	row.add_child(_debug_pill)

	_toast_line = _make_pill(Color(0.62, 0.96, 1.0))
	_toast_pill = _toast_line.get_parent()
	_toast_pill.visible = false
	row.add_child(_toast_pill)

	_build_death_ui()
	_build_pause_menu_ui()
	if slime != null and is_instance_valid(slime) and slime.has_signal("died"):
		if not slime.died.is_connected(_on_slime_died):
			slime.died.connect(_on_slime_died)

	_prev_pframe = Engine.get_physics_frames()
	call_deferred("_ensure_debug_mesh")


func _on_slime_died(_reason: String) -> void:
	_sync_death_ui(1.0)


func _sync_death_ui(dt: float = 0.016) -> void:
	if slime == null or not is_instance_valid(slime):
		return
	var target_dark := 1.0 if slime.is_dead else clampf(slime.sea_darkness, 0.0, 1.0)
	if slime.is_dead:
		_dark_alpha = 1.0
	else:
		_dark_alpha = lerpf(_dark_alpha, target_dark, 1.0 - exp(-14.0 * clampf(dt, 0.0, 0.1)))
		if _dark_alpha < 0.004 and target_dark <= 0.0:
			_dark_alpha = 0.0
	if _dark_overlay != null:
		_dark_overlay.visible = _dark_alpha > 0.002
		_dark_overlay.color = Color(0.0, 0.0, 0.0, _dark_alpha)
	if _death_backdrop != null:
		var want_panel := slime.is_dead
		if _death_backdrop.visible != want_panel:
			_death_backdrop.visible = want_panel
			if want_panel and _death_reason_label != null:
				_death_reason_label.text = slime.death_reason if slime.death_reason != "" else "You were killed by an unknown creature"
				if _btn_retry != null and is_inside_tree():
					_btn_retry.grab_focus()


func _make_death_button(label_text: String, primary: bool = false) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(126.0, 42.0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color("f4f7fb"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	var make_style := func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		return sb

	var base_bg := Color(0.56, 0.14, 0.18, 0.92) if primary else Color(0.12, 0.14, 0.19, 0.90)
	var base_bd := Color(0.95, 0.42, 0.46, 0.78) if primary else Color(0.42, 0.48, 0.58, 0.45)
	var hover_bg := Color(0.70, 0.18, 0.23, 0.96) if primary else Color(0.20, 0.24, 0.32, 0.95)
	var hover_bd := Color(1.0, 0.58, 0.60, 0.92) if primary else Color(0.68, 0.78, 0.90, 0.75)
	var press_bg := Color(0.44, 0.10, 0.14, 1.0) if primary else Color(0.08, 0.10, 0.14, 1.0)

	btn.add_theme_stylebox_override("normal", make_style.call(base_bg, base_bd))
	btn.add_theme_stylebox_override("hover", make_style.call(hover_bg, hover_bd))
	btn.add_theme_stylebox_override("focus", make_style.call(hover_bg, hover_bd))
	btn.add_theme_stylebox_override("pressed", make_style.call(press_bg, hover_bd))
	return btn


func _build_death_ui() -> void:
	_dark_overlay = ColorRect.new()
	_dark_overlay.name = "SeaDarknessOverlay"
	_dark_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_dark_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark_overlay.visible = false
	add_child(_dark_overlay)

	var death_ps := load("res://ui/death_overlay.tscn") as PackedScene
	if death_ps != null:
		var center := death_ps.instantiate() as CenterContainer
		center.visible = false
		add_child(center)
		_death_backdrop = center
		_death_title_label = center.get_node_or_null("DeathCard/VBox/TitleLabel") as Label
		_death_reason_label = center.get_node_or_null("DeathCard/VBox/ReasonLabel") as Label
		_btn_new_game = center.get_node_or_null("DeathCard/VBox/ButtonsRow/BtnNewGame") as Button
		_btn_retry = center.get_node_or_null("DeathCard/VBox/ButtonsRow/BtnRetry") as Button
		_btn_exit = center.get_node_or_null("DeathCard/VBox/ButtonsRow/BtnExit") as Button
		if _btn_new_game != null:
			_btn_new_game.pressed.connect(_on_new_game_pressed)
		if _btn_retry != null:
			_btn_retry.pressed.connect(_on_retry_pressed)
		if _btn_exit != null:
			_btn_exit.pressed.connect(_on_exit_pressed)
		return

	var center := CenterContainer.new()
	center.name = "DeathPanelBackdrop"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	center.visible = false
	add_child(center)
	_death_backdrop = center

	var card := PanelContainer.new()
	card.name = "DeathCard"
	card.custom_minimum_size = Vector2(460.0, 0.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.055, 0.045, 0.065, 0.94)
	card_style.border_color = Color(0.86, 0.22, 0.26, 0.58)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(18)
	card_style.content_margin_left = 34.0
	card_style.content_margin_right = 34.0
	card_style.content_margin_top = 28.0
	card_style.content_margin_bottom = 26.0
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	card_style.shadow_size = 24
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	_death_title_label = Label.new()
	_death_title_label.text = "YOU DIED"
	_death_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_title_label.add_theme_font_size_override("font_size", 28)
	_death_title_label.add_theme_color_override("font_color", Color(0.98, 0.36, 0.38))
	vbox.add_child(_death_title_label)

	_death_reason_label = Label.new()
	_death_reason_label.text = "You were killed by an unknown creature"
	_death_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_death_reason_label.add_theme_font_size_override("font_size", 17)
	_death_reason_label.add_theme_color_override("font_color", Color(0.91, 0.93, 0.96))
	vbox.add_child(_death_reason_label)

	var sep := HSeparator.new()
	sep.modulate = Color(1.0, 0.45, 0.45, 0.35)
	vbox.add_child(sep)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)

	_btn_new_game = _make_death_button("New Game", false)
	_btn_new_game.name = "BtnNewGame"
	_btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_row.add_child(_btn_new_game)

	_btn_retry = _make_death_button("Retry", true)
	_btn_retry.name = "BtnRetry"
	_btn_retry.pressed.connect(_on_retry_pressed)
	btn_row.add_child(_btn_retry)

	_btn_exit = _make_death_button("Exit", false)
	_btn_exit.name = "BtnExit"
	_btn_exit.pressed.connect(_on_exit_pressed)
	btn_row.add_child(_btn_exit)


func _on_new_game_pressed() -> void:
	if get_tree() != null:
		get_tree().reload_current_scene()


func _on_retry_pressed() -> void:
	if slime != null and is_instance_valid(slime) and slime.has_method("revive_at_safe_pos"):
		slime.revive_at_safe_pos()
	_dark_alpha = 0.0
	if _dark_overlay != null:
		_dark_overlay.color.a = 0.0
		_dark_overlay.visible = false
	if _death_backdrop != null:
		_death_backdrop.visible = false


func _on_exit_pressed() -> void:
	if get_tree() == null:
		return
	if FileAccess.file_exists("res://main_menu/main_menu.tscn"):
		get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")
	else:
		get_tree().quit()


func _update_perf_indicator(delta: float) -> void:
	if _perf_line == null:
		return
	var dt := maxf(delta, 0.0001)
	# Ignore one-frame screenshot / loading stalls (> 0.10s) so smoothed CPU time stays accurate.
	if dt <= 0.10:
		var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var sim_cpu_ms := proc_ms + phys_ms
		var frame_ms := maxf(dt * 1000.0, 1.0)
		var smooth_a := 1.0 - exp(-6.0 * dt)
		_perf_cpu_ms_smooth = lerpf(_perf_cpu_ms_smooth, sim_cpu_ms, smooth_a) if _perf_cpu_ms_smooth > 0.0 else sim_cpu_ms
		_perf_dt_ms_smooth = lerpf(_perf_dt_ms_smooth, frame_ms, smooth_a)

	_perf_accum_dt += minf(dt, 0.10)
	_perf_accum_frames += 1
	if _perf_accum_dt < 0.25:
		return

	var eng_fps := Engine.get_frames_per_second()
	var inst_fps := roundi(eng_fps if eng_fps > 0.5 else float(_perf_accum_frames) / maxf(_perf_accum_dt, 0.001))
	var cpu_pct := clampf((_perf_cpu_ms_smooth / maxf(_perf_dt_ms_smooth, 1.0)) * 100.0, 0.0, 100.0)
	_perf_accum_dt = 0.0
	_perf_accum_frames = 0

	_perf_line.text = "FPS %d  ·  CPU %.0f%% (%.1f ms)" % [inst_fps, cpu_pct, _perf_cpu_ms_smooth]
	var c := Color("a6f0c4")
	if inst_fps < 30:
		c = Color("ff8a8a")
	elif inst_fps < 50:
		c = Color("ffd97d")
	_perf_line.add_theme_color_override("font_color", c)


func show_toast(msg: String, color: Color = Color(0.62, 0.96, 1.0), duration: float = 3.5) -> void:
	if _toast_line == null or _toast_pill == null:
		return
	_toast_line.text = msg
	_toast_line.add_theme_color_override("font_color", color)
	_toast_pill.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_toast_pill.visible = true
	_toast_timer = maxf(duration, 0.25)


func _make_pill(font_color: Color) -> Label:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	box.content_margin_left = 4.0
	box.content_margin_right = 8.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override("panel", box)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", pill_font_size + 1)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(label)
	return label


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F3:
		debug_posture = not debug_posture
		_debug_pill.visible = debug_posture
		_stat_accum_dt = 0.2
		if not debug_posture and _dbg_im != null:
			_dbg_im.clear_surfaces()
		elif debug_posture:
			_ring_head = 0
			_ring_count = 0
			_prev_pframe = Engine.get_physics_frames()
			_ensure_debug_mesh()
		accept_event()
	elif event.keycode == KEY_ESCAPE:
		accept_event()
		if slime != null and is_instance_valid(slime) and slime.is_dead:
			return
		_set_menu_open(not _menu_open)
	elif event.keycode == KEY_F5:
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_quality_preset(0)
			accept_event()
	elif event.keycode == KEY_F6:
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_quality_preset(1)
			accept_event()
	elif event.keycode == KEY_F7:
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_quality_preset(2)
			accept_event()
	elif event.keycode == KEY_F8:
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_quality_preset(3)
			accept_event()
	elif event.keycode == KEY_F10:
		var s := SlimeSettings.get_or_create()
		if s:
			s.cycle_quality_preset()
			accept_event()


func set_hint_visible(is_visible: bool) -> void:
	if _hint and _hint.get_parent():
		_hint.get_parent().visible = is_visible


func _ensure_debug_mesh() -> void:
	if _dbg_mesh != null and is_instance_valid(_dbg_mesh):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	_dbg_mesh = MeshInstance3D.new()
	_dbg_mesh.name = "SlimeDebugWire"
	_dbg_mesh.top_level = true
	_dbg_mesh.global_transform = Transform3D.IDENTITY
	_dbg_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dbg_im = ImmediateMesh.new()
	_dbg_mesh.mesh = _dbg_im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.28, 0.95, 0.6, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_dbg_mesh.material_override = mat
	scene.add_child(_dbg_mesh)


func _sample(delta: float) -> void:
	if not debug_posture:
		return
	if _frames_ms.size() != DBG_RING_SIZE:
		_frames_ms.resize(DBG_RING_SIZE)
		_phys_ms.resize(DBG_RING_SIZE)
	_frames_ms[_ring_head] = delta * 1000.0
	_phys_ms[_ring_head] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_ring_head = (_ring_head + 1) % DBG_RING_SIZE
	if _ring_count < DBG_RING_SIZE:
		_ring_count += 1
	var pf := Engine.get_physics_frames()
	var df := pf - _prev_pframe
	if df > 0:
		_prev_pframe = pf
		var now: Array = [
			SlimeShapeModel.debug_rebuild_count,
			SlimeShapeModel.debug_baked_points_count,
			SlimeMotor.debug_set_points_count,
			SlimeMotor.debug_cast_count,
			SlimeMotor.debug_intersect_count,
			SlimeMotor.debug_rest_count,
		]
		for i in 6:
			_rates[i] = float(now[i] - _prev_counts[i]) / float(df)
			_prev_counts[i] = now[i]


func _percentile(arr: PackedFloat32Array, q: float) -> float:
	if _ring_count <= 0:
		return 0.0
	_ring_sort_buf.resize(_ring_count)
	for i in _ring_count:
		_ring_sort_buf[i] = arr[i]
	_ring_sort_buf.sort()
	var idx := clampi(int(roundf(q * float(_ring_count - 1))), 0, _ring_count - 1)
	return _ring_sort_buf[idx]


func _update_debug_overlay() -> void:
	if not debug_posture:
		return
	_draw_debug_3d()
	var passage := "OPEN"
	if slime != null and not slime._passage_session.is_empty():
		passage = "LATCHED"
	var txt := "frame p50 %.1f p95 %.1f p99 %.1f ms · phys p50 %.1f p95 %.1f p99 %.1f ms\nset %d cast %d int %d rest %d bake %d rebuild %d /tick · clones %d · objs %d · %s · sq %.2f liq %.2f h %.2f" % [
		_percentile(_frames_ms, 0.5), _percentile(_frames_ms, 0.95), _percentile(_frames_ms, 0.99),
		_percentile(_phys_ms, 0.5), _percentile(_phys_ms, 0.95), _percentile(_phys_ms, 0.99),
		int(roundf(_rates[2])), int(roundf(_rates[3])), int(roundf(_rates[4])), int(roundf(_rates[5])),
		int(roundf(_rates[1])), int(roundf(_rates[0])),
		maxi(0, props.registered_slimes.size() - 1), Performance.get_monitor(Performance.OBJECT_COUNT),
		passage, slime.squeeze_k, slime.liquid_amt, slime.height_ratio]
	if txt != _last_dbg:
		_last_dbg = txt
		_debug_line.text = txt


func _draw_debug_3d() -> void:
	if _dbg_im == null or props == null:
		return
	_dbg_im.clear_surfaces()
	_dbg_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for s in props.registered_slimes:
		if not is_instance_valid(s) or s.model == null:
			continue
		var foot: Vector3 = s.model.foot
		var pts: PackedVector3Array = s.model.resolved_points()
		var segs := SlimeShapeModel.PROFILE_SEGMENTS
		var rings := SlimeShapeModel.PROFILE_RINGS
		if pts.size() != segs * rings:
			continue
		for r in rings:
			for i in segs:
				_dbg_im.surface_add_vertex(foot + pts[r * segs + i])
				_dbg_im.surface_add_vertex(foot + pts[r * segs + (i + 1) % segs])
		for i in range(0, segs, 6):
			for r in range(rings - 1):
				_dbg_im.surface_add_vertex(foot + pts[r * segs + i])
				_dbg_im.surface_add_vertex(foot + pts[(r + 1) * segs + i])
		var ax: Vector3 = s.model.axis
		_dbg_im.surface_add_vertex(foot + Vector3(0.0, 0.02, 0.0))
		_dbg_im.surface_add_vertex(foot + Vector3(ax.x, 0.02, ax.z) * s.model.semi_a * 1.15)

		# Inner invisible core sphere debug wireframe
		var cc: Vector3 = s.model.core_sphere_center()
		var cr: float = s.model.core_sphere_radius()
		for a in 16:
			var th0 := float(a) * TAU / 16.0
			var th1 := float(a + 1) * TAU / 16.0
			# Horizontal ring
			_dbg_im.surface_add_vertex(cc + Vector3(cos(th0) * cr, 0.0, sin(th0) * cr))
			_dbg_im.surface_add_vertex(cc + Vector3(cos(th1) * cr, 0.0, sin(th1) * cr))
			# Vertical ring
			_dbg_im.surface_add_vertex(cc + Vector3(cos(th0) * cr, sin(th0) * cr, 0.0))
			_dbg_im.surface_add_vertex(cc + Vector3(cos(th1) * cr, sin(th1) * cr, 0.0))
		if not s._passage.is_empty():
			var c: Vector3 = s._passage.get("center", Vector3.ZERO)
			var flow: Vector3 = s._passage.get("flow", Vector3.ZERO)
			var half: float = s._passage.get("half_length", 0.0)
			var yy := foot.y + 0.03
			_dbg_im.surface_add_vertex(Vector3(c.x, yy, c.z) - flow * half)
			_dbg_im.surface_add_vertex(Vector3(c.x, yy, c.z) + flow * half)
	_dbg_im.surface_end()


func _process(_delta: float) -> void:
	_sample(_delta)
	_update_perf_indicator(_delta)
	if _toast_timer > 0.0 and _toast_pill != null:
		_toast_timer -= _delta
		if _toast_timer <= 0.0:
			_toast_pill.visible = false
		elif _toast_timer < 0.75:
			_toast_pill.modulate = Color(1.0, 1.0, 1.0, clampf(_toast_timer / 0.75, 0.0, 1.0))

	if slime != null and is_instance_valid(slime):
		if slime.has_signal("died") and not slime.died.is_connected(_on_slime_died):
			slime.died.connect(_on_slime_died)
		_sync_death_ui(_delta)

	if slime == null or props == null:
		return

	# Authoritative volume and mass calculations (throttled to 10 Hz unless count/state changes)
	var clone_count := maxi(0, props.registered_slimes.size() - 1)
	_stat_accum_dt += _delta
	var force_stat := (props.eaten != _stat_last_eaten) or (clone_count != _stat_last_clones) or (not slime.pressing_props.is_empty())
	if force_stat or _stat_accum_dt >= 0.10:
		_stat_accum_dt = 0.0
		_stat_last_eaten = props.eaten
		_stat_last_clones = clone_count
		var mass := slime.get_volume()
		var text := ""
		if props.total() > 0:
			text = "Eaten %d / %d  ·  Vol %.1f m³ (Scale %.2f×)" % [props.eaten, props.total(), mass, slime.target_scale]
		else:
			text = "Vol %.1f m³ (Scale %.2f×)" % [mass, slime.target_scale]
		if clone_count > 0:
			text += "  ·  Clones: %d" % clone_count
		var pos := slime.global_position
		text += "  ·  Pos %.1f, %.1f, %.1f" % [pos.x, pos.y, pos.z]

		# Check active push-eating engulf front progress
		var active_engulf_p = null
		for p in slime.pressing_props:
			if p != null and p.last_presser == slime and p.engulf_front > 0.01:
				active_engulf_p = p
				break

		if active_engulf_p != null:
			var s_vol: float = slime.get_volume()
			var vr: float = active_engulf_p.real_volume / maxf(1e-4, s_vol)
			if vr >= 0.75:
				text += "  ·  Engulfing %d%% [Heavy Resistance]" % int(active_engulf_p.engulf_front * 100.0)
			elif vr >= 0.45:
				text += "  ·  Engulfing %d%% [Resisting]" % int(active_engulf_p.engulf_front * 100.0)
			else:
				text += "  ·  Engulfing %d%%" % int(active_engulf_p.engulf_front * 100.0)

		if debug_posture and slime.model != null:
			text += "  ·  h %.2f  sq %.2f  liq %.2f" % [slime.height_ratio, slime.squeeze_k, slime.liquid_amt]
			if slime.expansion_blocked != "":
				text += "  ·  %s" % slime.expansion_blocked

		if text != _last:
			_last = text
			_stat.text = text

		if _time_weather == null or not is_instance_valid(_time_weather):
			_time_weather = get_tree().get_first_node_in_group("world_time_weather")
		if _time_weather != null and _env_line != null:
			var over_h := slime.global_position.y + 4.0
			if _terrain_node == null or not is_instance_valid(_terrain_node):
				_terrain_node = get_tree().get_first_node_in_group("terrain")
				if _terrain_node == null and get_tree().current_scene != null:
					_terrain_node = get_tree().current_scene.get_node_or_null("TerrainScene")
			if _terrain_node != null and _terrain_node.has_method("sample_height"):
				over_h = float(_terrain_node.sample_height(slime.global_position.x, slime.global_position.z))
			var web_c := WorldLandmarks.SPIDER_FOREST_CENTER
			if _terrain_node != null and _terrain_node.has_method("get_webwood_center"):
				web_c = _terrain_node.call("get_webwood_center")
			var zone_label := WorldLandmarks.describe_zone(slime.global_position, over_h, web_c)
			var env_txt := "%s %s · %s" % [
				_time_weather.get_hour_minute_string(),
				_time_weather.get_phase_label(),
				_time_weather.get_weather_label(),
			]
			if zone_label != "":
				env_txt += "  |  " + zone_label
			if env_txt != _last_env:
				_last_env = env_txt
				_env_line.text = env_txt

	if _dev_pill != null:
		_dev_pill.visible = false
	var dev_txt := "DEV %s · FLY %s (V) · NOCLIP %s (N) · SPEED %.0f m/s ([ / ] or Alt+Wheel · Shift ×2.5 · F4 toggle)" % [
		"ON" if slime.dev_mode else "OFF",
		"ON" if slime.dev_fly else "OFF",
		"ON" if slime.dev_noclip else "OFF",
		slime.dev_speed,
	]
	if dev_txt != _last_dev:
		_last_dev = dev_txt
		if _dev_line != null:
			_dev_line.text = dev_txt
		if _dev_panel_status_lbl != null:
			_dev_panel_status_lbl.text = dev_txt
		if _menu_open:
			_sync_menu_controls()

	_update_debug_overlay()


# ==============================================================================
# IN-GAME TELEPORT & SETTINGS PANEL (ESC / TOP-RIGHT MENU PILL)
# ==============================================================================

func is_menu_open() -> bool:
	return _menu_open and _menu_backdrop != null and _menu_backdrop.visible


func open_menu(tab: String = "teleport") -> void:
	_set_menu_open(true, tab)


func close_menu() -> void:
	_set_menu_open(false)


func _set_menu_open(open: bool, tab: String = "") -> void:
	if open and slime != null and is_instance_valid(slime) and slime.is_dead:
		return
	_menu_open = open
	if _menu_backdrop != null:
		_menu_backdrop.visible = open
	if open:
		if not tab.is_empty():
			_switch_menu_tab(tab)
		_sync_menu_controls()


func _switch_menu_tab(tab: String) -> void:
	var show_tp := (tab != "settings")
	if _tab_tp_page != null:
		_tab_tp_page.visible = show_tp
	if _tab_set_page != null:
		_tab_set_page.visible = not show_tp
	if _tab_tp_btn != null:
		_tab_tp_btn.button_pressed = show_tp
	if _tab_set_btn != null:
		_tab_set_btn.button_pressed = not show_tp


func get_teleport_destinations() -> Array[Dictionary]:
	if (_terrain_node == null or not is_instance_valid(_terrain_node)) and is_inside_tree():
		_terrain_node = get_tree().get_first_node_in_group("terrain")
		if _terrain_node == null and get_tree().current_scene != null:
			_terrain_node = get_tree().current_scene.get_node_or_null("TerrainScene")
	var dock_xz := Vector2(670.0, 2447.0)
	if _terrain_node != null and is_instance_valid(_terrain_node):
		var v_node := _terrain_node.get_node_or_null("Village")
		if v_node != null and v_node.has_meta("dock_shore_xy"):
			var meta_v: Variant = v_node.get_meta("dock_shore_xy")
			if meta_v is Vector2:
				dock_xz = meta_v as Vector2

	var web_c := WorldLandmarks.SPIDER_FOREST_CENTER
	if _terrain_node != null and _terrain_node.has_method("get_webwood_center"):
		web_c = _terrain_node.call("get_webwood_center") as Vector2

	var skel_in := WorldLandmarks.skel_dungeon_vestibule_spawn
	return [
		{
			"name": "Spawn Meadow",
			"subtitle": "Surface Starting Glade",
			"group": "Villages & Landmarks",
			"xz": Vector2(0.0, 10.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Forest Wildlife Glade",
			"subtitle": "Roaming Deer, Stags, Foxes & Wild Horses",
			"group": "Villages & Landmarks",
			"xz": Vector2(-62.0, 54.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Slimebrook Village Plaza",
			"subtitle": "Walled Market Town",
			"group": "Villages & Landmarks",
			"xz": Vector2(590.0, 2200.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Slimebrook Fishing Harbor",
			"subtitle": "Southern Coastal Pier",
			"group": "Villages & Landmarks",
			"xz": dock_xz,
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Crystal Cave Entrance",
			"subtitle": "Glittering Sinkhole Rim",
			"group": "Villages & Landmarks",
			"xz": Vector2(-16.0, -28.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Crystal Cave Interior",
			"subtitle": "Subterranean River Cavern",
			"group": "Villages & Landmarks",
			"xz": Vector2(CaveLayout.SPAWN.x, CaveLayout.SPAWN.z),
			"force_y": CaveLayout.SPAWN.y,
			"underground": true,
		},
		{
			"name": "Howlcrest Wolf Territory",
			"subtitle": "NE Granite Crag & Pine Grove",
			"group": "Monster Territories & Dungeons",
			"xz": WorldLandmarks.WOLF_CRAG_CENTER + Vector2(0.0, 14.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Webwood Spider Forest",
			"subtitle": "Haunted Canopy Silk Glade",
			"group": "Monster Territories & Dungeons",
			"xz": web_c + Vector2(0.0, 18.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Sunken Swamp Ruins · Rat Territory",
			"subtitle": "Eastern Bog Ruins & Burrow Mouth",
			"group": "Monster Territories & Dungeons",
			"xz": WorldLandmarks.RAT_WARREN_MOUTH + Vector2(0.0, 22.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Skeleton Crypt Entrance",
			"subtitle": "Barrow Ravine Cliff Portal",
			"group": "Monster Territories & Dungeons",
			"xz": WorldLandmarks.SKEL_CAVE_MOUTH + Vector2(0.0, 14.0),
			"force_y": NAN,
			"underground": false,
		},
		{
			"name": "Skeleton Catacombs Interior",
			"subtitle": "Procedural Subterranean Vestibule",
			"group": "Monster Territories & Dungeons",
			"xz": Vector2(skel_in.x, skel_in.z),
			"force_y": skel_in.y,
			"underground": true,
		},
	]


func teleport_to_destination(dest: Dictionary) -> void:
	if slime == null or not is_instance_valid(slime) or not slime.has_method("teleport_to_world"):
		return
	var xz: Vector2 = dest.get("xz", Vector2.ZERO)
	var fy: float = float(dest.get("force_y", NAN))
	var ug: bool = bool(dest.get("underground", false))
	slime.call("teleport_to_world", xz, fy, ug)
	_set_menu_open(false)
	show_toast("Teleported to %s" % String(dest.get("name", "Destination")), Color(0.56, 0.96, 1.0), 2.8)


func _make_menu_pill_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", pill_font_size)
	btn.add_theme_color_override("font_color", Color("eaf4fb"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.22, 0.34, 0.78)
	sb.border_color = Color(0.45, 0.78, 0.98, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(pill_corner_radius)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	var sb_hov := sb.duplicate() as StyleBoxFlat
	sb_hov.bg_color = Color(0.18, 0.36, 0.54, 0.92)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hov)
	btn.add_theme_stylebox_override("pressed", sb_hov)
	return btn


func _make_panel_btn(label_text: String, toggleable: bool = false, accent: bool = false) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.toggle_mode = toggleable
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color("eaf2fb"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	var make_sb := func(bg: Color, bd: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = bd
		s.set_border_width_all(1)
		s.set_corner_radius_all(10)
		s.content_margin_left = 12.0
		s.content_margin_right = 12.0
		s.content_margin_top = 7.0
		s.content_margin_bottom = 7.0
		return s

	var bg_n := Color(0.14, 0.30, 0.46, 0.88) if accent else Color(0.11, 0.14, 0.20, 0.88)
	var bd_n := Color(0.45, 0.78, 0.98, 0.62) if accent else Color(0.36, 0.46, 0.60, 0.45)
	var bg_h := Color(0.20, 0.42, 0.62, 0.95)
	var bd_h := Color(0.62, 0.88, 1.0, 0.88)
	var bg_p := Color(0.18, 0.44, 0.66, 0.98)
	btn.add_theme_stylebox_override("normal", make_sb.call(bg_n, bd_n))
	btn.add_theme_stylebox_override("hover", make_sb.call(bg_h, bd_h))
	btn.add_theme_stylebox_override("focus", make_sb.call(bg_h, bd_h))
	btn.add_theme_stylebox_override("pressed", make_sb.call(bg_p, bd_h))
	return btn


func _build_pause_menu_ui() -> void:
	_menu_backdrop = ColorRect.new()
	_menu_backdrop.name = "PauseMenuBackdrop"
	_menu_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_backdrop.color = Color(0.02, 0.03, 0.05, 0.56)
	_menu_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_backdrop.z_index = 40
	_menu_backdrop.visible = false
	add_child(_menu_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_backdrop.add_child(center)

	var card := PanelContainer.new()
	card.name = "MenuCard"
	card.custom_minimum_size = Vector2(720.0, 500.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	card_style.border_color = Color(0.42, 0.74, 0.96, 0.55)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(18)
	card_style.content_margin_left = 24.0
	card_style.content_margin_right = 24.0
	card_style.content_margin_top = 20.0
	card_style.content_margin_bottom = 20.0
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	card_style.shadow_size = 24
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	card.add_child(root_v)

	# Header + Tabs
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 10)
	root_v.add_child(top_h)

	var title := Label.new()
	title.text = "SLIME SANDBOX MENU"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("eaf4fb"))
	top_h.add_child(title)

	_tab_tp_btn = _make_panel_btn("Teleport Map", true, true)
	_tab_tp_btn.button_pressed = true
	_tab_tp_btn.pressed.connect(func(): _switch_menu_tab("teleport"))
	top_h.add_child(_tab_tp_btn)

	_tab_set_btn = _make_panel_btn("Settings", true, false)
	_tab_set_btn.pressed.connect(func(): _switch_menu_tab("settings"))
	top_h.add_child(_tab_set_btn)

	var sep := HSeparator.new()
	sep.modulate = Color(0.45, 0.76, 0.96, 0.35)
	root_v.add_child(sep)

	# Page stack inside scroll container
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(672.0, 355.0)
	root_v.add_child(scroll)

	var pages_holder := VBoxContainer.new()
	pages_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages_holder)

	# --- TAB 1: TELEPORT & DEV MODE ---
	var tp_v := VBoxContainer.new()
	tp_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tp_v.add_theme_constant_override("separation", 10)
	pages_holder.add_child(tp_v)
	_tab_tp_page = tp_v

	# Developer Mode Section directly inside the Teleport Panel
	var dev_hdr := Label.new()
	dev_hdr.text = "DEVELOPER MODE & FLIGHT"
	dev_hdr.add_theme_font_size_override("font_size", 12)
	dev_hdr.add_theme_color_override("font_color", dev_color)
	tp_v.add_child(dev_hdr)

	var dev_bar := HBoxContainer.new()
	dev_bar.add_theme_constant_override("separation", 14)
	tp_v.add_child(dev_bar)

	_dev_chk = CheckButton.new()
	_dev_chk.text = "Dev Mode (F4)"
	_dev_chk.toggled.connect(func(on: bool):
		if _syncing_menu_controls or slime == null or not is_instance_valid(slime):
			return
		if slime.dev_mode != on and slime.has_method("toggle_dev_mode"):
			slime.call("toggle_dev_mode")
		_sync_menu_controls()
	)
	dev_bar.add_child(_dev_chk)

	_fly_chk = CheckButton.new()
	_fly_chk.text = "Fly (V)"
	_fly_chk.toggled.connect(func(on: bool):
		if _syncing_menu_controls or slime == null or not is_instance_valid(slime):
			return
		if not slime.dev_mode and on and slime.has_method("toggle_dev_mode"):
			slime.call("toggle_dev_mode")
		if slime.dev_fly != on and slime.has_method("toggle_dev_fly"):
			slime.call("toggle_dev_fly")
		_sync_menu_controls()
	)
	dev_bar.add_child(_fly_chk)

	_noclip_chk = CheckButton.new()
	_noclip_chk.text = "Noclip (N)"
	_noclip_chk.toggled.connect(func(on: bool):
		if _syncing_menu_controls or slime == null or not is_instance_valid(slime):
			return
		if not slime.dev_mode and on and slime.has_method("toggle_dev_mode"):
			slime.call("toggle_dev_mode")
		if slime.dev_noclip != on and slime.has_method("toggle_dev_noclip"):
			slime.call("toggle_dev_noclip")
		_sync_menu_controls()
	)
	dev_bar.add_child(_noclip_chk)

	var spd_down_btn := _make_panel_btn("Speed -", false, false)
	spd_down_btn.pressed.connect(func():
		if slime != null and is_instance_valid(slime) and slime.has_method("adjust_dev_speed"):
			slime.call("adjust_dev_speed", -1)
			_sync_menu_controls()
	)
	dev_bar.add_child(spd_down_btn)

	var spd_up_btn := _make_panel_btn("Speed +", false, false)
	spd_up_btn.pressed.connect(func():
		if slime != null and is_instance_valid(slime) and slime.has_method("adjust_dev_speed"):
			slime.call("adjust_dev_speed", 1)
			_sync_menu_controls()
	)
	dev_bar.add_child(spd_up_btn)

	_dev_panel_status_lbl = Label.new()
	_dev_panel_status_lbl.text = "DEV OFF · FLY ON (V) · NOCLIP ON (N) · SPEED 32 m/s"
	_dev_panel_status_lbl.add_theme_font_size_override("font_size", 12)
	_dev_panel_status_lbl.add_theme_color_override("font_color", dev_color)
	tp_v.add_child(_dev_panel_status_lbl)

	var dev_sep := HSeparator.new()
	dev_sep.modulate = Color(0.45, 0.76, 0.96, 0.28)
	tp_v.add_child(dev_sep)

	for grp_name: String in ["Villages & Landmarks", "Monster Territories & Dungeons"]:
		var hdr := Label.new()
		hdr.text = grp_name.to_upper()
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.add_theme_color_override("font_color", Color("96c8ea"))
		tp_v.add_child(hdr)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		tp_v.add_child(grid)

		for dest in get_teleport_destinations():
			if String(dest.get("group", "")) != grp_name:
				continue
			var d_snap := dest.duplicate()
			var b := _make_panel_btn("%s\n%s" % [String(dest["name"]), String(dest["subtitle"])], false, false)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(310.0, 52.0)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func(): teleport_to_destination(d_snap))
			grid.add_child(b)

	# --- TAB 2: SETTINGS ---
	var set_v := VBoxContainer.new()
	set_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_v.add_theme_constant_override("separation", 10)
	set_v.visible = false
	pages_holder.add_child(set_v)
	_tab_set_page = set_v

	# Quality presets
	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override("separation", 8)
	set_v.add_child(q_row)
	var q_lbl := Label.new()
	q_lbl.text = "Graphics Quality"
	q_lbl.custom_minimum_size = Vector2(150.0, 0.0)
	q_lbl.add_theme_color_override("font_color", Color("dce8f5"))
	q_row.add_child(q_lbl)
	_quality_btns.clear()
	var q_names: Array[String] = ["Low", "Medium", "High", "Ultra"]
	for qi in range(4):
		var qname: String = q_names[qi]
		var qb := _make_panel_btn(qname, true)
		qb.pressed.connect(func():
			var s := SlimeSettings.get_or_create()
			if s:
				s.set_quality_preset(qi)
			_sync_menu_controls()
		)
		q_row.add_child(qb)
		_quality_btns.append(qb)

	# Time of day
	var t_row := HBoxContainer.new()
	t_row.add_theme_constant_override("separation", 8)
	set_v.add_child(t_row)
	var t_lbl := Label.new()
	t_lbl.text = "Time of Day"
	t_lbl.custom_minimum_size = Vector2(150.0, 0.0)
	t_lbl.add_theme_color_override("font_color", Color("dce8f5"))
	t_row.add_child(t_lbl)
	_time_btns.clear()
	for t_pair: Array in [["Dynamic", "dynamic"], ["Dawn", "dawn"], ["Day", "day"], ["Dusk", "dusk"], ["Night", "night"]]:
		var tm_key := String(t_pair[1])
		var tb := _make_panel_btn(String(t_pair[0]), true)
		tb.pressed.connect(func():
			if (_time_weather == null or not is_instance_valid(_time_weather)) and is_inside_tree():
				_time_weather = get_tree().get_first_node_in_group("world_time_weather")
			if _time_weather != null and _time_weather.has_method("set_time_mode"):
				_time_weather.call("set_time_mode", tm_key)
			_sync_menu_controls()
		)
		t_row.add_child(tb)
		_time_btns[tm_key] = tb

	# Weather
	var w_row := HBoxContainer.new()
	w_row.add_theme_constant_override("separation", 8)
	set_v.add_child(w_row)
	var w_lbl := Label.new()
	w_lbl.text = "Weather"
	w_lbl.custom_minimum_size = Vector2(150.0, 0.0)
	w_lbl.add_theme_color_override("font_color", Color("dce8f5"))
	w_row.add_child(w_lbl)
	_weather_btns.clear()
	var w_names: Array[String] = ["Clear", "Cloudy", "Light Rain", "Storm"]
	for wi in range(4):
		var wn: String = w_names[wi]
		var wb := _make_panel_btn(wn, true)
		wb.pressed.connect(func():
			if (_time_weather == null or not is_instance_valid(_time_weather)) and is_inside_tree():
				_time_weather = get_tree().get_first_node_in_group("world_time_weather")
			if _time_weather != null and _time_weather.has_method("set_weather_state"):
				_time_weather.call("set_weather_state", wi, 999.0)
			_sync_menu_controls()
		)
		w_row.add_child(wb)
		_weather_btns[wi] = wb

	# Audio sliders
	var m_pack := _make_slider_row(set_v, "Master Volume", 0.0, 100.0, 1.0)
	_master_slider = m_pack[0] as HSlider
	_master_val_lbl = m_pack[1] as Label
	_master_slider.value_changed.connect(func(v: float):
		if _syncing_menu_controls:
			return
		_master_val_lbl.text = "%d%%" % int(round(v))
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_value("audio", "master_volume", v)
	)

	var sfx_pack := _make_slider_row(set_v, "SFX Volume", 0.0, 100.0, 1.0)
	_sfx_slider = sfx_pack[0] as HSlider
	_sfx_val_lbl = sfx_pack[1] as Label
	_sfx_slider.value_changed.connect(func(v: float):
		if _syncing_menu_controls:
			return
		_sfx_val_lbl.text = "%d%%" % int(round(v))
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_value("audio", "sfx_volume", v)
	)

	# Controls
	var sens_pack := _make_slider_row(set_v, "Camera Sensitivity", 0.002, 0.022, 0.001)
	_sens_slider = sens_pack[0] as HSlider
	_sens_val_lbl = sens_pack[1] as Label
	_sens_slider.value_changed.connect(func(v: float):
		if _syncing_menu_controls:
			return
		_sens_val_lbl.text = "%.3f" % v
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_value("controls", "mouse_sensitivity", v)
		var cam_rig := get_tree().current_scene.get_node_or_null("CameraRig") if (get_tree() != null and get_tree().current_scene != null) else null
		if cam_rig != null and "drag_sensitivity" in cam_rig:
			cam_rig.set("drag_sensitivity", v)
	)

	var chk_row := HBoxContainer.new()
	chk_row.add_theme_constant_override("separation", 18)
	set_v.add_child(chk_row)

	_invert_y_chk = CheckButton.new()
	_invert_y_chk.text = "Invert Camera Y"
	_invert_y_chk.toggled.connect(func(on: bool):
		if _syncing_menu_controls:
			return
		var s := SlimeSettings.get_or_create()
		if s:
			s.set_value("controls", "invert_y", on)
		var cam_rig := get_tree().current_scene.get_node_or_null("CameraRig") if (get_tree() != null and get_tree().current_scene != null) else null
		if cam_rig != null and "invert_y" in cam_rig:
			cam_rig.set("invert_y", on)
	)
	chk_row.add_child(_invert_y_chk)

	# Footer bar
	var foot_sep := HSeparator.new()
	foot_sep.modulate = Color(0.45, 0.76, 0.96, 0.35)
	root_v.add_child(foot_sep)

	var foot_h := HBoxContainer.new()
	foot_h.alignment = BoxContainer.ALIGNMENT_END
	foot_h.add_theme_constant_override("separation", 12)
	root_v.add_child(foot_h)

	var main_btn := _make_panel_btn("Return to Main Menu", false, false)
	main_btn.pressed.connect(func():
		if get_tree() != null and FileAccess.file_exists("res://main_menu/main_menu.tscn"):
			get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")
	)
	foot_h.add_child(main_btn)

	var resume_btn := _make_panel_btn("Resume Game", false, true)
	resume_btn.pressed.connect(func(): close_menu())
	foot_h.add_child(resume_btn)


func _make_slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150.0, 0.0)
	lbl.add_theme_color_override("font_color", Color("dce8f5"))
	row.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sl)

	var val_l := Label.new()
	val_l.custom_minimum_size = Vector2(56.0, 0.0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.add_theme_color_override("font_color", Color("a6e4ff"))
	row.add_child(val_l)
	return [sl, val_l]


func _sync_menu_controls() -> void:
	_syncing_menu_controls = true
	var s := SlimeSettings.get_or_create()
	var q_cur := int(s.get_value("graphics", "quality_preset", 0)) if s != null else 0
	for qi in range(_quality_btns.size()):
		_quality_btns[qi].button_pressed = (qi == q_cur)

	if (_time_weather == null or not is_instance_valid(_time_weather)) and is_inside_tree():
		_time_weather = get_tree().get_first_node_in_group("world_time_weather")
	var tm_cur := String(_time_weather.get("time_mode")) if _time_weather != null else "dynamic"
	for k in _time_btns.keys():
		(_time_btns[k] as Button).button_pressed = (String(k) == tm_cur)

	var w_cur := int(_time_weather.get("weather_state")) if _time_weather != null else 0
	for k in _weather_btns.keys():
		(_weather_btns[k] as Button).button_pressed = (int(k) == w_cur)

	if s != null:
		var mv := float(s.get_value("audio", "master_volume", 85.0))
		if _master_slider != null:
			_master_slider.value = mv
			_master_val_lbl.text = "%d%%" % int(round(mv))
		var sv := float(s.get_value("audio", "sfx_volume", 85.0))
		if _sfx_slider != null:
			_sfx_slider.value = sv
			_sfx_val_lbl.text = "%d%%" % int(round(sv))
		var sens := float(s.get_value("controls", "mouse_sensitivity", 0.007))
		if _sens_slider != null:
			_sens_slider.value = sens
			_sens_val_lbl.text = "%.3f" % sens
		if _invert_y_chk != null:
			_invert_y_chk.button_pressed = bool(s.get_value("controls", "invert_y", false))

	if slime != null and is_instance_valid(slime):
		if _dev_chk != null:
			_dev_chk.button_pressed = slime.dev_mode
		if _fly_chk != null:
			_fly_chk.button_pressed = slime.dev_fly
		if _noclip_chk != null:
			_noclip_chk.button_pressed = slime.dev_noclip
		if _dev_panel_status_lbl != null:
			_dev_panel_status_lbl.text = "DEV %s · FLY %s (V) · NOCLIP %s (N) · SPEED %.0f m/s ([ / ] or Alt+Wheel · Shift ×2.5 · F4 toggle)" % [
				"ON" if slime.dev_mode else "OFF",
				"ON" if slime.dev_fly else "OFF",
				"ON" if slime.dev_noclip else "OFF",
				slime.dev_speed,
			]
	_syncing_menu_controls = false
