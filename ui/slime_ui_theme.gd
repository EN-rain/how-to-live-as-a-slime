class_name SlimeUITheme
extends RefCounted
## Default/Clean Godot UI theme and style helper for the Slime project.
## Returns standard clean Control styles without external custom assets.

const COL_BG_DEFAULT := Color(0.12, 0.14, 0.18, 0.92)
const COL_BORDER_DEFAULT := Color(0.35, 0.40, 0.48, 0.6)
const COL_TEXT_PRIMARY := Color(0.95, 0.95, 0.95, 1.0)
const COL_TEXT_SECONDARY := Color(0.75, 0.78, 0.82, 1.0)
const COL_ACCENT := Color(0.32, 0.65, 0.95, 1.0)
const COL_DANGER := Color(0.85, 0.35, 0.35, 1.0)

static func build_theme(_high_contrast := false, _night_mode := false) -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	return t

static func make_glass_card_style(_high_contrast := false, _night_mode := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COL_BG_DEFAULT
	box.border_color = COL_BORDER_DEFAULT
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	return box

static func make_pill_style(border_col := COL_BORDER_DEFAULT, bg_alpha := 0.85) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.14, 0.18, bg_alpha)
	box.border_color = border_col
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box

static func make_row_box(hovered: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.18, 0.22, 0.28, 0.85) if hovered else Color(0.14, 0.16, 0.20, 0.65)
	box.border_color = Color(0.40, 0.45, 0.55, 0.5) if hovered else Color(0.25, 0.28, 0.34, 0.4)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box

static func style_primary_cta(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_font_size_override("font_size", 16)

static func style_danger_button(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_color_override("font_color", COL_DANGER)

static func style_tab_button(_btn: Button, _active: bool) -> void:
	pass

static func make_key_badge(key_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.18, 0.20, 0.24, 0.9)
	box.border_color = Color(0.35, 0.40, 0.48, 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	panel.add_theme_stylebox_override("panel", box)

	var lbl := Label.new()
	lbl.text = key_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	panel.add_child(lbl)
	return panel

static func get_display_font() -> Font:
	return null

static func get_body_font() -> Font:
	return null

static func get_bold_font() -> Font:
	return null

static func make_ornate_divider() -> Control:
	return HSeparator.new()

static func add_gold_filigree_overlay(_target_card: Control) -> void:
	pass
