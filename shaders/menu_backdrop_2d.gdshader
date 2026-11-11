shader_type canvas_item;
// Clean dark background for Main Menu

void fragment() {
	vec2 uv = UV;
	vec3 top_color = vec3(0.08, 0.10, 0.14);
	vec3 bot_color = vec3(0.04, 0.05, 0.07);
	vec3 col = mix(top_color, bot_color, uv.y);
	COLOR = vec4(col, 1.0);
}
