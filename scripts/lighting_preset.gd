extends RefCounted
## Outdoor lighting preset for Godot 4.7 (Forward+), one static function per step, applied in this order:
## sun -> sky -> tonemap -> ambient occlusion -> sdfgi -> fog. Each step solves one visible problem; keep the order.
## Checked against Godot 4.7.2.stable class reference.
##
## Usage (from any node, e.g. a @tool script or _ready()):
##   const LightingPreset := preload("res://path/to/lighting_preset.gd")
##   LightingPreset.apply_sun($Sun)
##   LightingPreset.apply_sky($WorldEnvironment.environment)
##   LightingPreset.apply_tonemap(env)            # AgX + small exposure/colour adjustment
##   LightingPreset.apply_ambient_occlusion(env)  # SSAO (+ optional SSIL)
##   LightingPreset.apply_sdfgi(env)              # outdoor bounce light
##   LightingPreset.apply_fog(env)                # depth, tinted like the sky horizon
## Every function takes an optional `o: Dictionary` to override the defaults listed in it.

const SUN_WARM := Color(1.0, 0.86, 0.77)        # warm afternoon sun (value shown in the source video)
const SKY_TOP := Color(0.26, 0.45, 0.78)
const SKY_HORIZON := Color(0.78, 0.74, 0.66)     # slightly warmer horizon than the zenith
const GROUND_HORIZON := Color(0.55, 0.52, 0.47)
const GROUND_BOTTOM := Color(0.18, 0.17, 0.15)


static func _opt(o: Dictionary, key: String, def: Variant) -> Variant:
	return o[key] if o.has(key) else def


## 1. SUN: low and from the side so two faces of a building get clearly different light; warm colour.
## elevation_deg: height above the horizon (20-35 gives long readable shadows; 60+ flattens forms).
## azimuth_deg: compass direction the light COMES FROM (0 = from +Z, 90 = from +X). Pick it so that the
## wall facing the main camera and its neighbouring wall are NOT lit equally (avoid the camera's own direction).
static func apply_sun(sun: DirectionalLight3D, o := {}) -> void:
	var elev := deg_to_rad(float(_opt(o, "elevation_deg", 28.0)))
	var azim := deg_to_rad(float(_opt(o, "azimuth_deg", -35.0)))
	var from_dir := Vector3(sin(azim) * cos(elev), sin(elev), cos(azim) * cos(elev))
	# A DirectionalLight3D shines along its local -Z: point it from `from_dir` towards the origin.
	sun.global_basis = Basis.looking_at(-from_dir, Vector3.UP if absf(from_dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = _opt(o, "color", SUN_WARM)
	sun.light_energy = float(_opt(o, "energy", 1.5))
	sun.shadow_enabled = true
	# Shadow QUALITY is a separate (performance) decision: see godot-render-performance. Keep defaults here.


## 2. SKY: a real sky becomes the second light source; it fills the shadowed faces with cool blue
## while the sun stays warm. Without it, shadowed walls go nearly black.
static func apply_sky(env: Environment, o := {}) -> void:
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = _opt(o, "sky_top", SKY_TOP)
	mat.sky_horizon_color = _opt(o, "sky_horizon", SKY_HORIZON)
	mat.ground_horizon_color = _opt(o, "ground_horizon", GROUND_HORIZON)
	mat.ground_bottom_color = _opt(o, "ground_bottom", GROUND_BOTTOM)
	var sky := Sky.new()
	sky.sky_material = mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = float(_opt(o, "ambient_energy", 1.0))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


## 3. TONE MAPPING: AgX rolls highlights off instead of clipping them to one flat white (Linear does).
## Combine it with a small exposure and colour adjustment: the tonemapper alone looks greyer.
static func apply_tonemap(env: Environment, o := {}) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(_opt(o, "exposure", 1.1))
	env.adjustment_enabled = true
	env.adjustment_contrast = float(_opt(o, "contrast", 1.05))
	env.adjustment_saturation = float(_opt(o, "saturation", 1.15))


## 4. AMBIENT OCCLUSION: darkens creases and contact zones so objects sit on the ground.
## Screen-space: it changes with the view, so judge it while moving the camera, not on one screenshot.
## radius is in world units: scale it to your scene (about the size of the gaps you want darkened).
static func apply_ambient_occlusion(env: Environment, o := {}) -> void:
	env.ssao_enabled = true
	env.ssao_radius = float(_opt(o, "radius", 1.0))
	env.ssao_intensity = float(_opt(o, "intensity", 2.0))
	env.ssil_enabled = bool(_opt(o, "ssil", true))   # the source video toggled SSIL together with SSAO


## 5. SDFGI: approximated bounce light around the camera (green grass tints nearby walls).
## Judge it with the real scene albedo: saturated materials bounce saturated colour.
## min_cell_size: smaller for small-scale scenes (finer GI, shorter range); default 0.2.
static func apply_sdfgi(env: Environment, o := {}) -> void:
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = float(_opt(o, "energy", 1.0))
	env.sdfgi_min_cell_size = float(_opt(o, "min_cell_size", 0.2))


## 6. FOG: distant things lose contrast and melt into the horizon colour, near things stay crisp -> depth.
## More fog is not better: keep paths and goals readable.
## mode "depth" (default): no fog before depth_begin (put it just past the gameplay space), reaching
##   `density` (= max intensity, 1.0 hides everything) at depth_end. Distances are world units.
## mode "exponential": fog from the camera on, `density` per world unit; it also veils mid-ground objects.
static func apply_fog(env: Environment, o := {}) -> void:
	env.fog_enabled = true
	if _opt(o, "mode", "depth") == "depth":
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = float(_opt(o, "depth_begin", 20.0))
		env.fog_depth_end = float(_opt(o, "depth_end", 150.0))
		env.fog_depth_curve = float(_opt(o, "depth_curve", 1.0))
		env.fog_density = float(_opt(o, "density", 0.8))
	else:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = float(_opt(o, "density", 0.01))
	env.fog_light_color = _opt(o, "color", SKY_HORIZON)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = float(_opt(o, "sun_scatter", 0.1))
	env.fog_aerial_perspective = float(_opt(o, "aerial_perspective", 0.5))
	env.fog_sky_affect = float(_opt(o, "sky_affect", 0.0))
