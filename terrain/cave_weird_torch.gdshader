shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

// Brazier glowing charcoal & incandescent ember bed shader.
uniform sampler2D veil_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float torch_intensity : hint_range(0.3, 2.5, 0.05) = 1.15;
uniform float awaken_amount : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float torch_side_seed = 0.0;

varying vec3 v_local_pos;
varying vec2 v_uv;
varying vec4 v_col;

void vertex() {
	v_local_pos = VERTEX;
	v_uv = UV;
	v_col = COLOR;
}

void fragment() {
	float t = TIME + torch_side_seed * 2.1;
	vec2 p = (v_uv - vec2(0.5)) * 2.0;
	float radial = clamp(length(p), 0.0, 1.0);

	vec4 n1 = texture(veil_tex, v_local_pos.xz * 2.2 + vec2(0.13, -0.09));
	vec4 n2 = texture(veil_tex, v_local_pos.xz * 4.8 + vec2(-0.31, 0.27));
	float chunk = n1.r * 0.60 + n2.g * 0.40;
	float fissure = 1.0 - smoothstep(0.24, 0.56, chunk);

	float pulse = 0.84 + 0.16 * sin(t * 3.1 + n1.b * 4.5) + 0.08 * cos(t * 5.7 + n2.a * 6.0);
	float core_heat = clamp((1.0 - pow(radial, 1.65)) * 0.85 + 0.25, 0.0, 1.0);
	float glow = clamp(fissure * core_heat * pulse * (1.0 + awaken_amount * 0.35), 0.0, 1.0);

	vec3 charcoal = mix(vec3(0.022, 0.019, 0.018), vec3(0.095, 0.082, 0.075), smoothstep(0.45, 0.88, chunk));
	vec3 ember_deep = vec3(0.92, 0.16, 0.01);
	vec3 ember_hot = vec3(1.0, 0.64, 0.12);
	vec3 ember_col = mix(ember_deep, ember_hot, smoothstep(0.35, 0.92, glow));

	ALBEDO = charcoal * v_col.r;
	EMISSION = ember_col * glow * torch_intensity * 1.45;
	ROUGHNESS = mix(0.94, 0.52, glow);
	METALLIC = 0.0;
	SPECULAR = 0.10;

	// Crisp charred coal facet micro-normal
	float h_bump = chunk * 0.85;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h_bump);
	float dhdy = dFdy(h_bump);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-6) {
		vec3 surf_grad = sign(det) * (dhdx * r1 + dhdy * r2);
		NORMAL = normalize(NORMAL - 0.18 * surf_grad);
	}
}
