shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform bool greybox_mode = false;

uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 clay_base_color : source_color = vec3(0.60, 0.58, 0.55);
uniform vec3 rock_warm_tint : source_color = vec3(0.82, 0.76, 0.68);
uniform vec3 rock_cool_tint : source_color = vec3(0.54, 0.59, 0.68);
uniform vec3 moss_tint : source_color = vec3(0.18, 0.36, 0.13);
uniform float triplanar_scale : hint_range(0.02, 0.8, 0.01) = 0.26;
uniform float normal_bump_strength : hint_range(0.0, 2.5, 0.05) = 1.15;

// Exact CaveLayout transform & overworld meadow palette for invisible cave-to-terrain seams
uniform vec2 cave_origin_xz = vec2(-24.0, -52.0);
uniform vec2 cave_fwd_xz = vec2(-0.425105, -0.905144);
uniform vec2 cave_right_xz = vec2(0.905144, -0.425105);
uniform vec2 skylight_local_xz = vec2(-62.0, 68.0);
uniform vec3 grass_sun_color : source_color = vec3(0.32, 0.56, 0.20);
uniform vec3 grass_mid_color : source_color = vec3(0.23, 0.44, 0.15);
uniform vec3 grass_deep_color : source_color = vec3(0.15, 0.32, 0.11);
uniform vec3 terrain_rock_light : source_color = vec3(0.58, 0.60, 0.64);
uniform vec3 terrain_rock_dark : source_color = vec3(0.38, 0.40, 0.44);

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec4 v_baked; // R=AO, G=SkyVis, B=Wetness, A=Curvature
varying vec2 v_local_us;
varying float v_macro_pat;
varying float v_med_pat;
varying float v_flow_streak;
varying float v_geo_mask;
varying float v_patch_mask;
varying float v_ext_hint;

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

vec2 rot2d(vec2 uv, float s_ang, float c_ang) {
	return vec2(uv.x * c_ang - uv.y * s_ang, uv.x * s_ang + uv.y * c_ang);
}

vec3 sample_triplanar_fast(sampler2D tex, vec3 wp, vec3 wn, float sc) {
	vec3 b = abs(wn);
	b = b * b * b * b;
	b /= max(b.x + b.y + b.z, 1e-4);

	vec3 col = vec3(0.0);
	float w_sum = 0.0;
	if (b.x > 0.14) {
		col += texture(tex, wp.zy * sc).rgb * b.x;
		w_sum += b.x;
	}
	if (b.y > 0.14) {
		col += texture(tex, wp.xz * sc).rgb * b.y;
		w_sum += b.y;
	}
	if (b.z > 0.14) {
		col += texture(tex, wp.xy * sc).rgb * b.z;
		w_sum += b.z;
	}
	return col / max(w_sum, 1e-4);
}

// Non-repeating domain-warped dual-scale rotated triplanar sampler:
// Axis-weight culling skips unnecessary texture fetches on dominant planes.
vec3 sample_triplanar_nonrepeating(sampler2D tex, vec3 wp, vec3 wn, float sc, float mask_noise) {
	vec3 b = abs(wn);
	b = b * b * b * b;
	b /= max(b.x + b.y + b.z, 1e-4);

	// Organic domain warp breaks up straight UV grid lines
	vec3 warp = vec3(
		sin(wp.y * 0.43 + wp.z * 0.29),
		cos(wp.z * 0.37 + wp.x * 0.41),
		sin(wp.x * 0.33 - wp.y * 0.47)
	) * 0.68;
	vec3 p1 = wp + warp;
	vec3 p2 = wp * 0.41 - warp * 0.85 + vec3(11.7, -7.3, 19.1);
	float blend_w = smoothstep(0.24, 0.76, mask_noise);

	float s37 = 0.601815;
	float c37 = 0.798635;

	vec3 col_a = vec3(0.0);
	vec3 col_b = vec3(0.0);
	float w_sum = 0.0;
	if (b.x > 0.14) {
		col_a += texture(tex, p1.zy * sc).rgb * b.x;
		if (blend_w > 0.01) {
			col_b += texture(tex, rot2d(p2.zy * sc, s37, c37)).rgb * b.x;
		}
		w_sum += b.x;
	}
	if (b.y > 0.14) {
		col_a += texture(tex, p1.xz * sc).rgb * b.y;
		if (blend_w > 0.01) {
			col_b += texture(tex, rot2d(p2.xz * sc, s37, c37)).rgb * b.y;
		}
		w_sum += b.y;
	}
	if (b.z > 0.14) {
		col_a += texture(tex, p1.xy * sc).rgb * b.z;
		if (blend_w > 0.01) {
			col_b += texture(tex, rot2d(p2.xy * sc, s37, c37)).rgb * b.z;
		}
		w_sum += b.z;
	}
	float inv_w = 1.0 / max(w_sum, 1e-4);
	return mix(col_a, col_b, blend_w) * inv_w;
}

// Per-pixel exterior meadow coverage so curved Skylight & Entrance collars have crisp,
// organic transitions without 0.8 m triangle sawteeth while matching terrain.gdshader at seams.
float eval_mouth_pt(vec2 lus) {
	float du = abs(lus.x) / 16.5;
	float ds = abs(lus.y - 3.5) / 13.5;
	float warp = 0.025 * sin(lus.x * 0.23 + lus.y * 0.17) + 0.015 * cos(lus.x * 0.37 - lus.y * 0.29);
	return pow(du * du * du + ds * ds * ds, 1.0 / 3.0) + warp;
}

float eval_sky_pt(vec2 lus) {
	float d_sky = length(lus - (skylight_local_xz + vec2(-0.8, 0.0))) / 18.0;
	float d_exit = length(lus - vec2(-52.8, 70.2)) / 11.4;
	return min(d_sky, d_exit);
}

float eval_ext_daylight(vec3 wp, vec2 lus) {
	float mouth_pt = eval_mouth_pt(lus);
	float sky_pt = eval_sky_pt(lus);
	float d_mouth_front = (1.0 - smoothstep(-2.5, 11.5, lus.y)) * smoothstep(25.5, 28.0, wp.y);
	float d_mouth_collar = smoothstep(0.45, 0.62, mouth_pt) * (1.0 - smoothstep(1.05, 1.35, mouth_pt)) * smoothstep(26.2, 29.0, wp.y);
	float d_sky_collar = smoothstep(0.42, 0.62, sky_pt) * (1.0 - smoothstep(1.05, 1.35, sky_pt)) * smoothstep(48.5, 53.0, wp.y);
	return clamp(max(d_mouth_front, max(d_mouth_collar, d_sky_collar)), 0.0, 1.0);
}

float eval_ext_meadow(vec3 wp, vec3 wn, vec2 lus, float sky_vis, float med_pat) {
	float upness = clamp(normalize(wn).y, 0.0, 1.0);
	float slope_grass = smoothstep(0.40, 0.52, upness);
	float collar_slope = smoothstep(0.18, 0.42, upness);
	float w = (med_pat - 0.5);
	float mouth_pt = eval_mouth_pt(lus);
	float sky_pt = eval_sky_pt(lus);

	// Entrance apron (in front of mouth)
	float ext_outside_apron = (1.0 - smoothstep(-5.8 + w * 0.7, -1.6 + w * 0.7, lus.y)) * collar_slope;

	// Flanks & mouth collar: blend to meadow green before the 0.64 terrain cutout
	// without depending on baked sky_vis (prevents dark rock patches z-fighting green terrain).
	float flank_dist = abs(lus.x) - 7.0 - w * 1.2;
	float outer_seam_fill = smoothstep(8.2, 10.2, abs(lus.x) + w * 0.8);
	float flank_slope = mix(collar_slope, 1.0, outer_seam_fill);
	float ext_flanks = smoothstep(0.0, 2.8, flank_dist) * (1.0 - smoothstep(12.0, 18.0, lus.y)) * flank_slope;
	float ext_mouth_seam = smoothstep(0.56, 0.64, mouth_pt) * (1.0 - smoothstep(1.10, 1.35, mouth_pt)) * smoothstep(26.2, 28.5, wp.y) * collar_slope;

	// Back/brow top & mountain crest above mouth:
	float ext_brow_cap = smoothstep(3.5, 9.5, lus.y) * smoothstep(37.5 + w * 0.7, 41.0 + w * 0.7, wp.y) * collar_slope;

	// Skylight Rim & Spiral Ledge exit collar
	float d_sky = length(lus - (skylight_local_xz + vec2(-0.8, 0.0))) - w * 0.45;
	float ext_sky_rim = max(smoothstep(6.8, 9.2, d_sky), smoothstep(0.56, 0.64, sky_pt)) * smoothstep(50.5, 54.4, wp.y) * slope_grass;

	return clamp(max(max(ext_outside_apron, max(ext_flanks, ext_mouth_seam)), max(ext_brow_cap, ext_sky_rim)), 0.0, 1.0);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_baked = COLOR;

	vec2 d_xz = v_world_pos.xz - cave_origin_xz;
	v_local_us = vec2(dot(d_xz, cave_right_xz), dot(d_xz, cave_fwd_xz));

	// Depress outer overlap skirt (patch_t > 0.67) cleanly beneath uncut TerrainChunks
	// so CaveShell and Terrain never coplanarly z-fight or cast shadow acne at the entrance/skylight.
	float m_pt = eval_mouth_pt(v_local_us);
	float s_pt = eval_sky_pt(v_local_us);
	float p_t = min(m_pt, s_pt);
	float in_collar_zone = max(
		(1.0 - smoothstep(1.05, 1.30, m_pt)) * smoothstep(25.5, 27.0, v_world_pos.y),
		(1.0 - smoothstep(1.05, 1.30, s_pt)) * smoothstep(48.0, 52.0, v_world_pos.y)
	);
	if (p_t > 0.67 && in_collar_zone > 0.001 && v_world_nrm.y > 0.12) {
		float skirt_tuck = smoothstep(0.67, 0.77, p_t) * smoothstep(0.12, 0.45, v_world_nrm.y) * in_collar_zone * 1.15;
		VERTEX.y -= skirt_tuck;
		v_world_pos.y -= skirt_tuck;
	}

	v_macro_pat = fbm2(v_world_pos.xz * 0.025);
	v_med_pat = fbm2(v_world_pos.xz * 0.25 + vec2(5.2, -8.7));
	v_flow_streak = fbm2(v_local_us * 0.14 + vec2(3.7, -5.1));
	v_geo_mask = fbm2(v_world_pos.xz * 0.09 + vec2(v_world_pos.y * 0.17, -v_world_pos.y * 0.13));
	v_patch_mask = fbm2(v_local_us * 0.065 + vec2(13.4, -8.2));
	v_ext_hint = (v_local_us.y < 14.0 || v_world_pos.y > 35.0 || v_baked.g > 0.25) ? 1.0 : 0.0;
}

void fragment() {
	float ext_day = (v_ext_hint > 0.001) ? eval_ext_daylight(v_world_pos, v_local_us) : 0.0;
	float ao = clamp(max(v_baked.r, ext_day * 0.86), 0.08, 1.0);
	float sky_vis = clamp(max(v_baked.g, ext_day), 0.0, 1.0);
	float wet = clamp(v_baked.b, 0.0, 1.0);
	float curv = clamp(v_baked.a, 0.0, 1.0);

	// Crisp curvature shading: highlights convex rock edges and deepens recessed crevices
	float ridge_shade = mix(0.76, 1.22, smoothstep(0.22, 0.78, curv));

	if (greybox_mode) {
		vec3 bounce = mix(vec3(0.91, 0.94, 0.99), vec3(1.07, 1.01, 0.91), sky_vis);
		ALBEDO = clay_base_color * bounce * ridge_shade * mix(0.60, 1.0, ao);
		AO = ao;
		AO_LIGHT_AFFECT = 0.55;
		ROUGHNESS = 0.90;
		SPECULAR = 0.16;
		METALLIC = 0.0;
	} else {
		vec3 wn = normalize(v_world_nrm);
		float upness = clamp(wn.y, 0.0, 1.0);
		float ceiling_ness = clamp(-wn.y, 0.0, 1.0);
		float steepness = clamp(1.0 - abs(wn.y), 0.0, 1.0);
		float ext_meadow = (v_ext_hint > 0.001) ? eval_ext_meadow(v_world_pos, wn, v_local_us, sky_vis, v_med_pat) : 0.0;

		vec3 cave_albedo = vec3(0.0);
		vec3 cave_emission = vec3(0.0);
		float h_bump = 0.0;
		float cam_dist = max(-VERTEX.z, 0.0);

		if (ext_meadow < 0.9999) {
			// 3D geological noise masks interpolated from vertex() (11-15m wavelength, sub-meter mesh)
			float geo_mask = v_geo_mask;
			float patch_mask = v_patch_mask;

			vec3 rock_sample = sample_triplanar_nonrepeating(rock_texture, v_world_pos, wn, triplanar_scale, geo_mask);
			vec3 micro_sample = rock_sample;
			if (cam_dist < 36.0) {
				vec3 ms_raw = sample_triplanar_fast(rock_texture, v_world_pos * 2.45 + vec3(4.3, -2.1, 7.8), wn, triplanar_scale);
				micro_sample = mix(ms_raw, rock_sample, smoothstep(22.0, 36.0, cam_dist));
			}

			float floor_blend = smoothstep(0.58, 0.84, upness);
			vec3 floor_sample = rock_sample;
			// Mask floor gravel by low-frequency sediment patches so it never tiles across the floor
			float sediment_mask = smoothstep(0.32, 0.72, patch_mask);
			if (floor_blend > 0.06 && sediment_mask > 0.04 && cam_dist < 46.0) {
				floor_sample = sample_triplanar_fast(floor_texture, v_world_pos, wn, triplanar_scale * 1.15);
			}

			// Sedimentary karst strata bands + diagonal fracture lines break up vertical walls & ceilings
			float strata_coord = v_world_pos.y * 0.82 + geo_mask * 2.6 + sin(v_world_pos.x * 0.18 + v_world_pos.z * 0.15) * 1.1;
			float strata_band = 0.5 + 0.5 * sin(strata_coord * 3.14159);
			float strata_sharp = smoothstep(0.18, 0.82, strata_band);

			float fracture_wave = abs( fract(v_world_pos.x * 0.14 - v_world_pos.y * 0.27 + v_world_pos.z * 0.19 + geo_mask * 1.4) - 0.5 ) * 2.0;
			float fracture_crevice = smoothstep(0.04, 0.24, fracture_wave);

			// Ceiling dissolution pockets so ceilings have deep sculpted karst contrast
			float ceiling_pocket = mix(1.0, mix(0.68, 1.16, smoothstep(0.25, 0.75, geo_mask * 0.6 + strata_sharp * 0.4)), ceiling_ness * 0.85);

			float rock_luma = dot(rock_sample, vec3(0.3333));
			float micro_luma = dot(micro_sample, vec3(0.3333));
			float floor_luma = dot(floor_sample, vec3(0.3333));

			// Combined height field for screen-space derivative 3D normal bump mapping
			float tex_height = mix(rock_luma, mix(rock_luma, floor_luma, sediment_mask * 0.65), floor_blend);
			h_bump = (tex_height - 0.5) * 0.95
				+ (micro_luma - 0.5) * 0.42
				+ (strata_sharp - 0.5) * 0.38 * (1.0 - floor_blend * 0.7)
				- (1.0 - fracture_crevice) * 0.45
				+ (curv - 0.5) * 0.55;

			vec3 tint = mix(rock_cool_tint, rock_warm_tint, sky_vis);
			vec3 strata_tint = mix(vec3(0.84, 0.86, 0.92), vec3(1.12, 1.06, 0.98), strata_sharp);
			vec3 wall_col = rock_sample * tint * strata_tint * 1.92;
			wall_col *= mix(0.76, 1.22, micro_luma);
			wall_col *= mix(0.68, 1.04, fracture_crevice);
			wall_col *= ceiling_pocket;

			// Flowstone mineral streaks on steep walls
			float flow_col = smoothstep(0.35, 0.78, v_flow_streak) * pow(steepness, 1.35);
			wall_col = mix(wall_col, wall_col * vec3(0.76, 0.78, 0.72), flow_col * 0.48);

			// Cave floor: bedrock blended with noise-masked sediment gravel patches
			vec3 floor_rock = mix(rock_sample, floor_sample, sediment_mask * 0.52);
			vec3 floor_col = floor_rock * mix(vec3(0.56, 0.58, 0.63), vec3(0.78, 0.71, 0.61), sky_vis) * 1.60;
			floor_col *= mix(0.78, 1.18, micro_luma);
			floor_col *= mix(0.84, 1.08, strata_sharp);

			vec3 col = mix(wall_col, floor_col, floor_blend);

			// Sunlit moss under skylight and mouth threshold (dry upward surfaces only)
			float dry_mask = 1.0 - smoothstep(0.20, 0.55, wet);
			float moss_mask = smoothstep(0.38, 0.78, sky_vis) * smoothstep(0.52, 0.84, upness) * dry_mask * smoothstep(0.30, 0.70, geo_mask);
			col = mix(col, moss_tint * (0.75 + 0.40 * rock_sample.g), moss_mask * 0.42);

			// Wetness darkening along pools, underground lake shore, and grotto stream
			col *= mix(1.0, 0.56, wet);

			// Underwater Lake Bathymetry & Projected Seabed Caustics + Deep Crystal Trench Luminescence
			float in_uw_lake = smoothstep(126.0, 132.0, v_local_us.y) * smoothstep(-70.0, -64.0, v_local_us.x) * (1.0 - smoothstep(6.25, 6.46, v_world_pos.y));
			if (in_uw_lake > 0.001) {
				float uw_depth = clamp((6.40 - v_world_pos.y) / 5.10, 0.0, 1.0);
				// Bathymetric color shift: bright travertine/limestone mineral shoals -> cobalt shelves -> indigo trench walls
				vec3 shoal_tint = vec3(1.18, 1.24, 1.16);
				vec3 mid_tint = vec3(0.62, 0.86, 0.96);
				vec3 abyss_tint = vec3(0.32, 0.52, 0.78);
				vec3 bathy_tint = mix(shoal_tint, mid_tint, smoothstep(0.06, 0.48, uw_depth));
				bathy_tint = mix(bathy_tint, abyss_tint, smoothstep(0.48, 0.96, uw_depth));
				// Crisp contour terrace edge highlight via curvature & rock strata
				float ledge_hi = smoothstep(0.45, 0.76, curv) * (0.42 + 0.22 * upness);
				float ridge_band = mix(0.84, 1.18, strata_sharp * (0.45 + 0.55 * fracture_crevice));
				col = col * bathy_tint * ridge_band * (1.06 + ledge_hi);

				// Warped rotated dual-octave projected seabed caustics across shoals and rocky shelves (zero grid axes)
				vec2 c_warp = vec2(sin(v_world_pos.z * 0.28 + TIME * 0.11), cos(v_world_pos.x * 0.26 - TIME * 0.09)) * 0.48;
				vec2 c_p1 = rot2d(v_world_pos.xz * 0.46 + c_warp, 0.4226, 0.9063) + vec2(TIME * 0.18, -TIME * 0.14);
				vec2 c_p2 = rot2d(v_world_pos.xz * 0.64 - c_warp * 0.8, -0.7193, 0.6947) + vec2(-TIME * 0.15, TIME * 0.19);
				float cn1 = 1.0 - abs(value_noise(c_p1) * 2.0 - 1.0);
				float cn2 = 1.0 - abs(value_noise(c_p2) * 2.0 - 1.0);
				float bed_caust = pow(clamp(cn1 * cn2, 0.0, 1.0), 2.6) * (1.0 - smoothstep(0.28, 0.95, uw_depth)) * clamp(upness * 1.15 + 0.25, 0.0, 1.0) * in_uw_lake;
				col += vec3(0.14, 0.42, 0.46) * bed_caust * 0.52;
				cave_emission += vec3(0.05, 0.22, 0.28) * bed_caust * 0.38;

				// Bioluminescent sapphire-cyan radiance from the Deep Abyssal Crystal Bundle at (-14.5, 186.5)
				float d_pit = length((v_local_us - vec2(-14.5, 186.5)) / vec2(14.5, 11.5));
				float pit_glow = exp(-(d_pit * d_pit) * 1.75) * smoothstep(5.4, 2.2, v_world_pos.y) * in_uw_lake;
				cave_emission += vec3(0.06, 0.34, 0.48) * pit_glow * (0.58 + 0.42 * smoothstep(0.30, 0.72, curv));
			}

			float ridge_fade = mix(ridge_shade, 1.0, smoothstep(0.05, 0.55, ext_meadow));
			cave_albedo = mix(col, mix(col, vec3(dot(col, vec3(0.3333))), 0.15), ext_meadow * 0.3) * ridge_fade * mix(mix(0.52, 1.0, ao), 1.0, smoothstep(0.05, 0.55, ext_meadow));
		}

		vec3 final_albedo = cave_albedo;
		vec3 final_emission = cave_emission * (1.0 - ext_meadow);
		float final_ao = ao;
		float final_ao_affect = 0.68;
		float final_rough = mix(0.86, 0.34, wet);
		float final_spec = mix(0.16, 0.42, wet);

		if (ext_meadow > 0.001) {
			float canopy_blend = v_macro_pat * 0.70 + v_med_pat * 0.30;
			vec3 g_col = mix(grass_deep_color, grass_mid_color, smoothstep(0.28, 0.58, canopy_blend));
			g_col = mix(g_col, grass_sun_color, smoothstep(0.52, 0.82, canopy_blend));
			float height_shade = clamp(0.95 + (v_world_pos.y - 22.0) * 0.0004, 0.92, 1.02);
			vec3 terrain_match = g_col * height_shade;

			final_albedo = mix(cave_albedo, terrain_match, ext_meadow);
			final_ao = mix(ao, 1.0, ext_meadow);
			final_ao_affect = mix(0.68, 0.0, ext_meadow);
			final_rough = mix(final_rough, 0.92, ext_meadow);
			final_spec = mix(final_spec, 0.5, ext_meadow);
			vec3 view_up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			NORMAL = normalize(mix(NORMAL, view_up, ext_meadow * 0.55));
		}

		// Mikkelsen screen-space derivative 3D normal perturbation:
		// Gives cave walls, ceilings, and floors real 3D rock facets and crevice relief under cave lights
		float bump_mask = (1.0 - smoothstep(0.0, 0.45, ext_meadow)) * normal_bump_strength;
		if (bump_mask > 0.01) {
			vec3 dpdx = dFdx(VERTEX);
			vec3 dpdy = dFdy(VERTEX);
			float dhdx = dFdx(h_bump);
			float dhdy = dFdy(h_bump);
			vec3 r1 = cross(dpdy, NORMAL);
			vec3 r2 = cross(NORMAL, dpdx);
			float det = dot(dpdx, r1);
			if (abs(det) > 1e-6) {
				vec3 surf_grad = sign(det) * (dhdx * r1 + dhdy * r2);
				NORMAL = normalize(NORMAL - bump_mask * 0.16 * surf_grad);
			}
		}

		ALBEDO = final_albedo;
		EMISSION = final_emission;
		AO = final_ao;
		AO_LIGHT_AFFECT = final_ao_affect;
		ROUGHNESS = final_rough;
		SPECULAR = final_spec;
		METALLIC = 0.0;
	}
}

void light() {
	float ext_day_l = (v_ext_hint > 0.001) ? eval_ext_daylight(v_world_pos, v_local_us) : 0.0;
	float sky_vis_l = clamp(max(v_baked.g, ext_day_l), 0.0, 1.0);
	float ext_m = 0.0;
	if (LIGHT_IS_DIRECTIONAL) {
		ext_m = (v_ext_hint > 0.001) ? eval_ext_meadow(v_world_pos, v_world_nrm, v_local_us, sky_vis_l, v_med_pat) : 0.0;
	}

	// Block outdoor directional sunlight from leaking through solid underground mountain rock
	// (even when directional shadows are disabled on the Low quality preset!)
	float sun_gate = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		float sky_open = smoothstep(0.08, 0.58, sky_vis_l);
		sun_gate = max(sky_open, ext_m);
	}

	float ndotl = dot(NORMAL, LIGHT);
	float diff_wrap_cave = max(0.0, (ndotl + 0.18) / 1.18);
	float diff_wrap_meadow = clamp((ndotl + ROUGHNESS) / ((1.0 + ROUGHNESS) * (1.0 + ROUGHNESS)), 0.0, 1.0);
	float diff_wrap = mix(diff_wrap_cave, diff_wrap_meadow, ext_m);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff_wrap * sun_gate / PI;

	float spec_mask = 1.0 - ext_m;
	if (ndotl > 0.0 && sun_gate > 0.01 && spec_mask > 0.001) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndoth = max(0.0, dot(NORMAL, half_vec));
		float spec_pow = mix(8.0, 64.0, 1.0 - ROUGHNESS);
		float spec_val = pow(ndoth, spec_pow) * 0.12 * spec_mask;
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * ndotl * spec_val * sun_gate;
	}
}
