shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

global uniform float u_weather_wetness;

group_uniforms MeadowGrass;
uniform vec3 grass_sun_color : source_color = vec3(0.48, 0.84, 0.28);
uniform vec3 grass_mid_color : source_color = vec3(0.36, 0.72, 0.22);
uniform vec3 grass_deep_color : source_color = vec3(0.28, 0.62, 0.18);

group_uniforms IslandBeach;
uniform vec3 sand_light_color : source_color = vec3(0.93, 0.85, 0.62);
uniform vec3 sand_dark_color : source_color = vec3(0.79, 0.68, 0.45);
uniform vec3 wet_sand_color : source_color = vec3(0.62, 0.54, 0.38);
uniform float sea_level = 0.0;
uniform float beach_height = 6.2;
uniform float beach_blend = 2.6;
uniform float alpine_height = 115.0;
uniform float alpine_blend = 25.0;

group_uniforms SoilAndRock;
uniform vec3 rock_light_color : source_color = vec3(0.58, 0.60, 0.64);
uniform vec3 rock_dark_color : source_color = vec3(0.38, 0.40, 0.44);
uniform vec3 alpine_rock_color : source_color = vec3(0.44, 0.48, 0.54);
uniform vec3 snow_color : source_color = vec3(0.78, 0.84, 0.92);

group_uniforms VillageGround;
uniform vec2 village_center_xz = vec2(590.0, 2200.0);
uniform vec2 village_radii_xz = vec2(76.0, 66.0);
uniform vec3 mud_light_color : source_color = vec3(0.52, 0.42, 0.31);
uniform vec3 mud_dark_color : source_color = vec3(0.36, 0.28, 0.20);
uniform vec3 mud_verge_color : source_color = vec3(0.44, 0.40, 0.27);

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
varying float v_wet_puddle;

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
	v_wet_puddle = smoothstep(0.46, 0.78, fbm2(v_xz * 0.085 + vec2(-3.2, 6.4))) * smoothstep(0.82, 0.96, v_upness);
}

void fragment() {
	// 1. Clean, vibrant stylized meadow (zero procedural noise in fragment - ultra fast!)
	float canopy_blend = v_macro_pat * 0.70 + v_med_pat * 0.30;
	vec3 g_col = mix(grass_deep_color, grass_mid_color, smoothstep(0.28, 0.58, canopy_blend));
	g_col = mix(g_col, grass_sun_color, smoothstep(0.52, 0.82, canopy_blend));

	// Packed medieval town mud/earth strictly hugging the plaza, ring road, cardinal avenues & house frontages
	vec2 v_rel = v_xz - village_center_xz;
	if (abs(v_rel.x) < village_radii_xz.x + 8.0 && abs(v_rel.y) < village_radii_xz.y + 8.0) {
		float noise_m = (v_med_pat - 0.5) * 3.0 + (v_macro_pat - 0.5) * 2.0;
		// Grand Central Market Square & Civic Ring (rounded square covering diagonal corner plots)
		vec2 p_dist = abs(v_rel) - vec2(17.0, 17.0);
		float d_plaza = length(max(p_dist, vec2(0.0))) + min(max(p_dist.x, p_dist.y), 0.0) - 2.5 + noise_m * 0.70;
		float plaza_mud = 1.0 - smoothstep(0.0, 4.5, d_plaza);
		// East-West Cardinal Avenue mud shoulder (stops cleanly at West & East Gates)
		float ew_mud = (1.0 - smoothstep(4.2, 10.5, abs(v_rel.y) + noise_m * 0.65)) * (1.0 - smoothstep(54.0, 59.5, abs(v_rel.x) + noise_m * 0.5));
		// North-South Cardinal Avenue mud shoulder (stops cleanly at North & South Gates)
		float ns_mud = (1.0 - smoothstep(4.5, 11.5, abs(v_rel.x) + noise_m * 0.65)) * (1.0 - smoothstep(48.0, 53.5, abs(v_rel.y) + noise_m * 0.5));
		// Cobblestone Ring Road & Ward Lanes (loops around the Market Quarter while leaving gardens & backyards green)
		float ring_ew_lanes = (1.0 - smoothstep(2.6, 7.5, abs(abs(v_rel.x) - 36.0) + noise_m * 0.6)) * (1.0 - smoothstep(32.5, 38.0, abs(v_rel.y) + noise_m * 0.5));
		float ring_ns_lanes = (1.0 - smoothstep(2.6, 7.5, abs(abs(v_rel.y) - 32.0) + noise_m * 0.6)) * (1.0 - smoothstep(34.5, 40.5, abs(v_rel.x) + noise_m * 0.5));
		float ring_mud = max(ring_ew_lanes, ring_ns_lanes);
		float mud_mask = clamp(max(max(plaza_mud, ring_mud), max(ew_mud, ns_mud)), 0.0, 1.0);
		float mud_var = smoothstep(0.22, 0.78, v_med_pat * 0.65 + v_macro_pat * 0.35);
		vec3 mud_col = mix(mud_dark_color, mud_light_color, mud_var);
		// Darker wet cart-rut tracks right alongside the stone road edges & ring loop
		float rut_avenues = max(
			(1.0 - smoothstep(1.8, 5.2, abs(v_rel.y))) * step(abs(v_rel.x), 58.5),
			(1.0 - smoothstep(1.8, 5.5, abs(v_rel.x))) * step(abs(v_rel.y), 52.5)
		);
		float rut_ring = max(
			(1.0 - smoothstep(1.8, 4.0, abs(abs(v_rel.x) - 36.0))) * step(abs(v_rel.y), 34.5),
			(1.0 - smoothstep(1.8, 4.0, abs(abs(v_rel.y) - 32.0))) * step(abs(v_rel.x), 38.0)
		);
		float rut_zone = max(rut_avenues, rut_ring);
		mud_col = mix(mud_col, mud_dark_color * 0.85, rut_zone * 0.58);
		vec3 verge_mix = mix(mud_verge_color, mud_col, smoothstep(0.12, 0.58, mud_mask));
		g_col = mix(g_col, verge_mix, mud_mask);
	}

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

	// 4. Expanded Coastal Golden Beach Sand & Sunlit Dune Transition (zero fragment noise!)
	float wet_gloss = 0.0;
	if (v_world_y < beach_height + beach_blend + 2.5) {
		float dune_var = smoothstep(0.24, 0.78, v_med_pat * 0.68 + v_macro_pat * 0.32);
		vec3 s_col = mix(sand_dark_color, sand_light_color, dune_var);
		// Sunlit dune crests slightly brighter warm cream
		s_col = mix(s_col, sand_light_color * 1.06, smoothstep(0.85, 0.99, v_upness) * 0.35);
		float wet_jitter = (v_med_pat - 0.5) * 1.15 + (v_macro_pat - 0.5) * 0.55;
		float wet_t = smoothstep(sea_level - 1.8, sea_level + 1.45 + wet_jitter, v_world_y);
		s_col = mix(wet_sand_color, s_col, wet_t);

		// Organic wind-blown sand-to-dune-grass boundary (no straight contour stripe)
		float beach_noise = (v_macro_pat - 0.5) * 3.8 + (v_med_pat - 0.5) * 1.9;
		float y_warped = v_world_y + beach_noise;
		float beach_mask = 1.0 - smoothstep(beach_height - beach_blend, beach_height + beach_blend, y_warped);

		// Olive-sage coastal dune scrub belt along the transition into meadow grass
		float scrub_belt = smoothstep(beach_height - beach_blend * 0.85, beach_height, y_warped) *
			(1.0 - smoothstep(beach_height + beach_blend * 0.15, beach_height + beach_blend + 1.8, y_warped));
		vec3 dune_scrub_col = vec3(0.56, 0.66, 0.28);
		ground_col = mix(ground_col, dune_scrub_col, scrub_belt * 0.55 * (1.0 - v_rock_mask));

		float eff_beach = beach_mask * (1.0 - v_rock_mask * 0.82);
		ground_col = mix(ground_col, s_col, eff_beach);
		wet_gloss = (1.0 - wet_t) * eff_beach;
	}

	float rain_w = clamp(u_weather_wetness, 0.0, 1.0);
	float rain_sheen = rain_w * (0.45 + 0.55 * v_wet_puddle) * (1.0 - snow_mask);
	ALBEDO = ground_col * v_height_shade * mix(1.0, 0.84, rain_w * (1.0 - snow_mask * 0.7));
	float dry_rough = mix(mix(surface_roughness, 0.80, snow_mask), 0.34, wet_gloss);
	ROUGHNESS = mix(dry_rough, 0.28, rain_sheen * 0.78);
	METALLIC = 0.0;
}
