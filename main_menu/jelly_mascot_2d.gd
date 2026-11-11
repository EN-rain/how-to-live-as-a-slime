class_name JellyMascot2D
extends Control
## Pure 2D Interactive Anime Jelly Slime Mascot Stage.
##
## Renders the Hero Slime, Follower & Roamer companion blobs, floating 2D bubbles,
## internal Core Spheres, caustic highlights, and expressive cursor-tracking eyes
## using 2D spring-damper physics and vector canvas drawing (zero 3D objects).

signal slime_poked(actor_name: String, total_pokes: int, reaction_text: String)

enum MoodState {
	IDLE,
	EXCITED,
	CURIOUS,
	FOCUSED,
	SLEEPY
}

const REACTIONS: Array[String] = [
	"Boing! Jelly ripples active!",
	"Squish! Core Sphere resonating!",
	"Wobble! Surface tension 100%!",
	"Splat! Refractive dispersion!",
	"Jiggle! Ready to absorb cubes!",
	"Pop! Mitosis energy charged!"
]

@export_group("Mascot Appearance")
@export_range(0.0, 1.0, 0.05) var night_mode: float = 0.0
@export_range(0.2, 2.5, 0.05) var jiggle_strength: float = 1.0
@export var reduce_motion: bool = false
@export var show_core_xray: bool = true
@export var mood_state: MoodState = MoodState.IDLE

@export_group("Hero Slime")
@export var hero_uv: Vector2 = Vector2(0.50, 0.56)
@export var hero_radius: float = 138.0
@export var hero_color: Color = Color(0.52, 0.85, 1.0)

@export_group("Follower Slime")
@export var follower_uv: Vector2 = Vector2(0.76, 0.60)
@export var follower_radius: float = 74.0
@export var follower_color: Color = Color(0.50, 0.84, 0.99)

@export_group("Roamer Slime")
@export var roamer_uv: Vector2 = Vector2(0.26, 0.62)
@export var roamer_radius: float = 62.0
@export var roamer_color: Color = Color(0.45, 0.88, 0.98)

@export_group("Ambient Stage")
@export var bubble_count: int = 18
@export var inner_bubble_count: int = 7

var poke_count := 0

var _time := 0.0
var _actors: Array[Dictionary] = []
var _bubbles: Array[Dictionary] = []
var _ripples: Array[Dictionary] = []
var _float_texts: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_init_actors()
	_init_bubbles()


func _init_actors() -> void:
	_actors.clear()
	# 0: Roamer (back-left), 1: Follower (back-right), 2: Hero (center-front)
	_actors.append(_make_actor("Roamer Slime", roamer_uv, roamer_radius, 2.3, roamer_color))
	_actors.append(_make_actor("Follower Slime", follower_uv, follower_radius, 1.1, follower_color))
	_actors.append(_make_actor("Hero Slime", hero_uv, hero_radius, 0.0, hero_color))


func _make_actor(actor_name: String, uv_pos: Vector2, radius: float, phase: float, tint: Color) -> Dictionary:
	var inner_bubbles: Array[Dictionary] = []
	for i in inner_bubble_count:
		inner_bubbles.append({
			"ang": randf() * TAU,
			"dist": randf_range(0.22, 0.76),
			"r": randf_range(0.035, 0.085),
			"speed": randf_range(0.25, 0.55),
			"phase": randf() * TAU,
		})
	return {
		"name": actor_name,
		"uv": uv_pos,
		"radius": radius,
		"phase": phase,
		"tint": tint,
		"squash": 0.0,
		"squash_v": 0.0,
		"tilt": 0.0,
		"tilt_v": 0.0,
		"wave_amp": 0.0,
		"wave_angle": 0.0,
		"wave_t": 10.0,
		"happy_timer": 0.0,
		"eye_offset": Vector2.ZERO,
		"inner_bubbles": inner_bubbles,
	}


func _init_bubbles() -> void:
	_bubbles.clear()
	for i in bubble_count:
		_bubbles.append({
			"uv": Vector2(randf_range(0.08, 0.92), randf_range(0.08, 0.92)),
			"r": randf_range(4.0, 16.0),
			"speed": randf_range(0.025, 0.065),
			"wobble": randf() * TAU,
			"is_cube": i % 4 == 0,
			"rot": randf() * TAU,
			"hue": randf(),
		})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if poke_at_local_pos(mb.position):
				accept_event()


func poke_at_local_pos(local_pos: Vector2) -> bool:
	var sz := size
	if sz.x <= 10.0 or sz.y <= 10.0:
		return false
	# Check from front-most (Hero) to back
	for idx in range(_actors.size() - 1, -1, -1):
		var a: Dictionary = _actors[idx]
		var center := Vector2(a["uv"].x * sz.x, a["uv"].y * sz.y)
		var r: float = float(a["radius"]) * minf(sz.x / 680.0, sz.y / 620.0)
		var delta := local_pos - center
		var norm := Vector2(delta.x / (r * 1.18), delta.y / (r * 0.95))
		if norm.length() <= 1.08:
			_apply_actor_poke(idx, local_pos, center)
			return true
	# Clicked ambient stage: gently poke all slimes toward click
	var hero_center := Vector2(_actors[2]["uv"].x * sz.x, _actors[2]["uv"].y * sz.y)
	if local_pos.distance_to(hero_center) < minf(sz.x, sz.y) * 0.45:
		_apply_actor_poke(2, local_pos, hero_center)
		return true
	return false


func poke_all() -> void:
	var sz := size
	for i in _actors.size():
		var a: Dictionary = _actors[i]
		var center := Vector2(a["uv"].x * sz.x, a["uv"].y * sz.y)
		var ang := randf_range(-PI * 0.85, -PI * 0.15)
		var hit := center + Vector2(cos(ang), sin(ang)) * float(a["radius"]) * 0.6
		_apply_actor_poke(i, hit, center, i == _actors.size() - 1)


func _apply_actor_poke(idx: int, hit_pos: Vector2, center: Vector2, emit_feedback := true) -> void:
	var a: Dictionary = _actors[idx]
	var dir := (hit_pos - center)
	var ang := atan2(dir.y, dir.x)
	var strength := clampf(jiggle_strength, 0.2, 2.2) * (0.45 if reduce_motion else 1.0)
	a["squash_v"] = 3.2 * strength
	a["tilt_v"] = clampf(-dir.x / maxf(float(a["radius"]), 40.0), -1.0, 1.0) * 4.2 * strength
	a["wave_amp"] = 0.22 * strength
	a["wave_angle"] = ang
	a["wave_t"] = 0.0
	a["happy_timer"] = 0.85

	_ripples.append({
		"pos": hit_pos,
		"r": 10.0,
		"max_r": float(a["radius"]) * 0.95,
		"alpha": 0.9,
	})

	if emit_feedback:
		poke_count += 1
		var msg: String = REACTIONS[(poke_count - 1) % REACTIONS.size()]
		_float_texts.append({
			"pos": hit_pos + Vector2(0.0, -24.0),
			"text": msg.split("!")[0] + "!",
			"alpha": 1.0,
			"vy": -48.0,
		})
		slime_poked.emit(str(a["name"]), poke_count, msg)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var motion_scale := 0.15 if reduce_motion else 1.0
	_time += dt * motion_scale

	var sz := size
	var mouse_local := get_local_mouse_position()

	for i in _actors.size():
		var a: Dictionary = _actors[i]
		# Spring-damper for vertical squash/stretch
		var sq: float = float(a["squash"])
		var sq_v: float = float(a["squash_v"])
		var sq_acc := -68.0 * sq - 6.8 * sq_v
		sq_v += sq_acc * dt
		sq += sq_v * dt
		a["squash"] = sq
		a["squash_v"] = sq_v

		# Spring-damper for horizontal shear/tilt
		var tlt: float = float(a["tilt"])
		var tlt_v: float = float(a["tilt_v"])
		var tlt_acc := -54.0 * tlt - 6.2 * tlt_v
		tlt_v += tlt_acc * dt
		tlt += tlt_v * dt
		a["tilt"] = tlt
		a["tilt_v"] = tlt_v

		a["wave_t"] = float(a["wave_t"]) + dt * 5.2
		a["wave_amp"] = float(a["wave_amp"]) * exp(-3.4 * dt)
		a["happy_timer"] = maxf(0.0, float(a["happy_timer"]) - dt)

		# Smooth cursor eye tracking
		var center := Vector2(a["uv"].x * sz.x, a["uv"].y * sz.y)
		var to_mouse := (mouse_local - center) / maxf(minf(sz.x, sz.y) * 0.45, 1.0)
		if to_mouse.length() > 1.0:
			to_mouse = to_mouse.normalized()
		var cur_eye: Vector2 = a["eye_offset"]
		a["eye_offset"] = cur_eye.lerp(to_mouse, 1.0 - exp(-9.0 * dt))

	# Update ambient bubbles
	for b in _bubbles:
		b["uv"].y -= float(b["speed"]) * dt * motion_scale
		b["wobble"] = float(b["wobble"]) + dt * 1.8 * motion_scale
		b["rot"] = float(b["rot"]) + dt * 0.7 * motion_scale
		if b["uv"].y < -0.06:
			b["uv"].y = 1.06
			b["uv"].x = randf_range(0.08, 0.92)

	# Update ripples
	for idx in range(_ripples.size() - 1, -1, -1):
		var rp: Dictionary = _ripples[idx]
		rp["r"] = lerpf(float(rp["r"]), float(rp["max_r"]), 1.0 - exp(-7.0 * dt))
		rp["alpha"] = float(rp["alpha"]) - dt * 1.9
		if float(rp["alpha"]) <= 0.01:
			_ripples.remove_at(idx)

	# Update floating reaction labels
	for idx in range(_float_texts.size() - 1, -1, -1):
		var ft: Dictionary = _float_texts[idx]
		ft["pos"] = (ft["pos"] as Vector2) + Vector2(0.0, float(ft["vy"]) * dt)
		ft["alpha"] = float(ft["alpha"]) - dt * 1.25
		if float(ft["alpha"]) <= 0.01:
			_float_texts.remove_at(idx)

	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x <= 10.0 or sz.y <= 10.0:
		return
	var scale_f := minf(sz.x / 680.0, sz.y / 620.0)

	_draw_ambient_stage(sz, scale_f)

	# Draw floor shadows first
	for i in _actors.size():
		_draw_slime_shadow(_actors[i], sz, scale_f)

	# Draw slimes back-to-front
	for i in _actors.size():
		_draw_slime_actor(_actors[i], sz, scale_f, i == _actors.size() - 1)

	# Draw poke ripples (golden rune shockwaves)
	for rp in _ripples:
		var col := Color(0.98, 0.84, 0.42, float(rp["alpha"]) * 0.82)
		draw_arc(rp["pos"], float(rp["r"]), 0.0, TAU, 48, col, 2.8, true)

	# Draw floating poke reaction text
	var font := SlimeUITheme.get_bold_font()
	if font == null:
		font = ThemeDB.fallback_font
	for ft in _float_texts:
		var pos: Vector2 = ft["pos"]
		var a: float = float(ft["alpha"])
		var txt: String = ft["text"]
		draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, 5, Color(0.12, 0.06, 0.02, a * 0.90))
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(1.0, 0.88, 0.46, a))


func _draw_ambient_stage(sz: Vector2, scale_f: float) -> void:
	# Fantasy RPG Sanctuary Stone Pedestal & Golden Magic Circle
	var stage_c := Vector2(sz.x * 0.51, sz.y * 0.70)
	var rx := 275.0 * scale_f
	var ry := 68.0 * scale_f
	var rune_gold := Color(0.98, 0.82, 0.36, lerpf(0.55, 0.72, night_mode))
	var stone_dark := Color(0.14, 0.10, 0.07, 0.52)

	# Lower stone plinth rim & top surface
	_draw_ellipse_filled(stage_c + Vector2(0.0, 10.0 * scale_f), rx * 1.03, ry * 1.06, Color(0.08, 0.05, 0.03, 0.58))
	_draw_ellipse_filled(stage_c, rx, ry, stone_dark)
	_draw_ellipse_outline(stage_c, rx, ry, rune_gold, 2.2)
	_draw_ellipse_outline(stage_c, rx * 0.82, ry * 0.82, Color(rune_gold.r, rune_gold.g, rune_gold.b, rune_gold.a * 0.65), 1.4)

	# Rotating 8-point arcane sigil spokes inside the pedestal ellipse
	for k in 8:
		var ang := _time * 0.25 + float(k) * (TAU / 8.0)
		var p_in := stage_c + Vector2(cos(ang) * rx * 0.42, sin(ang) * ry * 0.42)
		var p_out := stage_c + Vector2(cos(ang) * rx * 0.82, sin(ang) * ry * 0.82)
		draw_line(p_in, p_out, Color(rune_gold.r, rune_gold.g, rune_gold.b, rune_gold.a * 0.42), 1.3, true)
		draw_circle(p_out, 3.2 * scale_f, Color(1.0, 0.90, 0.52, rune_gold.a * 0.85))

	# Floating 2D mana orbs & alchemical crystal relics
	for b in _bubbles:
		var p := Vector2(
			b["uv"].x * sz.x + sin(float(b["wobble"])) * 14.0 * scale_f,
			b["uv"].y * sz.y
		)
		var r: float = float(b["r"]) * scale_f
		if bool(b["is_cube"]):
			# Floating golden/emerald relic diamond crystal
			var rot: float = float(b["rot"])
			var h: float = float(b["hue"])
			var c_col := Color(0.98, 0.82, 0.36, 0.36) if h < 0.5 else Color(0.42, 0.94, 0.72, 0.36)
			var pts := PackedVector2Array()
			for k in 4:
				var a := rot + float(k) * PI * 0.5
				var rad_m := 1.35 if k % 2 == 0 else 0.85
				pts.append(p + Vector2(cos(a), sin(a)) * r * rad_m)
			draw_colored_polygon(pts, c_col)
			pts.append(pts[0])
			draw_polyline(pts, Color(1.0, 0.94, 0.68, 0.65), 1.5, true)
		else:
			var b_col := Color(0.98, 0.88, 0.52, lerpf(0.24, 0.36, night_mode))
			draw_circle(p, r, Color(b_col.r, b_col.g, b_col.b, b_col.a * 0.35))
			draw_arc(p, r, 0.0, TAU, 24, b_col, 1.3, true)
			draw_circle(p + Vector2(-r * 0.32, -r * 0.32), r * 0.22, Color(1.0, 0.98, 0.88, b_col.a * 0.95))


func _draw_slime_shadow(a: Dictionary, sz: Vector2, scale_f: float) -> void:
	var base_r: float = float(a["radius"]) * scale_f
	var phase: float = float(a["phase"])
	var sway_x := sin(_time * 1.1 + phase) * 8.0 * scale_f if phase > 0.0 else 0.0
	var foot_pos := Vector2(a["uv"].x * sz.x + sway_x, a["uv"].y * sz.y + base_r * 0.72)
	var sq: float = float(a["squash"])
	var sh_rx := base_r * (1.14 + sq * 0.16)
	var sh_ry := base_r * 0.27 * (1.0 + sq * 0.08)
	_draw_ellipse_filled(foot_pos + Vector2(0.0, 4.0 * scale_f), sh_rx * 1.12, sh_ry * 1.15, Color(0.02, 0.06, 0.11, 0.22))
	_draw_ellipse_filled(foot_pos, sh_rx, sh_ry, Color(0.02, 0.06, 0.12, 0.46))


func _draw_slime_actor(a: Dictionary, sz: Vector2, scale_f: float, is_hero: bool) -> void:
	var base_r: float = float(a["radius"]) * scale_f
	var phase: float = float(a["phase"])
	var sway_x := sin(_time * 1.1 + phase) * 8.0 * scale_f if not is_hero else 0.0
	var center := Vector2(a["uv"].x * sz.x + sway_x, a["uv"].y * sz.y)
	var foot_y := center.y + base_r * 0.72

	var excited_boost := 1.85 if mood_state == MoodState.EXCITED else 1.0
	var breath := sin(_time * 2.4 * excited_boost + phase) * 0.028 * clampf(jiggle_strength, 0.2, 2.2)
	var droop := 0.10 if mood_state == MoodState.SLEEPY else 0.0
	var sq: float = float(a["squash"]) + breath + droop
	var tilt: float = float(a["tilt"]) + sin(_time * 1.7 + phase) * 0.025 * excited_boost
	var wave_amp: float = float(a["wave_amp"])
	var wave_ang: float = float(a["wave_angle"])
	var wave_t: float = float(a["wave_t"])

	# Build 2D jelly silhouette contour (64 smooth samples)
	const N := 64
	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	var belly_pts := PackedVector2Array()
	outer_pts.resize(N)
	inner_pts.resize(N)
	belly_pts.resize(N)

	for i in N:
		var theta := TAU * float(i) / float(N)
		var cs := cos(theta)
		var sn := sin(theta) # +1 is bottom, -1 is top in screen coords

		# Authentic slime profile: wider lower belly, flat-ish cushioned base, dome top
		var h01 := clampf((1.0 - sn) * 0.5, 0.0, 1.0) # 0 at bottom, 1 at top
		var belly_bulge := 1.0 + sin(h01 * PI) * 0.14 + pow(1.0 - h01, 1.5) * 0.22
		var rx := base_r * belly_bulge * (1.0 + sq * 0.19)
		var ry := base_r * 0.84 * (1.0 - sq * 0.16)

		# Directional poke ripple harmonics around the perimeter
		var d_ang := angle_difference(theta, wave_ang)
		var ripple := wave_amp * cos(d_ang * 3.0 - wave_t * 3.5) * exp(-absf(d_ang) * 0.7)
		var harmonic := sin(theta * 4.0 + _time * 3.2 + phase) * 0.012 * jiggle_strength * (0.2 if reduce_motion else 1.0)
		var r_mod := 1.0 + ripple + harmonic

		var px := cs * rx * r_mod + h01 * tilt * base_r * 0.22
		var py := sn * ry * r_mod

		# Cushion flat-bottom contact with floor
		var raw_y := center.y + py
		if raw_y > foot_y - base_r * 0.08:
			var over := (raw_y - (foot_y - base_r * 0.08)) / (base_r * 0.25)
			raw_y = (foot_y - base_r * 0.08) + tanh(over) * base_r * 0.08

		var pt := Vector2(center.x + px, raw_y)
		outer_pts[i] = pt
		var inner_c := Vector2(center.x + tilt * base_r * 0.08, center.y + base_r * 0.04)
		inner_pts[i] = inner_c.lerp(pt, 0.84)
		belly_pts[i] = (inner_c + Vector2(0.0, base_r * 0.14)).lerp(pt, 0.62)

	# Palette colors (Day vs Bioluminescent Night)
	var col_deep := Color(0.18, 0.54, 0.86, 0.86).lerp(Color(0.07, 0.30, 0.62, 0.90), night_mode)
	var col_mid := Color(0.42, 0.80, 0.98, 0.72).lerp(Color(0.18, 0.62, 0.92, 0.76), night_mode)
	var col_caustic := Color(0.28, 0.96, 0.72, 0.42).lerp(Color(0.20, 0.98, 0.64, 0.56), night_mode)
	var col_rim := Color(0.84, 0.98, 1.0, 0.92).lerp(Color(0.56, 0.95, 1.0, 0.96), night_mode)
	var col_outline := Color(0.11, 0.28, 0.46, 0.90).lerp(Color(0.04, 0.14, 0.28, 0.95), night_mode)

	# 1. Outer deep translucent jelly body
	draw_colored_polygon(outer_pts, col_deep)
	# 2. Mid refractive body
	draw_colored_polygon(inner_pts, col_mid)
	# 3. Caustic lower emerald-cyan glow
	draw_colored_polygon(belly_pts, col_caustic)

	# 4. Internal floating micro-bubbles
	var b_list: Array = a["inner_bubbles"]
	for ib in b_list:
		var b_ang: float = float(ib["ang"]) + _time * float(ib["speed"]) * 0.25
		var b_dist: float = float(ib["dist"]) * base_r * 0.68
		var bp := center + Vector2(cos(b_ang) * b_dist, sin(b_ang) * b_dist * 0.65)
		var br: float = float(ib["r"]) * base_r
		draw_circle(bp, br, Color(0.86, 1.0, 0.96, 0.28))
		draw_arc(bp, br, 0.0, TAU, 16, Color(0.92, 1.0, 0.98, 0.48), 1.1, true)

	# 5. Inner Glowing Core Sphere (visualizing the signature Core-Sphere mechanic!)
	if show_core_xray:
		var core_r := base_r * 0.21
		var core_pos := Vector2(center.x + tilt * base_r * 0.06, foot_y - core_r - base_r * 0.06)
		var pulse := 1.0 + sin(_time * 4.0 + phase) * 0.06
		draw_circle(core_pos, core_r * 1.65 * pulse, Color(0.22, 0.92, 1.0, 0.18))
		draw_circle(core_pos, core_r * 1.22 * pulse, Color(0.28, 0.96, 0.88, 0.32))
		draw_circle(core_pos, core_r, Color(0.16, 0.68, 0.98, 0.88))
		draw_circle(core_pos + Vector2(-core_r * 0.28, -core_r * 0.28), core_r * 0.35, Color(0.88, 0.99, 1.0, 0.85))
		draw_arc(core_pos, core_r * 1.08, 0.0, TAU, 32, Color(0.68, 0.98, 1.0, 0.85), 1.6, true)

	# 6. Top anime specular gloss highlights
	var spec_pos := center + Vector2(-base_r * 0.36 + tilt * 8.0, -base_r * 0.36 + sq * base_r * 0.08)
	_draw_rotated_ellipse(spec_pos, base_r * 0.22, base_r * 0.095, -0.52, Color(1.0, 1.0, 1.0, 0.68))
	var spec2_pos := center + Vector2(-base_r * 0.14 + tilt * 6.0, -base_r * 0.50 + sq * base_r * 0.08)
	draw_circle(spec2_pos, base_r * 0.045, Color(1.0, 1.0, 1.0, 0.62))

	# 7. Crisp rim highlight & outer contour line
	var closed_outer := outer_pts.duplicate()
	closed_outer.append(outer_pts[0])
	draw_polyline(closed_outer, col_rim, 3.2 * scale_f if is_hero else 2.2 * scale_f, true)
	draw_polyline(closed_outer, col_outline, 1.4 * scale_f, true)

	# 8. Expressive Anime Eyes (cursor-tracking + blinking + happy squints)
	_draw_slime_eyes(a, center, base_r, sq, tilt, is_hero)


func _draw_slime_eyes(a: Dictionary, center: Vector2, base_r: float, sq: float, tilt: float, is_hero: bool) -> void:
	var eye_off: Vector2 = a["eye_offset"]
	var phase: float = float(a["phase"])
	var happy_t: float = float(a["happy_timer"])
	var blink_cycle := fmod(_time + phase * 1.37, 3.9)
	var blink := 0.08 if blink_cycle > 3.74 else 1.0
	if mood_state == MoodState.SLEEPY:
		blink = minf(blink, 0.42)

	var eye_sep := base_r * 0.30
	var eye_y := center.y - base_r * 0.05 + sq * base_r * 0.08 + eye_off.y * base_r * 0.10
	var eye_x_shift := tilt * base_r * 0.12 + eye_off.x * base_r * 0.16
	var ew := base_r * 0.095
	var eh := base_r * 0.155 * blink

	for side in [-1.0, 1.0]:
		var ep := Vector2(center.x + side * eye_sep + eye_x_shift, eye_y)
		if happy_t > 0.01 or (is_hero and mood_state == MoodState.EXCITED and sq > 0.06):
			# Cute happy anime arc `^`
			draw_arc(ep + Vector2(0.0, base_r * 0.04), ew * 1.15, PI * 1.12, PI * 1.88, 20, Color(0.04, 0.12, 0.22, 0.65), 4.5, true)
			draw_arc(ep + Vector2(0.0, base_r * 0.04), ew * 1.15, PI * 1.12, PI * 1.88, 20, Color(1.0, 1.0, 1.0, 0.98), 3.0, true)
		else:
			# Soft shadow backing + luminous white anime eye oval
			_draw_ellipse_filled(ep + Vector2(0.0, 2.0), ew * 1.12, eh * 1.10, Color(0.05, 0.16, 0.28, 0.48))
			_draw_ellipse_filled(ep, ew, eh, Color(0.98, 0.99, 1.0, 0.97))
			if blink > 0.35:
				var shine := ep + Vector2(-ew * 0.24, -eh * 0.28)
				draw_circle(shine, ew * 0.26, Color(0.72, 0.96, 1.0, 0.95))


func _draw_ellipse_filled(c: Vector2, rx: float, ry: float, col: Color) -> void:
	const SEG := 36
	var pts := PackedVector2Array()
	pts.resize(SEG)
	for i in SEG:
		var a := TAU * float(i) / float(SEG)
		pts[i] = c + Vector2(cos(a) * rx, sin(a) * ry)
	draw_colored_polygon(pts, col)


func _draw_ellipse_outline(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	const SEG := 40
	var pts := PackedVector2Array()
	pts.resize(SEG + 1)
	for i in SEG + 1:
		var a := TAU * float(i) / float(SEG)
		pts[i] = c + Vector2(cos(a) * rx, sin(a) * ry)
	draw_polyline(pts, col, width, true)


func _draw_rotated_ellipse(c: Vector2, rx: float, ry: float, rot: float, col: Color) -> void:
	const SEG := 28
	var pts := PackedVector2Array()
	pts.resize(SEG)
	var cr := cos(rot)
	var sr := sin(rot)
	for i in SEG:
		var a := TAU * float(i) / float(SEG)
		var lx := cos(a) * rx
		var ly := sin(a) * ry
		pts[i] = c + Vector2(lx * cr - ly * sr, lx * sr + ly * cr)
	draw_colored_polygon(pts, col)

