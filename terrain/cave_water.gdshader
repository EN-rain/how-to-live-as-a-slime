shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform bool is_waterfall = false;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.58, 0.62);
uniform vec3 deep_color : source_color = vec3(0.03, 0.16, 0.28);
uniform vec3 foam_color : source_color = vec3(0.84, 0.95, 1.0);
uniform vec3 waterfall_impact_world = vec3(0.0);
uniform float flow_speed : hint_range(0.0, 4.0, 0.05) = 0.75;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_world_pos;
varying vec2 v_uv;
varying vec4 v_col;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 41.3);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
	v_col = COLOR;
	if (!is_waterfall) {
		float ripple = sin(v_world_pos.x * 1.3 + TIME * 1.4) * cos(v_world_pos.z * 1.3 - TIME * 1.1) * 0.018;
		VERTEX.y += ripple * clamp(v_col.r, 0.0, 1.0);
	}
}

void fragment() {
	if (is_waterfall) {
		float side_fade = sin(clamp(v_uv.x, 0.0, 1.0) * 3.14159);
		float top_fade = smoothstep(0.02, 0.18, v_uv.y);
		float streak1 = value_noise(vec2(v_uv.x * 8.0, v_uv.y * 5.5 - TIME * 2.8));
		float streak2 = value_noise(vec2(v_uv.x * 14.0 + 3.1, v_uv.y * 9.0 - TIME * 4.2));
		float streaks = smoothstep(0.28, 0.78, streak1 * 0.6 + streak2 * 0.4);
		float bot_mist = smoothstep(0.65, 1.0, v_uv.y);
		vec3 wf_col = mix(shallow_color * 0.85, foam_color, clamp(streaks * 0.65 + bot_mist * 0.55, 0.0, 1.0));
		ALBEDO = wf_col;
		EMISSION = wf_col * (0.10 + 0.14 * streaks + 0.18 * bot_mist) * top_fade;
		ROUGHNESS = 0.25;
		SPECULAR = 0.48;
		ALPHA = clamp(side_fade * top_fade * (0.36 + 0.52 * streaks + 0.20 * bot_mist), 0.0, 0.90);
	} else {
		float depth_raw = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view_pos.xyz /= view_pos.w;
		float linear_depth = -view_pos.z;
		float water_depth = max(linear_depth + VERTEX.z, 0.0);

		float t = TIME * flow_speed;
		float is_stream = clamp(v_col.g, 0.0, 1.0);
		float mesh_feather = smoothstep(0.08, 0.46, clamp(v_col.r, 0.0, 1.0));
		float depth_t = smoothstep(0.0, 2.4, water_depth);

		// Gently flowing ripples (UV.y scrolls downstream for stream, concentric rings from waterfall for pool)
		float stream_drift = is_stream * t * 0.85;
		float n_rip = value_noise(v_world_pos.xz * 1.15 + vec2(t * 0.18, -t * 0.15 - stream_drift));
		float d_wf = length(v_world_pos.xz - waterfall_impact_world.xz);
		float wf_ring = (0.5 + 0.5 * sin(d_wf * 3.8 - TIME * 4.6)) * (1.0 - smoothstep(1.0, 7.6, d_wf)) * (1.0 - is_stream) * smoothstep(0.24, 0.55, v_col.r);

		vec3 stream_shallow = vec3(0.06, 0.30, 0.36);
		vec3 water_col = mix(mix(shallow_color, stream_shallow, is_stream), deep_color, depth_t * (1.0 - 0.35 * is_stream));
		float glint = smoothstep(0.58, 0.85, n_rip) * 0.14 + wf_ring * 0.22;
		float shore_foam = (1.0 - smoothstep(0.05, 0.22, water_depth)) * (0.35 + 0.55 * n_rip) * smoothstep(0.18, 0.50, v_col.r) * 0.28;
		water_col = mix(water_col + vec3(0.10, 0.18, 0.20) * glint, foam_color, clamp(shore_foam * 0.38 + wf_ring * 0.38, 0.0, 0.65));

		float edge_fade = smoothstep(0.05, 0.42, water_depth) * mesh_feather;
		float base_alpha = mix(mix(0.40, 0.82, depth_t), mix(0.22, 0.46, depth_t), is_stream);
		ALBEDO = water_col;
		EMISSION = (vec3(0.012, 0.042, 0.058) * (1.0 - 0.65 * is_stream) + foam_color * (wf_ring * 0.08)) * mesh_feather;
		ROUGHNESS = mix(0.22, 0.42, clamp(wf_ring + shore_foam * 0.4, 0.0, 1.0));
		SPECULAR = 0.36;
		ALPHA = clamp(edge_fade * base_alpha + wf_ring * 0.10 * mesh_feather, 0.0, 0.86);
	}
}

