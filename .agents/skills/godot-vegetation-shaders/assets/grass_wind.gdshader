// Grass / foliage wind sway (Godot 4.x spatial). Checked against Godot 4.7.2.stable.
//
// Problem: moving every vertex of a grass tuft by the same amount makes the whole tuft SLIDE over the ground.
// Fix: weight the motion per vertex: root planted (weight 0), tip bends most (weight 1). The weight comes from
// the mesh's VERTEX COLOUR (dark root -> bright tip); many asset packs already ship it. If yours does not,
// paint it with scripts/blender_grass_vertex_colors.py, or set weight_source = 2 to use vertex height.
// A scrolling noise texture varies the strength across the field so gusts travel through the grass.
//
// Works on MeshInstance3D and MultiMeshInstance3D (MODEL_MATRIX includes the instance transform).
shader_type spatial;
// world_vertex_coords: VERTEX is already in world space -> no per-vertex matrix inverse.
render_mode cull_disabled, world_vertex_coords;

group_uniforms wind;
uniform vec2 wind_direction = vec2(1.0, 0.3);
uniform float wind_strength = 0.12;          // max tip displacement, world units
uniform float sway_speed = 1.6;              // base oscillation, rad/s
uniform sampler2D wind_noise : hint_default_white, repeat_enable, filter_linear; // seamless noise
uniform float noise_scale = 0.08;            // world units -> noise UV
uniform float gust_speed = 0.05;             // noise scroll speed, UV/s
// Where the per-vertex weight comes from:
//   0 = vertex colour BRIGHTNESS (max of R, G, B): works for grey AND tinted gradients (dark green -> light green)
//   1 = vertex colour red channel only (packs that store the mask in R)
//   2 = local height / blade_height (no vertex colours at all)
uniform int weight_source : hint_range(0, 2) = 0;
// Remap the raw value so the root reads exactly 0 and the tip exactly 1. Tinted gradients rarely span 0..1
// (e.g. root 0.2, tip 0.8): without the remap the root creeps and the tip under-bends.
uniform vec2 weight_range = vec2(0.0, 1.0);
uniform float blade_height = 0.5;
uniform float bend_curve = 2.0;              // >1: base stays stiffer, motion concentrated near the tip

group_uniforms look;
uniform vec3 root_color : source_color = vec3(0.10, 0.22, 0.06);
uniform vec3 tip_color : source_color = vec3(0.45, 0.62, 0.22);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;

varying float v_weight;

void vertex() {
	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	float local_height = VERTEX.y - instance_origin.y;
	float raw = weight_source == 0 ? max(COLOR.r, max(COLOR.g, COLOR.b))
		: weight_source == 1 ? COLOR.r
		: local_height / blade_height;
	float w = clamp((raw - weight_range.x) / max(weight_range.y - weight_range.x, 1e-4), 0.0, 1.0);
	v_weight = w;
	vec2 dir = normalize(wind_direction);
	float gust = texture(wind_noise, instance_origin.xz * noise_scale + TIME * gust_speed * dir).r;
	// Per-tuft phase so neighbours do not move in lockstep.
	float phase = dot(instance_origin.xz, vec2(1.7, 2.3));
	float sway = sin(TIME * sway_speed + phase) * 0.35 + gust;
	vec2 offset = dir * sway * wind_strength * pow(w, bend_curve);
	VERTEX.xz += offset;
	// Keep blade length roughly constant: lower the tip a little as it bends.
	VERTEX.y -= length(offset) * 0.5 * w;
}

void fragment() {
	ALBEDO = mix(root_color, tip_color, v_weight);
	ROUGHNESS = roughness;
	// Grass looks better lit like a surface facing up than by each thin blade's own normal.
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
	BACKLIGHT = tip_color * 0.3 * v_weight;
}
