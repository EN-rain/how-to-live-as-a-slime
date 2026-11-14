shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

global uniform float u_wind_strength;

group_uniforms WaterColors;
uniform vec3 shallow_color : source_color = vec3(0.14, 0.72, 0.80);
uniform vec3 deep_color : source_color = vec3(0.04, 0.24, 0.56);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.78;
uniform float depth_distance : hint_range(0.5, 15.0) = 6.5;
uniform float foam_depth : hint_range(0.05, 2.0) = 0.65;

group_uniforms Waves;
uniform float wave_speed : hint_range(0.1, 4.0) = 0.85;
uniform float wave_amplitude : hint_range(0.0, 0.5) = 0.12;
uniform float wave_frequency : hint_range(0.05, 2.0) = 0.12;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.28;

group_uniforms SlimeInteraction;
uniform vec3 slime_pos = vec3(9999.0, -9999.0, 9999.0);
uniform vec3 slime_vel = vec3(0.0);
uniform float slime_radius = 1.6;
uniform float slime_submersion = 0.0;
uniform int active_wake_count = 0;
uniform vec4 wake_points[12]; // .xz = world position, .y = age (<0 unused), .w = initial energy

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec2 v_uv;
varying vec2 v_world_xz;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	vec2 p1 = p * 1.45 + vec2(t_val * 0.12, -t_val * 0.09);
	vec2 p2 = (rot37 * p) * 1.85 + vec2(-t_val * 0.10 + 7.3, t_val * 0.13 - 4.1);
	float n1 = 1.0 - abs(value_noise(p1) * 2.0 - 1.0);
	float n2 = 1.0 - abs(value_noise(p2) * 2.0 - 1.0);
	float ridge = n1 * n1 * (0.45 + 0.55 * n2);
	return pow(clamp(max(n1 * n2, ridge * 0.92), 1e-4, 1.0), 2.4);
}

vec3 sample_ocean_interaction_waves(vec2 world_xz, float time_val, out bool any_active) {
	any_active = false;
	float h = 0.0;
	vec2 grad = vec2(0.0);
	float rad_s = max(slime_radius, 0.45);
	float sub_mask = smoothstep(0.025, 0.25, slime_submersion);

	if (sub_mask > 0.001) {
		vec2 rel = world_xz - slime_pos.xz;
		float d_s = length(rel);
		if (d_s < 14.0) {
			any_active = true;
			vec2 r_dir = d_s > 1e-4 ? rel / d_s : vec2(1.0, 0.0);
			float sig_dimple = max(rad_s * 0.94, 0.45);
			float d_dimp = d_s / sig_dimple;
			float dimple = -0.065 * slime_submersion * exp(-(d_dimp * d_dimp));
			float sig_lip = max(rad_s * 0.46, 0.36);
			float r_diff = d_s - rad_s * 1.04;
			float r_norm = r_diff / sig_lip;
			float lip = 0.022 * slime_submersion * exp(-(r_norm * r_norm));
			h += dimple + lip;
			grad += r_dir * ((-2.0 * d_s / (sig_dimple * sig_dimple)) * dimple + (-2.0 * r_diff / (sig_lip * sig_lip)) * lip);

			float rip_env = (1.0 - smoothstep(rad_s * 0.72, rad_s + 7.5, d_s)) * exp(-max(d_s - rad_s * 0.65, 0.0) * 0.36) * sub_mask;
			float k_rip = 3.8;
			float ph_rip = d_s * k_rip - time_val * 5.2;
			h += sin(ph_rip) * 0.013 * rip_env;
			grad += r_dir * (cos(ph_rip) * k_rip * 0.013 * rip_env);
		}
	}

	if (active_wake_count > 0) {
		for (int i = 0; i < 12; i++) {
			vec4 wp = wake_points[i];
			float age = wp.y;
			if (age >= 0.0 && age < 2.6 && wp.w > 0.01) {
				vec2 rel_w = world_xz - wp.xz;
				float dw = length(rel_w);
				if (dw < 11.5 && dw > 0.04) {
					any_active = true;
					float r_cur = rad_s * 0.48 + age * 2.1;
					float band_w = 0.44 + age * 0.34;
					float dist_w = dw - r_cur;
					float dw_n = dist_w / band_w;
					float w_env = exp(-(dw_n * dw_n)) * exp(-age * 1.20) * wp.w;
					if (w_env > 0.004) {
						float k_w = 4.2;
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
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = world_pos.xz;
	v_world_xz = world_pos.xz;

	if (dot(world_pos.xz, world_pos.xz) < 16000000.0) {
		float t = TIME * wave_speed;
		float w1 = sin(world_pos.x * wave_frequency + t) * cos(world_pos.z * (wave_frequency * 0.8) + t * 0.9);
		float disp = w1 * wave_amplitude * (1.0 + u_wind_strength * 0.65);
		float cam_d = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
		if (cam_d < 340.0) {
			if (slime_submersion >= 0.025 || active_wake_count > 0) {
				bool active_w = false;
				vec3 inter_w = sample_ocean_interaction_waves(world_pos.xz, TIME, active_w);
				disp += inter_w.x;
			}
			float vert_fade = 1.0 - smoothstep(140.0, 340.0, cam_d);
			VERTEX.y += disp * vert_fade;
		}
	}
}

void fragment() {
	float view_dist = max(-VERTEX.z, 0.0);
	float t = TIME * wave_speed;
	float far_k = smoothstep(260.0, 520.0, view_dist);
	vec3 view_up = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	vec3 view_dir = normalize(VIEW);
	if (far_k >= 0.999) {
		float far_slope_fade = 1.0 - smoothstep(480.0, 1100.0, view_dist);
		float s1 = cos(v_world_xz.x * 0.14 + t) * sin(v_world_xz.y * 0.11 + t * 0.9);
		float s2 = sin(v_world_xz.x * 0.23 - t * 1.1) * cos(v_world_xz.y * 0.19 + t * 0.8);
		vec3 far_n = normalize(vec3(-s1 * 0.06 * far_slope_fade, 1.0, -s2 * 0.06 * far_slope_fade));
		vec3 n_view = normalize(mat3(VIEW_MATRIX) * far_n);
		float ndv_f = dot(n_view, view_dir);
		if (ndv_f < 0.06) {
			n_view = normalize(mix(n_view, view_up, clamp((0.06 - ndv_f) / 0.14, 0.0, 1.0)));
		}
		NORMAL = n_view;
		ALBEDO = deep_color;
		ROUGHNESS = max(roughness_val, 0.28);
		SPECULAR = 0.24;
		ALPHA = 1.0;
	} else {
		float water_depth = depth_distance + 4.0;
		float depth_raw = texture(depth_texture, SCREEN_UV).r;
		if (depth_raw > 0.0001) {
			vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
			vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
			if (abs(view_pos.w) > 1e-4) {
				view_pos.xyz /= view_pos.w;
				float linear_depth = -view_pos.z;
				water_depth = max(linear_depth + VERTEX.z, 0.0);
			}
		}

		bool near_interaction = false;
		vec3 inter_w = vec3(0.0);
		if (view_dist < 260.0 && (slime_submersion >= 0.025 || active_wake_count > 0)) {
			inter_w = sample_ocean_interaction_waves(v_world_xz, TIME, near_interaction);
		}

		float depth_ratio = clamp(water_depth / depth_distance, 0.0, 1.0);

		// Wider shoreline feather smoothly dissolves ultra-shallow coarse terrain triangle edges into wet glossy sand
		float shore_feather = smoothstep(0.0, 0.56, water_depth);

		// Multi-octave wave slope normals for smooth swells + wakes (analytic noise gradient saves 2x lookups)
		float c_sp1 = sin(v_world_xz.x * 0.42 + t * 1.35 + v_world_xz.y * 0.25);
		float c_sp2 = cos(v_world_xz.y * 0.58 - t * 1.15 + v_world_xz.x * 0.31);
		mat2 cap_rot = mat2(vec2(0.866, -0.5), vec2(0.5, 0.866));
		vec2 cap_p = (cap_rot * v_world_xz) * 1.28 + vec2(t * 0.30, -t * 0.23);
		vec3 ng = value_noise_grad(cap_p);
		vec2 micro_slope = vec2(ng.y, ng.z) * 0.062;
		vec2 swell_slope = vec2(c_sp1 * 0.045, c_sp2 * 0.045);
		vec2 inter_grad = vec2(inter_w.y, inter_w.z);
		float inter_glen = length(inter_grad);
		if (inter_glen > 0.14) {
			inter_grad *= (0.14 / inter_glen);
		}
		vec2 near_slope = swell_slope + micro_slope + inter_grad * 0.36;

		float s1 = cos(v_world_xz.x * 0.14 + t) * sin(v_world_xz.y * 0.11 + t * 0.9);
		float s2 = sin(v_world_xz.x * 0.23 - t * 1.1) * cos(v_world_xz.y * 0.19 + t * 0.8);
		vec2 tot_slope = mix(near_slope, vec2(s1 * 0.06, s2 * 0.06), far_k);
		vec3 world_norm = normalize(vec3(-tot_slope.x, 1.0, -tot_slope.y));
		vec3 n_view = normalize(mat3(VIEW_MATRIX) * world_norm);
		float ndv_raw = dot(n_view, view_dir);
		if (ndv_raw < 0.06) {
			n_view = normalize(mix(n_view, view_up, clamp((0.06 - ndv_raw) / 0.14, 0.0, 1.0)));
		}
		NORMAL = n_view;

		float ndv = clamp(dot(NORMAL, view_dir), 0.0, 1.0);
		float fresnel = pow(max(1.0 - ndv, 1e-4), 3.4);
		float ripple_crest = smoothstep(0.004, 0.032, inter_w.x) * (1.0 - far_k);
		float ripple_trough = smoothstep(0.004, 0.036, -inter_w.x) * (1.0 - far_k);

		// Underwater caustic light filaments across shallow sandy seabeds (fades cleanly to 0 before depth_ratio=0.85)
		float caust_mask = (1.0 - smoothstep(0.10, 0.84, depth_ratio)) * shore_feather * (1.0 - far_k);
		float caust = 0.0;
		if (caust_mask > 0.002) {
			caust = caustic_web(v_world_xz * 0.32 + vec2(t * 0.12, -t * 0.09) + tot_slope * 0.24, TIME);
		}

		vec3 water_col = mix(shallow_color, deep_color, pow(max(depth_ratio, 1e-4), 0.78));
		water_col *= (1.0 - ripple_trough * 0.16);
		water_col += vec3(0.22, 0.58, 0.64) * (caust * 0.24 * caust_mask) + vec3(0.32, 0.72, 0.86) * (ripple_crest * 0.42);
		water_col = mix(water_col, vec3(0.46, 0.82, 0.96), fresnel * 0.28 * (1.0 - far_k));

		// Organic noise-warped seafoam lace & animated tidal swash lines (pushed softly offshore so triangles never show)
		float lace_lo = value_noise(v_world_xz * 1.45 + vec2(t * 0.22, -t * 0.16));
		float lace_hi = value_noise(v_world_xz * 3.90 - vec2(t * 0.34, t * 0.27));
		float foam_lace = smoothstep(0.32, 0.76, lace_lo * 0.62 + lace_hi * 0.38);

		float shore_swash = 0.0;
		if (water_depth < foam_depth + 1.15 && far_k < 0.95) {
			float d_warp = max(water_depth + (lace_lo - 0.5) * 0.36, 0.0);
			float tide_wave = 0.5 + 0.5 * sin(d_warp * 7.8 - TIME * 2.1);
			float edge_lap = smoothstep(0.12, 0.34, d_warp) * (1.0 - smoothstep(0.38, 0.82, d_warp));
			float outer_surf = smoothstep(0.56, 0.92, tide_wave) * (1.0 - smoothstep(0.45, 1.55, d_warp));
			shore_swash = clamp((edge_lap * 0.68 + outer_surf * 0.66) * foam_lace, 0.0, 0.84) * (1.0 - far_k);
		}

		// Real-time Slime-Ocean Interaction (subtle ambient shadow + tiny waterline contact tint; zero white blobs)
		float slime_foam = 0.0;
		float slime_shadow = 0.0;
		float rad_s = max(slime_radius, 0.45);
		if (slime_submersion > 0.025 && far_k < 0.95) {
			vec2 rel_xz = v_world_xz - slime_pos.xz;
			float d_s = length(rel_xz);
			if (d_s < 14.0) {
				slime_shadow = exp(-(d_s * d_s) / max(rad_s * rad_s * 0.72, 0.25)) * smoothstep(0.025, 0.35, slime_submersion) * 0.24;
				float m_n = (d_s - rad_s * 0.98) / 0.065;
				float meniscus = exp(-(m_n * m_n)) * smoothstep(0.025, 0.28, slime_submersion);
				water_col += vec3(0.28, 0.68, 0.82) * (meniscus * foam_lace * 0.16);
			}
		}

		water_col *= (1.0 - slime_shadow);
		float total_foam = clamp(shore_swash + slime_foam, 0.0, 0.88) * (1.0 - far_k);
		vec3 final_col = mix(water_col, foam_color, total_foam);
		float base_alpha = mix(water_opacity, 1.0, smoothstep(0.04, 0.94, depth_ratio));
		float ripple_rough = clamp(inter_glen * 1.8, 0.0, 0.30) * (1.0 - far_k);

		ALBEDO = mix(final_col, deep_color, far_k);
		ROUGHNESS = mix(clamp(max(roughness_val, 0.28) + ripple_rough, 0.28, 0.62), 0.56, total_foam);
		SPECULAR = mix(0.24, 0.14, total_foam);
		ALPHA = clamp(mix(shore_feather * mix(base_alpha, 0.96, total_foam * 0.65), 1.0, far_k), 0.0, 1.0);
	}
}
