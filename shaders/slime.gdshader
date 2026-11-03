shader_type spatial;

// Wobbling cel-shaded jelly shader for the player slime.
// Uses an icosphere mesh so the multi-axis vertex wave deforms evenly without pole pinching.
// The body is translucent so the ground and the slime's own eyes read through the jelly.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.45, 0.92, 0.7, 1.0);
// Overall body opacity. The rim is made more opaque in fragment() so the
// silhouette stays readable while the middle lets the world through.
uniform float alpha : hint_range(0.15, 1.0, 0.01) = 0.62;
uniform float wobble_amplitude : hint_range(0.0, 0.2, 0.005) = 0.04;
uniform float wobble_speed : hint_range(0.5, 12.0, 0.1) = 4.2;
uniform float flash : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.95, 1.0, 0.96);
uniform float rim_strength : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform vec3 flash_color : source_color = vec3(1.0, 0.35, 0.4);

void vertex() {
	float t = TIME * wobble_speed;
	float wave = sin(VERTEX.x * 6.0 + t) * cos(VERTEX.y * 5.0 - t * 0.8) * sin(VERTEX.z * 6.0 + t * 1.1);
	float ripple = sin((VERTEX.x + VERTEX.z) * 4.5 + t * 1.3) * 0.5;
	VERTEX += NORMAL * (wave + ripple) * wobble_amplitude;
}

void fragment() {
	float f = clamp(flash, 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, flash_color, f);
	ROUGHNESS = 0.35;
	METALLIC = 0.0;

	// Facing ratio: 1 in the middle of the blob, 0 at the silhouette.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = pow(1.0 - facing, 2.0);
	ALPHA = clamp(alpha + edge * 0.2 + f * 0.2, 0.0, 1.0);

	// A little self-glow keeps the jelly readable against the ground.
	EMISSION = base_color.rgb * 0.06 + flash_color * (f * 0.65);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.08, 0.16, ndl);
	float hot = smoothstep(0.68, 0.88, ndl);
	float band = mix(0.6, 1.0, lit) + hot * 0.25;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band / PI;

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION;
}
