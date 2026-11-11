class_name CoreRuleDiagram2D
extends Control
## Interactive 2D vector schematic demonstrating the Core-Sphere traversal rule.
##
## Used inside the Slime Guide tab so players can visually see how outer jelly
## molds around narrow gates automatically as long as the inner Core Sphere fits.

@export_group("Gate Simulation")
## Interactive gate gap width in meters.
@export_range(0.48, 2.40, 0.02) var gate_width_m: float = 1.40:
	set(v):
		gate_width_m = clampf(v, 0.48, 2.40)
		queue_redraw()

## Hard physical core sphere diameter in meters (minimum passable gate width).
@export var core_diameter_m: float = 0.72:
	set(v):
		core_diameter_m = maxf(v, 0.1)
		queue_redraw()

## Rest outer jelly envelope diameter in meters.
@export var outer_diameter_m: float = 2.00:
	set(v):
		outer_diameter_m = maxf(v, 0.2)
		queue_redraw()

@export_group("Schematic Colors")
@export var bg_color: Color = Color(0.14, 0.09, 0.05, 0.88):
	set(v):
		bg_color = v
		queue_redraw()
@export var border_color: Color = Color(0.92, 0.74, 0.34, 0.65):
	set(v):
		border_color = v
		queue_redraw()
@export var grid_color: Color = Color(0.92, 0.76, 0.42, 0.08):
	set(v):
		grid_color = v
		queue_redraw()
@export var pass_jelly_fill: Color = Color(0.32, 0.78, 0.98, 0.48):
	set(v):
		pass_jelly_fill = v
		queue_redraw()
@export var block_jelly_fill: Color = Color(0.95, 0.46, 0.44, 0.42):
	set(v):
		block_jelly_fill = v
		queue_redraw()
@export var pillar_color: Color = Color(0.36, 0.25, 0.16, 0.96):
	set(v):
		pillar_color = v
		queue_redraw()
@export var pillar_border_color: Color = Color(0.96, 0.80, 0.38, 0.92):
	set(v):
		pillar_border_color = v
		queue_redraw()

var _time := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 210.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x <= 20.0 or sz.y <= 20.0:
		return

	# Warm dark parchment-slate schematic background with gold border
	draw_rect(Rect2(Vector2.ZERO, sz), bg_color, true)
	draw_rect(Rect2(Vector2.ONE, sz - Vector2(2, 2)), border_color, false, 2.0)

	var cx := sz.x * 0.5
	var cy := sz.y * 0.54
	var px_per_m := minf(sz.x * 0.16, sz.y * 0.36)

	var can_pass := gate_width_m >= core_diameter_m
	var outer_r := (outer_diameter_m * 0.5) * px_per_m
	var core_r := (core_diameter_m * 0.5) * px_per_m
	var half_gap := (gate_width_m * 0.5) * px_per_m

	# Subtle cartography grid lines
	for gx in range(-5, 6):
		var x := cx + float(gx) * px_per_m * 0.5
		draw_line(Vector2(x, 12.0), Vector2(x, sz.y - 12.0), grid_color, 1.0)
	for gy in range(-2, 3):
		var y := cy + float(gy) * px_per_m * 0.5
		draw_line(Vector2(16.0, y), Vector2(sz.x - 16.0, y), grid_color, 1.0)

	# Animated slime travel X position (left to right through the gate at cx)
	var cycle := fmod(_time * 0.52, 1.0)
	var travel_x: float
	if can_pass:
		travel_x = lerpf(cx - px_per_m * 1.85, cx + px_per_m * 1.85, smoothstep(0.05, 0.95, cycle))
	else:
		# Advances up to pillar contact, then recoils slightly
		var approach := sin(cycle * PI)
		var stop_x := cx - core_r - px_per_m * 0.28
		travel_x = lerpf(cx - px_per_m * 1.75, stop_x, approach)

	# Calculate how close slime is to the gate center to compress lateral radius
	var dist_to_gate := absf(travel_x - cx)
	var in_gate := clampf(1.0 - dist_to_gate / (outer_r * 1.25), 0.0, 1.0)
	var squeezed_half_w := lerpf(outer_r, minf(outer_r, maxf(half_gap - 3.0, core_r)), in_gate)
	var stretch_x := outer_r * (1.0 + (1.0 - squeezed_half_w / maxf(outer_r, 1.0)) * 0.38)

	# Draw Slime Outer Jelly Contour
	const SEG := 48
	var poly := PackedVector2Array()
	poly.resize(SEG)
	for i in SEG:
		var a := TAU * float(i) / float(SEG)
		var lx := cos(a) * stretch_x
		var ly := sin(a) * outer_r
		var wx := travel_x + lx
		# Clamp lateral width where overlapping gate X span
		var gate_overlap := clampf(1.0 - absf(wx - cx) / (px_per_m * 0.48), 0.0, 1.0)
		var max_allowed_y := lerpf(outer_r * 1.2, maxf(half_gap - 3.0, core_r * 1.02), gate_overlap)
		if absf(ly) > max_allowed_y:
			ly = signf(ly) * max_allowed_y
		poly[i] = Vector2(wx, cy + ly)

	var jelly_fill := pass_jelly_fill if can_pass else block_jelly_fill
	var jelly_rim := Color(0.68, 0.96, 1.0, 0.90) if can_pass else Color(0.98, 0.62, 0.58, 0.90)
	draw_colored_polygon(poly, jelly_fill)
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, jelly_rim, 2.2, true)

	# Draw Inner Glowing Core Sphere
	var core_pos := Vector2(travel_x, cy)
	draw_circle(core_pos, core_r * 1.35, Color(0.28, 0.95, 0.88, 0.25))
	draw_circle(core_pos, core_r, Color(0.18, 0.72, 0.98, 0.92))
	draw_arc(core_pos, core_r, 0.0, TAU, 28, Color(0.85, 0.99, 1.0, 0.95), 1.8, true)

	# Draw Stone & Gold Gate Pillars (top and bottom in top-down diagram)
	var pillar_w := px_per_m * 0.65
	var pillar_h := maxf(16.0, (sz.y * 0.5 - half_gap - 10.0))
	var top_rect := Rect2(Vector2(cx - pillar_w * 0.5, 10.0), Vector2(pillar_w, pillar_h))
	var bot_rect := Rect2(Vector2(cx - pillar_w * 0.5, cy + half_gap), Vector2(pillar_w, sz.y - (cy + half_gap) - 10.0))
	draw_rect(top_rect, pillar_color, true)
	draw_rect(top_rect, pillar_border_color, false, 2.0)
	draw_rect(bot_rect, pillar_color, true)
	draw_rect(bot_rect, pillar_border_color, false, 2.0)

	# Status overlay text
	var font := SlimeUITheme.get_bold_font()
	if font == null:
		font = ThemeDB.fallback_font
	var status_txt := "⚜ GATE %.2fm  >=  CORE %.2fm  →  LIQUID PASSAGE GRANTED" % [gate_width_m, core_diameter_m] \
		if can_pass else "✕ GATE %.2fm  <  CORE %.2fm  →  BLOCKED BY CORE SPHERE" % [gate_width_m, core_diameter_m]
	var status_col := Color(0.98, 0.86, 0.42, 0.98) if can_pass else Color(0.98, 0.52, 0.44, 0.98)
	draw_string(font, Vector2(16.0, 26.0), status_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_col)

