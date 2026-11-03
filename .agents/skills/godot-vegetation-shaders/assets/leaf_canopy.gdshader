// Leaf-card canopy shader (Godot 4.x spatial). Checked against Godot 4.7.2.stable.
//
// Problem: a canopy made of flat "leaf cards" lights each card by its own flat normal, so the tree reads as
// separate patches of brightness instead of one volume.
// Fix: tell the lighting that every leaf points AWAY FROM THE CANOPY CENTRE (a sphere/ellipsoid normal).
// The geometry does not change; only the normal used for lighting does.
//
// Use: on the leaf mesh surface (alpha-cut texture). Set canopy_center to the canopy middle in the MESH's
// local space (e.g. the centre of the leaves' AABB). For several canopy lobes, use one material per lobe or
// bake the normals in Blender instead (scripts/blender_leaf_card_normals.py).
shader_type spatial;
// alpha_to_coverage: with MSAA on, the cut-out leaf edges get anti-aliased instead of shimmering when the camera
// moves (no effect without MSAA).
render_mode cull_disabled, depth_prepass_alpha, alpha_to_coverage;

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 leaf_tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
// Canopy centre in the mesh's local space, and the canopy's half-size per axis (flattened canopies: y smaller).
uniform vec3 canopy_center = vec3(0.0, 2.0, 0.0);
uniform vec3 canopy_radius = vec3(1.0, 1.0, 1.0);
// 1.0 = fully spherical normals; 0.7-0.9 keeps a little of the per-card variation (looks less "plastic").
uniform float normal_blend : hint_range(0.0, 1.0) = 0.85;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// 0 = no specular AND no sky reflection. Leaves are matte; the default 0.5 gives a glassy sheen of sky
// reflection over the canopy (specular_disabled render mode would only remove the direct-light lobe).
uniform float specular : hint_range(0.0, 1.0) = 0.0;
// Alpha-to-coverage: alpha values between this and alpha_cut get MSAA-smoothed edges.
uniform float alpha_aa_edge : hint_range(0.0, 1.0) = 0.3;
// Light passing through leaves when lit from behind (cheap translucency).
uniform vec3 backlight_color : source_color = vec3(0.25, 0.3, 0.1);

varying vec3 canopy_normal_view;

void vertex() {
	vec3 outward = normalize((VERTEX - canopy_center) / canopy_radius);
	vec3 n = normalize(mix(NORMAL, outward, normal_blend));
	// Pass it as a varying and write NORMAL in fragment(): with cull_disabled, Godot flips the normal of
	// back faces, which would point half the leaves INTO the canopy.
	canopy_normal_view = normalize((MODELVIEW_MATRIX * vec4(n, 0.0)).xyz);
}

void fragment() {
	vec4 tex = texture(leaf_texture, UV) * leaf_tint;
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = alpha_aa_edge;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_texture, 0));
	NORMAL = canopy_normal_view;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	BACKLIGHT = backlight_color;
}
