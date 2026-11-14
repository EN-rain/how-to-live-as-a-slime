extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sc := load("res://terrain/terrain.tscn") as PackedScene
	var terrain := sc.instantiate() as TerrainScene
	terrain.terrain_subdivisions = 192
	terrain.enable_cave = true
	root.add_child(terrain)
	await process_frame
	await process_frame

	var t_node := terrain.get_node("Terrain") as MeshInstance3D
	var mesh := t_node.mesh as ArrayMesh
	var mdt := MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)

	print("Total terrain mesh vertices: ", mdt.get_vertex_count())
	print("Total terrain mesh faces: ", mdt.get_face_count())

	# Inspect faces near the entrance mouth
	# CaveLayout.ORIGIN is (-24, 27.2, -52)
	var mouth_faces := 0
	var hanging_faces := []
	for fi in mdt.get_face_count():
		var a := mdt.get_vertex(mdt.get_face_vertex(fi, 0))
		var b := mdt.get_vertex(mdt.get_face_vertex(fi, 1))
		var c := mdt.get_vertex(mdt.get_face_vertex(fi, 2))
		var center := (a + b + c) / 3.0
		var cl := CaveLayout.to_local(center)
		if absf(cl.x) < 20.0 and cl.z > -15.0 and cl.z < 20.0:
			mouth_faces += 1
			var patch_t := CaveSDF.eval_mouth_patch_t(cl.x, cl.z)
			var dy := maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y))
			if dy > 4.0:
				hanging_faces.append({
					"cl": cl,
					"patch_t": patch_t,
					"dy": dy,
					"min_y": minf(a.y, minf(b.y, c.y)),
					"max_y": maxf(a.y, maxf(b.y, c.y)),
					"a": a, "b": b, "c": c
				})

	print("Faces near entrance (|u|<20, s in [-15, 20]): ", mouth_faces)
	print("Steep/stretched faces (dy > 4m) across the mouth: ", hanging_faces.size())
	for hf in hanging_faces.slice(0, 15):
		print("  cl=(%5.1f, %5.1f) | patch_t=%5.2f | y=[%5.1f .. %5.1f] (dy=%4.1f)" % [
			hf.cl.x, hf.cl.z, hf.patch_t, hf.min_y, hf.max_y, hf.dy
		])

	terrain.free()
	quit(0)
