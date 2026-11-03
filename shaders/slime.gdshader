shader_type spatial;

// The slime body: rolling vertex wobble + cel bands + a jelly highlight.
// Squash & stretch is driven from GDScript on the MeshInstance3D transform.
uniform vec4 base_color : source_color = vec4(0.55, 0.9, 0.65, 1.0);
uniform float wobble_amplitude : hint_range(0.0, 0.4) = 0.045;
uniform float wobble_speed = 6.0;
uniform float wobble_frequency = 8.0;
uniform vec3 rim_color : source_color = vec3(0.85, 1.0, 0.9);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	// Phase varies across the surface so the blob breathes instead of pulsing.
	float phase = TIME * wobble_speed + VERTEX.y * wobble_frequency + VERTEX.x * 3.0;
	VERTEX += NORMAL * sin(phase) * wobble_amplitude;
}

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.28;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	// Faint inner glow so the jelly reads even in shade.
	EMISSION = base_color.rgb * 0.08 + vec3(1.0, 0.25, 0.2) * flash;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.05, 0.2, ndl);
	float hot = smoothstep(0.6, 0.85, ndl);
	float band = mix(0.5, 1.0, lit) + hot * 0.22;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band / PI;

	// Glossy blob highlight.
	float spec = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 42.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec * 0.5;

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION;
}
