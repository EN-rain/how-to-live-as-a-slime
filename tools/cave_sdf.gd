class_name CaveSDF
extends RefCounted
## Analytical + noise-sculpted 3D Signed Distance Field for the world cave.
## Convention:
##   eval_sdf(u, y, s) < 0.0  =>  OPEN AIR (cave interior OR sky above karst hill)
##   eval_sdf(u, y, s) > 0.0  =>  SOLID LIMESTONE ROCK
##   eval_sdf(u, y, s) = 0.0  =>  CAVE / OUTCROP ROCK SURFACE (normal = -grad(sdf) points into air)

# Pre-flattened tunnel capsules: 9 floats per segment [ax, ay, az, bx, by, bz, half_w, h, lean]
var _seg_data := PackedFloat32Array()
var _seg_count := 0

# Pre-flattened split-crawlway segments: 8 floats per segment [ax, ay, az, bx, by, bz, half_w, h]
var _crawl_data := PackedFloat32Array()
var _crawl_count := 0

# Pre-flattened ledge ramp segments: 6 floats per segment [ax, ay, az, bx, by, bz]
var _ledge_data := PackedFloat32Array()
var _ledge_count := 0

# Pre-flattened chambers: 7 floats per chamber [cx, cy, cz, rx, rz, h, lean]
var _chamb_data := PackedFloat32Array()
var _chamb_count := 0

# Pre-flattened undercut alcoves & side pockets: 6 floats [cx, cy, cz, rx, ry, rz]
var _alcove_data := PackedFloat32Array()
var _alcove_count := 0

# Pre-flattened solid pillars / buttresses: 6 floats [ux, sz, y0, y1, r_bot, r_top]
var _pillar_data := PackedFloat32Array()
var _pillar_count := 0

var _noise_macro: FastNoiseLite
var _noise_fracture: FastNoiseLite


func _init(seed_val: int = 1337, config: CaveBakeConfig = null, layout_data: CaveLayoutData = null) -> void:
	var s_val := config.seed_val if config != null else seed_val
	_noise_macro = FastNoiseLite.new()
	_noise_macro.seed = s_val + 311
	_noise_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_macro.frequency = config.macro_frequency if config != null else 0.048
	_noise_macro.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_macro.fractal_octaves = config.macro_octaves if config != null else 2

	_noise_fracture = FastNoiseLite.new()
	_noise_fracture.seed = s_val + 887
	_noise_fracture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_fracture.frequency = config.fracture_frequency if config != null else 0.095
	_noise_fracture.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_fracture.fractal_octaves = config.fracture_octaves if config != null else 2

	_compile_primitives(layout_data)


func _compile_primitives(layout_data: CaveLayoutData = null) -> void:
	var tunnels_src: Dictionary = layout_data.tunnels if (layout_data != null and not layout_data.tunnels.is_empty()) else CaveLayout.TUNNELS
	var chambers_src: Dictionary = layout_data.chambers if (layout_data != null and not layout_data.chambers.is_empty()) else CaveLayout.CHAMBERS
	var ledge_src: Array = layout_data.ledge_route if (layout_data != null and not layout_data.ledge_route.is_empty()) else CaveLayout.LEDGE_ROUTE

	# 1. Main navigable passages (with bedding-plane lean for non-tubular asymmetry)
	var leans: Dictionary = layout_data.tunnel_leans if (layout_data != null and not layout_data.tunnel_leans.is_empty()) else {
		"twilight_passage": -0.22,
		"hall_throat": 0.18,
		"stream_grotto": -0.20,
		"deep_descent": -0.16,
		"lake_tunnel": 0.14,
		"door_tunnel": -0.12,
	}
	for tname: String in ["twilight_passage", "hall_throat", "stream_grotto", "deep_descent", "lake_tunnel", "lake_shoreline", "door_tunnel"]:
		if not tunnels_src.has(tname):
			continue
		var nodes: Array = tunnels_src[tname]
		var lean: float = float(leans.get(tname, 0.04))
		for i in range(nodes.size() - 1):
			var a: Dictionary = nodes[i]
			var b: Dictionary = nodes[i + 1]
			var pa: Vector3 = a["p"]
			var pb: Vector3 = b["p"]
			var hw := 0.5 * (float(a["w"]) + float(b["w"])) * 0.5
			var hh := 0.5 * (float(a["h"]) + float(b["h"]))
			_seg_data.append_array([pa.x, pa.y, pa.z, pb.x, pb.y, pb.z, hw, hh, lean])
			_seg_count += 1

	# 2. Calibrated Split-Slime Crawlway
	if tunnels_src.has("split_crawlway"):
		var cnodes: Array = tunnels_src["split_crawlway"]
		for i in range(cnodes.size() - 1):
			var a: Dictionary = cnodes[i]
			var b: Dictionary = cnodes[i + 1]
			var pa: Vector3 = a["p"]
			var pb: Vector3 = b["p"]
			var hw := 0.5 * (float(a["w"]) + float(b["w"])) * 0.5
			var hh := 0.5 * (float(a["h"]) + float(b["h"]))
			_crawl_data.append_array([pa.x, pa.y, pa.z, pb.x, pb.y, pb.z, hw, hh])
			_crawl_count += 1

	# 3. Chambers
	var ch_leans: Dictionary = layout_data.chamber_leans if (layout_data != null and not layout_data.chamber_leans.is_empty()) else {
		"breakdown_fork": -0.15,
		"collapse_hall": 0.14,
		"geode_pocket": -0.10,
		"abyssal_atrium": 0.08,
		"underground_lake": -0.12,
		"vault_sanctum": 0.0,
	}
	for cname: String in chambers_src:
		var ch: Dictionary = chambers_src[cname]
		var c: Vector3 = ch["c"]
		_chamb_data.append_array([c.x, c.y, c.z, float(ch["rx"]), float(ch["rz"]), float(ch["h"]), float(ch_leans.get(cname, 0.0))])
		_chamb_count += 1

	# 4. Asymmetric Undercut Alcoves, Overhangs & Ceiling Pockets (kills "pipe/dome" uniformity)
	var alcoves := [
		# Entrance mouth overhang pocket (tucked deeper inside twilight bend away from front arch wall)
		[-3.8, 26.5, 8.5, 4.2, 3.0, 4.2],
		# Twilight passage side dissolution pockets
		[4.5, 26.8, 16.0, 4.8, 3.6, 5.5],
		[-16.5, 25.5, 29.0, 5.5, 4.4, 6.2],
		# Collapse Hall irregular side bays & vaulted pockets
		[-84.0, 23.0, 66.0, 14.0, 11.0, 12.0],
		[-52.0, 22.0, 91.5, 13.0, 11.5, 9.5],  # Waterfall & Pool alcove
		[-72.0, 34.0, 78.0, 14.0, 9.0, 12.0],  # High asymmetric upper vault pocket (keeps thick roof cap)
		[-44.0, 29.0, 62.0, 11.0, 9.5, 11.0],
		# Stream Grotto undercut water-worn bank pockets
		[-28.0, 18.8, 102.0, 5.5, 3.2, 4.8],
		[-2.0, 17.8, 86.0, 5.0, 3.4, 5.8],
		# Abyssal Atrium & Deep Chambers side dissolution bays
		[49.5, 11.8, 110.0, 7.5, 5.5, 7.0],  # Abyssal Atrium east alcove
		[50.0, 10.8, 184.0, 9.5, 5.4, 8.2],  # Expanded Underground Lake ESE lagoon bay overhang
		[-31.0, 10.5, 139.0, 8.2, 5.2, 7.2],  # Expanded Underground Lake NNW grotto cove pocket
		[-182.0, 5.2, 82.0, 9.0, 6.5, 8.5],  # Vault Sanctum north alcove
	]
	if layout_data != null and not layout_data.alcoves.is_empty():
		for alc_d in layout_data.alcoves:
			if alc_d is Dictionary:
				var ac: Vector3 = alc_d["c"]
				_alcove_data.append_array([ac.x, ac.y, ac.z, float(alc_d["rx"]), float(alc_d["ry"]), float(alc_d["rz"])])
				_alcove_count += 1
	else:
		for alc: Array in alcoves:
			_alcove_data.append_array([float(alc[0]), float(alc[1]), float(alc[2]), float(alc[3]), float(alc[4]), float(alc[5])])
			_alcove_count += 1

	# 5. Solid Structural Buttresses framing the Collapse Hall nave
	var pillars := [
		[-35.0, 74.0, 17.0, 52.0, 4.4, 6.2], # East hall buttress framing Pool bay
		[-36.5, 59.5, 17.0, 50.0, 4.2, 5.8], # South-east hall shoulder flanking throat (keeps west spiral ledge clear)
	]
	if layout_data != null and not layout_data.pillars.is_empty():
		for pl_d in layout_data.pillars:
			if pl_d is Dictionary:
				_pillar_data.append_array([float(pl_d["u"]), float(pl_d["s"]), float(pl_d["y0"]), float(pl_d["y1"]), float(pl_d["r_bot"]), float(pl_d["r_top"])])
				_pillar_count += 1
	else:
		for pl: Array in pillars:
			_pillar_data.append_array([float(pl[0]), float(pl[1]), float(pl[2]), float(pl[3]), float(pl[4]), float(pl[5])])
			_pillar_count += 1

	# 6. Ledge route segments
	var lpts := ledge_src
	for i in range(lpts.size() - 1):
		var a: Vector3 = lpts[i]
		var b: Vector3 = lpts[i + 1]
		_ledge_data.append_array([a.x, a.y, a.z, b.x, b.y, b.z])
		_ledge_count += 1


# ==============================================================================
# SHARED OVERWORLD KARST HILL HEIGHT (used by both TerrainScene and CaveSDF)
# ==============================================================================

## Smooth polynomial min for organic rock/air blending.
static func smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / maxf(k, 1e-4), 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func smax(a: float, b: float, k: float) -> float:
	return -smin(-a, -b, k)


## Evaluates the karst hill height in cave-local (u, s) given underlying terrain base_h.
static func eval_karst_hill_height(u: float, s: float, base_h: float) -> float:
	var h := base_h

	# 1. Gently graded approach meadow leading smoothly up to Entrance Threshold (s in [-18, +3], |u| < 16)
	if s > -18.0 and s < 3.0 and absf(u) < 16.0:
		var ws := smoothstep(-18.0, -4.5, s) * (1.0 - smoothstep(-1.0, 3.0, s))
		var wu := 1.0 - smoothstep(6.0, 16.0, absf(u))
		h = lerpf(h, CaveLayout.ORIGIN.y, ws * wu)

	# 2. Broad, natural limestone karst hill rising gradually behind the entrance over
	#    Twilight Passage, Collapse Hall, Geode Pocket, Abyssal Atrium, Underground Lake & Vault Sanctum.
	var du_hill := (u + 68.0) / 172.0
	var ds_hill := (s - 108.0) / 145.0
	var r2_hill := du_hill * du_hill + ds_hill * ds_hill
	if r2_hill < 1.85:
		var dome_w := 1.0 - smoothstep(0.92, 1.80, r2_hill)
		var shoulder_delay := smoothstep(8.0, 48.0, absf(u)) * 12.0
		var cliff_front := smoothstep(-2.0 + shoulder_delay, 34.0 + shoulder_delay, s)
		var target_hill := clampf(CaveLayout.MOUNTAIN_SURFACE_OVER_HALL + 4.5 * sin(u * 0.045) * cos(s * 0.04), 52.0, 62.5)
		h = lerpf(h, maxf(h, target_hill), dome_w * cliff_front)

	# 3. Natural limestone portal brow above Entrance Mouth (thick solid overburden over s = 0..14
	#    Twilight Passage ceiling before the hillside rises behind it).
	#    Wide, bell-shaped shoulders whose front lip recedes with |u| and whose flanks fall off smoothly,
	#    so the outcrop reads as one continuous hillside instead of a detached rectangular slab.
	var du_brow := u / 38.0
	var ds_brow := (s - 9.0) / 21.0
	var d2_brow := du_brow * du_brow + ds_brow * ds_brow
	if d2_brow < 1.0:
		var bell := 1.0 - smoothstep(0.10, 1.0, d2_brow)
		var lip_recede := smoothstep(4.0, 30.0, absf(u))
		var front_start := -2.5 + 15.0 * lip_recede
		var front_ramp := 5.0 + 11.0 * lip_recede
		var brow_w := bell * smoothstep(front_start, front_start + front_ramp, s)
		var mouth_opening := (1.0 - smoothstep(4.2, 6.8, absf(u))) * (1.0 - smoothstep(-3.5, 0.2, s))
		brow_w *= (1.0 - mouth_opening)
		var asym := 0.8 * sin(u * 0.25) * cos(s * 0.20)
		var target_brow := clampf(41.8 + asym, 40.5, 43.2)
		h = lerpf(h, maxf(h, target_brow), brow_w)

	# 4. Gentle karst basin right at the Skylight Rim (-62, 68) so ledge route exits flush at y ~ 56 m
	var sky_c_hill: Vector3 = CaveLayout.SKYLIGHT["c"]
	var d_sky: float = Vector2(u - sky_c_hill.x, s - sky_c_hill.z).length()
	if d_sky < 18.0:
		var sky_w := 1.0 - smoothstep(6.0, 18.0, d_sky)
		h = lerpf(h, CaveLayout.MOUNTAIN_SURFACE_OVER_HALL - 0.5, sky_w)

	return h


## Evaluates whether a world heightfield quad overlaps either the Entrance Outcrop core
## or the Skylight Rim opening (both continuously bridged & sealed by the baked SDF mesh).
static func is_quad_in_cave_cutout(v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3) -> bool:
	var cx := 0.25 * (v00.x + v10.x + v01.x + v11.x)
	var cz := 0.25 * (v00.z + v10.z + v01.z + v11.z)
	var cl := CaveLayout.to_local(Vector3(cx, 0.0, cz))
	if cl.x < -235.0 or cl.x > 85.0 or cl.z < -45.0 or cl.z > 245.0:
		return false

	# A. Skylight Rim + Spiral Ledge exit ramp cutout (matched to eval_sky_patch_t < 0.60)
	if eval_sky_patch_t(cl.x, cl.z) < 0.60:
		return true

	# B. Entrance Mouth Arch cutout: matched to mouth surface patch boundary (0.64)
	# so uncut Terrain overlaps CaveShell's flush 0.62..0.74 collar with zero gap.
	if eval_mouth_patch_t(cl.x, cl.z) < 0.64:
		return true

	return false


static func is_in_overworld_scatter_exclusion(wx: float, wz: float, is_grass: bool = false) -> bool:
	var p := CaveLayout.to_local(Vector3(wx, 0.0, wz))
	if is_grass:
		# Grass avoids the cave mouth rock floor and a narrow footpath leading in,
		# while growing lushly right up to the rock arch flanks and brow!
		if p.z >= -4.0 and p.z <= 10.0 and absf(p.x) < 5.0:
			return true
		if p.z >= -18.0 and p.z < -4.0 and absf(p.x) < 2.8:
			return true
	else:
		# Keep random overworld trees/boulders off the Entrance Outcrop rock & mouth plaza.
		var box_half_u := 22.0
		var box_s_min := -18.0
		var box_s_max := 28.0
		if p.z > box_s_min and p.z < box_s_max and absf(p.x) < box_half_u:
			return true
		# Clear a narrow rocky trail in front of the mouth (trees/boulders keep a wider sightline corridor)
		if p.z >= -38.0 and p.z <= box_s_min:
			var t_trail := clampf((box_s_min - p.z) / (box_s_min + 38.0), 0.0, 1.0)
			var half_w := 9.0
			if absf(p.x) < half_w:
				return true

	# Keep random trees/grass/vegetation out of the Skylight opening, rock collar, and Spiral Ledge exit ramp
	if is_grass:
		if eval_sky_patch_t(p.x, p.z) < 0.60:
			return true
	else:
		var sky_c_ex: Vector3 = CaveLayout.SKYLIGHT["c"]
		var ds: float = Vector2(p.x - sky_c_ex.x, p.z - sky_c_ex.z).length()
		if ds < 16.5:
			return true
		if p.x > -65.0 and p.x < -45.0 and p.z > 61.0 and p.z < 77.0:
			return true
	return false


# ==============================================================================
# CORE 3D SIGNED DISTANCE FIELD EVALUATION
# ==============================================================================

## Asymmetric flat-floored karst passage segment SDF (< 0 inside tunnel air).
func _sd_karst_segment(u: float, y: float, s: float, idx9: int) -> float:
	var ax := _seg_data[idx9]
	var ay := _seg_data[idx9 + 1]
	var az := _seg_data[idx9 + 2]
	var bx := _seg_data[idx9 + 3]
	var by := _seg_data[idx9 + 4]
	var bz := _seg_data[idx9 + 5]
	var hw := _seg_data[idx9 + 6]
	var hh := _seg_data[idx9 + 7]
	var lean := _seg_data[idx9 + 8]

	var abx := bx - ax
	var abz := bz - az
	var len2 := abx * abx + abz * abz
	var t := clampf(((u - ax) * abx + (s - az) * abz) / maxf(len2, 1e-5), 0.0, 1.0)

	var px := ax + abx * t
	var py := ay + (by - ay) * t
	var pz := az + abz * t

	var dx := u - px
	var dz := s - pz
	# Signed lateral offset perpendicular to segment direction for asymmetric bedding lean
	var seg_len := sqrt(maxf(len2, 1e-5))
	var lat := (dx * (-abz) + dz * abx) / seg_len
	var along := maxf(absf(dx * abx + dz * abz) / seg_len - 0.0, 0.0)
	var rad_horiz := sqrt(dx * dx + dz * dz)

	var dy := y - py
	# Shift upper arch laterally by lean * dy to create natural overhanging wall on one side!
	var lat_shifted := lat - clampf(dy, 0.0, hh) * lean
	var eff_horiz := sqrt(lat_shifted * lat_shifted + maxf(rad_horiz * rad_horiz - lat * lat, 0.0))

	var nx := eff_horiz / hw
	var ny := maxf(dy, 0.0) / hh
	var d_arch := (sqrt(nx * nx + ny * ny) - 1.0) * minf(hw, hh)
	var dish := 0.35 * (1.0 - clampf(nx * nx, 0.0, 1.0))
	var d_floor := -(dy + dish)
	var _unused := along
	return smax(d_arch, d_floor, 0.90)


## Asymmetric flat-floored chamber dome SDF (< 0 inside chamber air).
func _sd_chamber(u: float, y: float, s: float, idx7: int) -> float:
	var cx := _chamb_data[idx7]
	var cy := _chamb_data[idx7 + 1]
	var cz := _chamb_data[idx7 + 2]
	var rx := _chamb_data[idx7 + 3]
	var rz := _chamb_data[idx7 + 4]
	var hh := _chamb_data[idx7 + 5]
	var lean := _chamb_data[idx7 + 6]

	var dy := y - cy
	var du := (u - cx) - clampf(dy, 0.0, hh) * lean
	var ds := s - cz
	var nh := sqrt((du / rx) * (du / rx) + (ds / rz) * (ds / rz))
	var scale_r := minf(minf(rx, rz), hh)

	var ny := maxf(dy, 0.0) / hh
	var d_dome := (sqrt(nh * nh + ny * ny) - 1.0) * scale_r
	var dish := 0.45 * (1.0 - clampf(nh * nh, 0.0, 1.0))
	var d_floor := -(dy + dish)
	return smax(d_dome, d_floor, 1.15)


## Calibrated Split-Slime Crawlway segment (< 0 inside bore).
## Uses vertical barrel-vault lower walls up to dy = 1.45 m and C0-continuous floor blend
## so full slimes (diam 4.08 m) hit solid wall while split slimes (scale <= 0.79) fit cleanly.
func _sd_crawl_segment(u: float, y: float, s: float, idx8: int) -> float:
	var ax := _crawl_data[idx8]
	var ay := _crawl_data[idx8 + 1]
	var az := _crawl_data[idx8 + 2]
	var bx := _crawl_data[idx8 + 3]
	var by := _crawl_data[idx8 + 4]
	var bz := _crawl_data[idx8 + 5]
	var hw := _crawl_data[idx8 + 6]
	var hh := _crawl_data[idx8 + 7]

	var abx := bx - ax
	var abz := bz - az
	var len2 := abx * abx + abz * abz
	var t := clampf(((u - ax) * abx + (s - az) * abz) / maxf(len2, 1e-5), 0.0, 1.0)
	var px := ax + abx * t
	var py := ay + (by - ay) * t
	var pz := az + abz * t

	var r_xz := sqrt((u - px) * (u - px) + (s - pz) * (s - pz))
	var dy := y - py
	var nx := r_xz / hw
	var ny := maxf(dy - 1.45, 0.0) / maxf(hh - 1.45, 0.5)
	var d_arch := (sqrt(nx * nx + ny * ny) - 1.0) * minf(hw, hh)
	return smax(d_arch, -dy, 0.22)


## Analytical subterranean cave air SDF (< 0 inside cave void, > 0 in rock), WITHOUT surface noise.
## Used directly by coarse brick culling and combined with noise in eval_sdf_full().
func eval_cave_void_smooth(u: float, y: float, s: float) -> float:
	var d := 1e6

	# 1. Chambers
	for i in _chamb_count:
		var dc := _sd_chamber(u, y, s, i * 7)
		d = dc if i == 0 else smin(d, dc, 3.2)

	# 2. Main passages
	for i in _seg_count:
		var ds := _sd_karst_segment(u, y, s, i * 9)
		d = smin(d, ds, 2.6)

	# 3. Asymmetric undercut alcoves & side pockets (carve laterally & upward without digging deep floor pits)
	for i in _alcove_count:
		var b := i * 6
		var nx := (u - _alcove_data[b]) / _alcove_data[b + 3]
		var dy_a := y - _alcove_data[b + 1]
		var ry_up := _alcove_data[b + 4]
		var ry_down := minf(ry_up * 0.34, 3.4)
		var ny := dy_a / (ry_up if dy_a >= 0.0 else ry_down)
		var nz := (s - _alcove_data[b + 2]) / _alcove_data[b + 5]
		var da := (sqrt(nx * nx + ny * ny + nz * nz) - 1.0) * minf(_alcove_data[b + 3], ry_down)
		d = smin(d, da, 2.2)

	# 4. Subtract SOLID geological masses inside the hall (mound, fork rubble, pillars, spiral ledge shelf)
	# 4a. Breakdown Mound directly under the Skylight
	var mound_c: Vector3 = CaveLayout.MOUND["c"]
	var md_xz: float = Vector2(u - mound_c.x, s - mound_c.z).length()
	if md_xz < 16.5:
		var mound_top: float = mound_c.y + float(CaveLayout.MOUND["rise"]) * (1.0 - smoothstep(0.0, float(CaveLayout.MOUND["r"]), md_xz))
		var d_mound_solid := y - mound_top # < 0 inside solid mound
		d = smax(d, -d_mound_solid, 1.4)

	# 4b. Rubble Ramp Crest at Breakdown Fork (tapers smoothly into hall_throat without a step cliff)
	var rub_c: Vector3 = CaveLayout.RUBBLE_CREST["c"]
	var rd_xz: float = Vector2(u - rub_c.x, s - rub_c.z).length()
	var rub_r: float = float(CaveLayout.RUBBLE_CREST["r"])
	if rd_xz < rub_r * 1.65:
		var t_rub := clampf(rd_xz / rub_r, 0.0, 1.65)
		var rub_top := rub_c.y - 0.2 + float(CaveLayout.RUBBLE_CREST["rise"]) * (1.0 - smoothstep(0.0, 1.0, minf(t_rub, 1.0))) - maxf(t_rub - 0.72, 0.0) * 5.6
		d = smax(d, -(y - rub_top), 1.35)

	# 4c. Solid Fluted Rock Buttresses / Columns in Collapse Hall
	for i in _pillar_count:
		var b := i * 6
		var px := _pillar_data[b]
		var pz := _pillar_data[b + 1]
		var y0 := _pillar_data[b + 2]
		var y1 := _pillar_data[b + 3]
		var r_bot := _pillar_data[b + 4]
		var r_top := _pillar_data[b + 5]
		var tv := clampf((y - y0) / maxf(y1 - y0, 1.0), 0.0, 1.0)
		var du_p := u - px
		var ds_p := s - pz
		var ang := atan2(ds_p, du_p)
		# Natural non-periodic fluted rock buttress (wider anchored base, asymmetric ribs, flared ceiling arch)
		var flute := 1.0 + 0.14 * sin(ang * 3.0 + float(i) * 1.7 + y * 0.06) + 0.08 * cos(ang * 5.0 - y * 0.04)
		var waist := lerpf(r_bot, r_top, tv) * (0.86 + 0.28 * pow(tv - 0.35, 2.0)) * flute
		var d_pil := sqrt(du_p * du_p + ds_p * ds_p) - waist
		d = smax(d, -d_pil, 2.4)

	# 4d. Spiral Wall Ledge Solid Shelf + Guaranteed Walkable Headroom Gallery
	# Evaluate closest-polyline smooth height so segment end-caps never undercut rising corners!
	var lw_half := CaveLayout.LEDGE_WIDTH * 0.5 + 0.6
	var lh := CaveLayout.LEDGE_HEADROOM + 0.7
	var r_ledge_min := 1e6
	var w_ledge_sum := 0.0
	var py_ledge_sum := 0.0
	for i in _ledge_count:
		var b := i * 6
		var ax := _ledge_data[b]
		var ay := _ledge_data[b + 1]
		var az := _ledge_data[b + 2]
		var bx := _ledge_data[b + 3]
		var by := _ledge_data[b + 4]
		var bz := _ledge_data[b + 5]
		var abx := bx - ax
		var abz := bz - az
		var len2 := abx * abx + abz * abz
		var t := clampf(((u - ax) * abx + (s - az) * abz) / maxf(len2, 1e-5), 0.0, 1.0)
		var px := ax + abx * t
		var py := ay + (by - ay) * t
		var pz := az + abz * t
		var r_xz := sqrt((u - px) * (u - px) + (s - pz) * (s - pz))
		r_ledge_min = minf(r_ledge_min, r_xz)
		var w := exp(-clampf(r_xz, 0.0, 30.0) * 1.35)
		w_ledge_sum += w
		py_ledge_sum += w * py

	var py_ledge := py_ledge_sum / maxf(w_ledge_sum, 1e-8)
	var shelf_x := r_ledge_min - lw_half
	var shelf_y := maxf(y - py_ledge, (py_ledge - 10.5) - y)
	var d_ledge_shelf := maxf(shelf_x, shelf_y)

	var dy_l := y - py_ledge
	var nx_l := r_ledge_min / lw_half
	var ny_l := maxf(dy_l - 1.8, 0.0) / maxf(lh - 1.8, 0.5)
	var dl_arch := (sqrt(nx_l * nx_l + ny_l * ny_l) - 1.0) * minf(lw_half, lh)
	var sky_c_lg: Vector3 = CaveLayout.SKYLIGHT["c"]
	var r_sky_lg := Vector2(u - (sky_c_lg.x - 0.8), s - sky_c_lg.z).length()
	var roof_cap_y := maxf(py_ledge + 4.8, lerpf(60.0, 50.8, smoothstep(6.2, 9.2, r_sky_lg)))
	var d_ledge_air := smax(smax(dl_arch, -dy_l, 0.35), y - roof_cap_y, 0.8)

	d = smax(d, -d_ledge_shelf, 1.05)
	d = smin(d, d_ledge_air, 0.65)

	# 5. Carved Pool Basin & Shallow Stream Bed
	var pool_c: Vector3 = CaveLayout.POOL["c"]
	var pool_rx: float = float(CaveLayout.POOL["rx"])
	var pool_rz: float = float(CaveLayout.POOL["rz"])
	var pu: float = (u - pool_c.x) / pool_rx
	var ps: float = (s - pool_c.z) / pool_rz
	var pr := sqrt(pu * pu + ps * ps)
	if pr < 1.25:
		var pool_bot: float = pool_c.y
		var pool_top: float = float(CaveLayout.POOL["water_y"]) + 2.5
		var dy_pool := maxf(pool_bot - y, y - pool_top)
		var d_pool := maxf((pr - 1.0) * pool_rz, dy_pool)
		d = smin(d, d_pool, 1.4)

	# 5b. Carved Expanded Multi-Cove Subterranean Lake Basin: Multi-Tier Karst Bathymetry + Deep Abyssal Shard Trench
	var lake_c: Vector3 = CaveLayout.UNDERGROUND_LAKE["c"]
	var lake_rx: float = float(CaveLayout.UNDERGROUND_LAKE["rx"])
	var lake_rz: float = float(CaveLayout.UNDERGROUND_LAKE["rz"])
	var lu: float = (u - lake_c.x) / lake_rx
	var ls: float = (s - lake_c.z) / lake_rz
	var lr_raw := sqrt(lu * lu + ls * ls)
	if lr_raw < 1.78:
		var lake_theta := atan2(ls, lu)
		var shore_scale := CaveLayout.lake_shore_radius_scale(lake_theta)
		var lr := lr_raw / shore_scale
		if lr < 1.38:
			var water_y: float = float(CaveLayout.UNDERGROUND_LAKE["water_y"])
			var lake_top: float = water_y + 2.8
			var shore_floor_y: float = 7.50 # Walkable 360-deg organic shoreline pathway flush with lake_shoreline (y=7.5)
			var pen_w := smoothstep(0.95, 0.55, shore_scale)
			var shelf_in := lerpf(0.84, 0.68, pen_w)
			var shelf_warp := 0.045 * sin(u * 0.24 + s * 0.19) + 0.032 * cos(u * 0.17 - s * 0.29)
			var t_shore := smoothstep(shelf_in, 1.01, lr + shelf_warp * (1.0 - smoothstep(0.88, 1.01, lr)))

			# Non-flat sculpted karst lake floor: diagonal limestone ridges, channels & stepped strata terraces
			var ridge_nw_se := 0.85 * sin(u * 0.145 + s * 0.095 + 0.6 * cos(s * 0.07))
			var ridge_cross := 0.58 * cos(u * 0.115 - s * 0.165 + 0.5 * sin(u * 0.09))
			var shoal_ripple := 0.34 * sin(u * 0.31 - s * 0.24) * cos(u * 0.19 + s * 0.27)
			var raw_bed := 3.95 + ridge_nw_se + ridge_cross + shoal_ripple
			# Carved stepped travertine/limestone terrace bands + submerged shoal shoulders
			raw_bed += 0.24 * sin(raw_bed * 3.8 + 0.8 * sin(u * 0.12 - s * 0.10))
			var d_ese := Vector2((u - 25.5) / 15.0, (s - 180.0) / 11.8).length()
			raw_bed -= 1.15 * (1.0 - smoothstep(0.32, 1.05, d_ese))
			# Two subtle submerged stone shoal outcrops (stay <= 5.45m safely under water_y=6.40)
			var sh1 := exp(-Vector2((u + 27.5) / 5.5, (s - 160.5) / 4.8).length_squared()) * 0.95
			var sh2 := exp(-Vector2((u - 28.0) / 5.2, (s - 164.0) / 4.6).length_squared()) * 0.85
			raw_bed += sh1 + sh2

			# Deep Abyssal Crystal Trench ("Abyssal Pit") dropping steeply through rock terraces down to y ~ 1.40m
			var pit_c: Vector3 = CaveLayout.LAKE_ABYSS_PIT["c"]
			var pit_rx: float = float(CaveLayout.LAKE_ABYSS_PIT["rx"])
			var pit_rz: float = float(CaveLayout.LAKE_ABYSS_PIT["rz"])
			var pit_yaw: float = float(CaveLayout.LAKE_ABYSS_PIT["yaw"])
			var cy_p := cos(pit_yaw)
			var sy_p := sin(pit_yaw)
			var pu_raw := u - pit_c.x
			var ps_raw := s - pit_c.z
			var pu_rot := (pu_raw * cy_p + ps_raw * sy_p) / pit_rx
			var ps_rot := (-pu_raw * sy_p + ps_raw * cy_p) / pit_rz
			var pit_ang := atan2(ps_rot, pu_rot)
			var pit_warp := 1.0 + 0.14 * sin(pit_ang * 3.0 + 0.9) + 0.08 * cos(pit_ang * 5.0 - 1.4)
			var dp_pit := sqrt(pu_rot * pu_rot + ps_rot * ps_rot) / pit_warp
			var pit_w := (1.0 - smoothstep(0.45, 1.14, dp_pit)) * (1.0 - smoothstep(0.55, 0.85, t_shore))
			var pit_floor := pit_c.y + 0.28 * sin(u * 0.34 - s * 0.27) + 0.16 * cos(u * 0.52 + s * 0.41)
			var lake_bot := lerpf(raw_bed, pit_floor, pit_w)
			# Subtle fractured karst rim lip bracketing the deep sinkhole edge
			lake_bot += 0.24 * exp(-pow((dp_pit - 0.90) / 0.15, 2.0)) * (1.0 - t_shore)
			lake_bot = clampf(lake_bot, 1.25, 5.70)

			var basin_floor := lerpf(lake_bot, shore_floor_y, t_shore)
			var dy_lake := maxf(basin_floor - y, y - lake_top)
			var d_lake := maxf((lr - 1.22) * minf(lake_rx, lake_rz) * shore_scale, dy_lake)
			d = smin(d, d_lake, 1.4)
			# Prevent chained smin blends at shoreline junctions from scooping submerged trenches < 7.35 m
			var clamp_fade := 1.0 - smoothstep(1.20, 1.34, lr)
			if clamp_fade > 0.001:
				var d_shore_bedrock := (basin_floor - 0.12) - y
				d = lerpf(d, smax(d, d_shore_bedrock, 0.45), clamp_fade)

	# 5c. Asymmetric Karst Lagoon Features: off-center fluted sea-stack islet & low rocky reef shoal
	var stack_u := -17.0
	var stack_s := 167.5
	var st_du := u - stack_u
	var st_ds := s - stack_s
	var st_r2 := st_du * st_du + st_ds * st_ds
	if st_r2 < 120.0:
		var st_tv := clampf((y - 2.0) / 27.5, 0.0, 1.0)
		var st_ang := atan2(st_ds, st_du)
		var st_flute := 1.0 + 0.16 * sin(st_ang * 3.0 + 1.8 + y * 0.08) + 0.09 * cos(st_ang * 5.0 - y * 0.05)
		var st_waist := lerpf(4.4, 5.4, st_tv) * (0.80 + 0.34 * pow(st_tv - 0.38, 2.0)) * st_flute
		var d_stack := sqrt(st_r2) - st_waist
		d = smax(d, -d_stack, 2.0)

	var reef_u := 10.0
	var reef_s := 176.0
	var rf_du := u - reef_u
	var rf_ds := s - reef_s
	var rf_r2 := rf_du * rf_du + rf_ds * rf_ds
	if rf_r2 < 90.0:
		var rf_ang := atan2(rf_ds, rf_du)
		var rf_rad := 5.2 * (1.0 + 0.18 * sin(rf_ang * 3.0 - 0.7) + 0.10 * cos(rf_ang * 4.0 + 1.2))
		var rf_r := sqrt(rf_r2)
		var rf_top := 8.15 - 2.2 * smoothstep(2.2, rf_rad, rf_r) + 0.25 * sin(u * 0.45 + s * 0.35)
		var d_reef_solid := maxf(y - rf_top, rf_r - rf_rad)
		d = smax(d, -d_reef_solid, 1.15)

	# 6. Flared Cenote Skylight Chimney (punches from Collapse Hall dome straight through karst roof)
	if y > 36.0:
		var sky_c_ch: Vector3 = CaveLayout.SKYLIGHT["c"]
		var sky_r: float = float(CaveLayout.SKYLIGHT["r"]) + smoothstep(46.0, 58.0, y) * 1.3
		var sky_u: float = u - (sky_c_ch.x - 0.8 * smoothstep(46.0, 56.0, y)) + (y - 48.0) * 0.04
		var sky_s: float = s - sky_c_ch.z
		var d_sky_cyl := maxf(Vector2(sky_u, sky_s).length() - sky_r, 38.0 - y)
		d = smin(d, d_sky_cyl, 2.4)

	# 7. Calibrated Split-Slime Crawlway (carved last so rubble/walls never choke its bore)
	var d_crawl := 1e6
	for i in _crawl_count:
		d_crawl = minf(d_crawl, _sd_crawl_segment(u, y, s, i * 8))
	d = smin(d, d_crawl, 0.45)

	# 8. Solid limestone bedrock safety floor safely below deepest Vault Sanctum dish (y=1.55m) and Y_MIN=-1.0m
	var min_bedrock := 0.6
	d = smax(d, min_bedrock - y, 0.8)

	return d


## Distance to the Split-Slime Crawlway bore (used to keep its 3.74m x 3.02m calibration noise-free).
func dist_to_crawlway(u: float, y: float, s: float) -> float:
	var d := 1e6
	for i in _crawl_count:
		d = minf(d, _sd_crawl_segment(u, y, s, i * 8))
	return d


## Distance to the Spiral Ledge walkable air gallery (used to keep ledge gallery walls from pinching).
func dist_to_ledge_air(u: float, y: float, s: float) -> float:
	var lw_half := CaveLayout.LEDGE_WIDTH * 0.5 + 0.6
	var lh := CaveLayout.LEDGE_HEADROOM + 0.7
	var r_ledge_min := 1e6
	var w_ledge_sum := 0.0
	var py_ledge_sum := 0.0
	for i in _ledge_count:
		var b := i * 6
		var ax := _ledge_data[b]
		var ay := _ledge_data[b + 1]
		var az := _ledge_data[b + 2]
		var bx := _ledge_data[b + 3]
		var by := _ledge_data[b + 4]
		var bz := _ledge_data[b + 5]
		var abx := bx - ax
		var abz := bz - az
		var len2 := abx * abx + abz * abz
		var t := clampf(((u - ax) * abx + (s - az) * abz) / maxf(len2, 1e-5), 0.0, 1.0)
		var px := ax + abx * t
		var py := ay + (by - ay) * t
		var pz := az + abz * t
		var r_xz := sqrt((u - px) * (u - px) + (s - pz) * (s - pz))
		r_ledge_min = minf(r_ledge_min, r_xz)
		var w := exp(-clampf(r_xz, 0.0, 30.0) * 1.35)
		w_ledge_sum += w
		py_ledge_sum += w * py
	var py_ledge := py_ledge_sum / maxf(w_ledge_sum, 1e-8)
	var dy_l := y - py_ledge
	var nx_l := r_ledge_min / lw_half
	var ny_l := maxf(dy_l - 1.8, 0.0) / maxf(lh - 1.8, 0.5)
	var dl_arch := (sqrt(nx_l * nx_l + ny_l * ny_l) - 1.0) * minf(lw_half, lh)
	return smax(dl_arch, -dy_l, 0.35)


static func eval_mouth_patch_t(u: float, s: float) -> float:
	var du := absf(u) / 16.5
	var ds := absf(s - 3.5) / 13.5
	var warp := 0.025 * sin(u * 0.23 + s * 0.17) + 0.015 * cos(u * 0.37 - s * 0.29)
	return pow(du * du * du + ds * ds * ds, 1.0 / 3.0) + warp


static func eval_sky_patch_t(u: float, s: float) -> float:
	var sky_c_pt: Vector3 = CaveLayout.SKYLIGHT["c"]
	var d_sky := Vector2(u - (sky_c_pt.x - 0.8), s - sky_c_pt.z).length() / 18.0
	var d_exit := Vector2(u - (-53.0), s - 70.0).length() / 10.5
	return minf(d_sky, d_exit)


## Normalized distance (< 1.0 inside the Entrance Outcrop or Skylight Rim surface patches).
static func eval_surface_patch_t(u: float, s: float) -> float:
	return minf(eval_mouth_patch_t(u, s), eval_sky_patch_t(u, s))


## Full SDF including exterior Outcrop / Skylight surface blend and geological fracture/scallop relief.
## `karst_h` is the overworld karst hill height at (u, s).
func eval_sdf_full(u: float, y: float, s: float, karst_h: float) -> float:
	var d_cave := eval_cave_void_smooth(u, y, s)

	# Continuous union of subterranean cave air and open sky air at Entrance & Skylight surface patches.
	# Holds a slight +0.04m collar across the cutout edge (0.56..0.70) so Terrain never hovers above CaveShell,
	# then tucks cleanly beneath Terrain across 0.70..0.94.
	var patch_t := eval_surface_patch_t(u, s)
	var rim_collar := 0.04 * smoothstep(0.52, 0.60, patch_t) * (1.0 - smoothstep(0.68, 0.76, patch_t))
	var skirt_drop := smoothstep(0.70, 0.94, patch_t) * 3.80 - rim_collar
	var d_sky_air := (karst_h - skirt_drop) - y # < 0 above ground (air), > 0 underground (rock)
	# Keep smin k tight around the entire Entrance Rim, mouth floor, and Skylight Rim so rims stay flush with terrain
	var mouth_floor_w := (1.0 - smoothstep(-1.5, 2.5, s)) * (1.0 - smoothstep(28.0, 30.5, y))
	var mouth_pt := eval_mouth_patch_t(u, s)
	var mouth_rim_w := smoothstep(0.45, 0.58, mouth_pt) * (1.0 - smoothstep(0.72, 0.88, mouth_pt))
	var sky_rim_w := smoothstep(44.0, 51.0, y) * (1.0 - smoothstep(0.42, 0.72, eval_sky_patch_t(u, s)))
	var k_union := lerpf(2.0, 0.18, maxf(maxf(mouth_floor_w, mouth_rim_w), sky_rim_w * 0.92))
	var d := smin(d_cave, d_sky_air, k_union)

	# Skip expensive 3D noise far from the zero-isosurface
	if absf(d) > 3.2:
		return d

	# Protect the Split-Slime Crawlway bore from noise narrowing/widening
	var dc := dist_to_crawlway(u, y, s)
	var crawl_calm := smoothstep(-0.2, 1.8, dc)
	if crawl_calm <= 0.01:
		return d

	# Keep Spiral Ledge gallery walls organic (~25% relief) without ever pinching the walkable ramp
	var dl := dist_to_ledge_air(u, y, s)
	var ledge_calm := 0.22 + 0.78 * smoothstep(-0.3, 2.2, dl)

	# Calm noise on flat walkable floors AND outer overlap skirt (so seams stay razor-flush)
	var d_cave_up := eval_cave_void_smooth(u, y + 0.8, s)
	var d_sky_up := (karst_h - skirt_drop) - (y + 0.8)
	var d_up := smin(d_cave_up, d_sky_up, 2.0)
	var up_grad := clampf((d - d_up) / 0.8, -1.0, 1.0) # > 0 when normal points +Y (walkable floor)
	# Keep dry walkable trails smooth, while preserving rich 3D rock fractures & limestone relief on the submerged lakebed
	var sub_lake := smoothstep(6.05, 5.05, y) * smoothstep(128.0, 138.0, s) * smoothstep(-58.0, -48.0, u)
	var floor_atten := lerpf(0.88, 0.42, sub_lake)
	# Calm high vaulted lake dome noise (> 10.0m) to avoid wasting thousands of hidden ceiling triangles
	var lake_ceil_calm := 1.0 - 0.85 * smoothstep(10.0, 13.8, y) * smoothstep(128.0, 138.0, s) * smoothstep(-62.0, -52.0, u)
	var wall_ceil_weight := (1.0 - floor_atten * smoothstep(0.30, 0.80, up_grad)) * (1.0 - smoothstep(0.50, 0.64, patch_t) * smoothstep(0.0, 0.55, up_grad)) * lake_ceil_calm

	# 1. Broad water-worn phreatic scallops & dissolution pockets
	var n_mac := _noise_macro.get_noise_3d(u * 1.1, y * 1.35, s * 1.1)
	# 2. Smooth ridged limestone relief & subtle warped bedding (zero Voronoi singularities)
	var n_frac := _noise_fracture.get_noise_3d(u * 0.9, y * 1.15, s * 0.9)
	var strata := sin(y * 0.85 + n_mac * 2.2 + u * 0.10 - s * 0.08) * (0.12 + 0.12 * sub_lake)

	var disp := (n_mac * 1.15 + (n_frac - 0.5) * (0.55 + 0.30 * sub_lake) + strata) * wall_ceil_weight * crawl_calm * ledge_calm
	if up_grad > 0.15 and patch_t > 0.50 and sub_lake < 0.05:
		disp = minf(disp, -0.02 * smoothstep(0.52, 0.68, patch_t))
	return d + disp
