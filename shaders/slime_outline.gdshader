shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

// Rim-only outline for the translucent slime. The regular inverted-hull
// outline works for opaque props, but through a transparent body its dark
// backfaces would fill the whole silhouette. This pass discards everything
// except the thin band at the edge.
uniform float outline_width = 0.03;
uniform vec4 outline_color : source_color = vec4(0.09, 0.07, 0.12, 1.0);
uniform float rim_start : hint_range(0.0, 1.0, 0.01) = 0.55;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	if (1.0 - facing < rim_start) {
		discard;
	}
	ALBEDO = outline_color.rgb;
}
