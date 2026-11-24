shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Lightweight deep-horizon ocean shader: intentionally omits hint_depth_texture
// so Godot's Mobile renderer skips full-screen depth copies when only outer rings are visible.
group_uniforms WaterColors;
uniform vec3 deep_color : source_color = vec3(0.04, 0.24, 0.56);

group_uniforms Waves;
uniform float wave_speed : hint_range(0.1, 4.0) = 0.85;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.28;

varying vec2 v_world_xz;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world_pos.xz;
}

void fragment() {
	float view_dist = max(-VERTEX.z, 0.0);
	float t = TIME * wave_speed;
	float far_slope_fade = 1.0 - smoothstep(480.0, 1100.0, view_dist);
	float s1 = cos(v_world_xz.x * 0.14 + t) * sin(v_world_xz.y * 0.11 + t * 0.9);
	float s2 = sin(v_world_xz.x * 0.23 - t * 1.1) * cos(v_world_xz.y * 0.19 + t * 0.8);
	vec3 far_n = normalize(vec3(-s1 * 0.06 * far_slope_fade, 1.0, -s2 * 0.06 * far_slope_fade));
	vec3 n_view = normalize(mat3(VIEW_MATRIX) * far_n);
	vec3 view_up = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	vec3 view_dir = normalize(VIEW);
	float ndv_f = dot(n_view, view_dir);
	if (ndv_f < 0.06) {
		n_view = normalize(mix(n_view, view_up, clamp((0.06 - ndv_f) / 0.14, 0.0, 1.0)));
	}
	NORMAL = n_view;
	ALBEDO = deep_color;
	ROUGHNESS = max(roughness_val, 0.28);
	SPECULAR = 0.24;
	ALPHA = 1.0;
}
