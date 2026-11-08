shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

group_uniforms GrassColors;
uniform vec3 grass_sun_color : source_color = vec3(0.45, 0.75, 0.26);
uniform vec3 grass_mid_color : source_color = vec3(0.29, 0.60, 0.20);
uniform vec3 grass_deep_color : source_color = vec3(0.18, 0.44, 0.15);
uniform vec3 tip_color : source_color = vec3(0.56, 0.85, 0.32);
uniform float macro_scale : hint_range(0.01, 0.2, 0.005) = 0.07;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.92;

varying vec3 v_color;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Completely static geometry, all color computed per-vertex (zero fragment math)
	float h = clamp(VERTEX.y / 0.64, 0.0, 1.0);
	vec2 xz = MODEL_MATRIX[3].xz;

	float patch_h = hash21(floor(xz * (macro_scale * 4.0)));
	vec3 root_col = mix(grass_deep_color, grass_mid_color, patch_h);
	root_col = mix(root_col, grass_sun_color, patch_h * 0.45) * mix(0.88, 1.0, h);

	v_color = mix(root_col, tip_color, (h * h) * 0.72);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = v_color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
