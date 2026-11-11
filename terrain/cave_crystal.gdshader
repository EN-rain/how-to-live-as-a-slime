shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap;

uniform float emission_strength : hint_range(0.2, 4.0, 0.05) = 0.72;
uniform float fresnel_power : hint_range(1.0, 6.0, 0.1) = 3.2;
uniform float pulse_speed : hint_range(0.0, 4.0, 0.1) = 1.15;

varying float v_height01;
varying vec3 v_inst_col;
varying float v_phase;

void vertex() {
	v_height01 = clamp(UV.y, 0.0, 1.0);
	v_inst_col = COLOR.rgb;
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_phase = fract(sin(dot(world_origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.28318;
}

void fragment() {
	vec3 hue = v_inst_col;
	if (length(hue) < 0.05) {
		hue = vec3(0.22, 0.90, 1.0);
	}

	vec3 n_view = normalize(NORMAL);
	vec3 v_view = normalize(VIEW);
	float ndv = clamp(dot(n_view, v_view), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, fresnel_power);
	// Faceted crystalline cleavage contrast so every hexagonal prism face reads as sharp solid quartz
	float facet_catch = 0.42 + 0.58 * clamp(dot(n_view, normalize(vec3(0.35, 0.88, 0.30))), 0.0, 1.0);
	float tip_glow = smoothstep(0.18, 0.96, v_height01);
	float root_ao = mix(0.22, 1.0, smoothstep(0.0, 0.38, v_height01));
	float shimmer = 0.92 + 0.08 * sin(TIME * pulse_speed + v_phase);

	vec3 core_col = mix(hue * 0.14, hue * 0.58, tip_glow) * facet_catch;
	vec3 rim_col = mix(hue, vec3(1.0), 0.45);

	ALBEDO = mix(core_col, rim_col * facet_catch, fresnel * 0.55) * root_ao;
	EMISSION = (hue * 0.16 * pow(tip_glow, 1.7) + rim_col * pow(fresnel, 1.15) * 0.42) * facet_catch * emission_strength * root_ao * shimmer;
	ROUGHNESS = 0.12;
	SPECULAR = 0.95;
	METALLIC = 0.12;
}
