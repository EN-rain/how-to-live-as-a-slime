class_name CaveAtmosphere
extends Node

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
const AtmosphereProfile = preload("res://resources/atmosphere_profile.gd")
## Blends WorldEnvironment exposure, sky-ambient contribution, distance fog, glow,
## and exterior Sun bounce smoothly based on active camera depth inside the cave.

@export var atmosphere_profile: AtmosphereProfile = preload("res://resources/default_atmosphere_profile.tres")

var _world_env: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _settings: Node = null
var _terrain_node: Node = null

var _outdoor_exposure: float = 1.05
var _outdoor_sky_contrib: float = 0.55
var _outdoor_amb_color: Color = Color(0.76, 0.85, 0.98, 1.0)
var _outdoor_amb_energy: float = 0.56
var _outdoor_sun_energy: float = 1.38
var _outdoor_fog_color: Color = Color(0.65, 0.74, 0.82, 1.0)
var _outdoor_fog_density: float = 0.0
var _external_baseline_active := false

var _cave_factor: float = -1.0
var _grotto_factor: float = 0.0
var _alpine_factor: float = -1.0
var _webwood_factor: float = -1.0
var _ruins_factor: float = -1.0
var _wolf_factor: float = -1.0
var _extra_cave_factor: float = 0.0
var _in_extra_cave: bool = false
var _initialized := false
var _last_cam_pos := Vector3(1e9, 1e9, 1e9)
var _last_target_cave: float = 0.0
var _last_target_grotto: float = 0.0
var _last_target_alpine: float = 0.0
var _last_target_webwood: float = 0.0
var _last_target_ruins: float = 0.0
var _last_target_wolf: float = 0.0
var _settled := false
var _cave_sys: CaveSystem = null
var _quality_idx: int = 1


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	call_deferred("_bind_scene_nodes")


func _bind_scene_nodes() -> void:
	var st := get_tree()
	if st == null:
		return
	var root_node := st.current_scene
	if root_node == null:
		# Headless/benchmark runners often attach Main directly to SceneTree.root
		var p: Node = self
		while p.get_parent() != null and p.get_parent() != st.root:
			p = p.get_parent()
		root_node = p

	if root_node != null:
		_world_env = root_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
		_sun = root_node.get_node_or_null("Sun") as DirectionalLight3D

	_settings = get_node_or_null("/root/SettingsManager")
	if _settings != null:
		if _settings.has_method("get_value"):
			_quality_idx = int(_settings.get_value("graphics", "quality_preset", 1))
		if _settings.has_signal("settings_changed"):
			if not _settings.is_connected("settings_changed", Callable(self, "_on_settings_changed")):
				_settings.connect("settings_changed", Callable(self, "_on_settings_changed"))

	_capture_outdoor_baseline()
	_initialized = true
	_cave_sys = get_parent() as CaveSystem
	_last_cam_pos = Vector3(1e9, 1e9, 1e9)
	_settled = false
	_evaluate_and_apply(1.0)


func _on_settings_changed(_category: String, key: String, value: Variant) -> void:
	if key == "quality_preset":
		_quality_idx = int(value)
		_settled = false
	elif (key == "night_mode" or key == "shadow_quality") and not _external_baseline_active:
		_capture_outdoor_baseline()
		_cave_factor = -1.0
		_settled = false
		_last_cam_pos = Vector3(1e9, 1e9, 1e9)


func set_outdoor_baseline(
	sun_energy: float,
	amb_color: Color,
	amb_energy: float,
	sky_contrib: float,
	exposure: float,
	fog_color: Color,
	fog_density: float
) -> void:
	if _external_baseline_active \
			and absf(sun_energy - _outdoor_sun_energy) <= 1e-4 \
			and absf(amb_energy - _outdoor_amb_energy) <= 1e-4 \
			and absf(sky_contrib - _outdoor_sky_contrib) <= 1e-4 \
			and absf(exposure - _outdoor_exposure) <= 1e-4 \
			and absf(fog_density - _outdoor_fog_density) <= 1e-5 \
			and amb_color.is_equal_approx(_outdoor_amb_color) \
			and fog_color.is_equal_approx(_outdoor_fog_color):
		return
	_external_baseline_active = true
	_outdoor_sun_energy = sun_energy
	_outdoor_amb_color = amb_color
	_outdoor_amb_energy = amb_energy
	_outdoor_sky_contrib = sky_contrib
	_outdoor_exposure = exposure
	_outdoor_fog_color = fog_color
	_outdoor_fog_density = fog_density
	_settled = false


func _capture_outdoor_baseline() -> void:
	if _external_baseline_active:
		return
	var night := false
	if _settings != null and _settings.has_method("get_value"):
		night = bool(_settings.get_value("gameplay", "night_mode", false))

	if night:
		_outdoor_amb_color = Color(0.28, 0.48, 0.78, 1.0)
		_outdoor_amb_energy = 0.42
		_outdoor_sun_energy = 0.34
	else:
		_outdoor_amb_color = Color(0.76, 0.85, 0.98, 1.0)
		_outdoor_amb_energy = 0.56
		_outdoor_sun_energy = 1.38

	if _world_env != null and _world_env.environment != null:
		var env := _world_env.environment
		if not _initialized:
			_outdoor_exposure = env.tonemap_exposure
			_outdoor_sky_contrib = env.ambient_light_sky_contribution
		if not night:
			_outdoor_amb_color = env.ambient_light_color
			_outdoor_amb_energy = env.ambient_light_energy
	if _sun != null and not night and not _initialized:
		_outdoor_sun_energy = _sun.light_energy


func _process(delta: float) -> void:
	if not _initialized:
		return
	_evaluate_and_apply(clampf(delta * 4.5, 0.08, 1.0))


func _evaluate_and_apply(blend_rate: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return

	var cam_pos := cam.global_position
	var cam_moved := cam_pos.distance_squared_to(_last_cam_pos) > 0.0064
	if not cam_moved and _settled:
		return

	var cl := CaveLayout.to_local(cam_pos)
	var d_void: float = 10.0
	var target_cave: float = 0.0
	var target_grotto: float = 0.0
	var target_alpine: float = 0.0
	var target_webwood: float = 0.0
	var target_ruins: float = 0.0
	var target_wolf: float = 0.0
	if cam_moved or _cave_factor < 0.0:
		_last_cam_pos = cam_pos
		var sdf := CaveSystem.get_sdf()
		d_void = sdf.eval_cave_void_smooth(cl.x, cl.y, cl.z)

		# 0 outdoors or high above mountain crown, rising smoothly past twilight mouth into full interior
		var in_void := 1.0 - smoothstep(-0.5, 4.2, d_void)
		var past_mouth := smoothstep(0.0, 22.0, cl.z)
		var under_rim := 1.0 - smoothstep(47.5, 56.0, cl.y)
		target_cave = clampf(in_void * past_mouth * under_rim, 0.0, 1.0)

		# Warm Collapse Hall / Sanctum vs Cool Grotto / Geode / East Descent / Lake zone modulation
		var dist_to_grotto_x := smoothstep(-40.0, -14.0, cl.x) * smoothstep(68.0, 88.0, cl.z)
		var in_geode := (1.0 - smoothstep(6.0, 14.0, Vector2(cl.x - 2.0, cl.z - 56.0).length())) * smoothstep(32.0, 12.0, cl.y)
		var in_east_descent := smoothstep(4.0, 12.0, cl.x) * smoothstep(40.0, 52.0, cl.z) * smoothstep(26.0, 12.0, cl.y)
		var sanctum_atten := 1.0 - smoothstep(-140.0, -175.0, cl.x) * 0.65
		target_grotto = clampf(maxf(maxf(dist_to_grotto_x, in_geode), in_east_descent) * target_cave * sanctum_atten, 0.0, 1.0)

		var extra_cf: float = WorldLandmarks.eval_underground_atmosphere(cam_pos)
		_extra_cave_factor = extra_cf
		_in_extra_cave = extra_cf > 0.15
		target_cave = maxf(target_cave, extra_cf)
		target_alpine = smoothstep(95.0, 185.0, cam_pos.y) * (1.0 - target_cave)
		var web_c := WorldLandmarks.SPIDER_FOREST_CENTER
		if _terrain_node == null or not is_instance_valid(_terrain_node):
			_terrain_node = get_tree().get_first_node_in_group("terrain")
			if _terrain_node == null and get_tree().current_scene != null:
				_terrain_node = get_tree().current_scene.get_node_or_null("TerrainScene")
		if _terrain_node != null and _terrain_node.has_method("get_webwood_center"):
			web_c = _terrain_node.call("get_webwood_center")
		var d_web := Vector2(cam_pos.x - web_c.x, cam_pos.z - web_c.y).length()
		var ap := atmosphere_profile if atmosphere_profile != null else AtmosphereProfile.new()
		target_webwood = (1.0 - smoothstep(ap.webwood_fade_range.x, ap.webwood_fade_range.y, d_web)) * (1.0 - target_cave)
		var d_ruins := Vector2(cam_pos.x - WorldLandmarks.RAT_WARREN_MOUTH.x, cam_pos.z - (WorldLandmarks.RAT_WARREN_MOUTH.y + 44.0)).length()
		target_ruins = (1.0 - smoothstep(ap.ruins_fade_range.x, ap.ruins_fade_range.y, d_ruins)) * (1.0 - target_cave)
		var d_wolf := Vector2(cam_pos.x - WorldLandmarks.WOLF_CRAG_CENTER.x, cam_pos.z - WorldLandmarks.WOLF_CRAG_CENTER.y).length()
		target_wolf = (1.0 - smoothstep(ap.wolf_fade_range.x, ap.wolf_fade_range.y, d_wolf)) * (1.0 - target_cave)

		_last_target_cave = target_cave
		_last_target_grotto = target_grotto
		_last_target_alpine = target_alpine
		_last_target_webwood = target_webwood
		_last_target_ruins = target_ruins
		_last_target_wolf = target_wolf
	else:
		target_cave = _last_target_cave
		target_grotto = _last_target_grotto
		target_alpine = _last_target_alpine
		target_webwood = _last_target_webwood
		target_ruins = _last_target_ruins
		target_wolf = _last_target_wolf

	# Attenuate exterior directional Sun rapidly inside the subterranean cave so unshadowed
	# sunlight never leaks through the underground mountain roof (SkylightKeySpot provides the skylight beam!)
	var away_from_mouth := smoothstep(4.0, 20.0, cl.z)
	var sun_attenuation := clampf(1.0 - 0.96 * maxf(target_cave * away_from_mouth, _extra_cave_factor), 0.04, 1.0)

	if _cave_factor < 0.0:
		_cave_factor = target_cave
		_grotto_factor = target_grotto
		_alpine_factor = target_alpine
		_webwood_factor = target_webwood
		_ruins_factor = target_ruins
		_wolf_factor = target_wolf
	else:
		_cave_factor = lerpf(_cave_factor, target_cave, blend_rate)
		_grotto_factor = lerpf(_grotto_factor, target_grotto, blend_rate)
		_alpine_factor = lerpf(_alpine_factor, target_alpine, blend_rate)
		_webwood_factor = lerpf(_webwood_factor, target_webwood, blend_rate)
		_ruins_factor = lerpf(_ruins_factor, target_ruins, blend_rate)
		_wolf_factor = lerpf(_wolf_factor, target_wolf, blend_rate)

	_settled = absf(_cave_factor - target_cave) < 0.0005 and absf(_grotto_factor - target_grotto) < 0.0005 and absf(_alpine_factor - target_alpine) < 0.0005 and absf(_webwood_factor - target_webwood) < 0.0005 and absf(_ruins_factor - target_ruins) < 0.0005 and absf(_wolf_factor - target_wolf) < 0.0005
	if _settled:
		_cave_factor = target_cave
		_grotto_factor = target_grotto
		_alpine_factor = target_alpine
		_webwood_factor = target_webwood
		_ruins_factor = target_ruins
		_wolf_factor = target_wolf

	if _cave_sys != null and (cam_moved or not _settled):
		_cave_sys.update_zone_culling(cam_pos, cl, _cave_factor)

	if _world_env != null and _world_env.environment != null:
		var env := _world_env.environment
		var ap_col := atmosphere_profile if atmosphere_profile != null else AtmosphereProfile.new()
		var hall_amb := ap_col.hall_ambient_color
		var grotto_amb := ap_col.grotto_ambient_color
		var interior_amb := hall_amb.lerp(grotto_amb, _grotto_factor)
		var webwood_amb := _outdoor_amb_color.lerp(ap_col.webwood_ambient_tint, 0.68)
		var ruins_amb := _outdoor_amb_color.lerp(ap_col.ruins_ambient_tint, 0.44)
		var wolf_amb := _outdoor_amb_color.lerp(ap_col.wolf_ambient_tint, 0.38)
		var ext_amb_col := _outdoor_amb_color.lerp(webwood_amb, _webwood_factor).lerp(ruins_amb, _ruins_factor * (1.0 - _webwood_factor)).lerp(wolf_amb, _wolf_factor * (1.0 - _webwood_factor))
		var ext_amb_nrg := _outdoor_amb_energy * lerpf(1.0, 0.68, _webwood_factor) * lerpf(1.0, 0.85, _ruins_factor * (1.0 - _webwood_factor)) * lerpf(1.0, 0.92, _wolf_factor)

		env.tonemap_exposure = lerpf(_outdoor_exposure, 1.18, _cave_factor)
		env.ambient_light_sky_contribution = lerpf(_outdoor_sky_contrib, 0.0, _cave_factor)
		env.ambient_light_color = ext_amb_col.lerp(interior_amb, _cave_factor)
		env.ambient_light_energy = lerpf(ext_amb_nrg, 0.28, _cave_factor)

		var fog_on := _cave_factor > 0.04 or _alpine_factor > 0.04 or _webwood_factor > 0.04 or _ruins_factor > 0.04 or _wolf_factor > 0.04 or _outdoor_fog_density > 0.0001
		env.fog_enabled = fog_on
		if fog_on:
			env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
			var hall_fog := ap_col.hall_fog_color
			var grotto_fog := ap_col.grotto_fog_color
			var cave_fog_col := hall_fog.lerp(grotto_fog, _grotto_factor)
			var alpine_fog_col := ap_col.alpine_fog_color
			var web_fog_col := _outdoor_fog_color.lerp(ap_col.webwood_fog_tint, 0.76)
			var ruins_fog_col := _outdoor_fog_color.lerp(Color(0.39, 0.49, 0.44, 1.0), clampf(_outdoor_sun_energy, 0.18, 0.72))
			var wolf_fog_col := _outdoor_fog_color.lerp(ap_col.wolf_fog_tint, 0.45)
			var exterior_fog_col := _outdoor_fog_color.lerp(alpine_fog_col, _alpine_factor).lerp(web_fog_col, _webwood_factor * (1.0 - _alpine_factor)).lerp(ruins_fog_col, _ruins_factor * (1.0 - _alpine_factor) * (1.0 - _webwood_factor)).lerp(wolf_fog_col, _wolf_factor * (1.0 - _alpine_factor) * (1.0 - _webwood_factor))
			var cave_w := _cave_factor / maxf(_cave_factor + _alpine_factor + _webwood_factor * 0.5 + _ruins_factor * 0.45 + _wolf_factor * 0.35 + (0.25 if _outdoor_fog_density > 0.0001 else 0.0), 0.0001)
			env.fog_light_color = exterior_fog_col.lerp(cave_fog_col, cave_w)
			var cave_density := lerpf(0.0, lerpf(0.0082, 0.0118, _grotto_factor), _cave_factor)
			var alpine_density := 0.0042 * _alpine_factor * (1.0 - _cave_factor)
			var web_density := 0.0080 * _webwood_factor * (1.0 - _cave_factor)
			var ruins_density := 0.0038 * _ruins_factor * (1.0 - _cave_factor)
			var wolf_density := 0.0022 * _wolf_factor * (1.0 - _cave_factor)
			var rain_density := _outdoor_fog_density * (1.0 - _cave_factor)
			env.fog_density = maxf(cave_density, maxf(alpine_density, maxf(web_density, maxf(ruins_density, maxf(wolf_density, rain_density)))))
			env.fog_sky_affect = lerpf(maxf(maxf(maxf(0.28 * _alpine_factor, 0.22 * _webwood_factor), maxf(0.18 * _ruins_factor, 0.14 * _wolf_factor)), clampf(_outdoor_fog_density * 140.0, 0.0, 0.48)), 0.0, _cave_factor)

		var glow_on := (_cave_factor > 0.05) or (_quality_idx > 0)
		env.glow_enabled = glow_on
		if glow_on:
			env.glow_intensity = lerpf(0.38, 0.45, _cave_factor)
			env.glow_strength = 0.85
			env.glow_bloom = lerpf(0.08, 0.10, _cave_factor)
			env.glow_hdr_threshold = lerpf(1.25, 1.05, _cave_factor)

	if _sun != null:
		_sun.light_energy = _outdoor_sun_energy * sun_attenuation * lerpf(1.0, 0.63, _webwood_factor) * lerpf(1.0, 0.84, _ruins_factor)
