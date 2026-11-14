shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Subtle upward-scrolling refractive heat-haze billboard above brazier flame.
// Smoothly masked to zero well inside quad borders so zero rectangular artifact occurs.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float distortion_strength : hint_range(0.0, 0.03, 0.0005) = 0.0085;
uniform float awaken_amount : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float torch_seed : hint_range(0.0, 10.0, 0.01) = 0.0;
uniform float soft_fade_dist : hint_range(0.05, 1.0, 0.01) = 0.25;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float sz = length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sx, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sy, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sz, 0.0),
		MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	// QuadMesh UV.y = 0 at top, 1 at bottom
	float up_y = 1.0 - UV.y;
	float taper = mix(0.95, 0.68, up_y);
	float oval_r = length(vec2(centered.x / taper, centered.y));

	float mask = (1.0 - smoothstep(0.18, 0.86, oval_r))
		* smoothstep(0.0, 0.16, up_y)
		* (1.0 - smoothstep(0.74, 1.0, up_y));

	float screen_edge = smoothstep(0.0, 0.05, SCREEN_UV.x) * smoothstep(1.0, 0.95, SCREEN_UV.x)
		* smoothstep(0.0, 0.05, SCREEN_UV.y) * smoothstep(1.0, 0.95, SCREEN_UV.y);
	mask *= screen_edge;

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	float soft_mask = 1.0;
	if (depth_raw > 0.0001) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float scene_depth = -vp.z / max(vp.w, 1e-5);
		float frag_depth = -VERTEX.z;
		soft_mask = smoothstep(0.0, soft_fade_dist, scene_depth - frag_depth);
	}
	mask *= soft_mask;

	float t = TIME + torch_seed * 1.7;
	vec4 n1 = texture(noise_tex, vec2(UV.x * 1.8, up_y * 1.4 - t * 1.35));
	vec4 n2 = texture(noise_tex, vec2(UV.x * 3.1 + 0.37, up_y * 2.3 - t * 2.05));
	vec2 flow = vec2((n1.r - n2.g) * 0.95, ((n1.b - 0.5) * 1.15 + (n2.a - 0.5) * 0.85));

	float dist_atten = clamp(6.0 / max(-VERTEX.z, 1.0), 0.25, 1.0);
	vec2 offset = flow * distortion_strength * (1.0 + awaken_amount * 0.35) * mask * dist_atten;
	vec2 warped_uv = clamp(SCREEN_UV + offset, vec2(0.002), vec2(0.998));

	ALBEDO = texture(screen_tex, warped_uv).rgb;
	ALPHA = clamp(mask * 0.92, 0.0, 1.0);
}
