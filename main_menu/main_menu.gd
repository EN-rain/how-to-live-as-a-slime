class_name MainMenu
extends Node3D
## Interactive 3D Main Menu for "How to Live as a Slime".
##
## Combines a live 3D showcase stage (refractive hero slime + companion clones +
## studio grid floor with blob shadows + geometric props) and a glassmorphic HUD-style
## menu interface matching the in-game visual language.

@export_file("*.tscn") var game_scene_path := "res://scenes/main.tscn"

const FLOOR_Y := -1.2
const REF_RADIUS := 1.6
const MELT := 0.28
const REST_K := 0.86 - MELT * 0.22
const REST_HALF_HEIGHT := REF_RADIUS * REST_K
const REST_MAX_RADIUS := 2.0

const DAY_BG := Color(0.337, 0.471, 0.565, 1.0)
const NIGHT_BG := Color(0.065, 0.115, 0.195, 1.0)
const DAY_AMBIENT := Color(0.859, 0.918, 0.996, 1.0)
const NIGHT_AMBIENT := Color(0.28, 0.48, 0.78, 1.0)

const MOOD_REACTIONS := [
	"Boing! Jelly ripples active",
	"Squish! Core sphere resonating",
	"Wobble! Surface tension 100%",
	"Splat! Refractive dispersion!",
	"Jiggle! Ready to absorb cubes!"
]

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _floor: MeshInstance3D = $Floor
@onready var _props_root: Node3D = $StageProps

@onready var _hero_slime: MeshInstance3D = $SlimeStage/HeroSlime
@onready var _follower_slime: MeshInstance3D = $SlimeStage/FollowerSlime
@onready var _roamer_slime: MeshInstance3D = $SlimeStage/RoamerSlime

@onready var _play_btn: Button = $MenuLayer/MenuRoot/MainLayout/LeftColumn/ButtonStack/PlayButton
@onready var _how_to_play_btn: Button = $MenuLayer/MenuRoot/MainLayout/LeftColumn/ButtonStack/HowToPlayButton
@onready var _settings_btn: Button = $MenuLayer/MenuRoot/MainLayout/LeftColumn/ButtonStack/SettingsButton
@onready var _atmosphere_btn: Button = $MenuLayer/MenuRoot/MainLayout/LeftColumn/ButtonStack/AtmosphereButton
@onready var _poke_btn: Button = $MenuLayer/MenuRoot/MainLayout/LeftColumn/ButtonStack/PokeButton
@onready var _quit_btn: Button = $MenuLayer/MenuRoot/MainLayout/LeftColumn/ButtonStack/QuitButton

@onready var _controls_card: PanelContainer = $MenuLayer/MenuRoot/MainLayout/RightColumn/ControlsCard
@onready var _settings_card: PanelContainer = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard
@onready var _close_controls_btn: Button = $MenuLayer/MenuRoot/MainLayout/RightColumn/ControlsCard/CardMargin/CardVBox/HeaderRow/CloseControlsButton
@onready var _close_settings_btn: Button = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard/CardMargin/CardVBox/HeaderRow/CloseSettingsButton

@onready var _fullscreen_check: CheckButton = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard/CardMargin/CardVBox/FullscreenCheck
@onready var _vsync_check: CheckButton = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard/CardMargin/CardVBox/VsyncCheck
@onready var _night_check: CheckButton = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard/CardMargin/CardVBox/NightCheck
@onready var _msaa_option: OptionButton = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard/CardMargin/CardVBox/MsaaRow/MsaaOption
@onready var _jiggle_slider: HSlider = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard/CardMargin/CardVBox/JiggleRow/JiggleSlider
@onready var _jiggle_value_label: Label = $MenuLayer/MenuRoot/MainLayout/RightColumn/SettingsCard/CardMargin/CardVBox/JiggleRow/JiggleValue

@onready var _status_label: Label = $MenuLayer/MenuRoot/TopBar/StatusPill/StatusLabel
@onready var _fade_rect: ColorRect = $MenuLayer/MenuRoot/FadeOverlay

var _time := 0.0
var _night_mode := 0.0
var _night_target := 0.0
var _jiggle_strength := 1.0
var _poke_count := 0
var _play_hovered := false
var _transitioning := false

var _mouse_norm := Vector2.ZERO
var _cam_base_pos := Vector3(0.55, 0.95, 6.35)
var _cam_look_target := Vector3(0.45, 0.05, 0.0)

var _slime_actors: Array[Dictionary] = []
var _floating_cubes: Array[MeshInstance3D] = []
var _floor_mat: ShaderMaterial
var _env_res: Environment


func _ready() -> void:
	if _world_env and _world_env.environment:
		_env_res = _world_env.environment.duplicate() as Environment
		_world_env.environment = _env_res
	if _floor and _floor.material_override is ShaderMaterial:
		_floor_mat = _floor.material_override.duplicate() as ShaderMaterial
		_floor.material_override = _floor_mat

	_setup_slime_actor(_hero_slime, 1.08, -0.22, 0.0)
	_setup_slime_actor(_follower_slime, 0.56, 0.32, 1.35)
	_setup_slime_actor(_roamer_slime, 0.44, -0.58, 2.75)

	if _props_root:
		for child in _props_root.get_children():
			if child is MeshInstance3D:
				_floating_cubes.append(child)

	_connect_ui()
	_sync_settings_ui()
	_update_floor_blobs()
	_play_intro_fade()


func _setup_slime_actor(mesh_inst: MeshInstance3D, actor_scale: float, base_facing: float, phase_offset: float) -> void:
	if mesh_inst == null:
		return
	var mat: ShaderMaterial = null
	if mesh_inst.material_override is ShaderMaterial:
		mat = mesh_inst.material_override.duplicate() as ShaderMaterial
		mesh_inst.material_override = mat

	var foot_y := FLOOR_Y + 0.02
	var rest_y := foot_y + REST_HALF_HEIGHT * actor_scale
	mesh_inst.position.y = rest_y
	mesh_inst.scale = Vector3.ONE * actor_scale

	if mat:
		mat.set_shader_parameter("uMelt", MELT)
		mat.set_shader_parameter("uRefRadius", REF_RADIUS)
		mat.set_shader_parameter("uFacing", base_facing)
		mat.set_shader_parameter("uJiggleStrength", _jiggle_strength)
		mat.set_shader_parameter("uImpulseTime", 10.0)
		mat.set_shader_parameter("uImpulse2Time", 10.0)
		mat.set_shader_parameter("uLiquid", 0.0)
		mat.set_shader_parameter("uLiquidHeight", 1.0)
		mat.set_shader_parameter("uLiquidSpread", 1.0)

	_slime_actors.append({
		"node": mesh_inst,
		"mat": mat,
		"base_pos": mesh_inst.position,
		"scale": actor_scale,
		"base_facing": base_facing,
		"facing": base_facing,
		"phase": phase_offset,
		"impulse_t": 10.0,
		"impulse2_t": 10.0,
		"crawl": phase_offset,
	})


func _connect_ui() -> void:
	var buttons: Array[Button] = [
		_play_btn, _how_to_play_btn, _settings_btn,
		_atmosphere_btn, _poke_btn, _quit_btn,
		_close_controls_btn, _close_settings_btn
	]
	for btn in buttons:
		if btn == null:
			continue
		btn.mouse_entered.connect(_on_button_hover.bind(btn, true))
		btn.mouse_exited.connect(_on_button_hover.bind(btn, false))

	if _play_btn:
		_play_btn.pressed.connect(_on_play_pressed)
		_play_btn.mouse_entered.connect(func(): _play_hovered = true)
		_play_btn.mouse_exited.connect(func(): _play_hovered = false)
	if _how_to_play_btn:
		_how_to_play_btn.pressed.connect(_toggle_controls_card)
	if _settings_btn:
		_settings_btn.pressed.connect(_toggle_settings_card)
	if _atmosphere_btn:
		_atmosphere_btn.pressed.connect(_toggle_atmosphere)
	if _poke_btn:
		_poke_btn.pressed.connect(_poke_all_slimes)
	if _quit_btn:
		_quit_btn.pressed.connect(_on_quit_pressed)
	if _close_controls_btn:
		_close_controls_btn.pressed.connect(func(): _set_card_visible(_controls_card, false))
	if _close_settings_btn:
		_close_settings_btn.pressed.connect(func(): _set_card_visible(_settings_card, false))

	if _fullscreen_check:
		_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	if _vsync_check:
		_vsync_check.toggled.connect(_on_vsync_toggled)
	if _night_check:
		_night_check.toggled.connect(_on_night_check_toggled)
	if _msaa_option:
		_msaa_option.item_selected.connect(_on_msaa_selected)
	if _jiggle_slider:
		_jiggle_slider.value_changed.connect(_on_jiggle_changed)


func _sync_settings_ui() -> void:
	if _fullscreen_check:
		var mode := DisplayServer.window_get_mode()
		_fullscreen_check.set_pressed_no_signal(mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	if _vsync_check:
		var vs := DisplayServer.window_get_vsync_mode()
		_vsync_check.set_pressed_no_signal(vs != DisplayServer.VSYNC_DISABLED)
	if _msaa_option:
		_msaa_option.clear()
		_msaa_option.add_item("Off", Viewport.MSAA_DISABLED)
		_msaa_option.add_item("2× MSAA", Viewport.MSAA_2X)
		_msaa_option.add_item("4× MSAA", Viewport.MSAA_4X)
		_msaa_option.add_item("8× MSAA", Viewport.MSAA_8X)
		var cur_msaa := get_viewport().msaa_3d
		_msaa_option.select(clampi(int(cur_msaa), 0, 3))
	if _jiggle_slider:
		_jiggle_slider.set_value_no_signal(_jiggle_strength)
	if _jiggle_value_label:
		_jiggle_value_label.text = "%.1f×" % _jiggle_strength


func _play_intro_fade() -> void:
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	_fade_rect.color = Color(0.06, 0.11, 0.17, 1.0)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _fade_rect.visible = false)


func _process(delta: float) -> void:
	_time += delta
	_update_mouse_tracking(delta)
	_update_camera_sway(delta)
	_update_slimes(delta)
	_update_atmosphere(delta)
	_update_stage_props(delta)


func _update_mouse_tracking(dt: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var rect := vp.get_visible_rect().size
	if rect.x <= 1.0 or rect.y <= 1.0:
		return
	var mp := vp.get_mouse_position()
	var target_norm := Vector2(
		clampf((mp.x / rect.x) * 2.0 - 1.0, -1.0, 1.0),
		clampf((mp.y / rect.y) * 2.0 - 1.0, -1.0, 1.0)
	)
	_mouse_norm = _mouse_norm.lerp(target_norm, 1.0 - exp(-6.0 * dt))


func _update_camera_sway(_dt: float) -> void:
	if _camera == null:
		return
	var orbit_x := sin(_time * 0.35) * 0.28 + _mouse_norm.x * 0.32
	var orbit_y := cos(_time * 0.28) * 0.08 - _mouse_norm.y * 0.18
	var cam_pos := _cam_base_pos + Vector3(orbit_x, orbit_y, sin(_time * 0.22) * 0.18)
	_camera.global_position = cam_pos
	_camera.look_at(_cam_look_target + Vector3(_mouse_norm.x * 0.12, -_mouse_norm.y * 0.08, 0.0), Vector3.UP)


func _update_slimes(dt: float) -> void:
	for i in _slime_actors.size():
		var a: Dictionary = _slime_actors[i]
		var mat: ShaderMaterial = a["mat"]
		var node: MeshInstance3D = a["node"]
		if mat == null or node == null:
			continue

		a["impulse_t"] = float(a["impulse_t"]) + dt
		a["impulse2_t"] = float(a["impulse2_t"]) + dt

		var crawl_speed := 1.6 if (i == 0 and _play_hovered) else (0.65 if i > 0 else 0.38)
		a["crawl"] = float(a["crawl"]) + dt * crawl_speed * 2.4

		# Gaze follows the mouse cursor gently
		var base_f: float = a["base_facing"]
		var target_facing := base_f + _mouse_norm.x * 0.38
		var cur_facing: float = lerpf(float(a["facing"]), target_facing, 1.0 - exp(-7.0 * dt))
		a["facing"] = cur_facing

		var phase: float = a["phase"]
		var blink_cycle := fmod(_time + phase * 1.3, 4.0)
		var blink := 0.12 if blink_cycle > 3.84 else 1.0

		var move_amt := 0.42 if (i == 0 and _play_hovered) else (0.18 if i > 0 else 0.08)
		var ripple := 0.14 + move_amt * 0.35

		mat.set_shader_parameter("uImpulseTime", a["impulse_t"])
		mat.set_shader_parameter("uImpulse2Time", a["impulse2_t"])
		mat.set_shader_parameter("uCrawl", a["crawl"])
		mat.set_shader_parameter("uMoveAmt", move_amt)
		mat.set_shader_parameter("uMoveDir", Vector3(sin(cur_facing), 0.0, cos(cur_facing)))
		mat.set_shader_parameter("uFacing", cur_facing)
		mat.set_shader_parameter("uEyeElevation", clampf(0.12 - _mouse_norm.y * 0.06, 0.04, 0.24))
		mat.set_shader_parameter("uBlink", blink)
		mat.set_shader_parameter("uRippleIntensity", ripple)
		mat.set_shader_parameter("uNightMode", _night_mode)
		mat.set_shader_parameter("uJiggleStrength", _jiggle_strength)

		# Subtle companion wandering sway on the stage
		if i > 0:
			var base_p: Vector3 = a["base_pos"]
			var sway_x := sin(_time * 0.8 + phase) * 0.14
			var sway_z := cos(_time * 0.65 + phase) * 0.14
			node.position.x = base_p.x + sway_x
			node.position.z = base_p.z + sway_z

	_update_floor_blobs()


func _update_floor_blobs() -> void:
	if _floor_mat == null:
		return
	var pos_arr := PackedVector3Array()
	var scale_arr := PackedFloat32Array()
	pos_arr.resize(8)
	scale_arr.resize(8)
	for i in 8:
		if i < _slime_actors.size():
			var node: MeshInstance3D = _slime_actors[i]["node"]
			pos_arr[i] = node.global_position
			scale_arr[i] = float(_slime_actors[i]["scale"])
		else:
			pos_arr[i] = Vector3.ZERO
			scale_arr[i] = 0.0
	_floor_mat.set_shader_parameter("uBlobCount", _slime_actors.size())
	_floor_mat.set_shader_parameter("uBlobPos", pos_arr)
	_floor_mat.set_shader_parameter("uBlobScale", scale_arr)


func _update_atmosphere(dt: float) -> void:
	if absf(_night_mode - _night_target) < 1e-4:
		return
	_night_mode = lerpf(_night_mode, _night_target, 1.0 - exp(-5.0 * dt))
	var bg := DAY_BG.lerp(NIGHT_BG, _night_mode)
	var amb := DAY_AMBIENT.lerp(NIGHT_AMBIENT, _night_mode)
	var amb_energy := lerpf(0.85, 0.42, _night_mode)
	var sun_energy := lerpf(0.90, 0.32, _night_mode)

	if _env_res:
		_env_res.background_color = bg
		_env_res.ambient_light_color = amb
		_env_res.ambient_light_energy = amb_energy
		_env_res.fog_light_color = bg
	if _sun:
		_sun.light_energy = sun_energy
	if _floor_mat:
		_floor_mat.set_shader_parameter("uFogColor", bg)
		_floor_mat.set_shader_parameter("uAmbientColor", amb)
		_floor_mat.set_shader_parameter("uAmbientEnergy", amb_energy)
		_floor_mat.set_shader_parameter("uLightEnergy", sun_energy)


func _update_stage_props(dt: float) -> void:
	for i in _floating_cubes.size():
		var c := _floating_cubes[i]
		if c != null and is_instance_valid(c):
			c.rotation.y += dt * (0.12 if i % 2 == 0 else -0.09)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_poke_at_screen(mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_try_poke_at_screen(st.position)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ke := event as InputEventKey
	match ke.keycode:
		KEY_ESCAPE:
			if _controls_card and _controls_card.visible:
				_set_card_visible(_controls_card, false)
				get_viewport().set_input_as_handled()
			elif _settings_card and _settings_card.visible:
				_set_card_visible(_settings_card, false)
				get_viewport().set_input_as_handled()
		KEY_H:
			_toggle_controls_card()
			get_viewport().set_input_as_handled()
		KEY_N:
			_toggle_atmosphere()
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			_poke_all_slimes()
			get_viewport().set_input_as_handled()


func _try_poke_at_screen(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)

	var best_idx := -1
	var best_t := INF
	var best_hit := Vector3.ZERO

	for i in _slime_actors.size():
		var a: Dictionary = _slime_actors[i]
		var node: MeshInstance3D = a["node"]
		var s: float = a["scale"]
		var center := node.global_position
		var rx := REST_MAX_RADIUS * s
		var ry := REST_HALF_HEIGHT * s
		var oc := origin - center
		var oa := Vector3(oc.x / rx, oc.y / ry, oc.z / rx)
		var da := Vector3(dir.x / rx, dir.y / ry, dir.z / rx)
		var qa := da.dot(da)
		var qb := oa.dot(da)
		var qc := oa.dot(oa) - 1.0
		var disc := qb * qb - qa * qc
		if disc < 0.0:
			continue
		var sq := sqrt(disc)
		var t := (-qb - sq) / maxf(qa, 1e-6)
		if t < 0.0:
			t = (-qb + sq) / maxf(qa, 1e-6)
		if t > 0.0 and t < best_t:
			best_t = t
			best_idx = i
			best_hit = origin + dir * t

	if best_idx >= 0:
		var actor: Dictionary = _slime_actors[best_idx]
		var node: MeshInstance3D = actor["node"]
		var s: float = actor["scale"]
		var local_pt := ((best_hit - node.global_position) / maxf(s, 1e-4)).normalized() * REF_RADIUS
		var push := (best_hit - _camera.global_position).normalized() * 0.62
		push.y -= 0.25
		_trigger_actor_poke(best_idx, local_pt, push)
		_record_poke()


func _trigger_actor_poke(idx: int, local_point: Vector3, impulse: Vector3) -> void:
	if idx < 0 or idx >= _slime_actors.size():
		return
	var a: Dictionary = _slime_actors[idx]
	var mat: ShaderMaterial = a["mat"]
	if mat == null:
		return
	a["impulse_t"] = 0.001
	a["impulse2_t"] = 0.001
	mat.set_shader_parameter("uImpulsePos", local_point)
	mat.set_shader_parameter("uImpulseVector", impulse)
	mat.set_shader_parameter("uImpulse2Pos", -local_point * 0.85)
	mat.set_shader_parameter("uImpulse2Vector", -impulse * 0.45)


func _poke_all_slimes() -> void:
	for i in _slime_actors.size():
		var ang := randf() * TAU
		var local_pt := Vector3(cos(ang), randf_range(0.1, 0.55), sin(ang)).normalized() * REF_RADIUS
		var impulse := Vector3(-cos(ang) * 0.58, -0.28, -sin(ang) * 0.58)
		_trigger_actor_poke(i, local_pt, impulse)
	_record_poke()


func _record_poke() -> void:
	_poke_count += 1
	if _status_label:
		var msg: String = MOOD_REACTIONS[(_poke_count - 1) % MOOD_REACTIONS.size()]
		_status_label.text = "%s  ·  Pokes: %d" % [msg, _poke_count]


func _on_button_hover(btn: Button, entered: bool) -> void:
	if btn == null:
		return
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween()
	var target_scale := Vector2(1.025, 1.025) if entered else Vector2.ONE
	tw.tween_property(btn, "scale", target_scale, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_card_visible(card: PanelContainer, show_card: bool) -> void:
	if card == null:
		return
	if show_card:
		if card == _controls_card and _settings_card:
			_settings_card.visible = false
		elif card == _settings_card and _controls_card:
			_controls_card.visible = false
		card.visible = true
		card.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(card, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		card.visible = false


func _toggle_controls_card() -> void:
	if _controls_card:
		_set_card_visible(_controls_card, not _controls_card.visible)


func _toggle_settings_card() -> void:
	if _settings_card:
		_set_card_visible(_settings_card, not _settings_card.visible)


func _toggle_atmosphere() -> void:
	_night_target = 0.0 if _night_target > 0.5 else 1.0
	var is_night := _night_target > 0.5
	if _atmosphere_btn:
		_atmosphere_btn.text = "MOOD: BIOLUMINESCENT NIGHT" if is_night else "MOOD: STUDIO DAY"
	if _night_check:
		_night_check.set_pressed_no_signal(is_night)
	_poke_all_slimes()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_vsync_toggled(pressed: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if pressed else DisplayServer.VSYNC_DISABLED
	)


func _on_night_check_toggled(pressed: bool) -> void:
	_night_target = 1.0 if pressed else 0.0
	if _atmosphere_btn:
		_atmosphere_btn.text = "MOOD: BIOLUMINESCENT NIGHT" if pressed else "MOOD: STUDIO DAY"


func _on_msaa_selected(index: int) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.msaa_3d = clampi(index, Viewport.MSAA_DISABLED, Viewport.MSAA_8X) as Viewport.MSAA


func _on_jiggle_changed(value: float) -> void:
	_jiggle_strength = value
	if _jiggle_value_label:
		_jiggle_value_label.text = "%.1f×" % value


func _on_play_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_poke_all_slimes()
	if _fade_rect:
		_fade_rect.visible = true
		_fade_rect.color = Color(0.06, 0.11, 0.17, 0.0)
		var tw := create_tween()
		tw.tween_property(_fade_rect, "color:a", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): get_tree().change_scene_to_file(game_scene_path))
	else:
		get_tree().change_scene_to_file(game_scene_path)


func _on_quit_pressed() -> void:
	get_tree().quit()
