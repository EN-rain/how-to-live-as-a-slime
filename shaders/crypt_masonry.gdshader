shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

// World-space triplanar carved crypt limestone/slate masonry, chiseled flagstones,
// aged ironwork, damp moss & soot crevices — pairs organically with landmark_rock.gdshader.
uniform sampler2D rock_detail_tex : source_color, filter_linear_mipmap, repeat_enable;

// Mode selector: 0 = Floor Flagstones, 1 = Ashlar Retaining/Portal Wall, 2 = Carved Dark Trim/Pillars, 3 = Forged Ironwork
uniform float surface_mode : hint_range(0.0, 3.0, 1.0) = 0.0;
uniform float block_scale = 1.65;
uniform float bump_strength : hint_range(0.0, 2.0, 0.05) = 1.15;
uniform float moss_strength : hint_range(0.0, 1.0, 0.05) = 0.35;
uniform float base_roughness : hint_range(0.1, 1.0, 0.02) = 0.86;
uniform float spec_scale : hint_range(0.0, 1.0, 0.02) = 1.0;
uniform float metallic_amt : hint_range(0.0, 1.0, 0.05) = 0.0;

uniform vec3 stone_dark : source_color = vec3(0.16, 0.16, 0.19);
uniform vec3 stone_mid : source_color = vec3(0.32, 0.31, 0.30);
uniform vec3 stone_warm : source_color = vec3(0.42, 0.38, 0.33);
uniform vec3 mortar_tint : source_color = vec3(0.06, 0.06, 0.07);
uniform vec3 moss_tint : source_color = vec3(0.19, 0.38, 0.14);

uniform float moss_sky_y = 22.0; // Higher exposure near/above sunken stairwell rim gets richer moss
uniform vec3 abyss_glow_pos = vec3(-820.0, 4.0, 228.0);
uniform vec3 abyss_glow_col : source_color = vec3(0.34, 0.16, 0.56);
uniform float abyss_glow_radius = 28.0;

varying vec3 v_world_pos;
varying vec3 v_world_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 41.3);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm2(vec2 p) {
	return 0.62 * vnoise(p) + 0.38 * vnoise(p * 2.13 + vec2(11.3, -7.1));
}

vec3 sample_triplanar(vec3 wp, vec3 bw, float sc) {
	vec3 cx = texture(rock_detail_tex, wp.zy * sc).rgb;
	vec3 cy = texture(rock_detail_tex, wp.xz * sc).rgb;
	vec3 cz = texture(rock_detail_tex, wp.xy * sc).rgb;
	return cx * bw.x + cy * bw.y + cz * bw.z;
}

// Evaluates staggered masonry block mask + edge bevel + per-block random seed on a 2D face coordinate
vec3 eval_masonry_2d(vec2 uv, float row_stagger, float aspect_x) {
	vec2 p = vec2(uv.x / aspect_x, uv.y);
	// Slight organic hand-cut chisel wobble on joints
	float wobble = (vnoise(uv * 2.4) - 0.5) * 0.065;
	p += vec2(wobble, wobble * 0.8);

	float row = floor(p.y);
	p.x += mod(row, 2.0) * row_stagger;
	vec2 cell = floor(p);
	vec2 f = fract(p);

	float seed = hash21(cell + vec2(17.0, 53.0));
	// Vary slab width slightly by merging neighbor sub-blocks deterministically
	float edge_x = min(f.x, 1.0 - f.x) * aspect_x;
	float edge_y = min(f.y, 1.0 - f.y);
	float edge_d = min(edge_x, edge_y);

	float mortar = smoothstep(0.015, 0.068, edge_d);
	float bevel = smoothstep(0.055, 0.16, edge_d);
	return vec3(mortar, bevel, seed);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 wn = normalize(v_world_nrm);
	vec3 an = abs(wn);
	vec3 bw = pow(max(an, vec3(0.001)), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);

	vec3 tri_a = sample_triplanar(v_world_pos, bw, 0.28);
	vec3 tri_b = sample_triplanar(v_world_pos + vec3(7.3, 1.9, -4.1), bw, 0.85);
	float tex_luma = clamp(dot(tri_a * 0.65 + tri_b * 0.35, vec3(0.3333)), 0.0, 1.0);
	float macro_n = fbm2(v_world_pos.xz * 0.14 + vec2(v_world_pos.y * 0.21, -v_world_pos.y * 0.17));
	float fine_pit = fbm2(vec2(v_world_pos.x + v_world_pos.z * 0.7, v_world_pos.y * 1.15) * 2.2);

	// Select best planar projection for masonry joints per normal axis
	vec2 m_uv = v_world_pos.xz * block_scale;
	float stagger = 0.5;
	float aspect = 1.35;
	if (an.y < 0.55) {
		m_uv = (an.z >= an.x) ? v_world_pos.xy : v_world_pos.zy;
		m_uv *= block_scale;
		aspect = 1.85;
	}
	vec3 block_info = eval_masonry_2d(m_uv, stagger, aspect);
	float mortar = block_info.x;
	float bevel = block_info.y;
	float bseed = block_info.z;

	// Weathering variation per stone block & chisel edge wear
	float block_tone = 0.80 + 0.36 * bseed;
	vec3 stone_base = mix(stone_dark, stone_mid, smoothstep(0.18, 0.78, tex_luma * 0.68 + fine_pit * 0.32));
	stone_base = mix(stone_base, stone_warm, macro_n * 0.42 + (1.0 - bevel) * 0.26 * mortar);
	stone_base *= block_tone;

	// Mode modulation
	if (surface_mode > 0.5 && surface_mode < 1.5) {
		// Mode 1: Aged Ashlar Retaining Wall & Portal Stone (darker soot in lower courses, chiseled relief)
		float wall_soot = smoothstep(0.15, 0.90, fract(v_world_pos.y * 0.18 + macro_n * 0.35));
		stone_base *= mix(0.84, 1.08, wall_soot);
	} else if (surface_mode >= 1.5 && surface_mode < 2.5) {
		// Mode 2: Dark Gothic Pillars & Relief Trim
		stone_base = mix(stone_base * 0.80, stone_warm * 0.72, (1.0 - bevel) * 0.35);
	} else if (surface_mode >= 2.5) {
		// Mode 3: Blackened Forged Wrought Iron (matte charcoal-iron, never pale silver outdoors)
		stone_base = mix(vec3(0.022, 0.024, 0.028), vec3(0.068, 0.072, 0.078), tex_luma * 0.65 + fine_pit * 0.35);
		mortar = mix(mortar, 1.0, 0.85);
	}

	// Deep mortar shadow in block joints
	float joint_factor = (surface_mode >= 2.5) ? 0.25 : 1.0;
	vec3 albedo = mix(mortar_tint, stone_base, mix(1.0, mortar, joint_factor));

	// Creeping crypt moss along stairwell upper rim, damp fissures & block crevices
	float upper_sun_weight = smoothstep(moss_sky_y - 9.0, moss_sky_y + 4.5, v_world_pos.y);
	float up_face = smoothstep(0.25, 0.88, wn.y);
	float crevice_moss = (1.0 - mortar * 0.75) * smoothstep(0.42, 0.76, macro_n + bseed * 0.25);
	float moss_mask = clamp((up_face * 0.55 + crevice_moss * 0.65) * mix(0.28, 1.0, upper_sun_weight) * moss_strength, 0.0, 0.82);
	albedo = mix(albedo, moss_tint * (0.75 + 0.5 * tex_luma), moss_mask);

	// Subtle crack darkening
	float crack = smoothstep(0.02, 0.16, abs(macro_n * 1.6 + fine_pit * 0.7 - 1.15));
	albedo *= mix(0.68, 1.0, crack);

	// Subterranean Sanctum Abyssal violet floor bounce
	float d_abyss = distance(v_world_pos, abyss_glow_pos);
	float abyss_w = (1.0 - smoothstep(4.0, abyss_glow_radius, d_abyss)) * smoothstep(2.0, -2.5, v_world_pos.y - abyss_glow_pos.y);
	vec3 emission = abyss_glow_col * abyss_w * 0.16;

	// Mikkelsen derivative bump mapping for crisp chiseled grooves + rock grain
	float h_bump = mortar * 0.42 + bevel * 0.22 + tex_luma * 0.26 + fine_pit * 0.16;
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
			NORMAL = normalize(NORMAL - bump_strength * 0.11 * surf_grad);
		}
	}

	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = clamp(mix(base_roughness + 0.08, base_roughness - 0.06, tex_luma) + moss_mask * 0.10, 0.25, 0.98);
	METALLIC = metallic_amt;
	SPECULAR = ((surface_mode >= 2.5) ? 0.34 : 0.24) * spec_scale;
	AO = clamp(mix(0.32, 1.0, mortar) * mix(0.74, 1.0, crack), 0.22, 1.0);
	AO_LIGHT_AFFECT = 0.72;
}
