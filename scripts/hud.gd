class_name SlimeHud
extends Control
## HUD display for eaten stats, mass/volume, clone count, active status, and controls hints.

@export var slime: Slime
@export var props: SlimeProps
@export var hint_text := "WASD move · Shift run · E split · Q roam · M merge · F5-F8 quality · F4 dev · Esc menu"
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
var _hint: Label
var _dev_line: Label
var _dev_pill: PanelContainer
var _debug_line: Label
var _debug_pill: PanelContainer
var _toast_line: Label
var _toast_pill: PanelContainer
var _toast_timer: float = 0.0
var _last := ""
var _last_dev := ""
var _last_dbg := ""

var _frames_ms: Array = []
var _phys_ms: Array = []
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

	_prev_pframe = Engine.get_physics_frames()
	call_deferred("_ensure_debug_mesh")


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
		if not debug_posture and _dbg_im != null:
			_dbg_im.clear_surfaces()
		elif debug_posture:
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
	_frames_ms.append(delta * 1000.0)
	if _frames_ms.size() > 300:
		_frames_ms.pop_front()
	_phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if _phys_ms.size() > 300:
		_phys_ms.pop_front()
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


func _percentile(arr: Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var a := arr.duplicate()
	a.sort()
	var idx := int(clampf(roundf(q * float(a.size() - 1)), 0.0, float(a.size() - 1)))
	return float(a[idx])


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
	if _toast_timer > 0.0 and _toast_pill != null:
		_toast_timer -= _delta
		if _toast_timer <= 0.0:
			_toast_pill.visible = false
		elif _toast_timer < 0.75:
			_toast_pill.modulate = Color(1.0, 1.0, 1.0, clampf(_toast_timer / 0.75, 0.0, 1.0))
	if slime == null or props == null:
		return

	# Authoritative volume and mass calculations
	var mass := slime.get_volume()
	var clone_count := maxi(0, props.registered_slimes.size() - 1)
	var text := ""
	if props.total() > 0:
		text = "Eaten %d / %d  ·  Vol %.1f m³ (Scale %.2f×)" % [props.eaten, props.total(), mass, slime.target_scale]
	else:
		text = "Vol %.1f m³ (Scale %.2f×)" % [mass, slime.target_scale]
	if clone_count > 0:
		text += "  ·  Clones: %d" % clone_count

	# Check active push-eating engulf front progress
	var active_engulf_p = null
	for p in props.props:
		if p.last_presser == slime and p.engulf_front > 0.01:
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
