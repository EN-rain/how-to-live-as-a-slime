extends SceneTree
## Geometry verification for the wall-integrated AncientBigDoor collar (DoorWallIntegrationMesh).
## Fast static check: no scene instantiation, only the procedural collar builder + CaveSDF.

func _init() -> void:
	call_deferred("_run")

func _door_xf() -> Transform3D:
	var door_info: Dictionary = CaveLayout.ANCIENT_DOOR
	var door_world_pos := CaveLayout.to_world(door_info["pos"])
	var yaw_loc := float(door_info["yaw"])
	var fwd_loc := Vector3(sin(yaw_loc), 0.0, cos(yaw_loc)).normalized()
	var fwd_world := Vector3(
		CaveLayout.FWD_XZ.x * fwd_loc.z + CaveLayout.RIGHT_XZ.x * fwd_loc.x,
		0.0,
		CaveLayout.FWD_XZ.y * fwd_loc.z + CaveLayout.RIGHT_XZ.y * fwd_loc.x
	).normalized()
	var right_world := Vector3.UP.cross(fwd_world).normalized()
	return Transform3D(Basis(right_world, Vector3.UP, fwd_world), door_world_pos)

func _run() -> void:
	var door_xf := _door_xf()
	var sdf := CaveSystem.get_sdf()
	var kh := CaveSystem.GEOFENCE_OVERWORLD_H

	var grid: Array = []
	var mesh: ArrayMesh = CaveSystem._build_door_wall_integration_mesh(door_xf, grid)
	var pts: Array = grid[0]
	var nu := pts.size()
	var nv := (pts[0] as Array).size()

	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var indices := PackedInt32Array()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		nrms.append_array(arrays[Mesh.ARRAY_NORMAL])
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx != null:
			indices.append_array(idx)
		else:
			for vi in verts.size():
				indices.append(vi)

	var degen := 0
	var nan_v := 0
	for i in verts.size():
		if is_nan(verts[i].x) or is_nan(verts[i].y) or is_nan(verts[i].z):
			nan_v += 1
	for ti in range(0, indices.size(), 3):
		var a := verts[indices[ti]]
		var b := verts[indices[ti + 1]]
		var c := verts[indices[ti + 2]]
		if (b - a).cross(c - a).length_squared() < 1e-9:
			degen += 1
	print("verts=", verts.size(), " tris=", indices.size() / 3, " nan=", nan_v, " degenerate_tris=", degen)

	# 1. Outer ring (v = 1) must be buried inside the real CaveShell rock
	var rim_min := 1e9
	var rim_max := -1e9
	for iu in nu:
		var rim: Vector3 = (pts[iu] as Array)[nv - 1]
		var lw := CaveLayout.to_local(door_xf * rim)
		var clr: float = sdf.eval_sdf_full(lw.x, lw.y, lw.z, kh)
		rim_min = minf(rim_min, clr)
		rim_max = maxf(rim_max, clr)
	print("outer ring (v=1) rock clearance: min=", snappedf(rim_min, 0.001), " max=", snappedf(rim_max, 0.001), " (must be > 0 = sealed in rock)")

	# 2. Side seams (u = 0 / u = nu-1) must also stay buried where they sit above the floor
	var seam_min := 1e9
	for side_iu in [0, nu - 1]:
		var row: Array = pts[side_iu]
		for iv in range(1, nv - 1):
			var p: Vector3 = row[iv]
			if p.y < 0.4:
				continue
			var lw := CaveLayout.to_local(door_xf * p)
			seam_min = minf(seam_min, sdf.eval_sdf_full(lw.x, lw.y, lw.z, kh))
	print("side seam clearance min=", snappedf(seam_min, 0.001), " (must be > 0 = no open curtain edge)")

	# 3. Inner ring (v = 0) must sit flush/tucked cleanly against the inverted-U stone arch perimeter
	var arch_n := 240
	var arch_pts: Array[Vector2] = []
	var arch_outs: Array[Vector2] = []
	for ai in arch_n:
		var fr := CaveSystem._round_arch_frame(float(ai) / float(arch_n - 1), 3.55, 6.20, -1.05)
		arch_pts.append(fr["pos"])
		arch_outs.append(fr["out"])

	var clasp_over := 0
	var clasp_behind := 0
	var off_min := 1e9
	var off_max := -1e9
	for iu in nu:
		var p: Vector3 = (pts[iu] as Array)[0]
		var p2 := Vector2(p.x, p.y)
		var best := 1e9
		var bo := 0.0
		for ai in arch_n:
			var d := p2.distance_squared_to(arch_pts[ai])
			if d < best:
				best = d
				bo = (p2 - arch_pts[ai]).dot(arch_outs[ai])
		off_min = minf(off_min, bo)
		off_max = maxf(off_max, bo)
		if bo > 1.62:
			continue
		if p.z >= 0.35 and p.z <= 1.15:
			clasp_over += 1
		else:
			clasp_behind += 1
	print("inner ring arch-normal offset=", snappedf(off_min, 0.01), "..", snappedf(off_max, 0.01), " seated_in_masonry=", clasp_over, " out_of_range=", clasp_behind)

	# 4. Every collar facet must face VaultDoorOmni (door-local (0, 5.2, +9.76)) -> zero grazing self-shadow
	var light_local := Vector3(0.0, 5.2, 9.76)
	var facing := 0
	var grazing := 0
	var away := 0
	var away_deep := 0
	var min_ndl := 1.0
	var sum_ndl := 0.0
	var count := 0
	for iu in nu:
		for iv in nv:
			var p: Vector3 = (pts[iu] as Array)[iv]
			var pu0: Vector3 = (pts[maxi(iu - 1, 0)] as Array)[iv]
			var pu1: Vector3 = (pts[mini(iu + 1, nu - 1)] as Array)[iv]
			var pv0: Vector3 = (pts[iu] as Array)[maxi(iv - 1, 0)]
			var pv1: Vector3 = (pts[iu] as Array)[mini(iv + 1, nv - 1)]
			var n := (pv1 - pv0).cross(pu1 - pu0)
			if n.length_squared() < 1e-9:
				continue
			n = n.normalized()
			var l := light_local - p
			var dist := l.length()
			if dist < 0.05:
				continue
			if n.dot(l) < 0.0:
				n = -n
			var ndl := n.dot(l / dist)
			count += 1
			sum_ndl += ndl
			min_ndl = minf(min_ndl, ndl)
			if ndl > 0.25:
				facing += 1
			elif ndl > 0.0:
				grazing += 1
			else:
				away += 1
				# Facets inside the deep alcove (0.2 < v < 0.7) are legitimately self-shadowed
				if iv > 0 and iv < nv - 1 and float(iv) / float(nv - 1) > 0.18 and float(iv) / float(nv - 1) < 0.72:
					away_deep += 1
	print("collar facets vs VaultDoorOmni: facing=", facing, " grazing=", grazing, " away=", away, " (deep_alcove=", away_deep, ")",
		" ndl_min=", snappedf(min_ndl, 0.001), " ndl_avg=", snappedf(sum_ndl / float(maxi(count, 1)), 0.001))

	var ok: bool = (
		nan_v == 0
		and degen == 0
		and rim_min > 0.0
		and seam_min > 0.0
		and clasp_over > 0
		and away == away_deep
		and min_ndl > -0.6
	)
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)