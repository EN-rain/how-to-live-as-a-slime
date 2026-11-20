class_name WorldLandmarks
extends RefCounted
## Single source of truth for the Skeleton Dungeon Cave, Wolf Pack Crag,
## Spider Silk Forest (Webwood), and Underground Rat Warren coordinates,
## terrain grading/cutouts, analytical subterranean floor queries, and web slow zones.

# ==============================================================================
# CANONICAL OVERWORLD LANDMARK ANCHORS
# ==============================================================================

## Second Cave: Skeleton Catacombs Highland Barrow Portal & Procedural Multi-Room Dungeon (~878 m WSW of Crystal Cave)
const SKEL_CAVE_MOUTH := Vector2(-820.0, 326.0)
const SKEL_FORECOURT_Y := 26.0
const SKEL_UPPER_Y := 14.0
const SKEL_MID_Y := 10.0
const SKEL_SANCTUM_Y := 5.0
const SKEL_CUTOUT_MIN := Vector2(-826.5, 313.5)
const SKEL_CUTOUT_MAX := Vector2(-813.5, 325.5)
const SKEL_SUBDIV_MIN := Vector2(-866.0, 294.0)
const SKEL_SUBDIV_MAX := Vector2(-774.0, 358.0)
const SKEL_BOX_MIN := Vector2(-990.0, 35.0)
const SKEL_BOX_MAX := Vector2(-650.0, 345.0)

## Underground Rat Warren (Expanded Surface Burrow Approach -> Winding Multi-Loop Under-Empire)
## Relocated far from Spider Webwood to the SE deepwoods (460, 340).
## RAT_WARREN_BAKED/OFFSET define the frame of the baked rat_warren_* assets and
## all interior prop coordinates; world position = baked + OFFSET.
const RAT_WARREN_MOUTH := Vector2(460.0, 340.0)
const RAT_WARREN_BAKED := Vector2(-240.0, 280.0)
const RAT_WARREN_OFFSET := RAT_WARREN_MOUTH - RAT_WARREN_BAKED
const RAT_FORECOURT_Y := 22.0
const RAT_SWAMP_WATER_Y := 21.38
const RAT_VAULT_Y := 14.5
const RAT_SANCTUM_Y := 10.0
const RAT_CUTOUT_MIN := Vector2(-243.8, 269.5) + RAT_WARREN_OFFSET
const RAT_CUTOUT_MAX := Vector2(-236.2, 279.0) + RAT_WARREN_OFFSET
const RAT_SUBDIV_MIN := Vector2(-321.0, 243.0) + RAT_WARREN_OFFSET
const RAT_SUBDIV_MAX := Vector2(-159.0, 397.0) + RAT_WARREN_OFFSET
const RAT_BOX_MIN := Vector2(-296.0, 174.0) + RAT_WARREN_OFFSET
const RAT_BOX_MAX := Vector2(-184.0, 290.0) + RAT_WARREN_OFFSET

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

## Procedural Skeleton Catacombs runtime registry (populated by DungeonCaveBuilder)
static var skel_dungeon_seed: int = 0
static var skel_dungeon_rooms: Array[Dictionary] = []
static var skel_dungeon_corridors: Array[Dictionary] = []
static var skel_dungeon_bounds_min: Vector2 = Vector2(-990.0, 35.0)
static var skel_dungeon_bounds_max: Vector2 = Vector2(-650.0, 345.0)
static var skel_dungeon_vestibule_spawn: Vector3 = Vector3(-820.0, 14.0, 280.0)
static var skel_dungeon_sanctum_center: Vector3 = Vector3(-820.0, 5.0, 184.0)


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

	# 1. Skeleton Catacombs Highland Barrow Hillside & Natural Ravine Approach
	if x > -1025.0 and x < -615.0 and z > 10.0 and z < 385.0:
		var dx_sk := x - SKEL_CAVE_MOUTH.x
		# Broad forested hillside mound north of cliff portal (z < 342) covering the procedural dungeon
		if z < 342.0:
			var ridge_x := 1.0 - _smoothstep(108.0, 196.0, absf(dx_sk))
			var ridge_z := _smoothstep(340.0, 310.0, z) * _smoothstep(12.0, 48.0, z)
			var hill_w := ridge_x * ridge_z
			if hill_w > 0.002:
				var undul := 2.6 * sin(x * 0.055 + 0.4) * cos(z * 0.060 - 0.3) + 1.3 * sin(x * 0.12 - z * 0.10)
				var barrow_h := 38.0 + undul
				h = lerpf(h, maxf(h, barrow_h), hill_w * 0.92)
		# Keep terrain safely >= 35.0m over subterranean dungeon chambers/corridors (ceilings <= 26.1m)
		if z < 326.0 and z > 20.0:
			var cov_x := 1.0 - _smoothstep(145.0, 188.0, absf(dx_sk))
			var cov_z := _smoothstep(326.0, 314.0, z) * _smoothstep(20.0, 44.0, z)
			h = maxf(h, lerpf(SKEL_FORECOURT_Y, 35.0, cov_x * cov_z))
		# Rocky flanking hillside shoulders & sunken natural ravine funneling into the barrow cliff portal
		if z >= 316.0 and z <= 372.0 and absf(dx_sk) < 56.0:
			var side_ridge := clampf((absf(dx_sk) - 8.5) / 15.0, 0.0, 1.0) * (1.0 - _smoothstep(28.0, 52.0, absf(dx_sk)))
			var shoulder_z := _smoothstep(358.0, 336.0, z) * _smoothstep(316.0, 323.0, z)
			h += side_ridge * shoulder_z * 4.5
			var rav_x := 1.0 - _smoothstep(7.2, 19.5, absf(dx_sk))
			var rav_z := _smoothstep(368.0, 338.0, z) * _smoothstep(314.0, 322.0, z)
			var rav_t := rav_x * rav_z
			if rav_t > 0.002:
				h = lerpf(h, SKEL_FORECOURT_Y, rav_t)

	# 2. Expanded Rat Warren Sunken Swamp Ruins Basin, Causeway Saddle & Over-Cave Forested Ridge
	var bx := x - RAT_WARREN_OFFSET.x
	var bz := z - RAT_WARREN_OFFSET.y
	if bx > -378.0 and bx < -102.0 and bz > 158.0 and bz < 462.0:
		var web_guard := 1.0
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
			var r_crest := RAT_FORECOURT_Y + 12.8 * r_dome
			if bz > 262.0:
				r_crest = lerpf(r_crest, RAT_FORECOURT_Y, _smoothstep(262.0, 280.0, bz))
			h = maxf(h, r_crest)
		# Keep terrain safely >= 34.5m over the subterranean multi-loop Rat Warren chambers with smooth X/Z falloff
		if bx > -312.0 and bx < -168.0 and bz > 164.0 and bz < 280.0:
			var x_cov := 1.0 - _smoothstep(42.0, 72.0, absf(bx - RAT_WARREN_BAKED.x))
			var z_cov := (1.0 - _smoothstep(256.0, 279.0, bz)) * _smoothstep(166.0, 184.0, bz)
			h = maxf(h, lerpf(RAT_FORECOURT_Y, 34.5, x_cov * z_cov))

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


## Excludes surface trees, rocks, vegetation, and grass from cave cutouts, entry paths,
## continent dirt trails, and Wolf/Spider inner cores.
static func get_world_road_segments(webwood_center: Vector2 = SPIDER_FOREST_CENTER) -> Array[Array]:
	return [
		# 1. Central Basin South Edge -> Crystal Cave Mouth
		[Vector2(-6.0, -17.0), Vector2(-16.0, -28.0)],
		[Vector2(-16.0, -28.0), Vector2(-20.0, -38.0)],
		# 2. Central Basin NW Edge -> Webwood Spider Forest
		[Vector2(-6.0, 15.0), Vector2(-105.0, 140.0)],
		[Vector2(-105.0, 140.0), Vector2(-220.0, 260.0)],
		[Vector2(-220.0, 260.0), SPIDER_TRAIL_START],
		[SPIDER_TRAIL_START, SPIDER_TRAIL_BEND],
		[SPIDER_TRAIL_BEND, webwood_center],
		# 3. Central Basin NE Edge -> Rat Warren Swamp Road & Barbican Flagstone Causeway
		[Vector2(12.0, 15.0), Vector2(215.0, 185.0)],
		[Vector2(215.0, 185.0), Vector2(375.0, 442.0)],
		[Vector2(375.0, 442.0), Vector2(460.0, 442.0)],
		[Vector2(460.0, 442.0), Vector2(460.0, 490.0)],
		[Vector2(460.0, 442.0), RAT_WARREN_MOUTH],
		# 4. Webwood Junction -> Skeleton Crypt Western Road & Ravine Portal
		[SPIDER_TRAIL_START, Vector2(-530.0, 316.0)],
		[Vector2(-530.0, 316.0), Vector2(-820.0, 344.0)],
		[Vector2(-820.0, 344.0), SKEL_CAVE_MOUTH],
		# 5. Central Basin East Edge -> Wolf Pack Crag NE Foothill Trail
		[Vector2(18.0, -14.0), Vector2(150.0, -125.0)],
		[Vector2(150.0, -125.0), Vector2(286.0, -218.0)],
		[Vector2(286.0, -218.0), WOLF_CRAG_CENTER],
	]


static func _seg_dist_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func min_dist_to_world_road(x: float, z: float, webwood_center: Vector2 = SPIDER_FOREST_CENTER) -> float:
	# Quick spatial bounding box around all continent trails
	if x < -840.0 or x > 480.0 or z < -260.0 or z > 505.0:
		return 1e6
	var p := Vector2(x, z)
	var d_min := 1e6
	for seg: Array in get_world_road_segments(webwood_center):
		var d := _seg_dist_2d(p, seg[0] as Vector2, seg[1] as Vector2)
		if d < d_min:
			d_min = d
	return d_min


## Pushes a roadside prop/waystone position out to at least `min_clearance` meters from the nearest road centerline.
static func project_off_world_road(xz: Vector2, min_clearance: float = 7.5, webwood_center: Vector2 = SPIDER_FOREST_CENTER) -> Vector2:
	var out := xz
	for _pass in range(2):
		var best_d := 1e6
		var best_closest := out
		var best_dir := Vector2(1.0, 0.0)
		for seg: Array in get_world_road_segments(webwood_center):
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var ab := b - a
			var l2 := ab.length_squared()
			var t := clampf((out - a).dot(ab) / maxf(l2, 1e-6), 0.0, 1.0)
			var c := a + ab * t
			var d := out.distance_to(c)
			if d < best_d:
				best_d = d
				best_closest = c
				best_dir = ab.normalized() if l2 > 1e-6 else Vector2(0.0, 1.0)
		if best_d >= min_clearance:
			break
		var normal := out - best_closest
		if normal.length_squared() < 1e-4:
			normal = Vector2(-best_dir.y, best_dir.x)
		else:
			normal = normal.normalized()
		out = best_closest + normal * min_clearance
	return out


static func is_in_landmark_exclusion(x: float, z: float, is_grass: bool = false, webwood_center: Vector2 = SPIDER_FOREST_CENTER) -> bool:
	# Skeleton Catacombs Hillside Ravine & Barrow Cliff Portal Mouth
	if x >= -845.0 and x <= -795.0 and z >= 306.0 and z <= 360.0:
		if not is_grass and (x >= -832.0 and x <= -808.0 and z >= 310.0 and z <= 356.0):
			return true
		if not is_grass and Vector2(x - SKEL_CAVE_MOUTH.x, z - SKEL_CAVE_MOUTH.y).length() < 16.0:
			return true
		if is_grass and x >= -828.0 and x <= -812.0 and z >= 313.0 and z <= 348.5:
			return true

	# Rat Warren Expanded Surface Sunken Swamp Ruins Complex, Piers, Causeway & Burrow Mouth
	var rbx := x - RAT_WARREN_OFFSET.x
	var rbz := z - RAT_WARREN_OFFSET.y
	if rbx >= -304.0 and rbx <= -176.0 and rbz >= 256.0 and rbz <= 392.0:
		if not is_grass:
			return true
		if (rbx >= -254.0 and rbx <= -226.0 and rbz >= 274.0 and rbz <= 326.5) \
				or (rbx >= -247.5 and rbx <= -232.5 and rbz >= 326.5 and rbz <= 382.5) \
				or (rbx >= -278.5 and rbx <= -251.0 and rbz >= 294.0 and rbz <= 322.0) \
				or (rbx >= -229.0 and rbx <= -202.0 and rbz >= 290.0 and rbz <= 322.0):
			return true

	# Inner Wolf Den Clearing & Approach Trail Corridor
	var d_wolf_c := Vector2(x - WOLF_CRAG_CENTER.x, z - WOLF_CRAG_CENTER.y).length()
	var d_wolf_hollow := Vector2(x - WOLF_CRAG_CENTER.x, z - (WOLF_CRAG_CENTER.y - 4.8)).length()
	if (not is_grass and d_wolf_c < 19.5) or (is_grass and (d_wolf_c < 13.0 or d_wolf_hollow < 13.0)):
		return true

	# Leave room for the broodmother in the central Webwood hollow
	var d_spider_c := Vector2(x - webwood_center.x, z - webwood_center.y).length()
	if (not is_grass and d_spider_c < 11.0) or (is_grass and d_spider_c < 5.0):
		return true

	# Continent Dirt Roads & Landmark Approach Trails (zero grass inside dirt trails, zero blocking trees/rocks/bushes)
	var d_road := min_dist_to_world_road(x, z, webwood_center)
	if is_grass:
		if d_road < 5.6:
			return true
	else:
		# Inside Webwood forest, allow flanking silk-anchor trees at >= 5.4m while keeping the trail corridor clear
		var road_clear := 5.4 if d_spider_c < 165.0 else 7.2
		if d_road < road_clear:
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
	var sk_min := Vector2(minf(SKEL_BOX_MIN.x, skel_dungeon_bounds_min.x), minf(SKEL_BOX_MIN.y, skel_dungeon_bounds_min.y))
	var sk_max := Vector2(maxf(SKEL_BOX_MAX.x, skel_dungeon_bounds_max.x), maxf(SKEL_BOX_MAX.y, skel_dungeon_bounds_max.y))
	if x >= SKEL_CUTOUT_MIN.x and x <= SKEL_CUTOUT_MAX.x and z >= SKEL_CUTOUT_MIN.y and z <= SKEL_CUTOUT_MAX.y + 2.5:
		return true
	if x >= sk_min.x and x <= sk_max.x and z >= sk_min.y and z <= sk_max.y:
		if foot_y < overworld_h - 1.5:
			return true

	if x >= RAT_CUTOUT_MIN.x and x <= RAT_CUTOUT_MAX.x and z >= RAT_CUTOUT_MIN.y and z <= RAT_CUTOUT_MAX.y + 1.5:
		return true
	if x >= RAT_BOX_MIN.x and x <= RAT_BOX_MAX.x and z >= RAT_BOX_MIN.y and z <= RAT_BOX_MAX.y:
		if foot_y < overworld_h - 2.0:
			return true

	return false


## Analytical walkable floor surface inside the procedural Skeleton Catacombs.
static func sample_skeleton_cave_floor(x: float, z: float) -> Vector4:
	# Sloped descent tunnel from barrow portal y=26.0 (z=326) down to Vestibule y=14.0 (z=289)
	if z >= 289.0 and z <= 332.0 and absf(x - SKEL_CAVE_MOUTH.x) <= 8.2:
		var t := clampf((326.0 - z) / 37.0, 0.0, 1.0)
		var y := lerpf(SKEL_FORECOURT_Y, SKEL_UPPER_Y, t)
		var slope_dz := (SKEL_UPPER_Y - SKEL_FORECOURT_Y) / 37.0
		var n := Vector3(0.0, 1.0, -slope_dz).normalized()
		return Vector4(n.x, n.y, n.z, y)

	for room in skel_dungeon_rooms:
		var c: Vector2 = room["center"]
		var half: Vector2 = room["half"]
		if absf(x - c.x) <= half.x + 1.0 and absf(z - c.y) <= half.y + 1.0:
			return Vector4(0.0, 1.0, 0.0, float(room["floor_y"]))

	var p := Vector2(x, z)
	for corr in skel_dungeon_corridors:
		var a: Vector2 = corr["a"]
		var b: Vector2 = corr["b"]
		var ab := b - a
		var ab_len := ab.length()
		if ab_len < 0.05:
			continue
		var dir := ab / ab_len
		var rel := p - a
		var along := rel.dot(dir)
		var perp := absf(rel.dot(Vector2(-dir.y, dir.x)))
		var half_w := float(corr.get("half_w", 3.4))
		if perp <= half_w + 1.2 and along >= -1.2 and along <= ab_len + 1.2:
			var t_c := clampf(along / ab_len, 0.0, 1.0)
			var y_a := float(corr["y_a"])
			var y_b := float(corr["y_b"])
			var y_c := lerpf(y_a, y_b, t_c)
			var t3 := Vector3(dir.x * ab_len, y_b - y_a, dir.y * ab_len).normalized()
			var r3 := Vector3(-dir.y, 0.0, dir.x)
			var nc := r3.cross(t3).normalized()
			if nc.y < 0.0:
				nc = -nc
			return Vector4(nc.x, nc.y, nc.z, y_c)

	return Vector4(0.0, 1.0, 0.0, SKEL_UPPER_Y)


## Analytical walkable floor surface inside the Expanded Underground Rat Warren:
##   z = 278 -> 258: Sloped sinkhole burrow descent (y = 22.0 -> 14.5)
##   z = 232 -> 258: Sunken Crossroads Confluence + West Sump + East Burrow Nest (y = 14.5)
##   z = 232 -> 203: Winding Split NW/NE Burrow Loops (y = 14.5 -> 10.0)
##   z < 203: Rat King's Deep Brood Hollow (y = 10.0, dais 11.45)
static func sample_rat_warren_floor(z: float, x: float = -240.0) -> Vector4:
	var is_world := x > 0.0
	var bz := z - RAT_WARREN_OFFSET.y if is_world else z
	var bx := x - RAT_WARREN_OFFSET.x if is_world else x
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
	var sk_min := Vector2(minf(SKEL_BOX_MIN.x, skel_dungeon_bounds_min.x), minf(SKEL_BOX_MIN.y, skel_dungeon_bounds_min.y))
	var sk_max := Vector2(maxf(SKEL_BOX_MAX.x, skel_dungeon_bounds_max.x), maxf(SKEL_BOX_MAX.y, skel_dungeon_bounds_max.y))
	if x >= sk_min.x and x <= sk_max.x and z >= sk_min.y and z <= sk_max.y + 6.0:
		if (x >= SKEL_CUTOUT_MIN.x and x <= SKEL_CUTOUT_MAX.x and z >= SKEL_CUTOUT_MIN.y and z <= SKEL_CUTOUT_MAX.y + 2.5) or foot_y < overworld_h - 1.5:
			return sample_skeleton_cave_floor(x, z)
	if x >= RAT_BOX_MIN.x and x <= RAT_BOX_MAX.x and z >= RAT_BOX_MIN.y and z <= RAT_BOX_MAX.y + 6.0:
		if (x >= RAT_CUTOUT_MIN.x and x <= RAT_CUTOUT_MAX.x and z >= RAT_CUTOUT_MIN.y and z <= RAT_CUTOUT_MAX.y + 1.5) or foot_y < overworld_h - 2.0:
			return sample_rat_warren_floor(z, x)
	return Vector4(0.0, 1.0, 0.0, overworld_h)


## Returns atmospheric darkening weight [0, 1] for CaveAtmosphere inside Skeleton Cave or Rat Warren.
static func eval_underground_atmosphere(cam_pos: Vector3) -> float:
	var factor := 0.0

	# Skeleton Catacombs deep interior (portal descent + procedural chambers)
	var sk_min := Vector2(minf(SKEL_BOX_MIN.x, skel_dungeon_bounds_min.x), minf(SKEL_BOX_MIN.y, skel_dungeon_bounds_min.y))
	var sk_max := Vector2(maxf(SKEL_BOX_MAX.x, skel_dungeon_bounds_max.x), maxf(SKEL_BOX_MAX.y, skel_dungeon_bounds_max.y))
	if cam_pos.x >= sk_min.x - 4.0 and cam_pos.x <= sk_max.x + 4.0 and cam_pos.z >= sk_min.y - 4.0 and cam_pos.z <= 326.0 and cam_pos.y < 26.5:
		var in_z := _smoothstep(324.0, 302.0, cam_pos.z)
		var in_y := 1.0 - _smoothstep(18.0, 25.0, cam_pos.y)
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
	var sk_min := Vector2(minf(SKEL_BOX_MIN.x, skel_dungeon_bounds_min.x), minf(SKEL_BOX_MIN.y, skel_dungeon_bounds_min.y))
	var sk_max := Vector2(maxf(SKEL_BOX_MAX.x, skel_dungeon_bounds_max.x), maxf(SKEL_BOX_MAX.y, skel_dungeon_bounds_max.y))
	if pos.x >= sk_min.x and pos.x <= sk_max.x and pos.z >= sk_min.y and pos.z <= sk_max.y + 8.0:
		if pos.y < overworld_h - 1.2 or (pos.x >= -826.5 and pos.x <= -813.5 and pos.z >= 312.0 and pos.z <= 327.0 and pos.y < 27.5):
			if pos.z >= 290.0:
				return "Skeleton Catacombs · Barrow Descent"
			for room in skel_dungeon_rooms:
				var c: Vector2 = room["center"]
				var half: Vector2 = room["half"]
				if absf(pos.x - c.x) <= half.x + 1.0 and absf(pos.z - c.y) <= half.y + 1.0:
					return "Skeleton Catacombs · %s" % String(room.get("title", "Vault"))
			return "Skeleton Catacombs · Passage"
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
	if Vector2(pos.x - 590.0, pos.z - 2200.0).length() <= 135.0:
		return "Slimebrook Village"
	if Vector2(pos.x - 670.0, pos.z - 2447.0).length() <= 115.0:
		return "Slimebrook Fishing Harbor"
	if pos.x >= -260.0 and pos.x <= 80.0 and pos.z >= -320.0 and pos.z <= 80.0:
		if pos.y < overworld_h - 2.2:
			return "Crystal Cave Interior"
		elif Vector2(pos.x - (-24.0), pos.z - (-52.0)).length() <= 45.0:
			return "Crystal Cave Entrance"
		elif Vector2(pos.x - (-109.0), pos.z - (-87.0)).length() <= 45.0:
			return "Crystal Cave Skylight Hill"
	if Vector2(pos.x, pos.z).length() <= 140.0:
		return "Spawn Meadow & Forest"
	if pos.z < -450.0:
		return "Northern Alpine Foothills"
	if pos.x < -450.0:
		return "Western Mesa & Woodlands"
	if pos.z > 1800.0:
		return "Southern Coastline"
	return "Emerald Forest Valley"
