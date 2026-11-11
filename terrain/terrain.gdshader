shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

group_uniforms MeadowGrass;
uniform vec3 grass_sun_color : source_color = vec3(0.48, 0.84, 0.28);
uniform vec3 grass_mid_color : source_color = vec3(0.36, 0.72, 0.22);
uniform vec3 grass_deep_color : source_color = vec3(0.28, 0.62, 0.18);

group_uniforms IslandBeach;
uniform vec3 sand_light_color : source_color = vec3(0.88, 0.80, 0.56);
uniform vec3 sand_dark_color : source_color = vec3(0.74, 0.64, 0.44);
uniform vec3 wet_sand_color : source_color = vec3(0.46, 0.42, 0.34);
uniform float sea_level = 0.0;
uniform float beach_height = 4.5;
uniform float beach_blend = 2.5;
uniform float alpine_height = 115.0;
uniform float alpine_blend = 25.0;

group_uniforms SoilAndRock;
uniform vec3 rock_light_color : source_color = vec3(0.58, 0.60, 0.64);
uniform vec3 rock_dark_color : source_color = vec3(0.38, 0.40, 0.44);
uniform vec3 alpine_rock_color : source_color = vec3(0.44, 0.48, 0.54);
uniform vec3 snow_color : source_color = vec3(0.78, 0.84, 0.92);

group_uniforms SurfaceTuning;
uniform float detail_scale : hint_range(0.05, 5.0, 0.05) = 0.25;
uniform float macro_scale : hint_range(0.0001, 0.1, 0.0001) = 0.025;
uniform float slope_threshold : hint_range(0.3, 0.98, 0.01) = 0.46;
uniform float slope_softness : hint_range(0.01, 0.2, 0.01) = 0.04;
uniform float surface_roughness : hint_range(0.0, 1.0, 0.01) = 0.92;

varying vec2 v_xz;
varying float v_world_y;
varying float v_upness;
varying float v_rock_mask;
varying float v_height_shade;
varying float v_macro_pat;
varying float v_med_pat;
varying float v_rock_fbm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	return 0.62 * value_noise(p) + 0.38 * value_noise(p * 2.15 + vec2(17.1, -9.4));
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_xz = world_pos.xz;
	v_world_y = world_pos.y;

	v_upness = clamp(world_normal.y, 0.0, 1.0);
	v_rock_mask = 1.0 - smoothstep(slope_threshold - slope_softness, slope_threshold + slope_softness, v_upness);
	v_height_shade = clamp(0.95 + (world_pos.y - 22.0) * 0.0004, 0.92, 1.02);

	// Precompute macro, medium botanical detail, and rock FBM per-vertex (zero noise calls in fragment!)
	v_macro_pat = fbm2(v_xz * macro_scale);
	v_med_pat = fbm2(v_xz * detail_scale + vec2(5.2, -8.7));
	v_rock_fbm = fbm2(v_xz * 0.022 + vec2(v_world_y * 0.028, -v_world_y * 0.021));
}

void fragment() {
	// 1. Clean, vibrant stylized meadow (zero procedural noise in fragment - ultra fast!)
	float canopy_blend = v_macro_pat * 0.70 + v_med_pat * 0.30;
	vec3 g_col = mix(grass_deep_color, grass_mid_color, smoothstep(0.28, 0.58, canopy_blend));
	g_col = mix(g_col, grass_sun_color, smoothstep(0.52, 0.82, canopy_blend));

	// 2. Steep Rocky Mountain Cliffs (cool slate rock only on true vertical crags > 62°)
	float high_crag_rock = smoothstep(110.0, 150.0, v_world_y) * (1.0 - smoothstep(0.45, 0.65, v_upness));
	float total_rock = clamp(max(v_rock_mask, high_crag_rock), 0.0, 1.0);
	vec3 ground_col = g_col;
	if (total_rock > 0.001) {
		float rock_t = smoothstep(0.25, 0.75, v_rock_fbm);
		vec3 slate_rock = mix(rock_dark_color, rock_light_color, rock_t);
		vec3 cool_granite = mix(alpine_rock_color * 0.85, alpine_rock_color * 1.15, rock_t);
		float alpine_mask = smoothstep(alpine_height - alpine_blend, alpine_height + alpine_blend, v_world_y);
		vec3 cliff_col = mix(slate_rock, cool_granite, alpine_mask);
		ground_col = mix(g_col, cliff_col, total_rock);
	}

	// 3. Snow-Crowned Alpine Summits
	float snow_mask = 0.0;
	if (v_world_y > 130.0) {
		float snow_noise = (v_rock_fbm - 0.5) * 22.0;
		float snow_alt = smoothstep(145.0 + snow_noise, 175.0 + snow_noise, v_world_y);
		float snow_slope = smoothstep(0.55, 0.80, v_upness);
		snow_mask = snow_alt * snow_slope;
		ground_col = mix(ground_col, snow_color, snow_mask);
	}

	// 4. Coastal Golden Beach Sand (only evaluated near sea level y < 7.5m)
	if (v_world_y < beach_height + beach_blend) {
		vec3 s_col = mix(sand_dark_color, sand_light_color, smoothstep(0.30, 0.75, v_med_pat));
		s_col = mix(wet_sand_color, s_col, smoothstep(sea_level - 2.5, sea_level + 0.6, v_world_y));
		float beach_mask = 1.0 - smoothstep(beach_height - beach_blend, beach_height + beach_blend, v_world_y);
		ground_col = mix(ground_col, s_col, beach_mask * (1.0 - v_rock_mask * 0.85));
	}

	ALBEDO = ground_col * v_height_shade;
	ROUGHNESS = mix(surface_roughness, 0.80, snow_mask);
	METALLIC = 0.0;
}
