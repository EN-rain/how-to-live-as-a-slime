shader_type spatial;
render_mode skip_vertex_transform, blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

global uniform float u_wind_strength;
global uniform float u_weather_wetness;

uniform sampler2DArray leaf_textures : source_color, filter_linear_mipmap;
uniform sampler2DArray bark_textures : source_color, filter_linear_mipmap;
uniform vec3 leaf_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 bark_tint : source_color = vec3(0.85, 0.78, 0.72);
uniform float alpha_scissor : hint_range(0.1, 0.9) = 0.36;
uniform float wind_amp : hint_range(0.0, 0.4) = 0.06;
uniform vec2 u_webwood_center = vec2(-410.0, 480.0);

varying vec2 v_uv;
varying float v_webwood_w;
varying vec3 v_right_view;
varying vec3 v_up_view;
varying vec3 v_fwd_view;
varying float v_seed;
varying float v_arch;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 tree_origin = MODEL_MATRIX[3].xyz;
	float sx = max(length(MODEL_MATRIX[0].xyz), 0.01);
	float sy = max(length(MODEL_MATRIX[1].xyz), 0.01);
	vec3 up_w = normalize(MODEL_MATRIX[1].xyz);

	// INSTANCE_CUSTOM encodes (archetype_idx, half_w, min_y, max_y) for merged multi-species batches
	v_arch = INSTANCE_CUSTOM.x;
	float half_w = max(INSTANCE_CUSTOM.y, 1.0);
	float min_y = INSTANCE_CUSTOM.z;
	float max_y = max(INSTANCE_CUSTOM.w, min_y + 1.0);
	float quad_x = VERTEX.x * half_w;
	float quad_y = mix(min_y, max_y, VERTEX.y);

	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam_pos - tree_origin;
	to_cam -= up_w * dot(to_cam, up_w);
	float len_sq = dot(to_cam, to_cam);
	vec3 fwd_w = (len_sq > 1e-6) ? (to_cam * inversesqrt(len_sq)) : vec3(0.0, 0.0, 1.0);
	vec3 right_w = normalize(cross(up_w, fwd_w));

	// Gentle distant wind sway anchored at the roots (UV.y = 1 at bottom, 0 at top)
	float h_mask = clamp(1.0 - UV.y, 0.0, 1.0);
	h_mask *= h_mask;
	float phase = TIME * (1.5 + u_wind_strength * 2.2) + tree_origin.x * 0.23 + tree_origin.z * 0.19;
	float sway = sin(phase) * wind_amp * (0.65 + u_wind_strength * 2.0) * h_mask * sy;

	vec3 world_pos = tree_origin + right_w * (quad_x * sx + sway) + up_w * (quad_y * sy);
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;

	mat3 vrot = mat3(VIEW_MATRIX);
	v_right_view = normalize(vrot * right_w);
	v_up_view = normalize(vrot * up_w);
	v_fwd_view = normalize(vrot * fwd_w);
	NORMAL = v_fwd_view;

	v_uv = UV;
	v_seed = hash12(tree_origin.xz);
	v_webwood_w = 1.0 - smoothstep(95.0, 180.0, length(tree_origin.xz - u_webwood_center));
}

float sd_ellipse(vec2 p, vec2 r) {
	return length(p / max(r, vec2(0.001))) - 1.0;
}

void fragment() {
	int arch = clamp(int(round(v_arch)), 0, 8);
	// Archetype -> style: 0,1=Common(0); 2,3=Pine(1); 4,5=Birch(2); 6,7=Maple(3); 8=Dead(4)
	int tree_style = arch / 2;
	float bark_layer = float(arch);
	float leaf_layer = float(min(arch, 7));

	float x = v_uv.x - 0.5;          // -0.5 .. +0.5
	float y_up = 1.0 - v_uv.y;       // 0 at base, 1 at top

	// Subtle per-tree horizontal flip & jitter so forest silhouettes feel organic
	float flip_x = (v_seed > 0.5) ? -x : x;
	float trunk_curve = sin(y_up * 3.8 + v_seed * 6.2831) * 0.028 * smoothstep(0.05, 0.7, y_up);

	// Trunk silhouette
	float trunk_half_w = mix(0.068, 0.022, smoothstep(0.0, 0.65, y_up));
	float trunk_top = (tree_style == 4) ? 0.88 : ((tree_style == 1) ? 0.68 : 0.60);
	float trunk_mask = step(y_up, trunk_top) * (1.0 - smoothstep(trunk_half_w - 0.012, trunk_half_w + 0.008, abs(flip_x - trunk_curve)));

	// Style-specific canopy signed distance (d <= 0 inside crown)
	float crown_d = 1.0;
	vec2 crown_center = vec2(0.0, 0.64);
	vec2 crown_rad = vec2(0.38, 0.32);

	if (tree_style == 0) {
		// Common broadleaf: layered lush rounded lobes
		crown_center = vec2(0.0, 0.64);
		crown_rad = vec2(0.40, 0.34);
		float d0 = sd_ellipse(vec2(flip_x, y_up) - vec2(0.0, 0.68), vec2(0.36, 0.28));
		float d1 = sd_ellipse(vec2(flip_x, y_up) - vec2(-0.18, 0.54), vec2(0.24, 0.20));
		float d2 = sd_ellipse(vec2(flip_x, y_up) - vec2(0.18, 0.56), vec2(0.23, 0.20));
		crown_d = min(d0, min(d1, d2));
	} else if (tree_style == 1) {
		// Pine: 3-tier conical boughs
		crown_center = vec2(0.0, 0.56);
		crown_rad = vec2(0.42, 0.42);
		float d_cone = 1.0;
		for (int tier = 0; tier < 3; tier++) {
			float ft = float(tier);
			float y0 = 0.20 + ft * 0.22;
			float y1 = 0.58 + ft * 0.21;
			float ty = clamp((y_up - y0) / max(y1 - y0, 0.01), 0.0, 1.0);
			float hw = (0.44 - ft * 0.085) * (1.0 - pow(ty, 0.85));
			if (y_up >= y0 && y_up <= y1) {
				d_cone = min(d_cone, abs(flip_x) - hw);
			}
		}
		crown_d = d_cone * 2.5;
	} else if (tree_style == 2) {
		// Birch: tall airy oval crown
		crown_center = vec2(0.0, 0.66);
		crown_rad = vec2(0.30, 0.34);
		float d0 = sd_ellipse(vec2(flip_x, y_up) - vec2(0.0, 0.72), vec2(0.25, 0.25));
		float d1 = sd_ellipse(vec2(flip_x, y_up) - vec2(-0.11, 0.54), vec2(0.18, 0.20));
		float d2 = sd_ellipse(vec2(flip_x, y_up) - vec2(0.12, 0.58), vec2(0.17, 0.19));
		crown_d = min(d0, min(d1, d2));
	} else if (tree_style == 3) {
		// Maple: wide spreading crown
		crown_center = vec2(0.0, 0.62);
		crown_rad = vec2(0.44, 0.34);
		float d0 = sd_ellipse(vec2(flip_x, y_up) - vec2(0.0, 0.66), vec2(0.40, 0.29));
		float d1 = sd_ellipse(vec2(flip_x, y_up) - vec2(-0.22, 0.56), vec2(0.24, 0.22));
		float d2 = sd_ellipse(vec2(flip_x, y_up) - vec2(0.22, 0.58), vec2(0.23, 0.22));
		crown_d = min(d0, min(d1, d2));
	} else {
		// Dead tree: gnarled forked limbs, zero leaves
		float arm_l = (1.0 - smoothstep(0.015, 0.032, abs((flip_x + 0.18 * smoothstep(0.42, 0.84, y_up)) - trunk_curve))) * step(0.42, y_up) * step(y_up, 0.84);
		float arm_r = (1.0 - smoothstep(0.014, 0.030, abs((flip_x - 0.19 * smoothstep(0.50, 0.90, y_up)) - trunk_curve))) * step(0.50, y_up) * step(y_up, 0.90);
		trunk_mask = max(trunk_mask, max(arm_l, arm_r));
		crown_d = 1.0;
	}

	vec2 leaf_uv = fract(v_uv * vec2(2.2, 2.2) + vec2(v_seed * 0.73, v_seed * 0.37));
	vec4 leaf_tex = texture(leaf_textures, vec3(leaf_uv, leaf_layer));
	vec4 bark_tex = texture(bark_textures, vec3(v_uv.x * 4.0 + v_seed, v_uv.y * 2.5, bark_layer));

	float crown_shape = 1.0 - smoothstep(-0.35, 0.06, crown_d);
	float leaf_alpha = (tree_style == 4) ? 0.0 : clamp(crown_shape * mix(0.35, 1.35, leaf_tex.a), 0.0, 1.0);

	float alpha = max(trunk_mask, leaf_alpha);
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;

	// Approximate spherical canopy normal in view space for soft Ghibli shading
	vec2 rel = (vec2(x, y_up) - crown_center) / max(crown_rad, vec2(0.01));
	float r2 = clamp(dot(rel, rel), 0.0, 0.92);
	float z_n = sqrt(max(1.0 - r2, 0.08));
	vec3 sph_n = normalize(v_right_view * rel.x + v_up_view * (rel.y * 0.7 + 0.32) + v_fwd_view * z_n);
	NORMAL = normalize(mix(sph_n, v_up_view, 0.38));

	// Albedo blend between bark (trunk) and sunlit foliage + inner crown AO
	float leaf_weight = clamp((leaf_alpha - trunk_mask * 0.65) * 1.4, 0.0, 1.0);
	float crown_ao = mix(0.62, 1.06, clamp((y_up - 0.25) * 1.35, 0.0, 1.0));
	vec3 bark_col = bark_tex.rgb * bark_tint * mix(0.75, 1.0, y_up);
	vec3 foliage_col = leaf_tex.rgb * leaf_tint * crown_ao;
	vec3 base_col = mix(bark_col, foliage_col, leaf_weight);

	vec3 canopy_col = base_col * vec3(0.28, 0.40, 0.44);
	ALBEDO = mix(base_col, canopy_col, v_webwood_w * 0.92) * mix(1.0, 0.88, u_weather_wetness);
	ROUGHNESS = mix(0.88, 0.55, u_weather_wetness);
	METALLIC = 0.0;
}
