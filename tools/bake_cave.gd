extends SceneTree
## Offline SDF + Surface-Nets Cave Baker (runs headlessly inside the Docker Cloud Sandbox).
## Generates:
##   - res://terrain/cave/cave_mesh.res        (ArrayMesh with baked AO, SkyVis, Wetness, Curvature in COLOR)
##   - res://terrain/cave/cave_floor_shape.res (ConcavePolygonShape3D for layer-1 walkable floors/ledges)
##   - res://terrain/cave/cave_wall_shape.res  (ConcavePolygonShape3D for layer-4 walls/ceilings/pillars)

const VOXEL := 0.80
const BRICK := 4 # 4x4x4 coarse brick = 3.2 m

const U_MIN := -152.0
const U_MAX := 40.0
const Y_MIN := 4.0
const Y_MAX := 66.0
const S_MIN := -32.0
const S_MAX := 176.0


func _init() -> void:
	print("=== Starting Offline SDF + Surface-Nets Cave Bake ===")
	var t0 := Time.get_ticks_msec()

	DirAccess.make_dir_recursive_absolute("res://terrain/cave")

	# Instantiate TerrainScene solely to sample exact base+karst overworld heights on the 2D (u, s) grid
	var terrain_sc := load("res://terrain/terrain.tscn") as PackedScene
	var terrain := terrain_sc.instantiate()
	terrain.set("enable_cave", true)

	var sdf := CaveSDF.new(1337)

	var nx := int(ceil((U_MAX - U_MIN) / VOXEL))
	var ny := int(ceil((Y_MAX - Y_MIN) / VOXEL))
	var nz := int(ceil((S_MAX - S_MIN) / VOXEL))
	var gx := nx + 1
	var gy := ny + 1
	var gz := nz + 1
	print("Grid dimensions: %d x %d x %d corners (%.2f m voxel)" % [gx, gy, gz, VOXEL])

	# 1. Precompute 2D karst hill heights for every (ix, iz) column
	var karst_2d := PackedFloat32Array()
	karst_2d.resize(gx * gz)
	var patch_2d := PackedFloat32Array()
	patch_2d.resize(gx * gz)
	for iz in gz:
		var s := S_MIN + float(iz) * VOXEL
		for ix in gx:
			var u := U_MIN + float(ix) * VOXEL
			var wp := CaveLayout.to_world(Vector3(u, 0.0, s))
			var kh: float = float(terrain.call("sample_height", wp.x, wp.z))
			karst_2d[iz * gx + ix] = kh
			patch_2d[iz * gx + ix] = CaveSDF.eval_surface_patch_t(u, s)

	terrain.free()

	# 2. Coarse 4x4x4 brick culling (scan column [kh_min, kh_max] per brick so steep cliffs never get skipped!)
	var bx_cnt := int(ceil(float(nx) / float(BRICK)))
	var by_cnt := int(ceil(float(ny) / float(BRICK)))
	var bz_cnt := int(ceil(float(nz) / float(BRICK)))

	# Allocate full SDF corner array initialized to +99.0 (solid rock)
	var total_corners := gx * gy * gz
	var field := PackedFloat32Array()
	field.resize(total_corners)
	field.fill(99.0)

	var computed_corner := PackedByteArray()
	computed_corner.resize(total_corners)

	var active_bricks: Array[Vector3i] = []
	var brick_half_diag := float(BRICK) * VOXEL * 0.87 + 5.5

	for bz in bz_cnt:
		var s_mid := S_MIN + (float(bz * BRICK) + float(BRICK) * 0.5) * VOXEL
		var iz0 := maxi(bz * BRICK - 1, 0)
		var iz1 := mini((bz + 1) * BRICK + 1, nz)
		for bx in bx_cnt:
			var u_mid := U_MIN + (float(bx * BRICK) + float(BRICK) * 0.5) * VOXEL
			var ix0 := maxi(bx * BRICK - 1, 0)
			var ix1 := mini((bx + 1) * BRICK + 1, nx)
			var kh_min := 1e9
			var kh_max := -1e9
			var pt_min := 1e9
			for izc in range(iz0, iz1 + 1):
				var k_row := izc * gx
				for ixc in range(ix0, ix1 + 1):
					var khv := karst_2d[k_row + ixc]
					var ptv := patch_2d[k_row + ixc]
					kh_min = minf(kh_min, khv)
					kh_max = maxf(kh_max, khv)
					pt_min = minf(pt_min, ptv)

			for by in by_cnt:
				var y_lo := Y_MIN + float(by * BRICK) * VOXEL
				var y_hi := Y_MIN + float((by + 1) * BRICK) * VOXEL
				var y_mid := 0.5 * (y_lo + y_hi)

				var dc := sdf.eval_cave_void_smooth(u_mid, y_mid, s_mid)
				var near_cave := absf(dc) <= brick_half_diag
				var near_patch_surface := (pt_min <= 1.0) and (y_hi >= kh_min - 6.0) and (y_lo <= kh_max + 4.5)
				if near_cave or near_patch_surface:
					active_bricks.append(Vector3i(bx, by, bz))

	print("Active surface bricks: %d / %d (%.1f%%)" % [
		active_bricks.size(), bx_cnt * by_cnt * bz_cnt,
		100.0 * float(active_bricks.size()) / float(maxi(bx_cnt * by_cnt * bz_cnt, 1))
	])

	# Evaluate fine SDF corners on active bricks + 1-cell border so neighbor quads never miss corners
	var stride_y := gx
	var stride_z := gx * gy
	for bvec: Vector3i in active_bricks:
		var x0 := maxi(bvec.x * BRICK - 1, 0)
		var x1 := mini((bvec.x + 1) * BRICK + 1, nx)
		var y0 := maxi(bvec.y * BRICK - 1, 0)
		var y1 := mini((bvec.y + 1) * BRICK + 1, ny)
		var z0 := maxi(bvec.z * BRICK - 1, 0)
		var z1 := mini((bvec.z + 1) * BRICK + 1, nz)
		for iz in range(z0, z1 + 1):
			var s := S_MIN + float(iz) * VOXEL
			var z_off := iz * stride_z
			var k_row := iz * gx
			for iy in range(y0, y1 + 1):
				var y := Y_MIN + float(iy) * VOXEL
				var yz_off := z_off + iy * stride_y
				for ix in range(x0, x1 + 1):
					var c_idx := yz_off + ix
					if computed_corner[c_idx] != 0:
						continue
					computed_corner[c_idx] = 1
					var u := U_MIN + float(ix) * VOXEL
					field[c_idx] = sdf.eval_sdf_full(u, y, s, karst_2d[k_row + ix])

	var t_sdf := Time.get_ticks_msec()
	print("Fine SDF evaluated in %.2f s" % [float(t_sdf - t0) / 1000.0])

	# 3. Surface Nets Pass 1: Place 1 welded vertex in every sign-changing cell
	var cell_total := nx * ny * nz
	var cell_vert := PackedInt32Array()
	cell_vert.resize(cell_total)
	cell_vert.fill(-1)

	var local_verts := PackedVector3Array()
	var world_verts := PackedVector3Array()
	var vert_air_dirs := PackedVector3Array()

	# 12 cube edges as pairs of corner bitmasks (bit0=dx, bit1=dy, bit2=dz)
	var edge_a := [0, 2, 4, 6, 0, 1, 4, 5, 0, 1, 2, 3]
	var edge_b := [1, 3, 5, 7, 2, 3, 6, 7, 4, 5, 6, 7]
	var corner_pos: Array[Vector3] = []
	corner_pos.resize(8)
	var corner_val := PackedFloat32Array()
	corner_val.resize(8)

	var c_stride_y := nx
	var c_stride_z := nx * ny

	for bvec: Vector3i in active_bricks:
		var x0 := bvec.x * BRICK
		var x1 := mini(x0 + BRICK, nx)
		var y0 := bvec.y * BRICK
		var y1 := mini(y0 + BRICK, ny)
		var z0 := bvec.z * BRICK
		var z1 := mini(z0 + BRICK, nz)
		for iz in range(z0, z1):
			var s := S_MIN + float(iz) * VOXEL
			for iy in range(y0, y1):
				var y := Y_MIN + float(iy) * VOXEL
				for ix in range(x0, x1):
					var cell_idx := iz * c_stride_z + iy * c_stride_y + ix
					if cell_vert[cell_idx] != -1:
						continue

					# Filter out pure overworld hillside cells outside Entrance Outcrop & Skylight Rim patches
					var pt := patch_2d[iz * gx + ix]
					var u := U_MIN + float(ix) * VOXEL
					if pt > 0.995:
						var dc_cell := sdf.eval_cave_void_smooth(u + VOXEL * 0.5, y + VOXEL * 0.5, s + VOXEL * 0.5)
						if dc_cell > 3.6:
							continue

					var has_neg := false
					var has_pos := false
					for c in 8:
						var dx := c & 1
						var dy := (c >> 1) & 1
						var dz := (c >> 2) & 1
						var fv := field[(iz + dz) * stride_z + (iy + dy) * stride_y + (ix + dx)]
						corner_val[c] = fv
						if fv < 0.0:
							has_neg = true
						else:
							has_pos = true
					if not (has_neg and has_pos):
						continue

					for c in 8:
						corner_pos[c] = Vector3(
							u + float(c & 1) * VOXEL,
							y + float((c >> 1) & 1) * VOXEL,
							s + float((c >> 2) & 1) * VOXEL
						)

					var sum_p := Vector3.ZERO
					var cross_cnt := 0
					for e in 12:
						var ca: int = edge_a[e]
						var cb: int = edge_b[e]
						var va := corner_val[ca]
						var vb := corner_val[cb]
						if (va < 0.0) != (vb < 0.0):
							var t := va / (va - vb)
							sum_p += corner_pos[ca].lerp(corner_pos[cb], clampf(t, 0.0, 1.0))
							cross_cnt += 1

					if cross_cnt == 0:
						continue

					var p_local := sum_p / float(cross_cnt)
					var grad_x := (corner_val[1] + corner_val[3] + corner_val[5] + corner_val[7]) \
							- (corner_val[0] + corner_val[2] + corner_val[4] + corner_val[6])
					var grad_y := (corner_val[2] + corner_val[3] + corner_val[6] + corner_val[7]) \
							- (corner_val[0] + corner_val[1] + corner_val[4] + corner_val[5])
					var grad_z := (corner_val[4] + corner_val[5] + corner_val[6] + corner_val[7]) \
							- (corner_val[0] + corner_val[1] + corner_val[2] + corner_val[3])
					var air_world := _dir_local_to_world(Vector3(-grad_x, -grad_y, -grad_z))
					var air_dir := air_world.normalized() if air_world.length_squared() > 1e-8 else Vector3.UP

					var v_idx := local_verts.size()
					cell_vert[cell_idx] = v_idx
					local_verts.append(p_local)
					world_verts.append(CaveLayout.to_world(p_local))
					vert_air_dirs.append(air_dir)

	var vert_count := world_verts.size()
	print("Welded Surface-Nets vertices: %d" % vert_count)

	# 4. Surface Nets Pass 2: Gather dual quads around sign-changing interior grid edges
	var quad_verts := PackedInt32Array()
	var quad_dirs: Array[Vector3] = []

	for iz in range(1, nz):
		for iy in range(1, ny):
			for ix in range(1, nx):
				var c0 := iz * stride_z + iy * stride_y + ix
				var v0 := field[c0]

				# +X edge: (ix, iy, iz) -> (ix+1, iy, iz), shared by 4 cells in (iy-1..iy, iz-1..iz)
				var vx := field[c0 + 1]
				if (v0 < 0.0) != (vx < 0.0):
					var q0 := cell_vert[(iz - 1) * c_stride_z + (iy - 1) * c_stride_y + ix]
					var q1 := cell_vert[(iz - 1) * c_stride_z + iy * c_stride_y + ix]
					var q2 := cell_vert[iz * c_stride_z + iy * c_stride_y + ix]
					var q3 := cell_vert[iz * c_stride_z + (iy - 1) * c_stride_y + ix]
					if q0 >= 0 and q1 >= 0 and q2 >= 0 and q3 >= 0:
						quad_verts.append(q0); quad_verts.append(q1); quad_verts.append(q2); quad_verts.append(q3)
						quad_dirs.append(_dir_local_to_world(Vector3(-1.0 if v0 < 0.0 else 1.0, 0.0, 0.0)))

				# +Y edge: (ix, iy, iz) -> (ix, iy+1, iz), shared by 4 cells in (ix-1..ix, iz-1..iz)
				var vy := field[c0 + stride_y]
				if (v0 < 0.0) != (vy < 0.0):
					var q0 := cell_vert[(iz - 1) * c_stride_z + iy * c_stride_y + (ix - 1)]
					var q1 := cell_vert[iz * c_stride_z + iy * c_stride_y + (ix - 1)]
					var q2 := cell_vert[iz * c_stride_z + iy * c_stride_y + ix]
					var q3 := cell_vert[(iz - 1) * c_stride_z + iy * c_stride_y + ix]
					if q0 >= 0 and q1 >= 0 and q2 >= 0 and q3 >= 0:
						quad_verts.append(q0); quad_verts.append(q1); quad_verts.append(q2); quad_verts.append(q3)
						quad_dirs.append(Vector3(0.0, -1.0 if v0 < 0.0 else 1.0, 0.0))

				# +Z edge: (ix, iy, iz) -> (ix, iy, iz+1), shared by 4 cells in (ix-1..ix, iy-1..iy)
				var vz := field[c0 + stride_z]
				if (v0 < 0.0) != (vz < 0.0):
					var q0 := cell_vert[iz * c_stride_z + (iy - 1) * c_stride_y + (ix - 1)]
					var q1 := cell_vert[iz * c_stride_z + iy * c_stride_y + (ix - 1)]
					var q2 := cell_vert[iz * c_stride_z + iy * c_stride_y + ix]
					var q3 := cell_vert[iz * c_stride_z + (iy - 1) * c_stride_y + ix]
					if q0 >= 0 and q1 >= 0 and q2 >= 0 and q3 >= 0:
						quad_verts.append(q0); quad_verts.append(q1); quad_verts.append(q2); quad_verts.append(q3)
						quad_dirs.append(_dir_local_to_world(Vector3(0.0, 0.0, -1.0 if v0 < 0.0 else 1.0)))

	var quad_count := quad_dirs.size()

	# 4B. 3-Pass Masked Laplacian Relaxation (eliminates voxel staircase banding on floors while keeping
	#     the calibrated crawlway bore, exterior terrain-overlap apron, and 3D karst wall/ceiling facets crisp)
	var relax_weights := PackedFloat32Array()
	relax_weights.resize(vert_count)
	for i in vert_count:
		var lp := local_verts[i]
		var dc_rw := sdf.dist_to_crawlway(lp.x, lp.y, lp.z)
		var pt_rw := CaveSDF.eval_surface_patch_t(lp.x, lp.z)
		var air_y := vert_air_dirs[i].y
		# Keep floors smooth (0.34) for buttery locomotion, but preserve crisp rock relief on walls & ceilings (0.15)
		var base_rw := lerpf(0.15, 0.34, clampf((air_y - 0.25) / 0.55, 0.0, 1.0))
		relax_weights[i] = base_rw * smoothstep(-0.1, 1.2, dc_rw) * (1.0 - smoothstep(0.78, 0.89, pt_rw))

	var nb_sum := PackedVector3Array()
	nb_sum.resize(vert_count)
	var nb_cnt := PackedInt32Array()
	nb_cnt.resize(vert_count)
	for _rpass in 3:
		nb_sum.fill(Vector3.ZERO)
		nb_cnt.fill(0)
		for qi in quad_count:
			var b := qi * 4
			var q0 := quad_verts[b]
			var q1 := quad_verts[b + 1]
			var q2 := quad_verts[b + 2]
			var q3 := quad_verts[b + 3]
			var p0 := local_verts[q0]
			var p1 := local_verts[q1]
			var p2 := local_verts[q2]
			var p3 := local_verts[q3]
			nb_sum[q0] += p1 + p3; nb_cnt[q0] += 2
			nb_sum[q1] += p0 + p2; nb_cnt[q1] += 2
			nb_sum[q2] += p1 + p3; nb_cnt[q2] += 2
			nb_sum[q3] += p2 + p0; nb_cnt[q3] += 2
		for i in vert_count:
			var cnt := nb_cnt[i]
			var rw := relax_weights[i]
			if cnt > 0 and rw > 0.001:
				local_verts[i] = local_verts[i].lerp(nb_sum[i] / float(cnt), rw)

	for i in vert_count:
		world_verts[i] = CaveLayout.to_world(local_verts[i])

	# 4C. Emit triangles with best-diagonal split and centroid SDF-gradient winding verification
	var indices := PackedInt32Array()
	var adj_sum := PackedVector3Array()
	adj_sum.resize(vert_count)
	var adj_cnt := PackedInt32Array()
	adj_cnt.resize(vert_count)

	for qi in quad_count:
		var b := qi * 4
		_emit_quad(
			quad_verts[b], quad_verts[b + 1], quad_verts[b + 2], quad_verts[b + 3],
			quad_dirs[qi], local_verts, world_verts, vert_air_dirs,
			field, gx, gy, gz, stride_y, stride_z,
			indices, adj_sum, adj_cnt
		)

	var tri_count := indices.size() / 3
	print("Emitted triangles: %d (budget <= 120,000)" % tri_count)

	# 5. Compute smooth area-weighted vertex normals & split physics faces (Floor layer 1 vs Wall layer 4)
	var normals := PackedVector3Array()
	normals.resize(vert_count)
	var floor_faces := PackedVector3Array()
	var wall_faces := PackedVector3Array()

	for t in tri_count:
		var i0 := indices[t * 3]
		var i1 := indices[t * 3 + 1]
		var i2 := indices[t * 3 + 2]
		var p0 := world_verts[i0]
		var p1 := world_verts[i1]
		var p2 := world_verts[i2]
		# Godot front-face normal: (p2 - p0).cross(p1 - p0)
		var fn := (p2 - p0).cross(p1 - p0)
		normals[i0] += fn
		normals[i1] += fn
		normals[i2] += fn

		var fn_len := fn.length()
		var n_unit := fn / fn_len if fn_len > 1e-8 else Vector3.UP
		# Classify physics triangles between CaveFloorBody (Layer 1) and CaveWallBody (Layer 4):
		# - Walkable floors/ramps (n_unit.y >= 0.46, up to ~62 deg slope) belong on Layer 1.
		# - Steep cave walls (n_unit.y < 0.46), pillars, crawlway walls, and ceilings belong on Layer 4
		#   so horizontal sweeps solidly block the slime from climbing up steep walls!
		if n_unit.y >= 0.46:
			floor_faces.append(p0)
			floor_faces.append(p1)
			floor_faces.append(p2)
		else:
			var lp_mid := (local_verts[i0] + local_verts[i1] + local_verts[i2]) * (1.0 / 3.0)
			var pt_mid := CaveSDF.eval_surface_patch_t(lp_mid.x, lp_mid.z)
			var dc_mid := sdf.eval_cave_void_smooth(lp_mid.x, lp_mid.y, lp_mid.z)
			var is_buried_skirt := pt_mid > 0.62 and (dc_mid > 1.8 or lp_mid.z < -4.0)
			if is_buried_skirt:
				continue

			# Convert world normal horizontal direction to local (u, s)
			var ln_u := n_unit.x * CaveLayout.RIGHT_XZ.x + n_unit.z * CaveLayout.RIGHT_XZ.y
			var ln_s := n_unit.x * CaveLayout.FWD_XZ.x + n_unit.z * CaveLayout.FWD_XZ.y
			var ln_h := Vector2(ln_u, ln_s)
			var ln_hlen := ln_h.length()
			var hu := (ln_h.x / ln_hlen) if ln_hlen > 1e-4 else 0.0
			var hs := (ln_h.y / ln_hlen) if ln_hlen > 1e-4 else 0.0

			if n_unit.y < -0.35:
				# Downward-facing surface: if walkable air exists 3.2m above it, it's a ledge-shelf underside -> Layer 1
				var is_ledge_underside := sdf.eval_cave_void_smooth(lp_mid.x, lp_mid.y + 3.2, lp_mid.z) < -0.2
				if is_ledge_underside:
					floor_faces.append(p0)
					floor_faces.append(p1)
					floor_faces.append(p2)
				else:
					wall_faces.append(p0)
					wall_faces.append(p1)
					wall_faces.append(p2)
			else:
				# Near-vertical face:
				# Only put very low ankle fillets (< 0.50m above floor) or step drop-off rims on Layer 1;
				# true walls (where there is solid rock behind and no floor within 0.50m below) stay on Layer 4!
				var d_under_floor := sdf.eval_cave_void_smooth(lp_mid.x + hu * 0.25, lp_mid.y - 0.48, lp_mid.z + hs * 0.25)
				var d_back_step_air := sdf.eval_cave_void_smooth(lp_mid.x - hu * 1.15, lp_mid.y + 1.25, lp_mid.z - hs * 1.15)
				if (n_unit.y >= 0.20 and d_under_floor >= 0.0) or d_back_step_air < -0.15:
					floor_faces.append(p0)
					floor_faces.append(p1)
					floor_faces.append(p2)
				else:
					wall_faces.append(p0)
					wall_faces.append(p1)
					wall_faces.append(p2)

	for i in vert_count:
		var nl := normals[i].length()
		normals[i] = normals[i] / nl if nl > 1e-8 else Vector3.UP

	# 6. Bake per-vertex lighting & geological attributes into COLOR:
	#    R = SDF Ambient Occlusion (0..1)
	#    G = Skylight + Mouth Daylight Visibility (0..1)
	#    B = Hydrological Wetness (0..1)
	#    A = Surface Curvature (0.5 flat, >0.5 convex ridge, <0.5 concave crevice)
	var colors := PackedColorArray()
	colors.resize(vert_count)
	var uvs := PackedVector2Array()
	uvs.resize(vert_count)

	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	var sky_target := Vector3(sky_c.x, 58.0, sky_c.z)
	var mouth_target := Vector3(0.0, 29.5, -6.0)
	var ao_steps := [0.65, 1.45, 2.80, 4.80]
	var pool_c: Vector3 = CaveLayout.POOL["c"]
	var pool_rx: float = float(CaveLayout.POOL["rx"])
	var pool_rz: float = float(CaveLayout.POOL["rz"])

	for i in vert_count:
		var lp := local_verts[i]
		var wp := world_verts[i]
		var wn := normals[i]
		var ln := Vector3(
			wn.x * CaveLayout.RIGHT_XZ.x + wn.z * CaveLayout.RIGHT_XZ.y,
			wn.y,
			wn.x * CaveLayout.FWD_XZ.x + wn.z * CaveLayout.FWD_XZ.y
		).normalized()

		# A. 4-step SDF Ambient Occlusion
		var occ := 0.0
		var w_sum := 0.0
		for si in 4:
			var dist_s: float = ao_steps[si]
			var sp := lp + ln * dist_s
			var clearance := maxf(-sdf.eval_cave_void_smooth(sp.x, sp.y, sp.z), 0.0)
			var w := 1.0 / float(si + 1)
			occ += clampf(clearance / dist_s, 0.0, 1.0) * w
			w_sum += w
		# Exterior outcrop & skylight rim open directly to sky -> boost AO smoothly
		var pt := CaveSDF.eval_surface_patch_t(lp.x, lp.z)
		var is_exterior := clampf((lp.y - 31.0) / 8.0, 0.0, 1.0) if lp.z < 6.0 else clampf((lp.y - 51.0) / 5.0, 0.0, 1.0)
		var ao := clampf(occ / w_sum, 0.12, 1.0)
		if pt < 0.95:
			ao = lerpf(ao, maxf(ao, 0.88), is_exterior * (1.0 - smoothstep(0.6, 0.95, pt)))

		# B. Skylight & Entrance Mouth Ray-Marched Daylight Visibility
		var sky_vis := 0.0
		var to_sky := sky_target - lp
		var d_sky := to_sky.length()
		if d_sky < 48.0:
			var dir_s := to_sky / maxf(d_sky, 0.01)
			var ndl_s := clampf(ln.dot(dir_s) * 0.7 + 0.3, 0.0, 1.0)
			if ndl_s > 0.02:
				var vis_s := 1.0
				for ms in range(1, 7):
					var mp := lp + dir_s * (d_sky * float(ms) / 7.0)
					if mp.y < 54.0:
						var md := -sdf.eval_cave_void_smooth(mp.x, mp.y, mp.z)
						vis_s = minf(vis_s, clampf((md + 0.6) / 3.2, 0.0, 1.0))
				sky_vis = maxf(sky_vis, vis_s * ndl_s * (1.0 - smoothstep(22.0, 48.0, d_sky)))

		var to_mouth := mouth_target - lp
		var d_mouth := to_mouth.length()
		if d_mouth < 34.0 and lp.z < 26.0:
			var dir_m := to_mouth / maxf(d_mouth, 0.01)
			var ndl_m := clampf(ln.dot(dir_m) * 0.65 + 0.35, 0.0, 1.0)
			var vis_m := 1.0
			for mm in range(1, 5):
				var mp := lp + dir_m * (d_mouth * float(mm) / 5.0)
				if mp.z > -1.0:
					var md := -sdf.eval_cave_void_smooth(mp.x, mp.y, mp.z)
					vis_m = minf(vis_m, clampf((md + 0.8) / 3.5, 0.0, 1.0))
			sky_vis = maxf(sky_vis, vis_m * ndl_m * (1.0 - smoothstep(8.0, 34.0, d_mouth)))
		if lp.z < -1.5:
			sky_vis = 1.0
		var pt_ext := CaveSDF.eval_surface_patch_t(lp.x, lp.z)
		if pt_ext < 1.0:
			var ix_k := clampi(int(roundf((lp.x - U_MIN) / VOXEL)), 0, gx - 1)
			var iz_k := clampi(int(roundf((lp.z - S_MIN) / VOXEL)), 0, gz - 1)
			var kh_lp := karst_2d[iz_k * gx + ix_k]
			var near_mouth_arch := absf(lp.x) < 10.5 and lp.z > -3.5 and lp.z < 12.5 and lp.y < kh_lp - 0.5
			if lp.y >= kh_lp - 3.5 and not near_mouth_arch:
				if sdf.eval_sdf_full(lp.x, lp.y + 4.0, lp.z, kh_lp) < -1.0:
					sky_vis = 1.0
					ao = maxf(ao, 0.88)

		# C. Hydrological Wetness (pool shore, waterfall wall, stream grotto bed)
		var dp_pool: float = Vector2((lp.x - pool_c.x) / (pool_rx + 2.5), (lp.z - pool_c.z) / (pool_rz + 2.5)).length()
		var pool_wet := (1.0 - smoothstep(0.75, 1.35, dp_pool)) * (1.0 - smoothstep(17.85, 20.5, lp.y))
		var wf_wet := 1.0 - smoothstep(2.0, 7.5, Vector2(lp.x - CaveLayout.WATERFALL.x, lp.z - CaveLayout.WATERFALL.z).length())
		var stream_wet := (1.0 - smoothstep(15.5, 18.6, lp.y)) * smoothstep(55.0, 75.0, lp.z) * (1.0 - smoothstep(-46.0, -56.0, lp.x))
		var wet := clampf(maxf(maxf(pool_wet, wf_wet * 0.85), stream_wet * 0.75), 0.0, 1.0)

		# D. 1-Ring Laplacian Curvature (softened on smoothed surface to eliminate contour bands)
		var curv := 0.5
		if adj_cnt[i] > 0:
			var avg_nb := adj_sum[i] / float(adj_cnt[i])
			# If vertex protrudes past neighbor average along normal -> convex (>0.5)
			var lap := (wp - avg_nb).dot(wn)
			curv = clampf(0.5 + lap * 0.65, 0.0, 1.0)

		colors[i] = Color(ao, clampf(sky_vis, 0.0, 1.0), wet, curv)
		uvs[i] = Vector2(wp.x * 0.12, wp.z * 0.12)

	# 7. Save binary ArrayMesh and ConcavePolygonShape3D resources
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = world_verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var err_m := ResourceSaver.save(mesh, "res://terrain/cave/cave_mesh.res", ResourceSaver.FLAG_COMPRESS)

	var floor_shape := ConcavePolygonShape3D.new()
	floor_shape.backface_collision = false
	floor_shape.set_faces(floor_faces)
	var err_f := ResourceSaver.save(floor_shape, "res://terrain/cave/cave_floor_shape.res", ResourceSaver.FLAG_COMPRESS)

	var wall_shape := ConcavePolygonShape3D.new()
	wall_shape.backface_collision = false
	wall_shape.set_faces(wall_faces)
	var err_w := ResourceSaver.save(wall_shape, "res://terrain/cave/cave_wall_shape.res", ResourceSaver.FLAG_COMPRESS)

	var dt_total := float(Time.get_ticks_msec() - t0) / 1000.0
	print("Saved cave_mesh.res (%d), cave_floor_shape.res (%d, %d tris), cave_wall_shape.res (%d, %d tris) in %.2f s" % [
		err_m, err_f, floor_faces.size() / 3, err_w, wall_faces.size() / 3, dt_total
	])
	if err_m != OK or err_f != OK or err_w != OK:
		quit(1)
		return
	quit(0)


func _dir_local_to_world(d: Vector3) -> Vector3:
	return Vector3(
		CaveLayout.FWD_XZ.x * d.z + CaveLayout.RIGHT_XZ.x * d.x,
		d.y,
		CaveLayout.FWD_XZ.y * d.z + CaveLayout.RIGHT_XZ.y * d.x
	)


func _sample_field_trilinear(
	lp: Vector3,
	field: PackedFloat32Array,
	gx: int, gy: int, gz: int, stride_y: int, stride_z: int
) -> float:
	var fx := clampf((lp.x - U_MIN) / VOXEL, 0.0, float(gx - 2))
	var fy := clampf((lp.y - Y_MIN) / VOXEL, 0.0, float(gy - 2))
	var fz := clampf((lp.z - S_MIN) / VOXEL, 0.0, float(gz - 2))
	var ix := int(fx); var iy := int(fy); var iz := int(fz)
	var tx := fx - float(ix); var ty := fy - float(iy); var tz := fz - float(iz)
	var c0 := iz * stride_z + iy * stride_y + ix
	var v000 := field[c0]; var v100 := field[c0 + 1]
	var v010 := field[c0 + stride_y]; var v110 := field[c0 + stride_y + 1]
	var v001 := field[c0 + stride_z]; var v101 := field[c0 + stride_z + 1]
	var v011 := field[c0 + stride_z + stride_y]; var v111 := field[c0 + stride_z + stride_y + 1]
	var x00 := lerpf(v000, v100, tx); var x10 := lerpf(v010, v110, tx)
	var x01 := lerpf(v001, v101, tx); var x11 := lerpf(v011, v111, tx)
	return lerpf(lerpf(x00, x10, ty), lerpf(x01, x11, ty), tz)


func _sample_centroid_air_dir(
	lc: Vector3,
	field: PackedFloat32Array,
	gx: int, gy: int, gz: int, stride_y: int, stride_z: int
) -> Vector3:
	var eps := 0.35
	var gdx := _sample_field_trilinear(lc + Vector3(eps, 0.0, 0.0), field, gx, gy, gz, stride_y, stride_z) \
			- _sample_field_trilinear(lc - Vector3(eps, 0.0, 0.0), field, gx, gy, gz, stride_y, stride_z)
	var gdy := _sample_field_trilinear(lc + Vector3(0.0, eps, 0.0), field, gx, gy, gz, stride_y, stride_z) \
			- _sample_field_trilinear(lc - Vector3(0.0, eps, 0.0), field, gx, gy, gz, stride_y, stride_z)
	var gdz := _sample_field_trilinear(lc + Vector3(0.0, 0.0, eps), field, gx, gy, gz, stride_y, stride_z) \
			- _sample_field_trilinear(lc - Vector3(0.0, 0.0, eps), field, gx, gy, gz, stride_y, stride_z)
	return _dir_local_to_world(Vector3(-gdx, -gdy, -gdz))


func _append_oriented_tri(
	ia: int, ib: int, ic: int,
	fallback_dir_air: Vector3,
	local_verts: PackedVector3Array,
	world_verts: PackedVector3Array,
	vert_air_dirs: PackedVector3Array,
	field: PackedFloat32Array,
	gx: int, gy: int, gz: int, stride_y: int, stride_z: int,
	indices: PackedInt32Array
) -> void:
	var pa := world_verts[ia]
	var pb := world_verts[ib]
	var pc := world_verts[ic]
	var lc := (local_verts[ia] + local_verts[ib] + local_verts[ic]) * (1.0 / 3.0)
	var c_air := _sample_centroid_air_dir(lc, field, gx, gy, gz, stride_y, stride_z)
	var v_air := (vert_air_dirs[ia] + vert_air_dirs[ib] + vert_air_dirs[ic]) * 0.25
	var ref := c_air if c_air.length_squared() > 1e-6 else (v_air if v_air.length_squared() > 1e-6 else fallback_dir_air)
	var fn := (pc - pa).cross(pb - pa)
	if fn.dot(ref) >= 0.0:
		indices.append(ia); indices.append(ib); indices.append(ic)
	else:
		indices.append(ia); indices.append(ic); indices.append(ib)


func _emit_quad(
	q0: int, q1: int, q2: int, q3: int,
	fallback_dir_air: Vector3,
	local_verts: PackedVector3Array,
	world_verts: PackedVector3Array,
	vert_air_dirs: PackedVector3Array,
	field: PackedFloat32Array,
	gx: int, gy: int, gz: int, stride_y: int, stride_z: int,
	indices: PackedInt32Array,
	adj_sum: PackedVector3Array,
	adj_cnt: PackedInt32Array
) -> void:
	var p0 := world_verts[q0]
	var p1 := world_verts[q1]
	var p2 := world_verts[q2]
	var p3 := world_verts[q3]

	# Accumulate 1-ring quad perimeter neighbors (each undirected edge counted twice across shared quads -> symmetric)
	adj_sum[q0] += p1 + p3; adj_cnt[q0] += 2
	adj_sum[q1] += p0 + p2; adj_cnt[q1] += 2
	adj_sum[q2] += p1 + p3; adj_cnt[q2] += 2
	adj_sum[q3] += p2 + p0; adj_cnt[q3] += 2

	# Choose the quad diagonal with better triangle dihedral alignment to prevent pinched bowties
	var na0 := (p2 - p0).cross(p1 - p0).normalized()
	var na1 := (p3 - p0).cross(p2 - p0).normalized()
	var nb0 := (p3 - p1).cross(p2 - p1).normalized()
	var nb1 := (p0 - p1).cross(p3 - p1).normalized()
	var score_a := absf(na0.dot(na1))
	var score_b := absf(nb0.dot(nb1))
	if score_a >= score_b:
		_append_oriented_tri(q0, q1, q2, fallback_dir_air, local_verts, world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, indices)
		_append_oriented_tri(q0, q2, q3, fallback_dir_air, local_verts, world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, indices)
	else:
		_append_oriented_tri(q1, q2, q3, fallback_dir_air, local_verts, world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, indices)
		_append_oriented_tri(q1, q3, q0, fallback_dir_air, local_verts, world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, indices)

