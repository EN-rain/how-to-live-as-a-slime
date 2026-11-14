shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

// Aged carved limestone/basalt, kiln-charred ancient oak planks, forged wrought iron,
// and tarnished dull bronze — zero neon emission, lit naturally by flickering brazier fire.
uniform sampler2D detail_veil_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cave_rock_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 v_local_pos;
varying vec3 v_local_nrm;
varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec2 v_uv;
varying vec2 v_uv2;
varying vec4 v_col;

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

vec3 sample_world_rock(vec3 wp, vec3 wn) {
	vec3 b = pow(max(abs(wn), vec3(1e-4)), vec3(3.2));
	b /= (b.x + b.y + b.z);
	vec3 warp = vec3(
		sin(wp.y * 0.43 + wp.z * 0.29),
		cos(wp.z * 0.37 + wp.x * 0.41),
		sin(wp.x * 0.33 - wp.y * 0.47)
	) * 0.68;
	vec3 p1 = (wp + warp) * 0.26;
	vec3 col = vec3(0.0);
	if (b.x > 0.04) col += texture(cave_rock_tex, p1.zy).rgb * b.x;
	if (b.y > 0.04) col += texture(cave_rock_tex, p1.xz).rgb * b.y;
	if (b.z > 0.04) col += texture(cave_rock_tex, p1.xy).rgb * b.z;
	return col;
}

void vertex() {
	v_local_pos = VERTEX;
	v_local_nrm = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_uv = UV;
	v_uv2 = UV2;
	v_col = COLOR;
}

void fragment() {
	vec3 wn = normalize(v_world_nrm);
	float mat_id = v_uv2.x;
	float phase = v_uv2.y;
	float ao = clamp(v_col.r, 0.12, 1.0);
	float bevel_hint = clamp(v_col.g, 0.0, 1.0);
	float accent_hint = clamp(v_col.b, 0.0, 1.0);

	// Triplanar stone/metal/wood micro-detail in door-local space
	vec3 an = abs(normalize(v_local_nrm));
	vec3 bw = pow(max(an, vec3(1e-4)), vec3(3.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 veil_x = texture(detail_veil_tex, v_local_pos.zy * 0.34 + vec2(0.13, -0.07));
	vec4 veil_y = texture(detail_veil_tex, v_local_pos.xz * 0.34 + vec2(-0.19, 0.23));
	vec4 veil_z = texture(detail_veil_tex, v_local_pos.xy * 0.34 + vec2(0.07, 0.17));
	vec4 veil_a = veil_x * bw.x + veil_y * bw.y + veil_z * bw.z;
	vec2 tri_uv = (an.z >= an.x && an.z >= an.y)
		? v_local_pos.xy
		: ((an.x >= an.y) ? v_local_pos.zy : v_local_pos.xz);
	vec4 veil_b = texture(detail_veil_tex, tri_uv * 0.78 + vec2(-0.31, 0.29));
	float grain = mix(veil_a.g, veil_b.a, 0.45);
	float vein = veil_a.r * 0.65 + veil_b.b * 0.35;
	float block_var = 0.88 + 0.24 * fract(phase * 3.71 + 0.17);
	float organic_var = (0.90 + 0.20 * smoothstep(0.18, 0.84, grain * 0.7 + vein * 0.3)) * block_var;

	float uv_edge_x = min(v_uv.x, 1.0 - v_uv.x);
	float uv_edge_y = min(v_uv.y, 1.0 - v_uv.y);
	// Soft natural edge wear without hard rectangular UV-border outlines
	float crisp_edge = (1.0 - smoothstep(0.0, 0.16, min(uv_edge_x, uv_edge_y))) * bevel_hint * 0.42;
	float h_bump = 0.0;
	float bump_strength = 0.0;

	if (mat_id < 0.5) {
		// ZONE 0: Weathered Cut Ashlar Limestone / Basalt Stone + Damp Moss & Soot
		float geo_mask = fbm2(v_world_pos.xz * 0.11 + vec2(v_world_pos.y * 0.19, -v_world_pos.y * 0.15));
		vec3 rock_sample = sample_world_rock(v_world_pos, wn);
		float rock_luma = dot(rock_sample, vec3(0.3333));
		float pit_noise = fbm2(tri_uv * 2.4 + vec2(phase * 3.1, -phase * 2.7));
		float strata_coord = v_world_pos.y * 0.82 + geo_mask * 2.6 + sin(v_world_pos.x * 0.18 + v_world_pos.z * 0.15) * 1.1;
		float strata_sharp = smoothstep(0.18, 0.82, 0.5 + 0.5 * sin(strata_coord * 3.14159));
		float fracture_wave = abs(fract(v_world_pos.x * 0.14 - v_world_pos.y * 0.27 + v_world_pos.z * 0.19 + geo_mask * 1.4) - 0.5) * 2.0;
		float fracture_crevice = smoothstep(0.04, 0.24, fracture_wave);

		vec3 strata_tint = mix(vec3(0.84, 0.86, 0.92), vec3(1.12, 1.06, 0.98), strata_sharp);
		vec3 cave_limestone = rock_sample * vec3(0.54, 0.59, 0.68) * strata_tint * 1.92;
		cave_limestone *= mix(0.78, 1.18, grain);
		cave_limestone *= mix(0.68, 1.04, fracture_crevice);

		vec3 dark_carved = vec3(0.095, 0.091, 0.085);
		vec3 mid_carved = vec3(0.215, 0.203, 0.184);
		vec3 warm_chisel = vec3(0.285, 0.252, 0.214);
		vec3 carved_stone = mix(dark_carved, mid_carved, smoothstep(0.18, 0.84, rock_luma * 0.48 + grain * 0.30 + pit_noise * 0.22));
		carved_stone = mix(carved_stone, warm_chisel, crisp_edge * 0.28 + smoothstep(0.74, 0.95, vein) * 0.12);
		carved_stone *= organic_var * mix(0.88, 1.10, pit_noise);

		// Damp cave moss on upward stone ledges and near the damp cavern floor
		float floor_damp = smoothstep(1.85, 0.05, v_local_pos.y);
		float moss_mask = max(smoothstep(0.30, 0.78, wn.y) * 0.75, floor_damp * 0.85)
			* smoothstep(0.42, 0.82, grain * 0.65 + geo_mask * 0.35)
			* (1.0 - smoothstep(0.35, 0.90, accent_hint));
		carved_stone = mix(carved_stone, vec3(0.085, 0.145, 0.068), moss_mask * 0.52);

		// Subtle mortar & weathering grime without harsh cartoony black outlines
		float soot_crevice = clamp((1.0 - ao) * 0.65 + (1.0 - fracture_crevice) * 0.20, 0.0, 0.50);
		carved_stone = mix(carved_stone, vec3(0.042, 0.038, 0.035), soot_crevice * 0.36);

		float rock_blend = smoothstep(0.08, 0.94, accent_hint);
		vec3 final_stone = mix(carved_stone, cave_limestone, rock_blend);
		ALBEDO = final_stone * mix(0.62, 1.0, ao);
		ROUGHNESS = mix(
			clamp(0.94 + moss_mask * 0.04, 0.90, 0.99),
			0.96,
			rock_blend
		);
		METALLIC = 0.0;
		SPECULAR = mix(0.04, 0.03, rock_blend);
		EMISSION = vec3(0.0);
		AO = mix(0.42, 1.0, ao);
		AO_LIGHT_AFFECT = 0.55;
		h_bump = (rock_luma - 0.5) * 1.15 + (grain - 0.5) * 0.72 + (pit_noise - 0.5) * 0.95 + (strata_sharp - 0.5) * 0.38 - (1.0 - fracture_crevice) * 0.48;
		bump_strength = 2.65;
	} else if (mat_id < 1.5) {
		// ZONE 1: Monolithic Carved Ancient Granite / Basalt Stone Door Slabs (no brick grid)
		vec3 rock_sample = sample_world_rock(v_world_pos * 1.45, wn);
		float rock_luma = dot(rock_sample, vec3(0.3333));
		float slab_pat = fbm2(tri_uv * 1.35 + vec2(phase * 3.7, -phase * 2.1));
		float pit_noise = fbm2(tri_uv * 3.6 + vec2(phase * 2.3, -phase * 1.9));
		float fracture_wave = abs(fract(v_local_pos.x * 0.22 - v_local_pos.y * 0.31 + slab_pat * 1.2) - 0.5) * 2.0;
		float fracture_crack = smoothstep(0.025, 0.14, fracture_wave);

		vec3 dark_granite = vec3(0.090, 0.108, 0.132);
		vec3 mid_granite = vec3(0.185, 0.205, 0.232);
		vec3 chiseled_edge = vec3(0.265, 0.285, 0.315);
		vec3 door_stone = mix(dark_granite, mid_granite, smoothstep(0.16, 0.84, rock_luma * 0.48 + slab_pat * 0.30 + pit_noise * 0.22));
		door_stone = mix(door_stone, chiseled_edge, crisp_edge * 0.32 + smoothstep(0.68, 0.94, vein) * 0.16);
		door_stone *= mix(0.74, 1.04, fracture_crack);

		// Damp green moss near the bottom of the stone door slabs & recessed coffer corners
		float bottom_moss = smoothstep(1.65, 0.05, v_local_pos.y) * smoothstep(0.42, 0.82, slab_pat * 0.5 + grain * 0.5);
		door_stone = mix(door_stone, vec3(0.075, 0.138, 0.062), bottom_moss * 0.55);
		door_stone = mix(door_stone, vec3(0.032, 0.036, 0.042), (1.0 - ao) * 0.30);

		ALBEDO = door_stone * mix(0.60, 1.0, ao);
		ROUGHNESS = clamp(0.94 + (1.0 - ao) * 0.04 + bottom_moss * 0.03, 0.90, 0.99);
		METALLIC = 0.0;
		SPECULAR = 0.04;
		EMISSION = vec3(0.0);
		AO = mix(0.45, 1.0, ao);
		AO_LIGHT_AFFECT = 0.55;
		h_bump = (rock_luma - 0.5) * 1.15 + (pit_noise - 0.5) * 1.00 + (grain - 0.5) * 0.68 - (1.0 - fracture_crack) * 0.55;
		bump_strength = 2.75;
	} else if (mat_id < 2.5) {
		// ZONE 2: Forged Hammered Wrought Iron (Straps, Rivets, Lock-Bar, Door Rings, Cauldron)
		float hammer = texture(detail_veil_tex, tri_uv * 1.45 + vec2(phase * 0.31, -phase * 0.19)).g;
		vec3 deep_iron = vec3(0.044, 0.046, 0.052);
		vec3 forged_iron = vec3(0.135, 0.138, 0.148);
		vec3 edge_steel = vec3(0.245, 0.238, 0.230);
		vec3 rust_patina = vec3(0.165, 0.088, 0.044);

		vec3 iron_col = mix(deep_iron, forged_iron, smoothstep(0.20, 0.82, hammer * 0.6 + grain * 0.4));
		iron_col = mix(iron_col, edge_steel, crisp_edge * 0.35);
		float rust_mask = clamp((1.0 - ao) * 0.72 + smoothstep(0.62, 0.90, vein) * 0.32, 0.0, 0.72);
		iron_col = mix(iron_col, rust_patina, rust_mask * 0.40);

		ALBEDO = iron_col * mix(0.62, 1.0, ao);
		ROUGHNESS = clamp(0.64 + rust_mask * 0.22 - crisp_edge * 0.06, 0.56, 0.88);
		METALLIC = clamp(0.65 - rust_mask * 0.28, 0.32, 0.68);
		SPECULAR = 0.22;
		EMISSION = vec3(0.0);
		AO = mix(0.50, 1.0, ao);
		AO_LIGHT_AFFECT = 0.50;
		h_bump = (hammer - 0.5) * 0.62;
		bump_strength = 0.76;
	} else {
		// ZONE 3: Tarnished Dull Ancient Bronze (Central Lock Escutcheon & Brazier Rim Accent)
		vec3 dull_bronze = vec3(0.28, 0.20, 0.10);
		vec3 worn_bronze = vec3(0.46, 0.34, 0.16);
		vec3 verdigris = vec3(0.06, 0.15, 0.13);
		float hammered = smoothstep(0.22, 0.80, grain * 0.65 + vein * 0.35);
		vec3 brass = mix(dull_bronze, worn_bronze, hammered * 0.58 + crisp_edge * 0.28);
		float tarnish = clamp((1.0 - ao) * 0.78 + (1.0 - hammered) * 0.24, 0.0, 0.80);
		brass = mix(brass, verdigris, tarnish * 0.52);

		ALBEDO = brass * mix(0.62, 1.0, ao);
		ROUGHNESS = clamp(0.66 + tarnish * 0.22 - crisp_edge * 0.06, 0.58, 0.88);
		METALLIC = clamp(0.64 - tarnish * 0.26, 0.34, 0.66);
		SPECULAR = 0.24;
		EMISSION = vec3(0.0);
		AO = mix(0.50, 1.0, ao);
		AO_LIGHT_AFFECT = 0.50;
		h_bump = (hammered - 0.5) * 0.48;
		bump_strength = 0.62;
	}

	if (bump_strength > 0.01) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhdx = dFdx(h_bump);
		float dhdy = dFdy(h_bump);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		if (abs(det) > 1e-6) {
			vec3 surf_grad = sign(det) * (dhdx * r1 + dhdy * r2);
			NORMAL = normalize(NORMAL - bump_strength * 0.15 * surf_grad);
		}
	}
}

void light() {
	float sun_gate = LIGHT_IS_DIRECTIONAL ? 0.0 : 1.0;
	float ndotl = dot(NORMAL, LIGHT);
	float diff_wrap = max(0.0, (ndotl + 0.18) / 1.18);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff_wrap * sun_gate / PI;

	if (ndotl > 0.0 && sun_gate > 0.01) {
		// Zero specular on rough non-metals (stone & ancient oak); keep subtle patina glint on iron/bronze
		float matte_gate = (1.0 - smoothstep(0.68, 0.88, ROUGHNESS)) * smoothstep(0.15, 0.55, METALLIC);
		if (matte_gate > 0.005) {
			vec3 half_vec = normalize(LIGHT + VIEW);
			float ndoth = max(0.0, dot(NORMAL, half_vec));
			float spec_pow = mix(12.0, 64.0, 1.0 - ROUGHNESS);
			float spec_scale = mix(0.05, 0.30, METALLIC) * matte_gate;
			SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * ndotl * pow(ndoth, spec_pow) * spec_scale * sun_gate;
		}
	}
}
