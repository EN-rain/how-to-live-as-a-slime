extends SceneTree
## Verifies the chisel crystal generator emits real geometry for the warren cluster path.

const CaveSys := preload("res://terrain/cave_system.gd")


func _initialize() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CaveSys._add_chisel_crystal_to_st(
		st, Vector3.ZERO, Vector3.UP,
		0.15, 0.15, 0.11,
		0.6, 0.9, 0.4,
		1.0, 1.0,
		Color(0.12, 0.62, 0.95), true, false, 0.35, 1.0, false
	)
	CaveSys._add_chisel_crystal_to_st(
		st, Vector3(0.3, 0.0, 0.1), Vector3(0.4, 0.9, 0.2),
		0.08, 0.08, 0.06,
		0.3, 0.45, -0.7,
		0.9, 1.1,
		Color(0.48, 0.32, 0.96), true, true, 0.35, 1.0, false
	)
	st.generate_tangents()
	var mesh := st.commit()
	if mesh == null:
		print("FAIL: mesh null")
		quit(1)
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	print("SURFACES=", mesh.get_surface_count(), " VERTS=", verts.size(), " COLS=", cols.size(), " UV2=", uv2s.size())
	print("BOUNDS=", mesh.get_aabb())
	print("COL0=", cols[0] if cols.size() > 0 else Color.BLACK, " UV2_0=", uv2s[0] if uv2s.size() > 0 else Vector2.ZERO)
	# Shader material smoke check
	var mat := ShaderMaterial.new()
	mat.shader = load("res://terrain/cave_crystal.gdshader")
	mat.set_shader_parameter(&"striation_normal", CaveSys._get_crystal_striation_normal_tex())
	mat.set_shader_parameter(&"interior_veil_tex", CaveSys._get_crystal_interior_tex())
	print("TEX_STRIA=", mat.get_shader_parameter(&"striation_normal"))
	print("TEX_VEIL=", mat.get_shader_parameter(&"interior_veil_tex"))
	print("TEST_DONE")
	quit(0)
