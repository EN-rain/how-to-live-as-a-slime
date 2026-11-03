class_name Icosphere
extends RefCounted

## Builds an icosphere (20 triangles, evenly subdivided).
##
## The plan (§8) calls for an icosphere on the slime body: a UV sphere pinches
## at the poles, so vertices there cluster and the wobble shader makes the top
## and bottom of the blob crawl. An icosphere distributes vertices evenly, so
## the wobble reads as one soft surface everywhere.

const _PHI := 1.61803398875


static func build(radius := 0.5, subdivisions := 3) -> ArrayMesh:
	var verts: Array[Vector3] = [
		Vector3(-1, _PHI, 0), Vector3(1, _PHI, 0), Vector3(-1, -_PHI, 0), Vector3(1, -_PHI, 0),
		Vector3(0, -1, _PHI), Vector3(0, 1, _PHI), Vector3(0, -1, -_PHI), Vector3(0, 1, -_PHI),
		Vector3(_PHI, 0, -1), Vector3(_PHI, 0, 1), Vector3(-_PHI, 0, -1), Vector3(-_PHI, 0, 1),
	]
	for i in verts.size():
		verts[i] = verts[i].normalized()

	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10),
		Vector3i(0, 10, 11), Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2),
		Vector3i(10, 7, 6), Vector3i(7, 1, 8), Vector3i(3, 9, 4), Vector3i(3, 4, 2),
		Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9), Vector3i(4, 9, 5),
		Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]

	var midpoints: Dictionary = {}
	for _level in subdivisions:
		var next_faces: Array[Vector3i] = []
		for face in faces:
			var a := face.x
			var b := face.y
			var c := face.z
			var ab := _midpoint(a, b, verts, midpoints)
			var bc := _midpoint(b, c, verts, midpoints)
			var ca := _midpoint(c, a, verts, midpoints)
			next_faces.append(Vector3i(a, ab, ca))
			next_faces.append(Vector3i(b, bc, ab))
			next_faces.append(Vector3i(c, ca, bc))
			next_faces.append(Vector3i(ab, bc, ca))
		faces = next_faces

	var points := PackedVector3Array()
	points.resize(verts.size())
	for i in verts.size():
		points[i] = verts[i] * radius

	var indices := PackedInt32Array()
	indices.resize(faces.size() * 3)
	for i in faces.size():
		# Godot treats clockwise winding as front-facing, so emit the triangle
		# with the middle/last vertices swapped. Without this the body renders
		# inside-out and the `cull_front` outline pass covers the whole slime.
		indices[i * 3] = faces[i].x
		indices[i * 3 + 1] = faces[i].z
		indices[i * 3 + 2] = faces[i].y

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	# Smooth normals: on a unit sphere they equal the normalised positions.
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = points
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _midpoint(
		a: int, b: int, verts: Array[Vector3], cache: Dictionary
	) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return cache[key]
