extends SceneTree

# Offline Surface-Nets Baker for:
#   1) Skeleton Crypt Cave (res://assets/dungeon/skel_cave_*.res)
#   2) Underground Rat Warren (res://assets/dungeon/rat_warren_*.res)
#   3) Wolf Pack Crag Granite Cliff Cave (res://assets/dungeon/wolf_den_*.res)
#
# Run headlessly:
#   godot --headless --path d:\slime --script res://tools/bake_extra_caves.gd

const TerrainScript := preload("res://terrain/terrain.gd")
const WorldLandmarks := preload("res://scripts/world_landmarks.gd")

const OUT_DIR := "res://assets/dungeon"

var _terrain = null
var _n_macro: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_karst: FastNoiseLite
var _n_warp: FastNoiseLite
var _th_grid := PackedFloat32Array()
var _th_gx: int = 0
var _th_gz: int = 0
var _th_x0: float = 0.0
var _th_z0: float = 0.0
var _th_voxel: float = 1.0


func _build_th_grid(x0: float, z0: float, gx: int, gz: int, voxel: float, world_off: Vector2 = Vector2.ZERO) -> void:
	_th_x0 = x0
	_th_z0 = z0
	_th_gx = gx
	_th_gz = gz
	_th_voxel = voxel
	_th_grid.resize(gx * gz)
	for iz in gz:
		var z := z0 + float(iz) * voxel + world_off.y
		var row := iz * gx
		for ix in gx:
			var x := x0 + float(ix) * voxel + world_off.x
			_th_grid[row + ix] = float(_terrain.sample_height(x, z))


func _lookup_th(x: float, z: float) -> float:
	var fx := clampf((x - _th_x0) / _th_voxel, 0.0, float(_th_gx - 2))
	var fz := clampf((z - _th_z0) / _th_voxel, 0.0, float(_th_gz - 2))
	var ix := int(fx); var iz := int(fz)
	var tx := fx - float(ix); var tz := fz - float(iz)
	var r0 := iz * _th_gx + ix
	var r1 := r0 + _th_gx
	return lerpf(lerpf(_th_grid[r0], _th_grid[r0 + 1], tx), lerpf(_th_grid[r1], _th_grid[r1 + 1], tx), tz)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_terrain = TerrainScript.new()
	_setup_noise()

	print("=== Baking Extra Organic Caves (SurfaceNets) ===")
	var only_arg := ""
	for ua in OS.get_cmdline_user_args():
		if ua.begins_with("--only="):
			only_arg = ua.substr(7).to_lower()
	var ok := true

	if only_arg.is_empty() or only_arg == "skel":
		ok = ok and _bake_skeleton_cave()
	if only_arg.is_empty() or only_arg == "rat":
		ok = ok and _bake_rat_warren()
	if only_arg.is_empty() or only_arg == "wolf":
		ok = ok and _bake_wolf_den()

	if _terrain != null:
		_terrain.free()
		_terrain = null

	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	print("=== Extra Caves Bake Complete in %.2f s (ok=%s) ===" % [dt, str(ok)])
	quit(0 if ok else 1)


func _setup_noise() -> void:
	_n_macro = FastNoiseLite.new()
	_n_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_macro.seed = 4103
	_n_macro.frequency = 0.048
	_n_macro.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_macro.fractal_octaves = 3

	_n_ridge = FastNoiseLite.new()
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_ridge.seed = 5309
	_n_ridge.frequency = 0.115
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 2

	_n_karst = FastNoiseLite.new()
	_n_karst.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_karst.seed = 6733
	_n_karst.frequency = 0.19
	_n_karst.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_karst.fractal_octaves = 3

	_n_warp = FastNoiseLite.new()
	_n_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_warp.seed = 8191
	_n_warp.frequency = 0.065
	_n_warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_warp.fractal_octaves = 2


# ==============================================================================
# SIGNED DISTANCE HELPERS (field < 0 = AIR, field > 0 = SOLID ROCK)
# ==============================================================================

static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / maxf(k, 0.001), 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _smax(a: float, b: float, k: float) -> float:
	return -_smin(-a, -b, k)


# Returns < 0 inside oriented box/dome void, > 0 outside
static func _sd_box(p: Vector3, b: Vector3) -> float:
	var q := Vector3(absf(p.x), absf(p.y), absf(p.z)) - b
	var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
	var inside := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
	return outside + inside


static func _sd_vault_chamber(
	p: Vector3,
	center_xz: Vector2,
	half_xz: Vector2,
	floor_y: float,
	ceil_y: float,
	arch_roundness: float = 0.42
) -> float:
	var dx := absf(p.x - center_xz.x) / maxf(half_xz.x, 0.1)
	var dz := absf(p.z - center_xz.y) / maxf(half_xz.y, 0.1)
	# Fast squircle metric without slow pow() calls
	var r_plan := lerpf(sqrt(dx * dx + dz * dz), maxf(dx, dz), 0.34)
	var min_r := minf(half_xz.x, half_xz.y)
	var d_wall := (r_plan - 1.0) * min_r
	var r_clamped := clampf(r_plan, 0.0, 1.25)
	var arch_drop := (r_clamped * r_clamped) * (ceil_y - floor_y) * arch_roundness
	var local_ceil := ceil_y - arch_drop
	var d_floor := floor_y - p.y
	var d_ceil := p.y - local_ceil
	return _smax(_smax(d_wall, d_floor, 0.9), d_ceil, 1.35)


static func _sd_capsule_segment(p: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.length_squared(), 1e-5), 0.0, 1.0)
	return (pa - ba * h).length() - r


# ==============================================================================
# 1. SKELETON CRYPT CAVE (-882..-762, y 12.5..48, z 202..340)
# ==============================================================================

func _skel_eval_void(x: float, y: float, z: float) -> float:
	var wp := Vector3(x, y, z)
	# Lateral karst wobble (strictly zeroed near dry walkable floor slabs!)
	var wx := _n_warp.get_noise_3d(x, y * 1.15, z) * 1.35
	var wy := _n_macro.get_noise_3d(x * 1.1, y, z * 1.1) * 0.85
	var wz := _n_warp.get_noise_3d(x + 31.0, y * 1.1, z - 19.0) * 1.35
	var p := Vector3(x + wx, y, z + wz)

	# Sunken Stairwell Descent (z = 326 -> 298, floor 26.0 -> 8.0):
	# Open to sky along z >= 305, plunging under an arched bedrock vault north of z <= 303!
	var tz_ent := clampf((326.0 - z) / 28.0, 0.0, 1.0)
	var floor_ent := lerpf(WorldLandmarks.SKEL_FORECOURT_Y, WorldLandmarks.SKEL_UPPER_Y, tz_ent)
	var ent_half_x := lerpf(6.15, 7.2, smoothstep(318.0, 298.0, z))
	var sky_t := smoothstep(302.5, 306.5, z)
	var ent_ceil := lerpf(floor_ent + 9.4, 32.0, sky_t)
	var d_ent := _sd_vault_chamber(Vector3(x + wx * 0.28, y, z), Vector2(-820.0, 312.5), Vector2(ent_half_x, 15.8), floor_ent, ent_ceil, lerpf(0.35, 0.04, sky_t))

	# Pillared Atrium (-820, 8.0, 282.5): grand vaulted underground hall (>= 7m below flat meadow!)
	var d_atrium := _sd_vault_chamber(p, Vector2(-820.0, 282.5), Vector2(19.5, 16.5), WorldLandmarks.SKEL_UPPER_Y, 18.8 + wy * 0.6, 0.36)
	var d := _smin(d_ent, d_atrium, 2.0)

	# West Squeeze Gate Corridor (kept cleanly open along z = 263.5, x = -838..-870)
	var d_squeeze_corr := _sd_vault_chamber(Vector3(x, y, z + wz * 0.35), Vector2(-854.0, 263.5), Vector2(18.5, 3.5), WorldLandmarks.SKEL_UPPER_Y, 13.8, 0.32)
	d = _smin(d, d_squeeze_corr, 1.3)

	# West Flooded Cistern N & S pools + cavern vault behind squeeze gate
	var d_cistern_dom := _sd_vault_chamber(p, Vector2(-860.5, 263.5), Vector2(13.5, 16.5), WorldLandmarks.SKEL_UPPER_Y, 16.2 + wy * 0.5, 0.38)
	d = _smin(d, d_cistern_dom, 1.8)
	# Submerge N & S basins of the West Cistern (floor dropped to 5.8m), keeping central z in [260..267] bridge at 8.0!
	var d_pool_n := _sd_vault_chamber(Vector3(x + wx * 0.4, y, z), Vector2(-860.0, 253.5), Vector2(11.5, 5.2), 5.8, 15.2, 0.35)
	var d_pool_s := _sd_vault_chamber(Vector3(x + wx * 0.4, y, z), Vector2(-860.0, 274.5), Vector2(11.5, 6.2), 5.8, 15.2, 0.35)
	d = _smin(d, d_pool_n, 1.1)
	d = _smin(d, d_pool_s, 1.1)

	# East Ossuary Wing (-788, 8.0, 271.5)
	var d_east_corr := _sd_vault_chamber(Vector3(x, y, z + wz * 0.4), Vector2(-799.5, 272.0), Vector2(8.0, 4.8), WorldLandmarks.SKEL_UPPER_Y, 15.2, 0.36)
	var d_ossuary := _sd_vault_chamber(p, Vector2(-786.5, 270.0), Vector2(14.5, 16.5), WorldLandmarks.SKEL_UPPER_Y, 17.0 + wy * 0.5, 0.36)
	# Subtle shallow bone-water trench along far East wall (x = -776) clear of gameplay zone
	var d_east_trench := _sd_vault_chamber(Vector3(x + wx * 0.3, y, z), Vector2(-775.5, 270.0), Vector2(3.6, 11.0), 6.7, 14.5, 0.3)
	d = _smin(d, d_east_corr, 1.4)
	d = _smin(d, d_ossuary, 1.8)
	d = _smin(d, d_east_trench, 0.9)

	# Sanctum Grand Stairway (z = 268 -> 252, floor 8.0 -> 4.0)
	var tz_st := clampf((268.0 - z) / 16.0, 0.0, 1.0)
	var floor_st := lerpf(WorldLandmarks.SKEL_UPPER_Y, WorldLandmarks.SKEL_SANCTUM_Y, tz_st)
	var d_stair := _sd_vault_chamber(Vector3(x + wx * 0.4, y, z), Vector2(-820.0, 260.0), Vector2(7.0, 10.0), floor_st, floor_st + 10.8, 0.32)
	d = _smin(d, d_stair, 1.6)

	# Skeleton Overlord Sanctum Cathedral (-820, 4.0, 230.0) - towering 16m subterranean limestone dome!
	var d_sanctum := _sd_vault_chamber(p, Vector2(-820.0, 229.5), Vector2(24.5, 21.0), WorldLandmarks.SKEL_SANCTUM_Y, 20.4 + wy * 0.7, 0.42)
	# Apse behind Overlord Throne (-820, 4.0, 212)
	var d_apse := _sd_vault_chamber(p, Vector2(-820.0, 214.0), Vector2(12.0, 7.5), WorldLandmarks.SKEL_SANCTUM_Y, 16.8, 0.45)
	# West & East Abyssal Moat Trenches along extreme sanctum flanks (keeps floor center [-835..-805] dry 4.0!)
	var d_moat_w := _sd_vault_chamber(Vector3(x, y, z), Vector2(-841.5, 229.5), Vector2(3.6, 15.5), 2.2, 14.8, 0.3)
	var d_moat_e := _sd_vault_chamber(Vector3(x, y, z), Vector2(-798.5, 229.5), Vector2(3.6, 15.5), 2.2, 14.8, 0.3)
	d = _smin(d, d_sanctum, 2.2)
	d = _smin(d, d_apse, 1.6)
	d = _smin(d, d_moat_w, 1.0)
	d = _smin(d, d_moat_e, 1.0)

	# Karst limestone ribs & rock relief on walls & ceilings (zeroed smoothly on dry walkable floor levels)
	var above_floor := smoothstep(0.65, 2.2, absf(y - WorldLandmarks.SKEL_UPPER_Y)) * smoothstep(0.65, 2.2, absf(y - WorldLandmarks.SKEL_SANCTUM_Y)) * smoothstep(0.55, 1.9, absf(y - floor_ent)) * smoothstep(0.55, 1.9, absf(y - floor_st))
	var k_detail := (_n_karst.get_noise_3d(wp.x, wp.y * 1.35, wp.z) * 0.65 + _n_ridge.get_noise_3d(wp.x * 0.9, wp.y * 0.75, wp.z * 0.9) * 0.50)
	# Strata horizontal limestone ledges
	var strata := sin(y * 1.15 + _n_macro.get_noise_3d(x, 0.0, z) * 2.5) * 0.32
	d += (k_detail * 0.85 + strata) * above_floor
	return d


func _skel_eval_patch_t(x: float, z: float) -> float:
	# Normalized distance around sunken stairwell pit (-820, 315.5) — zero exterior hill mound!
	return Vector2((x + 820.0) / 14.0, (z - 315.5) / 16.5).length()


func _skel_eval_field(x: float, y: float, z: float) -> float:
	var th := _lookup_th(x, z)
	var pt := _skel_eval_patch_t(x, z)
	# Flush beneath flat courtyard plaza (-0.55m down to -2.2m) — NO artificial dome mound!
	var surf_h := th - 0.55 - smoothstep(0.60, 0.96, pt) * 1.65
	var d_rock := surf_h - y
	var d_void := _skel_eval_void(x, y, z)
	# North of stairwell portal throat (z < 304.5): clamp every vault roof >= 2.6m beneath flat ground!
	var sub_mask := clampf((306.5 - z) / 4.0, 0.0, 1.0)
	if sub_mask > 0.001:
		var roof_y := th - 2.6
		d_void = lerpf(d_void, _smax(d_void, y - roof_y, 1.4), sub_mask)
	return _smin(d_rock, d_void, 1.0)


func _bake_skeleton_cave() -> bool:
	var cfg := {
		"name": "skel_cave",
		"x_min": -880.0, "x_max": -764.0,
		"y_min": 0.5, "y_max": 29.0,
		"z_min": 204.0, "z_max": 335.0,
		"voxel": 0.78,
		"cutout_min": WorldLandmarks.SKEL_CUTOUT_MIN,
		"cutout_max": WorldLandmarks.SKEL_CUTOUT_MAX,
		"sky_open_dir": Vector3(0.0, 0.62, 0.78).normalized(),
		"mouth_xz": Vector2(-820.0, 305.0),
		"pool_ys": [7.65, 3.65],
		"walk_ys": [8.0, 4.0],
	}
	return _bake_region(
		cfg,
		Callable(self, "_skel_eval_field"),
		Callable(self, "_skel_eval_void"),
		Callable(self, "_skel_eval_patch_t")
	)


# ==============================================================================
# 2. UNDERGROUND RAT WARREN (-268..-212, y 10.5..35, z 218..292)
# ==============================================================================

static func _sd_organic_cavern(
	p: Vector3,
	center_xz: Vector2,
	rx: float,
	rz: float,
	angle_rad: float,
	floor_y: float,
	ceil_y: float,
	arch_roundness: float = 0.48
) -> float:
	var c := cos(angle_rad)
	var s := sin(angle_rad)
	var lx := p.x - center_xz.x
	var lz := p.z - center_xz.y
	var ux := (lx * c - lz * s) / maxf(rx, 0.2)
	var uz := (lx * s + lz * c) / maxf(rz, 0.2)
	# Pure smooth rotated ellipse + gentle organic cove undulation (zero square max() metric!)
	var r_plan := sqrt(ux * ux + uz * uz)
	var lobe := 0.06 * sin(atan2(uz, ux) * 3.0 + angle_rad * 2.0) + 0.04 * cos(atan2(uz, ux) * 5.0)
	r_plan -= lobe
	var min_r := minf(rx, rz)
	var d_wall := (r_plan - 1.0) * min_r
	var r_clamped := clampf(r_plan, 0.0, 1.25)
	var arch_drop := (r_clamped * r_clamped) * (ceil_y - floor_y) * arch_roundness
	var local_ceil := ceil_y - arch_drop
	var d_floor := floor_y - p.y
	var d_ceil := p.y - local_ceil
	return _smax(_smax(d_wall, d_floor, 1.05), d_ceil, 1.45)


static func _sd_curved_tunnel(p: Vector3, pts: Array, half_w: float, head_h: float) -> float:
	var best := 1e6
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ab := b - a
		var ab_xz := Vector2(ab.x, ab.z)
		var len2 := maxf(ab_xz.length_squared(), 1e-4)
		var ap_xz := Vector2(p.x - a.x, p.z - a.z)
		var t := clampf(ap_xz.dot(ab_xz) / len2, 0.0, 1.0)
		var c_pt := a.lerp(b, t)
		var r_xz := Vector2(p.x - c_pt.x, p.z - c_pt.z).length() / maxf(half_w, 0.3)
		var d_w := (r_xz - 1.0) * half_w
		var arch_h := head_h * maxf(0.18, 1.0 - r_xz * r_xz * 0.58)
		var d_v := _smax(c_pt.y - p.y, p.y - (c_pt.y + arch_h), 1.1)
		best = minf(best, _smax(d_w, d_v, 0.95))
	return best


func _rat_eval_void(x: float, y: float, z: float) -> float:
	var wx := _n_warp.get_noise_3d(x * 1.15, y * 1.05, z * 1.15) * 1.45
	var wy := _n_macro.get_noise_3d(x * 1.15, y, z * 1.15) * 0.90
	var wz := _n_warp.get_noise_3d(x * 1.15 - 17.0, y, z * 1.15 + 23.0) * 1.45
	var p := Vector3(x + wx, y, z + wz)

	# 1. Dog-Leg Winding Sinkhole Descent Tunnel (z=281 -> 253, y=22.0 -> 14.5)
	#    Keeps entrance mouth z=280..271 aligned for doorway entry then bends Eastward to break straight-line sightline!
	var d_ent := _sd_curved_tunnel(Vector3(x + wx * 0.45, y, z), [
		Vector3(-240.0, 22.0, 281.0),
		Vector3(-239.8, 22.0, 278.0),
		Vector3(-239.4, 19.38, 271.0),
		Vector3(-234.2, 15.81, 261.5),
		Vector3(-235.5, 14.5, 258.0),
		Vector3(-236.5, 14.5, 253.0),
	], 4.7, 6.2)
	var d_flare := _sd_organic_cavern(Vector3(x + wx * 0.4, y, z), Vector2(-240.0, 278.5), 5.6, 4.6, 0.12, 21.95, 28.0, 0.38)
	var d := _smin(d_ent, d_flare, 1.6)

	# 2. Asymmetrical Central Confluence Dome (-239.5, 244, floor y=14.5, vaulted ceil ~24.6m)
	var d_hub := _sd_organic_cavern(p, Vector2(-239.5, 244.0), 18.8, 15.2, -0.32, 14.50, 24.6 + wy * 0.55, 0.44)
	d = _smin(d, d_hub, 2.2)

	# Single NE Elevated Scavenger Shelf above Crossroads water cove (-228.5, 234.0, floor y=17.4)
	var d_ne_alcove := _sd_organic_cavern(p, Vector2(-228.5, 234.0), 6.0, 5.0, -0.45, 17.40, 24.6, 0.42)
	d = _smin(d, d_ne_alcove, 1.4)

	# Asymmetrical Submerged Water Coves carved naturally around central rocks (bed y=12.15, water=13.35)
	var d_cove_sw := _sd_organic_cavern(Vector3(x + wx * 0.35, y, z + wz * 0.35), Vector2(-250.8, 246.5), 5.4, 5.8, 0.48, 12.15, 22.8, 0.42)
	var d_cove_se := _sd_organic_cavern(Vector3(x + wx * 0.35, y, z + wz * 0.35), Vector2(-231.5, 247.2), 4.2, 4.4, 0.62, 12.15, 22.8, 0.42)
	d = _smin(d, d_cove_sw, 1.1)
	d = _smin(d, d_cove_se, 1.1)

	# Natural Skylight Chimney Dome above (-240, 244.5) without piercing outer ground overburden
	var d_sky_shaft := _sd_organic_cavern(Vector3(x, y, z), Vector2(-240.0, 244.5), 3.4, 3.1, 0.2, 18.0, 25.8, 0.28)
	d = _smin(d, d_sky_shaft, 1.2)

	# 3. WEST WING: Stronger S-Bend Squeeze -> Crescent Flooded Sump Grotto (-276, 243) + NW Bolt-Hole Loop
	var d_w_corr := _sd_curved_tunnel(Vector3(x, y, z + wz * 0.45), [
		Vector3(-248.5, 14.5, 244.5),
		Vector3(-257.5, 14.5, 238.2),
		Vector3(-266.5, 14.5, 245.2),
		Vector3(-275.0, 14.5, 242.5),
	], 3.9, 6.2)
	var d_w_grotto := _sd_organic_cavern(p, Vector2(-276.0, 243.0), 14.5, 16.0, 0.42, 14.50, 24.4 + wy * 0.50, 0.44)
	var d_w_spout := _sd_organic_cavern(p, Vector2(-287.2, 243.5), 4.2, 4.8, 0.1, 16.0, 23.6, 0.38)
	var d_w_lagoon_n := _sd_organic_cavern(Vector3(x + wx * 0.3, y, z + wz * 0.3), Vector2(-280.5, 234.5), 9.5, 5.8, -0.35, 12.05, 22.5, 0.40)
	var d_w_lagoon_s := _sd_organic_cavern(Vector3(x + wx * 0.3, y, z + wz * 0.3), Vector2(-275.0, 252.8), 10.5, 5.6, 0.28, 12.05, 22.5, 0.40)
	var d_nw_loop := _sd_curved_tunnel(Vector3(x, y, z + wz * 0.4), [
		Vector3(-268.5, 14.5, 234.0),
		Vector3(-261.0, 13.65, 226.5),
		Vector3(-252.0, 13.03, 222.5),
	], 3.6, 5.6)
	d = _smin(d, d_w_corr, 1.6)
	d = _smin(d, d_w_grotto, 1.9)
	d = _smin(d, d_w_spout, 1.2)
	d = _smin(d, d_w_lagoon_n, 1.2)
	d = _smin(d, d_w_lagoon_s, 1.2)
	d = _smin(d, d_nw_loop, 1.4)

	# 4. EAST WING: Organic S-Curve Burrow -> Fungal Nest (-202.5, 242) with Raised Shelf -> NE Bypass Loop
	var d_e_corr := _sd_curved_tunnel(Vector3(x, y, z + wz * 0.45), [
		Vector3(-231.0, 14.5, 241.5),
		Vector3(-221.0, 14.8, 247.8),
		Vector3(-211.0, 15.0, 239.8),
		Vector3(-203.0, 14.5, 242.0),
	], 4.2, 6.4)
	var d_e_nest := _sd_organic_cavern(p, Vector2(-202.5, 242.0), 15.8, 17.2, -0.38, 14.50, 24.6 + wy * 0.50, 0.44)
	# Elevated natural fungal root-burrow terrace shelf along East curve (floor y=16.0)
	var d_e_shelf := _sd_organic_cavern(p, Vector2(-194.2, 241.5), 6.2, 9.2, -0.25, 16.0, 24.4, 0.40)
	var d_e_loop := _sd_curved_tunnel(Vector3(x, y, z + wz * 0.4), [
		Vector3(-204.5, 14.34, 231.0),
		Vector3(-209.5, 12.64, 220.0),
		Vector3(-218.0, 11.32, 211.5),
		Vector3(-228.5, 11.01, 209.5),
	], 4.2, 6.4)
	d = _smin(d, d_e_corr, 1.6)
	d = _smin(d, d_e_nest, 1.9)
	d = _smin(d, d_e_shelf, 1.4)
	d = _smin(d, d_e_loop, 1.6)

	# 5. SPLIT NW & NE WINDING BURROW LOOPS AROUND CENTRAL BEDROCK & ROOT DIVIDE -> DEEP BROOD HOLLOW (-239, 194)
	var ts_n := clampf((232.0 - z) / 29.0, 0.0, 1.0)
	var floor_ns := lerpf(WorldLandmarks.RAT_VAULT_Y, WorldLandmarks.RAT_SANCTUM_Y, ts_n)
	var d_nw_burrow := _sd_curved_tunnel(Vector3(x + wx * 0.4, y, z), [
		Vector3(-245.0, 14.5, 234.5),
		Vector3(-246.5, 14.5, 232.0),
		Vector3(-252.0, 13.18, 223.5),
		Vector3(-249.0, 11.47, 212.5),
		Vector3(-243.0, 10.0, 203.0),
		Vector3(-242.5, 10.0, 201.5),
	], 4.6, 7.0)
	var d_ne_burrow := _sd_curved_tunnel(Vector3(x + wx * 0.4, y, z), [
		Vector3(-233.5, 14.5, 233.5),
		Vector3(-231.5, 14.5, 232.0),
		Vector3(-225.5, 12.95, 222.0),
		Vector3(-228.5, 11.24, 211.0),
		Vector3(-235.0, 10.0, 203.0),
		Vector3(-235.5, 10.0, 201.0),
	], 4.8, 7.4)
	var plateau_w := (1.0 - smoothstep(7.5, 11.5, absf(x + 240.0))) * smoothstep(190.0, 185.0, z)
	var floor_cathedral := 10.0 + 1.45 * plateau_w
	var d_ncath := _sd_organic_cavern(p, Vector2(-239.0, 194.0), 23.5, 16.8, 0.34, floor_cathedral, 23.8 + wy * 0.55, 0.48)
	# Single asymmetrical NW dark seepage pool hugging outer curve (bed y=8.25, water=9.20)
	var d_nmoat_w := _sd_organic_cavern(Vector3(x + wx * 0.28, y, z + wz * 0.28), Vector2(-257.5, 193.5), 5.2, 12.5, 0.22, 8.25, 21.5, 0.40)
	d = _smin(d, d_nw_burrow, 1.8)
	d = _smin(d, d_ne_burrow, 1.8)
	d = _smin(d, d_ncath, 2.4)
	d = _smin(d, d_nmoat_w, 1.1)

	# Deep natural karst limestone rock ribs & gnarled strata along walls/ceilings (smoothly zeroed on walkable beds!)
	var above_floor := smoothstep(0.55, 1.9, absf(y - 14.50)) \
		* smoothstep(0.55, 1.9, absf(y - floor_cathedral)) \
		* smoothstep(0.55, 1.8, absf(y - 16.0)) \
		* smoothstep(0.55, 1.8, absf(y - 12.10)) \
		* smoothstep(0.50, 1.7, absf(y - floor_ns))
	var k_detail := _n_karst.get_noise_3d(x * 1.15, y * 1.35, z * 1.15) * 0.78 + _n_ridge.get_noise_3d(x, y * 0.85, z) * 0.56
	var strata := sin(y * 1.25 + _n_macro.get_noise_3d(x, 0.0, z) * 2.4) * 0.34
	d += (k_detail * 0.92 + strata) * above_floor
	return d


func _rat_eval_patch_t(x: float, z: float) -> float:
	return Vector2((x + 240.0) / 14.5, (z - 275.5) / 10.5).length()


func _rat_eval_field(x: float, y: float, z: float) -> float:
	var th := _lookup_th(x, z)
	var surf_h := th
	var d_rock := surf_h - y
	var d_void := _rat_eval_void(x, y, z)
	var sub_mask := clampf((271.5 - z) / 5.0, 0.0, 1.0)
	if sub_mask > 0.001:
		var roof_y := th - 4.2
		d_void = lerpf(d_void, _smax(d_void, y - roof_y, 1.2), sub_mask)
	return _smin(d_rock, d_void, 0.95)


func _bake_rat_warren() -> bool:
	var cfg := {
		"name": "rat_warren",
		"x_min": -298.0, "x_max": -182.0,
		"y_min": 6.5, "y_max": 33.5,
		"z_min": 172.0, "z_max": 286.0,
		"voxel": 0.62,
		# Baked-frame coords (world = baked + WorldLandmarks.RAT_WARREN_OFFSET)
		"world_offset": WorldLandmarks.RAT_WARREN_OFFSET,
		"cutout_min": Vector2(-243.8, 269.5),
		"cutout_max": Vector2(-236.2, 279.0),
		"sky_open_dir": Vector3(0.0, 0.50, 0.86).normalized(),
		"mouth_xz": Vector2(-240.0, 279.0),
		"pool_ys": [13.05, 9.2],
		"walk_ys": [14.5, 10.0],
	}
	return _bake_region(
		cfg,
		Callable(self, "_rat_eval_field"),
		Callable(self, "_rat_eval_void"),
		Callable(self, "_rat_eval_patch_t")
	)


# ==============================================================================
# 3. WOLF PACK CRAG GRANITE CLIFF CAVE (LOCAL coords around Howlcrest anchor)
#    Placed at (290, cy, -240) with cave opening facing +Z toward central clearing
# ==============================================================================

func _wolf_eval_void(lx: float, ly: float, lz: float) -> float:
	var wx := _n_warp.get_noise_3d(lx + 290.0, ly, lz - 240.0) * 0.95
	var wy := _n_macro.get_noise_3d(lx + 290.0, ly * 1.2, lz - 240.0) * 0.65
	var wz := _n_warp.get_noise_3d(lx + 271.0, ly, lz - 213.0) * 0.95
	var p := Vector3(lx + wx, ly, lz + wz)
	# Vaulted granite wolf den recess inside cliff (lz = -12.8..-3.5, opening +Z toward clearing)
	var d_recess := _sd_vault_chamber(p, Vector2(0.0, -7.8), Vector2(5.8, 5.2), -0.45, 4.75 + wy * 0.55, 0.40)
	# Wide jaw mouth flaring out toward lz = -1.8
	var d_mouth := _sd_vault_chamber(Vector3(lx + wx * 0.5, ly, lz), Vector2(0.0, -3.0), Vector2(6.2, 3.8), -0.45, 5.25, 0.36)
	var d := _smin(d_recess, d_mouth, 1.4)
	var above_floor := smoothstep(0.35, 1.2, ly)
	d += (_n_karst.get_noise_3d(lx * 1.2, ly * 1.3, lz * 1.2) * 0.45 + _n_ridge.get_noise_3d(lx, ly, lz) * 0.42) * above_floor
	return d


func _wolf_eval_field(lx: float, ly: float, lz: float) -> float:
	# Sculpted Alpine Crag Mass centered at local (0, 0, -9.8): top_h - ly > 0 inside rock, < 0 in air!
	var rx := lx / 12.2
	var rz := (lz + 9.8) / 7.8
	var r2 := rx * rx + rz * rz
	var ridge := 8.2 * exp(-r2 * 1.15) \
			+ 3.5 * exp(-(pow((lx - 4.8) / 5.2, 2.0) + pow((lz + 9.0) / 4.8, 2.0))) \
			+ 3.1 * exp(-(pow((lx + 5.2) / 4.8, 2.0) + pow((lz + 9.2) / 4.5, 2.0)))
	var crag_n := _n_ridge.get_noise_3d((lx + 290.0) * 0.75, ly * 0.45, (lz - 240.0) * 0.75) * 1.65 * clampf(1.2 - r2 * 0.6, 0.0, 1.0)
	var mac_n := _n_macro.get_noise_3d(lx + 290.0, ly * 0.6, lz - 240.0) * 0.85
	var top_h := ridge + crag_n + mac_n - 0.55
	var d_rock := minf(top_h - ly, ly + 0.75)
	var d_void := _wolf_eval_void(lx, ly, lz)
	return _smin(d_rock, d_void, 0.85)


func _bake_wolf_den() -> bool:
	var gx_min := -15.5; var gx_max := 15.5
	var gy_min := -1.2; var gy_max := 11.2
	var gz_min := -20.5; var gz_max := -0.5
	var voxel := 0.46
	var nx := int(ceilf((gx_max - gx_min) / voxel))
	var ny := int(ceilf((gy_max - gy_min) / voxel))
	var nz := int(ceilf((gz_max - gz_min) / voxel))
	var gx := nx + 1; var gy := ny + 1; var gz := nz + 1
	var stride_y := gx; var stride_z := gx * gy
	var field := PackedFloat32Array()
	field.resize(gx * gy * gz)
	for iz in gz:
		var z := gz_min + float(iz) * voxel
		for iy in gy:
			var y := gy_min + float(iy) * voxel
			for ix in gx:
				var x := gx_min + float(ix) * voxel
				field[iz * stride_z + iy * stride_y + ix] = _wolf_eval_field(x, y, z)

	var res := _extract_surfacenets(
		field, nx, ny, nz, gx, gy, gz,
		gx_min, gy_min, gz_min, voxel,
		func(p: Vector3) -> bool: return false, # Keep entire boulder crag mesh
		func(p: Vector3, _n: Vector3) -> bool: return p.y > -0.65,
		Callable(self, "_wolf_eval_void"),
		Vector3(0.0, 0.35, 0.94).normalized(),
		[], [], Vector2(0.0, -3.0), false
	)

	var mesh: ArrayMesh = res["mesh"]
	var wall_faces: PackedVector3Array = res["wall_faces"]
	# Merge floor + wall tris for boulder collision on cliff dome
	wall_faces.append_array(res["floor_faces"])
	var wall_shape := ConcavePolygonShape3D.new()
	wall_shape.backface_collision = true
	wall_shape.set_faces(wall_faces)

	var err_m := ResourceSaver.save(mesh, OUT_DIR + "/wolf_den_mesh.res", ResourceSaver.FLAG_COMPRESS)
	var err_w := ResourceSaver.save(wall_shape, OUT_DIR + "/wolf_den_wall_shape.res", ResourceSaver.FLAG_COMPRESS)
	print("Saved wolf_den_mesh.res (%d, %d verts) wall_shape (%d, %d tris)" % [
		err_m, mesh.surface_get_array_len(0), err_w, wall_faces.size() / 3
	])
	return err_m == OK and err_w == OK


# ==============================================================================
# SHARED SPARSE-BRICK SURFACE-NETS PIPELINE (same orientation math as bake_cave.gd)
# ==============================================================================

func _bake_region(
	cfg: Dictionary,
	eval_field: Callable,
	eval_void: Callable,
	eval_patch_t: Callable
) -> bool:
	var t0 := Time.get_ticks_msec()
	var x_min: float = cfg["x_min"]; var x_max: float = cfg["x_max"]
	var y_min: float = cfg["y_min"]; var y_max: float = cfg["y_max"]
	var z_min: float = cfg["z_min"]; var z_max: float = cfg["z_max"]
	var voxel: float = cfg["voxel"]

	var nx := int(ceilf((x_max - x_min) / voxel))
	var ny := int(ceilf((y_max - y_min) / voxel))
	var nz := int(ceilf((z_max - z_min) / voxel))
	var gx := nx + 1; var gy := ny + 1; var gz := nz + 1
	var stride_y := gx; var stride_z := gx * gy
	_build_th_grid(x_min, z_min, gx, gz, voxel, cfg.get("world_offset", Vector2.ZERO))

	# Coarse active brick culling (8x8x8 bricks): test all 8 brick corners + center, then dilate by 1 brick
	# so SurfaceNets NEVER hits an uncomputed +25.0 sentinel neighbor along any sloped or warped surface.
	const BRICK := 8
	var bnx := (nx + BRICK - 1) / BRICK
	var bny := (ny + BRICK - 1) / BRICK
	var bnz := (nz + BRICK - 1) / BRICK
	var active_seed := PackedByteArray()
	active_seed.resize(bnx * bny * bnz)
	var b_stride_z := bnx * bny

	# Pre-sample coarse brick corner grid (bnx+1) x (bny+1) x (bnz+1)
	var cnx := bnx + 1; var cny := bny + 1; var cnz := bnz + 1
	var c_stride_y := cnx; var c_stride_z := cnx * cny
	var cf := PackedFloat32Array(); cf.resize(cnx * cny * cnz)
	var cpt := PackedFloat32Array(); cpt.resize(cnx * cnz)
	var cdv := PackedFloat32Array(); cdv.resize(cnx * cny * cnz)

	for cz_i in cnz:
		var wz := z_min + float(mini(cz_i * BRICK, nz)) * voxel
		for cx_i in cnx:
			var wx := x_min + float(mini(cx_i * BRICK, nx)) * voxel
			cpt[cz_i * cnx + cx_i] = float(eval_patch_t.call(wx, wz))
			for cy_i in cny:
				var wy := y_min + float(mini(cy_i * BRICK, ny)) * voxel
				var cidx := cz_i * c_stride_z + cy_i * c_stride_y + cx_i
				cf[cidx] = float(eval_field.call(wx, wy, wz))
				cdv[cidx] = float(eval_void.call(wx, wy, wz))

	for bz in bnz:
		var cz := z_min + (float(bz) + 0.5) * float(BRICK) * voxel
		for bx in bnx:
			var cx := x_min + (float(bx) + 0.5) * float(BRICK) * voxel
			var pt_min := minf(
				minf(cpt[bz * cnx + bx], cpt[bz * cnx + bx + 1]),
				minf(cpt[(bz + 1) * cnx + bx], cpt[(bz + 1) * cnx + bx + 1])
			)
			for by in bny:
				var f_min := 1e9; var f_max := -1e9; var dv_min := 1e9
				for dz in 2:
					for dy in 2:
						for dx in 2:
							var cidx := (bz + dz) * c_stride_z + (by + dy) * c_stride_y + (bx + dx)
							var fv := cf[cidx]
							f_min = minf(f_min, fv)
							f_max = maxf(f_max, fv)
							dv_min = minf(dv_min, cdv[cidx])
				var cy := y_min + (float(by) + 0.5) * float(BRICK) * voxel
				var fc := float(eval_field.call(cx, cy, cz))
				f_min = minf(f_min, fc)
				f_max = maxf(f_max, fc)
				dv_min = minf(dv_min, float(eval_void.call(cx, cy, cz)))
				if pt_min > 1.08 and dv_min > 4.2:
					continue
				if f_min <= 4.2 and f_max >= -4.2:
					active_seed[bz * b_stride_z + by * bnx + bx] = 1

	var active_mask := PackedByteArray()
	active_mask.resize(bnx * bny * bnz)
	for bz in bnz:
		for by in bny:
			for bx in bnx:
				if active_seed[bz * b_stride_z + by * bnx + bx] == 0:
					continue
				for dz in range(maxi(0, bz - 1), mini(bnz - 1, bz + 1) + 1):
					for dy in range(maxi(0, by - 1), mini(bny - 1, by + 1) + 1):
						for dx in range(maxi(0, bx - 1), mini(bnx - 1, bx + 1) + 1):
							active_mask[dz * b_stride_z + dy * bnx + dx] = 1

	var active_bricks: Array[Vector3i] = []
	for bz in bnz:
		for by in bny:
			for bx in bnx:
				if active_mask[bz * b_stride_z + by * bnx + bx] == 1:
					active_bricks.append(Vector3i(bx, by, bz))

	var field := PackedFloat32Array()
	field.resize(gx * gy * gz)
	for iz in gz:
		var row_th := iz * _th_gx
		for iy in gy:
			var y := y_min + float(iy) * voxel
			var base_idx := iz * stride_z + iy * stride_y
			for ix in gx:
				field[base_idx + ix] = clampf(_th_grid[row_th + ix] - y, -25.0, 25.0)
	var computed := PackedByteArray()
	computed.resize(gx * gy * gz)

	for bvec: Vector3i in active_bricks:
		var ix0 := bvec.x * BRICK
		var ix1 := mini(ix0 + BRICK, nx) + 1
		var iy0 := bvec.y * BRICK
		var iy1 := mini(iy0 + BRICK, ny) + 1
		var iz0 := bvec.z * BRICK
		var iz1 := mini(iz0 + BRICK, nz) + 1
		for iz in range(iz0, iz1):
			var z := z_min + float(iz) * voxel
			for iy in range(iy0, iy1):
				var y := y_min + float(iy) * voxel
				for ix in range(ix0, ix1):
					var idx := iz * stride_z + iy * stride_y + ix
					if computed[idx] == 1:
						continue
					computed[idx] = 1
					var x := x_min + float(ix) * voxel
					field[idx] = float(eval_field.call(x, y, z))

	var res := _extract_surfacenets(
		field, nx, ny, nz, gx, gy, gz,
		x_min, y_min, z_min, voxel,
		func(p: Vector3) -> bool:
			var pt := float(eval_patch_t.call(p.x, p.z))
			if pt > 0.99:
				var dv := float(eval_void.call(p.x, p.y, p.z))
				if dv > 2.2:
					return true
			return false,
		func(p: Vector3, _n: Vector3) -> bool:
			var pt := float(eval_patch_t.call(p.x, p.z))
			if pt > 1.01 and float(eval_void.call(p.x, p.y, p.z)) > 2.1:
				return false
			return true,
		eval_void,
		cfg["sky_open_dir"],
		cfg["pool_ys"],
		cfg["walk_ys"],
		cfg["mouth_xz"],
		true
	)

	var mesh: ArrayMesh = res["mesh"]
	var floor_faces: PackedVector3Array = res["floor_faces"]
	var wall_faces: PackedVector3Array = res["wall_faces"]

	var floor_shape := ConcavePolygonShape3D.new()
	floor_shape.backface_collision = false
	floor_shape.set_faces(floor_faces)

	var wall_shape := ConcavePolygonShape3D.new()
	wall_shape.backface_collision = true
	wall_shape.set_faces(wall_faces)

	var prefix := OUT_DIR + "/" + String(cfg["name"])
	var err_m := ResourceSaver.save(mesh, prefix + "_mesh.res", ResourceSaver.FLAG_COMPRESS)
	var err_f := ResourceSaver.save(floor_shape, prefix + "_floor_shape.res", ResourceSaver.FLAG_COMPRESS)
	var err_w := ResourceSaver.save(wall_shape, prefix + "_wall_shape.res", ResourceSaver.FLAG_COMPRESS)
	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	print("Baked %s in %.2f s: verts=%d floor_tris=%d wall_tris=%d (errs=%d,%d,%d)" % [
		String(cfg["name"]), dt, mesh.surface_get_array_len(0), floor_faces.size() / 3, wall_faces.size() / 3,
		err_m, err_f, err_w
	])
	return err_m == OK and err_f == OK and err_w == OK


func _extract_surfacenets(
	field: PackedFloat32Array,
	nx: int, ny: int, nz: int, gx: int, gy: int, gz: int,
	x_min: float, y_min: float, z_min: float, voxel: float,
	skip_cell_fn: Callable,
	keep_physics_tri_fn: Callable,
	eval_void: Callable,
	sky_open_dir: Vector3,
	pool_ys: Array,
	walk_ys: Array,
	mouth_xz: Vector2,
	is_subterranean_cave: bool
) -> Dictionary:
	var stride_y := gx
	var stride_z := gx * gy
	var c_stride_y := nx
	var c_stride_z := nx * ny
	var cell_vert := PackedInt32Array()
	cell_vert.resize(nx * ny * nz)
	cell_vert.fill(-1)

	var edge_a := [0, 2, 4, 6, 0, 1, 4, 5, 0, 1, 2, 3]
	var edge_b := [1, 3, 5, 7, 2, 3, 6, 7, 4, 5, 6, 7]
	var corner_pos: Array[Vector3] = []
	corner_pos.resize(8)
	var corner_val := PackedFloat32Array()
	corner_val.resize(8)

	var world_verts := PackedVector3Array()
	var vert_air_dirs := PackedVector3Array()

	for iz in nz:
		var z := z_min + float(iz) * voxel
		for iy in ny:
			var y := y_min + float(iy) * voxel
			for ix in nx:
				var cell_idx := iz * c_stride_z + iy * c_stride_y + ix
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

				var x := x_min + float(ix) * voxel
				var center := Vector3(x + voxel * 0.5, y + voxel * 0.5, z + voxel * 0.5)
				if bool(skip_cell_fn.call(center)):
					continue

				for c in 8:
					corner_pos[c] = Vector3(
						x + float(c & 1) * voxel,
						y + float((c >> 1) & 1) * voxel,
						z + float((c >> 2) & 1) * voxel
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

				var p_world := sum_p / float(cross_cnt)
				var gx_d := (corner_val[1] + corner_val[3] + corner_val[5] + corner_val[7]) \
						- (corner_val[0] + corner_val[2] + corner_val[4] + corner_val[6])
				var gy_d := (corner_val[2] + corner_val[3] + corner_val[6] + corner_val[7]) \
						- (corner_val[0] + corner_val[1] + corner_val[4] + corner_val[5])
				var gz_d := (corner_val[4] + corner_val[5] + corner_val[6] + corner_val[7]) \
						- (corner_val[0] + corner_val[1] + corner_val[2] + corner_val[3])
				var air_dir := Vector3(-gx_d, -gy_d, -gz_d)
				air_dir = air_dir.normalized() if air_dir.length_squared() > 1e-8 else Vector3.UP

				cell_vert[cell_idx] = world_verts.size()
				world_verts.append(p_world)
				vert_air_dirs.append(air_dir)

	# Pass 2: Gather quads across crossing interior grid edges
	var quad_verts := PackedInt32Array()
	var quad_dirs: Array[Vector3] = []
	for iz in range(1, nz):
		for iy in range(1, ny):
			for ix in range(1, nx):
				var c0 := iz * stride_z + iy * stride_y + ix
				var v0 := field[c0]

				var vx := field[c0 + 1]
				if (v0 < 0.0) != (vx < 0.0):
					var q0 := cell_vert[(iz - 1) * c_stride_z + (iy - 1) * c_stride_y + ix]
					var q1 := cell_vert[(iz - 1) * c_stride_z + iy * c_stride_y + ix]
					var q2 := cell_vert[iz * c_stride_z + iy * c_stride_y + ix]
					var q3 := cell_vert[iz * c_stride_z + (iy - 1) * c_stride_y + ix]
					if q0 >= 0 and q1 >= 0 and q2 >= 0 and q3 >= 0:
						quad_verts.append(q0); quad_verts.append(q1); quad_verts.append(q2); quad_verts.append(q3)
						quad_dirs.append(Vector3(-1.0 if v0 < 0.0 else 1.0, 0.0, 0.0))

				var vy := field[c0 + stride_y]
				if (v0 < 0.0) != (vy < 0.0):
					var q0 := cell_vert[(iz - 1) * c_stride_z + iy * c_stride_y + (ix - 1)]
					var q1 := cell_vert[iz * c_stride_z + iy * c_stride_y + (ix - 1)]
					var q2 := cell_vert[iz * c_stride_z + iy * c_stride_y + ix]
					var q3 := cell_vert[(iz - 1) * c_stride_z + iy * c_stride_y + ix]
					if q0 >= 0 and q1 >= 0 and q2 >= 0 and q3 >= 0:
						quad_verts.append(q0); quad_verts.append(q1); quad_verts.append(q2); quad_verts.append(q3)
						quad_dirs.append(Vector3(0.0, -1.0 if v0 < 0.0 else 1.0, 0.0))

				var vz := field[c0 + stride_z]
				if (v0 < 0.0) != (vz < 0.0):
					var q0 := cell_vert[iz * c_stride_z + (iy - 1) * c_stride_y + (ix - 1)]
					var q1 := cell_vert[iz * c_stride_z + iy * c_stride_y + (ix - 1)]
					var q2 := cell_vert[iz * c_stride_z + iy * c_stride_y + ix]
					var q3 := cell_vert[iz * c_stride_z + (iy - 1) * c_stride_y + ix]
					if q0 >= 0 and q1 >= 0 and q2 >= 0 and q3 >= 0:
						quad_verts.append(q0); quad_verts.append(q1); quad_verts.append(q2); quad_verts.append(q3)
						quad_dirs.append(Vector3(0.0, 0.0, -1.0 if v0 < 0.0 else 1.0))

	var vert_count := world_verts.size()
	var quad_count := quad_dirs.size()

	# 3-Pass Masked Laplacian Relaxation (keep floors flat/smooth, preserve crisp rock walls & ceilings)
	var relax_weights := PackedFloat32Array()
	relax_weights.resize(vert_count)
	for i in vert_count:
		var air_y := vert_air_dirs[i].y
		var floor_rw := 0.36
		var base_rw := lerpf(0.16, floor_rw, clampf((air_y - 0.25) / 0.55, 0.0, 1.0))
		relax_weights[i] = base_rw

	var nb_sum := PackedVector3Array()
	nb_sum.resize(vert_count)
	var nb_cnt := PackedInt32Array()
	nb_cnt.resize(vert_count)
	for _rp in 3:
		nb_sum.fill(Vector3.ZERO)
		nb_cnt.fill(0)
		for qi in quad_count:
			var b := qi * 4
			var q0 := quad_verts[b]; var q1 := quad_verts[b + 1]
			var q2 := quad_verts[b + 2]; var q3 := quad_verts[b + 3]
			var p0 := world_verts[q0]; var p1 := world_verts[q1]
			var p2 := world_verts[q2]; var p3 := world_verts[q3]
			nb_sum[q0] += p1 + p3; nb_cnt[q0] += 2
			nb_sum[q1] += p0 + p2; nb_cnt[q1] += 2
			nb_sum[q2] += p1 + p3; nb_cnt[q2] += 2
			nb_sum[q3] += p2 + p0; nb_cnt[q3] += 2
		for vi in vert_count:
			var cnt := nb_cnt[vi]
			if cnt > 0:
				var avg := nb_sum[vi] / float(cnt)
				world_verts[vi] = world_verts[vi].lerp(avg, relax_weights[vi])

	# Orient triangles + build smooth normals
	var indices := PackedInt32Array()
	var adj_sum := PackedVector3Array()
	adj_sum.resize(vert_count)
	var adj_cnt := PackedInt32Array()
	adj_cnt.resize(vert_count)

	for qi in quad_count:
		var b := qi * 4
		var q0 := quad_verts[b]; var q1 := quad_verts[b + 1]
		var q2 := quad_verts[b + 2]; var q3 := quad_verts[b + 3]
		var p0 := world_verts[q0]; var p1 := world_verts[q1]
		var p2 := world_verts[q2]; var p3 := world_verts[q3]

		adj_sum[q0] += p1 + p3; adj_cnt[q0] += 2
		adj_sum[q1] += p0 + p2; adj_cnt[q1] += 2
		adj_sum[q2] += p1 + p3; adj_cnt[q2] += 2
		adj_sum[q3] += p2 + p0; adj_cnt[q3] += 2

		var na0 := (p2 - p0).cross(p1 - p0).normalized()
		var na1 := (p3 - p0).cross(p2 - p0).normalized()
		var nb0 := (p3 - p1).cross(p2 - p1).normalized()
		var nb1 := (p0 - p1).cross(p3 - p1).normalized()
		if absf(na0.dot(na1)) >= absf(nb0.dot(nb1)):
			_append_tri_oriented(q0, q1, q2, quad_dirs[qi], world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel, indices)
			_append_tri_oriented(q0, q2, q3, quad_dirs[qi], world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel, indices)
		else:
			_append_tri_oriented(q1, q2, q3, quad_dirs[qi], world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel, indices)
			_append_tri_oriented(q1, q3, q0, quad_dirs[qi], world_verts, vert_air_dirs, field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel, indices)

	var normals := PackedVector3Array()
	normals.resize(vert_count)
	for i in range(0, indices.size(), 3):
		var ia := indices[i]; var ib := indices[i + 1]; var ic := indices[i + 2]
		var fn := (world_verts[ic] - world_verts[ia]).cross(world_verts[ib] - world_verts[ia])
		normals[ia] += fn; normals[ib] += fn; normals[ic] += fn
	for i in vert_count:
		var n := normals[i]
		normals[i] = n.normalized() if n.length_squared() > 1e-10 else Vector3.UP

	# Bake RGBA lighting & weathering vertex attributes matching landmark_rock.gdshader:
	# R = AO, G = SkyVis, B = Wetness, A = Curvature
	var colors := PackedColorArray()
	colors.resize(vert_count)
	var uvs := PackedVector2Array()
	uvs.resize(vert_count)

	for i in vert_count:
		var p := world_verts[i]
		var n := normals[i]
		var cnt := adj_cnt[i]
		var curv := 0.5
		if cnt > 0:
			var avg := adj_sum[i] / float(cnt)
			var lap := (p - avg).dot(n)
			curv = clampf(0.5 + lap * 1.45, 0.0, 1.0)

		var ao := clampf(0.50 + 0.42 * curv + 0.14 * maxf(n.y, 0.0), 0.16, 1.0)

		var sky_vis := 0.0
		if is_subterranean_cave:
			var th := _lookup_th(p.x, p.z)
			var dm := Vector2(p.x - mouth_xz.x, p.z - mouth_xz.y).length()
			# Exterior mound: only upward-facing slopes near terrain blend to meadow grass; steep cliff walls stay bare stone!
			var ext_sun := smoothstep(th - 1.2, th + 1.5, p.y) * smoothstep(mouth_xz.y - 14.0, mouth_xz.y - 2.0, p.z)
			var slope_up := lerpf(0.54, 1.0, smoothstep(0.40, 0.78, n.y))
			var m_fall := (1.0 - smoothstep(3.0, 18.0, dm)) * clampf(n.dot(sky_open_dir) * 0.55 + 0.30, 0.0, 0.68)
			sky_vis = clampf(maxf(ext_sun * slope_up, m_fall), 0.0, 1.0)
			if p.z < mouth_xz.y - 16.0:
				sky_vis *= 0.08
		else:
			# Wolf granite crag: mossy outer ridges sunlit, vertical faces stony, inner den cave ceiling dark & sheltered
			var into_den := clampf((-p.z - 3.5) / 8.0, 0.0, 1.0) * smoothstep(4.6, 1.6, p.y)
			sky_vis = clampf(lerpf(0.42, 0.96, smoothstep(0.25, 0.80, n.y)) * (1.0 - into_den * 0.88), 0.0, 1.0)

		var wet := 0.15
		for py: float in pool_ys:
			var dist_w := absf(p.y - py)
			if p.y < py + 1.3:
				wet = maxf(wet, (1.0 - smoothstep(0.0, 1.3, maxf(p.y - py, 0.0))) * 0.85)
		if is_subterranean_cave and n.y < -0.35:
			wet = maxf(wet, 0.32 * (1.0 - sky_vis))
		if not is_subterranean_cave:
			wet = maxf(0.08, (1.0 - sky_vis) * 0.38)

		colors[i] = Color(ao, sky_vis, clampf(wet, 0.0, 1.0), curv)
		uvs[i] = Vector2(p.x * 0.1, p.z * 0.1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = world_verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if is_subterranean_cave:
		mesh.custom_aabb = mesh.get_aabb().grow(4.0)

	# Split physics shapes: Floor (n.y >= 0.54, backface off) vs Wall/Ceiling (< 0.54, backface on)
	var floor_faces := PackedVector3Array()
	var wall_faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		var pa := world_verts[indices[i]]
		var pb := world_verts[indices[i + 1]]
		var pc := world_verts[indices[i + 2]]
		var tri_c := (pa + pb + pc) * (1.0 / 3.0)
		var fn := (pc - pa).cross(pb - pa)
		if fn.length_squared() < 1e-10:
			continue
		var fn_u := fn.normalized()
		if not bool(keep_physics_tri_fn.call(tri_c, fn_u)):
			continue
		if fn_u.y >= 0.54:
			floor_faces.append(pa); floor_faces.append(pb); floor_faces.append(pc)
		else:
			wall_faces.append(pa); wall_faces.append(pb); wall_faces.append(pc)

	return {
		"mesh": mesh,
		"floor_faces": floor_faces,
		"wall_faces": wall_faces,
	}


func _append_tri_oriented(
	ia: int, ib: int, ic: int,
	fallback_air: Vector3,
	world_verts: PackedVector3Array,
	vert_air_dirs: PackedVector3Array,
	field: PackedFloat32Array,
	gx: int, gy: int, gz: int, stride_y: int, stride_z: int,
	x_min: float, y_min: float, z_min: float, voxel: float,
	indices: PackedInt32Array
) -> void:
	var pa := world_verts[ia]
	var pb := world_verts[ib]
	var pc := world_verts[ic]
	var center := (pa + pb + pc) * (1.0 / 3.0)
	var eps := 0.32
	var gx_s := _sample_field(center + Vector3(eps, 0.0, 0.0), field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel) \
			- _sample_field(center - Vector3(eps, 0.0, 0.0), field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel)
	var gy_s := _sample_field(center + Vector3(0.0, eps, 0.0), field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel) \
			- _sample_field(center - Vector3(0.0, eps, 0.0), field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel)
	var gz_s := _sample_field(center + Vector3(0.0, 0.0, eps), field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel) \
			- _sample_field(center - Vector3(0.0, 0.0, eps), field, gx, gy, gz, stride_y, stride_z, x_min, y_min, z_min, voxel)
	var c_air := Vector3(-gx_s, -gy_s, -gz_s)
	var v_air := (vert_air_dirs[ia] + vert_air_dirs[ib] + vert_air_dirs[ic]) * 0.25
	var ref := c_air if c_air.length_squared() > 1e-6 else (v_air if v_air.length_squared() > 1e-6 else fallback_air)
	var fn := (pc - pa).cross(pb - pa)
	if fn.dot(ref) >= 0.0:
		indices.append(ia); indices.append(ib); indices.append(ic)
	else:
		indices.append(ia); indices.append(ic); indices.append(ib)


func _sample_field(
	p: Vector3, field: PackedFloat32Array,
	gx: int, gy: int, gz: int, stride_y: int, stride_z: int,
	x_min: float, y_min: float, z_min: float, voxel: float
) -> float:
	var fx := clampf((p.x - x_min) / voxel, 0.0, float(gx - 2))
	var fy := clampf((p.y - y_min) / voxel, 0.0, float(gy - 2))
	var fz := clampf((p.z - z_min) / voxel, 0.0, float(gz - 2))
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
