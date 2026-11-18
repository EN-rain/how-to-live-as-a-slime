shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 silk_color : source_color = vec4(0.86, 0.91, 0.95, 0.88);
uniform float radial_spokes : hint_range(6.0, 24.0, 1.0) = 13.0;
uniform float ring_count : hint_range(3.0, 16.0, 1.0) = 8.0;
uniform float thread_width : hint_range(0.015, 0.20, 0.005) = 0.085;
uniform float sway_amp : hint_range(0.0, 0.25, 0.005) = 0.045;
uniform float seed_phase : hint_range(0.0, 100.0, 0.1) = 0.0;
uniform float is_funnel : hint_range(0.0, 1.0, 1.0) = 0.0;
uniform float web_mode : hint_range(0.0, 5.0, 1.0) = 0.0;
uniform bool use_noise_tex = false;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying float v_seed;
varying float v_mode_var;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm_silk(vec2 p) {
	return 0.56 * vnoise(p) + 0.30 * vnoise(p * 2.13 + vec2(5.7, -3.4)) + 0.14 * vnoise(p * 4.41 - vec2(2.9, 8.1));
}

float line_mask(float wave, float half_w) {
	float fw = max(fwidth(wave) * 0.75, 0.004);
	return 1.0 - smoothstep(half_w, half_w + fw * 1.5 + 0.010, wave);
}

vec2 eval_fiber_web(vec2 uv, float n_macro, float n_fine, float sc, float seed, float clump) {
	vec2 w_uv = uv + vec2(n_macro - 0.5, n_fine - 0.5) * 0.22;
	float f1 = abs(fract((w_uv.x * 0.88 + w_uv.y * 0.47) * 11.0 * sc + n_fine * 0.55) - 0.5) * 2.0;
	float f2 = abs(fract((w_uv.x * -0.62 + w_uv.y * 0.78) * 13.5 * sc - n_macro * 0.50) - 0.5) * 2.0;
	float f3 = abs(fract((w_uv.x * 0.28 - w_uv.y * 0.96) * 16.0 * sc + n_fine * 0.42) - 0.5) * 2.0;
	float f4 = abs(fract((w_uv.x * 0.95 - w_uv.y * 0.31) * 8.5 * sc + n_macro * 0.65) - 0.5) * 2.0;
	float f5 = abs(fract((w_uv.y + sin(w_uv.x * 6.0 + seed) * 0.14) * 7.0 * sc) - 0.5) * 2.0;
	float thick_cables = max(line_mask(f4, 0.105), line_mask(f5, 0.095));
	float med_fibers = max(line_mask(f1, 0.082), line_mask(f2, 0.078));
	float fine_mesh = line_mask(f3, 0.065);
	float fiber_web = max(thick_cables * 0.95, max(med_fibers * mix(0.55, 1.0, clump), fine_mesh * clump * 0.85));
	return vec2(fiber_web, thick_cables);
}

void vertex() {
	v_seed = seed_phase + COLOR.r * 37.7;
	v_mode_var = max(COLOR.g, 0.65);

	float eff_mode = max(web_mode, is_funnel);
	float pin_mask = 0.0;
	if (eff_mode > 1.5 && eff_mode < 2.5) {
		pin_mask = smoothstep(0.05, 0.85, UV.y);
	} else if (eff_mode > 2.5 && eff_mode < 3.5) {
		pin_mask = 0.0;
	} else {
		float edge_x = 1.0 - smoothstep(0.55, 0.98, abs(UV.x - 0.5) * 2.0);
		float edge_y = 1.0 - smoothstep(0.60, 0.98, abs(UV.y - 0.5) * 2.0);
		pin_mask = edge_x * (0.35 + 0.65 * edge_y);
	}

	float flutter = sin(TIME * 1.8 + v_seed + VERTEX.x * 0.85 + VERTEX.z * 0.75) * 0.7
		+ cos(TIME * 2.9 + v_seed * 1.3 + VERTEX.y * 1.2) * 0.3;
	VERTEX += NORMAL * flutter * pin_mask * sway_amp;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float eff_mode = max(web_mode, is_funnel);
	float strand = 0.0;
	float veil = 0.0;

	// Domain-warped organic silk coordinates (completely non-radial, non-spiral!)
	vec2 uv = UV;
	// Guaranteed zero-alpha border/corner early-out before noise/fwidth() work
	if (eff_mode < 1.5) {
		vec2 p_chk = (uv - vec2(0.5)) * 2.0;
		if (length(p_chk * vec2(1.0, 1.05)) > 1.35) {
			discard;
		}
	} else if (eff_mode < 2.5) {
		if (uv.y > 0.97 || uv.x <= 0.002 || uv.x >= 0.998) {
			discard;
		}
	} else if (eff_mode < 3.5) {
		if (uv.y < 0.01 || uv.y > 0.99) {
			discard;
		}
	} else {
		if (uv.x < 0.002 || uv.x > 0.998 || uv.y < 0.002 || uv.y > 0.998) {
			discard;
		}
	}

	vec2 seed_v = vec2(sin(v_seed * 0.73), cos(v_seed * 1.19)) * 6.0;
	float n_macro = 0.0;
	float n_fine = 0.0;
	if (use_noise_tex) {
		n_macro = texture(noise_tex, uv * 0.65 * v_mode_var + seed_v * 0.17).r;
		n_fine = texture(noise_tex, uv * 1.62 * v_mode_var - seed_v * 0.24).r;
	} else {
		n_macro = fbm_silk(uv * 3.8 * v_mode_var + seed_v);
		n_fine = fbm_silk(uv * 9.5 * v_mode_var - seed_v * 1.4);
	}
	float clump = smoothstep(0.24, 0.78, n_macro * 0.62 + n_fine * 0.38);
	float sc = clamp(v_mode_var, 0.75, 2.2);

	if (eff_mode < 1.5) {
		// MODE 0 & 1: Thick Matted Ground/Boulder Funnel-Sheet & Stretched Nest Blanket (ZERO radial spokes!)
		vec2 fw = eval_fiber_web(uv, n_macro, n_fine, sc, v_seed, clump);
		float fiber_web = fw.x;
		float thick_cables = fw.y;

		vec2 p = (uv - vec2(0.5)) * 2.0;
		float r = length(p * vec2(1.0, 1.05));
		float edge_warp = (n_macro - 0.5) * 0.42 + (n_fine - 0.5) * 0.22;
		float edge_fade = 1.0 - smoothstep(0.58, 0.98, r + edge_warp);
		// Stretched anchor tendrils reaching past the edge onto rocks/bark/soil
		float tendrils = smoothstep(0.42, 0.95, thick_cables * (1.0 - smoothstep(0.72, 1.12, r + edge_warp * 0.7)));
		float env = max(edge_fade, tendrils * 0.78);
		// Dense milky funnel throat & thick matted silk sheet pockets
		float funnel_core = (1.0 - smoothstep(0.08, 0.62, r + (n_macro - 0.5) * 0.25)) * 0.58;
		float holes = smoothstep(0.16, 0.42, n_macro * 0.7 + n_fine * 0.3);
		strand = max(fiber_web * mix(0.45, 1.0, holes), funnel_core * 0.85) * env;
		veil = (0.34 * clump * holes + funnel_core * 0.62) * edge_fade;
	} else if (eff_mode < 2.5) {
		// MODE 2: Heavy Hanging Tattered Cobweb Curtains & Festoon Drapes
		float fiber_web = eval_fiber_web(uv, n_macro, n_fine, sc, v_seed, clump).x;

		float u = uv.x;
		float v = uv.y;
		float top_rope = 1.0 - smoothstep(0.02, 0.09, v + (n_fine - 0.5) * 0.04);
		float taper = 0.55 + 0.30 * sin(u * 6.28318 * 2.0 + v_seed) + 0.18 * (n_macro - 0.5);
		taper = clamp(taper, 0.32, 0.98);
		float side_fade = smoothstep(0.0, 0.10, u) * (1.0 - smoothstep(0.90, 1.0, u));
		float v_fade = (1.0 - smoothstep(taper - 0.28, taper, v)) * side_fade;
		float swag = abs(fract((v + 0.16 * sin(u * 9.0 + v_seed) + n_macro * 0.18) * 7.5 * sc) - 0.5) * 2.0;
		float vert_strands = abs(fract((u + (n_fine - 0.5) * 0.10) * 18.0 * sc) - 0.5) * 2.0;
		float drape_mesh = max(line_mask(swag, 0.095), max(line_mask(vert_strands, 0.080) * clump, fiber_web * 0.85));
		float bottom_fade = 1.0 - smoothstep(0.84, 1.0, v);
		strand = max(top_rope * side_fade * 0.90, drape_mesh * v_fade) * bottom_fade;
		veil = v_fade * (1.0 - v * 0.65) * (0.28 + 0.32 * clump) * bottom_fade;
	} else if (eff_mode < 3.5) {
		// MODE 3: Dense Tree-Trunk Silk Shroud Collar & Flared Root Skirt (skips unused f1..f5 fiber_web!)
		float u = uv.x;
		float v = uv.y;
		float s1 = abs(fract(u * 6.0 + v * 4.0 + (n_macro - 0.5) * 0.45) - 0.5) * 2.0;
		float s2 = abs(fract(u * 6.0 - v * 3.5 + (n_fine - 0.5) * 0.45) - 0.5) * 2.0;
		float s3 = abs(fract(v * 8.0 + sin(u * 6.28318 * 3.0 + v_seed) * 0.22) - 0.5) * 2.0;
		float wrap_fibers = max(max(line_mask(s1, 0.115), line_mask(s2, 0.110)), line_mask(s3, 0.095));
		float hole_m = smoothstep(0.24, 0.62, n_macro * 0.65 + n_fine * 0.35);
		float v_prof = smoothstep(0.01, 0.14, v) * (1.0 - smoothstep(0.72, 0.99, v + (n_macro - 0.5) * 0.22));
		strand = wrap_fibers * v_prof * mix(0.45, 1.0, hole_m);
		veil = (0.14 + 0.18 * clump * hole_m) * v_prof;
	} else {
		// MODE 4 & 5: Thick Billowing Overhead Canopy Silk Hammocks & Tangled Sheet Tunnels
		float fiber_web = eval_fiber_web(uv, n_macro, n_fine, sc, v_seed, clump).x;

		float skin = smoothstep(0.0, 0.14, uv.x) * (1.0 - smoothstep(0.86, 1.0, uv.x));
		skin *= smoothstep(0.0, 0.14, uv.y) * (1.0 - smoothstep(0.82, 1.0, uv.y + (n_macro - 0.5) * 0.22));
		// Organic stretched fenestrations (open breathing pockets between thick matted silk ribs)
		float fenestration = smoothstep(0.26, 0.56, n_macro * 0.65 + n_fine * 0.35);
		strand = fiber_web * skin * mix(0.42, 1.0, fenestration);
		veil = skin * (0.16 + 0.24 * clump) * fenestration;
	}

	float alpha = clamp(strand * 0.85 + veil * 0.85, 0.0, 0.84) * silk_color.a;
	if (alpha < 0.020) {
		discard;
	}

	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);
	float glint = smoothstep(0.60, 0.95, strand) * (0.30 + 0.42 * rim);

	ALBEDO = mix(vec3(0.74, 0.81, 0.87), silk_color.rgb, 0.65) * mix(0.92, 1.08, clump);
	ROUGHNESS = 0.34;
	METALLIC = 0.02;
	SPECULAR = 0.40;
	EMISSION = silk_color.rgb * (0.28 + 0.16 * strand + 0.12 * rim + glint * 0.12);
	ALPHA = alpha;
}
