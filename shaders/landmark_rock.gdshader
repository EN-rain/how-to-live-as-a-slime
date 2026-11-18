shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_warm_tint : source_color = vec3(0.84, 0.77, 0.67);
uniform vec3 rock_cool_tint : source_color = vec3(0.52, 0.56, 0.65);
uniform vec3 moss_tint : source_color = vec3(0.18, 0.38, 0.14);
uniform float triplanar_scale : hint_range(0.02, 0.8, 0.01) = 0.26;
uniform float normal_bump_strength : hint_range(0.0, 2.5, 0.05) = 1.18;

uniform float meadow_blend_enable = 1.0;
uniform float meadow_sky_min : hint_range(0.3, 0.99, 0.01) = 0.72;
uniform vec3 grass_sun_color : source_color = vec3(0.32, 0.56, 0.20);
uniform vec3 grass_mid_color : source_color = vec3(0.23, 0.44, 0.15);
uniform vec3 grass_deep_color : source_color = vec3(0.15, 0.32, 0.11);

uniform vec3 abyss_glow_pos = vec3(0.0, -9999.0, 0.0);
uniform vec3 abyss_glow_col : source_color = vec3(0.14, 0.42, 0.48);
uniform float abyss_glow_radius = 12.0;
uniform float rough_dry : hint_range(0.3, 1.0, 0.01) = 0.86;
uniform float rough_wet : hint_range(0.2, 1.0, 0.01) = 0.32;
uniform float spec_dry : hint_range(0.0, 0.6, 0.01) = 0.16;
uniform float spec_wet : hint_range(0.0, 0.6, 0.01) = 0.44;
uniform float spec_light_strength : hint_range(0.0, 0.3, 0.005) = 0.14;
uniform float bump_detail_scale : hint_range(0.01, 0.25, 0.005) = 0.052;

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec4 v_baked; // R=AO, G=SkyVis, B=Wetness, A=Curvature
varying float v_macro_pat;
varying float v_med_pat;
varying float v_flow_streak;
varying float v_geo_mask;
varying float v_patch_mask;

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

vec3 sample_triplanar_nonrepeating(sampler2D tex, vec3 wp, vec3 wn, float sc, float mask_noise) {
	vec3 b = abs(wn);
	b = pow(max(b, vec3(0.0001)), vec3(3.2));
	b /= (b.x + b.y + b.z);

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
	if (b.x > 0.045) {
		col_a += texture(tex, p1.zy * sc).rgb * b.x;
		if (blend_w > 0.01) {
			col_b += texture(tex, rot2d(p2.zy * sc, s37, c37)).rgb * b.x;
		}
		w_sum += b.x;
	}
	if (b.y > 0.045) {
		col_a += texture(tex, p1.xz * sc).rgb * b.y;
		if (blend_w > 0.01) {
			col_b += texture(tex, rot2d(p2.xz * sc, s37, c37)).rgb * b.y;
		}
		w_sum += b.y;
	}
	if (b.z > 0.045) {
		col_a += texture(tex, p1.xy * sc).rgb * b.z;
		if (blend_w > 0.01) {
			col_b += texture(tex, rot2d(p2.xy * sc, s37, c37)).rgb * b.z;
		}
		w_sum += b.z;
	}
	float inv_w = 1.0 / max(w_sum, 1e-4);
	return mix(col_a, col_b, blend_w) * inv_w;
}

float eval_ext_meadow(vec3 wn, float sky_vis, float med_pat) {
	if (meadow_blend_enable < 0.5) {
		return 0.0;
	}
	float upness = clamp(normalize(wn).y, 0.0, 1.0);
	float slope_grass = smoothstep(0.44, 0.64, upness);
	float sky_mask = smoothstep(meadow_sky_min, min(meadow_sky_min + 0.16, 0.995), sky_vis + (med_pat - 0.5) * 0.12);
	return clamp(slope_grass * sky_mask, 0.0, 1.0);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_baked = COLOR;

	v_macro_pat = fbm2(v_world_pos.xz * 0.025);
	v_med_pat = fbm2(v_world_pos.xz * 0.25 + vec2(5.2, -8.7));
	v_flow_streak = fbm2(v_world_pos.xz * 0.14 + vec2(3.7, -5.1));
	v_geo_mask = fbm2(v_world_pos.xz * 0.09 + vec2(v_world_pos.y * 0.17, -v_world_pos.y * 0.13));
	v_patch_mask = fbm2(v_world_pos.xz * 0.065 + vec2(13.4, -8.2));
}

void fragment() {
	float ao = clamp(v_baked.r, 0.08, 1.0);
	float sky_vis = clamp(v_baked.g, 0.0, 1.0);
	float wet = clamp(v_baked.b, 0.0, 1.0);
	float curv = clamp(v_baked.a, 0.0, 1.0);

	float ridge_shade = mix(0.76, 1.22, smoothstep(0.22, 0.78, curv));
	vec3 wn = normalize(v_world_nrm);
	float upness = clamp(wn.y, 0.0, 1.0);
	float ceiling_ness = clamp(-wn.y, 0.0, 1.0);
	float steepness = clamp(1.0 - abs(wn.y), 0.0, 1.0);
	float ext_meadow = eval_ext_meadow(wn, sky_vis, v_med_pat);

	vec3 cave_albedo = vec3(0.0);
	vec3 cave_emission = vec3(0.0);
	float h_bump = 0.0;
	float cam_dist = max(-VERTEX.z, 0.0);

	if (ext_meadow < 0.9999) {
		float geo_mask = v_geo_mask;
		float patch_mask = v_patch_mask;

		vec3 rock_sample = sample_triplanar_nonrepeating(rock_texture, v_world_pos, wn, triplanar_scale, geo_mask);
		vec3 micro_sample = rock_sample;
		if (cam_dist < 58.0) {
			vec3 ms_raw = sample_triplanar_nonrepeating(rock_texture, v_world_pos * 2.45 + vec3(4.3, -2.1, 7.8), wn, triplanar_scale, 1.0 - geo_mask);
			micro_sample = mix(ms_raw, rock_sample, smoothstep(38.0, 58.0, cam_dist));
		}

		float floor_blend = smoothstep(0.58, 0.84, upness);
		vec3 floor_sample = rock_sample;
		float sediment_mask = smoothstep(0.32, 0.72, patch_mask);
		if (floor_blend > 0.02 && sediment_mask > 0.005 && cam_dist < 62.0) {
			floor_sample = sample_triplanar_nonrepeating(floor_texture, v_world_pos, wn, triplanar_scale * 1.15, patch_mask);
		}

		float strata_coord = v_world_pos.y * 0.82 + geo_mask * 2.6 + sin(v_world_pos.x * 0.18 + v_world_pos.z * 0.15) * 1.1;
		float strata_band = 0.5 + 0.5 * sin(strata_coord * 3.14159);
		float strata_sharp = smoothstep(0.18, 0.82, strata_band);

		float fracture_wave = abs(fract(v_world_pos.x * 0.14 - v_world_pos.y * 0.27 + v_world_pos.z * 0.19 + geo_mask * 1.4) - 0.5) * 2.0;
		float fracture_crevice = smoothstep(0.04, 0.24, fracture_wave);

		float ceiling_pocket = mix(1.0, mix(0.68, 1.16, smoothstep(0.25, 0.75, geo_mask * 0.6 + strata_sharp * 0.4)), ceiling_ness * 0.85);

		float rock_luma = dot(rock_sample, vec3(0.3333));
		float micro_luma = dot(micro_sample, vec3(0.3333));
		float floor_luma = dot(floor_sample, vec3(0.3333));

		// Smooth macro/strata relief dominates bump gradient (avoids 2x2 quad JPEG-block checkerboard)
		float smooth_luma = rock_luma * 0.65 + micro_luma * 0.35;
		float tex_height = mix(smooth_luma, mix(smooth_luma, floor_luma, sediment_mask * 0.55), floor_blend);
		h_bump = (tex_height - 0.5) * 0.42
			+ (strata_sharp - 0.5) * 0.46 * (1.0 - floor_blend * 0.65)
			- (1.0 - fracture_crevice) * 0.36
			+ (curv - 0.5) * 0.52;

		vec3 tint = mix(rock_cool_tint, rock_warm_tint, clamp(sky_vis + 0.15, 0.0, 1.0));
		vec3 strata_tint = mix(vec3(0.84, 0.86, 0.92), vec3(1.12, 1.06, 0.98), strata_sharp);
		vec3 wall_col = rock_sample * tint * strata_tint * 1.92;
		wall_col *= mix(0.76, 1.22, micro_luma);
		wall_col *= mix(0.68, 1.04, fracture_crevice);
		wall_col *= ceiling_pocket;

		float flow_col = smoothstep(0.35, 0.78, v_flow_streak) * pow(steepness, 1.35);
		wall_col = mix(wall_col, wall_col * vec3(0.76, 0.78, 0.72), flow_col * 0.48);

		vec3 floor_rock = mix(rock_sample, floor_sample, sediment_mask * 0.52);
		vec3 floor_col = floor_rock * mix(vec3(0.58, 0.60, 0.64), vec3(0.80, 0.72, 0.60), sky_vis) * 1.60;
		floor_col *= mix(0.78, 1.18, micro_luma);
		floor_col *= mix(0.84, 1.08, strata_sharp);

		vec3 col = mix(wall_col, floor_col, floor_blend);

		float dry_mask = 1.0 - smoothstep(0.20, 0.55, wet);
		float moss_mask = smoothstep(0.28, 0.72, sky_vis) * smoothstep(0.45, 0.82, upness) * dry_mask * smoothstep(0.28, 0.68, geo_mask);
		col = mix(col, moss_tint * (0.72 + 0.36 * rock_sample.g), moss_mask * 0.38);

		col *= mix(1.0, 0.54, wet);

		float d_glow = length(v_world_pos - abyss_glow_pos) / max(abyss_glow_radius, 0.1);
		float g_mask = exp(-(d_glow * d_glow) * 1.5);
		cave_emission += abyss_glow_col * g_mask * (0.45 + 0.45 * wet) * (1.0 - sky_vis);

		cave_albedo = col * ridge_shade * mix(0.52, 1.0, ao);
	}

	vec3 final_albedo = cave_albedo;
	vec3 final_emission = cave_emission * (1.0 - ext_meadow);
	float final_ao = ao;
	float final_ao_affect = 0.68;
	float final_rough = mix(rough_dry, rough_wet, wet);
	float final_spec = mix(spec_dry, spec_wet, wet);

	if (ext_meadow > 0.001) {
		float canopy_blend = v_macro_pat * 0.70 + v_med_pat * 0.30;
		vec3 g_col = mix(grass_deep_color, grass_mid_color, smoothstep(0.28, 0.58, canopy_blend));
		g_col = mix(g_col, grass_sun_color, smoothstep(0.52, 0.82, canopy_blend));
		final_albedo = mix(cave_albedo, g_col, ext_meadow);
		final_ao = mix(ao, 1.0, ext_meadow);
		final_ao_affect = mix(0.68, 0.0, ext_meadow);
		final_rough = mix(final_rough, 0.92, ext_meadow);
		final_spec = mix(final_spec, 0.5, ext_meadow);
	}

	float bump_mask = (1.0 - ext_meadow) * normal_bump_strength;
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
			NORMAL = normalize(NORMAL - bump_mask * bump_detail_scale * surf_grad);
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

void light() {
	float sky_vis_l = clamp(v_baked.g, 0.0, 1.0);
	float ext_m = eval_ext_meadow(v_world_nrm, sky_vis_l, v_med_pat);

	float sun_gate = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		float sky_open = smoothstep(0.06, 0.52, sky_vis_l);
		sun_gate = max(sky_open, ext_m);
	}

	float ndotl = dot(NORMAL, LIGHT);
	float diff_wrap_cave = max(0.0, (ndotl + 0.22) / 1.22);
	float diff_wrap_meadow = clamp((ndotl + ROUGHNESS) / ((1.0 + ROUGHNESS) * (1.0 + ROUGHNESS)), 0.0, 1.0);
	float diff_wrap = mix(diff_wrap_cave, diff_wrap_meadow, ext_m);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff_wrap * sun_gate / PI;

	float spec_mask = 1.0 - ext_m;
	if (ndotl > 0.0 && sun_gate > 0.01 && spec_mask > 0.001) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndoth = max(0.0, dot(NORMAL, half_vec));
		float spec_pow = mix(8.0, 64.0, 1.0 - ROUGHNESS);
		float spec_val = pow(ndoth, spec_pow) * spec_light_strength * smoothstep(0.97, 0.45, ROUGHNESS) * spec_mask;
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * ndotl * spec_val * sun_gate;
	}
}
