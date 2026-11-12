shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

uniform vec3 core_color : source_color = vec3(0.10, 0.88, 1.0);
uniform vec3 deep_color : source_color = vec3(0.03, 0.06, 0.28);
uniform vec3 prism_color : source_color = vec3(0.72, 0.28, 1.0);
uniform float emission_strength : hint_range(0.2, 4.0, 0.05) = 1.25;
uniform sampler2D interior_veil_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 v_local_pos;
varying vec3 v_local_nrm;
varying vec2 v_uv;
varying vec3 v_vert_col;

void vertex() {
	v_local_pos = VERTEX;
	v_local_nrm = NORMAL;
	v_uv = UV;
	v_vert_col = COLOR.rgb;
}

void fragment() {
	vec3 n_view = normalize(NORMAL);
	vec3 v_view = normalize(VIEW);
	float ndv = clamp(dot(n_view, v_view), 0.0, 1.0);
	float inv_ndv = max(1.0 - ndv, 1e-4);
	float fresnel = pow(inv_ndv, 2.55);

	// Blend vertex color with core_color (handles both default WHITE and tinted companion shards)
	vec3 shard_hue = (min(v_vert_col.r, min(v_vert_col.g, v_vert_col.b)) > 0.92 || length(v_vert_col) < 0.05)
		? core_color
		: mix(core_color, v_vert_col, 0.78);

	// Per-triangle crystal facet hash for unmistakable jewel cut contrast
	vec3 q_n = floor(normalize(v_local_nrm) * 28.0 + 0.5);
	float facet_rand = fract(sin(dot(q_n, vec3(12.9898, 78.233, 37.719))) * 43758.5453);

	// 1. Triplanar Parallax coordinates inside elongated cut gemstone shard (zero polar pinch)
	float r_norm = clamp(length(v_local_pos) / 1.05, 0.0, 1.25);
	float tip_flare = smoothstep(0.18, 0.96, abs(v_local_pos.y));
	vec2 dir_xy = v_view.xy / max(abs(v_view.z) + 0.50, 0.50);
	vec3 an = abs(normalize(v_local_nrm));
	vec2 tri_uv = mix(v_local_pos.xy, v_local_pos.zy, smoothstep(0.35, 0.65, an.x)) * 1.15;

	// Counter-drifting subtle internal cleavage & chromatic dispersion
	vec2 p1 = tri_uv - dir_xy * 0.12 + vec2(TIME * 0.022, -TIME * 0.015);
	vec2 p2 = tri_uv * 1.52 - dir_xy * 0.25 + vec2(-TIME * 0.028, TIME * 0.018);
	vec4 tap1 = texture(interior_veil_tex, p1);
	vec4 tap2 = texture(interior_veil_tex, p2);

	vec2 disp = normalize(dir_xy + vec2(0.001, 0.002)) * 0.020;
	float disp_r = texture(interior_veil_tex, p1 + disp).g;
	float disp_b = texture(interior_veil_tex, p1 - disp).g;

	// 2. Pinpoint Luminous Heart Deep Inside + Crisp Cut Facet Illumination (rich jewel contrast, zero flat white washout)
	float pulse = 0.90 + 0.10 * sin(TIME * 2.2);
	float heart = pow(max(ndv, 1e-4), 3.6) * (0.58 + 0.20 * sin(TIME * 2.8 + r_norm * 3.4));
	float key1 = clamp(dot(n_view, normalize(vec3(0.48, 0.76, 0.44))), 0.0, 1.0);
	float key2 = clamp(dot(n_view, normalize(vec3(-0.62, 0.35, 0.68))), 0.0, 1.0);
	float facet_pop = clamp((0.16 + 0.64 * key1 + 0.26 * key2) * (0.68 + 0.56 * facet_rand), 0.16, 1.16);

	// Crisp facet edge gleam from UV.x prism seams
	float edge_dist = abs(fract(v_uv.x * 6.0 + 0.5) - 0.5);
	float edge_gleam = pow(max(1.0 - smoothstep(0.0, 0.070, edge_dist), 1e-4), 2.3);

	vec3 h1 = normalize(normalize(vec3(0.42, 0.84, 0.34)) + v_view);
	vec3 h2 = normalize(normalize(vec3(-0.56, 0.44, 0.70)) + v_view);
	float diamond_glint = pow(max(dot(n_view, h1), 1e-4), 138.0) * 0.45 + pow(max(dot(n_view, h2), 1e-4), 78.0) * 0.24;

	float cleave = pow(clamp(max(tap1.r * 0.68, tap2.r * 0.45), 1e-4, 1.0), 2.05);
	float inner_cell = tap1.g * 0.6 + tap2.g * 0.4;
	float phantom_veil = tap2.b * 0.65 + tap1.b * 0.35;

	// 3. Deep Sapphire Absorption -> Prism Violet-Magenta -> Aquamarine Dispersion Rim
	vec3 deep_shard = mix(deep_color, shard_hue * 0.22, 0.35);
	vec3 irid = mix(shard_hue, prism_color, clamp(fresnel * 1.15 + (disp_b - disp_r) * 1.1 + 0.20 * sin(TIME + v_local_pos.y * 3.6 + facet_rand * 2.0), 0.0, 1.0));
	vec3 interior_col = mix(deep_shard, shard_hue * 0.82, clamp(inner_cell * 0.40 + heart * 0.46 + tip_flare * 0.36, 0.0, 1.0));
	interior_col += irid * (cleave * 0.18 + phantom_veil * 0.14);
	interior_col += mix(shard_hue, vec3(0.75, 0.96, 1.0), 0.38) * (edge_gleam * 0.34);

	ALBEDO = mix(interior_col * facet_pop, irid, clamp(fresnel * 0.46 + edge_gleam * 0.22, 0.0, 0.72));
	vec3 raw_em = (
		shard_hue * (heart * 0.48 + tip_flare * 0.38 + cleave * 0.14 + phantom_veil * 0.12) * (0.38 + 0.62 * facet_pop)
		+ irid * (fresnel * 0.56 + edge_gleam * 0.42)
		+ vec3(0.72, 0.95, 1.0) * diamond_glint
	) * emission_strength * pulse;
	EMISSION = raw_em / (1.0 + raw_em * 0.28);

	ROUGHNESS = 0.80;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
