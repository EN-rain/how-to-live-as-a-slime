shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

group_uniforms GrassTexture;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.18, 0.46, 0.15);
uniform vec3 tip_color : source_color = vec3(0.54, 0.86, 0.34);
uniform float world_uv_scale : hint_range(0.01, 1.0, 0.01) = 0.08;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.62;

group_uniforms Wind;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform float wind_speed : hint_range(0.0, 5.0, 0.1) = 1.25;
uniform float wind_strength : hint_range(0.0, 1.5, 0.05) = 0.28;
uniform vec2 wind_direction = vec2(1.0, 0.4);
uniform float wind_scale : hint_range(0.01, 0.5, 0.01) = 0.06;

varying vec3 v_world_pos;
varying float v_height_factor;
varying float v_wind_wave;

void vertex() {
	// UV.y = 1 at bottom root, 0 at top tip (or 0..1 from root to tip based on vertex Y)
	float h = clamp(VERTEX.y / 0.85, 0.0, 1.0);
	v_height_factor = h;

	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 w_dir = normalize(wind_direction + vec2(1e-4, 0.0));
	vec2 wind_uv = world_origin.xz * wind_scale + w_dir * (TIME * wind_speed * 0.25);
	float noise_val = textureLod(wind_noise, wind_uv, 0.0).r * 2.0 - 1.0;

	float wave = sin(TIME * wind_speed * 2.2 + dot(world_origin.xz, w_dir) * 0.45) * 0.6 + noise_val * 0.4;
	v_wind_wave = wave;

	float bend = h * h * wind_strength * (0.65 + 0.35 * wave);
	VERTEX.xz += w_dir * bend;
	VERTEX.y -= abs(bend) * 0.18;

	// Blend normal toward world-up so grass blades match the underlying terrain lighting smoothly
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.72));
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 tex_col = texture(grass_texture, v_world_pos.xz * world_uv_scale + UV * 0.25).rgb;
	vec3 grad_col = mix(base_color, tip_color, pow(v_height_factor, 1.15));
	vec3 wind_highlight = vec3(0.06, 0.10, 0.02) * max(v_wind_wave, 0.0) * v_height_factor;

	ALBEDO = grad_col * mix(vec3(0.85), tex_col * 1.25, 0.45) + wind_highlight;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.28, 0.45, 0.14) * v_height_factor;
}
