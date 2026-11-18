shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

global uniform float u_wind_strength;
global uniform float u_weather_wetness;

group_uniforms GrassTexture;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.1, 0.9, 0.05) = 0.40;

group_uniforms GrassColors;
uniform vec3 grass_sun_color : source_color = vec3(0.32, 0.56, 0.20);
uniform vec3 grass_mid_color : source_color = vec3(0.23, 0.44, 0.15);
uniform vec3 grass_deep_color : source_color = vec3(0.15, 0.32, 0.11);
uniform vec3 tip_color : source_color = vec3(0.40, 0.60, 0.22);
uniform float macro_scale : hint_range(0.005, 0.2, 0.005) = 0.025;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.75;

group_uniforms GrassMap;
uniform sampler2D grass_map : hint_default_white, filter_linear;
uniform vec4 grass_map_bounds = vec4(-1200.0, -900.0, 2600.0, 3800.0);
uniform vec2 u_webwood_center = vec2(-410.0, 480.0);

varying vec3 v_ground_root;
varying float v_blade_height;
varying float v_grass_map_h;
varying float v_webwood_w;

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

	float d_webwood = length(xz - u_webwood_center);
	float webwood_w = 1.0 - smoothstep(82.0, 178.0, d_webwood + (macro_pat - 0.5) * 18.0);
	vec3 webwood_moss = mix(vec3(0.010, 0.026, 0.014), vec3(0.024, 0.040, 0.034), smoothstep(0.25, 0.78, canopy_blend));
	v_ground_root = mix(v_ground_root, webwood_moss, webwood_w * 0.94);
	v_webwood_w = webwood_w;

	vec2 gm_uv = clamp((xz - grass_map_bounds.xy) / grass_map_bounds.zw, vec2(0.0), vec2(1.0));
	vec3 gm = texture(grass_map, gm_uv).rgb;
	v_grass_map_h = gm.g * mix(1.0, 0.22, webwood_w);

	// Blade height fraction (0 at root, 1 at tip)
	float h = clamp(VERTEX.y * 1.35, 0.0, 1.0);
	v_blade_height = h;
	VERTEX.y *= mix(0.86, 1.16, gm.g) * mix(1.0, 0.58, webwood_w);

	// Lightweight single-wave wind sway beyond 32m (zero slime push / zero matrix inverse)
	float wind_boost = 1.0 + u_wind_strength * 2.1;
	float breeze = sin(TIME * (2.2 + u_wind_strength * 1.4) + xz.x * 0.18 + xz.y * 0.14) * 0.08 * wind_boost * (h * h);
	VERTEX.x += breeze;
	VERTEX.z += breeze * 0.65;

	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 tex = texture(grass_texture, UV);

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	float tex_lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float ao = mix(0.55, 1.0, smoothstep(0.0, 0.45, v_blade_height));
	vec3 blade_base = v_ground_root * (0.85 + tex_lum * 0.35) * ao;
	vec3 tall_tip_col = mix(tip_color, vec3(0.18, 0.27, 0.036), smoothstep(0.42, 0.94, v_grass_map_h));
	// Webwood tips: dull the bright olive tips into cold slate moss so the domain reads shadowed
	tall_tip_col = mix(tall_tip_col, tall_tip_col * vec3(0.22, 0.34, 0.40) + vec3(0.008, 0.012, 0.016), v_webwood_w * 0.94);
	vec3 blade_col = mix(blade_base, tall_tip_col, smoothstep(0.32, 1.0, v_blade_height) * mix(0.28, 0.44, v_grass_map_h));

	ALBEDO = blade_col * mix(1.0, 0.86, u_weather_wetness);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
