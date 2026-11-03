shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

// Inverted-hull outline. Attached to a toon material's `next_pass` so it rides
// along with the same mesh and scales naturally with the node.
uniform float outline_width = 0.025;
uniform vec4 outline_color : source_color = vec4(0.09, 0.07, 0.12, 1.0);

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
