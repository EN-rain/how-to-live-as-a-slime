extends SceneTree

func _initialize() -> void:
	var rings := 40
	var segments := 80
	var r_in := 2400.0
	var r_out := 12000.0

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var row_count := segments + 1
	verts.resize((rings + 1) * row_count)
	uvs.resize((rings + 1) * row_count)

	var idx := 0
	for ir in range(rings + 1):
		var t := float(ir) / float(rings)
		# Quadratic spacing so more detail near coast, spreading out to horizon
		var r := lerpf(r_in, r_out, t * t)
		for iseg in range(row_count):
			var theta := (float(iseg) / float(segments)) * TAU
			var x := cos(theta) * r
			var z := sin(theta) * r
			verts[idx] = Vector3(x, 0.0, z)
			uvs[idx] = Vector2(x * 0.01, z * 0.01)
			idx += 1

	for ir in range(rings):
		var r0 := ir * row_count
		var r1 := (ir + 1) * row_count
		for iseg in range(segments):
			var i00 := r0 + iseg
			var i10 := r0 + iseg + 1
			var i01 := r1 + iseg
			var i11 := r1 + iseg + 1

			indices.append(i00)
			indices.append(i10)
			indices.append(i01)

			indices.append(i10)
			indices.append(i11)
			indices.append(i01)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	print("Built annular ocean mesh: verts=", verts.size(), " indices=", indices.size())
	print("Center (r < 2400m) is 100% HOLLOW! No water below continent.")
	quit(0)

