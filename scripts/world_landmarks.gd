class_name WorldLandmarks
extends RefCounted
## Single source of truth for the Skeleton Dungeon Cave, Wolf Pack Crag,
## Spider Silk Forest (Webwood), and Underground Rat Warren coordinates,
## terrain grading/cutouts, analytical subterranean floor queries, and web slow zones.

# ==============================================================================
# CANONICAL OVERWORLD LANDMARK ANCHORS
# ==============================================================================

## Second Cave: Skeleton Crypt Sunken Stairwell & Subterranean Dungeon (~878 m WSW of Crystal Cave)
const SKEL_CAVE_MOUTH := Vector2(-820.0, 326.0)
const SKEL_FORECOURT_Y := 26.0
const SKEL_UPPER_Y := 8.0
const SKEL_SANCTUM_Y := 4.0
const SKEL_CUTOUT_MIN := Vector2(-826.5, 304.0)
const SKEL_CUTOUT_MAX := Vector2(-813.5, 327.0)
const SKEL_SUBDIV_MIN := Vector2(-858.0, 286.0)
const SKEL_SUBDIV_MAX := Vector2(-782.0, 354.0)
const SKEL_BOX_MIN := Vector2(-876.0, 204.0)
const SKEL_BOX_MAX := Vector2(-764.0, 336.0)

## Underground Rat Warren (Expanded Surface Burrow Approach -> Winding Multi-Loop Under-Empire)
## Relocated from the (-240, 280) roadway into the deepwoods east of Webwood.
## RAT_WARREN_BAKED/OFFSET define the frame of the baked rat_warren_* assets and
## all interior prop coordinates; world position = baked + OFFSET.
const RAT_WARREN_MOUTH := Vector2(-235.0, 415.0)
const RAT_WARREN_BAKED := Vector2(-240.0, 280.0)
const RAT_WARREN_OFFSET := RAT_WARREN_MOUTH - RAT_WARREN_BAKED
const RAT_FORECOURT_Y := 22.0
const RAT_SWAMP_WATER_Y := 21.38
const RAT_VAULT_Y := 14.5
const RAT_SANCTUM_Y := 10.0
const RAT_CUTOUT_MIN := Vector2(-238.8, 404.5)
const RAT_CUTOUT_MAX := Vector2(-231.2, 414.0)
const RAT_SUBDIV_MIN := Vector2(-316.0, 378.0)
const RAT_SUBDIV_MAX := Vector2(-154.0, 532.0)
const RAT_BOX_MIN := Vector2(-291.0, 309.0)
const RAT_BOX_MAX := Vector2(-179.0, 425.0)

## Spider Silk Forest (Webwood Domain, SW towering haunted webwood, ~656 m SW of Crystal Cave)
const SPIDER_FOREST_CENTER := Vector2(-410.0, 480.0)
const SPIDER_TRAIL_START := Vector2(-335.0, 390.0)
const SPIDER_TRAIL_BEND := Vector2(-396.0, 468.0)
const SPIDER_NEST_SNAGS: Array[Vector2] = [Vector2(-12, -6), Vector2(2, -13), Vector2(12, 2), Vector2(5, 13), Vector2(-8, 9)]
const SPIDER_FOREST_RADIUS := 165.0
const SPIDER_TERRITORY_RADIUS := 125.0
const SPIDER_LEASH_RADIUS := 158.0
const SPIDER_NEST_SATELLITES: Array[Vector2] = [
	Vector2(-362.0, 405.0),  # North Trail Ambush Nest
	Vector2(-498.0, 466.0),  # West Deepwood Nest
	Vector2(-416.0, 566.0),  # South Ridge Nest
	Vector2(-328.0, 514.0),  # East Hollow Nest
]

## Wolf Pack Crag (Howlcrest Pine Grove, NE Pine Foothills, ~365 m ENE of Crystal Cave)
const WOLF_CRAG_CENTER := Vector2(290.0, -240.0)
const WOLF_GROVE_RADIUS := 105.0
const WOLF_TERRITORY_RADIUS := 54.0
const WOLF_LEASH_RADIUS := 105.0

## Spider Sticky Ground Web patches inside Webwood Forest (populated at runtime by TerritoryBuilder)
## Each entry: {"xz": Vector2, "radius": float}
static var sticky_web_zones: Array[Dictionary] = []


# ==============================================================================
# TERRAIN GRADING & PORTAL CUTOUTS
# ==============================================================================

static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if edge1 < edge0:
		return 1.0 - _smoothstep(edge1, edge0, x)
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 1e-6), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Smoothly grades heightfield plateaus/hill mounds around Skeleton Cave, Rat Warren,
## Wolf Pack Crag, and Spider Forest Glade while keeping spatial early-out cost tiny.
static func apply_landmark_terrain_grading(x: float, z: float, base_h: float, webwood_center: Vector2 = SPIDER_FOREST_CENTER) -> float:
	var h := base_h

	# 1. Skeleton Crypt Sunken Stairwell Plaza (level necropolis courtyard at y=26.0, NO artificial hill!)
	if x > -892.0 and x < -748.0 and z > 195.0 and z < 395.0:
		var d_fc := Vector2(x - SKEL_CAVE_MOUTH.x, z - 320.0).length()
		var fc_blend := 1.0 - _smoothstep(22.0, 56.0, d_fc)
		h = lerpf(h, SKEL_FORECOURT_Y, fc_blend)
		# Keep natural terrain over subterranean dungeon footprint >= 25.5m so vaults stay >= 5.5m underground
		if x > -878.0 and x < -762.0 and z > 202.0 and z < 312.0:
			h = maxf(h, 25.5)

	# 2. Expanded Rat Warren Sunken Swamp Ruins Basin, Causeway Saddle & Over-Cave Forested Ridge
	var bx := x - RAT_WARREN_OFFSET.x
	var bz := z - RAT_WARREN_OFFSET.y
	if bx > -378.0 and bx < -102.0 and bz > 158.0 and bz < 462.0:
		var web_guard := _smoothstep(22.0, 48.0, Vector2(x + 328.0, z - 514.0).length())
		var dx_b := bx - RAT_WARREN_BAKED.x
		var d_ruin := Vector2(dx_b / 104.0, (bz - 336.0) / 106.0).length()
		var rc_blend := (1.0 - _smoothstep(0.52, 1.0, d_ruin)) * web_guard
		h = lerpf(h, RAT_FORECOURT_Y, rc_blend)

		# Carve winding, organic shoreline fen channels & bog lagoons (radial-lobed perimeter = zero rectangular borders!)
		if bz > 282.0 and bz < 438.0 and absf(dx_b) < 98.0:
			var ang := atan2(bz - 342.0, dx_b)
			var shore_lobe := 1.0 + 0.14 * sin(ang * 3.0 + 0.55) + 0.09 * cos(ang * 5.0 - 0.9) + 0.06 * sin(dx_b * 0.055 + bz * 0.045)
			var ell_r := Vector2(dx_b / 68.0, (bz - 342.0) / 56.0).length() / shore_lobe
			var outer_fade := (1.0 - _smoothstep(0.62, 1.04, ell_r)) * _smoothstep(282.0, 294.0, bz) * web_guard
			var d_core_plaza := maxf(absf(dx_b) / 14.5, absf(bz - 304.0) / 21.0)
			var keep_plaza := 1.0 - _smoothstep(0.86, 1.18, d_core_plaza)
			var keep_causeway := (1.0 - _smoothstep(5.2, 8.6, absf(dx_b))) * _smoothstep(278.0, 286.0, bz) * (1.0 - _smoothstep(378.0, 395.0, bz))
			var keep_west_hall := 1.0 - _smoothstep(0.78, 1.18, Vector2((bx - (RAT_WARREN_BAKED.x - 33.5)) / 10.5, (bz - 308.0) / 13.5).length())
			var keep_east_hall := 1.0 - _smoothstep(0.78, 1.18, Vector2((bx - (RAT_WARREN_BAKED.x + 31.5)) / 10.5, (bz - 306.0) / 13.5).length())
			var keep_barbican := 1.0 - _smoothstep(0.76, 1.15, Vector2(dx_b / 13.0, (bz - 354.5) / 8.5).length())
			var dry_island := clampf(maxf(maxf(keep_plaza, keep_causeway), maxf(maxf(keep_west_hall, keep_east_hall), keep_barbican)), 0.0, 1.0)
			var cistern_slot := (1.0 - _smoothstep(2.4, 4.6, absf(dx_b + 8.0))) * _smoothstep(282.0, 286.0, bz) * (1.0 - _smoothstep(293.0, 298.0, bz))
			dry_island = clampf(dry_island - cistern_slot * 0.92, 0.0, 1.0)
			var swamp_mask := outer_fade * (1.0 - dry_island)
			if swamp_mask > 0.002:
				var hummock := sin(bx * 0.13 + bz * 0.09) * cos(bx * 0.07 - bz * 0.12)
				var bog_target := (RAT_SWAMP_WATER_Y - 0.56) + hummock * 0.42
				h = lerpf(h, bog_target, swamp_mask)

		var rx := (bx - RAT_WARREN_BAKED.x) / 76.0
		var rz := (bz - 220.0) / 58.0
		var rd := sqrt(rx * rx + rz * rz)
		if rd < 1.35:
			var r_dome := 1.0 - _smoothstep(0.28, 1.30, rd)
			var r_crest := RAT_FORECOURT_Y + 8.6 * r_dome
			if bz > 262.0:
				r_crest = lerpf(r_crest, RAT_FORECOURT_Y, _smoothstep(262.0, 280.0, bz))
			h = maxf(h, r_crest)
		# Keep terrain safely >= 30.5m over the subterranean multi-loop Rat Warren chambers with smooth X/Z falloff
		if bx > -312.0 and bx < -168.0 and bz > 164.0 and bz < 280.0:
			var x_cov := 1.0 - _smoothstep(38.0, 70.0, absf(bx - RAT_WARREN_BAKED.x))
			var z_cov := (1.0 - _smoothstep(256.0, 279.0, bz)) * _smoothstep(166.0, 184.0, bz)
			h = maxf(h, lerpf(RAT_FORECOURT_Y, 30.5, x_cov * z_cov))

	# 3. Spider Webwood Forest (Central R=14m gently smoothed glade matching local ridge ~54.5m)
	if absf(x - webwood_center.x) < 58.0 and absf(z - webwood_center.y) < 58.0:
		var d_sf := Vector2(x - webwood_center.x, z - webwood_center.y).length()
		if d_sf < 48.0:
			var sf_w := (1.0 - _smoothstep(14.0, 48.0, d_sf)) * 0.65
			h = lerpf(h, 54.5, sf_w)

	# 4. Wolf Pack Crag (Level R=16m den clearing ~77.5m + horseshoe granite ridge amphitheater behind & flanking the den)
	if x > 215.0 and x < 365.0 and z > -315.0 and z < -165.0:
		var rel_w := Vector2(x - WOLF_CRAG_CENTER.x, z - WOLF_CRAG_CENTER.y)
		var d_wf := rel_w.length()
		if d_wf < 64.0:
			var wf_w := (1.0 - _smoothstep(16.0, 62.0, d_wf)) * 0.78
			h = lerpf(h, 77.5, wf_w)
		# Sculpt U-shaped alpine crag amphitheater rising behind the den (z < -244) and flanking spurs
		if d_wf > 15.0 and d_wf < 62.0:
			var north_arc := _smoothstep(-241.0, -258.0, z)
			var flank_spurs := clampf((absf(rel_w.x) - 14.0) / 18.0, 0.0, 1.0) * (1.0 - _smoothstep(-226.0, -214.0, z))
			var ridge_env := clampf(maxf(north_arc, flank_spurs * 0.75), 0.0, 1.0) * _smoothstep(15.0, 26.0, d_wf) * (1.0 - _smoothstep(38.0, 60.0, d_wf))
			h += ridge_env * (5.2 + 1.8 * sin(x * 0.14 + z * 0.11))

	return h


## Returns true if a terrain quad overlaps the Skeleton Cave mouth or Rat Sinkhole mouth.
static func is_quad_in_extra_cutout(v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3) -> bool:
	var cx := 0.25 * (v00.x + v10.x + v01.x + v11.x)
	var cz := 0.25 * (v00.z + v10.z + v01.z + v11.z)
	if cx >= SKEL_CUTOUT_MIN.x and cx <= SKEL_CUTOUT_MAX.x and cz >= SKEL_CUTOUT_MIN.y and cz <= SKEL_CUTOUT_MAX.y:
		return true
	if cx >= RAT_CUTOUT_MIN.x and cx <= RAT_CUTOUT_MAX.x and cz >= RAT_CUTOUT_MIN.y and cz <= RAT_CUTOUT_MAX.y:
		return true
	return false


## Excludes surface trees, rocks, vegetation, and grass from cave cutouts, entry paths, and Wolf/Spider inner cores.
static func is_in_landmark_exclusion(x: float, z: float, is_grass: bool = false, webwood_center: Vector2 = SPIDER_FOREST_CENTER) -> bool:
	# Skeleton Crypt Sunken Stairwell & Necropolis Courtyard
	if x >= -845.0 and x <= -795.0 and z >= 298.0 and z <= 355.0:
		if x >= -829.5 and x <= -810.5 and z >= 301.0 and z <= 343.0:
			return true
		if not is_grass and Vector2(x - SKEL_CAVE_MOUTH.x, z - 322.0).length() < 20.0:
			return true
		if is_grass and x >= -832.0 and x <= -808.0 and z >= 325.0 and z <= 339.0:
			return true

	# Rat Warren Expanded Surface Sunken Swamp Ruins Complex, Piers, Causeway & Burrow Mouth
	var rbx := x - RAT_WARREN_OFFSET.x
	var rbz := z - RAT_WARREN_OFFSET.y
	if rbx >= -304.0 and rbx <= -176.0 and rbz >= 256.0 and rbz <= 392.0:
		if not is_grass:
			return true
		if (rbx >= -251.5 and rbx <= -228.5 and rbz >= 278.5 and rbz <= 326.5) \
				or (rbx >= -247.0 and rbx <= -233.0 and rbz >= 326.5 and rbz <= 382.0) \
				or (rbx >= -278.5 and rbx <= -251.0 and rbz >= 294.0 and rbz <= 322.0) \
				or (rbx >= -229.0 and rbx <= -202.0 and rbz >= 290.0 and rbz <= 322.0) \
				or (rbx >= -246.0 and rbx <= -234.0 and rbz >= 274.0 and rbz <= 284.0):
			return true

	# Inner Wolf Den Clearing & Approach Trail Corridor (keep inner 19.5m clear of trees/rocks, inner clearing + den hollow clear of grass)
	var d_wolf_c := Vector2(x - WOLF_CRAG_CENTER.x, z - WOLF_CRAG_CENTER.y).length()
	var d_wolf_hollow := Vector2(x - WOLF_CRAG_CENTER.x, z - (WOLF_CRAG_CENTER.y - 4.8)).length()
	var w_trail_ab := Vector2(28.0, -20.0)
	var w_trail_t := clampf((Vector2(x, z) - Vector2(262.0, -216.0)).dot(w_trail_ab) / w_trail_ab.length_squared(), 0.0, 1.0)
	var w_trail_d := Vector2(x, z).distance_to(Vector2(262.0, -216.0) + w_trail_ab * w_trail_t)
	if (not is_grass and (d_wolf_c < 19.5 or w_trail_d < 4.8)) or (is_grass and (d_wolf_c < 12.5 or d_wolf_hollow < 12.8)):
		return true

	# Leave room for the broodmother, not a bare disk around the entire nest.
	var d_spider_c := Vector2(x - webwood_center.x, z - webwood_center.y).length()
	if (not is_grass and d_spider_c < 11.0) or (is_grass and d_spider_c < 4.5):
		return true

	return false


static func is_in_extra_subdiv_box(x0: float, x1: float, z0: float, z1: float) -> bool:
	var in_skel := x1 > SKEL_SUBDIV_MIN.x and x0 < SKEL_SUBDIV_MAX.x and z1 > SKEL_SUBDIV_MIN.y and z0 < SKEL_SUBDIV_MAX.y
	if in_skel:
		return true
	var in_rat := x1 > RAT_SUBDIV_MIN.x and x0 < RAT_SUBDIV_MAX.x and z1 > RAT_SUBDIV_MIN.y and z0 < RAT_SUBDIV_MAX.y
	if in_rat:
		return true
	var in_spider := x1 > -445.0 and x0 < -375.0 and z1 > 445.0 and z0 < 515.0
	if in_spider:
		return true
	return x1 > 230.0 and x0 < 350.0 and z1 > -305.0 and z0 < -180.0


# ==============================================================================
# SUBTERRANEAN FLOOR SUPPORT & ATMOSPHERE QUERIES
# ==============================================================================

## True when (x, z, foot_y) is inside the Skeleton Cave or Rat Warren cutout/subterranean chambers.
static func is_in_extra_cave(x: float, z: float, foot_y: float, overworld_h: float) -> bool:
	if x >= SKEL_CUTOUT_MIN.x and x <= SKEL_CUTOUT_MAX.x and z >= SKEL_CUTOUT_MIN.y and z <= SKEL_CUTOUT_MAX.y + 1.5:
		return true
	if x >= SKEL_BOX_MIN.x and x <= SKEL_BOX_MAX.x and z >= SKEL_BOX_MIN.y and z <= SKEL_BOX_MAX.y:
		if foot_y < overworld_h - 2.0:
			return true

	if x >= RAT_CUTOUT_MIN.x and x <= RAT_CUTOUT_MAX.x and z >= RAT_CUTOUT_MIN.y and z <= RAT_CUTOUT_MAX.y + 1.5:
		return true
	if x >= RAT_BOX_MIN.x and x <= RAT_BOX_MAX.x and z >= RAT_BOX_MIN.y and z <= RAT_BOX_MAX.y:
		if foot_y < overworld_h - 2.0:
			return true

	return false


## Analytical walkable floor surface inside the Skeleton Crypt (matching stairwell & chamber slabs).
## Layout (local to SKEL_CAVE_MOUTH x = -820):
##   z = 326 -> 298: Sunken Stairwell Descent (y = 26.0 -> 8.0)
##   z = 268 -> 300, x in [-835, -805]: Pillar Atrium (y = 8.0)
##   z = 256 -> 290, x in [-862, -835]: West Flooded Cistern & Squeeze Vault (y = 8.0)
##   z = 256 -> 290, x in [-805, -778]: East Ossuary & Spike Wing (y = 8.0)
##   z = 252 -> 268, x in [-826, -814]: Sanctum Stairway (y = 8.0 -> 4.0)
##   z = 212 -> 252, x in [-840, -800]: Skeleton Overlord Sanctum (y = 4.0)
static func sample_skeleton_cave_floor(x: float, z: float) -> Vector4:
	# Sunken stone staircase descending north from courtyard y=26 (z=326) down to atrium y=8 (z=298)
	if z >= 298.0 and z <= 330.0 and absf(x - SKEL_CAVE_MOUTH.x) <= 7.0:
		var t := clampf((326.0 - z) / 28.0, 0.0, 1.0)
		var y := lerpf(SKEL_FORECOURT_Y, SKEL_UPPER_Y, t)
		var slope_dz := (SKEL_UPPER_Y - SKEL_FORECOURT_Y) / 28.0
		var n := Vector3(0.0, 1.0, -slope_dz).normalized()
		return Vector4(n.x, n.y, n.z, y)

	# Sanctum stairs descending from Atrium y=8 (z=268) to Sanctum y=4 (z=252)
	if z >= 252.0 and z <= 268.0 and absf(x - SKEL_CAVE_MOUTH.x) <= 6.5:
		var t2 := clampf((268.0 - z) / 16.0, 0.0, 1.0)
		var y2 := lerpf(SKEL_UPPER_Y, SKEL_SANCTUM_Y, t2)
		var slope_dz2 := (SKEL_SANCTUM_Y - SKEL_UPPER_Y) / 16.0
		var n2 := Vector3(0.0, 1.0, -slope_dz2).normalized()
		return Vector4(n2.x, n2.y, n2.z, y2)

	# Boss Sanctum lower chamber
	if z < 252.0:
		return Vector4(0.0, 1.0, 0.0, SKEL_SANCTUM_Y)

	# Atrium + West Cistern + East Ossuary mid tier
	return Vector4(0.0, 1.0, 0.0, SKEL_UPPER_Y)


## Analytical walkable floor surface inside the Expanded Underground Rat Warren:
##   z = 278 -> 258: Sloped sinkhole burrow descent (y = 22.0 -> 14.5)
##   z = 232 -> 258: Sunken Crossroads Confluence + West Sump + East Burrow Nest (y = 14.5)
##   z = 232 -> 203: Winding Split NW/NE Burrow Loops (y = 14.5 -> 10.0)
##   z < 203: Rat King's Deep Brood Hollow (y = 10.0, dais 11.45)
static func sample_rat_warren_floor(z: float, x: float = -240.0) -> Vector4:
	var bz := z - RAT_WARREN_OFFSET.y if z >= 295.0 else z
	var bx := x - RAT_WARREN_OFFSET.x if z >= 295.0 else x
	if bz >= 258.0 and bz <= 284.0:
		var t := clampf((278.0 - bz) / 20.0, 0.0, 1.0)
		var y := lerpf(RAT_FORECOURT_Y, RAT_VAULT_Y, t)
		var slope_dz := (RAT_VAULT_Y - RAT_FORECOURT_Y) / 20.0
		var n := Vector3(0.0, 1.0, -slope_dz).normalized()
		return Vector4(n.x, n.y, n.z, y)
	if bz >= 203.0 and bz <= 232.0:
		var ts := clampf((232.0 - bz) / 29.0, 0.0, 1.0)
		var ys := lerpf(RAT_VAULT_Y, RAT_SANCTUM_Y, ts)
		var sd := (RAT_SANCTUM_Y - RAT_VAULT_Y) / 29.0
		var ns := Vector3(0.0, 1.0, -sd).normalized()
		return Vector4(ns.x, ns.y, ns.z, ys)
	if bz < 203.0:
		var plateau_w := (1.0 - _smoothstep(7.5, 11.5, absf(bx - RAT_WARREN_BAKED.x))) * _smoothstep(190.0, 185.0, bz)
		return Vector4(0.0, 1.0, 0.0, RAT_SANCTUM_Y + 1.45 * plateau_w)
	if bx > -199.5 and bz > 233.0 and bz < 250.0:
		var shelf_w := _smoothstep(-199.5, -196.5, bx)
		return Vector4(0.0, 1.0, 0.0, RAT_VAULT_Y + 1.50 * shelf_w)
	return Vector4(0.0, 1.0, 0.0, RAT_VAULT_Y)


static func sample_extra_cave_floor(x: float, z: float, foot_y: float, overworld_h: float) -> Vector4:
	if x >= SKEL_BOX_MIN.x and x <= SKEL_BOX_MAX.x and z >= SKEL_BOX_MIN.y and z <= SKEL_BOX_MAX.y + 6.0:
		if (x >= SKEL_CUTOUT_MIN.x and x <= SKEL_CUTOUT_MAX.x and z >= SKEL_CUTOUT_MIN.y and z <= SKEL_CUTOUT_MAX.y + 1.5) or foot_y < overworld_h - 2.0:
			return sample_skeleton_cave_floor(x, z)
	if x >= RAT_BOX_MIN.x and x <= RAT_BOX_MAX.x and z >= RAT_BOX_MIN.y and z <= RAT_BOX_MAX.y + 6.0:
		if (x >= RAT_CUTOUT_MIN.x and x <= RAT_CUTOUT_MAX.x and z >= RAT_CUTOUT_MIN.y and z <= RAT_CUTOUT_MAX.y + 1.5) or foot_y < overworld_h - 2.0:
			return sample_rat_warren_floor(z, x)
	return Vector4(0.0, 1.0, 0.0, overworld_h)


## Returns atmospheric darkening weight [0, 1] for CaveAtmosphere inside Skeleton Cave or Rat Warren.
static func eval_underground_atmosphere(cam_pos: Vector3) -> float:
	var factor := 0.0

	# Skeleton Crypt deep interior (z <= 316, x in [-872, -768], y < 23)
	if cam_pos.x >= -872.0 and cam_pos.x <= -768.0 and cam_pos.z >= 204.0 and cam_pos.z <= 324.0 and cam_pos.y < 23.0:
		var in_z := _smoothstep(316.0, 298.0, cam_pos.z)
		var in_y := 1.0 - _smoothstep(18.0, 24.5, cam_pos.y)
		factor = maxf(factor, in_z * in_y)

	# Rat Warren interior (baked bz <= 278, bx in [-294, -186], y < 26.5)
	var rbx := cam_pos.x - RAT_WARREN_OFFSET.x
	var rbz := cam_pos.z - RAT_WARREN_OFFSET.y
	if rbx >= -294.0 and rbx <= -186.0 and rbz >= 174.0 and rbz <= 282.0 and cam_pos.y < 26.5:
		var in_rz := _smoothstep(280.0, 264.0, rbz)
		var in_ry := 1.0 - _smoothstep(22.0, 26.0, cam_pos.y)
		factor = maxf(factor, in_rz * in_ry)

	return clampf(factor, 0.0, 1.0)


## Returns true if the world XZ coordinate is inside a Spider Sticky Ground Web patch.
static func is_in_sticky_web(pos: Vector3) -> bool:
	if sticky_web_zones.is_empty():
		return false
	if absf(pos.x - SPIDER_FOREST_CENTER.x) > SPIDER_FOREST_RADIUS or absf(pos.z - SPIDER_FOREST_CENTER.y) > SPIDER_FOREST_RADIUS:
		return false
	var px := Vector2(pos.x, pos.z)
	for z in sticky_web_zones:
		var c: Vector2 = z["xz"]
		var r: float = float(z["radius"])
		if px.distance_squared_to(c) <= r * r:
			return true
	return false


## Friendly HUD location label when inside one of the new landmarks.
static func describe_zone(pos: Vector3, overworld_h: float, webwood_center: Vector2 = SPIDER_FOREST_CENTER) -> String:
	if pos.x >= SKEL_BOX_MIN.x and pos.x <= SKEL_BOX_MAX.x and pos.z >= SKEL_BOX_MIN.y and pos.z <= SKEL_BOX_MAX.y + 8.0:
		if pos.y < overworld_h - 1.5 or (pos.x >= -828.0 and pos.x <= -812.0 and pos.z >= 303.0 and pos.z <= 328.0 and pos.y < 27.5):
			if pos.z >= 300.0:
				return "Skeleton Crypt · Sunken Stairwell"
			elif pos.z < 252.0:
				return "Skeleton Cave · Overlord Sanctum"
			elif pos.x < -835.0:
				return "Skeleton Cave · Flooded Cistern"
			elif pos.x > -805.0:
				return "Skeleton Cave · Ossuary Crypt"
			return "Skeleton Cave · Pillar Atrium"
	if pos.x >= RAT_BOX_MIN.x and pos.x <= RAT_BOX_MAX.x and pos.z >= RAT_BOX_MIN.y and pos.z <= RAT_BOX_MAX.y + 6.0 and pos.y < overworld_h - 1.5:
		var rbx := pos.x - RAT_WARREN_OFFSET.x
		var rbz := pos.z - RAT_WARREN_OFFSET.y
		if rbz < 215.0:
			return "Rat Warren · King's Deep Brood Hollow"
		elif rbx < -256.0:
			return "Rat Warren · West Sump & Cistern"
		elif rbx > -224.0:
			return "Rat Warren · East Root Larder"
		return "Rat Warren · Winding Burrows"
	if Vector2(pos.x - RAT_WARREN_MOUTH.x, pos.z - (RAT_WARREN_MOUTH.y + 42.0)).length() <= 94.0:
		return "Sunken Swamp Ruins · Rat Territory"
	if Vector2(pos.x - webwood_center.x, pos.z - webwood_center.y).length() <= 68.0:
		return "Webwood Spider Forest"
	if Vector2(pos.x - WOLF_CRAG_CENTER.x, pos.z - WOLF_CRAG_CENTER.y).length() <= 82.0:
		return "Howlcrest Wolf Territory"
	return ""
