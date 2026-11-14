class_name SlimeHud
extends Control
## HUD display for eaten stats, mass/volume, clone count, active status, and controls hints.

@export var slime: Slime
@export var props: SlimeProps
@export var hint_text := "WASD move · Space jump (hold) · Shift run · E split · Q roam · M merge · T time · Y weather · F5-F8 quality · F4 dev · Esc menu"
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
	row.add_child(_hint.get_parent())

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
	box.bg_color = pill_bg_color
	box.set_corner_radius_all(pill_corner_radius)
	box.content_margin_left = 11.0
	box.content_margin_right = 11.0
	box.content_margin_top = 5.0
	box.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", box)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", pill_font_size)
	label.add_theme_color_override("font_color", font_color)
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
		if FileAccess.file_exists("res://main_menu/main_menu.tscn"):
			accept_event()
			get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")
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
			var env_txt := "%s %s · %s" % [
				_time_weather.get_hour_minute_string(),
				_time_weather.get_phase_label(),
				_time_weather.get_weather_label(),
			]
			if env_txt != _last_env:
				_last_env = env_txt
				_env_line.text = env_txt

	if _dev_pill != null:
		var show_dev := slime.dev_mode
		_dev_pill.visible = show_dev
		if show_dev:
			var dev_txt := "DEV · FLY %s (V) · NOCLIP %s (N) · SPEED %.0f m/s ([ / ] or Alt+Wheel · Shift ×2.5) · Space/C ▲▼ · F4 off" % [
				"ON" if slime.dev_fly else "OFF",
				"ON" if slime.dev_noclip else "OFF",
				slime.dev_speed,
			]
			if dev_txt != _last_dev:
				_last_dev = dev_txt
				_dev_line.text = dev_txt

	_update_debug_overlay()
