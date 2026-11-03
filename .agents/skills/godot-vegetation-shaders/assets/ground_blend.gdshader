// Ground blend shader (Godot 4.x spatial). Checked against Godot 4.7.2.stable.
//
// Problem: one flat green under the grass makes vegetation and props look pasted onto the world.
// Fix: mix several greens (large-scale noise) + worn dirt where people walk + darker grass in shade,
// with a MASK deciding where each appears:
//   mask.r = worn dirt (paths, doorways, around wells/stalls)
//   mask.g = shade under trees (darker, cooler, less saturated grass)
// The mask is sampled in WORLD XZ over `mask_world_rect`, so it lines up with the scene regardless of mesh UVs.
// Build it with scripts/ground_mask.gd (from path points and tree positions) or paint it in any image editor.
shader_type spatial;

uniform sampler2D ground_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 mask_world_rect = vec4(-30.0, -30.0, 60.0, 60.0); // x, z, width, depth (world units)

uniform vec3 grass_a : source_color = vec3(0.24, 0.42, 0.14);
uniform vec3 grass_b : source_color = vec3(0.36, 0.48, 0.17);   // drier / yellower green
uniform vec3 shade_grass : source_color = vec3(0.13, 0.25, 0.10);
uniform vec3 dirt : source_color = vec3(0.40, 0.31, 0.21);
uniform sampler2D variation_noise : hint_default_white, repeat_enable, filter_linear_mipmap; // seamless noise
uniform float variation_scale = 0.05;  // world units -> noise UV (large patches)
uniform float detail_scale = 0.6;      // small-scale breakup of the dirt edge
uniform float dirt_edge_softness : hint_range(0.01, 0.5) = 0.15;
// Optional textures (leave empty to use the flat colours above, multiplied by the noise).
uniform sampler2D grass_texture : source_color, hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_texture : source_color, hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float texture_scale = 0.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 muv = (world_pos.xz - mask_world_rect.xy) / mask_world_rect.zw;
	vec4 mask = texture(ground_mask, muv);
	float big = texture(variation_noise, world_pos.xz * variation_scale).r;
	float detail = texture(variation_noise, world_pos.xz * detail_scale).r;

	vec2 tuv = world_pos.xz * texture_scale;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.35, 0.65, big)) * texture(grass_texture, tuv).rgb;
	grass = mix(grass, shade_grass * texture(grass_texture, tuv).rgb, mask.g);
	// Noise-broken threshold: worn ground has ragged edges, not a clean gradient.
	float d = smoothstep(0.5 - dirt_edge_softness, 0.5 + dirt_edge_softness, mask.r + (detail - 0.5) * 0.5);
	vec3 col = mix(grass, dirt * texture(dirt_texture, tuv).rgb * mix(0.85, 1.1, detail), d);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 1.0, d);
}
