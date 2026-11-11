shader_type spatial;
render_mode diffuse_lambert_wrap, cull_back;

uniform vec4 foliage_sun_color : source_color = vec4(0.48, 0.84, 0.26, 1.0);
uniform vec4 foliage_mid_color : source_color = vec4(0.34, 0.68, 0.18, 1.0);
uniform vec4 foliage_shade_color : source_color = vec4(0.18, 0.44, 0.12, 1.0);

uniform vec4 bark_color : source_color = vec4(0.38, 0.26, 0.18, 1.0);
uniform vec4 bark_dark_color : source_color = vec4(0.26, 0.17, 0.11, 1.0);

uniform float wind_speed = 1.4;
uniform float wind_strength = 0.07;
uniform float surface_roughness = 0.88;

varying vec3 v_world_pos;
varying float v_is_foliage;
varying float v_height;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_is_foliage = COLOR.r;
	v_height = VERTEX.y;

	// Wind sway: only affects foliage and upper branches
	if (v_is_foliage > 0.5) {
		float wind_phase = TIME * wind_speed + v_world_pos.x * 0.18 + v_world_pos.z * 0.18;
		float sway_h = clamp((v_height - 1.5) / 4.0, 0.0, 1.0);
		float sway = sin(wind_phase) * wind_strength * sway_h;
		VERTEX.x += sway;
		VERTEX.z += cos(wind_phase * 0.85) * (sway * 0.75);
	}
}

void fragment() {
	if (v_is_foliage > 0.5) {
		// Stylized volume lighting: combine vertical canopy gradient with hemispherical normal
		float vert_grad = clamp((v_height - 2.0) / 3.5, 0.0, 1.0);
		float sun_dir = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
		float light_factor = clamp(vert_grad * 0.6 + sun_dir * 0.4, 0.0, 1.0);

		vec3 leaf_col = mix(foliage_shade_color.rgb, foliage_mid_color.rgb, smoothstep(0.0, 0.55, light_factor));
		leaf_col = mix(leaf_col, foliage_sun_color.rgb, smoothstep(0.55, 1.0, light_factor));

		ALBEDO = leaf_col;
		ROUGHNESS = surface_roughness;
		SPECULAR = 0.08;
	} else {
		// Bark with subtle vertical variation
		float bark_grad = clamp(v_height / 3.5, 0.0, 1.0);
		vec3 trunk_col = mix(bark_dark_color.rgb, bark_color.rgb, bark_grad * 0.5 + 0.5);
		ALBEDO = trunk_col;
		ROUGHNESS = 0.95;
		SPECULAR = 0.05;
	}
}

