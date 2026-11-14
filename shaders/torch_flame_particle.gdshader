shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Animated 4x4 (16-frame) flipbook billboard flame sprite shader with soft particle depth fade.
uniform sampler2D flipbook_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float hdr_intensity : hint_range(0.5, 4.0, 0.05) = 1.55;
uniform float soft_fade_dist : hint_range(0.05, 1.0, 0.01) = 0.24;

varying float v_life;
varying float v_anim;
varying vec4 v_color;

void vertex() {
	v_life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_anim = INSTANCE_CUSTOM.z;
	v_color = COLOR;

	float ang = INSTANCE_CUSTOM.x;
	float ca = cos(ang);
	float sa = sin(ang);
	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]
	);
	mat_world = mat_world * mat4(
		vec4(ca, -sa, 0.0, 0.0),
		vec4(sa,  ca, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec2 tile_uv(float frame_idx, vec2 uv_in) {
	float fi = mod(frame_idx, 16.0);
	float col_i = mod(fi, 4.0);
	float row_i = floor(fi * 0.25);
	vec2 safe_uv = clamp(uv_in, vec2(0.03), vec2(0.97));
	return (vec2(col_i, row_i) + safe_uv) * 0.25;
}

vec3 flame_ramp(float heat) {
	vec3 c_red = vec3(0.76, 0.08, 0.01);
	vec3 c_orange = vec3(1.0, 0.38, 0.03);
	vec3 c_yellow = vec3(1.0, 0.80, 0.20);
	vec3 c_white = vec3(1.0, 0.97, 0.84);
	vec3 col = mix(c_red, c_orange, smoothstep(0.05, 0.36, heat));
	col = mix(col, c_yellow, smoothstep(0.36, 0.70, heat));
	col = mix(col, c_white, smoothstep(0.70, 1.0, heat));
	return col;
}

void fragment() {
	float f_prog = fract(v_anim + v_life * 0.95) * 16.0;
	float f0 = floor(f_prog);
	float f1 = mod(f0 + 1.0, 16.0);
	float f_mix = fract(f_prog);

	vec4 s0 = texture(flipbook_tex, tile_uv(f0, UV));
	vec4 s1 = texture(flipbook_tex, tile_uv(f1, UV));
	vec4 sample_f = mix(s0, s1, f_mix);

	float life_env = smoothstep(0.0, 0.15, v_life) * (1.0 - smoothstep(0.42, 1.0, v_life));
	float cool = mix(1.05, 0.38, pow(v_life, 0.85));
	float heat = clamp(sample_f.r * cool, 0.0, 1.0);

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	float soft_mask = 1.0;
	if (depth_raw > 0.0001) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float scene_depth = -vp.z / max(vp.w, 1e-5);
		float frag_depth = -VERTEX.z;
		soft_mask = smoothstep(0.0, soft_fade_dist, scene_depth - frag_depth);
	}

	vec3 col = flame_ramp(heat) * v_color.rgb;
	float alpha = clamp(sample_f.a * life_env * soft_mask * v_color.a, 0.0, 1.0);

	ALBEDO = col * alpha * hdr_intensity;
	ALPHA = alpha;
}
