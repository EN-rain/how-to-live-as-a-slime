shader_type spatial;

// Cel-shaded material used by every prop, mob and piece of scenery.
// Two light bands + a hot top band, plus an inverted-hull outline supplied as `next_pass`.
uniform vec4 base_color : source_color = vec4(0.9, 0.4, 0.5, 1.0);
uniform vec3 rim_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dissolve_edge_color : source_color = vec3(1.0, 1.0, 0.85);

void vertex() {
	// Swell a touch while dissolving so the prop reads as "being absorbed".
	if (dissolve > 0.0) {
		VERTEX += NORMAL * dissolve * 0.22;
	}
}

void fragment() {
	// Cheap deterministic noise from the mesh UVs; no texture needed.
	if (dissolve > 0.0) {
		vec2 cell = floor(UV * 26.0);
		float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		if (n < dissolve) {
			discard;
		}
		if (n < dissolve + 0.06) {
			EMISSION = dissolve_edge_color * 1.4;
		}
	}
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.78;
	METALLIC = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.05, 0.18, ndl);
	float hot = smoothstep(0.62, 0.85, ndl);
	// Keep the shadow band at 55% so the sky ambient still reads in shade.
	float band = mix(0.55, 1.0, lit) + hot * 0.18;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band / PI;

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION;
}
