class_name WorldTimeWeather
extends Node
## Drives 24-hour orbital Sun/Moon cycle, dynamic Rain weather FSM,
## Godot Global Shader Uniforms, village lanterns, camera rain streaks & audio.

enum WeatherState {
	CLEAR = 0,
	CLOUDY = 1,
	LIGHT_RAIN = 2,
	HEAVY_RAIN = 3,
	CLEARING = 4,
}

@export var cycle_duration_sec: float = 720.0  # 12 real minutes = 24 in-game hours
@export_range(0.0, 1.0) var time_of_day: float = 0.42  # Starts ~10:05 AM bright morning
@export var paused_time: bool = false
@export var time_mode: String = "dynamic"  # dynamic | day | night | dawn | dusk

var weather_state: WeatherState = WeatherState.CLEAR
var weather_timer: float = 115.0
var weather_wetness: float = 0.0
var rain_intensity: float = 0.0
var wind_strength: float = 0.22
var night_light_strength: float = 0.0
var is_night: bool = false

var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _cave_atm: Node
var _village_root: Node
var _terrain: Node
var _settings: Node
var _rain_particles: GPUParticles3D
var _rain_audio: AudioStreamPlayer
var _last_village_push: float = -1.0
var _last_wetness_push: float = -1.0
var _rain_streak_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("world_time_weather")
	var parent := get_parent()
	if parent != null:
		_sun = parent.get_node_or_null("Sun") as DirectionalLight3D
		_world_env = parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
		_terrain = parent.get_node_or_null("TerrainScene")
	_settings = get_node_or_null("/root/SettingsManager")
	if _settings != null:
		var night_pref: bool = bool(_settings.get_value("gameplay", "night_mode", false))
		var saved_mode: String = str(_settings.get_value("gameplay", "time_mode", "night" if night_pref else "dynamic"))
		set_time_mode(saved_mode)
		if _settings.has_signal("settings_changed"):
			_settings.connect("settings_changed", Callable(self, "_on_settings_changed"))

	_apply_sky_shader()
	_build_rain_particles()
	_build_rain_audio()
	_resolve_scene_refs()
	_apply_lighting_and_globals(true)


func _on_settings_changed(_category: String, key: String, value: Variant) -> void:
	if key == "night_mode":
		set_time_mode("night" if bool(value) else "dynamic")
	elif key == "time_mode":
		set_time_mode(str(value))
	elif key == "quality_preset":
		_update_rain_quality_budget()
	elif key == "sfx_volume" or key == "master_volume" or key == "muted":
		_update_rain_audio(0.0)


func set_time_mode(mode: String) -> void:
	time_mode = mode
	match mode:
		"day":
			time_of_day = 0.45
			paused_time = true
		"dawn":
			time_of_day = 0.26
			paused_time = true
		"dusk":
			time_of_day = 0.74
			paused_time = true
		"night":
			time_of_day = 0.04
			paused_time = true
		_:
			paused_time = false
	_apply_lighting_and_globals(true)


func set_time_of_day(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	_apply_lighting_and_globals(true)


func set_weather_state(state: int, duration: float = 95.0) -> void:
	weather_state = clampi(state, 0, 4) as WeatherState
	weather_timer = maxf(duration, 10.0)
	_apply_lighting_and_globals(true)


func get_hour_minute_string() -> String:
	var total_mins := int(round(fposmod(time_of_day, 1.0) * 1440.0)) % 1440
	var hh := int(total_mins / 60)
	var mm := total_mins % 60
	return "%02d:%02d" % [hh, mm]


func get_weather_label() -> String:
	match weather_state:
		WeatherState.CLEAR:
			return "Clear"
		WeatherState.CLOUDY:
			return "Cloudy"
		WeatherState.LIGHT_RAIN:
			return "Rain"
		WeatherState.HEAVY_RAIN:
			return "Storm"
		WeatherState.CLEARING:
			return "Clearing"
	return "Clear"


func get_phase_label() -> String:
	var h := fposmod(time_of_day, 1.0) * 24.0
	if h >= 5.0 and h < 7.5:
		return "Dawn"
	if h >= 7.5 and h < 17.0:
		return "Day"
	if h >= 17.0 and h < 19.5:
		return "Dusk"
	return "Night"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_T:
			# Advance time by 3 hours for quick inspection/gameplay preview
			set_time_of_day(time_of_day + 0.125)
		elif k.keycode == KEY_Y:
			var next_w := (int(weather_state) + 1) % 4
			set_weather_state(next_w, 90.0)


func _process(delta: float) -> void:
	if _cave_atm == null or _village_root == null:
		_resolve_scene_refs()

	if not paused_time and cycle_duration_sec > 1.0:
		time_of_day = fposmod(time_of_day + delta / cycle_duration_sec, 1.0)

	_tick_weather(delta)
	_apply_lighting_and_globals(false)
	_update_rain_particles()
	_update_rain_audio(delta)


func _resolve_scene_refs() -> void:
	if _terrain != null:
		if _village_root == null or not is_instance_valid(_village_root):
			_village_root = _terrain.get_node_or_null("Village")
		if _cave_atm == null or not is_instance_valid(_cave_atm):
			var cave_sys := _terrain.get_node_or_null("CaveSystem")
			if cave_sys != null:
				_cave_atm = cave_sys.get_node_or_null("CaveAtmosphere")


func _tick_weather(delta: float) -> void:
	weather_timer -= delta
	if weather_timer <= 0.0:
		match weather_state:
			WeatherState.CLEAR:
				weather_state = WeatherState.CLOUDY
				weather_timer = randf_range(35.0, 55.0)
			WeatherState.CLOUDY:
				if randf() < 0.65:
					weather_state = WeatherState.LIGHT_RAIN
					weather_timer = randf_range(40.0, 75.0)
				else:
					weather_state = WeatherState.CLEAR
					weather_timer = randf_range(95.0, 165.0)
			WeatherState.LIGHT_RAIN:
				if randf() < 0.45:
					weather_state = WeatherState.HEAVY_RAIN
					weather_timer = randf_range(30.0, 55.0)
				else:
					weather_state = WeatherState.CLEARING
					weather_timer = randf_range(25.0, 40.0)
			WeatherState.HEAVY_RAIN:
				weather_state = WeatherState.CLEARING
				weather_timer = randf_range(28.0, 45.0)
			WeatherState.CLEARING:
				weather_state = WeatherState.CLEAR
				weather_timer = randf_range(110.0, 190.0)

	var target_cloud := 0.0
	var target_rain := 0.0
	var target_wind := 0.20
	match weather_state:
		WeatherState.CLEAR:
			target_cloud = 0.0
			target_rain = 0.0
			target_wind = 0.18
		WeatherState.CLOUDY:
			target_cloud = 0.52
			target_rain = 0.0
			target_wind = 0.36
		WeatherState.LIGHT_RAIN:
			target_cloud = 0.80
			target_rain = 0.55
			target_wind = 0.56
		WeatherState.HEAVY_RAIN:
			target_cloud = 1.0
			target_rain = 1.0
			target_wind = 0.95
		WeatherState.CLEARING:
			target_cloud = 0.32
			target_rain = 0.0
			target_wind = 0.30

	rain_intensity = move_toward(rain_intensity, target_rain, delta * 0.24)
	wind_strength = move_toward(wind_strength, target_wind, delta * 0.22)
	var target_wet := maxf(target_cloud * 0.35, rain_intensity)
	var wet_rate := 0.20 if target_wet >= weather_wetness else 0.055  # Ground dries slower than it wets
	weather_wetness = move_toward(weather_wetness, target_wet, delta * wet_rate)


func _apply_lighting_and_globals(force: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"u_time_of_day", time_of_day)
	RenderingServer.global_shader_parameter_set(&"u_weather_wetness", weather_wetness)
	RenderingServer.global_shader_parameter_set(&"u_wind_strength", wind_strength)

	# 0.25 = 06:00 sunrise, 0.50 = noon, 0.75 = sunset
	var sun_angle := (time_of_day - 0.25) * TAU
	var sun_vec := Vector3(cos(sun_angle), sin(sun_angle), 0.34).normalized()
	var day_w := smoothstep(-0.08, 0.22, sun_vec.y)
	var twilight := smoothstep(-0.22, -0.02, sun_vec.y) * (1.0 - smoothstep(0.04, 0.28, sun_vec.y))
	is_night = sun_vec.y < -0.01

	# Horizon-safe directional light vector: minimum +7 deg elevation so cull_back terrain never receives under-horizon shadows
	var min_sin_elev := 0.125
	var active_dir := -sun_vec if is_night else sun_vec
	var horiz := Vector2(active_dir.x, active_dir.z)
	if horiz.length_squared() < 0.001:
		horiz = Vector2(0.8, 0.6)
	horiz = horiz.normalized()
	var safe_y := clampf(absf(active_dir.y), min_sin_elev, 0.96)
	var h_scale := sqrt(maxf(1.0 - safe_y * safe_y, 0.01))
	var light_from := Vector3(horiz.x * h_scale, safe_y, horiz.y * h_scale).normalized()

	var overcast := weather_wetness
	var sun_peak := lerpf(1.38, 0.62, overcast * 0.85)
	var moon_peak := lerpf(0.32, 0.16, overcast * 0.85)

	# Horizon crossfade prevents hard shadow flip at 0 deg
	var sun_fade := clampf((sun_vec.y + 0.02) / 0.14, 0.0, 1.0)
	var moon_fade := clampf((-sun_vec.y + 0.02) / 0.14, 0.0, 1.0)
	var target_dir_energy := moon_peak * moon_fade if is_night else sun_peak * sun_fade

	var day_col := Color(1.0, 0.95, 0.86)
	var dusk_col := Color(1.0, 0.66, 0.38)
	var moon_col := Color(0.62, 0.76, 1.0)
	var storm_tint := Color(0.76, 0.81, 0.90)
	var dir_col := moon_col if is_night else day_col.lerp(dusk_col, twilight * 0.88)
	dir_col = dir_col.lerp(storm_tint, overcast * 0.45)

	if _sun != null:
		# Aim -Z of DirectionalLight3D toward origin from light_from direction
		var target_basis := Transform3D().looking_at(-light_from, Vector3.UP).basis
		_sun.global_transform = Transform3D(target_basis, _sun.global_position)
		_sun.light_color = dir_col
		_sun.shadow_opacity = lerpf(0.56, lerpf(0.84, 0.45, overcast), day_w)

	var night_amb := Color(0.14, 0.21, 0.42)
	var dawn_amb := Color(0.82, 0.62, 0.56)
	var day_amb := Color(0.76, 0.85, 0.98)
	var amb_col := night_amb.lerp(day_amb, day_w).lerp(dawn_amb, twilight * 0.72)
	amb_col = amb_col.lerp(Color(0.46, 0.52, 0.60), overcast * 0.65)
	var amb_energy := lerpf(0.28, 0.56, day_w) * lerpf(1.0, 0.84, overcast * 0.5)
	var sky_contrib := lerpf(0.30, 0.58, day_w)
	var exposure := lerpf(0.96, 1.06, day_w)

	var rain_fog_col := night_amb.lerp(Color(0.58, 0.66, 0.74), day_w)
	var rain_fog_density := 0.0022 * rain_intensity

	if _cave_atm != null and _cave_atm.has_method("set_outdoor_baseline"):
		_cave_atm.call("set_outdoor_baseline", target_dir_energy, amb_col, amb_energy, sky_contrib, exposure, rain_fog_col, rain_fog_density)
	else:
		if _sun != null:
			_sun.light_energy = target_dir_energy
		if _world_env != null and _world_env.environment != null:
			var env := _world_env.environment
			env.ambient_light_color = amb_col
			env.ambient_light_energy = amb_energy
			env.ambient_light_sky_contribution = sky_contrib
			env.tonemap_exposure = exposure
			if rain_fog_density > 0.0001:
				env.fog_enabled = true
				env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
				env.fog_light_color = rain_fog_col
				env.fog_density = rain_fog_density
			else:
				env.fog_enabled = false

	# Village lanterns & warm windows turn on cleanly at dusk/night or deep storms
	night_light_strength = clampf(maxf(smoothstep(0.18, -0.06, sun_vec.y), rain_intensity * 0.45), 0.0, 1.0)
	if force or absf(night_light_strength - _last_village_push) > 0.015 or absf(weather_wetness - _last_wetness_push) > 0.025:
		_last_village_push = night_light_strength
		_last_wetness_push = weather_wetness
		if _village_root != null and is_instance_valid(_village_root):
			VillageBuilder.update_night_lights(_village_root, night_light_strength, weather_wetness)


func _apply_sky_shader() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var sky_shader := load("res://terrain/world_sky.gdshader") as Shader
	if sky_shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_world_env.environment.sky = sky
	_world_env.environment.background_mode = Environment.BG_SKY


func _build_rain_particles() -> void:
	var gp := GPUParticles3D.new()
	gp.name = "RainVolume"
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.emitting = false
	gp.amount = 1400
	gp.lifetime = 0.85
	gp.preprocess = 0.25
	gp.visibility_aabb = AABB(Vector3(-28.0, -24.0, -28.0), Vector3(56.0, 48.0, 56.0))

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(20.0, 2.0, 20.0)
	pmat.direction = Vector3(0.12, -1.0, 0.05)
	pmat.spread = 4.0
	pmat.initial_velocity_min = 24.0
	pmat.initial_velocity_max = 31.0
	pmat.gravity = Vector3(0.0, -9.8, 0.0)
	gp.process_material = pmat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.032, 0.92)
	_rain_streak_mat = StandardMaterial3D.new()
	_rain_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_streak_mat.albedo_color = Color(0.76, 0.86, 0.98, 0.34)
	_rain_streak_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_streak_mat.no_depth_test = false
	mesh.material = _rain_streak_mat
	gp.draw_pass_1 = mesh

	add_child(gp)
	_rain_particles = gp
	_update_rain_quality_budget()


func _update_rain_quality_budget() -> void:
	if _rain_particles == null:
		return
	var q_idx := 1
	if _settings != null and _settings.has_method("get_value"):
		q_idx = int(_settings.get_value("graphics", "quality_preset", 1))
	match q_idx:
		0:
			_rain_particles.amount = 420
		1:
			_rain_particles.amount = 900
		2:
			_rain_particles.amount = 1400
		_:
			_rain_particles.amount = 2000


func _update_rain_particles() -> void:
	if _rain_particles == null:
		return
	var cave_f := 0.0
	if _cave_atm != null and "get" in _cave_atm:
		var v: Variant = _cave_atm.get("_cave_factor")
		if v != null:
			cave_f = maxf(float(v), 0.0)
	var eff_rain := rain_intensity * (1.0 - smoothstep(0.18, 0.55, cave_f))
	if eff_rain <= 0.03:
		_rain_particles.emitting = false
		return
	_rain_particles.emitting = true
	_rain_particles.amount_ratio = clampf(eff_rain, 0.05, 1.0)
	if _rain_streak_mat != null:
		_rain_streak_mat.albedo_color.a = lerpf(0.14, 0.38, eff_rain)

	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.001:
			fwd = fwd.normalized()
		else:
			fwd = Vector3.FORWARD
		_rain_particles.global_position = cam.global_position + fwd * 12.0 + Vector3(0.0, 14.0, 0.0)
	var pmat := _rain_particles.process_material as ParticleProcessMaterial
	if pmat != null:
		pmat.direction = Vector3(0.28 * wind_strength, -1.0, 0.14 * wind_strength).normalized()


func _build_rain_audio() -> void:
	# Pre-synthesize a 2.5-second seamless soft pink-brown rain noise loop once at startup
	var sample_rate := 22050
	var count := int(sample_rate * 2.5)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424291
	var lp1 := 0.0
	var lp2 := 0.0
	var vals := PackedFloat32Array()
	vals.resize(count)
	for i in range(count):
		var w := rng.randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.84 + w * 0.16
		lp2 = lp2 * 0.94 + lp1 * 0.06
		var patters := (rng.randf_range(-1.0, 1.0) * 0.25) if rng.randf() < 0.018 else 0.0
		vals[i] = clampf(lp2 * 2.6 + lp1 * 0.45 + patters, -0.95, 0.95)
	# Crossfade loop seam (last 2000 samples) for zero click
	var seam := 2000
	for i in range(seam):
		var t := float(i) / float(seam)
		var end_i := count - seam + i
		var blended := lerpf(vals[end_i], vals[i], t)
		vals[i] = blended
		vals[end_i] = blended
	for i in range(count):
		var s := clampi(int(vals[i] * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	wav.data = data

	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "RainAmbience"
	_rain_audio.stream = wav
	_rain_audio.volume_db = -80.0
	add_child(_rain_audio)


func _update_rain_audio(_delta: float) -> void:
	if _rain_audio == null:
		return
	var muted := false
	var master_v := 0.8
	var sfx_v := 0.8
	if _settings != null and _settings.has_method("get_value"):
		muted = bool(_settings.get_value("audio", "muted", false))
		master_v = float(_settings.get_value("audio", "master_volume", 0.8))
		sfx_v = float(_settings.get_value("audio", "sfx_volume", 0.8))
	var cave_f := 0.0
	if _cave_atm != null and "get" in _cave_atm:
		var v: Variant = _cave_atm.get("_cave_factor")
		if v != null:
			cave_f = maxf(float(v), 0.0)
	var eff := rain_intensity * (1.0 - cave_f * 0.72) * master_v * sfx_v
	if muted or eff <= 0.02:
		if _rain_audio.playing:
			_rain_audio.stop()
		return
	if not _rain_audio.playing:
		_rain_audio.play()
	_rain_audio.volume_db = linear_to_db(clampf(eff * 0.42, 0.001, 1.0))
