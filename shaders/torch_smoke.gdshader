shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Soft billowing soot/smoke billboard particles with warm ember under-glow and depth fade.
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 smoke_color : source_color = vec3(0.085, 0.075, 0.072);
uniform vec3 ember_bounce_color : source_color = vec3(0.54, 0.21, 0.06);
uniform float smoke_opacity : hint_range(0.05, 0.8, 0.01) = 0.32;
uniform float soft_fade_dist : hint_range(0.1, 1.5, 0.02) = 0.45;

varying float v_life;
varying float v_seed;
varying vec4 v_color;

void vertex() {
	v_life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.z;
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

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);

	vec2 nuv_a = UV * 0.78 + vec2(v_seed * 0.37, -v_life * 0.32 + v_seed * 0.19);
	vec2 nuv_b = UV * 1.45 + vec2(-v_seed * 0.23, -v_life * 0.54 + 0.41);
	float na = texture(noise_tex, nuv_a).r;
	float nb = texture(noise_tex, nuv_b).g;
	float wisp = na * 0.62 + nb * 0.38;

	float puff = 1.0 - smoothstep(0.12, 0.94, r + (0.5 - wisp) * 0.48);
	float life_env = smoothstep(0.0, 0.20, v_life) * pow(1.0 - smoothstep(0.28, 1.0, v_life), 1.35);

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	float soft_mask = 1.0;
	if (depth_raw > 0.0001) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float scene_depth = -vp.z / max(vp.w, 1e-5);
		float frag_depth = -VERTEX.z;
		soft_mask = smoothstep(0.0, soft_fade_dist, scene_depth - frag_depth);
	}

	float warm_lit = (1.0 - smoothstep(0.0, 0.42, v_life)) * smoothstep(0.15, 0.85, 1.0 - UV.y);
	vec3 col = mix(smoke_color, ember_bounce_color, warm_lit * 0.52 * (0.5 + 0.5 * wisp)) * v_color.rgb;
	float alpha = clamp(puff * life_env * smoke_opacity * soft_mask * v_color.a, 0.0, 0.72);

	ALBEDO = col;
	ALPHA = alpha;
}
