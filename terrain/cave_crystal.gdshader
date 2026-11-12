shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

uniform float emission_strength : hint_range(0.2, 4.0, 0.05) = 0.92;
uniform float fresnel_power : hint_range(1.0, 6.0, 0.1) = 3.4;
uniform float striation_strength : hint_range(0.0, 1.5, 0.05) = 0.12;
uniform float pulse_speed : hint_range(0.0, 4.0, 0.1) = 1.25;

uniform sampler2D striation_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D interior_veil_tex : source_color, filter_linear_mipmap, repeat_enable;

varying float v_height01;
varying vec3 v_inst_col;
varying float v_phase;
varying float v_part_u;
varying float v_crown;
varying vec2 v_uv;
varying vec3 v_local_pos;
varying vec3 v_local_nrm;

void vertex() {
	v_height01 = clamp(UV.y, 0.0, 1.0);
	v_uv = UV;
	v_part_u = UV2.x;
	v_crown = UV2.y;
	v_local_pos = VERTEX;
	v_local_nrm = NORMAL;
	v_inst_col = COLOR.rgb;
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_phase = fract(sin(dot(world_origin.xz + world_origin.y * 0.37, vec2(12.9898, 78.233))) * 43758.5453) * 6.28318;
}

void fragment() {
	vec3 hue = v_inst_col;
	if (length(hue) < 0.05 || min(hue.r, min(hue.g, hue.b)) > 0.96) {
		hue = vec3(0.14, 0.78, 1.0);
	}
	// Rich jewel-toned absorption gradient so crystal spires stay deep sapphire/aquamarine/amethyst
	vec3 deep_hue = pow(max(hue, vec3(0.01)), vec3(2.25)) * 0.14;
	vec3 rich_hue = mix(deep_hue, hue, 0.88);
	vec3 bright_hue = mix(hue, vec3(0.86, 0.96, 1.0), 0.30);

	vec3 n_view = normalize(NORMAL);
	vec3 v_view = normalize(VIEW);
	float ndv = clamp(dot(n_view, v_view), 0.0, 1.0);
	float pulse = 0.91 + 0.09 * sin(TIME * pulse_speed + v_phase + v_height01 * 1.4);

	if (v_part_u < 0.5) {
		// Dark fractured obsidian-basalt matrix pedestal/cradle (3D object-space coords -> crisp angular stone, zero sine stripes)
		vec2 rock_uv1 = v_local_pos.xz * 0.72 + vec2(v_local_pos.y * 0.44, -v_local_pos.y * 0.38);
		vec2 rock_uv2 = v_local_pos.xy * 0.88 + vec2(-v_local_pos.z * 0.52, 0.27);
		vec4 rs1 = texture(interior_veil_tex, rock_uv1);
		vec4 rs2 = texture(interior_veil_tex, rock_uv2);
		float grain = mix(rs1.a, rs2.g, 0.45);
		float rim_stone = pow(max(1.0 - ndv, 1e-4), 3.0);
		vec3 basalt = mix(vec3(0.022, 0.028, 0.038), vec3(0.068, 0.082, 0.105), smoothstep(0.25, 0.78, grain));
		basalt += vec3(0.04, 0.09, 0.14) * rim_stone * 0.55;
		float socket_bounce = smoothstep(0.55, 1.0, v_height01) * 0.08;
		ALBEDO = basalt + deep_hue * socket_bounce;
		EMISSION = vec3(0.0);
		ROUGHNESS = 0.88;
		SPECULAR = 0.0;
		METALLIC = 0.0;
	} else {
		bool is_floating = (v_part_u > 1.5);
		// 1. Distinct flat-facet light catch using quantized flat triangle normal (clean across both prism walls & bevel crowns)
		vec3 q_n = floor(normalize(v_local_nrm) * 24.0 + 0.5);
		float facet_hash = fract(sin(dot(q_n, vec3(12.9898, 78.233, 37.719)) + v_phase * 0.31) * 43758.5453);
		float facet_shimmer = 0.64 + 0.56 * facet_hash;

		// Softened subtle quartz micro-striations along middle prism shaft (strictly off crown bevel faces)
		vec2 stria_uv = vec2(v_uv.x * 1.4, v_uv.y * 2.4);
		vec3 nrm_sample = texture(striation_normal, stria_uv).xyz;
		vec3 t_pert = vec3(nrm_sample.x * 2.0 - 1.0, nrm_sample.y * 2.0 - 1.0, 0.0) * striation_strength;
		float is_shaft = 1.0 - step(0.5, v_crown);
		float stria_mask = is_shaft * smoothstep(0.14, 0.28, v_height01) * (1.0 - smoothstep(0.62, 0.74, v_height01));

		// Crisp hexagonal rib gleams on prism walls + razor-sharp shoulder bevel highlight
		float edge_dist = abs(fract(v_uv.x * 6.0 + 0.5) - 0.5);
		float rib_gleam = is_shaft * pow(max(1.0 - smoothstep(0.0, 0.048, edge_dist), 1e-4), 2.7);
		float shoulder_gleam = pow(max(1.0 - smoothstep(0.0, 0.024, abs(v_height01 - 0.76)), 1e-4), 3.1) * 0.42;
		float edge_gleam = max(rib_gleam, shoulder_gleam);

		// 2. Clean View-Parallax Internal Phantom Planes & Chromatic Dispersion (silky gemstone depth, zero noisy dust dots)
		vec2 view_dir_xy = v_view.xy / max(abs(v_view.z) + 0.56, 0.56);
		vec2 disp_shift = normalize(view_dir_xy + vec2(0.001, 0.002)) * 0.014;
		vec2 p_uv1 = vec2(v_uv.x * 1.10, v_uv.y * 1.55) - view_dir_xy * 0.080;
		vec2 p_uv2 = vec2(v_uv.x * 1.45, v_uv.y * 2.05) - view_dir_xy * 0.175;

		vec4 v_near = texture(interior_veil_tex, p_uv1);
		vec4 v_mid = texture(interior_veil_tex, p_uv2);
		float disp_r = texture(interior_veil_tex, p_uv2 + disp_shift).g;
		float disp_b = texture(interior_veil_tex, p_uv2 - disp_shift).g;

		float cleave_raw = max(v_near.r * 0.65, v_mid.r * 0.42);
		float cleave = pow(clamp(cleave_raw, 1e-4, 1.0), 2.15);
		float inner_facet = mix(0.38, 1.0, v_near.g * 0.55 + v_mid.g * 0.45);
		float phantom_veil = v_mid.b * 0.65 + v_near.b * 0.35;
		vec3 disp_tint = vec3(
			clamp(disp_r - v_mid.g + 0.5, 0.0, 1.0),
			0.5,
			clamp(disp_b - v_mid.g + 0.5, 0.0, 1.0)
		);

		// 3. Bold Analytical Gemstone Lighting (deep sapphire shadows vs crisp faceted highlights)
		vec3 n_faceted = normalize(n_view + vec3(0.0, t_pert.y * stria_mask * 0.32, t_pert.x * 0.20 * stria_mask));
		vec3 l_key1 = normalize(vec3(0.46, 0.80, 0.38));
		vec3 l_key2 = normalize(vec3(-0.62, 0.36, 0.69));
		float diff1 = clamp(dot(n_faceted, l_key1), 0.0, 1.0);
		float diff2 = clamp(dot(n_faceted, l_key2), 0.0, 1.0);
		float facet_catch = (0.22 + 0.56 * diff1 + 0.24 * diff2) * facet_shimmer;
		if (is_floating) {
			facet_catch = max(facet_catch, 0.46);
		}

		vec3 h1 = normalize(l_key1 + v_view);
		vec3 h2 = normalize(l_key2 + v_view);
		float spec1 = pow(max(dot(n_faceted, h1), 1e-4), 140.0);
		float spec2 = pow(max(dot(n_faceted, h2), 1e-4), 76.0);

		float inv_ndv = max(1.0 - ndv, 1e-4);
		float fresnel = pow(inv_ndv, fresnel_power);

		// 4. Deep Gemstone Optical Absorption Gradient (double-ended tips glow symmetrically when floating!)
		float tip_glow = is_floating
			? max(0.36, smoothstep(0.06, 0.92, abs(v_height01 * 2.0 - 1.0)))
			: smoothstep(0.10, 0.96, v_height01);
		float root_ao = is_floating ? 1.0 : mix(0.28, 1.0, smoothstep(0.04, 0.26, v_height01));
		float thickness_absorb = mix(1.0, 0.38, pow(max(ndv, 1e-4), 1.45));

		vec3 gem_body = mix(deep_hue, rich_hue * 0.95, tip_glow);
		gem_body *= inner_facet * (0.86 + 0.28 * phantom_veil);
		gem_body += rich_hue * (cleave * 0.12) + (disp_tint - vec3(0.5)) * (cleave * 0.18);
		gem_body += bright_hue * (edge_gleam * 0.30);
		gem_body *= facet_catch * thickness_absorb;

		ALBEDO = mix(gem_body, bright_hue * facet_catch, clamp(fresnel * 0.44 + edge_gleam * 0.22, 0.0, 0.68)) * root_ao;
		EMISSION = (
			rich_hue * (0.36 * pow(max(tip_glow, 1e-4), 1.65) + cleave * 0.11 + phantom_veil * 0.14 + (inner_facet - 0.38) * 0.12)
			+ bright_hue * (fresnel * 0.48 + edge_gleam * 0.40)
			+ mix(bright_hue, vec3(0.84, 0.96, 1.0), 0.42) * (spec1 * 0.42 + spec2 * 0.22)
		) * (0.56 + 0.44 * facet_catch) * emission_strength * root_ao * pulse;

		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nrm_sample, stria_mask * 0.22);
		NORMAL_MAP_DEPTH = striation_strength * stria_mask;
		ROUGHNESS = 0.84;
		SPECULAR = 0.0;
		METALLIC = 0.0;
	}
}
