shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap;

global uniform float u_weather_wetness;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool use_tex = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float base_roughness : hint_range(0.1, 1.0) = 0.86;
uniform float base_specular : hint_range(0.0, 0.5) = 0.08;

// Per-instance hit flash without duplicating materials
instance uniform vec4 hit_flash : source_color = vec4(0.0, 0.0, 0.0, 0.0);

void fragment() {
	vec3 col = albedo_color.rgb;
	if (use_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	float wet = clamp(u_weather_wetness, 0.0, 1.0);
	col *= mix(1.0, 0.88, wet);

	float flash = clamp(hit_flash.a, 0.0, 1.0);
	col = mix(col, hit_flash.rgb, flash);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(base_roughness, 0.54, wet);
	SPECULAR = mix(base_specular, 0.22, wet);
	EMISSION = hit_flash.rgb * flash * 0.65;
}
