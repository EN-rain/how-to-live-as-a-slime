shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec3 beam_color : source_color = vec3(1.0, 0.92, 0.68);
uniform float beam_intensity : hint_range(0.01, 1.0, 0.01) = 0.22;

varying float v_v;

void vertex() {
	v_v = UV.y;
}

void fragment() {
	// UV.y = 0 at top skylight aperture, 1 at cavern floor
	float vertical_fade = smoothstep(0.0, 0.14, v_v) * (1.0 - smoothstep(0.62, 1.0, v_v));
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge_soft = pow(clamp(ndv, 0.0, 1.0), 1.85);
	float dust_shimmer = 0.92 + 0.08 * sin(TIME * 0.8 + v_v * 6.0);
	float alpha = beam_intensity * vertical_fade * edge_soft * dust_shimmer;
	ALBEDO = beam_color * alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
}

