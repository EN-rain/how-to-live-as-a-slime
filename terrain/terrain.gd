@tool
class_name TerrainScene
extends Node3D
## Self-contained 3D Terrain + Grass scene.
## Generates a sculpted 3D terrain mesh with terrain/grass textured material
## and populates a 3D MultiMesh grass layer across the terrain surface.

@export_group("Terrain")
@export var terrain_size: float = 160.0:
	set(v):
		terrain_size = maxf(v, 16.0)
		_rebuild_if_ready()
@export var terrain_subdivisions: int = 96:
	set(v):
		terrain_subdivisions = clampi(v, 16, 256)
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
@export var grass_count: int = 5000:
	set(v):
		grass_count = clampi(v, 0, 25000)
		_rebuild_if_ready()
@export var grass_spawn_radius: float = 72.0:
	set(v):
		grass_spawn_radius = maxf(v, 5.0)
		_rebuild_if_ready()
@export var min_grass_normal_y: float = 0.80:
	set(v):
		min_grass_normal_y = clampf(v, 0.0, 1.0)
		_rebuild_if_ready()

var _noise: FastNoiseLite


func _ready() -> void:
	rebuild()


func _rebuild_if_ready() -> void:
	if is_inside_tree():
		rebuild()


func rebuild() -> void:
	_setup_noise()
	var terrain_node := get_node_or_null("Terrain") as MeshInstance3D
	var grass_node := get_node_or_null("Grass") as MultiMeshInstance3D
	if terrain_node != null:
		_build_terrain_mesh(terrain_node)
	if grass_node != null:
		_build_grass_multimesh(grass_node)


func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.018
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.05
	_noise.fractal_gain = 0.48


func sample_height(x: float, z: float) -> float:
	if _noise == null:
		_setup_noise()
	var dist := Vector2(x, z).length()
	# Smooth flat clearing in the center transitioning into rolling hills
	var center_blend := smoothstep(flat_center_radius * 0.45, flat_center_radius * 1.45, dist)
	var n1 := _noise.get_noise_2d(x, z)
	var n2 := _noise.get_noise_2d(x * 2.4 + 120.0, z * 2.4 - 85.0) * 0.35
	var raw_h := (n1 + n2) * height_scale
	# Slight bowl rise near the outer perimeter for nice horizon framing
	var rim := smoothstep(terrain_size * 0.25, terrain_size * 0.48, dist) * (height_scale * 0.55)
	return (raw_h + rim) * center_blend


func sample_normal(x: float, z: float) -> Vector3:
	var eps := 0.35
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
			var y := sample_height(x, z)
			verts[idx] = Vector3(x, y, z)
			normals[idx] = sample_normal(x, z)
			uvs[idx] = Vector2(u, v)
			idx += 1

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

	var col_shape_node := terrain_node.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	if col_shape_node != null:
		col_shape_node.shape = arr_mesh.create_trimesh_shape()


func _make_grass_tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# 3 crossed blades per tuft so each instance has 3D volume from all viewing angles
	var blade_count := 3
	var segs := 3
	var base_half_w := 0.09
	var blade_h := 0.72

	for b in blade_count:
		var ang := float(b) * (PI / float(blade_count)) + (0.18 if b == 1 else 0.0)
		var rot := Basis(Vector3.UP, ang)
		var lean := 0.14 * (1.0 if (b % 2 == 0) else -1.0)
		var base_vert := verts.size()

		for s in range(segs + 1):
			var t := float(s) / float(segs)
			var y := t * blade_h
			var z_curve := t * t * lean
			# Taper width smoothly to a pointed tip at the top
			var w := base_half_w * (1.0 - t * 0.88)
			var n_local := rot * Vector3(0.0, 0.35, 1.0).normalized()

			var p_left := rot * Vector3(-w, y, z_curve)
			var p_right := rot * Vector3(w, y, z_curve)

			verts.append(p_left)
			verts.append(p_right)
			normals.append(n_local)
			normals.append(n_local)
			uvs.append(Vector2(0.0, 1.0 - t))
			uvs.append(Vector2(1.0, 1.0 - t))

		for s in segs:
			var r0 := base_vert + s * 2
			var r1 := r0 + 2
			indices.append(r0)
			indices.append(r0 + 1)
			indices.append(r1)
			indices.append(r0 + 1)
			indices.append(r1 + 1)
			indices.append(r1)

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
	var mm := grass_node.multimesh
	if mm == null:
		mm = MultiMesh.new()
		grass_node.multimesh = mm

	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _make_grass_tuft_mesh()
	mm.instance_count = grass_count

	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 77

	var placed := 0
	var attempts := 0
	var max_attempts := grass_count * 6

	while placed < grass_count and attempts < max_attempts:
		attempts += 1
		var r := sqrt(rng.randf()) * grass_spawn_radius
		var theta := rng.randf() * TAU
		var x := cos(theta) * r
		var z := sin(theta) * r

		var n := sample_normal(x, z)
		if n.y < min_grass_normal_y:
			continue

		# Clumping noise modulation so grass forms natural meadow patches
		var clump := _noise.get_noise_2d(x * 1.6 - 45.0, z * 1.6 + 60.0)
		if clump < -0.32 and rng.randf() < 0.75:
			continue

		var y := sample_height(x, z)
		var yaw := rng.randf() * TAU
		var scale_xz := rng.randf_range(0.75, 1.45)
		var scale_y := rng.randf_range(0.65, 1.55) * lerpf(0.85, 1.25, clampf(clump + 0.5, 0.0, 1.0))

		var up := n
		var forward := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := up.cross(forward).normalized()
		forward = right.cross(up).normalized()

		var basis := Basis(right * scale_xz, up * scale_y, forward * scale_xz)
		var xform := Transform3D(basis, Vector3(x, y - 0.02, z))
		mm.set_instance_transform(placed, xform)
		placed += 1

	mm.visible_instance_count = placed
