shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform vec3 fog_color : source_color = vec3(0.90, 0.94, 0.99);
uniform vec3 shadow_tint : source_color = vec3(0.72, 0.82, 0.94);
uniform float fog_opacity : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float drift_speed : hint_range(0.0, 1.0, 0.01) = 0.045;
uniform float near_fade_dist : hint_range(1.0, 60.0, 1.0) = 18.0;
uniform float far_fade_dist : hint_range(200.0, 4000.0, 50.0) = 2400.0;

varying float v_cam_dist;
varying float v_band_phase;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Gentle breathing drift on summit mist layers
	float w = sin(TIME * 0.35 + world_pos.x * 0.018 + world_pos.z * 0.015);
	VERTEX.y += w * 1.6;
	v_cam_dist = length(CAMERA_POSITION_WORLD - world_pos);
	v_band_phase = fract((world_pos.x + world_pos.z) * 0.0037);
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float r = length(centered);
	if (r >= 1.0) {
		discard;
	}

	// Smooth wispy horizontal cloud envelope (pure analytical trig, zero fragment noise)
	vec2 uvd = UV + vec2(TIME * drift_speed + v_band_phase, TIME * drift_speed * 0.35);
	float wisp1 = 0.5 + 0.5 * sin(uvd.x * 6.28318 + sin(uvd.y * 6.28318) * 1.4);
	float wisp2 = 0.5 + 0.5 * cos(uvd.y * 9.42477 - uvd.x * 3.14159);
	float density = smoothstep(1.0, 0.12, r);
	density *= mix(0.55, 1.15, wisp1 * 0.6 + wisp2 * 0.4);

	// Soft camera near/far fade so walking through summit clouds has zero hard clipping
	float near_fade = smoothstep(2.0, near_fade_dist, v_cam_dist);
	float far_fade = 1.0 - smoothstep(far_fade_dist * 0.65, far_fade_dist, v_cam_dist);

	ALBEDO = mix(shadow_tint, fog_color, smoothstep(-0.7, 0.7, centered.y));
	ALPHA = clamp(density * fog_opacity * near_fade * far_fade, 0.0, 0.85);
}
