shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Rising glowing ember sparks with HDR bloom and soft particle depth fade.
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float hdr_boost : hint_range(1.0, 5.0, 0.1) = 2.6;
uniform float soft_fade_dist : hint_range(0.05, 0.8, 0.01) = 0.18;

varying float v_life;
varying float v_seed;
varying vec4 v_color;

void vertex() {
	v_life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.z;
	v_color = COLOR;

	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]
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

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 q = vec2(p.x * 1.25, p.y * 0.85);
	float d = length(q);

	float kernel = exp(-d * d * 8.0) * (1.0 - smoothstep(0.58, 0.96, d));
	float twinkle = 0.68 + 0.32 * sin(TIME * 15.0 + v_seed * 47.0 + v_life * 11.0);
	float life_env = smoothstep(0.0, 0.08, v_life) * (1.0 - smoothstep(0.52, 1.0, v_life));

	vec3 c_hot = vec3(1.0, 0.94, 0.60);
	vec3 c_mid = vec3(1.0, 0.42, 0.05);
	vec3 c_cool = vec3(0.86, 0.12, 0.01);
	vec3 col = mix(c_hot, c_mid, smoothstep(0.05, 0.45, v_life));
	col = mix(col, c_cool, smoothstep(0.45, 0.95, v_life)) * v_color.rgb;

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	float soft_mask = 1.0;
	if (depth_raw > 0.0001) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float scene_depth = -vp.z / max(vp.w, 1e-5);
		float frag_depth = -VERTEX.z;
		soft_mask = smoothstep(0.0, soft_fade_dist, scene_depth - frag_depth);
	}

	float alpha = clamp(kernel * life_env * twinkle * soft_mask * v_color.a, 0.0, 1.0);
	ALBEDO = col * alpha * hdr_boost;
	ALPHA = alpha;
}
