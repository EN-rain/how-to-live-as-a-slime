shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

global uniform float u_weather_wetness;

group_uniforms MeadowGrass;
uniform vec3 grass_sun_color : source_color = vec3(0.32, 0.56, 0.20);
uniform vec3 grass_mid_color : source_color = vec3(0.23, 0.44, 0.15);
uniform vec3 grass_deep_color : source_color = vec3(0.15, 0.32, 0.11);

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
uniform vec2 u_webwood_center = vec2(-410.0, 480.0);
uniform vec2 u_webwood_trail_start = vec2(-335.0, 390.0);
uniform vec2 u_webwood_trail_bend = vec2(-396.0, 468.0);
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

float seg_dist2d(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	// 1. Rich Natural Meadow with organic loam & moss mottling (zero procedural noise in fragment!)
	float canopy_blend = v_macro_pat * 0.68 + v_med_pat * 0.32;
	vec3 g_col = mix(grass_deep_color, grass_mid_color, smoothstep(0.25, 0.56, canopy_blend));
	g_col = mix(g_col, grass_sun_color, smoothstep(0.50, 0.82, canopy_blend));
	// Subtle dry clover & warm soil pockets breaking up uniform grass expanses (linear RGB!)
	float loam_pocket = smoothstep(0.68, 0.90, v_med_pat) * (1.0 - smoothstep(0.45, 0.75, v_macro_pat));
	g_col = mix(g_col, vec3(0.068, 0.085, 0.018), loam_pocket * 0.36);

	// 1b. Regional World Biome Ground Palettes (all literals in LINEAR RGB space!)
	float w_noise = (v_macro_pat - 0.5) * 14.0 + (v_med_pat - 0.5) * 7.5;
	// Highland Alpine Tundra & Heather above 58m
	float highland_t = smoothstep(56.0, 96.0, v_world_y + (v_macro_pat - 0.5) * 12.0);
	vec3 highland_col = mix(vec3(0.042, 0.088, 0.020), vec3(0.068, 0.054, 0.026), smoothstep(0.40, 0.78, v_med_pat));
	g_col = mix(g_col, highland_col, highland_t * 0.62);

	// Webwood Spider Domain: Wide deep mossy leaf-litter humus + silk-dusted nest clearing
	vec2 d_spider_v = v_xz - u_webwood_center;
	float d_spider = length(d_spider_v);
	if (d_spider < 194.0) {
		float w_web = 1.0 - smoothstep(78.0, 184.0, d_spider + w_noise * 1.45);
		vec3 forest_moss = mix(vec3(0.010, 0.028, 0.014), vec3(0.026, 0.034, 0.030), smoothstep(0.24, 0.76, v_med_pat));
		g_col = mix(g_col, forest_moss, w_web * 0.93);
		float glade_dirt = (1.0 - smoothstep(4.0, 24.0, d_spider + w_noise * 1.3)) * smoothstep(0.19, 0.73, v_med_pat);
		vec3 spider_earth = mix(vec3(0.032, 0.038, 0.026), vec3(0.072, 0.068, 0.064), smoothstep(0.32, 0.82, v_med_pat));
		g_col = mix(g_col, spider_earth, glade_dirt * 0.72);
		float silk_dust = (1.0 - smoothstep(8.0, 24.0, d_spider + w_noise * 0.45)) * smoothstep(0.46, 0.84, v_med_pat);
		g_col = mix(g_col, vec3(0.14, 0.17, 0.20), silk_dust * 0.26);
	}

	// Wolf Pack Crag (290, -240): Wide alpine pine-needle floor + heather pockets + granite gravel clearing at the den
	vec2 d_wolf_v = v_xz - vec2(290.0, -240.0);
	float d_wolf = length(d_wolf_v);
	if (d_wolf < 145.0) {
		float w_crag = 1.0 - smoothstep(48.0, 136.0, d_wolf + w_noise * 1.35);
		vec3 pine_duff = mix(vec3(0.024, 0.046, 0.015), vec3(0.058, 0.036, 0.017), smoothstep(0.24, 0.80, v_med_pat));
		g_col = mix(g_col, pine_duff, w_crag * 0.82);
		float den_scree = 1.0 - smoothstep(12.0, 32.0, length(v_xz - vec2(290.0, -242.0)) + w_noise * 0.60);
		vec3 scree_col = mix(vec3(0.056, 0.052, 0.044), vec3(0.095, 0.088, 0.076), smoothstep(0.22, 0.78, v_med_pat));
		g_col = mix(g_col, scree_col, den_scree * 0.76);
	}

	// Sunken Swamp Ruins & Undercroft Rat Warren (-235, 395..545): Expanded bog moss, peaty marsh soil & wet shoreline mud (zero fragment noise!)
	float d_rat = length(v_xz - vec2(-235.0, 460.0));
	float swamp_wet_gloss = 0.0;
	if (d_rat < 178.0) {
		float w_rat = 1.0 - smoothstep(58.0, 164.0, d_rat + w_noise * 1.35);
		vec3 bog_moss = mix(vec3(0.013, 0.036, 0.015), vec3(0.038, 0.048, 0.017), smoothstep(0.24, 0.78, v_med_pat));
		g_col = mix(g_col, bog_moss, w_rat * 0.80);
		float court_earth = 1.0 - smoothstep(26.0, 62.0, length((v_xz - vec2(-235.0, 454.0)) * vec2(0.76, 0.70)) + w_noise * 0.65);
		vec3 court_loam = mix(mud_dark_color * 0.56, vec3(0.042, 0.046, 0.028), smoothstep(0.25, 0.75, v_med_pat));
		g_col = mix(g_col, court_loam, court_earth * 0.60);
		float bog_bank = (1.0 - smoothstep(21.22, 21.92, v_world_y + (v_med_pat - 0.5) * 0.24)) * (1.0 - smoothstep(82.0, 136.0, d_rat));
		vec3 peat_mud = mix(vec3(0.018, 0.019, 0.013), mud_dark_color * 0.58, smoothstep(0.25, 0.75, v_med_pat));
		g_col = mix(g_col, peat_mud, bog_bank * 0.84);
		swamp_wet_gloss = bog_bank * smoothstep(0.75, 0.94, v_upness) * 0.68;
		float rat_mud = 1.0 - smoothstep(4.2, 9.8, length(v_xz - vec2(-235.0, 418.0)) + w_noise * 0.35);
		g_col = mix(g_col, mix(mud_dark_color * 0.74, mud_light_color * 0.68, v_med_pat), rat_mud * 0.64);
	}

	// Skeleton Crypt Moorland (-820, 326): Somber weathered moss & stone approach soil
	float d_skel = length(v_xz - vec2(-820.0, 328.0));
	if (d_skel < 108.0) {
		float w_sk = 1.0 - smoothstep(36.0, 102.0, d_skel + w_noise * 1.25);
		vec3 moor_col = mix(vec3(0.024, 0.068, 0.017), vec3(0.046, 0.064, 0.021), smoothstep(0.24, 0.76, v_med_pat));
		g_col = mix(g_col, moor_col, w_sk * 0.68);
		float plaza_verge = 1.0 - smoothstep(10.0, 23.0, length(v_xz - vec2(-820.0, 338.0)) + w_noise * 0.45);
		vec3 verge_rock = mix(vec3(0.046, 0.045, 0.038), vec3(0.068, 0.064, 0.052), smoothstep(0.25, 0.75, v_med_pat));
		g_col = mix(g_col, verge_rock, plaza_verge * 0.68);
	}

	// 1c. Winding Continent Dirt Trails linking World Hubs (zero fragment noise!)
	if (v_world_y > beach_height + 0.8 && v_world_y < 105.0) {
		float road_wobble = (v_macro_pat - 0.5) * 8.0 + (v_med_pat - 0.5) * 3.2;
		float d_path = 1e6;
		// Central Basin -> Crystal Cave trail
		d_path = min(d_path, seg_dist2d(v_xz, vec2(0.0, 12.0), vec2(-16.0, -28.0)));
		// Central Basin -> Webwood Spider Forest -> Gnawed Ruins South Approach (clean valley routing, zero hillside gashes!)
		d_path = min(d_path, seg_dist2d(v_xz, vec2(0.0, 12.0), vec2(-105.0, 140.0)));
		d_path = min(d_path, seg_dist2d(v_xz, vec2(-105.0, 140.0), vec2(-220.0, 260.0)));
		d_path = min(d_path, seg_dist2d(v_xz, vec2(-220.0, 260.0), u_webwood_trail_start));
		d_path = min(d_path, seg_dist2d(v_xz, u_webwood_trail_start, u_webwood_trail_bend));
		d_path = min(d_path, seg_dist2d(v_xz, vec2(-235.0, 512.0), vec2(-235.0, 565.0)));
		// Webwood Junction -> Skeleton Crypt Western Road
		d_path = min(d_path, seg_dist2d(v_xz, u_webwood_trail_start, vec2(-530.0, 316.0)));
		d_path = min(d_path, seg_dist2d(v_xz, vec2(-530.0, 316.0), vec2(-820.0, 344.0)));
		// Central Basin -> Wolf Pack Crag NE Foothill Trail
		d_path = min(d_path, seg_dist2d(v_xz, vec2(10.0, 0.0), vec2(150.0, -125.0)));
		d_path = min(d_path, seg_dist2d(v_xz, vec2(150.0, -125.0), vec2(284.0, -234.0)));
		if (d_path < 11.0) {
			float p_dist = d_path + road_wobble * 0.42;
			float trail_mask = (1.0 - smoothstep(2.2, 5.2, p_dist)) * smoothstep(0.55, 0.82, v_upness);
			float rut_core = 1.0 - smoothstep(0.6, 2.3, p_dist);
			vec3 trail_col = mix(mud_verge_color * 0.72, mix(mud_dark_color, mud_light_color, v_med_pat * 0.65), smoothstep(0.15, 0.70, trail_mask));
			trail_col = mix(trail_col, mud_dark_color * 0.76, rut_core * 0.45);
			g_col = mix(g_col, trail_col, trail_mask * 0.88);
		}
	}

	// Slope Soil/Gravel Verge right below rocky cliffs
	float slope_soil = (1.0 - smoothstep(0.52, 0.78, v_upness)) * (1.0 - v_rock_mask);
	g_col = mix(g_col, mix(vec3(0.066, 0.048, 0.025), mud_dark_color * 0.90, v_med_pat), slope_soil * 0.64);

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
	float wet_gloss = swamp_wet_gloss;
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
		vec3 dune_scrub_col = vec3(0.24, 0.34, 0.062);
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
