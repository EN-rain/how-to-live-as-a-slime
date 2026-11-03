// Finishing touches: subtle vignette + film grain, as a full-screen post effect. Godot 4.x (all renderers).
// Godot's Environment has no built-in vignette or grain (checked: Godot 4.7.2 class reference).
// Use: CanvasLayer (layer above the 3D view, below the UI) > ColorRect (anchors: Full Rect,
// mouse_filter = Ignore) with a ShaderMaterial using this shader. scripts/lights_camera_post.gd does it.
// Keep it SMALL: it should glue the image together, not be noticed.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.15;  // darkening at the corners
uniform float vignette_radius : hint_range(0.1, 1.5) = 0.75;    // where darkening starts (0 = centre)
uniform float vignette_softness : hint_range(0.01, 1.0) = 0.6;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.03;
uniform float grain_speed = 24.0;                                // grain pattern changes per second

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	// Aspect-corrected distance from the centre, so the vignette is round on wide screens.
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 d = (SCREEN_UV - 0.5) * vec2(res.x / res.y, 1.0);
	float v = smoothstep(vignette_radius, vignette_radius - vignette_softness, length(d) * 1.4);
	col *= mix(1.0 - vignette_strength, 1.0, v);
	// Luminance-weighted grain: less visible in deep shadows and bright highlights.
	float n = hash(FRAGCOORD.xy + floor(TIME * grain_speed) * 17.0) - 0.5;
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col += n * grain_amount * (1.0 - abs(l * 2.0 - 1.0) * 0.5);
	COLOR = vec4(col, 1.0);
}
