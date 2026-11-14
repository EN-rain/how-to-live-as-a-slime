shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Crossed flame card shader: UV.y = 0.0 at base (coal bed), 1.0 at tip.
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float flame_intensity : hint_range(0.5, 4.0, 0.05) = 1.85;
uniform float awaken_amount : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float torch_seed : hint_range(0.0, 10.0, 0.01) = 0.0;
uniform float soft_fade_dist : hint_range(0.05, 1.0, 0.01) = 0.28;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	float h = clamp(UV.y, 0.0, 1.0);
	float t = TIME + torch_seed * 1.9;
	float sway_amp = pow(h, 1.35) * (0.075 + 0.025 * awaken_amount);
	float sway_x = sin(t * 4.3 - h * 4.8 + VERTEX.z * 3.2) + 0.45 * cos(t * 7.4 - h * 8.1);
	float sway_z = cos(t * 3.9 - h * 4.3 + VERTEX.x * 3.2) + 0.45 * sin(t * 6.7 - h * 7.3);
	VERTEX.x += sway_x * sway_amp;
	VERTEX.z += sway_z * sway_amp;
}

vec3 blackbody_ramp(float heat) {
	vec3 c_deep_red = vec3(0.68, 0.06, 0.01);
	vec3 c_orange = vec3(1.0, 0.36, 0.02);
	vec3 c_yellow = vec3(1.0, 0.78, 0.16);
	vec3 c_white = vec3(1.0, 0.97, 0.80);
	vec3 col = mix(c_deep_red, c_orange, smoothstep(0.04, 0.38, heat));
	col = mix(col, c_yellow, smoothstep(0.38, 0.72, heat));
	col = mix(col, c_white, smoothstep(0.72, 1.0, heat));
	return col;
}

void fragment() {
	float h = clamp(v_uv.y, 0.0, 1.0);
	float x_centered = (v_uv.x - 0.5) * 2.0;

	float t = TIME + torch_seed * 2.3;
	vec2 uv_a = vec2(v_uv.x * 1.45 + torch_seed * 0.17, h * 1.15 - t * 1.24);
	vec2 uv_b = vec2(v_uv.x * 2.65 - torch_seed * 0.29, h * 2.10 - t * 1.98);
	vec4 na = texture(noise_tex, uv_a);
	vec4 nb = texture(noise_tex, uv_b);

	float n_turb = na.r * 0.56 + nb.g * 0.44;
	float n_lick = na.g * 0.44 + nb.b * 0.56;

	// Tapered flame silhouette with dynamic turbulent tongues licking upward
	float width_profile = mix(0.86, 0.22, pow(h, 0.74)) * (0.84 + 0.16 * sin(min(h * 3.1, 1.5708)));
	float warp_x = (na.b - 0.5) * 0.38 * (0.20 + h) + (nb.a - 0.5) * 0.18 * h;
	float warped_rx = abs(x_centered + warp_x) / max(width_profile, 0.08);

	float radial_mask = 1.0 - smoothstep(0.16, 0.96, warped_rx);
	float base_in = smoothstep(0.0, 0.12, h);
	float tip_erode = 1.0 - smoothstep(0.34, 0.98, h + (1.0 - n_lick) * 0.34);
	float flame_mask = radial_mask * base_in * tip_erode;

	float inner_core = (1.0 - smoothstep(0.0, 0.58, abs(x_centered) / max(width_profile * 0.72, 0.08)))
		* smoothstep(0.02, 0.14, h) * (1.0 - smoothstep(0.16, 0.62, h)) * 0.44;

	float heat = clamp(flame_mask * (0.58 + 0.82 * n_turb) * (1.05 - 0.22 * h) + inner_core, 0.0, 1.15);
	heat = smoothstep(0.06, 1.02, heat);

	// Softly fade cards viewed edge-on so crossed quads never form hard lines
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float angle_fade = smoothstep(0.08, 0.42, ndv);

	// Soft particles against solid brazier & cave stone
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	float soft_mask = 1.0;
	if (depth_raw > 0.0001) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float scene_depth = -vp.z / max(vp.w, 1e-5);
		float frag_depth = -VERTEX.z;
		soft_mask = smoothstep(0.0, soft_fade_dist, scene_depth - frag_depth);
	}

	vec3 col = blackbody_ramp(heat);
	float boost = flame_intensity * (1.0 + awaken_amount * 0.30);
	float alpha = clamp(heat * angle_fade * soft_mask, 0.0, 1.0);

	ALBEDO = col * alpha * boost;
	ALPHA = alpha;
}
