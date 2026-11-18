shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap;

global uniform float u_wind_strength;
global uniform float u_weather_wetness;

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor : hint_range(0.1, 0.9) = 0.42;
uniform vec3 leaf_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float wind_amp : hint_range(0.0, 0.4) = 0.075;
uniform vec2 u_webwood_center = vec2(-410.0, 480.0);

varying vec3 v_sky_up_view;
varying float v_webwood_w;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = wind_amp * (0.65 + u_wind_strength * 2.2);
	float h_mask = clamp((VERTEX.y - 1.2) * 0.28, 0.0, 1.0);
	float phase = TIME * (1.8 + u_wind_strength * 2.6) + world_pos.x * 0.37 + world_pos.z * 0.29;
	float gust = sin(phase) * 0.65 + sin(phase * 2.13 + world_pos.y) * 0.35;
	VERTEX.x += gust * w * h_mask;
	VERTEX.z += cos(phase * 0.87) * w * 0.65 * h_mask;
	v_sky_up_view = VIEW_MATRIX[1].xyz;
	v_webwood_w = 1.0 - smoothstep(95.0, 180.0, length(world_pos.xz - u_webwood_center));
}

void fragment() {
	vec4 tex = texture(leaf_texture, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Soften harsh leaf-card normals toward sky up for Ghibli canopy volume shading
	NORMAL = normalize(mix(NORMAL, v_sky_up_view, 0.36));

	vec3 base_col = tex.rgb * leaf_tint;
	vec3 canopy_col = base_col * vec3(0.28, 0.40, 0.44);
	ALBEDO = mix(base_col, canopy_col, v_webwood_w * 0.92) * mix(1.0, 0.88, u_weather_wetness);
	ROUGHNESS = mix(0.85, 0.50, u_weather_wetness);
	SPECULAR = mix(0.06, 0.20, u_weather_wetness);
	METALLIC = 0.0;
}
