shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

group_uniforms GrassTexture;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.1, 0.9, 0.05) = 0.40;

group_uniforms GrassColors;
uniform vec3 grass_sun_color : source_color = vec3(0.50, 0.88, 0.28);
uniform vec3 grass_mid_color : source_color = vec3(0.36, 0.72, 0.20);
uniform vec3 grass_deep_color : source_color = vec3(0.22, 0.54, 0.14);
uniform vec3 tip_color : source_color = vec3(0.62, 0.95, 0.34);
uniform float macro_scale : hint_range(0.005, 0.2, 0.005) = 0.025;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.75;

group_uniforms SlimeInteraction;
uniform vec3 slime_pos = vec3(0.0, 999.0, 0.0);
uniform float slime_radius : hint_range(0.5, 5.0, 0.1) = 1.9;

varying vec3 v_ground_root;
varying float v_blade_height;

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
	vec2 xz = world_pos.xz;

	// Terrain macro-color matching (exact 1:1 match with terrain ground shader)
	float macro_pat = value_noise(xz * macro_scale);
	float med_pat = value_noise(xz * 0.25 + vec2(5.2, -8.7));
	float canopy_blend = macro_pat * 0.70 + med_pat * 0.30;

	v_ground_root = mix(grass_deep_color, grass_mid_color, smoothstep(0.28, 0.58, canopy_blend));
	v_ground_root = mix(v_ground_root, grass_sun_color, smoothstep(0.52, 0.82, canopy_blend));

	// Blade height fraction (0 at root, 1 at tip)
	float h = clamp(VERTEX.y * 1.35, 0.0, 1.0);
	v_blade_height = h;

	// Multi-frequency wind sway on upper blade
	float breeze = sin(TIME * 2.2 + xz.x * 0.18 + xz.y * 0.14) * 0.08 * (h * h);
	breeze += sin(TIME * 4.1 + xz.x * 0.45 - xz.y * 0.35) * 0.03 * (h * h);
	VERTEX.x += breeze;
	VERTEX.z += breeze * 0.65;

	// Dynamic Slime Collision Push: grass bends outward and down under slime body
	vec3 to_slime = world_pos - slime_pos;
	float dist_slime_xz = length(to_slime.xz);
	if (dist_slime_xz < slime_radius && abs(to_slime.y) < 2.0) {
		float push = (1.0 - dist_slime_xz / slime_radius) * h;
		vec2 push_dir = (dist_slime_xz > 0.01) ? (to_slime.xz / dist_slime_xz) : vec2(0.707, 0.707);
		VERTEX.x += push_dir.x * push * 0.70;
		VERTEX.z += push_dir.y * push * 0.70;
		VERTEX.y -= push * 0.35;
	}

	// Normal aligns predominantly skyward with subtle lateral curve for soft Ghibli lighting
	NORMAL = normalize(vec3(0.0, 0.95, 0.0) + vec3(sin(VERTEX.x * 3.0), 0.0, cos(VERTEX.z * 3.0)) * 0.12);
}

void fragment() {
	vec4 tex = texture(grass_texture, UV);
	if (tex.a < alpha_scissor_threshold) {
		discard;
	}
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	// Botanical color harmony with ground terrain:
	// Extract texture luminance to preserve painted blade details and fiber grain
	float tex_lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

	// Root ambient occlusion: darkens bottom 45% of tuft so grass anchors into soil with 3D depth
	float ao = mix(0.55, 1.0, smoothstep(0.0, 0.45, v_blade_height));

	// Base color harmonizes with terrain meadow palette with ambient occlusion
	vec3 blade_base = v_ground_root * (0.85 + tex_lum * 0.35) * ao;

	// Vibrant sunny gradient towards blade tips
	vec3 blade_col = mix(blade_base, tip_color, smoothstep(0.30, 1.0, v_blade_height) * 0.45);

	ALBEDO = blade_col;
	ROUGHNESS = roughness;
	SPECULAR = 0.20;
	METALLIC = 0.0;
}
