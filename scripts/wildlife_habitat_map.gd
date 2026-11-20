class_name WildlifeHabitatMap
extends RefCounted
## Deterministic Habitat Weight-Paint & Ecological Density-Field Placement for Wildlife.
##
## Instead of random scatter, evaluates continuous biome/habitat weights [0.0 .. 1.0]
## across the continent using real TerrainScene height, slope, grass density, actual tree
## canopy density, road clearance, and territory masks (with optional Texture2D weight-paint
## mask override). Selects the highest-weight habitat peaks with minimum cluster spacing and
## spawns structured social groups (warrens, herds, flocks, groves).

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")

const CANOPY_CELL_SIZE := 20.0

var _tree_grid: Dictionary = {}  # Vector2i -> int (tree count in 20m cell)
var _terrain: Node = null
var _village_center: Vector2 = Vector2(590.0, 2200.0)
var _dock_shore: Vector2 = Vector2(656.6, 2448.0)
var _weight_mask_img: Image = null
var _weight_mask_bounds: Rect2 = Rect2(-900.0, -400.0, 1800.0, 3000.0)


func build_from_terrain(terrain: Node, village_center: Vector2, dock_shore: Vector2, weight_mask_override: Texture2D = null) -> void:
	_terrain = terrain
	_village_center = village_center
	_dock_shore = dock_shore
	_tree_grid.clear()
	_weight_mask_img = null

	if weight_mask_override != null:
		var img := weight_mask_override.get_image()
		if img != null and not img.is_empty():
			_weight_mask_img = img

	if terrain != null and "_cached_tree_data" in terrain:
		var tdata: Array = terrain.get("_cached_tree_data")
		for rec in tdata:
			if rec is Dictionary and rec.has("position"):
				var p: Vector3 = rec["position"]
				var cell := Vector2i(floori(p.x / CANOPY_CELL_SIZE), floori(p.z / CANOPY_CELL_SIZE))
				_tree_grid[cell] = int(_tree_grid.get(cell, 0)) + 1


func _sample_surface(x: float, z: float) -> Vector4:
	if _terrain != null and _terrain.has_method("sample_surface_exact"):
		return _terrain.call("sample_surface_exact", x, z) as Vector4
	var y := 22.0
	if _terrain != null and _terrain.has_method("sample_height"):
		y = float(_terrain.call("sample_height", x, z))
	return Vector4(0.0, 1.0, 0.0, y)


func _sample_grass_density(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("sample_grass_density"):
		return clampf(float(_terrain.call("sample_grass_density", x, z)), 0.0, 1.0)
	return 0.75


## Smooth [0..1] tree canopy weight from real placed trees in a 3x3 neighborhood (60m x 60m).
func sample_canopy_weight(x: float, z: float) -> float:
	var cx := floori(x / CANOPY_CELL_SIZE)
	var cz := floori(z / CANOPY_CELL_SIZE)
	var weighted_trees := 0.0
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var cnt := int(_tree_grid.get(Vector2i(cx + ox, cz + oz), 0))
			if cnt > 0:
				var w := 1.0 if (ox == 0 and oz == 0) else (0.55 if (ox == 0 or oz == 0) else 0.30)
				weighted_trees += float(cnt) * w
	return clampf(weighted_trees / 6.5, 0.0, 1.0)


func _sample_override_weight(x: float, z: float, channel: int) -> float:
	if _weight_mask_img == null:
		return 1.0
	var u := clampf((x - _weight_mask_bounds.position.x) / maxf(1.0, _weight_mask_bounds.size.x), 0.0, 1.0)
	var v := clampf((z - _weight_mask_bounds.position.y) / maxf(1.0, _weight_mask_bounds.size.y), 0.0, 1.0)
	var px := clampi(int(round(u * float(_weight_mask_img.get_width() - 1))), 0, _weight_mask_img.get_width() - 1)
	var py := clampi(int(round(v * float(_weight_mask_img.get_height() - 1))), 0, _weight_mask_img.get_height() - 1)
	var c := _weight_mask_img.get_pixel(px, py)
	match channel:
		0: return c.r
		1: return c.g
		2: return c.b
		_: return c.a


func _is_blocked_for_wildlife(x: float, z: float, allow_village: bool = false, allow_shore: bool = false) -> bool:
	var p := Vector2(x, z)
	# Keep central starting sandbox structures clear (x in [-18..20], z in [-18..16])
	if x > -19.0 and x < 21.0 and z > -19.0 and z < 16.0:
		return true
	if WorldLandmarks.min_dist_to_world_road(x, z) < 6.8:
		return true
	if _terrain != null and _terrain.has_method("is_point_in_cave_cutout") and bool(_terrain.call("is_point_in_cave_cutout", x, z)):
		return true
	if CaveSystem.is_in_portal_scatter_exclusion(x, z, false):
		return true
	if not allow_village and VillageBuilder.is_in_village_exclusion(x, z, false):
		return true
	# Keep peaceful wildlife out of hostile territory inner cores
	if p.distance_to(WorldLandmarks.WOLF_CRAG_CENTER) < 46.0:
		return true
	if p.distance_to(WorldLandmarks.SPIDER_FOREST_CENTER) < 76.0:
		return true
	if p.distance_to(WorldLandmarks.SKEL_CAVE_MOUTH) < 52.0:
		return true
	if not allow_shore and p.distance_to(Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 42.0)) < 68.0:
		return true
	if allow_shore and p.distance_to(Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 38.0)) < 46.0:
		return true
	return false


## Evaluates continuous Habitat Weight [0.0 .. 1.0] for a given habitat channel at (x, z):
##   "meadow_glade"   -> Bunnies, Wild Horses (sunlit, flat, lush grass, low canopy)
##   "dense_canopy"   -> Squirrels (high tree density, woodland floor)
##   "forest_ecotone" -> Deer/Stag herds, Foxes, Birbs (forest-meadow edge transition)
##   "wetland_shore"  -> Frogs, Ducks, Turtles (swamp outer banks & coastal harbor coves)
##   "village_yard"   -> Chicks, Pigeons (village gardens, paddocks, quiet corners)
func evaluate_habitat_weight(x: float, z: float, channel: String) -> float:
	var allow_village := (channel == "village_yard")
	var allow_shore := (channel == "wetland_shore")
	if _is_blocked_for_wildlife(x, z, allow_village, allow_shore):
		return 0.0

	var surf := _sample_surface(x, z)
	var ny := surf.y
	var y := surf.w
	if ny < 0.85:
		return 0.0

	var flatness := clampf((ny - 0.85) / 0.14, 0.0, 1.0)
	var canopy := sample_canopy_weight(x, z)
	var grass_d := _sample_grass_density(x, z)
	var p := Vector2(x, z)

	match channel:
		"meadow_glade":
			if y < 6.5 or y > 78.0:
				return 0.0
			var open_w := clampf(1.0 - canopy * 1.15, 0.0, 1.0)
			# Natural clover-basin boost near starting valley & village outskirts
			var basin_w := 1.0 + 0.35 * (1.0 - smoothstep(25.0, 145.0, p.length()))
			var w := open_w * lerpf(0.45, 1.0, grass_d) * flatness * basin_w
			return clampf(w * _sample_override_weight(x, z, 0), 0.0, 1.0)

		"dense_canopy":
			if y < 7.0 or y > 84.0 or canopy < 0.25:
				return 0.0
			var grove_w := smoothstep(0.25, 0.85, canopy)
			var w := grove_w * lerpf(0.65, 1.0, flatness)
			return clampf(w * _sample_override_weight(x, z, 1), 0.0, 1.0)

		"forest_ecotone":
			if y < 6.5 or y > 82.0:
				return 0.0
			# Ecotone peaks where forest meets meadow (canopy ~ 0.35..0.70)
			var ecotone := clampf(1.0 - absf(canopy - 0.45) / 0.48, 0.0, 1.0)
			var w := ecotone * lerpf(0.55, 1.0, grass_d) * flatness
			return clampf(w * _sample_override_weight(x, z, 2), 0.0, 1.0)

		"wetland_shore":
			# Peaks along the outer Rat Swamp marsh shoreline (R=48..105m) & Slimebrook coastal cove beach (y=0.9..8.2m)
			var swamp_c := Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 44.0)
			var d_swamp := p.distance_to(swamp_c)
			var swamp_bank := 0.0
			if d_swamp >= 48.0 and d_swamp <= 115.0 and y >= WorldLandmarks.RAT_SWAMP_WATER_Y - 0.10 and y <= WorldLandmarks.RAT_SWAMP_WATER_Y + 3.2:
				swamp_bank = (1.0 - smoothstep(55.0, 112.0, d_swamp)) * (1.0 - smoothstep(0.4, 3.0, absf(y - (WorldLandmarks.RAT_SWAMP_WATER_Y + 0.55))))
			var d_cove := p.distance_to(_dock_shore)
			var cove_bank := 0.0
			if d_cove >= 14.0 and d_cove <= 125.0 and y >= 0.85 and y <= 8.4:
				cove_bank = (1.0 - smoothstep(22.0, 120.0, d_cove)) * (1.0 - smoothstep(1.2, 5.2, absf(y - 2.6)))
			return clampf(maxf(swamp_bank, cove_bank) * flatness * _sample_override_weight(x, z, 3), 0.0, 1.0)

		"village_yard":
			var d_v := p.distance_to(_village_center)
			if d_v > 125.0 or y < 6.0:
				return 0.0
			# Prefer village cloister gardens, paddocks & outer wall verge (avoid main cobblestone avenues)
			var rel := p - _village_center
			var on_avenue := (absf(rel.x) < 6.5 and absf(rel.y) < 82.0) or (absf(rel.y) < 6.5 and absf(rel.x) < 90.0)
			if on_avenue:
				return 0.0
			var yard_w := 1.0 - smoothstep(75.0, 125.0, d_v)
			return clampf(yard_w * flatness, 0.0, 1.0)

	return 0.0


## Samples candidate habitat peaks inside a list of search zones and returns the top `max_peaks`
## positions separated by at least `min_spacing`, ranked strictly by deterministic Habitat Weight.
func select_habitat_peaks(
	zones: Array,
	channel: String,
	grid_step: float,
	min_weight: float,
	min_spacing: float,
	max_peaks: int,
	occupied_peaks: Array[Vector2]
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for z_def in zones:
		var center: Vector2 = z_def[0]
		var radius: float = float(z_def[1])
		var r2 := radius * radius
		var steps := int(ceil(radius / grid_step))
		for gx in range(-steps, steps + 1):
			for gz in range(-steps, steps + 1):
				var off := Vector2(float(gx) * grid_step, float(gz) * grid_step)
				if off.length_squared() > r2:
					continue
				var px := center.x + off.x
				var pz := center.y + off.y
				var w := evaluate_habitat_weight(px, pz, channel)
				if w >= min_weight:
					candidates.append({"xz": Vector2(px, pz), "weight": w})

	# Deterministic descending sort by weight (tie-break by position for 100% repeatability)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa: float = a["weight"]
		var wb: float = b["weight"]
		if absf(wa - wb) > 0.0005:
			return wa > wb
		var pa: Vector2 = a["xz"]
		var pb: Vector2 = b["xz"]
		if not is_equal_approx(pa.x, pb.x):
			return pa.x < pb.x
		return pa.y < pb.y
	)

	var chosen: Array[Dictionary] = []
	var sp_sq := min_spacing * min_spacing
	for cand in candidates:
		if chosen.size() >= max_peaks:
			break
		var pt: Vector2 = cand["xz"]
		var ok := true
		for ex in chosen:
			if pt.distance_squared_to(ex["xz"] as Vector2) < sp_sq:
				ok = false
				break
		if ok:
			for occ in occupied_peaks:
				if pt.distance_squared_to(occ) < (min_spacing * 0.45) * (min_spacing * 0.45):
					ok = false
					break
		if ok:
			chosen.append(cand)
			occupied_peaks.append(pt)
	return chosen


## Generates the complete weight-painted wildlife population (both small hybrid Poly Pizza + Quaternius
## critters AND roaming forest deer/stags/foxes/horses) as deterministic social clusters.
func generate_wildlife_spawns() -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	var occupied: Array[Vector2] = []

	var central_zones := [
		[Vector2(0.0, 0.0), 115.0],
		[Vector2(-68.0, 60.0), 75.0],
		[Vector2(115.0, 50.0), 80.0],
	]
	var broad_forest_zones := [
		[Vector2(0.0, 0.0), 150.0],
		[Vector2(150.0, -135.0), 95.0],
		[Vector2(-165.0, -155.0), 90.0],
		[Vector2(-230.0, 155.0), 95.0],
		[Vector2(265.0, 135.0), 95.0],
		[Vector2(140.0, 440.0), 100.0],
		[Vector2(590.0, 2040.0), 185.0],
	]
	var wetland_zones := [
		[Vector2(WorldLandmarks.RAT_WARREN_MOUTH.x, WorldLandmarks.RAT_WARREN_MOUTH.y + 44.0), 115.0],
		[_dock_shore, 120.0],
	]
	var village_zones := [
		[_village_center, 118.0],
	]

	# Helper to place a tight social cluster around a weight peak on valid ground
	var add_cluster := func(peak_xz: Vector2, members: Array, ring_r: float, tr: float, allow_v: bool, allow_s: bool) -> void:
		for mi in range(members.size()):
			var m: Dictionary = members[mi]
			var ang := float(mi) * (TAU / maxf(1.0, float(members.size()))) + peak_xz.x * 0.07
			var rad := 0.0 if mi == 0 else ring_r * (0.75 + 0.35 * float(mi % 2))
			var px := peak_xz.x + cos(ang) * rad
			var pz := peak_xz.y + sin(ang) * rad
			if _is_blocked_for_wildlife(px, pz, allow_v, allow_s):
				px = peak_xz.x
				pz = peak_xz.y
			var entry := m.duplicate()
			entry["pos"] = Vector2(px, pz)
			entry["tc"] = peak_xz
			entry["tr"] = tr
			spawns.append(entry)

	# ------------------------------------------------------------------
	# 1. SMALL ANIMALS (Hybrid Quaternius CC0 Animated + Poly Pizza Stylized)
	# ------------------------------------------------------------------

	# 1A. Meadow Bunnies (Quaternius CC0 animated Bunny.glb) — sunlit clover meadow peaks (warrens of 2-3)
	var bunny_peaks := select_habitat_peaks(central_zones, "meadow_glade", 12.0, 0.38, 36.0, 5, occupied)
	bunny_peaks.append_array(select_habitat_peaks([[Vector2(590.0, 2040.0), 170.0], [Vector2(140.0, 440.0), 90.0]], "meadow_glade", 18.0, 0.35, 65.0, 2, occupied))
	for bi in range(bunny_peaks.size()):
		var pk: Vector2 = bunny_peaks[bi]["xz"]
		var group := [
			{"name": "Meadow Bunny", "glb": "res://assets/animals/Bunny.glb", "target_height": 0.62, "walk_spd": 2.4, "run_spd": 6.8, "hp": 25.0, "rad": 0.38, "hp_h": 1.05, "gait": "hop"},
			{"name": "Clover Bunny", "glb": "res://assets/animals/Bunny.glb", "target_height": 0.54, "walk_spd": 2.5, "run_spd": 7.0, "hp": 22.0, "rad": 0.35, "hp_h": 0.98, "gait": "hop"},
		]
		if bi < 3:
			group.append({"name": "Young Cottontail", "glb": "res://assets/animals/Bunny.glb", "target_height": 0.44, "walk_spd": 2.6, "run_spd": 7.2, "hp": 18.0, "rad": 0.30, "hp_h": 0.88, "gait": "hop"})
		add_cluster.call(pk, group, 3.8, 28.0, false, false)

	# 1B. Woodland Squirrels (Poly Pizza Squirrel.glb + procedural scurry/hop) — strictly dense tree canopy peaks!
	var sq_peaks := select_habitat_peaks(central_zones, "dense_canopy", 12.0, 0.32, 34.0, 5, occupied)
	sq_peaks.append_array(select_habitat_peaks(broad_forest_zones, "dense_canopy", 20.0, 0.38, 78.0, 4, occupied))
	for si in range(sq_peaks.size()):
		var pk: Vector2 = sq_peaks[si]["xz"]
		var group := [
			{"name": "Forest Squirrel", "glb": "res://assets/animals/Squirrel.glb", "target_height": 0.48, "walk_spd": 2.8, "run_spd": 7.4, "hp": 20.0, "rad": 0.32, "hp_h": 0.95, "gait": "hop"},
		]
		if si % 2 == 0:
			group.append({"name": "Acorn Squirrel", "glb": "res://assets/animals/Squirrel.glb", "target_height": 0.42, "walk_spd": 2.9, "run_spd": 7.6, "hp": 18.0, "rad": 0.30, "hp_h": 0.90, "gait": "hop"})
		add_cluster.call(pk, group, 3.4, 24.0, false, false)

	# 1C. Woodland Songbirds / Birbs (Quaternius CC0 animated Birb.glb) — sunlit forest-meadow ecotone edges
	var birb_peaks := select_habitat_peaks(central_zones, "forest_ecotone", 14.0, 0.34, 42.0, 4, occupied)
	for bk in birb_peaks:
		var pk: Vector2 = bk["xz"]
		add_cluster.call(pk, [
			{"name": "Meadow Birb", "glb": "res://assets/animals/Birb.glb", "target_height": 0.48, "walk_spd": 2.2, "run_spd": 6.2, "hp": 18.0, "rad": 0.32, "hp_h": 0.95, "gait": "hop"},
			{"name": "Songbird", "glb": "res://assets/animals/Birb.glb", "target_height": 0.44, "walk_spd": 2.3, "run_spd": 6.4, "hp": 16.0, "rad": 0.30, "hp_h": 0.90, "gait": "hop"},
		], 3.2, 26.0, false, false)

	# 1D. Marsh & Cove Frogs (Quaternius CC0 animated Frog.glb) — wetland & shoreline banks
	var frog_peaks := select_habitat_peaks(wetland_zones, "wetland_shore", 12.0, 0.18, 28.0, 4, occupied)
	for fk in frog_peaks:
		var pk: Vector2 = fk["xz"]
		add_cluster.call(pk, [
			{"name": "Marsh Frog", "glb": "res://assets/animals/Frog.glb", "target_height": 0.44, "walk_spd": 1.8, "run_spd": 5.2, "hp": 18.0, "rad": 0.32, "hp_h": 0.85, "gait": "hop"},
			{"name": "Pond Frog", "glb": "res://assets/animals/Frog.glb", "target_height": 0.38, "walk_spd": 1.9, "run_spd": 5.4, "hp": 16.0, "rad": 0.28, "hp_h": 0.80, "gait": "hop"},
		], 3.0, 20.0, false, true)

	# 1E. Cove & Marsh Ducks (Poly Pizza Duck.glb + procedural waddle) — shoreline coves & marsh banks
	var duck_peaks := select_habitat_peaks(wetland_zones, "wetland_shore", 12.0, 0.16, 32.0, 4, occupied)
	for dk in duck_peaks:
		var pk: Vector2 = dk["xz"]
		add_cluster.call(pk, [
			{"name": "Cove Duck", "glb": "res://assets/animals/Duck.glb", "target_height": 0.56, "walk_spd": 1.9, "run_spd": 5.0, "hp": 24.0, "rad": 0.38, "hp_h": 1.00, "gait": "waddle"},
			{"name": "Pond Duck", "glb": "res://assets/animals/Duck.glb", "target_height": 0.52, "walk_spd": 2.0, "run_spd": 5.2, "hp": 22.0, "rad": 0.35, "hp_h": 0.96, "gait": "waddle"},
		], 3.2, 24.0, false, true)

	# 1F. Shoreline Turtles (Poly Pizza Turtle.glb + slow crawl bob) — flat sandy beaches & gentle marsh banks
	var turtle_peaks := select_habitat_peaks(wetland_zones, "wetland_shore", 14.0, 0.14, 38.0, 3, occupied)
	for tk in turtle_peaks:
		var pk: Vector2 = tk["xz"]
		add_cluster.call(pk, [
			{"name": "Shore Turtle", "glb": "res://assets/animals/Turtle.glb", "target_height": 0.44, "walk_spd": 1.05, "run_spd": 2.1, "hp": 40.0, "rad": 0.42, "hp_h": 0.90, "gait": "waddle"},
		], 2.5, 18.0, false, true)

	# 1G. Village Chicks & Pigeons (Quaternius CC0 animated Chick.glb & Pigeon.glb) — Slimebrook Village yards & gardens
	var chick_peaks := select_habitat_peaks(village_zones, "village_yard", 14.0, 0.35, 34.0, 3, occupied)
	for ci in range(chick_peaks.size()):
		var pk: Vector2 = chick_peaks[ci]["xz"]
		if ci < 2:
			add_cluster.call(pk, [
				{"name": "Village Chick", "glb": "res://assets/animals/Chick.glb", "target_height": 0.46, "walk_spd": 1.9, "run_spd": 4.8, "hp": 18.0, "rad": 0.30, "hp_h": 0.88, "gait": "hop"},
				{"name": "Yard Chick", "glb": "res://assets/animals/Chick.glb", "target_height": 0.42, "walk_spd": 2.0, "run_spd": 5.0, "hp": 16.0, "rad": 0.28, "hp_h": 0.84, "gait": "hop"},
			], 2.8, 18.0, true, false)
		else:
			add_cluster.call(pk, [
				{"name": "Town Pigeon", "glb": "res://assets/animals/Pigeon.glb", "target_height": 0.48, "walk_spd": 2.1, "run_spd": 5.6, "hp": 18.0, "rad": 0.30, "hp_h": 0.90, "gait": "hop"},
				{"name": "Square Pigeon", "glb": "res://assets/animals/Pigeon.glb", "target_height": 0.46, "walk_spd": 2.1, "run_spd": 5.6, "hp": 18.0, "rad": 0.30, "hp_h": 0.90, "gait": "hop"},
			], 2.8, 22.0, true, false)

	# ------------------------------------------------------------------
	# 2. MEDIUM & LARGE ROAMING FOREST WILDLIFE (Weight-Painted Herds)
	# ------------------------------------------------------------------

	# 2A. Deer & Stag Family Herds (forest-meadow ecotone peaks -> 1 Stag + 2 Does per herd)
	var deer_peaks := select_habitat_peaks(central_zones, "forest_ecotone", 16.0, 0.30, 58.0, 3, occupied)
	deer_peaks.append_array(select_habitat_peaks(broad_forest_zones, "forest_ecotone", 24.0, 0.30, 125.0, 5, occupied))
	for dp in deer_peaks:
		var pk: Vector2 = dp["xz"]
		add_cluster.call(pk, [
			{"name": "Forest Stag", "glb": "res://assets/animals/Stag.glb", "scale": 0.68, "walk_spd": 2.6, "run_spd": 7.6, "hp": 65.0, "rad": 0.95, "hp_h": 3.20},
			{"name": "Woodland Doe", "glb": "res://assets/animals/Deer.glb", "scale": 0.65, "walk_spd": 2.6, "run_spd": 7.6, "hp": 55.0, "rad": 0.88, "hp_h": 2.70},
			{"name": "Spotted Fawn", "glb": "res://assets/animals/Deer.glb", "scale": 0.54, "walk_spd": 2.7, "run_spd": 7.8, "hp": 42.0, "rad": 0.78, "hp_h": 2.25},
		], 5.5, 46.0, false, false)

	# 2B. Woodland Foxes (forest-meadow fringe peaks)
	var fox_peaks := select_habitat_peaks(broad_forest_zones, "forest_ecotone", 22.0, 0.28, 105.0, 6, occupied)
	for fp in fox_peaks:
		var pk: Vector2 = fp["xz"]
		add_cluster.call(pk, [
			{"name": "Red Fox", "glb": "res://assets/animals/Fox.glb", "scale": 0.48, "walk_spd": 2.8, "run_spd": 8.0, "hp": 45.0, "rad": 0.72, "hp_h": 1.55},
		], 3.0, 44.0, false, false)

	# 2C. Wild Horse Pairs (wide open meadow glade peaks)
	var horse_peaks := select_habitat_peaks(broad_forest_zones, "meadow_glade", 24.0, 0.42, 165.0, 3, occupied)
	for hp_d in horse_peaks:
		var pk: Vector2 = hp_d["xz"]
		add_cluster.call(pk, [
			{"name": "Wild Roan Horse", "glb": "res://assets/animals/Horse.glb", "scale": 0.68, "walk_spd": 2.8, "run_spd": 8.2, "hp": 75.0, "rad": 1.02, "hp_h": 2.95},
			{"name": "Wild White Mare", "glb": "res://assets/animals/Horse_White.glb", "scale": 0.66, "walk_spd": 2.8, "run_spd": 8.2, "hp": 72.0, "rad": 1.02, "hp_h": 2.90},
		], 5.2, 52.0, false, false)

	return spawns
