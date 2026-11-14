shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform bool is_waterfall = false;
uniform vec3 shallow_color : source_color = vec3(0.14, 0.56, 0.64);
uniform vec3 deep_color : source_color = vec3(0.02, 0.13, 0.24);
uniform vec3 foam_color : source_color = vec3(0.84, 0.96, 1.0);
uniform vec3 waterfall_impact_world = vec3(0.0);
uniform float flow_speed : hint_range(0.0, 4.0, 0.05) = 0.75;

uniform vec3 slime_pos = vec3(9999.0, -9999.0, 9999.0);
uniform vec3 slime_vel = vec3(0.0);
uniform float slime_radius = 1.6;
uniform float slime_submersion = 0.0;
uniform int active_wake_count = 0;
uniform vec4 wake_points[12]; // .xz = world position, .y = age (<0 unused), .w = initial energy

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_world_pos;
varying vec2 v_uv;
varying vec4 v_col;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// Value noise + analytic derivative vec3(val, d/dx, d/dy) using 1 hash block instead of 3 finite diffs
vec3 value_noise_grad(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k3 = a - b - c + d;
	return vec3(
		a + k1 * u.x + k2 * u.y + k3 * u.x * u.y,
		du.x * (k1 + k3 * u.y),
		du.y * (k2 + k3 * u.x)
	);
}

float caustic_web(vec2 p, float t_val) {
	mat2 rot37 = mat2(vec2(0.7986, -0.6018), vec2(0.6018, 0.7986));
	vec2 p1 = p * 1.45 + vec2(t_val * 0.14, -t_val * 0.11);
	vec2 p2 = (rot37 * p) * 1.85 + vec2(-t_val * 0.12 + 7.3, t_val * 0.15 - 4.1);
	float n1 = 1.0 - abs(value_noise(p1) * 2.0 - 1.0);
	float n2 = 1.0 - abs(value_noise(p2) * 2.0 - 1.0);
	float ridge = n1 * n1 * (0.45 + 0.55 * n2);
	return pow(clamp(max(n1 * n2, ridge * 0.92), 1e-4, 1.0), 2.4);
}

// Returns vec3(height_delta, dH_dx, dH_dz) for both vertex displacement and crisp normal-mapped surface waves.
vec3 sample_cave_waves(vec2 world_xz, float time_val, float feather) {
	float h = 0.0;
	vec2 grad = vec2(0.0);

	// 1. Ambient cross-capillary wavelets (non-axis-aligned vectors avoid Cartesian stripes)
	vec2 wv1 = vec2(1.18, 0.74);
	vec2 wv2 = vec2(-0.88, 1.52);
	float p1 = dot(world_xz, wv1) + time_val * 1.55 + sin(dot(world_xz, vec2(-0.42, 0.55))) * 0.55;
	float p2 = dot(world_xz, wv2) - time_val * 1.25 + cos(dot(world_xz, vec2(0.52, 0.44))) * 0.55;
	h += (sin(p1) * 0.011 + cos(p2) * 0.008) * feather;
	grad += wv1 * (cos(p1) * 0.011 * feather) + wv2 * (-sin(p2) * 0.008 * feather);

	// 2. Waterfall radial wave train
	vec2 d_wf_v = world_xz - waterfall_impact_world.xz;
	float d_wf = length(d_wf_v);
	if (d_wf > 0.05 && d_wf < 12.5) {
		vec2 dir_wf = d_wf_v / d_wf;
		float wf_env = (1.0 - smoothstep(1.2, 12.0, d_wf)) * feather;
		float ph_wf = d_wf * 3.8 - time_val * 5.6;
		h += sin(ph_wf) * 0.038 * wf_env;
		grad += dir_wf * (cos(ph_wf) * 3.8 * 0.038 * wf_env);
	}

	float rad_s = max(slime_radius, 0.45);
	float sub_mask = smoothstep(0.025, 0.25, slime_submersion) * feather;

	// 3. Active Slime Meniscus & Isotropic Capillary Rim Waves (velocity-angle invariant)
	if (sub_mask > 0.001) {
		vec2 rel = world_xz - slime_pos.xz;
		float d_s = length(rel);
		if (d_s < 13.5) {
			vec2 r_dir = d_s > 1e-4 ? rel / d_s : vec2(1.0, 0.0);
			float sig_dimple = max(rad_s * 0.94, 0.45);
			float d_dimp = d_s / sig_dimple;
			float dimple = -0.065 * slime_submersion * exp(-(d_dimp * d_dimp));
			float sig_lip = max(rad_s * 0.46, 0.36);
			float r_diff = d_s - rad_s * 1.04;
			float r_norm = r_diff / sig_lip;
			float lip = 0.022 * slime_submersion * exp(-(r_norm * r_norm));
			h += (dimple + lip) * feather;
			float d_dimple_dr = (-2.0 * d_s / (sig_dimple * sig_dimple)) * dimple;
			float d_lip_dr = (-2.0 * r_diff / (sig_lip * sig_lip)) * lip;
			grad += r_dir * ((d_dimple_dr + d_lip_dr) * feather);

			// Tight propagating concentric ripple wavelets around swimming slime
			float rip_env = (1.0 - smoothstep(rad_s * 0.72, rad_s + 7.2, d_s)) * exp(-max(d_s - rad_s * 0.65, 0.0) * 0.38) * sub_mask;
			float k_rip = 3.8;
			float ph_rip = d_s * k_rip - time_val * 5.2;
			h += sin(ph_rip) * 0.013 * rip_env;
			grad += r_dir * (cos(ph_rip) * k_rip * 0.013 * rip_env);
		}
	}

	// 4. Pooled 12-Slot Trailing Wake Packets
	if (active_wake_count > 0) {
		for (int i = 0; i < 12; i++) {
			vec4 wp = wake_points[i];
			float age = wp.y;
			if (age >= 0.0 && age < 2.6 && wp.w > 0.01) {
				vec2 rel_w = world_xz - wp.xz;
				float dw = length(rel_w);
				if (dw < 10.5 && dw > 0.04) {
					float r_cur = rad_s * 0.46 + age * 2.05;
					float band_w = 0.42 + age * 0.32;
					float dist_w = dw - r_cur;
					float dw_n = dist_w / band_w;
					float w_env = exp(-(dw_n * dw_n)) * exp(-age * 1.22) * wp.w * feather;
					if (w_env > 0.004) {
						float k_w = 4.4;
						float ph_w = dist_w * k_w - age * 2.2;
						h += sin(ph_w) * 0.018 * w_env;
						grad += (rel_w / dw) * (cos(ph_w) * k_w * 0.018 * w_env);
					}
				}
			}
		}
	}

	return vec3(h, grad.x, grad.y);
}

void vertex() {
	v_uv = UV;
	v_col = COLOR;
	if (!is_waterfall) {
		v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float feather = clamp(v_col.r, 0.0, 1.0);
		if (feather > 0.005) {
			float is_stream_v = clamp(v_col.g, 0.0, 1.0);
			vec3 wv = sample_cave_waves(v_world_pos.xz, TIME, feather);
			VERTEX.y += wv.x * (1.0 - 0.62 * is_stream_v);
		}
	} else {
		float side_s = sin(clamp(UV.x, 0.0, 1.0) * 3.14159);
		float fall_s = smoothstep(0.10, 0.30, UV.y);
		float is_veil_v = step(0.5, v_col.r);
		float surge_amp = mix(0.080, 0.135, is_veil_v);
		float flutter = sin(UV.y * 13.0 - TIME * 12.0 + UV.x * 6.5) * 0.65
			+ cos(UV.y * 23.0 - TIME * 17.5 - UV.x * 11.0) * 0.35;
		float sway = sin(UV.y * 5.5 - TIME * 5.2) * cos(UV.x * 9.0 + TIME * 2.1) * 0.045;
		VERTEX += NORMAL * (flutter * surge_amp * side_s * fall_s + sway * fall_s);
		v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
}

void fragment() {
	if (is_waterfall) {
		bool is_veil = (v_col.r >= 0.5);
		float y_acc = v_uv.y * (0.64 + v_uv.y * 0.72);
		// Domain warp so falling water strands curve, braid & break cleanly
		float wx = value_noise(vec2(v_uv.x * 4.4, y_acc * 3.1 - TIME * 2.8)) - 0.5;
		float wy = value_noise(vec2(v_uv.x * 5.2 + 7.1, y_acc * 4.0 - TIME * 3.9)) - 0.5;
		float ux = v_uv.x + wx * mix(0.09, 0.16, is_veil ? 1.0 : 0.0);
		float uy = y_acc + wy * 0.06;

		vec3 s1_g = value_noise_grad(vec2(ux * 7.8, uy * 4.4 - TIME * 5.2));
		float streak1 = s1_g.x;
		float streak2 = value_noise(vec2(ux * 15.5 + 3.7, uy * 8.6 - TIME * 8.1));
		float droplets = value_noise(vec2(ux * 29.0 - 2.1, uy * 15.0 - TIME * 11.8));
		float du = s1_g.y * 0.18;
		float dv = s1_g.z * 0.14;
		NORMAL = normalize(NORMAL + TANGENT * du + BINORMAL * dv);

		// Organic edge erosion on left/right edges so cascade blends smoothly into water;
		// minimal top fade only inside the shadowed stone spring fissure so spout lip stays full & solid
		float edge_sine = sin(clamp(v_uv.x, 0.0, 1.0) * 3.14159);
		float edge_noise = (streak2 * 0.65 + droplets * 0.35 - 0.48) * (is_veil ? 0.54 : 0.32);
		float side_fade = smoothstep(0.04, is_veil ? 0.52 : 0.38, edge_sine + edge_noise);
		float top_fade = smoothstep(0.0, 0.03, v_uv.y);
		float bot_fade = 1.0 - smoothstep(0.84, 1.00, v_uv.y);
		float end_fade = top_fade * bot_fade;

		float core_veins = smoothstep(0.24, 0.74, streak1 * 0.50 + streak2 * 0.34 + droplets * 0.16);
		float aerated = smoothstep(is_veil ? 0.36 : 0.42, 0.84, streak2 * 0.56 + droplets * 0.44);
		float spark = pow(clamp(droplets * streak2 * 1.65, 0.0, 1.0), 3.2);
		float lip_spill = exp(-pow((v_uv.y - 0.16) / 0.075, 2.0)) * top_fade;

		float foam_w = clamp(aerated * (is_veil ? 0.85 : 0.65) + lip_spill * 0.62 + spark * 0.45, 0.0, 1.0);
		vec3 base_aqua = mix(vec3(0.08, 0.46, 0.60), shallow_color, 0.65);
		vec3 wf_col = mix(base_aqua, foam_color, foam_w);
		float veil_fade = is_veil ? (0.30 + 0.58 * aerated + 0.35 * spark) : (0.54 + 0.38 * core_veins);

		ALBEDO = wf_col;
		EMISSION = wf_col * (0.16 + 0.24 * core_veins + 0.28 * aerated + 0.30 * spark) * end_fade;
		ROUGHNESS = mix(0.14, 0.36, foam_w);
		SPECULAR = 0.48;
		ALPHA = clamp(side_fade * end_fade * veil_fade * (is_veil ? 0.76 : 0.92), 0.0, 0.92);
	} else {
		float depth_raw = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view_pos.xyz /= view_pos.w;
		float linear_depth = -view_pos.z;
		float water_depth = max(linear_depth + VERTEX.z, 0.0);

		float t = TIME * flow_speed;
		float is_stream = clamp(v_col.g, 0.0, 1.0);
		float mesh_feather = smoothstep(0.08, 0.44, clamp(v_col.r, 0.0, 1.0));
		float depth_t = smoothstep(0.0, 2.35, water_depth);
		float shallow_t = smoothstep(0.0, 2.05, water_depth);
		float deep_t = smoothstep(1.15, 5.35, water_depth);

		// 1. High-Frequency Perturbed Surface Normals + Micro-Ripples -> Specular Glinting Waves
		float stream_drift = is_stream * t * 0.95;
		vec3 wave_info = sample_cave_waves(v_world_pos.xz, TIME, mesh_feather);
		// Rotated noise capillary slopes using analytic gradient (3x fewer hash evaluations)
		mat2 cap_rot = mat2(vec2(0.866, -0.5), vec2(0.5, 0.866));
		vec2 cap_p = (cap_rot * v_world_pos.xz) * 2.4 + vec2(t * 0.34, -t * 0.27 - stream_drift);
		vec3 ng = value_noise_grad(cap_p);
		float micro_dx = ng.y * 0.24;
		float micro_dz = ng.z * 0.24;

		vec2 wave_grad = vec2(wave_info.y, wave_info.z);
		float wave_glen = length(wave_grad);
		if (wave_glen > 0.14) {
			wave_grad *= (0.14 / wave_glen);
		}
		vec2 total_slope = wave_grad * 0.40 + vec2(micro_dx, micro_dz) * 0.11;
		vec3 world_norm = normalize(vec3(-total_slope.x, 1.0, -total_slope.y));
		vec3 view_up = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
		vec3 view_dir = normalize(VIEW);
		vec3 n_view = normalize(mat3(VIEW_MATRIX) * world_norm);
		float ndv_raw = dot(n_view, view_dir);
		if (ndv_raw < 0.06) {
			n_view = normalize(mix(n_view, view_up, clamp((0.06 - ndv_raw) / 0.14, 0.0, 1.0)));
		}
		NORMAL = n_view;

		float ndv = clamp(dot(NORMAL, view_dir), 0.0, 1.0);
		float fresnel = pow(max(1.0 - ndv, 1e-4), 3.3);
		vec3 cave_key_v = normalize(mat3(VIEW_MATRIX) * normalize(vec3(0.32, 0.88, 0.36)));
		vec3 half_v = normalize(cave_key_v + normalize(VIEW));
		float water_glint = pow(max(dot(NORMAL, half_v), 1e-4), 48.0);
		float ripple_crest = smoothstep(0.004, 0.032, wave_info.x) * mesh_feather;
		float ripple_trough = smoothstep(0.004, 0.036, -wave_info.x) * mesh_feather;

		// 2. Crisp Dual-Octave Voronoi Filament Caustics (zero axis-aligned grid artifacts)
		vec2 caust_uv = v_world_pos.xz * 0.42 + vec2(t * 0.12, -t * 0.09 - stream_drift * 0.5) + total_slope * 0.28;
		float caust = caustic_web(caust_uv, TIME) * (1.0 - smoothstep(0.35, 0.98, depth_t) * 0.65) * mesh_feather;

		// 3. Organic Broken Lace Foam (plunge burst + warped shore lap)
		float lace_lo = value_noise(v_world_pos.xz * 2.5 - vec2(t * 0.40, t * 0.34 + stream_drift));
		float lace_hi = value_noise(v_world_pos.xz * 6.8 + vec2(t * 0.58, -t * 0.48));
		float foam_lace = smoothstep(0.32, 0.76, lace_lo * 0.62 + lace_hi * 0.38);

		float d_wf = length(v_world_pos.xz - waterfall_impact_world.xz);
		float wf_froth = (1.0 - smoothstep(0.6, 4.2, d_wf)) * (0.45 + 0.55 * sin(d_wf * 5.2 - TIME * 5.5)) * (1.0 - is_stream) * mesh_feather * foam_lace;

		float slime_shadow = 0.0;
		float slime_meniscus = 0.0;
		float rad_s = max(slime_radius, 0.45);
		if (slime_submersion > 0.025) {
			vec2 rel_xz = v_world_pos.xz - slime_pos.xz;
			float d_s = length(rel_xz);
			if (d_s < 13.5) {
				slime_shadow = exp(-(d_s * d_s) / max(rad_s * rad_s * 0.72, 0.25)) * smoothstep(0.025, 0.35, slime_submersion) * 0.32;
				float m_n = (d_s - rad_s * 0.98) / 0.065;
				slime_meniscus = exp(-(m_n * m_n)) * smoothstep(0.025, 0.28, slime_submersion) * foam_lace * mesh_feather;
			}
		}

		float depth_warp = max(water_depth + (lace_lo - 0.5) * mix(0.18, 0.05, is_stream), 0.0);
		float shore_lace = smoothstep(0.06, 0.16, depth_warp) * (1.0 - smoothstep(0.18, 0.36, depth_warp)) * foam_lace * 0.24 * smoothstep(0.20, 0.55, v_col.r) * (1.0 - 0.72 * is_stream);
		float total_foam = clamp(shore_lace + wf_froth * 0.55, 0.0, 0.88);

		// 4. Multi-Depth Water Albedo, Clear Downward Bathymetry Sightlines & Crisp Aqua Ripple Rings
		vec3 stream_shallow = vec3(0.05, 0.30, 0.38);
		vec3 lake_mid = mix(shallow_color, deep_color, 0.56);
		vec3 lake_base = mix(shallow_color, lake_mid, shallow_t);
		lake_base = mix(lake_base, deep_color * vec3(0.76, 0.90, 1.15), deep_t * 0.88);
		vec3 stream_base = mix(stream_shallow, shallow_color * 0.65, smoothstep(0.02, 0.14, water_depth));
		vec3 base_water = mix(lake_base, stream_base, is_stream);
		base_water *= (1.0 - slime_shadow) * (1.0 - ripple_trough * 0.16);
		base_water += vec3(0.16, 0.48, 0.56) * (caust * 0.18) + vec3(0.28, 0.78, 0.90) * (ripple_crest * 0.48 + slime_meniscus * 0.18);
		base_water = mix(base_water, vec3(0.32, 0.76, 0.88), fresnel * 0.34 * mesh_feather);
		vec3 water_col = mix(base_water, foam_color, total_foam);

		float edge_fade_dist = mix(0.38, 0.048, is_stream);
		float edge_fade = smoothstep(0.0, edge_fade_dist, water_depth) * mesh_feather;
		float optical_depth = shallow_t * 0.52 + deep_t * 0.48;
		float lake_alpha = mix(0.17, 0.48, optical_depth) + fresnel * 0.16 + ripple_crest * 0.16;
		float stream_alpha = mix(0.24, 0.46, smoothstep(0.02, 0.12, water_depth)) + fresnel * 0.14 + ripple_crest * 0.14;
		float base_alpha = mix(lake_alpha, stream_alpha, is_stream);

		ALBEDO = water_col;
		EMISSION = (
			mix(vec3(0.011, 0.044, 0.064), vec3(0.004, 0.016, 0.034), deep_t) * (1.0 - 0.55 * is_stream) * (1.0 - slime_shadow * 0.7)
			+ shallow_color * (caust * 0.16 + ripple_crest * 0.30 + slime_meniscus * 0.12 + fresnel * 0.17)
			+ vec3(0.56, 0.90, 0.98) * (water_glint * 0.22)
			+ foam_color * (total_foam * 0.16)
		) * mesh_feather;
		float ripple_rough = clamp(wave_glen * 1.4, 0.0, 0.28);
		ROUGHNESS = mix(clamp(0.24 + ripple_rough, 0.24, 0.54), 0.48, clamp(total_foam * 0.8 + wf_froth * 0.3, 0.0, 1.0));
		SPECULAR = mix(0.28, 0.16, total_foam);
		ALPHA = clamp(edge_fade * base_alpha + total_foam * 0.30 * mesh_feather, 0.0, 0.88);
	}
}
