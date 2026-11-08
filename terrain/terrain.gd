@tool
class_name TerrainScene
extends Node3D
## Self-contained, ultra-lightweight 3D Terrain + Static Stylized Grass scene.

@export_group("Terrain")
@export var terrain_size: float = 160.0:
	set(v):
		terrain_size = maxf(v, 16.0)
		_rebuild_if_ready()
@export var terrain_subdivisions: int = 48:
	set(v):
		terrain_subdivisions = clampi(v, 16, 96)
		_rebuild_if_ready()
@export var height_scale: float = 4.2:
	set(v):
		height_scale = maxf(v, 0.0)
		_rebuild_if_ready()
@export var flat_center_radius: float = 18.0:
	set(v):
		flat_center_radius = maxf(v, 0.0)
		_rebuild_if_ready()
@export var terrain_seed: int = 1337:
	set(v):
		terrain_seed = v
		_rebuild_if_ready()

@export_group("Grass")
@export var grass_count: int = 900:
	set(v):
		grass_count = clampi(v, 0, 3000)
		_rebuild_if_ready()
@export var grass_spawn_radius: float = 52.0:
	set(v):
		grass_spawn_radius = maxf(v, 5.0)
		_rebuild_if_ready()
@export var min_grass_normal_y: float = 0.82:
	set(v):
		min_grass_normal_y = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()

var _noise: FastNoiseLite
var _built_once := false


func _ready() -> void:
	_built_once = true
	rebuild()


func _process(_delta: float) -> void:
	if not _built_once:
		_built_once = true
		rebuild()
	set_process(false)


func _rebuild_if_ready() -> void:
	if is_inside_tree():
		rebuild()


func rebuild() -> void:
	_setup_noise()
	var terrain_node := get_node_or_null("Terrain") as MeshInstance3D
	var grass_node := get_node_or_null("Grass") as MultiMeshInstance3D
	if terrain_node != null:
		terrain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t_mat := terrain_node.material_override as ShaderMaterial
		if t_mat != null and t_mat.shader != null and FileAccess.file_exists("res://terrain/terrain.gdshader"):
			var t_code := FileAccess.get_file_as_string("res://terrain/terrain.gdshader")
			if not t_code.is_empty() and t_mat.shader.code != t_code:
				t_mat.shader.code = t_code
		_build_terrain_mesh(terrain_node)
	if grass_node != null:
		grass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var g_mat := grass_node.material_override as ShaderMaterial
		if g_mat != null and g_mat.shader != null and FileAccess.file_exists("res://terrain/grass.gdshader"):
			var g_code := FileAccess.get_file_as_string("res://terrain/grass.gdshader")
			if not g_code.is_empty() and g_mat.shader.code != g_code:
				g_mat.shader.code = g_code
		_build_grass_multimesh(grass_node)


func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.018
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 2
	_noise.fractal_lacunarity = 2.05
	_noise.fractal_gain = 0.48


func sample_height(x: float, z: float) -> float:
	if _noise == null:
		_setup_noise()
	var dist := Vector2(x, z).length()
	var center_blend := smoothstep(flat_center_radius * 0.45, flat_center_radius * 1.45, dist)
	var raw_h := _noise.get_noise_2d(x, z) * height_scale * 1.25
	var rim := smoothstep(terrain_size * 0.25, terrain_size * 0.48, dist) * (height_scale * 0.55)
	return (raw_h + rim) * center_blend


func sample_normal(x: float, z: float) -> Vector3:
	var eps := 0.75
	var hL := sample_height(x - eps, z)
	var hR := sample_height(x + eps, z)
	var hD := sample_height(x, z - eps)
	var hU := sample_height(x, z + eps)
	return Vector3(hL - hR, 2.0 * eps, hD - hU).normalized()


func _build_terrain_mesh(terrain_node: MeshInstance3D) -> void:
	var n := terrain_subdivisions
	var half := terrain_size * 0.5
	var step := terrain_size / float(n)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var row_count := n + 1
	verts.resize(row_count * row_count)
	normals.resize(row_count * row_count)
	uvs.resize(row_count * row_count)

	var idx := 0
	for iz in row_count:
		var z := -half + float(iz) * step
		var v := float(iz) / float(n)
		for ix in row_count:
			var x := -half + float(ix) * step
			var u := float(ix) / float(n)
			verts[idx] = Vector3(x, sample_height(x, z), z)
			uvs[idx] = Vector2(u, v)
			idx += 1

	# Compute vertex normals directly from the height grid (avoids 4 extra noise calls per vertex)
	var inv_2step := 2.0 * step
	for iz in row_count:
		var z0 := maxi(iz - 1, 0) * row_count
		var z1 := mini(iz + 1, n) * row_count
		var zr := iz * row_count
		for ix in row_count:
			var x0 := maxi(ix - 1, 0)
			var x1 := mini(ix + 1, n)
			var hL := verts[zr + x0].y
			var hR := verts[zr + x1].y
			var hD := verts[z0 + ix].y
			var hU := verts[z1 + ix].y
			normals[zr + ix] = Vector3(hL - hR, inv_2step, hD - hU).normalized()

	indices.resize(n * n * 6)
	var ii := 0
	for iz in n:
		for ix in n:
			var i00 := iz * row_count + ix
			var i10 := i00 + 1
			var i01 := (iz + 1) * row_count + ix
			var i11 := i01 + 1
			indices[ii] = i00
			indices[ii + 1] = i10
			indices[ii + 2] = i01
			indices[ii + 3] = i10
			indices[ii + 4] = i11
			indices[ii + 5] = i01
			ii += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_node.mesh = arr_mesh
	terrain_node.custom_aabb = AABB(Vector3(-half, -height_scale * 2.0, -half), Vector3(terrain_size, height_scale * 4.0, terrain_size))

	var col_shape_node := terrain_node.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	if col_shape_node != null:
		col_shape_node.shape = _build_low_mem_collision_shape(verts, row_count, n)


func _build_low_mem_collision_shape(verts: PackedVector3Array, row_count: int, n: int) -> ConcavePolygonShape3D:
	var stride := 4 if (n % 4 == 0 and n >= 32) else 2
	var cn := n / stride
	var faces := PackedVector3Array()
	faces.resize(cn * cn * 6)
	var fi := 0
	for iz in range(0, n, stride):
		for ix in range(0, n, stride):
			var i00 := iz * row_count + ix
			var i10 := i00 + stride
			var i01 := (iz + stride) * row_count + ix
			var i11 := i01 + stride
			faces[fi] = verts[i00]
			faces[fi + 1] = verts[i10]
			faces[fi + 2] = verts[i01]
			faces[fi + 3] = verts[i10]
			faces[fi + 4] = verts[i11]
			faces[fi + 5] = verts[i01]
			fi += 6
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


func _make_grass_tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# 3 single-triangle blades per tuft = 9 vertices, 3 triangles per tuft
	var blade_count := 3
	var base_half_w := 0.115
	var heights := [0.64, 0.52, 0.66]
	var leans := [0.18, 0.22, 0.16]
	var offsets := [
		Vector3(0.0, 0.0, 0.02),
		Vector3(0.05, 0.0, -0.03),
		Vector3(-0.05, 0.0, -0.025),
	]
	var angles := [0.2, 2.3, 4.4]

	for b in blade_count:
		var rot := Basis(Vector3.UP, angles[b])
		var offset: Vector3 = offsets[b]
		var h: float = heights[b]
		var lean: float = leans[b]
		var base_vert := verts.size()
		var up_norm := Vector3.UP

		verts.append(offset + rot * Vector3(-base_half_w, 0.0, 0.0))
		verts.append(offset + rot * Vector3(base_half_w, 0.0, 0.0))
		verts.append(offset + rot * Vector3(0.0, h, lean))

		normals.append(up_norm)
		normals.append(up_norm)
		normals.append(up_norm)

		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(0.5, 1.0))

		indices.append(base_vert + 0)
		indices.append(base_vert + 1)
		indices.append(base_vert + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_grass_multimesh(grass_node: MultiMeshInstance3D) -> void:
	grass_node.visibility_range_end = 55.0
	grass_node.visibility_range_end_margin = 8.0
	grass_node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _make_grass_tuft_mesh()

	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 77

	var xforms: Array[Transform3D] = []
	var attempts := 0
	var max_attempts := grass_count * 3

	while xforms.size() < grass_count and attempts < max_attempts:
		attempts += 1
		var r := sqrt(rng.randf()) * grass_spawn_radius
		var theta := rng.randf() * TAU
		var x := cos(theta) * r
		var z := sin(theta) * r

		var clump := _noise.get_noise_2d(x * 1.6 - 45.0, z * 1.6 + 60.0)
		if clump < -0.20 and rng.randf() < 0.80:
			continue

		var n := sample_normal(x, z)
		if n.y < min_grass_normal_y:
			continue

		var y := sample_height(x, z)
		var yaw := rng.randf() * TAU
		var scale_xz := rng.randf_range(0.85, 1.30)
		var scale_y := rng.randf_range(0.75, 1.35) * lerpf(0.85, 1.20, clampf(clump + 0.5, 0.0, 1.0))

		var up := n
		var forward := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := up.cross(forward).normalized()
		forward = right.cross(up).normalized()

		var basis := Basis(right * scale_xz, up * scale_y, forward * scale_xz)
		xforms.append(Transform3D(basis, Vector3(x, y - 0.02, z)))

	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

	grass_node.multimesh = mm
	grass_node.custom_aabb = AABB(Vector3(-grass_spawn_radius, -height_scale * 2.0, -grass_spawn_radius), Vector3(grass_spawn_radius * 2.0, height_scale * 4.0 + 2.0, grass_spawn_radius * 2.0))
