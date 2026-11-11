shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform bool greybox_mode = false;

uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 clay_base_color : source_color = vec3(0.60, 0.58, 0.55);
uniform vec3 rock_warm_tint : source_color = vec3(0.82, 0.76, 0.68);
uniform vec3 rock_cool_tint : source_color = vec3(0.54, 0.59, 0.68);
uniform vec3 moss_tint : source_color = vec3(0.36, 0.70, 0.24);
uniform float triplanar_scale : hint_range(0.02, 0.8, 0.01) = 0.26;
uniform float normal_bump_strength : hint_range(0.0, 2.5, 0.05) = 1.15;

// Exact CaveLayout transform & overworld meadow palette for invisible cave-to-terrain seams
uniform vec2 cave_origin_xz = vec2(-72.9, -126.9);
uniform vec2 cave_fwd_xz = vec2(-0.425105, -0.905144);
uniform vec2 cave_right_xz = vec2(0.905144, -0.425144);
uniform vec2 skylight_local_xz = vec2(-62.0, 68.0);
uniform vec3 grass_sun_color : source_color = vec3(0.48, 0.84, 0.28);
uniform vec3 grass_mid_color : source_color = vec3(0.36, 0.72, 0.22);
uniform vec3 grass_deep_color : source_color = vec3(0.28, 0.62, 0.18);
uniform vec3 terrain_rock_light : source_color = vec3(0.58, 0.60, 0.64);
uniform vec3 terrain_rock_dark : source_color = vec3(0.38, 0.40, 0.44);

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec4 v_baked; // R=AO, G=SkyVis, B=Wetness, A=Curvature
varying vec2 v_local_us;
varying float v_macro_pat;
varying float v_med_pat;
varying float v_flow_streak;
varying float v_ext_meadow;

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

// Non-repeating domain-warped dual-scale rotated triplanar sampler:
// Eliminates visible Cartesian grid tiling across expansive cave walls, ceilings, and floors.
vec3 sample_triplanar_nonrepeating(sampler2D tex, vec3 wp, vec3 wn, float sc, float mask_noise) {
	vec3 b = abs(wn);
	b = pow(max(b, vec3(0.0001)), vec3(3.2));
	b /= (b.x + b.y + b.z);

	// Organic domain warp breaks up straight UV grid lines
	vec3 warp = vec3(
		sin(wp.y * 0.43 + wp.z * 0.29),
		cos(wp.z * 0.37 + wp.x * 0.41),
		sin(wp.x * 0.33 - wp.y * 0.47)
	) * 0.68;
	vec3 p1 = wp + warp;
	vec3 p2 = wp * 0.41 - warp * 0.85 + vec3(11.7, -7.3, 19.1);

	// Scale A (medium crisp rock detail)
	vec3 cx1 = texture(tex, p1.zy * sc).rgb;
	vec3 cy1 = texture(tex, p1.xz * sc).rgb;
	vec3 cz1 = texture(tex, p1.xy * sc).rgb;
	vec3 col_a = cx1 * b.x + cy1 * b.y + cz1 * b.z;

	// Scale B (macro rotated by 37 deg so features never align with Scale A)
	float s37 = 0.601815;
	float c37 = 0.798635;
	vec3 cx2 = texture(tex, rot2d(p2.zy * sc, s37, c37)).rgb;
	vec3 cy2 = texture(tex, rot2d(p2.xz * sc, s37, c37)).rgb;
	vec3 cz2 = texture(tex, rot2d(p2.xy * sc, s37, c37)).rgb;
	vec3 col_b = cx2 * b.x + cy2 * b.y + cz2 * b.z;

	float blend_w = smoothstep(0.24, 0.76, mask_noise);
	return mix(col_a, col_b, blend_w);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_baked = COLOR;

	vec2 d_xz = v_world_pos.xz - cave_origin_xz;
	v_local_us = vec2(dot(d_xz, cave_right_xz), dot(d_xz, cave_fwd_xz));

	v_macro_pat = fbm2(v_world_pos.xz * 0.025);
	v_med_pat = fbm2(v_world_pos.xz * 0.25 + vec2(5.2, -8.7));
	v_flow_streak = fbm2(v_local_us * 0.14 + vec2(3.7, -5.1));

	// Compute meadow coverage in vertex shader
	float upness = clamp(v_world_nrm.y, 0.0, 1.0);
	float slope_grass = smoothstep(0.55, 0.72, upness);
	float ext_outside_apron = smoothstep(-11.0, -16.0, v_local_us.y) * slope_grass;
	float ext_flanks = smoothstep(12.0, 18.0, abs(v_local_us.x)) * smoothstep(0.50, 0.85, v_baked.g) * slope_grass;
	float ext_mountain_top = smoothstep(46.0, 52.0, v_world_pos.y) * slope_grass;
	float d_sky = length(v_local_us - skylight_local_xz);
	float ext_sky_rim = smoothstep(7.5, 12.0, d_sky) * smoothstep(51.0, 55.0, v_world_pos.y) * slope_grass;
	v_ext_meadow = clamp(max(max(ext_outside_apron, ext_flanks), max(ext_mountain_top, ext_sky_rim)), 0.0, 1.0);
}

void fragment() {
	float ao = clamp(v_baked.r, 0.08, 1.0);
	float sky_vis = clamp(v_baked.g, 0.0, 1.0);
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
		float ext_meadow = v_ext_meadow;

		vec3 cave_albedo = vec3(0.0);
		float h_bump = 0.0;

		if (ext_meadow < 0.9999) {
			// 3D geological noise masks for non-repeating texture blending, strata, and crevices
			float geo_mask = fbm2(v_world_pos.xz * 0.09 + vec2(v_world_pos.y * 0.17, -v_world_pos.y * 0.13));
			float patch_mask = fbm2(v_local_us * 0.065 + vec2(13.4, -8.2));

			vec3 rock_sample = sample_triplanar_nonrepeating(rock_texture, v_world_pos, wn, triplanar_scale, geo_mask);
			vec3 micro_sample = sample_triplanar_nonrepeating(rock_texture, v_world_pos * 2.45 + vec3(4.3, -2.1, 7.8), wn, triplanar_scale, 1.0 - geo_mask);

			float floor_blend = smoothstep(0.58, 0.84, upness);
			vec3 floor_sample = rock_sample;
			// Mask floor gravel by low-frequency sediment patches so it never tiles across the floor
			float sediment_mask = smoothstep(0.32, 0.72, patch_mask);
			if (floor_blend > 0.01) {
				floor_sample = sample_triplanar_nonrepeating(floor_texture, v_world_pos, wn, triplanar_scale * 1.15, patch_mask);
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
			vec3 wall_col = rock_sample * tint * strata_tint * 2.55;
			wall_col *= mix(0.76, 1.22, micro_luma);
			wall_col *= mix(0.68, 1.04, fracture_crevice);
			wall_col *= ceiling_pocket;

			// Flowstone mineral streaks on steep walls
			float flow_col = smoothstep(0.35, 0.78, v_flow_streak) * pow(steepness, 1.35);
			wall_col = mix(wall_col, wall_col * vec3(0.76, 0.78, 0.72), flow_col * 0.48);

			// Cave floor: bedrock blended with noise-masked sediment gravel patches
			vec3 floor_rock = mix(rock_sample, floor_sample, sediment_mask * 0.52);
			vec3 floor_col = floor_rock * mix(vec3(0.56, 0.58, 0.63), vec3(0.78, 0.71, 0.61), sky_vis) * 2.15;
			floor_col *= mix(0.78, 1.18, micro_luma);
			floor_col *= mix(0.84, 1.08, strata_sharp);

			vec3 col = mix(wall_col, floor_col, floor_blend);

			// Sunlit moss under skylight and mouth threshold (dry upward surfaces only)
			float dry_mask = 1.0 - smoothstep(0.20, 0.55, wet);
			float moss_mask = smoothstep(0.38, 0.78, sky_vis) * smoothstep(0.52, 0.84, upness) * dry_mask * smoothstep(0.30, 0.70, geo_mask);
			col = mix(col, moss_tint * (0.75 + 0.40 * rock_sample.g), moss_mask * 0.42);

			// Wetness darkening along pools, underground lake, and grotto stream
			col *= mix(1.0, 0.52, wet);
			cave_albedo = col * ridge_shade * mix(0.52, 1.0, ao);
		}

		vec3 final_albedo = cave_albedo;
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
			final_spec = mix(final_spec, 0.0, ext_meadow);
		}

		// Mikkelsen screen-space derivative 3D normal perturbation:
		// Gives cave walls, ceilings, and floors real 3D rock facets and crevice relief under cave lights
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
				NORMAL = normalize(NORMAL - bump_mask * 0.16 * surf_grad);
			}
		}

		ALBEDO = final_albedo;
		AO = final_ao;
		AO_LIGHT_AFFECT = final_ao_affect;
		ROUGHNESS = final_rough;
		SPECULAR = final_spec;
		METALLIC = 0.0;
	}
}

void light() {
	// Block outdoor directional sunlight from leaking through solid underground mountain rock
	// (even when directional shadows are disabled on the Low quality preset!)
	float sun_gate = 1.0;
	if (LIGHT_IS_DIRECTIONAL) {
		float sky_open = smoothstep(0.08, 0.58, clamp(v_baked.g, 0.0, 1.0));
		sun_gate = max(sky_open, clamp(v_ext_meadow, 0.0, 1.0));
	}

	float ndotl = dot(NORMAL, LIGHT);
	float diff_wrap = max(0.0, (ndotl + 0.18) / 1.18);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * diff_wrap * sun_gate / PI;

	if (ndotl > 0.0 && sun_gate > 0.01) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndoth = max(0.0, dot(NORMAL, half_vec));
		float spec_pow = mix(8.0, 64.0, 1.0 - ROUGHNESS);
		float spec_val = pow(ndoth, spec_pow) * 0.12;
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * ndotl * spec_val * sun_gate;
	}
}
