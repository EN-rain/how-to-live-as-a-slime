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

varying float v_wet_mul;
varying float v_rough;
varying float v_spec;
varying float v_flash;
varying vec3 v_flash_rgb;
varying vec3 v_flash_emit;

void vertex() {
	float wet = clamp(u_weather_wetness, 0.0, 1.0);
	v_wet_mul = mix(1.0, 0.88, wet);
	v_rough = mix(base_roughness, 0.54, wet);
	v_spec = mix(base_specular, 0.22, wet);
	v_flash = clamp(hit_flash.a, 0.0, 1.0);
	v_flash_rgb = hit_flash.rgb;
	v_flash_emit = v_flash_rgb * v_flash * 0.65;
}

void fragment() {
	vec3 col = albedo_color.rgb;
	if (use_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	col *= v_wet_mul;
	col = mix(col, v_flash_rgb, v_flash);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = v_rough;
	SPECULAR = v_spec;
	EMISSION = v_flash_emit;
}
