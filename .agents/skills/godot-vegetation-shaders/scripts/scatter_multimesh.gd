extends RefCounted
## Scatters thousands of copies of a mesh (grass tufts, flowers, pebbles) as ONE MultiMeshInstance3D. Godot 4.x.
## One node and one draw call per surface, instead of thousands of MeshInstance3D nodes.
## Checked against Godot 4.7.2.stable (MultiMesh, MultiMeshInstance3D, GeometryInstance3D).
##
## Usage:
##   const Scatter := preload("res://path/to/scatter_multimesh.gd")
##   var mmi := Scatter.scatter(grass_mesh, Rect2(3, 0, 10, 8), 20000, {
##       "material": grass_material,      # e.g. ShaderMaterial with grass_wind.gdshader
##       "visibility_end": 40.0,          # hide beyond this distance (world units); 0 = always drawn
##       "exclude": func(p: Vector2) -> bool: return p.x > 0.5 and p.x < 2.5,  # e.g. keep the road clear
##   })
##   add_child(mmi)
## Options: seed, scale_min, scale_max, y (ground height), material, visibility_end, visibility_margin, exclude.
##
## Performance defaults chosen on purpose: no shadow casting (thousands of thin blades in the shadow maps are
## expensive and barely visible), and a visibility range that fades the whole field out with distance.
## For very large fields, split the area into several chunks (one MultiMeshInstance3D each) so frustum culling
## and visibility ranges work per chunk instead of for the whole field.


static func scatter(mesh: Mesh, area: Rect2, count: int, o := {}) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o.get("seed", 1))
	var smin := float(o.get("scale_min", 0.7))
	var smax := float(o.get("scale_max", 1.3))
	var y := float(o.get("y", 0.0))
	var exclude: Callable = o.get("exclude", Callable())

	var transforms: Array[Transform3D] = []
	var attempts := 0
	while transforms.size() < count and attempts < count * 4:
		attempts += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if exclude.is_valid() and exclude.call(p):
			continue
		var s := rng.randf_range(smin, smax)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s))
		transforms.append(Transform3D(b, Vector3(p.x, y, p.y)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D   # must be set before instance_count
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Scatter_%s" % (mesh.resource_name if mesh.resource_name != "" else "mesh")
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if o.has("material"):
		mmi.material_override = o.material
	var vis_end := float(o.get("visibility_end", 40.0))
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = float(o.get("visibility_margin", vis_end * 0.2))
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mmi
