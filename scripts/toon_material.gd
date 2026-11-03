class_name ToonMaterial
extends RefCounted

## Factory for the game's cel-shaded materials. Every opaque material gets an
## inverted-hull outline as its `next_pass`. Use `flat()` for unlit UI-like bits
## such as eyes.

const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/outline.gdshader")


static func make(
		color: Color,
		outline_width := 0.02,
		outline_color := Color(0.09, 0.07, 0.12),
		with_outline := true
	) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("rim_strength", 0.18)
	if with_outline:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("outline_width", outline_width)
		outline.set_shader_parameter("outline_color", outline_color)
		mat.next_pass = outline
	return mat


static var _cache: Dictionary = {}


## Shared material for a colour/outline pair. Props of the same kind reuse one
## material, which cuts material instances and state changes. Per-instance
## effects (the dissolve) use the shader's `instance uniform`, set on the mesh.
static func shared(color: Color, outline_width: float, with_outline := true) -> ShaderMaterial:
	var key := "%s|%.4f|%s" % [color.to_html(), outline_width, with_outline]
	if _cache.has(key):
		return _cache[key]
	var mat := make(color, outline_width, Color(0.09, 0.07, 0.12), with_outline)
	_cache[key] = mat
	return mat


static func flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
