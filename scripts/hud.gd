class_name SlimeHud
extends Control
## HUD display for eaten stats, mass/volume, clone count, active status, and controls hints.

@export var slime: Slime
@export var props: SlimeProps
@export var hint_text := "WASD move · Shift run · Z hold liquid / engulf · E split follower · Q split roamer · M merge · Click poke"

var _stat: Label
var _hint: Label
var _last := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 6)
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = 12.0
	row.offset_top = 12.0
	row.offset_right = -12.0
	add_child(row)

	_stat = _make_pill(Color("eaf4fb"))
	row.add_child(_stat.get_parent())
	_hint = _make_pill(Color("bcd3e4"))
	_hint.text = hint_text
	row.add_child(_hint.get_parent())


func _make_pill(font_color: Color) -> Label:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(16.0 / 255.0, 32.0 / 255.0, 48.0 / 255.0, 0.55)
	box.set_corner_radius_all(999)
	box.content_margin_left = 11.0
	box.content_margin_right = 11.0
	box.content_margin_top = 5.0
	box.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", box)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", font_color)
	panel.add_child(label)
	return label


func _process(_delta: float) -> void:
	if slime == null or props == null:
		return

	# Authoritative volume and mass calculations
	var mass := slime.get_volume()
	var clone_count := maxi(0, props.registered_slimes.size() - 1)
	var text := "Eaten %d / %d  ·  Vol %.1f m³ (Scale %.2f×)" % [props.eaten, props.total(), mass, slime.target_scale]
	if clone_count > 0:
		text += "  ·  Clones: %d" % clone_count

	# Check active push-eating engulf front or Z-cover progress
	var active_engulf_p = null
	for p in props.props:
		if p.last_presser == slime and p.engulf_front > 0.01:
			active_engulf_p = p
			break

	if active_engulf_p != null:
		text += "  ·  Engulfing %d%%" % int(active_engulf_p.engulf_front * 100.0)
	elif slime.engulf_progress > 0.05:
		text += "  ·  Z-Drape %d%%" % int(slime.engulf_progress * 100.0)
	elif slime.liquid_amt > 0.5:
		text += "  ·  [Liquid Mode]"

	if text != _last:
		_last = text
		_stat.text = text
