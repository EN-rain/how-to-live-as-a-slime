shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

group_uniforms WaterColors;
uniform vec3 shallow_color : source_color = vec3(0.18, 0.78, 0.84);
uniform vec3 deep_color : source_color = vec3(0.06, 0.32, 0.68);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.85;
uniform float depth_distance : hint_range(0.5, 15.0) = 6.5;
uniform float foam_depth : hint_range(0.05, 2.0) = 0.65;

group_uniforms Waves;
uniform float wave_speed : hint_range(0.1, 4.0) = 0.85;
uniform float wave_amplitude : hint_range(0.0, 0.5) = 0.12;
uniform float wave_frequency : hint_range(0.05, 2.0) = 0.12;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.12;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec2 v_uv;

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
	v_uv = world_pos.xz;

	// Only displace vertices near the continent shoreline (< 4000m from origin)
	if (dot(world_pos.xz, world_pos.xz) < 16000000.0) {
		float t = TIME * wave_speed;
		float w1 = sin(world_pos.x * wave_frequency + t) * cos(world_pos.z * (wave_frequency * 0.8) + t * 0.9);
		VERTEX.y += w1 * wave_amplitude;
	}
}

void fragment() {
	// Linearize scene depth to calculate exact water depth against the island terrain
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_depth = -view_pos.z;
	float diff_depth = linear_depth + VERTEX.z;
	float water_depth = max(diff_depth, 0.0);

	// Fast-path for deep open ocean or distant horizon: skips all 3 value_noise calls
	if (water_depth >= depth_distance || -VERTEX.z > 750.0) {
		ALBEDO = deep_color;
		ROUGHNESS = roughness_val;
		SPECULAR = 0.5;
		ALPHA = 1.0;
	} else {
		float t = TIME * wave_speed;
		float depth_ratio = clamp(water_depth / depth_distance, 0.0, 1.0);

		vec2 uv_flow1 = v_uv * 0.35 + vec2(t * 0.08, t * 0.06);
		float n1 = value_noise(uv_flow1);
		float caustic_ripple = smoothstep(0.42, 0.75, n1);

		vec3 water_col = mix(shallow_color, deep_color, depth_ratio);
		water_col += caustic_ripple * 0.10 * (1.0 - depth_ratio * 0.6);

		float foam_band = 0.0;
		if (water_depth < foam_depth + 0.35) {
			float foam_noise = value_noise(v_uv * 1.4 + vec2(t * 0.25, -t * 0.18)) * 0.15;
			foam_band = 1.0 - smoothstep(0.02, foam_depth + foam_noise, water_depth);
		}

		ALBEDO = mix(water_col, foam_color, foam_band);
		ROUGHNESS = mix(roughness_val, 0.6, foam_band);
		SPECULAR = 0.5;
		ALPHA = mix(mix(water_opacity, 1.0, depth_ratio), 1.0, foam_band);
	}
}
