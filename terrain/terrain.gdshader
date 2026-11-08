shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

group_uniforms MeadowGrass;
uniform vec3 grass_sun_color : source_color = vec3(0.45, 0.75, 0.26);
uniform vec3 grass_mid_color : source_color = vec3(0.29, 0.60, 0.20);
uniform vec3 grass_deep_color : source_color = vec3(0.18, 0.44, 0.15);

group_uniforms SoilAndRock;
uniform vec3 dirt_light_color : source_color = vec3(0.58, 0.44, 0.30);
uniform vec3 dirt_dark_color : source_color = vec3(0.39, 0.28, 0.18);
uniform vec3 rock_light_color : source_color = vec3(0.52, 0.50, 0.47);
uniform vec3 rock_dark_color : source_color = vec3(0.34, 0.32, 0.30);

group_uniforms SurfaceTuning;
uniform float detail_scale : hint_range(0.5, 10.0, 0.1) = 2.4;
uniform float micro_scale : hint_range(5.0, 40.0, 0.5) = 18.0;
uniform float macro_scale : hint_range(0.01, 0.3, 0.005) = 0.07;
uniform float slope_threshold : hint_range(0.5, 0.98, 0.01) = 0.85;
uniform float slope_softness : hint_range(0.02, 0.3, 0.01) = 0.08;
uniform float dirt_patch_amount : hint_range(0.0, 1.0, 0.01) = 0.26;
uniform float relief_strength : hint_range(0.0, 0.5, 0.01) = 0.22;
uniform float surface_roughness : hint_range(0.0, 1.0, 0.01) = 0.92;

varying vec2 v_xz;
varying float v_macro_n;
varying float v_rock_mask;
varying float v_height_shade;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_xz = world_pos.xz;

	// Precompute low-frequency macro noise, slope rock mask, and height shading per-vertex (400x cheaper than per-pixel)
	float m1 = value_noise(v_xz * macro_scale + vec2(11.3, -7.9));
	float m2 = value_noise(v_xz * (macro_scale * 2.1) + vec2(-5.4, 19.1));
	v_macro_n = m1 * 0.65 + m2 * 0.35;

	float upness = clamp(world_normal.y, 0.0, 1.0);
	v_rock_mask = 1.0 - smoothstep(slope_threshold - slope_softness, slope_threshold + slope_softness, upness);
	v_height_shade = clamp(0.95 + world_pos.y * 0.025, 0.86, 1.10);
}

void fragment() {
	// Only 3 fast value_noise evaluations per pixel total
	float n_med_a = value_noise(v_xz * detail_scale);
	float n_med_b = value_noise(v_xz * (detail_scale * 2.3) + vec2(17.1, 9.4));
	float med_n = n_med_a * 0.6 + n_med_b * 0.4;

	float fw = length(fwidth(v_xz));
	float micro_fade = 1.0 - smoothstep(0.025, 0.16, fw);
	float fine_n = value_noise(v_xz * micro_scale);
	float micro_grain = mix(0.5, fine_n, micro_fade);

	// 1. Meadow Grass Color
	vec3 g_col = mix(grass_deep_color, grass_mid_color, smoothstep(0.22, 0.78, v_macro_n));
	g_col = mix(g_col, grass_sun_color, smoothstep(0.35, 0.80, med_n) * 0.75);
	g_col *= mix(0.85, 1.14, micro_grain);

	// 2. Soil Patch Color
	vec3 d_col = mix(dirt_dark_color, dirt_light_color, smoothstep(0.20, 0.80, med_n));
	d_col *= mix(0.84, 1.15, micro_grain);

	// 3. Slope Rock Color
	vec3 r_col = mix(rock_dark_color, rock_light_color, smoothstep(0.25, 0.75, n_med_b));
	r_col *= mix(0.86, 1.12, micro_grain);

	// 4. Blend Layers
	float patch_field = v_macro_n * 0.60 + med_n * 0.40;
	float grass_patch = smoothstep(dirt_patch_amount - 0.05, dirt_patch_amount + 0.07, patch_field);
	vec3 ground_col = mix(d_col, g_col, grass_patch);
	ground_col = mix(ground_col, r_col, v_rock_mask);

	// 5. Zero-cost screen-space derivative relief shading (no extra noise samples needed)
	float grad = (dFdx(fine_n) + dFdy(fine_n)) * micro_fade;
	float relief = 1.0 + clamp(grad * relief_strength * 2.5, -0.14, 0.14);

	ALBEDO = ground_col * v_height_shade * relief;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;
}
