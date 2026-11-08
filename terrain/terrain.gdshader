shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms TerrainTexture;
uniform sampler2D terrain_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D terrain_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 terrain_tint : source_color = vec3(0.56, 0.42, 0.28);
uniform vec3 terrain_dark_tint : source_color = vec3(0.38, 0.27, 0.18);
uniform float terrain_uv_scale : hint_range(0.01, 2.0, 0.01) = 0.12;
uniform float terrain_roughness : hint_range(0.0, 1.0, 0.01) = 0.88;

group_uniforms GrassTexture;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 grass_light_tint : source_color = vec3(0.42, 0.74, 0.28);
uniform vec3 grass_dark_tint : source_color = vec3(0.22, 0.52, 0.18);
uniform float grass_uv_scale : hint_range(0.01, 2.0, 0.01) = 0.18;
uniform float grass_roughness : hint_range(0.0, 1.0, 0.01) = 0.72;

group_uniforms Blending;
uniform sampler2D blend_noise : filter_linear_mipmap, repeat_enable;
uniform float blend_uv_scale : hint_range(0.005, 0.5, 0.005) = 0.035;
uniform float slope_threshold : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float slope_softness : hint_range(0.01, 0.5, 0.01) = 0.12;
uniform float patch_strength : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float normal_strength : hint_range(0.0, 2.0, 0.05) = 0.65;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	vec2 terrain_uv = v_world_pos.xz * terrain_uv_scale;
	vec2 grass_uv = v_world_pos.xz * grass_uv_scale;
	vec2 macro_uv = v_world_pos.xz * blend_uv_scale;

	// Sample terrain (dirt / soil / rock) texture at two scales to avoid tiling repetition
	vec3 t_sample_a = texture(terrain_texture, terrain_uv).rgb;
	vec3 t_sample_b = texture(terrain_texture, terrain_uv * 0.37 + vec2(0.41, 0.19)).rgb;
	float t_luma = dot(mix(t_sample_a, t_sample_b, 0.45), vec3(0.299, 0.587, 0.114));
	vec3 dirt_col = mix(terrain_dark_tint, terrain_tint, clamp(t_luma * 1.35, 0.0, 1.0)) * mix(vec3(0.85), t_sample_a * 1.25, 0.55);

	// Sample grass surface texture at two scales
	vec3 g_sample_a = texture(grass_texture, grass_uv).rgb;
	vec3 g_sample_b = texture(grass_texture, grass_uv * 0.31 + vec2(0.73, 0.29)).rgb;
	float g_luma = dot(mix(g_sample_a, g_sample_b, 0.5), vec3(0.299, 0.587, 0.114));
	vec3 grass_col = mix(grass_dark_tint, grass_light_tint, clamp(g_luma * 1.3, 0.0, 1.0)) * mix(vec3(0.88), g_sample_a * 1.2, 0.5);

	// Blend factor based on surface slope + organic macro patches
	float macro = texture(blend_noise, macro_uv).r;
	float upness = clamp(v_world_normal.y, 0.0, 1.0);
	float slope_mask = smoothstep(slope_threshold - slope_softness, slope_threshold + slope_softness, upness);
	float patch_mask = smoothstep(0.28, 0.62, macro + (1.0 - patch_strength) * 0.35);
	float grass_weight = clamp(slope_mask * patch_mask, 0.0, 1.0);

	ALBEDO = mix(dirt_col, grass_col, grass_weight);
	ROUGHNESS = mix(terrain_roughness, grass_roughness, grass_weight);
	METALLIC = 0.0;
	SPECULAR = 0.25;

	vec3 t_norm = texture(terrain_normal, terrain_uv).rgb;
	vec3 g_norm = texture(grass_normal, grass_uv).rgb;
	NORMAL_MAP = mix(t_norm, g_norm, grass_weight);
	NORMAL_MAP_DEPTH = normal_strength;
}
