class_name VillageBuilder
extends RefCounted

## Builds the 50-building Octagonal Walled Concentric medieval market town ("Slimebrook"),
## packed mud ring & cardinal avenue corridors, textured terrain-draped Grand Market Square,
## Ring Road & 4 cardinal cobblestone streets, 4 Twin-Tower Gatehouse Bridges + 4 Corner Bastions
## connected by continuous Octagonal Stone Curtain Walls, far from CaveLayout.ORIGIN.

const VILLAGE_CENTER := Vector3(590.0, 20.4, 2200.0)
const V_SCALE := 1.40
const VILLAGE_RADIUS_X := 76.0 * V_SCALE
const VILLAGE_RADIUS_Z := 66.0 * V_SCALE
const STORY_H := 3.0 * V_SCALE
const CELL := 2.0 * V_SCALE
const LAYER_OBSTACLES := 4
const ASSET_DIR := "res://assets/village/"
const VILLAGE_CACHE_PATH := "user://cache/village_baked.scn"
const GRAY_TILE_TEX_PATH := "user://cache/village_gray_tile_tex.res"

const ROOF_PALETTES: Dictionary = {
	"slate":      Color(0.48, 0.54, 0.62),
	"burgundy":   Color(0.58, 0.34, 0.30),
	"ochre":      Color(0.84, 0.66, 0.40),
	"terracotta": Color(0.82, 0.44, 0.30),
}

## 50 non-overlapping buildings across 6 rings/districts:
## 8 Cardinal Gate Towers + 4 Corner Bastion Watchtowers + 10 Inner Square Landmarks +
## 4 Diagonal (45 deg) Plaza Corner Townhouses + 4 Mid-Avenue Shops + 4 Outer Avenue Manors +
## 16 Ring-Road District Houses/Workshops.
const HOUSE_SPECS: Array[Dictionary] = [
	# --- 1. 8 Cardinal Gatehouse Towers ---
	{"name": "GateTowerWest",        "offset": Vector2(-4.5, -52.5),  "w": 4, "d": 4,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": 0.0,              "is_tower": true,  "open_door": false, "civic": true},
	{"name": "GateTowerEast",        "offset": Vector2( 4.5, -52.5),  "w": 4, "d": 4,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": 0.0,              "is_tower": true,  "open_door": false, "civic": true},
	{"name": "SouthGateWest",        "offset": Vector2(-4.5,  52.5),  "w": 4, "d": 4,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": PI,               "is_tower": true,  "open_door": false, "civic": true},
	{"name": "SouthGateEast",        "offset": Vector2( 4.5,  52.5),  "w": 4, "d": 4,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": PI,               "is_tower": true,  "open_door": false, "civic": true},
	{"name": "WestGateTowerNorth",   "offset": Vector2(-58.5, -4.5),  "w": 4, "d": 4,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": PI * 0.5,         "is_tower": true,  "open_door": false, "civic": true},
	{"name": "WestGateTowerSouth",   "offset": Vector2(-58.5,  4.5),  "w": 4, "d": 4,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": PI * 0.5,         "is_tower": true,  "open_door": false, "civic": true},
	{"name": "EastGatehouseTower",   "offset": Vector2( 58.5, -4.5),  "w": 4, "d": 4,  "stories": 3, "style": "brick",   "roof": "slate",      "yaw": -PI * 0.5,        "is_tower": true,  "open_door": false, "civic": true},
	{"name": "EastGateSouthTower",   "offset": Vector2( 58.5,  4.5),  "w": 4, "d": 4,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": -PI * 0.5,        "is_tower": true,  "open_door": false, "civic": true},

	# --- 2. 4 Corner Bastion Watchtowers (Octagonal Perimeter Anchors) ---
	{"name": "NWWatchtower",         "offset": Vector2(-45.0, -41.0), "w": 4, "d": 4,  "stories": 3, "style": "brick",   "roof": "slate",      "yaw": PI * 0.25,        "is_tower": true,  "open_door": false, "civic": true},
	{"name": "NEWatchtower",         "offset": Vector2( 45.0, -41.0), "w": 4, "d": 4,  "stories": 3, "style": "brick",   "roof": "slate",      "yaw": -PI * 0.25,       "is_tower": true,  "open_door": false, "civic": true},
	{"name": "SWWatchtower",         "offset": Vector2(-45.0,  41.0), "w": 4, "d": 4,  "stories": 3, "style": "brick",   "roof": "slate",      "yaw": PI * 0.75,        "is_tower": true,  "open_door": false, "civic": true},
	{"name": "SEWatchtower",         "offset": Vector2( 45.0,  41.0), "w": 4, "d": 4,  "stories": 3, "style": "brick",   "roof": "slate",      "yaw": -PI * 0.75,       "is_tower": true,  "open_door": false, "civic": true},

	# --- 3. 10 Inner Market Square Civic & Guild Landmarks ---
	{"name": "Guildhall",            "offset": Vector2( -8.5, -20.5), "w": 8, "d": 10, "stories": 3, "style": "plaster", "roof": "slate",      "yaw": 0.0,              "is_tower": false, "open_door": true,  "civic": true},
	{"name": "GuildBellTower",       "offset": Vector2(-14.8, -24.0), "w": 4, "d": 4,  "stories": 3, "style": "brick",   "roof": "slate",      "yaw": 0.0,              "is_tower": true,  "open_door": false, "civic": true},
	{"name": "VillageAbbey",         "offset": Vector2(  8.5, -20.5), "w": 8, "d": 10, "stories": 2, "style": "brick",   "roof": "slate",      "yaw": 0.0,              "is_tower": false, "open_door": true,  "civic": true},
	{"name": "AbbeySpireTower",      "offset": Vector2( 14.8, -24.0), "w": 4, "d": 4,  "stories": 3, "style": "brick",   "roof": "slate",      "yaw": 0.0,              "is_tower": true,  "open_door": false, "civic": true},
	{"name": "MerchantExchange",     "offset": Vector2( -8.5,  20.5), "w": 8, "d": 8,  "stories": 2, "style": "plaster", "roof": "burgundy",   "yaw": PI,               "is_tower": false, "open_door": true,  "civic": true},
	{"name": "Blacksmith",           "offset": Vector2(  8.5,  20.5), "w": 6, "d": 8,  "stories": 2, "style": "brick",   "roof": "terracotta", "yaw": PI,               "is_tower": false, "open_door": true,  "civic": false, "wing": {"local_off": Vector2(0.8, -5.6), "w": 4, "d": 4, "stories": 1, "style": "brick"}},
	{"name": "GoldenSlimeInn",       "offset": Vector2(-20.5,  -8.2), "w": 8, "d": 8,  "stories": 3, "style": "plaster", "roof": "burgundy",   "yaw": PI * 0.5,         "is_tower": false, "open_door": true,  "civic": true},
	{"name": "Bakery",               "offset": Vector2(-20.5,   8.2), "w": 6, "d": 8,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": PI * 0.5,         "is_tower": false, "open_door": true,  "civic": false},
	{"name": "MarketHall",           "offset": Vector2( 20.5,  -8.2), "w": 8, "d": 8,  "stories": 2, "style": "brick",   "roof": "burgundy",   "yaw": -PI * 0.5,        "is_tower": false, "open_door": true,  "civic": true},
	{"name": "Apothecary",           "offset": Vector2( 20.5,   8.2), "w": 6, "d": 8,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": -PI * 0.5,        "is_tower": false, "open_door": false, "civic": false},

	# --- 4. 4 Diagonal (45 deg) Plaza Corner Townhouses ---
	{"name": "CornerTavernNW",       "offset": Vector2(-19.8, -17.2), "w": 4, "d": 6,  "stories": 2, "style": "plaster", "roof": "burgundy",   "yaw": PI * 0.25,        "is_tower": false, "open_door": false, "civic": false},
	{"name": "ClockmakerHouseNE",    "offset": Vector2( 19.8, -17.2), "w": 4, "d": 6,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": -PI * 0.25,       "is_tower": false, "open_door": false, "civic": false},
	{"name": "JewelerHouseSW",       "offset": Vector2(-19.5,  16.8), "w": 4, "d": 6,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": PI * 0.75,        "is_tower": false, "open_door": false, "civic": false},
	{"name": "ScribeManorSE",        "offset": Vector2( 19.5,  16.8), "w": 4, "d": 6,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": -PI * 0.75,       "is_tower": false, "open_door": false, "civic": false},

	# --- 5. 4 Mid-Avenue Artisan Shops (between Plaza & Ring Road) ---
	{"name": "InnKitchenWing",       "offset": Vector2(-29.5,  -8.5), "w": 4, "d": 6,  "stories": 1, "style": "brick",   "roof": "burgundy",   "yaw": 0.05,             "is_tower": false, "open_door": false, "civic": false},
	{"name": "CobblerShop",          "offset": Vector2(-29.5,   8.5), "w": 4, "d": 6,  "stories": 2, "style": "plaster", "roof": "terracotta", "yaw": PI - 0.05,        "is_tower": false, "open_door": false, "civic": false},
	{"name": "SpiceMerchant",        "offset": Vector2( 29.5,  -8.5), "w": 4, "d": 6,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": -0.05,            "is_tower": false, "open_door": false, "civic": false},
	{"name": "ArmorerForge",         "offset": Vector2( 29.5,   8.5), "w": 4, "d": 6,  "stories": 1, "style": "brick",   "roof": "terracotta", "yaw": PI + 0.05,        "is_tower": false, "open_door": false, "civic": false},

	# --- 6. 4 Outer Avenue L-Wing Manors ---
	{"name": "WeaverManor",          "offset": Vector2(-46.0,  -9.0), "w": 6, "d": 8,  "stories": 2, "style": "plaster", "roof": "burgundy",   "yaw": -0.06,            "is_tower": false, "open_door": false, "civic": false, "wing": {"local_off": Vector2(-0.8, -5.8), "w": 4, "d": 4, "stories": 1, "style": "plaster"}},
	{"name": "CarpenterShop",        "offset": Vector2(-46.0,   9.0), "w": 6, "d": 8,  "stories": 2, "style": "brick",   "roof": "terracotta", "yaw": PI + 0.06,        "is_tower": false, "open_door": false, "civic": false, "wing": {"local_off": Vector2( 0.8, -5.8), "w": 4, "d": 4, "stories": 1, "style": "brick"}},
	{"name": "TailorHouse",          "offset": Vector2( 46.0,  -9.0), "w": 6, "d": 8,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": 0.06,             "is_tower": false, "open_door": false, "civic": false, "wing": {"local_off": Vector2( 0.8, -5.8), "w": 4, "d": 4, "stories": 1, "style": "brick"}},
	{"name": "MerchantHouse",        "offset": Vector2( 46.0,   9.0), "w": 6, "d": 8,  "stories": 2, "style": "plaster", "roof": "burgundy",   "yaw": PI - 0.06,        "is_tower": false, "open_door": false, "civic": false, "wing": {"local_off": Vector2(-0.8, -5.8), "w": 4, "d": 4, "stories": 1, "style": "plaster"}},

	# --- 7. 16 Ring-Road District Houses & Workshops (4 Quadrants) ---
	{"name": "NorthWatchBarracks",   "offset": Vector2( -9.5, -41.0), "w": 6, "d": 8,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": 0.04,             "is_tower": false, "open_door": false, "civic": true},
	{"name": "OrchardStewardCottage","offset": Vector2(-23.5, -40.5), "w": 6, "d": 6,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": -0.05,            "is_tower": false, "open_door": false, "civic": false},
	{"name": "GranaryBarn",          "offset": Vector2(  9.5, -41.0), "w": 6, "d": 8,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": -0.04,            "is_tower": false, "open_door": false, "civic": false},
	{"name": "CandlemakerShop",      "offset": Vector2( 23.5, -40.5), "w": 6, "d": 6,  "stories": 2, "style": "plaster", "roof": "terracotta", "yaw": 0.05,             "is_tower": false, "open_door": false, "civic": false},

	{"name": "MillerHouse",          "offset": Vector2( -9.5,  41.0), "w": 6, "d": 8,  "stories": 2, "style": "plaster", "roof": "burgundy",   "yaw": PI - 0.04,        "is_tower": false, "open_door": false, "civic": false},
	{"name": "HerbalistLodge",       "offset": Vector2(-23.5,  40.5), "w": 6, "d": 6,  "stories": 1, "style": "plaster", "roof": "terracotta", "yaw": PI + 0.05,        "is_tower": false, "open_door": false, "civic": false},
	{"name": "BreweryHall",          "offset": Vector2(  9.5,  41.0), "w": 6, "d": 8,  "stories": 2, "style": "brick",   "roof": "burgundy",   "yaw": PI + 0.04,        "is_tower": false, "open_door": false, "civic": false},
	{"name": "PotteryCottage",       "offset": Vector2( 23.5,  40.5), "w": 6, "d": 6,  "stories": 1, "style": "brick",   "roof": "terracotta", "yaw": PI - 0.05,        "is_tower": false, "open_door": false, "civic": false},

	{"name": "CooperCottage",        "offset": Vector2(-28.5, -22.5), "w": 4, "d": 6,  "stories": 1, "style": "plaster", "roof": "terracotta", "yaw": -PI * 0.5 + 0.05, "is_tower": false, "open_door": false, "civic": false},
	{"name": "InnStablesWing",       "offset": Vector2(-28.5,  22.5), "w": 4, "d": 6,  "stories": 1, "style": "brick",   "roof": "ochre",      "yaw": -PI * 0.5 - 0.05, "is_tower": false, "open_door": false, "civic": false},
	{"name": "TanneryWorkshop",      "offset": Vector2(-45.0, -22.5), "w": 6, "d": 6,  "stories": 1, "style": "brick",   "roof": "terracotta", "yaw": PI * 0.5 - 0.05,  "is_tower": false, "open_door": false, "civic": false},
	{"name": "FletcherCottage",      "offset": Vector2(-45.0,  22.5), "w": 6, "d": 6,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": PI * 0.5 + 0.05,  "is_tower": false, "open_door": false, "civic": false},

	{"name": "DyerCottage",          "offset": Vector2( 28.5, -22.5), "w": 4, "d": 6,  "stories": 2, "style": "plaster", "roof": "ochre",      "yaw": PI * 0.5 - 0.05,  "is_tower": false, "open_door": false, "civic": false},
	{"name": "GlassblowerShop",      "offset": Vector2( 28.5,  22.5), "w": 4, "d": 6,  "stories": 1, "style": "brick",   "roof": "terracotta", "yaw": PI * 0.5 + 0.05,  "is_tower": false, "open_door": false, "civic": false},
	{"name": "WheelwrightShop",      "offset": Vector2( 45.0, -22.5), "w": 6, "d": 6,  "stories": 1, "style": "brick",   "roof": "terracotta", "yaw": -PI * 0.5 + 0.05, "is_tower": false, "open_door": false, "civic": false},
	{"name": "MasonWorkshop",        "offset": Vector2( 45.0,  22.5), "w": 6, "d": 6,  "stories": 2, "style": "brick",   "roof": "slate",      "yaw": -PI * 0.5 - 0.05, "is_tower": false, "open_door": false, "civic": false},
]

const STALL_SPECS: Array[Dictionary] = [
	{"offset": Vector2(-8.4, -8.6), "yaw": PI * 0.5,  "canopy": Color(0.56, 0.22, 0.18)},
	{"offset": Vector2(-8.4, -4.6), "yaw": PI * 0.5,  "canopy": Color(0.24, 0.40, 0.24)},
	{"offset": Vector2(-8.4,  4.6), "yaw": PI * 0.5,  "canopy": Color(0.64, 0.46, 0.20)},
	{"offset": Vector2(-8.4,  8.6), "yaw": PI * 0.5,  "canopy": Color(0.24, 0.34, 0.48)},
	{"offset": Vector2( 8.4, -8.6), "yaw": -PI * 0.5, "canopy": Color(0.54, 0.28, 0.20)},
	{"offset": Vector2( 8.4, -4.6), "yaw": -PI * 0.5, "canopy": Color(0.62, 0.48, 0.28)},
	{"offset": Vector2( 8.4,  4.6), "yaw": -PI * 0.5, "canopy": Color(0.24, 0.40, 0.24)},
	{"offset": Vector2( 8.4,  8.6), "yaw": -PI * 0.5, "canopy": Color(0.24, 0.34, 0.48)},
]

## Positioned on Plaza aprons, avenue verges, and Ring Road corners clearly away from stalls & porches.
const WAGON_SPECS: Array[Dictionary] = [
	{"offset": Vector2( -5.2, -11.4), "yaw":  1.52},
	{"offset": Vector2(  5.2,  11.4), "yaw": -1.52},
	{"offset": Vector2(-39.8,   3.6), "yaw":  1.50},
	{"offset": Vector2( 39.8,  -3.6), "yaw": -1.50},
	{"offset": Vector2(-17.5, -35.8), "yaw":  1.55},
]

## Positioned at plaza inner ring, cardinal avenues, and ring road intersections.
const LANTERN_OFFSETS: Array[Vector2] = [
	Vector2(-3.6, -3.6),
	Vector2( 3.6, -3.6),
	Vector2(-3.6,  3.6),
	Vector2( 3.6,  3.6),
	Vector2(-3.2, -12.8),
	Vector2( 3.2, -12.8),
	Vector2(-3.2,  12.8),
	Vector2( 3.2,  12.8),
	Vector2(-12.8, -3.2),
	Vector2(-12.8,  3.2),
	Vector2( 12.8, -3.2),
	Vector2( 12.8,  3.2),
	Vector2(-3.2, -26.0),
	Vector2( 3.2, -26.0),
	Vector2(-3.2, -37.0),
	Vector2( 3.2, -37.0),
	Vector2(-3.2, -47.5),
	Vector2( 3.2, -47.5),
	Vector2(-3.2,  26.0),
	Vector2( 3.2,  26.0),
	Vector2(-3.2,  37.0),
	Vector2( 3.2,  37.0),
	Vector2(-3.2,  47.5),
	Vector2( 3.2,  47.5),
	Vector2(-26.0, -3.0),
	Vector2(-40.5, -3.0),
	Vector2(-53.0, -3.0),
	Vector2( 26.0,  3.0),
	Vector2( 40.5,  3.0),
	Vector2( 53.0,  3.0),
	Vector2(-33.5, -29.5),
	Vector2( 33.5, -29.5),
	Vector2(-33.5,  29.5),
	Vector2( 33.5,  29.5),
]

## 24 Curated town trees in cloister courts, outer paddocks, orchard yards, and outside all 4 town gates.
const TREE_SPECS: Array[Dictionary] = [
	{"offset": Vector2(-15.0, -56.0), "arch": 0, "scale": 1.06, "yaw": 0.4},
	{"offset": Vector2( 15.0, -56.0), "arch": 4, "scale": 1.02, "yaw": 1.7},
	{"offset": Vector2(-30.0, -51.5), "arch": 6, "scale": 1.12, "yaw": 2.3},
	{"offset": Vector2( 30.0, -51.5), "arch": 0, "scale": 1.08, "yaw": 0.9},
	{"offset": Vector2(-15.0,  56.0), "arch": 4, "scale": 1.04, "yaw": 3.1},
	{"offset": Vector2( 15.0,  56.0), "arch": 6, "scale": 1.10, "yaw": 4.2},
	{"offset": Vector2(-30.0,  51.5), "arch": 0, "scale": 1.05, "yaw": 1.2},
	{"offset": Vector2( 30.0,  51.5), "arch": 4, "scale": 1.00, "yaw": 2.9},
	{"offset": Vector2(-62.5, -13.5), "arch": 0, "scale": 1.04, "yaw": 1.1},
	{"offset": Vector2(-62.5,  13.5), "arch": 4, "scale": 0.98, "yaw": 2.8},
	{"offset": Vector2( 62.5, -13.5), "arch": 6, "scale": 1.08, "yaw": 5.0},
	{"offset": Vector2( 62.5,  13.5), "arch": 0, "scale": 1.02, "yaw": 0.6},
	{"offset": Vector2(-21.2, -25.8), "arch": 4, "scale": 0.96, "yaw": 2.4},
	{"offset": Vector2( 21.2, -25.8), "arch": 6, "scale": 0.98, "yaw": 0.7},
	{"offset": Vector2(-19.5,  25.5), "arch": 0, "scale": 1.02, "yaw": 3.7},
	{"offset": Vector2( 19.5,  25.5), "arch": 4, "scale": 0.96, "yaw": 1.9},
	{"offset": Vector2(-34.5, -39.2), "arch": 6, "scale": 1.08, "yaw": 4.6},
	{"offset": Vector2( 34.5, -39.2), "arch": 0, "scale": 1.04, "yaw": 2.1},
	{"offset": Vector2(-34.5,  39.2), "arch": 4, "scale": 1.00, "yaw": 0.8},
	{"offset": Vector2( 34.5,  39.2), "arch": 6, "scale": 1.06, "yaw": 3.4},
	{"offset": Vector2(-42.5, -32.0), "arch": 0, "scale": 1.02, "yaw": 5.2},
	{"offset": Vector2( 42.5, -32.0), "arch": 4, "scale": 0.98, "yaw": 1.5},
	{"offset": Vector2(-42.5,  32.0), "arch": 6, "scale": 1.04, "yaw": 2.7},
	{"offset": Vector2( 42.5,  32.0), "arch": 0, "scale": 1.00, "yaw": 4.1},
]

const CRATE_CLUSTERS: Array[Dictionary] = [
	{"offset": Vector2( -6.8, -48.5), "count": 2, "yaw":  0.25},
	{"offset": Vector2(  6.8, -48.5), "count": 2, "yaw": -0.30},
	{"offset": Vector2(-14.2, -14.8), "count": 2, "yaw":  0.40},
	{"offset": Vector2( 14.2, -14.8), "count": 1, "yaw":  0.10},
	{"offset": Vector2(-25.8,  -4.5), "count": 3, "yaw":  0.55},
	{"offset": Vector2(-32.8,   4.4), "count": 2, "yaw": -0.20},
	{"offset": Vector2( 25.8,  -4.5), "count": 3, "yaw":  0.35},
	{"offset": Vector2( 25.8,   4.5), "count": 2, "yaw": -0.45},
	{"offset": Vector2(  5.2,  48.0), "count": 2, "yaw":  0.20},
	{"offset": Vector2(-15.5,  28.2), "count": 2, "yaw":  0.15},
	{"offset": Vector2(-40.2, -14.2), "count": 2, "yaw": -0.35},
	{"offset": Vector2( 40.2,  14.2), "count": 2, "yaw":  0.42},
]

## Split-rail paddock fences framing outer corner greens & inner ward gardens (strictly off streets/buildings).
const FENCE_RUNS: Array[Dictionary] = [
	{"a": Vector2(-41.5, -36.5), "b": Vector2(-28.5, -36.5)},
	{"a": Vector2( 28.5, -36.5), "b": Vector2( 41.5, -36.5)},
	{"a": Vector2(-41.5,  36.5), "b": Vector2(-28.5,  36.5)},
	{"a": Vector2( 28.5,  36.5), "b": Vector2( 41.5,  36.5)},
	{"a": Vector2(-24.5, -28.0), "b": Vector2(-17.5, -28.0)},
	{"a": Vector2( 17.5, -28.0), "b": Vector2( 24.5, -28.0)},
	{"a": Vector2(-24.5,  28.0), "b": Vector2(-16.5,  28.0)},
	{"a": Vector2( 16.5,  28.0), "b": Vector2( 24.5,  28.0)},
]

var _mesh_cache: Dictionary = {}
var _roof_mesh_cache: Dictionary = {}
var _roof_mat_cache: Dictionary = {}
var _mat_cache: Dictionary = {}
var _mat_sig_cache: Dictionary = {}
var _tex_sig_cache: Dictionary = {}
var _ext_scene_cache: Dictionary = {}
var _color_mat_cache: Dictionary = {}
var _smoke_mesh: QuadMesh = null
var _smoke_pmat: ParticleProcessMaterial = null
var _gray_tile_tex: Texture2D = null
var _mat_stone_foundation: StandardMaterial3D
var _mat_cobble: StandardMaterial3D
var _mat_plaza_brick: StandardMaterial3D
var _mat_packed_mud: StandardMaterial3D
var _mat_wood_trim: StandardMaterial3D
var _mat_wood_dark: StandardMaterial3D
var _mat_dock_oak: StandardMaterial3D
var _mat_rope: StandardMaterial3D
var _mat_iron: StandardMaterial3D
var _mat_lantern_glow: StandardMaterial3D
var _mat_window_glow: StandardMaterial3D
var _mat_well_water: StandardMaterial3D
var _mat_coastal_rock: StandardMaterial3D
var _night_lights: Array[Dictionary] = []
var _occluder_target_name: String = ""
var _dock_shore_xy: Vector2 = Vector2.ZERO
var _dock_cottage_xy: Vector2 = Vector2.ZERO
var _dock_yaw: float = 0.0

static var _cached_dock_ready: bool = false
static var _cached_gate_xy: Vector2 = Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z + 55.0 * V_SCALE)
static var _cached_ctrl_xy: Vector2 = Vector2(637.4, 2376.6)
static var _cached_entry_xy: Vector2 = Vector2(654.0, 2438.0)
static var _cached_shore_xy: Vector2 = Vector2(656.6, 2448.0)
static var _cached_cottage_xy: Vector2 = Vector2(633.0, 2402.0)
static var _cached_spur_a: Vector2 = Vector2(648.5, 2418.0)
static var _cached_spur_b: Vector2 = Vector2(628.0, 2403.5)


static func _sample_h_static(terrain: Node3D, wx: float, wz: float) -> float:
	if terrain == null:
		return 20.0
	if terrain.has_method("sample_surface_exact"):
		var res := terrain.call("sample_surface_exact", wx, wz) as Vector4
		return float(res.w)
	if terrain.has_method("sample_height"):
		return float(terrain.call("sample_height", wx, wz))
	return 20.0


static func ensure_dock_layout(terrain: Node3D) -> void:
	if terrain == null:
		return
	var v_xz := Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z)
	var shore_guess := v_xz + v_xz.normalized() * 257.0
	var eps := 18.0
	var hL := _sample_h_static(terrain, shore_guess.x - eps, shore_guess.y)
	var hR := _sample_h_static(terrain, shore_guess.x + eps, shore_guess.y)
	var hU := _sample_h_static(terrain, shore_guess.x, shore_guess.y - eps)
	var hD := _sample_h_static(terrain, shore_guess.x, shore_guess.y + eps)
	var sea_normal := Vector2(hL - hR, hU - hD)
	if sea_normal.length_squared() < 0.0001:
		sea_normal = v_xz.normalized()
	else:
		sea_normal = sea_normal.normalized()

	var shore_xy := shore_guess
	for step_i in range(56):
		var cand := shore_guess - sea_normal * 40.0 + sea_normal * (float(step_i) * 2.0)
		if _sample_h_static(terrain, cand.x, cand.y) <= 0.0:
			shore_xy = cand
			break

	var dock_yaw := atan2(sea_normal.x, sea_normal.y)
	var tangent := Vector2(-sea_normal.y, sea_normal.x)
	var d_basis := Basis(Vector3.UP, dock_yaw)
	var cottage_xy := shore_xy - sea_normal * 44.0 + tangent * 12.0
	var gate_xy := Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z + 55.0 * V_SCALE)
	var entry_w := Vector3(shore_xy.x, 0.0, shore_xy.y) + d_basis * Vector3(0.0, 0.0, -10.35)
	var entry_xy := Vector2(entry_w.x, entry_w.z)
	var ctrl_xy := entry_xy - sea_normal * 64.0
	var t_spur := float(40) / 48.0
	var omt_spur := 1.0 - t_spur
	var spur_a := omt_spur * omt_spur * gate_xy + 2.0 * omt_spur * t_spur * ctrl_xy + t_spur * t_spur * entry_xy
	var spur_b := cottage_xy - tangent * (3.8 * V_SCALE)

	_cached_gate_xy = gate_xy
	_cached_ctrl_xy = ctrl_xy
	_cached_entry_xy = entry_xy
	_cached_shore_xy = shore_xy
	_cached_cottage_xy = cottage_xy
	_cached_spur_a = spur_a
	_cached_spur_b = spur_b
	_cached_dock_ready = true


static func is_in_village_exclusion(x: float, z: float, is_grass: bool = false) -> bool:
	var dx: float = x - VILLAGE_CENTER.x
	var dz: float = z - VILLAGE_CENTER.z
	if dz > 50.0 and dz < 350.0 and dx > -65.0 and dx < 165.0:
		# Exclude trees/rocks/grass along the exact coastal PierPathway curve, CottageCobbleSpur, FishermanCottage yard & cove
		var pt := Vector2(x, z)
		var b0 := _cached_gate_xy
		var b1 := _cached_ctrl_xy
		var b2 := _cached_entry_xy
		var min_path_d := 1e9
		var q_prev := b0
		const PATH_SEGS := 24
		for si in range(1, PATH_SEGS + 1):
			var ta := float(si) / float(PATH_SEGS)
			var omta := 1.0 - ta
			var q := omta * omta * b0 + 2.0 * omta * ta * b1 + ta * ta * b2
			var c_pt := Geometry2D.get_closest_point_to_segment(pt, q_prev, q)
			min_path_d = minf(min_path_d, pt.distance_to(c_pt))
			q_prev = q
		if min_path_d <= (4.8 if is_grass else 10.5):
			return true
		var spur_c := Geometry2D.get_closest_point_to_segment(pt, _cached_spur_a, _cached_spur_b)
		if pt.distance_to(spur_c) <= (3.6 if is_grass else 8.0):
			return true
		# Cove & dock shoreline
		if pt.distance_to(_cached_shore_xy) <= (24.0 if is_grass else 32.0):
			return true
		if pt.distance_to(Vector2(VILLAGE_CENTER.x + 80.0, VILLAGE_CENTER.z + 247.0)) <= (24.0 if is_grass else 32.0):
			return true
		# Fisherman's Cottage clear perimeter
		if pt.distance_to(_cached_cottage_xy) <= (15.0 if is_grass else 22.0):
			return true
		if pt.distance_to(Vector2(VILLAGE_CENTER.x + 38.0, VILLAGE_CENTER.z + 263.0)) <= (15.0 if is_grass else 22.0):
			return true
	if absf(dx) > VILLAGE_RADIUS_X + 6.0 or absf(dz) > VILLAGE_RADIUS_Z + 6.0:
		return false

	if not is_grass:
		var nx: float = dx / VILLAGE_RADIUS_X
		var nz: float = dz / VILLAGE_RADIUS_Z
		return nx * nx + nz * nz <= 1.0

	# Grass exclusion: keep Grand Market Square, Ring Road & Cardinal Avenues (including outer gate thresholds) free of 3D grass blades
	# while allowing lush meadow grass to grow inside cloister gardens, paddocks, and outer orchards.
	if absf(dx) <= 22.5 * V_SCALE and absf(dz) <= 22.0 * V_SCALE:
		return true
	if absf(dx) <= 64.5 * V_SCALE and absf(dz) <= 10.8 * V_SCALE:
		return true
	if absf(dx) <= 11.8 * V_SCALE and absf(dz) <= 58.5 * V_SCALE:
		return true
	if absf(absf(dx) - 36.0 * V_SCALE) <= 7.8 * V_SCALE and absf(dz) <= 38.2 * V_SCALE:
		return true
	if absf(absf(dz) - 32.0 * V_SCALE) <= 7.8 * V_SCALE and absf(dx) <= 40.8 * V_SCALE:
		return true

	for spec in HOUSE_SPECS:
		var off: Vector2 = spec["offset"] * V_SCALE
		var yaw: float = spec["yaw"]
		var px: float = dx - off.x
		var pz: float = dz - off.y
		var c: float = cos(yaw)
		var s: float = sin(yaw)
		var lx: float = px * c - pz * s
		var lz: float = px * s + pz * c
		var hw: float = float(spec["w"]) * V_SCALE * 0.5 + 1.8
		var hd: float = float(spec["d"]) * V_SCALE * 0.5 + 2.4
		if absf(lx) <= hw and absf(lz) <= hd:
			return true
		if spec.has("wing"):
			var wing: Dictionary = spec["wing"]
			var loff: Vector2 = wing["local_off"] * V_SCALE
			var w_hw: float = float(wing.get("w", 4)) * V_SCALE * 0.5 + 1.2
			var w_hd: float = float(wing.get("d", 4)) * V_SCALE * 0.5 + 1.2
			if absf(lx - loff.x) <= w_hw and absf(lz - loff.y) <= w_hd:
				return true

	for stall in STALL_SPECS:
		var soff: Vector2 = stall["offset"] * V_SCALE
		if absf(dx - soff.x) <= 2.2 * V_SCALE and absf(dz - soff.y) <= 2.2 * V_SCALE:
			return true

	for wag in WAGON_SPECS:
		var woff: Vector2 = wag["offset"] * V_SCALE
		if Vector2(dx - woff.x, dz - woff.y).length_squared() <= 10.24 * V_SCALE * V_SCALE:
			return true

	return false


static func _compute_village_sig(terrain: Node3D) -> String:
	var tseed := int(terrain.get("terrain_seed")) if terrain != null and "terrain_seed" in terrain else 0
	var script_md5 := FileAccess.get_md5("res://terrain/village_builder.gd")
	return "v1|%s|%d|%d|%s" % [str(VILLAGE_CENTER), HOUSE_SPECS.size(), tseed, script_md5]


static func _set_owner_recursive(node: Node, owner_root: Node) -> void:
	for ch in node.get_children():
		ch.owner = owner_root
		_set_owner_recursive(ch, owner_root)


static func _restore_cached_village_refs(root: Node3D) -> void:
	var lights: Array = []
	var lantern_mat: StandardMaterial3D = null
	var window_mat: StandardMaterial3D = null
	var mat_cobble: StandardMaterial3D = null
	var mat_plaza: StandardMaterial3D = null
	var mat_mud: StandardMaterial3D = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is OmniLight3D and cur.has_meta("night_base_e"):
			lights.append({"light": cur, "base": float(cur.get_meta("night_base_e"))})
		elif cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var mats: Array[Material] = []
			if mi.material_override != null:
				mats.append(mi.material_override)
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					var sm := mi.get_active_material(si)
					if sm != null:
						mats.append(sm)
			for m in mats:
				if m is StandardMaterial3D:
					match m.resource_name:
						"VillageLanternGlow": lantern_mat = m as StandardMaterial3D
						"VillageWindowGlow": window_mat = m as StandardMaterial3D
						"VillageCobble": mat_cobble = m as StandardMaterial3D
						"VillagePlazaBrick": mat_plaza = m as StandardMaterial3D
						"VillagePackedMud": mat_mud = m as StandardMaterial3D
		for gc in cur.get_children():
			stack.append(gc)
	root.set_meta("village_lights", lights)
	if lantern_mat != null:
		root.set_meta("lantern_mat", lantern_mat)
	if window_mat != null:
		root.set_meta("window_mat", window_mat)
	var cobbles: Array = []
	if mat_cobble != null: cobbles.append(mat_cobble)
	if mat_plaza != null: cobbles.append(mat_plaza)
	if mat_mud != null: cobbles.append(mat_mud)
	root.set_meta("cobble_mats", cobbles)


static func build_village(terrain: Node3D, village_region: Node = null) -> Node3D:
	var sig := _compute_village_sig(terrain)
	var root: Node3D = null
	if ResourceLoader.exists(VILLAGE_CACHE_PATH):
		var cached_ps := load(VILLAGE_CACHE_PATH) as PackedScene
		if cached_ps != null:
			var inst := cached_ps.instantiate() as Node3D
			if inst != null and String(inst.get_meta("vb_sig", "")) == sig:
				var old: Node = terrain.get_node_or_null("Village")
				if old != null:
					old.name = "Village_Old"
					old.queue_free()
				inst.name = "Village"
				terrain.add_child(inst)
				_restore_cached_village_refs(inst)
				update_night_lights(inst, 0.0, 0.0)
				root = inst
			elif inst != null:
				inst.free()

	if root == null:
		var script_res: GDScript = load("res://terrain/village_builder.gd") as GDScript
		var builder: VillageBuilder = script_res.new()
		root = builder._build_into(terrain)
		if root != null:
			root.set_meta("vb_sig", sig)
			var dir_abs := ProjectSettings.globalize_path(VILLAGE_CACHE_PATH.get_base_dir())
			DirAccess.make_dir_recursive_absolute(dir_abs)
			if DirAccess.dir_exists_absolute(dir_abs):
				_set_owner_recursive(root, root)
				var ps := PackedScene.new()
				if ps.pack(root) == OK:
					ResourceSaver.save(ps, VILLAGE_CACHE_PATH, ResourceSaver.FLAG_COMPRESS)

	if root != null and village_region != null and village_region.has_method("get_profile"):
		var vp = village_region.call("get_profile")
		if vp != null:
			root.set_meta("harbor_ropes_decorative_only", bool(vp.get("harbor_ropes_decorative_only")))
	return root


static func update_night_lights(village_root: Node, strength: float, wetness: float = 0.0) -> void:
	if village_root == null or not is_instance_valid(village_root):
		return
	var s := clampf(strength, 0.0, 1.0)
	var w := clampf(wetness, 0.0, 1.0)
	var lights: Array = village_root.get_meta("village_lights", []) as Array
	for item in lights:
		var d: Dictionary = item
		var omni: OmniLight3D = d.get("light") as OmniLight3D
		if omni != null and is_instance_valid(omni):
			var base_e: float = float(d.get("base", 1.25))
			omni.visible = s > 0.02
			omni.light_energy = base_e * s
	var l_mat := village_root.get_meta("lantern_mat", null) as StandardMaterial3D
	if l_mat != null:
		l_mat.emission_energy_multiplier = lerpf(0.06, 3.8, s)
	var w_mat := village_root.get_meta("window_mat", null) as StandardMaterial3D
	if w_mat != null:
		w_mat.emission_energy_multiplier = lerpf(0.03, 1.55, s)
	var cobbles: Array = village_root.get_meta("cobble_mats", []) as Array
	for cm in cobbles:
		var sm := cm as StandardMaterial3D
		if sm != null:
			sm.roughness = lerpf(0.92, 0.36, w)
			sm.metallic_specular = lerpf(0.08, 0.30, w)


func _register_night_light(light: OmniLight3D, base_energy: float) -> void:
	light.set_meta("night_base_e", base_energy)
	_night_lights.append({"light": light, "base": base_energy})


func _build_into(terrain: Node3D) -> Node3D:
	var old: Node = terrain.get_node_or_null("Village")
	if old != null:
		old.name = "Village_Old"
		old.queue_free()

	_night_lights.clear()
	_init_shared_materials()

	var root := Node3D.new()
	root.name = "Village"
	terrain.add_child(root)

	var colliders := StaticBody3D.new()
	colliders.name = "VillageColliders"
	colliders.collision_layer = LAYER_OBSTACLES
	colliders.collision_mask = 0
	root.add_child(colliders)

	var plaza_center_top := _build_plaza_and_roads(root, colliders, terrain)

	var floor_heights: Dictionary = {}
	for spec in HOUSE_SPECS:
		var fy := _build_house(root, colliders, terrain, spec)
		floor_heights[String(spec["name"])] = fy

	# 4 Arched Town Gateways framing every main avenue approach on the Octagonal Perimeter
	var north_y: float = maxf(float(floor_heights.get("GateTowerWest", VILLAGE_CENTER.y)), float(floor_heights.get("GateTowerEast", VILLAGE_CENTER.y)))
	_build_gatehouse_bridge(root, colliders, "NorthGateBridge", Vector2(0.0, -52.5) * V_SCALE, 0.0, north_y)
	var south_y: float = maxf(float(floor_heights.get("SouthGateWest", VILLAGE_CENTER.y)), float(floor_heights.get("SouthGateEast", VILLAGE_CENTER.y)))
	_build_gatehouse_bridge(root, colliders, "SouthGateBridge", Vector2(0.0, 52.5) * V_SCALE, PI, south_y)
	var west_y: float = maxf(float(floor_heights.get("WestGateTowerNorth", VILLAGE_CENTER.y)), float(floor_heights.get("WestGateTowerSouth", VILLAGE_CENTER.y)))
	_build_gatehouse_bridge(root, colliders, "WestGateBridge", Vector2(-58.5, 0.0) * V_SCALE, -PI * 0.5, west_y)
	var east_y: float = maxf(float(floor_heights.get("EastGatehouseTower", VILLAGE_CENTER.y)), float(floor_heights.get("EastGateSouthTower", VILLAGE_CENTER.y)))
	_build_gatehouse_bridge(root, colliders, "EastGateBridge", Vector2(58.5, 0.0) * V_SCALE, PI * 0.5, east_y)

	_build_well(root, colliders, terrain, plaza_center_top)
	_build_market_stalls(root, colliders, terrain)
	_build_street_lanterns(root, colliders, terrain)
	_build_town_trees(root, colliders, terrain)
	_build_props_and_fences(root, colliders, terrain)
	_build_plaza_bunting(root, terrain, plaza_center_top)
	_build_plaza_ambiance(root, plaza_center_top)
	_build_fishing_dock(root, colliders, terrain)
	_batch_village_meshes(root)

	root.set_meta("village_lights", _night_lights.duplicate())
	root.set_meta("lantern_mat", _mat_lantern_glow)
	root.set_meta("window_mat", _mat_window_glow)
	root.set_meta("cobble_mats", [_mat_cobble, _mat_plaza_brick, _mat_packed_mud])
	root.set_meta("dock_shore_xy", _dock_shore_xy)
	root.set_meta("dock_cottage_xy", _dock_cottage_xy)
	root.set_meta("dock_yaw", _dock_yaw)
	update_night_lights(root, 0.0, 0.0)

	return root


func _init_shared_materials() -> void:
	_mat_stone_foundation = _extract_floor_material("Prop_ExteriorBorder_Straight1.gltf", Color(0.78, 0.77, 0.74), Color(0.36, 0.35, 0.33))
	_mat_wood_trim = _extract_floor_material("Wall_Arch.gltf", Color(0.95, 0.92, 0.88), Color(0.46, 0.34, 0.22))
	_mat_wood_dark = _extract_floor_material("Wall_Arch.gltf", Color(0.68, 0.60, 0.52), Color(0.31, 0.21, 0.14))
	_mat_dock_oak = _make_matte_mat(Color(0.42, 0.28, 0.18), 0.92)
	_mat_rope = _make_matte_mat(Color(0.74, 0.61, 0.39), 0.96)
	_mat_iron = _make_matte_mat(Color(0.20, 0.21, 0.23), 0.88)
	_mat_well_water = _make_matte_mat(Color(0.14, 0.24, 0.28), 0.32)

	# Extract real cobblestone & red brick textures from loaded floor glTFs for seamless roads & plaza
	_mat_cobble = _extract_floor_material("Floor_UnevenBrick.gltf", Color(0.86, 0.85, 0.83), Color(0.45, 0.43, 0.40))
	_mat_cobble.resource_name = "VillageCobble"
	_mat_plaza_brick = _extract_floor_material("Floor_RedBrick.gltf", Color(0.90, 0.84, 0.80), Color(0.54, 0.38, 0.32))
	_mat_plaza_brick.resource_name = "VillagePlazaBrick"
	_mat_packed_mud = _make_matte_mat(Color(0.38, 0.30, 0.22), 0.96)
	_mat_packed_mud.resource_name = "VillagePackedMud"

	_mat_coastal_rock = _make_matte_mat(Color(0.62, 0.59, 0.53), 0.94)
	_mat_coastal_rock.metallic_specular = 0.06

	_mat_lantern_glow = StandardMaterial3D.new()
	_mat_lantern_glow.resource_name = "VillageLanternGlow"
	_mat_lantern_glow.albedo_color = Color(1.0, 0.90, 0.65)
	_mat_lantern_glow.roughness = 0.85
	_mat_lantern_glow.metallic = 0.0
	_mat_lantern_glow.metallic_specular = 0.08
	_mat_lantern_glow.emission_enabled = true
	_mat_lantern_glow.emission = Color(1.0, 0.74, 0.32)
	_mat_lantern_glow.emission_energy_multiplier = 3.8

	_mat_window_glow = StandardMaterial3D.new()
	_mat_window_glow.resource_name = "VillageWindowGlow"
	_mat_window_glow.albedo_color = Color(0.95, 0.76, 0.44)
	_mat_window_glow.roughness = 0.45
	_mat_window_glow.metallic = 0.0
	_mat_window_glow.metallic_specular = 0.12
	_mat_window_glow.emission_enabled = true
	_mat_window_glow.emission = Color(1.0, 0.68, 0.28)
	_mat_window_glow.emission_energy_multiplier = 1.55

	# Shared soft radial smoke puff mesh & process material for active hearth chimneys
	var simg := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for py in range(24):
		for px in range(24):
			var d := Vector2((float(px) + 0.5) / 12.0 - 1.0, (float(py) + 0.5) / 12.0 - 1.0).length()
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.7)
			simg.set_pixel(px, py, Color(1.0, 1.0, 1.0, a))
	var stex := ImageTexture.create_from_image(simg)
	var smat := StandardMaterial3D.new()
	smat.albedo_texture = stex
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.billboard_keep_scale = true
	smat.vertex_color_use_as_albedo = true
	smat.no_depth_test = false
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.size = Vector2(0.85, 0.85)
	_smoke_mesh.material = smat
	_smoke_pmat = ParticleProcessMaterial.new()
	_smoke_pmat.direction = Vector3(0.32, 1.0, 0.14)
	_smoke_pmat.spread = 16.0
	_smoke_pmat.initial_velocity_min = 0.85
	_smoke_pmat.initial_velocity_max = 1.35
	_smoke_pmat.gravity = Vector3(0.16, 0.14, 0.06)
	_smoke_pmat.scale_min = 0.55
	_smoke_pmat.scale_max = 1.35
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.92, 0.88, 0.0),
		Color(0.92, 0.90, 0.87, 0.34),
		Color(0.88, 0.88, 0.90, 0.18),
		Color(0.86, 0.86, 0.90, 0.0),
	])
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	_smoke_pmat.color_ramp = gtex


func _extract_floor_material(rel_path: String, tint: Color, fallback_col: Color) -> StandardMaterial3D:
	var mesh := _get_mesh(rel_path)
	if mesh != null and mesh.get_surface_count() > 0:
		var base := mesh.surface_get_material(0) as StandardMaterial3D
		if base != null and base.albedo_texture != null:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = base.albedo_texture
			mat.albedo_color = tint
			mat.roughness = 0.92
			mat.metallic = 0.0
			mat.metallic_specular = 0.08
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			return mat
	return _make_matte_mat(fallback_col, 0.92)


func _make_matte_mat(col: Color, rough: float = 0.90) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	mat.metallic = 0.0
	mat.metallic_specular = 0.08
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


func _sample_h(terrain: Node3D, wx: float, wz: float) -> float:
	if terrain.has_method("sample_surface_exact"):
		var res := terrain.call("sample_surface_exact", wx, wz) as Vector4
		return float(res.w)
	return float(terrain.call("sample_height", wx, wz))


func _sample_patch_minmax(terrain: Node3D, cx: float, cz: float, hx: float, hz: float, yaw: float = 0.0) -> Vector2:
	var min_h := INF
	var max_h := -INF
	var c := cos(yaw)
	var s := sin(yaw)
	for ix in [-1.0, 0.0, 1.0]:
		for iz in [-1.0, 0.0, 1.0]:
			var lx: float = ix * hx
			var lz: float = iz * hz
			var wx: float = cx + lx * c + lz * s
			var wz: float = cz - lx * s + lz * c
			var h := _sample_h(terrain, wx, wz)
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
	return Vector2(min_h, max_h)


func _is_runtime_animated_mat(mat: Material) -> bool:
	return mat == _mat_window_glow or mat == _mat_lantern_glow or mat == _mat_cobble or mat == _mat_plaza_brick or mat == _mat_packed_mud


func _texture_signature(tex: Texture2D) -> String:
	if tex == null:
		return "none"
	var tid: int = tex.get_instance_id()
	if _tex_sig_cache.has(tid):
		return String(_tex_sig_cache[tid])
	var sig := ""
	if tex.resource_path != "":
		sig = "p:" + tex.resource_path
	else:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var hc := HashingContext.new()
			hc.start(HashingContext.HASH_MD5)
			hc.update(img.get_data())
			sig = "i:%dx%d:%d:%s" % [img.get_width(), img.get_height(), int(img.get_format()), hc.finish().hex_encode()]
		else:
			sig = "id:%d" % tid
	_tex_sig_cache[tid] = sig
	return sig


func _material_signature(mat: StandardMaterial3D) -> String:
	var em_c: int = mat.emission.to_rgba32() if mat.emission_enabled else 0
	var em_e: int = int(round(mat.emission_energy_multiplier * 100.0)) if mat.emission_enabled else 0
	return "%s|%x|%d|%d|%d|%d|%d|%s|%s|%d|%x|%d|%s|%d" % [
		_texture_signature(mat.albedo_texture),
		mat.albedo_color.to_rgba32(),
		int(round(mat.roughness * 100.0)),
		int(mat.transparency),
		int(round(mat.alpha_scissor_threshold * 100.0)),
		int(mat.cull_mode),
		int(mat.shading_mode),
		str(mat.uv1_scale),
		str(mat.uv1_offset),
		int(mat.emission_enabled),
		em_c,
		em_e,
		_texture_signature(mat.normal_texture) if mat.normal_enabled else "none",
		int(mat.vertex_color_use_as_albedo),
	]


func _normalize_matte_material(src: Material) -> Material:
	if src == null or not (src is StandardMaterial3D):
		return src
	if _is_runtime_animated_mat(src):
		return src
	var rid: int = src.get_instance_id()
	if _mat_cache.has(rid):
		return _mat_cache[rid] as Material
	var mat: StandardMaterial3D = src.duplicate() as StandardMaterial3D
	mat.metallic = 0.0
	mat.metallic_specular = 0.08
	mat.roughness = maxf(mat.roughness, 0.88)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	# Opaque closed geometry uses CULL_BACK to prevent double-sided shadow acne & seam artifacts;
	# only alpha cutouts (leaves/vines) remain CULL_DISABLED.
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		mat.cull_mode = BaseMaterial3D.CULL_BACK
	else:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sig := _material_signature(mat)
	if _mat_sig_cache.has(sig):
		var shared := _mat_sig_cache[sig] as Material
		_mat_cache[rid] = shared
		return shared
	_mat_sig_cache[sig] = mat
	_mat_cache[rid] = mat
	return mat


func _get_mesh(rel_path: String) -> Mesh:
	if _mesh_cache.has(rel_path):
		return _mesh_cache[rel_path] as Mesh
	var full_path: String = ASSET_DIR + rel_path
	var scene := load(full_path) as PackedScene
	if scene == null:
		push_error("VillageBuilder: failed to load glTF scene: " + full_path)
		return null
	var inst := scene.instantiate()
	var mi := _find_first_mesh_instance(inst)
	var normalized_mesh: Mesh = null
	if mi != null and mi.mesh != null:
		normalized_mesh = mi.mesh.duplicate() as Mesh
		for si in range(normalized_mesh.get_surface_count()):
			var smat := normalized_mesh.surface_get_material(si)
			if smat != null:
				normalized_mesh.surface_set_material(si, _normalize_matte_material(smat))
	inst.free()
	_mesh_cache[rel_path] = normalized_mesh
	return normalized_mesh


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


func _get_gray_tile_texture(src_tex: Texture2D) -> Texture2D:
	if _gray_tile_tex != null:
		return _gray_tile_tex
	if ResourceLoader.exists(GRAY_TILE_TEX_PATH):
		var loaded := load(GRAY_TILE_TEX_PATH) as ImageTexture
		if loaded != null:
			_gray_tile_tex = loaded
			return _gray_tile_tex
	var img: Image = null
	var disk_tex := load(ASSET_DIR + "T_RoundTiles_BaseColor.png") as Texture2D
	if disk_tex != null:
		img = disk_tex.get_image()
	if (img == null or img.is_empty()) and src_tex != null:
		img = src_tex.get_image()
	if img == null or img.is_empty():
		var abs_p := ProjectSettings.globalize_path(ASSET_DIR + "T_RoundTiles_BaseColor.png")
		img = Image.load_from_file(abs_p)
	if img == null or img.is_empty():
		return src_tex
	var gimg := img.duplicate() as Image
	if gimg.is_compressed():
		gimg.decompress()
	gimg.clear_mipmaps()
	gimg.convert(Image.FORMAT_RGBA8)
	for py in range(gimg.get_height()):
		for px in range(gimg.get_width()):
			var c := gimg.get_pixel(px, py)
			var lum: float = clampf((c.r * 0.30 + c.g * 0.59 + c.b * 0.11) * 1.08, 0.0, 1.0)
			gimg.set_pixel(px, py, Color(lum, lum, lum, c.a))
	gimg.generate_mipmaps()
	_gray_tile_tex = ImageTexture.create_from_image(gimg)
	var dir_abs := ProjectSettings.globalize_path(GRAY_TILE_TEX_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir_abs)
	if DirAccess.dir_exists_absolute(dir_abs):
		ResourceSaver.save(_gray_tile_tex, GRAY_TILE_TEX_PATH, ResourceSaver.FLAG_COMPRESS)
	return _gray_tile_tex


func _get_roof_mesh(rel_path: String, palette_name: String) -> Mesh:
	if not ROOF_PALETTES.has(palette_name):
		return _get_mesh(rel_path)
	var cache_key: String = rel_path + "::" + palette_name
	if _roof_mesh_cache.has(cache_key):
		return _roof_mesh_cache[cache_key] as Mesh
	var base_mesh := _get_mesh(rel_path)
	if base_mesh == null:
		return null
	var tint: Color = ROOF_PALETTES[palette_name]
	var dup := base_mesh.duplicate() as Mesh
	for si in range(dup.get_surface_count()):
		var mat := dup.surface_get_material(si) as StandardMaterial3D
		if mat != null and (mat.resource_name.contains("RoundTiles") or (mat.albedo_texture != null and mat.albedo_texture.resource_path.contains("RoundTiles"))):
			var tmat := mat.duplicate() as StandardMaterial3D
			var gtex := _get_gray_tile_texture(mat.albedo_texture)
			if gtex != null:
				tmat.albedo_texture = gtex
			tmat.albedo_color = tint
			var rsig := palette_name + "|" + _material_signature(tmat)
			if _roof_mat_cache.has(rsig):
				tmat = _roof_mat_cache[rsig] as StandardMaterial3D
			else:
				_roof_mat_cache[rsig] = tmat
			dup.surface_set_material(si, tmat)
	_roof_mesh_cache[cache_key] = dup
	return dup


func _spawn_tinted_part(parent: Node3D, rel_path: String, palette_name: String, pos: Vector3, rot_y: float = 0.0, scale_vec: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := _get_roof_mesh(rel_path, palette_name)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = Vector3(0.0, rot_y, 0.0)
	mi.scale = scale_vec * V_SCALE
	parent.add_child(mi)
	return mi


func _spawn_part(parent: Node3D, rel_path: String, pos: Vector3, rot_y: float = 0.0, rot_euler: Vector3 = Vector3.INF, scale_vec: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := _get_mesh(rel_path)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if rot_euler != Vector3.INF:
		mi.rotation = rot_euler
	else:
		mi.rotation = Vector3(0.0, rot_y, 0.0)
	mi.scale = scale_vec * V_SCALE
	parent.add_child(mi)
	return mi


func _add_box_visual(parent: Node3D, box_name: String, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _add_cylinder_visual(parent: Node3D, cyl_name: String, pos: Vector3, top_r: float, bottom_r: float, height: float, mat: Material, rot: Vector3 = Vector3.ZERO, radial_segs: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = cyl_name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = radial_segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _add_rope_ring_visual(parent: Node3D, ring_name: String, pos: Vector3, inner_r: float, outer_r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = ring_name
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = outer_r
	tm.rings = 10
	tm.ring_segments = 6
	mi.mesh = tm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _spawn_rope_span(parent: Node3D, span_name: String, p_a: Vector3, p_b: Vector3, radius: float, mat: Material) -> void:
	var delta := p_b - p_a
	var dist := delta.length()
	if dist < 0.05:
		return
	var mid := (p_a + p_b) * 0.5
	var dir := delta / dist
	var yaw := atan2(dir.x, dir.z)
	var horiz := Vector2(dir.x, dir.z).length()
	var pitch := -atan2(dir.y, maxf(horiz, 0.0001)) + PI * 0.5
	_add_cylinder_visual(parent, span_name, mid, radius, radius, dist, mat, Vector3(pitch, yaw, 0.0), 6)


func _spawn_mooring_dolphin(dock: Node3D, colliders: StaticBody3D, d_basis: Basis, local_xz: Vector2, bottom_y: float, top_y: float) -> void:
	var height := top_y - bottom_y
	var cy := (top_y + bottom_y) * 0.5
	var offsets: Array[Vector2] = [Vector2(0.0, 0.20), Vector2(-0.18, -0.12), Vector2(0.18, -0.12)]
	var tilts: Array[Vector3] = [Vector3(0.04, 0.0, 0.0), Vector3(-0.03, 0.0, 0.04), Vector3(-0.03, 0.0, -0.04)]
	for i in range(3):
		var ox := local_xz.x + offsets[i].x
		var oz := local_xz.y + offsets[i].y
		var post_h := height + (0.28 if i == 0 else -0.12 * float(i))
		var post_cy := bottom_y + post_h * 0.5
		_add_cylinder_visual(dock, "DolphinPost_%d" % i, Vector3(ox, post_cy, oz), 0.12, 0.16, post_h, _mat_dock_oak, tilts[i])
	_add_rope_ring_visual(dock, "DolphinRopeHi", Vector3(local_xz.x, top_y - 0.52, local_xz.y), 0.25, 0.37, _mat_rope)
	_add_rope_ring_visual(dock, "DolphinRopeLo", Vector3(local_xz.x, top_y - 0.72, local_xz.y), 0.26, 0.38, _mat_rope)
	var dw := dock.position + d_basis * Vector3(local_xz.x, cy, local_xz.y)
	_add_cylinder_collider(colliders, dw, 0.42, height)


func _add_box_collider(colliders: StaticBody3D, xform: Transform3D, size: Vector3) -> void:
	if size.x <= 0.02 or size.y <= 0.02 or size.z <= 0.02:
		return
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xform
	if not _occluder_target_name.is_empty():
		cs.set_meta(&"occluder_node", _occluder_target_name)
	colliders.add_child(cs)


func _add_cylinder_collider(colliders: StaticBody3D, pos: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = pos
	if not _occluder_target_name.is_empty():
		cs.set_meta(&"occluder_node", _occluder_target_name)
	colliders.add_child(cs)


## Builds continuous terrain-draped textured cobblestone Town Square and 4 streets
## with ground-sunk stone perimeter skirts (zero stair-steps, zero floating edges, zero grass bleed).
func _build_plaza_and_roads(root: Node3D, colliders: StaticBody3D, terrain: Node3D) -> float:
	var roads_node := Node3D.new()
	roads_node.name = "CobblestoneNetwork"
	root.add_child(roads_node)

	# 1. Flush draped cobblestone Grand Market Square, civic forecourts & 4 cardinal gate avenues
	_add_draped_surface(roads_node, colliders, terrain, "PlazaOuterRing", -13.2 * V_SCALE, 13.2 * V_SCALE, -13.2 * V_SCALE, 13.2 * V_SCALE, 1.0, 0.040, _mat_plaza_brick)
	_add_draped_surface(roads_node, colliders, terrain, "PlazaInnerCobble", -10.2 * V_SCALE, 10.2 * V_SCALE, -10.2 * V_SCALE, 10.2 * V_SCALE, 1.0, 0.055, _mat_cobble)
	_add_draped_surface(roads_node, colliders, terrain, "PlazaCenterApron", -3.4 * V_SCALE, 3.4 * V_SCALE, -3.4 * V_SCALE, 3.4 * V_SCALE, 1.0, 0.070, _mat_plaza_brick)

	# Secondary civic forecourts in front of Guildhall & VillageAbbey
	_add_draped_surface(roads_node, colliders, terrain, "GuildhallForecourt", -12.5 * V_SCALE, -4.5 * V_SCALE, -16.0 * V_SCALE, -12.8 * V_SCALE, 1.0, 0.038, _mat_cobble)
	_add_draped_surface(roads_node, colliders, terrain, "AbbeyForecourt",       4.5 * V_SCALE, 12.5 * V_SCALE, -16.0 * V_SCALE, -12.8 * V_SCALE, 1.0, 0.038, _mat_cobble)

	# 2. North & South High Streets (through Twin-Tower Gatehouses out to outer approaches)
	_add_draped_surface(roads_node, colliders, terrain, "NorthHighStreet", -2.5 * V_SCALE, 2.5 * V_SCALE, -56.5 * V_SCALE, -12.8 * V_SCALE, 1.0, 0.048, _mat_cobble)
	_add_draped_surface(roads_node, colliders, terrain, "SouthHighStreet", -2.5 * V_SCALE, 2.5 * V_SCALE,  12.8 * V_SCALE,  56.5 * V_SCALE, 1.0, 0.048, _mat_cobble)

	# 3. West Artisan Ave & East Market Street (through West & East Gatehouses)
	_add_draped_surface(roads_node, colliders, terrain, "WestArtisanAve",   -62.5 * V_SCALE, -12.8 * V_SCALE, -2.5 * V_SCALE, 2.5 * V_SCALE, 1.0, 0.048, _mat_cobble)
	_add_draped_surface(roads_node, colliders, terrain, "EastMarketStreet",  12.8 * V_SCALE,  62.5 * V_SCALE, -2.5 * V_SCALE, 2.5 * V_SCALE, 1.0, 0.048, _mat_cobble)

	# 4. Concentric Cobblestone Ring Road looping around the Market Quarter
	_add_draped_surface(roads_node, colliders, terrain, "NorthRingLane", -37.8 * V_SCALE,  37.8 * V_SCALE, -33.8 * V_SCALE, -30.2 * V_SCALE, 1.0, 0.044, _mat_cobble)
	_add_draped_surface(roads_node, colliders, terrain, "SouthRingLane", -37.8 * V_SCALE,  37.8 * V_SCALE,  30.2 * V_SCALE,  33.8 * V_SCALE, 1.0, 0.044, _mat_cobble)
	_add_draped_surface(roads_node, colliders, terrain, "WestRingLane",  -37.8 * V_SCALE, -34.2 * V_SCALE, -30.2 * V_SCALE,  30.2 * V_SCALE, 1.0, 0.044, _mat_cobble)
	_add_draped_surface(roads_node, colliders, terrain, "EastRingLane",   34.2 * V_SCALE,  37.8 * V_SCALE, -30.2 * V_SCALE,  30.2 * V_SCALE, 1.0, 0.044, _mat_cobble)

	# 5. Carved rock-trim curbstones flanking the West, East, and South Plaza borders (leaving avenues & N forecourts open)
	for side_x in [-11.0, -9.0, -7.0, -5.0, 5.0, 7.0, 9.0, 11.0]:
		var nx_n := VILLAGE_CENTER.x + float(side_x) * V_SCALE
		_spawn_part(roads_node, "Prop_ExteriorBorder_Straight1.gltf", Vector3(nx_n, _sample_h(terrain, nx_n, VILLAGE_CENTER.z + 13.2 * V_SCALE) - 0.02, VILLAGE_CENTER.z + 13.2 * V_SCALE), 0.0)
	for side_z in [-11.0, -9.0, -7.0, -5.0, 5.0, 7.0, 9.0, 11.0]:
		var nz_n := VILLAGE_CENTER.z + float(side_z) * V_SCALE
		_spawn_part(roads_node, "Prop_ExteriorBorder_Straight1.gltf", Vector3(VILLAGE_CENTER.x - 13.2 * V_SCALE, _sample_h(terrain, VILLAGE_CENTER.x - 13.2 * V_SCALE, nz_n) - 0.02, nz_n), -PI * 0.5)
		_spawn_part(roads_node, "Prop_ExteriorBorder_Straight1.gltf", Vector3(VILLAGE_CENTER.x + 13.2 * V_SCALE, _sample_h(terrain, VILLAGE_CENTER.x + 13.2 * V_SCALE, nz_n) - 0.02, nz_n), PI * 0.5)

	return _sample_h(terrain, VILLAGE_CENTER.x, VILLAGE_CENTER.z) + 0.070


func _add_draped_surface(
	parent: Node3D, colliders: StaticBody3D, terrain: Node3D,
	surf_name: String, off_x0: float, off_x1: float, off_z0: float, off_z1: float,
	step: float, lift_y: float, mat: Material
) -> void:
	var nx: int = maxi(1, int(round((off_x1 - off_x0) / step)))
	var nz: int = maxi(1, int(round((off_z1 - off_z0) / step)))
	var dx: float = (off_x1 - off_x0) / float(nx)
	var dz: float = (off_z1 - off_z0) / float(nz)

	var grid: Array[Vector3] = []
	grid.resize((nx + 1) * (nz + 1))
	for ix in range(nx + 1):
		var wx: float = VILLAGE_CENTER.x + off_x0 + float(ix) * dx
		for iz in range(nz + 1):
			var wz: float = VILLAGE_CENTER.z + off_z0 + float(iz) * dz
			var h: float = _sample_h(terrain, wx, wz)
			h = maxf(h, _sample_h(terrain, wx - dx * 0.5, wz))
			h = maxf(h, _sample_h(terrain, wx + dx * 0.5, wz))
			h = maxf(h, _sample_h(terrain, wx, wz - dz * 0.5))
			h = maxf(h, _sample_h(terrain, wx, wz + dz * 0.5))
			grid[ix * (nz + 1) + iz] = Vector3(wx, h + lift_y, wz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_faces := PackedVector3Array()

	var uv_scale := 0.5
	# Emit indexed top cobblestone vertices so top normals stay smoothly upward without skirt tilt
	for idx in range(grid.size()):
		var p: Vector3 = grid[idx]
		st.set_uv(Vector2(p.x * uv_scale, p.z * uv_scale))
		st.add_vertex(p)

	var stride := nz + 1
	for ix in range(nx):
		for iz in range(nz):
			var i00 := ix * stride + iz
			var i10 := (ix + 1) * stride + iz
			var i01 := ix * stride + (iz + 1)
			var i11 := (ix + 1) * stride + (iz + 1)
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i00)
			st.add_index(i11)
			st.add_index(i01)
			var p00 := grid[i00]
			var p10 := grid[i10]
			var p01 := grid[i01]
			var p11 := grid[i11]
			col_faces.append(p00)
			col_faces.append(p10)
			col_faces.append(p11)
			col_faces.append(p00)
			col_faces.append(p11)
			col_faces.append(p01)

	# Outward-winding stone curb skirts with dedicated vertices (isolates vertical normals from top face)
	var skirt_drop := 0.85
	var next_v := grid.size()
	var add_skirt_quad := func(a: Vector3, b: Vector3, abot: Vector3, bbot: Vector3) -> void:
		st.set_uv(Vector2(a.x * uv_scale, a.z * uv_scale))
		st.add_vertex(a)
		st.set_uv(Vector2(b.x * uv_scale, b.z * uv_scale))
		st.add_vertex(b)
		st.set_uv(Vector2(bbot.x * uv_scale, bbot.z * uv_scale))
		st.add_vertex(bbot)
		st.set_uv(Vector2(abot.x * uv_scale, abot.z * uv_scale))
		st.add_vertex(abot)
		st.add_index(next_v)
		st.add_index(next_v + 3)
		st.add_index(next_v + 2)
		st.add_index(next_v)
		st.add_index(next_v + 2)
		st.add_index(next_v + 1)
		next_v += 4

	var drop_v := Vector3(0.0, skirt_drop, 0.0)
	for ix in range(nx):
		var a0: Vector3 = grid[ix * stride]
		var b0: Vector3 = grid[(ix + 1) * stride]
		add_skirt_quad.call(a0, b0, a0 - drop_v, b0 - drop_v)

		var a1: Vector3 = grid[ix * stride + nz]
		var b1: Vector3 = grid[(ix + 1) * stride + nz]
		add_skirt_quad.call(b1, a1, b1 - drop_v, a1 - drop_v)

	for iz in range(nz):
		var c0: Vector3 = grid[iz]
		var d0: Vector3 = grid[iz + 1]
		add_skirt_quad.call(d0, c0, d0 - drop_v, c0 - drop_v)

		var c1: Vector3 = grid[nx * stride + iz]
		var d1: Vector3 = grid[nx * stride + (iz + 1)]
		add_skirt_quad.call(c1, d1, c1 - drop_v, d1 - drop_v)

	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = surf_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

	if not col_faces.is_empty():
		var col_shape := ConcavePolygonShape3D.new()
		col_shape.set_faces(col_faces)
		var cs := CollisionShape3D.new()
		cs.shape = col_shape
		colliders.add_child(cs)


func _build_gatehouse_bridge(root: Node3D, colliders: StaticBody3D, bridge_name: String, center_off: Vector2, rot_y: float, bridge_base_y: float) -> void:
	var bridge := Node3D.new()
	bridge.name = bridge_name
	bridge.position = Vector3(VILLAGE_CENTER.x + center_off.x, bridge_base_y, VILLAGE_CENTER.z + center_off.y)
	bridge.rotation = Vector3(0.0, rot_y, 0.0)
	root.add_child(bridge)

	var b_basis := Basis(Vector3.UP, rot_y)
	var bridge_stone_mat := _mat_cobble
	# Textured stone bridge gallery spanning the scaled avenue between twin gatehouse towers
	var gallery_size := Vector3(5.3, 2.35, 3.6) * V_SCALE
	var gallery_pos := Vector3(0.0, 3.25 * V_SCALE + gallery_size.y * 0.5, 0.0)
	_add_box_visual(bridge, "BridgeGallery", gallery_pos, gallery_size, bridge_stone_mat)
	_add_box_collider(colliders, Transform3D(b_basis, bridge.position + b_basis * gallery_pos), gallery_size)

	# Upper plaster frieze band to match medieval brickwork & half-timber palette
	var plaster_mat := _make_matte_mat(Color(0.76, 0.72, 0.64), 0.90)
	for sz in [-1.82 * V_SCALE, 1.82 * V_SCALE]:
		_add_box_visual(bridge, "BridgeFrieze", Vector3(0.0, 4.95 * V_SCALE, float(sz)), Vector3(5.2, 0.85, 0.08) * V_SCALE, plaster_mat)
		_add_box_visual(bridge, "BridgeTrim", Vector3(0.0, 3.32 * V_SCALE, float(sz)), Vector3(5.35, 0.24, 0.22) * V_SCALE, _mat_wood_trim)
		_add_box_visual(bridge, "BridgeCornice", Vector3(0.0, 5.52 * V_SCALE, float(sz)), Vector3(5.40, 0.22, 0.28) * V_SCALE, _mat_wood_trim)

	for sx in [-2.15 * V_SCALE, 2.15 * V_SCALE]:
		_add_box_visual(bridge, "ArchCorbel", Vector3(float(sx), 3.05 * V_SCALE, 0.0), Vector3(0.85, 0.55, 3.5) * V_SCALE, _mat_stone_foundation)

	for mx in [-1.8, -0.6, 0.6, 1.8]:
		for sz in [-1.62, 1.62]:
			_add_box_visual(bridge, "Merlon", Vector3(float(mx) * V_SCALE, 5.82 * V_SCALE, float(sz) * V_SCALE), Vector3(0.65, 0.55, 0.36) * V_SCALE, _mat_stone_foundation)

	# Arched timber portals spanning the central street gap inside the two GateTowers
	for arch_pair in [[1.62 * V_SCALE, 0.0], [-1.62 * V_SCALE, PI]]:
		_spawn_part(bridge, "Wall_Arch.gltf", Vector3(0.0, 0.02, float(arch_pair[0])), float(arch_pair[1]), Vector3.INF, Vector3(2.45, 1.12, 2.2))

	for sx in [-2.05 * V_SCALE, 2.05 * V_SCALE]:
		_spawn_wall_sconce(bridge, Vector3(float(sx), 2.65 * V_SCALE,  1.88 * V_SCALE), 0.0, false)
		_spawn_wall_sconce(bridge, Vector3(float(sx), 2.65 * V_SCALE, -1.88 * V_SCALE), PI,  false)

	var gate_light := OmniLight3D.new()
	gate_light.position = Vector3(0.0, 3.1 * V_SCALE, 0.0)
	gate_light.light_color = Color(1.0, 0.76, 0.40)
	gate_light.light_energy = 1.45
	gate_light.omni_range = 14.0 * V_SCALE
	gate_light.shadow_enabled = false
	gate_light.distance_fade_enabled = true
	gate_light.distance_fade_begin = 110.0
	gate_light.distance_fade_length = 35.0
	bridge.add_child(gate_light)
	_register_night_light(gate_light, 1.45)

	_spawn_tinted_part(bridge, "Roof_RoundTiles_4x6.gltf", "slate", Vector3(0.0, 5.55 * V_SCALE, 0.0), PI * 0.5)


func _build_house(root: Node3D, colliders: StaticBody3D, terrain: Node3D, spec: Dictionary) -> float:
	var hname: String = spec["name"]
	var raw_off: Vector2 = spec["offset"]
	var off: Vector2 = raw_off if bool(spec.get("unscaled_offset", false)) else raw_off * V_SCALE
	var w: int = spec["w"]
	var d: int = spec["d"]
	var ws: float = float(w) * V_SCALE
	var ds: float = float(d) * V_SCALE
	var stories: int = spec["stories"]
	var style: String = spec["style"]
	var roof_palette: String = String(spec.get("roof", "terracotta"))
	var yaw: float = spec["yaw"]
	var is_tower: bool = spec["is_tower"]
	var open_door: bool = spec["open_door"]
	var civic: bool = spec["civic"]

	var house := Node3D.new()
	house.name = hname
	_occluder_target_name = hname
	var wx: float = VILLAGE_CENTER.x + off.x
	var wz: float = VILLAGE_CENTER.z + off.y

	var mm := _sample_patch_minmax(terrain, wx, wz, ws * 0.5 + 0.5 * V_SCALE, ds * 0.5 + 1.0 * V_SCALE, yaw)
	var min_h: float = mm.x
	var max_h: float = mm.y
	var floor_y: float = max_h + 0.14
	var found_bot: float = min_h - 1.5
	var found_h: float = floor_y - found_bot

	house.position = Vector3(wx, 0.0, wz)
	house.rotation = Vector3(0.0, yaw, 0.0)
	root.add_child(house)

	var house_basis := Basis(Vector3.UP, yaw)
	var house_origin := Vector3(wx, 0.0, wz)

	# 1. Ground-sunk stone foundation plinth + Layer 4 base collider
	var found_pos := Vector3(0.0, found_bot + found_h * 0.5, 0.0)
	var found_size := Vector3(ws + 0.22 * V_SCALE, found_h, ds + 0.22 * V_SCALE)
	_add_box_visual(house, "Foundation", found_pos, found_size, _mat_stone_foundation)
	_add_box_collider(
		colliders,
		Transform3D(house_basis, house_origin + house_basis * found_pos),
		Vector3(ws + 0.16 * V_SCALE, maxf(found_h - 0.04, 0.2), ds + 0.16 * V_SCALE)
	)

	var nx: int = w / 2
	var nz: int = d / 2
	var hw: float = ws * 0.5
	var hd: float = ds * 0.5
	var door_idx: int = nx / 2

	if not is_tower:
		var door_local_x_p: float = -hw + CELL * 0.5 + float(door_idx) * CELL
		var apron_front: Vector3 = house_origin + house_basis * Vector3(door_local_x_p, 0.0, hd + 1.1 * V_SCALE)
		var apron_far: Vector3 = house_origin + house_basis * Vector3(door_local_x_p, 0.0, hd + 1.9 * V_SCALE)
		var apron_min_h: float = minf(_sample_h(terrain, apron_front.x, apron_front.z), _sample_h(terrain, apron_far.x, apron_far.z))
		var step_bot: float = minf(apron_min_h - 1.0, found_bot)

		var sub_top: float = floor_y - 0.78 * V_SCALE
		var sub_h: float = maxf(sub_top - step_bot, 0.35)
		var sub_pos := Vector3(door_local_x_p, step_bot + sub_h * 0.5, hd + 0.95 * V_SCALE)
		var sub_size := Vector3(1.82 * V_SCALE, sub_h, 1.80 * V_SCALE)
		_add_box_visual(house, "PorchSubBase", sub_pos, sub_size, _mat_stone_foundation)
		_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * Vector3(door_local_x_p, (floor_y - 0.16 + step_bot) * 0.5, hd + 0.65 * V_SCALE)), Vector3(1.90 * V_SCALE, maxf(floor_y - 0.16 - step_bot, 0.4), 1.35 * V_SCALE))

		_spawn_part(house, "Stairs_Exterior_Straight.gltf", Vector3(door_local_x_p, floor_y - 0.82 * V_SCALE, hd + 0.96 * V_SCALE), 0.0, Vector3.INF, Vector3(1.02, 0.98, 0.94))

	var door_local_x: float = -hw + CELL * 0.5 + float(door_idx) * CELL
	var use_wood_grid: bool = (hname == "GranaryBarn")

	# 3. Stories: mixed brick ground + plaster upper floors, foundation trim, balconies, corbels, doors
	var floor0_rel: String = "Floor_RedBrick.gltf" if civic else "Floor_UnevenBrick.gltf"
	for s in range(stories):
		var sy: float = floor_y + float(s) * STORY_H
		var story_style: String = "brick" if (style == "brick" or (stories >= 2 and s == 0)) else "plaster"
		var wall_prefix: String = "Wall_UnevenBrick_" if story_style == "brick" else "Wall_Plaster_"

		var tile_rel: String = floor0_rel if s == 0 else "Floor_WoodLight.gltf"
		var tile_y: float = sy + 0.01 if s == 0 else sy
		for ix in range(nx):
			var fx: float = -hw + CELL * 0.5 + float(ix) * CELL
			for iz in range(nz):
				var fz: float = -hd + CELL * 0.5 + float(iz) * CELL
				_spawn_part(house, tile_rel, Vector3(fx, tile_y, fz))

		# Front (+Z) wall
		for ix in range(nx):
			var bx: float = -hw + CELL * 0.5 + float(ix) * CELL
			var fpos := Vector3(bx, sy, hd)
			if s == 0 and ix == door_idx:
				_spawn_part(house, wall_prefix + "Door_Round.gltf", fpos, 0.0)
				var frame_rel: String = "DoorFrame_Round_Brick.gltf" if story_style == "brick" else "DoorFrame_Round_WoodDark.gltf"
				_spawn_part(house, frame_rel, fpos, 0.0)
				var door_pivot := Node3D.new()
				door_pivot.name = "DoorPivot"
				door_pivot.position = fpos + Vector3(-0.514 * V_SCALE, 0.0, 0.0)
				door_pivot.rotation = Vector3(0.0, 1.65 if open_door else 0.0, 0.0)
				house.add_child(door_pivot)
				var door_rel: String = "Door_2_Round.gltf" if civic else ("Door_4_Round.gltf" if story_style == "brick" else "Door_1_Round.gltf")
				_spawn_part(door_pivot, door_rel, Vector3.ZERO, 0.0)
			else:
				if s == 0:
					_spawn_part(house, "Wall_BottomCover.gltf", fpos, 0.0)
				var want_win: bool = (not is_tower and ((ix + s) % 2 == 0 or (nx == 3 and ix == 1))) or (is_tower and s >= 1 and ix == 0)
				if want_win:
					var allow_shutters: bool = (nx >= 3) and ((absf(bx) + 1.25 * V_SCALE) <= hw - 0.15 * V_SCALE)
					_spawn_window_bay(house, wall_prefix, fpos, 0.0, allow_shutters, false, is_tower, s < 2)
				else:
					var solid_rel: String = "Wall_Plaster_WoodGrid.gltf" if (story_style == "plaster" and use_wood_grid) else wall_prefix + "Straight.gltf"
					_spawn_part(house, solid_rel, fpos, 0.0)
					if is_tower and s == 0 and ix == 1:
						_spawn_part(house, "Prop_Vine2.gltf", Vector3(bx, sy + 2.45 * V_SCALE, hd + 0.06 * V_SCALE), 0.0)
			if s == 1 and not is_tower and (w < 6 or ix != door_idx):
				_spawn_part(house, "Prop_ExteriorBorder_Straight1.gltf", fpos, 0.0)

		# Back (-Z) wall
		for ix in range(nx):
			var bx: float = -hw + CELL * 0.5 + float(ix) * CELL
			var bpos := Vector3(bx, sy, -hd)
			if s == 0:
				_spawn_part(house, "Wall_BottomCover.gltf", bpos, PI)
			var want_back_win: bool = (not is_tower and nx >= 3 and (ix == 1 or (nx == 5 and ix == 3))) or (is_tower and s >= 1 and ix == 1)
			if want_back_win:
				var allow_shutters: bool = (nx >= 3) and ((absf(bx) + 1.25 * V_SCALE) <= hw - 0.15 * V_SCALE)
				var closed_sh: bool = (not civic and (ix + s) % 2 == 1)
				_spawn_window_bay(house, wall_prefix, bpos, PI, allow_shutters, closed_sh, is_tower, s < 2)
			else:
				var solid_back: String = "Wall_Plaster_WoodGrid.gltf" if (story_style == "plaster" and use_wood_grid) else wall_prefix + "Straight.gltf"
				_spawn_part(house, solid_back, bpos, PI)
				if story_style == "brick" and s == 0 and ix == 0:
					_spawn_part(house, "Prop_Vine1.gltf", Vector3(bx, sy + 2.42 * V_SCALE, -hd - 0.06 * V_SCALE), PI)
			if s == 1 and not is_tower:
				_spawn_part(house, "Prop_ExteriorBorder_Straight1.gltf", bpos, PI)

		# Right (+X) and Left (-X) walls
		for iz in range(nz):
			var bz: float = -hd + CELL * 0.5 + float(iz) * CELL
			var allow_side_win: bool = (not is_tower and nz >= 3 and ((nz == 3 and iz == 1) or (nz == 4 and iz == 1) or (nz == 5 and (iz == 1 or iz == 3)))) or (is_tower and s >= 1 and iz == 0)
			var allow_side_shutters: bool = (nz >= 3) and ((absf(bz) + 1.25 * V_SCALE) <= hd - 0.15 * V_SCALE)
			var solid_side: String = "Wall_Plaster_WoodGrid.gltf" if (story_style == "plaster" and use_wood_grid) else wall_prefix + "Straight.gltf"

			var rpos := Vector3(hw, sy, bz)
			if allow_side_win:
				_spawn_window_bay(house, wall_prefix, rpos, PI * 0.5, allow_side_shutters, not civic and iz % 2 == 0, is_tower, s < 2)
			else:
				_spawn_part(house, solid_side, rpos, PI * 0.5)
				if s == 0 and story_style == "brick" and iz == nz - 1 and (civic or is_tower):
					_spawn_part(house, "Prop_Vine4.gltf", Vector3(hw + 0.06 * V_SCALE, sy + 2.35 * V_SCALE, bz), PI * 0.5)

			var lpos := Vector3(-hw, sy, bz)
			if allow_side_win:
				_spawn_window_bay(house, wall_prefix, lpos, -PI * 0.5, allow_side_shutters, false, is_tower, s < 2)
			else:
				_spawn_part(house, solid_side, lpos, -PI * 0.5)

			if s == 1 and not is_tower:
				_spawn_part(house, "Prop_ExteriorBorder_Straight1.gltf", rpos,  PI * 0.5)
				_spawn_part(house, "Prop_ExteriorBorder_Straight1.gltf", lpos, -PI * 0.5)

		# 4 Exterior corners matched per story material
		if story_style == "brick":
			_spawn_part(house, "Corner_Exterior_Brick.gltf", Vector3(-hw, sy, -hd), PI * 0.5)
			_spawn_part(house, "Corner_Exterior_Brick.gltf", Vector3( hw, sy, -hd), 0.0)
			_spawn_part(house, "Corner_Exterior_Brick.gltf", Vector3( hw, sy,  hd), -PI * 0.5)
			_spawn_part(house, "Corner_Exterior_Brick.gltf", Vector3(-hw, sy,  hd), PI)
		else:
			_spawn_part(house, "Corner_Exterior_Wood.gltf", Vector3(-hw, sy, -hd), 0.0)
			_spawn_part(house, "Corner_Exterior_Wood.gltf", Vector3( hw, sy, -hd), 0.0)
			_spawn_part(house, "Corner_Exterior_Wood.gltf", Vector3( hw, sy,  hd), 0.0)
			_spawn_part(house, "Corner_Exterior_Wood.gltf", Vector3(-hw, sy,  hd), 0.0)

		if s == stories - 1 and not is_tower:
			for cx in [-hw + 0.28 * V_SCALE, hw - 0.28 * V_SCALE]:
				_spawn_part(house, "Prop_Support.gltf", Vector3(float(cx), sy,  hd), 0.0, Vector3.INF, Vector3(0.85, 1.0, 0.52))
				_spawn_part(house, "Prop_Support.gltf", Vector3(float(cx), sy, -hd), PI,  Vector3.INF, Vector3(0.85, 1.0, 0.52))

	if not is_tower:
		_spawn_wall_sconce(house, Vector3(door_local_x - 0.78 * V_SCALE, floor_y + 2.08 * V_SCALE, hd + 0.14 * V_SCALE), 0.0, false)
		_spawn_wall_sconce(house, Vector3(door_local_x + 0.78 * V_SCALE, floor_y + 2.08 * V_SCALE, hd + 0.14 * V_SCALE), 0.0, false)

	# Second-story front balcony with matching kit end-rails and doorway-flanking corbels
	if stories >= 2 and not is_tower and w >= 6:
		var bal_y: float = floor_y + STORY_H
		var bal_rel: String = "Balcony_Cross_Straight.gltf" if civic else "Balcony_Simple_Straight.gltf"
		_spawn_part(house, bal_rel, Vector3(door_local_x, bal_y, hd), 0.0)
		_spawn_part(house, bal_rel, Vector3(door_local_x, bal_y, hd + 0.50 * V_SCALE),  PI * 0.5, Vector3.INF, Vector3(0.50, 1.0, 1.0))
		_spawn_part(house, bal_rel, Vector3(door_local_x, bal_y, hd + 0.50 * V_SCALE), -PI * 0.5, Vector3.INF, Vector3(0.50, 1.0, 1.0))
		_spawn_part(house, "Floor_WoodLight.gltf", Vector3(door_local_x, bal_y, hd + 0.50 * V_SCALE), 0.0, Vector3.INF, Vector3(1.0, 1.0, 0.56))
		_add_box_collider(
			colliders,
			Transform3D(house_basis, house_origin + house_basis * Vector3(door_local_x, bal_y - 0.04 * V_SCALE, hd + 0.50 * V_SCALE)),
			Vector3(2.05, 0.18, 1.06) * V_SCALE
		)
		for bx_side in [-0.88 * V_SCALE, 0.88 * V_SCALE]:
			_spawn_part(house, "Prop_Support.gltf", Vector3(door_local_x + float(bx_side), floor_y, hd), 0.0, Vector3.INF, Vector3(1.0, 1.0, 0.52))

	# Top ceiling tiles under attic
	var top_y: float = floor_y + float(stories) * STORY_H
	for ix in range(nx):
		var fx: float = -hw + CELL * 0.5 + float(ix) * CELL
		for iz in range(nz):
			var fz: float = -hd + CELL * 0.5 + float(iz) * CELL
			_spawn_part(house, "Floor_WoodLight.gltf", Vector3(fx, top_y, fz))

	# 4. Roof, front/back brick gables, dormers, and chimneys (using palette-tinted tiles)
	if is_tower:
		_spawn_tinted_part(house, "Roof_Tower_RoundTiles.gltf", roof_palette, Vector3(0.0, top_y, 0.0), 0.0)
	else:
		var roof_file: String = "Roof_RoundTiles_%dx%d.gltf" % [w, d]
		_spawn_tinted_part(house, roof_file, roof_palette, Vector3(0.0, top_y, 0.0), 0.0)
		var front_gable: String = "Roof_Front_Brick%d.gltf" % w
		_spawn_part(house, front_gable, Vector3(0.0, top_y,  hd), 0.0)
		_spawn_part(house, front_gable, Vector3(0.0, top_y, -hd), PI)

		if w >= 6 and d >= 6 and stories >= 2:
			var dormer_x: float = (1.15 if w >= 8 else 0.55) * V_SCALE
			var dormer_y: float = top_y + (1.72 if w >= 8 else 1.12) * V_SCALE
			_spawn_tinted_part(house, "Roof_Dormer_RoundTile.gltf", roof_palette, Vector3(dormer_x, dormer_y, (-1.0 if d >= 8 else 0.0) * V_SCALE), 0.0)
			if d >= 8:
				_spawn_tinted_part(house, "Roof_Dormer_RoundTile.gltf", roof_palette, Vector3(-dormer_x, dormer_y, 1.0 * V_SCALE), PI)
		elif w >= 6:
			_spawn_part(house, "Window_Roof_Wide.gltf", Vector3(1.35 * V_SCALE, top_y + 0.45 * V_SCALE, 0.0), PI * 0.5)

		var chim_file: String = "Prop_Chimney2.gltf" if (w >= 8) else "Prop_Chimney.gltf"
		var chim_x: float = hw - (1.25 if w >= 8 else 0.75) * V_SCALE
		var chim_y: float = top_y + (2.05 if w >= 8 else (1.55 if w == 6 else 1.05)) * V_SCALE
		_spawn_part(house, chim_file, Vector3(chim_x, chim_y, -hd + 1.15 * V_SCALE), 0.0)
		var bname: String = String(spec.get("name", ""))
		if bname in ["GoldenSlimeInn", "Bakery", "Blacksmith", "BreweryHall", "PotteryCottage", "InnKitchenWing", "MarketHall"]:
			var smoke := GPUParticles3D.new()
			smoke.name = "ChimneySmoke"
			smoke.position = Vector3(chim_x, chim_y + 1.45 * V_SCALE, -hd + 1.15 * V_SCALE)
			smoke.amount = 7
			smoke.lifetime = 3.8
			smoke.preprocess = 2.5
			smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			smoke.visibility_range_end = 145.0
			smoke.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			smoke.process_material = _smoke_pmat
			smoke.draw_pass_1 = _smoke_mesh
			house.add_child(smoke)

	# 4b. Attached L-shaped side/rear annex wing for complex medieval compound silhouettes
	if spec.has("wing"):
		_build_attached_wing(house, colliders, terrain, house_origin, house_basis, floor_y, roof_palette, spec["wing"])

	# 5. Layer 4 Wall, Floor, Door & Roof Colliders (split around front doorway so open buildings are enterable)
	var wall_h: float = float(stories) * STORY_H
	var wall_cy: float = floor_y + wall_h * 0.5
	var wall_thick := 0.38 * V_SCALE

	var slab_pos := Vector3(0.0, floor_y - 0.08 * V_SCALE, 0.0)
	_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * slab_pos), Vector3(ws, 0.16 * V_SCALE, ds))

	var back_c := Vector3(0.0, wall_cy, -hd - 0.08 * V_SCALE)
	_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * back_c), Vector3(ws + 0.3 * V_SCALE, wall_h, wall_thick))

	var left_c := Vector3(-hw - 0.08 * V_SCALE, wall_cy, 0.0)
	_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * left_c), Vector3(wall_thick, wall_h, ds + 0.3 * V_SCALE))
	var right_c := Vector3(hw + 0.08 * V_SCALE, wall_cy, 0.0)
	_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * right_c), Vector3(wall_thick, wall_h, ds + 0.3 * V_SCALE))

	var door_left_edge: float = door_local_x - 0.70 * V_SCALE
	var door_right_edge: float = door_local_x + 0.70 * V_SCALE
	var front_left_w: float = door_left_edge - (-hw - 0.15 * V_SCALE)
	if front_left_w > 0.05:
		var fl_pos := Vector3(-hw - 0.15 * V_SCALE + front_left_w * 0.5, wall_cy, hd + 0.08 * V_SCALE)
		_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * fl_pos), Vector3(front_left_w, wall_h, wall_thick))
	var front_right_w: float = (hw + 0.15 * V_SCALE) - door_right_edge
	if front_right_w > 0.05:
		var fr_pos := Vector3(door_right_edge + front_right_w * 0.5, wall_cy, hd + 0.08 * V_SCALE)
		_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * fr_pos), Vector3(front_right_w, wall_h, wall_thick))
	var door_clear_h := 2.40 * V_SCALE
	if wall_h > door_clear_h + 0.1:
		var hdr_h: float = wall_h - door_clear_h
		var hdr_pos := Vector3(door_local_x, floor_y + door_clear_h + hdr_h * 0.5, hd + 0.08 * V_SCALE)
		_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * hdr_pos), Vector3(1.40 * V_SCALE, hdr_h, wall_thick))
	if not open_door:
		var closed_pos := Vector3(door_local_x, floor_y + door_clear_h * 0.5, hd)
		_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * closed_pos), Vector3(1.36 * V_SCALE, door_clear_h, 0.24 * V_SCALE))

	var roof_cap_h := (2.6 if not is_tower else 3.8) * V_SCALE
	var roof_cap_pos := Vector3(0.0, top_y + roof_cap_h * 0.5 - 0.1 * V_SCALE, 0.0)
	_add_box_collider(colliders, Transform3D(house_basis, house_origin + house_basis * roof_cap_pos), Vector3(ws + 0.6 * V_SCALE, roof_cap_h, ds + 0.6 * V_SCALE))

	_occluder_target_name = ""
	return floor_y


func _build_attached_wing(
	house: Node3D, colliders: StaticBody3D, terrain: Node3D,
	house_origin: Vector3, house_basis: Basis, floor_y: float, roof_palette: String, wing: Dictionary
) -> void:
	var loff: Vector2 = wing["local_off"] * V_SCALE
	var w: int = int(wing.get("w", 4))
	var d: int = int(wing.get("d", 4))
	var ws: float = float(w) * V_SCALE
	var ds: float = float(d) * V_SCALE
	var w_style: String = String(wing.get("style", "brick"))
	var stories: int = int(wing.get("stories", 1))
	var hw: float = ws * 0.5
	var hd: float = ds * 0.5

	var w_root := Node3D.new()
	w_root.name = "AttachedWing"
	w_root.position = Vector3(loff.x, 0.0, loff.y)
	house.add_child(w_root)

	var wing_world := house_origin + house_basis * Vector3(loff.x, 0.0, loff.y)
	var wing_mm := _sample_patch_minmax(terrain, wing_world.x, wing_world.z, hw + 0.3 * V_SCALE, hd + 0.3 * V_SCALE, 0.0)
	var wing_bot: float = wing_mm.x - 1.5
	var wing_fh: float = floor_y - wing_bot
	var found_pos := Vector3(0.0, wing_bot + wing_fh * 0.5, 0.0)
	_add_box_visual(w_root, "WingFoundation", found_pos, Vector3(ws + 0.16 * V_SCALE, wing_fh, ds + 0.16 * V_SCALE), _mat_stone_foundation)
	_add_box_collider(
		colliders,
		Transform3D(house_basis, wing_world + house_basis * Vector3(0.0, floor_y + float(stories) * STORY_H * 0.5, 0.0)),
		Vector3(ws + 0.25 * V_SCALE, float(stories) * STORY_H + wing_fh, ds + 0.25 * V_SCALE)
	)

	var nx: int = w / 2
	var nz: int = d / 2
	for s in range(stories):
		var sy: float = floor_y + float(s) * STORY_H
		var st_style: String = "brick" if (w_style == "brick" or (stories >= 2 and s == 0)) else "plaster"
		var wprefix: String = "Wall_UnevenBrick_" if st_style == "brick" else "Wall_Plaster_"
		var solid_rel: String = wprefix + "Straight.gltf"

		for ix in range(nx):
			var bx: float = -hw + CELL * 0.5 + float(ix) * CELL
			var bpos := Vector3(bx, sy, -hd)
			if s == 0:
				_spawn_part(w_root, "Wall_BottomCover.gltf", bpos, PI)
			if ix == 0:
				_spawn_window_bay(w_root, wprefix, bpos, PI, false, false, true, s < 2)
			else:
				_spawn_part(w_root, solid_rel, bpos, PI)

		for iz in range(nz):
			var bz: float = -hd + CELL * 0.5 + float(iz) * CELL
			_spawn_part(w_root, solid_rel, Vector3( hw, sy, bz),  PI * 0.5)
			_spawn_part(w_root, solid_rel, Vector3(-hw, sy, bz), -PI * 0.5)

		if st_style == "brick":
			_spawn_part(w_root, "Corner_Exterior_Brick.gltf", Vector3(-hw, sy, -hd),  PI * 0.5)
			_spawn_part(w_root, "Corner_Exterior_Brick.gltf", Vector3( hw, sy, -hd),  0.0)
			_spawn_part(w_root, "Corner_Exterior_Brick.gltf", Vector3( hw, sy,  hd), -PI * 0.5)
			_spawn_part(w_root, "Corner_Exterior_Brick.gltf", Vector3(-hw, sy,  hd),  PI)
		else:
			_spawn_part(w_root, "Corner_Exterior_Wood.gltf", Vector3(-hw, sy, -hd), 0.0)
			_spawn_part(w_root, "Corner_Exterior_Wood.gltf", Vector3( hw, sy, -hd), 0.0)
			_spawn_part(w_root, "Corner_Exterior_Wood.gltf", Vector3( hw, sy,  hd), 0.0)
			_spawn_part(w_root, "Corner_Exterior_Wood.gltf", Vector3(-hw, sy,  hd), 0.0)

	var top_y: float = floor_y + float(stories) * STORY_H
	_spawn_tinted_part(w_root, "Roof_RoundTiles_4x4.gltf", roof_palette, Vector3(0.0, top_y, 0.0), PI * 0.5)
	_spawn_part(w_root, "Roof_Front_Brick4.gltf", Vector3(-hw, top_y, 0.0), -PI * 0.5)
	_spawn_part(w_root, "Roof_Front_Brick4.gltf", Vector3( hw, top_y, 0.0),  PI * 0.5)
	_spawn_part(w_root, "Prop_Chimney.gltf", Vector3(-hw + 0.85 * V_SCALE, top_y + 1.05 * V_SCALE, 0.0), 0.0)


func _spawn_wall_sconce(parent: Node3D, pos: Vector3, rot_y: float, add_light: bool = false) -> void:
	var sconce := Node3D.new()
	sconce.name = "WallSconce"
	sconce.position = pos
	sconce.rotation = Vector3(0.0, rot_y, 0.0)
	parent.add_child(sconce)

	_add_box_visual(sconce, "SconceBackplate", Vector3(0.0, 0.0, -0.04) * V_SCALE, Vector3(0.14, 0.32, 0.06) * V_SCALE, _mat_iron).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box_visual(sconce, "SconceArm", Vector3(0.0, 0.06, 0.12) * V_SCALE, Vector3(0.07, 0.07, 0.30) * V_SCALE, _mat_iron).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := _add_box_visual(sconce, "SconceGlow", Vector3(0.0, -0.10, 0.22) * V_SCALE, Vector3(0.18, 0.26, 0.18) * V_SCALE, _mat_lantern_glow)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box_visual(sconce, "SconceCap", Vector3(0.0, 0.06, 0.22) * V_SCALE, Vector3(0.24, 0.08, 0.24) * V_SCALE, _mat_iron).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if add_light:
		var light := OmniLight3D.new()
		light.position = Vector3(0.0, -0.12, 0.34) * V_SCALE
		light.light_color = Color(1.0, 0.78, 0.42)
		light.light_energy = 1.25
		light.omni_range = 10.5 * V_SCALE
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 95.0
		light.distance_fade_length = 30.0
		sconce.add_child(light)
		_register_night_light(light, 1.25)


func _spawn_window_bay(house: Node3D, wall_prefix: String, pos: Vector3, rot_y: float, add_shutters: bool, closed_shutters: bool = false, thin_bay: bool = false, add_glow: bool = true) -> void:
	if thin_bay:
		_spawn_part(house, wall_prefix + "Window_Thin_Round.gltf", pos, rot_y)
		_spawn_part(house, "Window_Thin_Round1.gltf", pos, rot_y)
		if add_shutters:
			_spawn_part(house, "WindowShutters_Thin_Round_Open.gltf", pos, rot_y)
	else:
		_spawn_part(house, wall_prefix + "Window_Wide_Round.gltf", pos, rot_y)
		_spawn_part(house, "Window_Wide_Round1.gltf", pos, rot_y)
		if add_shutters:
			var shut_rel: String = "WindowShutters_Wide_Round_Closed.gltf" if closed_shutters else "WindowShutters_Wide_Round_Open.gltf"
			_spawn_part(house, shut_rel, pos, rot_y)
	if add_glow:
		var glow_pos: Vector3 = pos + Basis(Vector3.UP, rot_y) * Vector3(0.0, 1.48 * V_SCALE, -0.12 * V_SCALE)
		var glow_size: Vector3 = Vector3((0.56 if thin_bay else 1.02) * V_SCALE, 1.08 * V_SCALE, 0.04 * V_SCALE)
		var gw := _add_box_visual(house, "WindowGlow", glow_pos, glow_size, _mat_window_glow, Vector3(0.0, rot_y, 0.0))
		gw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_well(root: Node3D, colliders: StaticBody3D, terrain: Node3D, plaza_top_y: float) -> void:
	var well := Node3D.new()
	well.name = "VillageWell"
	var wx: float = VILLAGE_CENTER.x
	var wz: float = VILLAGE_CENTER.z
	var ground_y: float = maxf(_sample_h(terrain, wx, wz), plaza_top_y)
	well.position = Vector3(wx, ground_y, wz)
	root.add_child(well)

	# Textured rock-masonry drum + carved coping borders
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 1.24 * V_SCALE
	rim_mesh.bottom_radius = 1.32 * V_SCALE
	rim_mesh.height = 1.00 * V_SCALE
	rim_mesh.radial_segments = 16
	rim.mesh = rim_mesh
	rim.material_override = _mat_stone_foundation
	rim.position = Vector3(0.0, 0.34 * V_SCALE, 0.0)
	well.add_child(rim)

	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 0.96 * V_SCALE
	water_mesh.bottom_radius = 0.96 * V_SCALE
	water_mesh.height = 0.12 * V_SCALE
	water_mesh.radial_segments = 16
	water.mesh = water_mesh
	water.material_override = _mat_well_water
	water.position = Vector3(0.0, 0.72 * V_SCALE, 0.0)
	well.add_child(water)

	# Carved stone coping borders around well base
	for edge_rot in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var dir := Vector3(sin(edge_rot), 0.0, cos(edge_rot))
		_spawn_part(well, "Prop_ExteriorBorder_Straight1.gltf", dir * (1.18 * V_SCALE) + Vector3(0.0, 0.72 * V_SCALE, 0.0), edge_rot, Vector3.INF, Vector3(1.10, 1.25, 0.55))

	# 4 corner timber posts + crossbeam + winch drum supporting a slate-tiled tower spire roof
	for px in [-1.14 * V_SCALE, 1.14 * V_SCALE]:
		for pz in [-1.14 * V_SCALE, 1.14 * V_SCALE]:
			_add_box_visual(well, "WellPostBase", Vector3(float(px), 0.28 * V_SCALE, float(pz)), Vector3(0.32, 0.62, 0.32) * V_SCALE, _mat_stone_foundation)
			_add_box_visual(well, "WellPost", Vector3(float(px), 1.48 * V_SCALE, float(pz)), Vector3(0.20, 2.15, 0.20) * V_SCALE, _mat_wood_trim)
	_add_box_visual(well, "WellWinchBeam", Vector3(0.0, 1.72 * V_SCALE, 0.0), Vector3(2.20, 0.14, 0.14) * V_SCALE, _mat_wood_trim)
	_add_box_visual(well, "WellPulley", Vector3(0.0, 1.72 * V_SCALE, 0.0), Vector3(0.72, 0.28, 0.28) * V_SCALE, _mat_wood_dark)
	_add_box_visual(well, "WellRope", Vector3(0.0, 1.38 * V_SCALE, 0.0), Vector3(0.05, 0.62, 0.05) * V_SCALE, _get_color_mat("hemp", Color(0.76, 0.64, 0.44)))
	_add_box_visual(well, "WellBucket", Vector3(0.0, 1.08 * V_SCALE, 0.0), Vector3(0.36, 0.34, 0.36) * V_SCALE, _mat_wood_trim)
	_add_box_visual(well, "WellBucketBand", Vector3(0.0, 1.12 * V_SCALE, 0.0), Vector3(0.38, 0.07, 0.38) * V_SCALE, _mat_iron)
	_spawn_tinted_part(well, "Roof_Tower_RoundTiles.gltf", "slate", Vector3(0.0, 2.52 * V_SCALE, 0.0), 0.0, Vector3(0.58, 0.56, 0.58))
	for corner_sign: Vector2 in [Vector2(-1.42, -1.42), Vector2(1.42, -1.42), Vector2(-1.42, 1.42), Vector2(1.42, 1.42)]:
		var cs_pos: Vector2 = corner_sign * V_SCALE
		_add_box_visual(well, "WellPlanterBox", Vector3(cs_pos.x, 0.22 * V_SCALE, cs_pos.y), Vector3(0.58, 0.40, 0.58) * V_SCALE, _mat_wood_dark)
		_spawn_ext_prop(well, "res://assets/nature/Flower_4_Group.gltf", Vector3(cs_pos.x, 0.42 * V_SCALE, cs_pos.y), corner_sign.x, Vector3.ONE * (0.72 * V_SCALE), false)

	var well_light := OmniLight3D.new()
	well_light.position = Vector3(0.0, 2.25 * V_SCALE, 0.0)
	well_light.light_color = Color(1.0, 0.80, 0.44)
	well_light.light_energy = 1.45
	well_light.omni_range = 12.0 * V_SCALE
	well_light.shadow_enabled = false
	well_light.distance_fade_enabled = true
	well_light.distance_fade_begin = 110.0
	well_light.distance_fade_length = 35.0
	well.add_child(well_light)
	_register_night_light(well_light, 1.45)

	_add_cylinder_collider(colliders, Vector3(wx, ground_y + 1.3 * V_SCALE, wz), 1.38 * V_SCALE, 2.9 * V_SCALE)


func _build_market_stalls(root: Node3D, colliders: StaticBody3D, terrain: Node3D) -> void:
	var group := Node3D.new()
	group.name = "MarketStalls"
	root.add_child(group)

	for i in range(STALL_SPECS.size()):
		var spec := STALL_SPECS[i]
		var off: Vector2 = spec["offset"] * V_SCALE
		var yaw: float = spec["yaw"]
		var canopy_col: Color = spec["canopy"]

		var wx: float = VILLAGE_CENTER.x + off.x
		var wz: float = VILLAGE_CENTER.z + off.y
		var mm := _sample_patch_minmax(terrain, wx, wz, 1.65 * V_SCALE, 0.95 * V_SCALE, yaw)
		var top_y: float = mm.y + 0.07
		var bot_y: float = mm.x - 0.8
		var plinth_h: float = maxf(top_y - bot_y, 0.90)

		var stall := Node3D.new()
		stall.name = "MarketStall_%d" % i
		stall.position = Vector3(wx, 0.0, wz)
		stall.rotation = Vector3(0.0, yaw, 0.0)
		group.add_child(stall)

		var plinth_pos := Vector3(0.0, bot_y + plinth_h * 0.5, 0.0)
		var plinth_size := Vector3(3.2 * V_SCALE, plinth_h, 1.8 * V_SCALE)
		_add_box_visual(stall, "Plinth", plinth_pos, plinth_size, _mat_stone_foundation)

		var stall_body := Node3D.new()
		stall_body.name = "StallBody"
		stall_body.position = Vector3(0.0, top_y, 0.0)
		stall_body.scale = Vector3.ONE * V_SCALE
		stall.add_child(stall_body)

		_add_box_visual(stall_body, "Counter", Vector3(0.0, 0.46, 0.25), Vector3(2.85, 0.92, 0.78), _mat_wood_dark)
		_add_box_visual(stall_body, "CounterTop", Vector3(0.0, 0.96, 0.25), Vector3(2.96, 0.12, 0.92), _mat_wood_trim)

		for px in [-1.36, 1.36]:
			_add_box_visual(stall_body, "BackPost", Vector3(float(px), 1.25, -0.68), Vector3(0.16, 2.50, 0.16), _mat_wood_trim)
			_add_box_visual(stall_body, "FrontPost", Vector3(float(px), 1.25, 0.68), Vector3(0.16, 2.50, 0.16), _mat_wood_trim)

		# Real kit tiled market canopy tinted per guild color
		var roof_mesh := _get_mesh("Roof_2x4_RoundTile.gltf")
		if roof_mesh != null:
			var dup_roof := roof_mesh.duplicate() as Mesh
			var tile_tint: Color = Color(0.90, 0.90, 0.90).lerp(canopy_col * 1.15, 0.78)
			for si in range(dup_roof.get_surface_count()):
				var sm := dup_roof.surface_get_material(si) as StandardMaterial3D
				if sm != null and (sm.resource_name.contains("RoundTiles") or (sm.albedo_texture != null and sm.albedo_texture.resource_path.contains("RoundTiles"))):
					var tsm := sm.duplicate() as StandardMaterial3D
					var gtex := _get_gray_tile_texture(sm.albedo_texture)
					if gtex != null:
						tsm.albedo_texture = gtex
					tsm.albedo_color = tile_tint
					tsm.metallic = 0.0
					tsm.metallic_specular = 0.08
					tsm.roughness = maxf(tsm.roughness, 0.88)
					tsm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
					tsm.cull_mode = BaseMaterial3D.CULL_BACK
					dup_roof.surface_set_material(si, tsm)
			var rmi := MeshInstance3D.new()
			rmi.name = "TiledAwning"
			rmi.mesh = dup_roof
			rmi.position = Vector3(0.0, 2.38, 0.0)
			rmi.rotation = Vector3(0.0, PI * 0.5, 0.0)
			rmi.scale = Vector3(0.66, 0.64, 0.88)
			stall_body.add_child(rmi)

		# Stocked guild goods & wares cleanly placed on counters and beneath awnings
		_populate_stall_wares(stall_body, i, 0.0)

		# Small hanging warm brass lantern under awning eaves
		_add_box_visual(stall_body, "StallLanternMount", Vector3(0.0, 2.26, 0.66), Vector3(0.10, 0.18, 0.10), _mat_iron)
		var sl_glass := _add_box_visual(stall_body, "StallLanternGlow", Vector3(0.0, 2.10, 0.66), Vector3(0.20, 0.24, 0.20), _mat_lantern_glow)
		if sl_glass != null:
			sl_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var stall_basis := Basis(Vector3.UP, yaw)
		var col_local := Vector3(0.0, bot_y + (plinth_h + 2.4 * V_SCALE) * 0.5, 0.0)
		_add_box_collider(
			colliders,
			Transform3D(stall_basis, Vector3(wx, 0.0, wz) + stall_basis * col_local),
			Vector3(3.2 * V_SCALE, plinth_h + 2.4 * V_SCALE, 1.8 * V_SCALE)
		)


func _build_street_lanterns(root: Node3D, colliders: StaticBody3D, terrain: Node3D) -> void:
	var group := Node3D.new()
	group.name = "StreetLanterns"
	root.add_child(group)

	for i in range(LANTERN_OFFSETS.size()):
		var off := LANTERN_OFFSETS[i] * V_SCALE
		var wx: float = VILLAGE_CENTER.x + off.x
		var wz: float = VILLAGE_CENTER.z + off.y
		var gy: float = _sample_h(terrain, wx, wz)

		var aim := Vector2(1.0, 0.0)
		if absf(off.x) < 5.0 * V_SCALE and absf(off.y) > 8.0 * V_SCALE:
			aim = Vector2(-signf(off.x), 0.0)
		elif absf(off.y) < 5.0 * V_SCALE and absf(off.x) > 8.0 * V_SCALE:
			aim = Vector2(0.0, -signf(off.y))
		else:
			aim = (-off).normalized()

		var post := Node3D.new()
		post.name = "StreetLantern_%d" % i
		post.position = Vector3(wx, gy, wz)
		post.rotation.y = atan2(-aim.y, aim.x)
		post.scale = Vector3.ONE * V_SCALE
		group.add_child(post)

		_add_box_visual(post, "Socket", Vector3(0.0, 0.05, 0.0), Vector3(0.56, 0.90, 0.56), _mat_stone_foundation)
		_add_box_visual(post, "StoneCollar", Vector3(0.0, 0.54, 0.0), Vector3(0.42, 0.16, 0.42), _mat_stone_foundation)
		_add_box_visual(post, "TimberPost", Vector3(0.0, 1.85, 0.0), Vector3(0.20, 3.10, 0.20), _mat_wood_dark)
		_add_box_visual(post, "PostCap", Vector3(0.0, 3.44, 0.0), Vector3(0.28, 0.10, 0.28), _mat_iron)
		_add_box_visual(post, "IronArm", Vector3(0.32, 3.16, 0.0), Vector3(0.66, 0.10, 0.10), _mat_iron)
		_add_box_visual(post, "KneeBrace", Vector3(0.22, 2.94, 0.0), Vector3(0.46, 0.07, 0.07), _mat_iron, Vector3(0.0, 0.0, 0.78))
		_add_box_visual(post, "Chain", Vector3(0.58, 3.05, 0.0), Vector3(0.06, 0.16, 0.06), _mat_iron)
		_add_box_visual(post, "LanternCap", Vector3(0.58, 2.95, 0.0), Vector3(0.36, 0.10, 0.36), _mat_iron)
		_add_box_visual(post, "LanternSpire", Vector3(0.58, 3.02, 0.0), Vector3(0.16, 0.08, 0.16), _mat_iron)
		var lglow := _add_box_visual(post, "LanternGlow", Vector3(0.58, 2.74, 0.0), Vector3(0.24, 0.34, 0.24), _mat_lantern_glow)
		lglow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for cx_bar in [-0.12, 0.12]:
			for cz_bar in [-0.12, 0.12]:
				_add_box_visual(post, "CageBar", Vector3(0.58 + float(cx_bar), 2.74, float(cz_bar)), Vector3(0.035, 0.36, 0.035), _mat_iron)
		_add_box_visual(post, "LanternBase", Vector3(0.58, 2.54, 0.0), Vector3(0.30, 0.08, 0.30), _mat_iron)

		if i < 24 and i % 4 == 0:
			var light := OmniLight3D.new()
			light.position = Vector3(0.58, 2.70, 0.0)
			light.light_color = Color(1.0, 0.79, 0.44)
			light.light_energy = 1.45
			light.omni_range = 16.0 * V_SCALE
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 110.0
			light.distance_fade_length = 35.0
			post.add_child(light)
			_register_night_light(light, 1.45)

		_add_cylinder_collider(colliders, Vector3(wx, gy + 1.5 * V_SCALE, wz), 0.28 * V_SCALE, 3.2 * V_SCALE)


func _build_town_trees(root: Node3D, colliders: StaticBody3D, terrain: Node3D) -> void:
	var group := Node3D.new()
	group.name = "TownTrees"
	root.add_child(group)

	for i in range(TREE_SPECS.size()):
		var spec := TREE_SPECS[i]
		var off: Vector2 = spec["offset"] * V_SCALE
		var arch: int = spec["arch"]
		var sc: float = float(spec["scale"]) * 1.18
		var yaw: float = spec["yaw"]

		var tree_mesh := terrain.call("_get_tree_mesh", arch) as Mesh
		if tree_mesh == null:
			continue

		var wx: float = VILLAGE_CENTER.x + off.x
		var wz: float = VILLAGE_CENTER.z + off.y
		var gy: float = _sample_h(terrain, wx, wz) - 0.25

		var mi := MeshInstance3D.new()
		mi.name = "TownTree_%d" % i
		mi.mesh = tree_mesh
		mi.position = Vector3(wx, gy, wz)
		mi.rotation = Vector3(0.0, yaw, 0.0)
		mi.scale = Vector3(sc, sc, sc)
		group.add_child(mi)

		_add_cylinder_collider(colliders, Vector3(wx, gy + 2.2 * sc, wz), 0.42 * sc, 4.4 * sc)


func _build_props_and_fences(root: Node3D, colliders: StaticBody3D, terrain: Node3D) -> void:
	var group := Node3D.new()
	group.name = "TownProps"
	root.add_child(group)

	for i in range(WAGON_SPECS.size()):
		var spec := WAGON_SPECS[i]
		var off: Vector2 = spec["offset"] * V_SCALE
		var yaw: float = spec["yaw"]
		var wx: float = VILLAGE_CENTER.x + off.x
		var wz: float = VILLAGE_CENTER.z + off.y
		var plaza_lift := 0.048 if (absf(off.x) <= 13.2 * V_SCALE and absf(off.y) <= 13.2 * V_SCALE) else 0.0

		var dir_z := Vector2(sin(yaw), cos(yaw))
		var p_front := Vector2(wx, wz) - dir_z * 2.1 * V_SCALE
		var p_back := Vector2(wx, wz) + dir_z * 0.6 * V_SCALE
		var h_front: float = _sample_h(terrain, p_front.x, p_front.y) + plaza_lift
		var h_back: float = _sample_h(terrain, p_back.x, p_back.y) + plaza_lift
		var h_mid: float = _sample_h(terrain, wx, wz) + plaza_lift
		var wag_y: float = minf(h_mid, (h_front + h_back) * 0.5) - 0.02
		var slope_x: float = clampf(atan2(h_front - h_back, 2.7 * V_SCALE), -0.25, 0.25)

		var wag_node := Node3D.new()
		wag_node.name = "Wagon_%d" % i
		wag_node.position = Vector3(wx, wag_y, wz)
		wag_node.rotation = Vector3(slope_x, yaw, 0.0)
		group.add_child(wag_node)
		_spawn_part(wag_node, "Prop_Wagon.gltf", Vector3.ZERO, 0.0)

		var wb := Basis.from_euler(Vector3(slope_x, yaw, 0.0))
		_add_box_collider(
			colliders,
			Transform3D(wb, wag_node.position + wb * (Vector3(0.0, 0.78, -1.14) * V_SCALE)),
			Vector3(1.92, 1.48, 3.85) * V_SCALE
		)

	for ci in range(CRATE_CLUSTERS.size()):
		var cspec := CRATE_CLUSTERS[ci]
		var off: Vector2 = cspec["offset"] * V_SCALE
		var cnt: int = cspec["count"]
		var base_yaw: float = cspec["yaw"]
		var wx: float = VILLAGE_CENTER.x + off.x
		var wz: float = VILLAGE_CENTER.z + off.y

		var offsets_local := [Vector2.ZERO, Vector2(1.16, 0.14) * V_SCALE, Vector2(0.55, 0.0) * V_SCALE]
		for k in range(cnt):
			var oy: float = 0.0
			var ox_off := Vector2.ZERO
			if k == 1:
				ox_off = offsets_local[1].rotated(base_yaw)
			elif k == 2:
				ox_off = (Vector2(0.45, 0.06) * V_SCALE).rotated(base_yaw)
				oy = 1.04 * V_SCALE
			var cx: float = wx + ox_off.x
			var cz: float = wz + ox_off.y
			var rdx: float = cx - VILLAGE_CENTER.x
			var rdz: float = cz - VILLAGE_CENTER.z
			var on_cobble: bool = (absf(rdx) <= 13.2 * V_SCALE and absf(rdz) <= 13.2 * V_SCALE) or (absf(rdx) <= 2.5 * V_SCALE and absf(rdz) <= 56.5 * V_SCALE) or (absf(rdz) <= 2.5 * V_SCALE and absf(rdx) <= 62.5 * V_SCALE)
			var road_lift: float = 0.048 if on_cobble else 0.0
			var cy: float = _sample_h(terrain, cx, cz) + road_lift - 0.03 + oy
			var pos := Vector3(cx, cy, cz)
			var cyaw: float = base_yaw + float(k) * 0.35
			_spawn_part(group, "Prop_Crate.gltf", pos, cyaw)
			_add_box_collider(
				colliders,
				Transform3D(Basis(Vector3.UP, cyaw), pos + Vector3(0.0, 0.53 * V_SCALE, 0.0)),
				Vector3(1.06, 1.04, 1.06) * V_SCALE
			)

	# Continuous 16-segment double-faced crenellated stone ramparts connecting 4 Gatehouses, 4 Corner Watchtowers & 8 Bastion Turrets
	var octant_spans: Array = [
		[Vector2( -4.5, -52.5), Vector2(-45.0, -41.0)],
		[Vector2( 45.0, -41.0), Vector2(  4.5, -52.5)],
		[Vector2( 58.5,  -4.5), Vector2( 45.0, -41.0)],
		[Vector2( 45.0,  41.0), Vector2( 58.5,   4.5)],
		[Vector2(  4.5,  52.5), Vector2( 45.0,  41.0)],
		[Vector2(-45.0,  41.0), Vector2( -4.5,  52.5)],
		[Vector2(-58.5,   4.5), Vector2(-45.0,  41.0)],
		[Vector2(-45.0, -41.0), Vector2(-58.5,  -4.5)],
	]
	var stone_wall_runs: Array[Dictionary] = []
	for s_idx in range(octant_spans.size()):
		var span: Array = octant_spans[s_idx]
		var t0: Vector2 = span[0] * V_SCALE
		var t1: Vector2 = span[1] * V_SCALE
		var s_vec: Vector2 = (t1 - t0).normalized()
		var wa: Vector2 = t0 + s_vec * (1.85 * V_SCALE)
		var wb: Vector2 = t1 - s_vec * (1.85 * V_SCALE)
		var wmid: Vector2 = (wa + wb) * 0.5
		stone_wall_runs.append({"a": wa, "b": wmid, "pier": true, "span_idx": s_idx})
		stone_wall_runs.append({"a": wmid, "b": wb, "pier": false, "span_idx": s_idx})

	var bridge_center_2d := Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z)
	var turret_idx := 0
	for srun in stone_wall_runs:
		var sa: Vector2 = srun["a"] + bridge_center_2d
		var sb: Vector2 = srun["b"] + bridge_center_2d
		var slen: float = sa.distance_to(sb)
		var segs: int = maxi(1, int(round(slen / CELL)))
		var sdir: Vector2 = (sb - sa) / float(segs)
		var seg_w: float = sdir.length()
		var sdir_n: Vector2 = sdir.normalized()

		for si in range(segs):
			var pa: Vector2 = sa + sdir * float(si)
			var pb: Vector2 = pa + sdir
			var mid: Vector2 = (pa + pb) * 0.5
			var wall_mid_rel: Vector2 = mid - bridge_center_2d
			var outward_n: Vector2 = Vector2(-sdir_n.y, sdir_n.x)
			if outward_n.dot(wall_mid_rel) < 0.0:
				outward_n = -outward_n
			var wall_yaw: float = atan2(outward_n.x, outward_n.y)

			var ha: float = _sample_h(terrain, pa.x, pa.y)
			var hb: float = _sample_h(terrain, pb.x, pb.y)
			var hin: float = _sample_h(terrain, mid.x - outward_n.x * 0.80 * V_SCALE, mid.y - outward_n.y * 0.80 * V_SCALE)
			var hout: float = _sample_h(terrain, mid.x + outward_n.x * 0.80 * V_SCALE, mid.y + outward_n.y * 0.80 * V_SCALE)
			var min_h: float = minf(minf(ha, hb), minf(hin, hout))
			var avg_h: float = (ha + hb) * 0.5

			var wall_seg := Node3D.new()
			wall_seg.name = "StoneWallSeg"
			wall_seg.position = Vector3(mid.x, avg_h, mid.y)
			wall_seg.rotation.y = wall_yaw
			group.add_child(wall_seg)

			var plinth_bot: float = (min_h - avg_h) - 1.80
			var plinth_top: float = 0.72 * V_SCALE
			var plinth_h: float = plinth_top - plinth_bot
			_add_box_visual(wall_seg, "WallPlinth", Vector3(0.0, plinth_bot + plinth_h * 0.5, 0.0), Vector3(seg_w + 0.08 * V_SCALE, plinth_h, 1.72 * V_SCALE), _mat_stone_foundation)
			_add_box_visual(wall_seg, "WallCore", Vector3(0.0, 2.08 * V_SCALE, 0.0), Vector3(seg_w + 0.04 * V_SCALE, 2.96 * V_SCALE, 1.18 * V_SCALE), _mat_stone_foundation)
			_spawn_part(wall_seg, "Wall_UnevenBrick_Straight.gltf", Vector3(0.0, 0.60 * V_SCALE,  0.70 * V_SCALE), 0.0, Vector3.INF, Vector3(seg_w / CELL, 1.0, 1.0))
			_spawn_part(wall_seg, "Wall_UnevenBrick_Straight.gltf", Vector3(0.0, 0.60 * V_SCALE, -0.70 * V_SCALE), PI,  Vector3.INF, Vector3(seg_w / CELL, 1.0, 1.0))
			_add_box_visual(wall_seg, "RampartWalk", Vector3(0.0, 3.52 * V_SCALE, 0.0), Vector3(seg_w + 0.08 * V_SCALE, 0.22 * V_SCALE, 1.70 * V_SCALE), _mat_cobble)
			_add_box_visual(wall_seg, "OuterCornice", Vector3(0.0, 3.46 * V_SCALE,  0.86 * V_SCALE), Vector3(seg_w + 0.10 * V_SCALE, 0.18 * V_SCALE, 0.16 * V_SCALE), _mat_stone_foundation)
			_add_box_visual(wall_seg, "InnerCornice", Vector3(0.0, 3.46 * V_SCALE, -0.86 * V_SCALE), Vector3(seg_w + 0.10 * V_SCALE, 0.18 * V_SCALE, 0.16 * V_SCALE), _mat_stone_foundation)
			_add_box_visual(wall_seg, "OuterBreastwork", Vector3(0.0, 3.74 * V_SCALE, 0.72 * V_SCALE), Vector3(seg_w + 0.06 * V_SCALE, 0.28 * V_SCALE, 0.28 * V_SCALE), _mat_stone_foundation)
			for mx_sign in [-0.25, 0.25]:
				var mx: float = seg_w * float(mx_sign)
				_add_box_visual(wall_seg, "Merlon", Vector3(mx, 4.10 * V_SCALE, 0.72 * V_SCALE), Vector3(0.56, 0.52, 0.28) * V_SCALE, _mat_stone_foundation)
				_add_box_visual(wall_seg, "MerlonCap", Vector3(mx, 4.40 * V_SCALE, 0.72 * V_SCALE), Vector3(0.64, 0.09, 0.34) * V_SCALE, _mat_stone_foundation)
			_add_box_visual(wall_seg, "InnerParapet", Vector3(0.0, 3.82 * V_SCALE, -0.74 * V_SCALE), Vector3(seg_w + 0.06 * V_SCALE, 0.44 * V_SCALE, 0.22 * V_SCALE), _mat_stone_foundation)

			_add_box_collider(
				colliders,
				Transform3D(Basis(Vector3.UP, wall_yaw), Vector3(mid.x, avg_h + 2.15 * V_SCALE, mid.y)),
				Vector3(seg_w, 4.6 * V_SCALE, 1.68 * V_SCALE)
			)

		if bool(srun.get("pier", false)):
			var pier_rel: Vector2 = sb - bridge_center_2d
			var tw_out: Vector2 = Vector2(-sdir_n.y, sdir_n.x)
			if tw_out.dot(pier_rel) < 0.0:
				tw_out = -tw_out
			var tw_yaw: float = atan2(tw_out.x, tw_out.y)
			var tw_h: float = _sample_h(terrain, sb.x, sb.y)

			var turret := Node3D.new()
			turret.name = "BastionTurret_%d" % turret_idx
			turret.position = Vector3(sb.x, tw_h, sb.y)
			turret.rotation.y = tw_yaw
			group.add_child(turret)
			turret_idx += 1

			_add_box_visual(turret, "TurretPlinth", Vector3(0.0, -0.675 * V_SCALE, 0.0), Vector3(2.68, 3.05, 2.68) * V_SCALE, _mat_stone_foundation)
			_add_box_visual(turret, "TurretCore", Vector3(0.0, 2.30 * V_SCALE, 0.0), Vector3(2.26, 3.00, 2.26) * V_SCALE, _mat_stone_foundation)
			_spawn_part(turret, "Wall_UnevenBrick_Straight.gltf", Vector3( 0.0,  0.80,  1.25) * V_SCALE,  0.0,      Vector3.INF, Vector3(1.25, 1.0, 1.0))
			_spawn_part(turret, "Wall_UnevenBrick_Straight.gltf", Vector3( 0.0,  0.80, -1.25) * V_SCALE,  PI,       Vector3.INF, Vector3(1.25, 1.0, 1.0))
			_spawn_part(turret, "Wall_UnevenBrick_Straight.gltf", Vector3( 1.25, 0.80,  0.0) * V_SCALE,   PI * 0.5, Vector3.INF, Vector3(1.25, 1.0, 1.0))
			_spawn_part(turret, "Wall_UnevenBrick_Straight.gltf", Vector3(-1.25, 0.80,  0.0) * V_SCALE,  -PI * 0.5, Vector3.INF, Vector3(1.25, 1.0, 1.0))
			_spawn_part(turret, "Corner_Exterior_Brick.gltf", Vector3(-1.25, 0.80, -1.25) * V_SCALE,  PI * 0.5)
			_spawn_part(turret, "Corner_Exterior_Brick.gltf", Vector3( 1.25, 0.80, -1.25) * V_SCALE,  0.0)
			_spawn_part(turret, "Corner_Exterior_Brick.gltf", Vector3( 1.25, 0.80,  1.25) * V_SCALE, -PI * 0.5)
			_spawn_part(turret, "Corner_Exterior_Brick.gltf", Vector3(-1.25, 0.80,  1.25) * V_SCALE,  PI)

			_add_box_visual(turret, "TurretCornice", Vector3(0.0, 3.86 * V_SCALE, 0.0), Vector3(2.76, 0.22, 2.76) * V_SCALE, _mat_stone_foundation)
			_add_box_visual(turret, "TurretDeck", Vector3(0.0, 3.98 * V_SCALE, 0.0), Vector3(2.50, 0.16, 2.50) * V_SCALE, _mat_cobble)
			for px in [-1.08, 1.08]:
				for pz in [-1.08, 1.08]:
					_add_box_visual(turret, "TurretPier", Vector3(float(px), 4.58, float(pz)) * V_SCALE, Vector3(0.42, 1.24, 0.42) * V_SCALE, _mat_stone_foundation)
			for pside in [-1.14, 1.14]:
				_add_box_visual(turret, "TurretParapetZ", Vector3(0.0, 4.20, float(pside)) * V_SCALE, Vector3(2.40, 0.52, 0.22) * V_SCALE, _mat_stone_foundation)
				_add_box_visual(turret, "TurretParapetX", Vector3(float(pside), 4.20, 0.0) * V_SCALE, Vector3(0.22, 0.52, 2.40) * V_SCALE, _mat_stone_foundation)
			_add_box_visual(turret, "TurretEaves", Vector3(0.0, 5.18 * V_SCALE, 0.0), Vector3(2.58, 0.14, 2.58) * V_SCALE, _mat_wood_dark)
			_spawn_tinted_part(turret, "Roof_RoundTiles_4x4.gltf", "slate", Vector3(0.0, 5.22 * V_SCALE, 0.0), 0.0, Vector3(0.70, 0.70, 0.70))
			_spawn_wall_sconce(turret, Vector3(0.0, 3.15, -1.36) * V_SCALE, PI, false)

			_add_box_collider(
				colliders,
				Transform3D(Basis(Vector3.UP, tw_yaw), Vector3(sb.x, tw_h + 2.6 * V_SCALE, sb.y)),
				Vector3(2.58, 5.4, 2.58) * V_SCALE
			)

	# 4 inner corner-paddock stone rampart access stairs parallel to the North & South curtain walls
	for st_i in range(4):
		var st_span_idx: int = [0, 1, 4, 5][st_i]
		var sp: Array = octant_spans[st_span_idx]
		var corner_pt: Vector2 = (sp[1] if (st_span_idx == 0 or st_span_idx == 4) else sp[0]) * V_SCALE
		var gate_pt: Vector2 = (sp[0] if (st_span_idx == 0 or st_span_idx == 4) else sp[1]) * V_SCALE
		var stair_wall_rel: Vector2 = corner_pt.lerp(gate_pt, 0.25)
		var wall_tangent: Vector2 = (gate_pt - corner_pt).normalized()
		var st_out: Vector2 = Vector2(-wall_tangent.y, wall_tangent.x)
		if st_out.dot(stair_wall_rel) < 0.0:
			st_out = -st_out
		var st_yaw: float = atan2(st_out.x, st_out.y)

		var wall_sample: Vector2 = bridge_center_2d + stair_wall_rel
		var wall_h: float = _sample_h(terrain, wall_sample.x, wall_sample.y)
		var stair_pos_2d: Vector2 = wall_sample - st_out * (1.45 * V_SCALE)
		var st_h: float = _sample_h(terrain, stair_pos_2d.x, stair_pos_2d.y)
		var top_rel_y: float = (wall_h + 3.55 * V_SCALE) - st_h

		var r_stair := Node3D.new()
		r_stair.name = "RampartStairs_%d" % st_i
		r_stair.position = Vector3(stair_pos_2d.x, st_h, stair_pos_2d.y)
		r_stair.rotation.y = st_yaw
		group.add_child(r_stair)

		var landing_h: float = top_rel_y + 1.60
		_add_box_visual(r_stair, "LandingPier", Vector3(2.10 * V_SCALE, -1.60 + landing_h * 0.5, 0.0), Vector3(1.50 * V_SCALE, landing_h, 1.25 * V_SCALE), _mat_stone_foundation)
		_add_box_visual(r_stair, "LandingDeck", Vector3(2.10 * V_SCALE, top_rel_y, 0.0), Vector3(1.56, 0.14, 1.30) * V_SCALE, _mat_cobble)

		var flight_step_y: float = top_rel_y / 3.0
		var flight_xs: Array[float] = [-1.35 * V_SCALE, -0.30 * V_SCALE, 0.75 * V_SCALE]
		for fi in range(3):
			var fy: float = float(fi) * flight_step_y
			var fx: float = flight_xs[fi]
			var plinth_fy_h: float = fy + 1.60 + flight_step_y * 0.45
			_add_box_visual(r_stair, "StairPlinth", Vector3(fx, -1.60 + plinth_fy_h * 0.5, 0.0), Vector3(1.08 * V_SCALE, plinth_fy_h, 1.22 * V_SCALE), _mat_stone_foundation)
			_spawn_part(r_stair, "Stairs_Exterior_Straight.gltf", Vector3(fx, fy, 0.0), -PI * 0.5, Vector3.INF, Vector3(0.68, flight_step_y * 1.05 / V_SCALE, 0.66))

		var st_basis := Basis(Vector3.UP, st_yaw)
		_add_box_collider(
			colliders,
			Transform3D(st_basis, r_stair.position + st_basis * Vector3(0.65 * V_SCALE, top_rel_y * 0.5, 0.0)),
			Vector3(4.6 * V_SCALE, top_rel_y + 0.4, 1.26 * V_SCALE)
		)

	# Ornamental wrought-iron forecourt fences framing the Guildhall and VillageAbbey courtyards
	var iron_runs: Array[Dictionary] = [
		{"a": Vector2(-12.5, -13.8), "b": Vector2(-10.2, -13.8)},
		{"a": Vector2( 10.2, -13.8), "b": Vector2( 12.5, -13.8)},
		{"a": Vector2( -4.0, -24.0), "b": Vector2( -4.0, -16.5)},
		{"a": Vector2(  4.0, -24.0), "b": Vector2(  4.0, -16.5)},
	]
	for irun in iron_runs:
		var ia: Vector2 = irun["a"] * V_SCALE + Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z)
		var ib: Vector2 = irun["b"] * V_SCALE + Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z)
		var ilen: float = ia.distance_to(ib)
		var ipanels: int = maxi(1, int(round(ilen / (1.5 * V_SCALE))))
		var idir: Vector2 = (ib - ia) / float(ipanels)
		var ipanel_w: float = idir.length()
		var iyaw: float = atan2(-idir.y, idir.x)
		for ipi in range(ipanels):
			var ipa: Vector2 = ia + idir * float(ipi)
			var ipb: Vector2 = ipa + idir
			var imid: Vector2 = (ipa + ipb) * 0.5
			var min_ground: float = minf(_sample_h(terrain, ipa.x, ipa.y), _sample_h(terrain, ipb.x, ipb.y))
			var ifpos := Vector3(imid.x, min_ground - 0.14 * V_SCALE, imid.y)
			_spawn_part(group, "Prop_MetalFence_Ornament.gltf", ifpos, iyaw, Vector3.INF, Vector3(ipanel_w / (1.95 * V_SCALE), 0.72, 1.0))
			_add_box_collider(
				colliders,
				Transform3D(Basis(Vector3.UP, iyaw), ifpos + Vector3(0.0, 1.02 * V_SCALE, 0.0)),
				Vector3(ipanel_w, 2.04 * V_SCALE, 0.24 * V_SCALE)
			)

	for ri in range(FENCE_RUNS.size()):
		var run := FENCE_RUNS[ri]
		var a: Vector2 = run["a"] * V_SCALE + Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z)
		var b: Vector2 = run["b"] * V_SCALE + Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z)
		var total_len: float = a.distance_to(b)
		var panels: int = maxi(1, int(round(total_len / CELL)))
		var dir2: Vector2 = (b - a) / float(panels)
		var panel_len: float = dir2.length()
		var yaw: float = atan2(-dir2.y, dir2.x)

		for pi_idx in range(panels):
			var pa: Vector2 = a + dir2 * float(pi_idx)
			var pb: Vector2 = pa + dir2
			var mid: Vector2 = (pa + pb) * 0.5
			var ha: float = _sample_h(terrain, pa.x, pa.y)
			var hb: float = _sample_h(terrain, pb.x, pb.y)
			var slope_z: float = clampf(atan2(hb - ha, maxf(panel_len, 0.1)), -0.45, 0.45)
			var fpos := Vector3(mid.x, (ha + hb) * 0.5 - 0.04, mid.y)
			var rot_euler := Vector3(0.0, yaw, slope_z)
			_spawn_part(group, "Prop_WoodenFence_Single.gltf", fpos, 0.0, rot_euler)
			var fb := Basis.from_euler(rot_euler)
			_add_box_collider(colliders, Transform3D(fb, fpos + fb * Vector3(0.0, 0.42 * V_SCALE, 0.0)), Vector3(panel_len, 0.84 * V_SCALE, 0.24 * V_SCALE))

	# Cozy civic life clusters: outdoor Inn tables, Bakery bread display, Blacksmith anvil & forge rack,
	# plaza wooden benches, wine barrels, bottle crates, and timber flower boxes (all statically batched!).
	_populate_civic_life_props(group, colliders, terrain)


func _get_color_mat(key: String, col: Color, rough: float = 0.88) -> StandardMaterial3D:
	if _color_mat_cache.has(key):
		return _color_mat_cache[key] as StandardMaterial3D
	var mat := _make_matte_mat(col, rough)
	_color_mat_cache[key] = mat
	return mat


func _spawn_ext_prop(parent: Node3D, res_path: String, pos: Vector3, rot_y: float = 0.0, scale_vec: Vector3 = Vector3.ONE, shadow: bool = true) -> Node3D:
	var tmpl: Node3D = _ext_scene_cache.get(res_path) as Node3D
	if tmpl == null:
		var ps := load(res_path) as PackedScene
		if ps == null:
			return null
		tmpl = ps.instantiate() as Node3D
		if tmpl == null:
			return null
		_normalize_glb_materials(tmpl)
		_ext_scene_cache[res_path] = tmpl
	var inst := tmpl.duplicate() as Node3D
	inst.position = pos
	inst.rotation = Vector3(0.0, rot_y, 0.0)
	if scale_vec != Vector3.ONE:
		inst.scale = scale_vec
	if not shadow:
		_disable_shadow_recursive(inst)
	parent.add_child(inst)
	return inst


func _disable_shadow_recursive(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_disable_shadow_recursive(ch)


func _populate_stall_wares(stall: Node3D, idx: int, fy: float) -> void:
	var cy := fy + 1.02
	# Ground crates / barrels tucked cleanly underneath or beside counter
	_spawn_ext_prop(stall, "res://assets/fishing/barrel.glb", Vector3(-1.02, fy - 0.01, -0.34), 0.2, Vector3.ONE * 0.85, true)
	if idx % 2 == 0:
		_spawn_ext_prop(stall, "res://assets/fishing/crate.glb", Vector3(0.95, fy - 0.01, -0.36), -0.3, Vector3.ONE * 0.82, true)
	else:
		_spawn_ext_prop(stall, "res://assets/fishing/chest.glb", Vector3(0.95, fy - 0.01, -0.34), 0.15, Vector3.ONE * 0.85, true)

	match idx % 4:
		0:
			# Harvest & Fruit Stall: wooden tray + crimson apples, golden melons & green cabbages
			var apples := _get_color_mat("apple_red", Color(0.86, 0.20, 0.16), 0.72)
			var pumpkin := _get_color_mat("pumpkin_gold", Color(0.92, 0.52, 0.14), 0.78)
			var cabbage := _get_color_mat("cabbage_green", Color(0.32, 0.62, 0.26), 0.82)
			_add_box_visual(stall, "ProduceTrayL", Vector3(-0.78, cy + 0.04, 0.22), Vector3(0.76, 0.08, 0.54), _mat_wood_trim).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for ax in [-0.95, -0.78, -0.62]:
				for az in [0.12, 0.30]:
					var orb := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.09
					sm.height = 0.18
					sm.radial_segments = 8
					sm.rings = 4
					orb.mesh = sm
					orb.material_override = apples if idx < 4 else cabbage
					orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					orb.position = Vector3(float(ax), cy + 0.15, float(az))
					stall.add_child(orb)
			for px_off in [0.12, 0.42]:
				var mel := MeshInstance3D.new()
				var ms := SphereMesh.new()
				ms.radius = 0.15
				ms.height = 0.26
				ms.radial_segments = 8
				ms.rings = 4
				mel.mesh = ms
				mel.material_override = pumpkin
				mel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mel.position = Vector3(float(px_off), cy + 0.13, 0.24)
				stall.add_child(mel)
			_spawn_ext_prop(stall, "res://assets/fishing/crate-bottles.glb", Vector3(0.96, cy, 0.24), 0.2, Vector3.ONE * 0.68, false)
		1:
			# Florist & Herbalist / Botanical Stall: colorful flowers, forest mushrooms & potion flasks
			_spawn_ext_prop(stall, "res://assets/nature/Flower_3_Group.gltf", Vector3(-0.92, cy, 0.22), 0.3, Vector3.ONE * 0.85, false)
			_spawn_ext_prop(stall, "res://assets/nature/Flower_4_Group.gltf", Vector3(-0.22, cy, 0.24), -0.4, Vector3.ONE * 0.85, false)
			_spawn_ext_prop(stall, "res://assets/nature/Mushroom_Laetiporus.gltf", Vector3(0.45, cy, 0.22), 0.5, Vector3.ONE * 0.72, false)
			_spawn_ext_prop(stall, "res://assets/fishing/crate-bottles.glb", Vector3(0.98, cy, 0.24), -0.2, Vector3.ONE * 0.65, false)
		2:
			# Bakery & Cloth / Pantry Stall: warm golden bread loaves, stacked cheese & mugs
			var bread_mat := _get_color_mat("bread_crust", Color(0.84, 0.58, 0.26), 0.86)
			var cheese_mat := _get_color_mat("cheese_gold", Color(0.96, 0.78, 0.28), 0.78)
			for bx in [-0.95, -0.58, -0.22]:
				var loaf := _add_box_visual(stall, "BreadLoaf", Vector3(float(bx), cy + 0.08, 0.22), Vector3(0.28, 0.14, 0.18), bread_mat)
				if loaf != null:
					loaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for cx_off in [0.34, 0.34]:
				var wheel := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.18
				cm.bottom_radius = 0.18
				cm.height = 0.11
				cm.radial_segments = 10
				wheel.mesh = cm
				wheel.material_override = cheese_mat
				wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				wheel.position = Vector3(float(cx_off), cy + (0.06 if cx_off == 0.34 else 0.17), 0.22)
				stall.add_child(wheel)
			_spawn_ext_prop(stall, "res://assets/npcs/mug_full.gltf", Vector3(0.82, cy, 0.20), 0.4, Vector3.ONE * 0.95, false)
			_spawn_ext_prop(stall, "res://assets/npcs/mug_full.gltf", Vector3(1.06, cy, 0.28), -0.3, Vector3.ONE * 0.95, false)
		_:
			# Merchant / Clothier & Oddities Stall: folded colorful fabric bolts, open ledger & brass coffer
			var cloth_cols := [
				["cloth_crimson", Color(0.76, 0.22, 0.22)],
				["cloth_cobalt", Color(0.22, 0.38, 0.72)],
				["cloth_saffron", Color(0.90, 0.70, 0.22)],
			]
			for ci in range(cloth_cols.size()):
				var cmat := _get_color_mat(cloth_cols[ci][0], cloth_cols[ci][1], 0.90)
				var bolt := _add_box_visual(stall, "ClothBolt", Vector3(-0.92 + float(ci) * 0.34, cy + 0.08, 0.22), Vector3(0.28, 0.15, 0.46), cmat)
				if bolt != null:
					bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_spawn_ext_prop(stall, "res://assets/npcs/spellbook_open.gltf", Vector3(0.25, cy + 0.04, 0.25), 0.15, Vector3.ONE * 0.95, false)
			_spawn_ext_prop(stall, "res://assets/fishing/chest.glb", Vector3(0.92, cy, 0.22), -0.25, Vector3.ONE * 0.48, false)


func _populate_civic_life_props(group: Node3D, colliders: StaticBody3D, terrain: Node3D) -> void:
	# 1. Plaza Well Quadrant Wooden Benches & Planter Boxes facing the central Well
	var bench_specs := [
		{"off": Vector2(-4.8, -4.8), "yaw": PI * 0.25},
		{"off": Vector2( 4.8, -4.8), "yaw": -PI * 0.25},
		{"off": Vector2(-4.8,  4.8), "yaw": PI * 0.75},
		{"off": Vector2( 4.8,  4.8), "yaw": -PI * 0.75},
		{"off": Vector2(-5.2, -14.8), "yaw": 0.0},
		{"off": Vector2( 5.2, -14.8), "yaw": 0.0},
	]
	for bspec in bench_specs:
		var boff: Vector2 = bspec["off"] * V_SCALE
		var byaw: float = bspec["yaw"]
		var bx: float = VILLAGE_CENTER.x + boff.x
		var bz: float = VILLAGE_CENTER.z + boff.y
		var by: float = _sample_h(terrain, bx, bz) + 0.048
		var bench := Node3D.new()
		bench.name = "PlazaBench"
		bench.position = Vector3(bx, by, bz)
		bench.rotation = Vector3(0.0, byaw, 0.0)
		bench.scale = Vector3.ONE * V_SCALE
		group.add_child(bench)
		_add_box_visual(bench, "Seat", Vector3(0.0, 0.42, 0.0), Vector3(1.65, 0.10, 0.50), _mat_wood_trim)
		_add_box_visual(bench, "LegL", Vector3(-0.68, 0.21, 0.0), Vector3(0.14, 0.42, 0.44), _mat_wood_dark)
		_add_box_visual(bench, "LegR", Vector3( 0.68, 0.21, 0.0), Vector3(0.14, 0.42, 0.44), _mat_wood_dark)
		_add_box_visual(bench, "Back", Vector3(0.0, 0.74, -0.20), Vector3(1.65, 0.34, 0.08), _mat_wood_trim)
		_add_box_collider(colliders, Transform3D(Basis(Vector3.UP, byaw), Vector3(bx, by + 0.38 * V_SCALE, bz)), Vector3(1.65, 0.76, 0.52) * V_SCALE)

	# 2. GoldenSlimeInn & Bakery Outdoor Terrace Tables + Benches + Barrels (x=-14.2 apron)
	var inn_tables := [Vector2(-14.2, -9.8), Vector2(-14.2, -5.8), Vector2(-14.2, 6.2)]
	for ti in range(inn_tables.size()):
		var toff: Vector2 = inn_tables[ti] * V_SCALE
		var tx: float = VILLAGE_CENTER.x + toff.x
		var tz: float = VILLAGE_CENTER.z + toff.y
		var ty: float = _sample_h(terrain, tx, tz) + 0.048
		var tbl := Node3D.new()
		tbl.name = "InnTable_%d" % ti
		tbl.position = Vector3(tx, ty, tz)
		tbl.scale = Vector3.ONE * V_SCALE
		group.add_child(tbl)
		_add_box_visual(tbl, "TableTop", Vector3(0.0, 0.74, 0.0), Vector3(1.60, 0.10, 0.92), _mat_wood_trim)
		_add_box_visual(tbl, "TableLegL", Vector3(-0.62, 0.37, 0.0), Vector3(0.14, 0.74, 0.72), _mat_wood_dark)
		_add_box_visual(tbl, "TableLegR", Vector3( 0.62, 0.37, 0.0), Vector3(0.14, 0.74, 0.72), _mat_wood_dark)
		_add_box_visual(tbl, "BenchN", Vector3(0.0, 0.40, -0.78), Vector3(1.45, 0.10, 0.34), _mat_wood_trim)
		_add_box_visual(tbl, "BenchS", Vector3(0.0, 0.40,  0.78), Vector3(1.45, 0.10, 0.34), _mat_wood_trim)
		if ti < 2:
			_spawn_ext_prop(tbl, "res://assets/npcs/mug_full.gltf", Vector3(-0.35, 0.79, 0.10), 0.3, Vector3.ONE * 0.95, false)
			_spawn_ext_prop(tbl, "res://assets/npcs/mug_full.gltf", Vector3(0.32, 0.79, -0.14), -0.6, Vector3.ONE * 0.95, false)
		else:
			var bread_m := _get_color_mat("bread_crust", Color(0.84, 0.58, 0.26), 0.86)
			_add_box_visual(tbl, "BakeryLoaf1", Vector3(-0.35, 0.86, 0.08), Vector3(0.30, 0.14, 0.18), bread_m).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_add_box_visual(tbl, "BakeryLoaf2", Vector3(0.28, 0.86, -0.10), Vector3(0.28, 0.14, 0.18), bread_m).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_box_collider(colliders, Transform3D(Basis.IDENTITY, Vector3(tx, ty + 0.44 * V_SCALE, tz)), Vector3(1.65, 0.88, 1.85) * V_SCALE)

	# 3. Tavern, Brewery, Market & Apothecary Barrel + Bottle Crate Clusters
	var barrel_spots := [
		Vector2(-15.5, -12.4), Vector2(-15.5, 11.4), Vector2(14.8, -11.4),
		Vector2(14.8, 11.2), Vector2(13.2, 18.2), Vector2(-13.2, 18.2),
		Vector2(6.5, 36.2), Vector2(-24.8, -35.8),
	]
	for bi in range(barrel_spots.size()):
		var bo: Vector2 = barrel_spots[bi] * V_SCALE
		var bx: float = VILLAGE_CENTER.x + bo.x
		var bz: float = VILLAGE_CENTER.z + bo.y
		var by: float = _sample_h(terrain, bx, bz) + (0.048 if absf(bo.x) <= 13.5 * V_SCALE and absf(bo.y) <= 13.5 * V_SCALE else 0.0)
		_spawn_ext_prop(group, "res://assets/fishing/barrel.glb", Vector3(bx, by, bz), float(bi) * 0.6, Vector3.ONE * V_SCALE, true)
		_spawn_ext_prop(group, "res://assets/fishing/crate-bottles.glb", Vector3(bx + 0.88 * V_SCALE, by, bz + 0.22 * V_SCALE), float(bi) * 0.4, Vector3.ONE * (0.88 * V_SCALE), true)
		_add_cylinder_collider(colliders, Vector3(bx, by + 0.55 * V_SCALE, bz), 0.60 * V_SCALE, 1.15 * V_SCALE)

	# 4. Blacksmith Forge Courtyard (outside Blacksmith at (+8.5, +14.8) * V_SCALE)
	var fx: float = VILLAGE_CENTER.x + 5.8 * V_SCALE
	var fz: float = VILLAGE_CENTER.z + 14.8 * V_SCALE
	var fy_smith: float = _sample_h(terrain, fx, fz) + 0.048
	var smith_yard := Node3D.new()
	smith_yard.name = "BlacksmithCourtyard"
	smith_yard.position = Vector3(fx, fy_smith, fz)
	smith_yard.scale = Vector3.ONE * V_SCALE
	group.add_child(smith_yard)
	_add_box_visual(smith_yard, "AnvilStump", Vector3(0.0, 0.34, 0.0), Vector3(0.56, 0.68, 0.56), _mat_wood_dark)
	_add_box_visual(smith_yard, "AnvilBase", Vector3(0.0, 0.76, 0.0), Vector3(0.46, 0.16, 0.32), _mat_iron)
	_add_box_visual(smith_yard, "AnvilHorn", Vector3(0.0, 0.90, 0.0), Vector3(0.68, 0.14, 0.24), _mat_iron)
	_spawn_ext_prop(smith_yard, "res://assets/fishing/barrel.glb", Vector3(1.15, 0.0, 0.15), 0.3, Vector3.ONE, true)
	_spawn_ext_prop(smith_yard, "res://assets/npcs/sword_1handed.gltf", Vector3(1.15, 0.96, 0.15), 0.4, Vector3.ONE, false)
	_add_box_collider(colliders, Transform3D(Basis.IDENTITY, Vector3(fx + 0.45 * V_SCALE, fy_smith + 0.55 * V_SCALE, fz)), Vector3(1.90, 1.10, 0.85) * V_SCALE)

	# 5. Vibrant Flower Planter Boxes along Plaza Promenade Corners
	for poff: Vector2 in [
		Vector2(-12.2, -12.2), Vector2(12.2, -12.2), Vector2(-12.2, 12.2), Vector2(12.2, 12.2),
		Vector2(-7.8, -14.8), Vector2(7.8, -14.8), Vector2(-7.8, 14.8), Vector2(7.8, 14.8),
	]:
		var ps: Vector2 = poff * V_SCALE
		var px: float = VILLAGE_CENTER.x + ps.x
		var pz: float = VILLAGE_CENTER.z + ps.y
		var py: float = _sample_h(terrain, px, pz) + 0.048
		_add_box_visual(group, "FlowerPlanter", Vector3(px, py + 0.20 * V_SCALE, pz), Vector3(0.92, 0.40, 0.56) * V_SCALE, _mat_wood_dark)
		_spawn_ext_prop(group, "res://assets/nature/Flower_3_Group.gltf", Vector3(px - 0.18 * V_SCALE, py + 0.40 * V_SCALE, pz), poff.x, Vector3.ONE * (0.78 * V_SCALE), false)
		_spawn_ext_prop(group, "res://assets/nature/Flower_4_Group.gltf", Vector3(px + 0.18 * V_SCALE, py + 0.40 * V_SCALE, pz), poff.y, Vector3.ONE * (0.78 * V_SCALE), false)


func _build_plaza_bunting(root: Node3D, terrain: Node3D, plaza_top_y: float) -> void:
	var holder := Node3D.new()
	holder.name = "PlazaBunting"
	root.add_child(holder)

	var spans := [
		[Vector2(-7.6, -8.6), Vector2(-3.6, -3.6)],
		[Vector2( 7.6, -8.6), Vector2( 3.6, -3.6)],
		[Vector2(-7.6,  8.6), Vector2(-3.6,  3.6)],
		[Vector2( 7.6,  8.6), Vector2( 3.6,  3.6)],
		[Vector2(-8.2, -6.6), Vector2(-8.2, -2.8)],
		[Vector2( 8.2, -6.6), Vector2( 8.2, -2.8)],
		[Vector2(-8.2,  2.8), Vector2(-8.2,  6.6)],
		[Vector2( 8.2,  2.8), Vector2( 8.2,  6.6)],
	]
	var flag_mats := [
		_get_color_mat("bunting_red", Color(0.84, 0.24, 0.20), 0.90),
		_get_color_mat("bunting_gold", Color(0.94, 0.74, 0.24), 0.90),
		_get_color_mat("bunting_blue", Color(0.24, 0.46, 0.78), 0.90),
		_get_color_mat("bunting_green", Color(0.28, 0.62, 0.34), 0.90),
	]
	var cord_mat := _get_color_mat("bunting_cord", Color(0.32, 0.24, 0.16), 0.92)
	var base_y := maxf(_sample_h(terrain, VILLAGE_CENTER.x, VILLAGE_CENTER.z), plaza_top_y)

	for s_idx in range(spans.size()):
		var a2: Vector2 = Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z) + (spans[s_idx][0] as Vector2) * V_SCALE
		var b2: Vector2 = Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z) + (spans[s_idx][1] as Vector2) * V_SCALE
		var ha: float = maxf(_sample_h(terrain, a2.x, a2.y), base_y) + 3.85 * V_SCALE
		var hb: float = maxf(_sample_h(terrain, b2.x, b2.y), base_y) + 3.85 * V_SCALE
		var dvec := b2 - a2
		var len2 := dvec.length()
		var yaw := atan2(dvec.x, dvec.y)
		var n_flags := maxi(5, int(round(len2 / (0.62 * V_SCALE))))
		for fi in range(n_flags):
			var t := (float(fi) + 0.5) / float(n_flags)
			var p2 := a2.lerp(b2, t)
			var sag := 4.0 * t * (1.0 - t) * 0.45 * V_SCALE
			var py := lerpf(ha, hb, t) - sag
			var fmat: Material = flag_mats[(fi + s_idx) % flag_mats.size()]
			var pennant := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.04, 0.34, 0.36) * V_SCALE
			pennant.mesh = pm
			pennant.material_override = fmat
			pennant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pennant.position = Vector3(p2.x, py - 0.16 * V_SCALE, p2.y)
			pennant.rotation = Vector3(PI, yaw, 0.0)
			holder.add_child(pennant)
		# Thin taut rope cord segment at midpoint
		var mid2 := (a2 + b2) * 0.5
		var cord := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.03 * V_SCALE, 0.03 * V_SCALE, len2)
		cord.mesh = cm
		cord.material_override = cord_mat
		cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cord.position = Vector3(mid2.x, (ha + hb) * 0.5 - 0.22 * V_SCALE, mid2.y)
		cord.rotation = Vector3(0.0, yaw, 0.0)
		holder.add_child(cord)


func _build_plaza_ambiance(root: Node3D, plaza_y: float) -> void:
	# Gentle sunlit pollen/blossom motes floating above Grand Market Square
	var motes := GPUParticles3D.new()
	motes.name = "PlazaBlossomMotes"
	motes.position = Vector3(VILLAGE_CENTER.x, plaza_y + 2.4 * V_SCALE, VILLAGE_CENTER.z)
	motes.amount = 24
	motes.lifetime = 4.6
	motes.preprocess = 2.0
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.visibility_range_end = 70.0
	motes.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(13.0, 1.8, 13.0) * V_SCALE
	pmat.direction = Vector3(0.45, 0.18, 0.25)
	pmat.spread = 45.0
	pmat.initial_velocity_min = 0.25
	pmat.initial_velocity_max = 0.65
	pmat.gravity = Vector3(0.04, -0.04, 0.02)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.94, 0.72, 0.0),
		Color(1.0, 0.94, 0.72, 0.72),
		Color(1.0, 0.86, 0.76, 0.65),
		Color(1.0, 0.86, 0.76, 0.0),
	])
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	pmat.color_ramp = gtex
	motes.process_material = pmat

	var q := QuadMesh.new()
	q.size = Vector2(0.065, 0.065)
	var qmat := StandardMaterial3D.new()
	if _smoke_mesh != null and _smoke_mesh.material is StandardMaterial3D:
		qmat.albedo_texture = (_smoke_mesh.material as StandardMaterial3D).albedo_texture
	qmat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	qmat.roughness = 0.92
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.billboard_keep_scale = true
	qmat.vertex_color_use_as_albedo = true
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = qmat
	motes.draw_pass_1 = q
	root.add_child(motes)


func _normalize_glb_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var dup := mi.mesh.duplicate() as Mesh
			for si in range(dup.get_surface_count()):
				var smat := dup.surface_get_material(si)
				if smat != null:
					dup.surface_set_material(si, _normalize_matte_material(smat))
			mi.mesh = dup
	for ch in node.get_children():
		_normalize_glb_materials(ch)


func _spawn_glb_scene(parent: Node3D, res_path: String, pos: Vector3, rot_y: float = 0.0, rot_euler: Vector3 = Vector3.INF, scale_vec: Vector3 = Vector3.ONE) -> Node3D:
	var ps := load(res_path) as PackedScene
	if ps == null:
		push_error("VillageBuilder: failed to load glb scene: " + res_path)
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	_normalize_glb_materials(inst)
	inst.position = pos
	if rot_euler != Vector3.INF:
		inst.rotation = rot_euler
	else:
		inst.rotation = Vector3(0.0, rot_y, 0.0)
	if scale_vec != Vector3.ONE:
		inst.scale = scale_vec
	parent.add_child(inst)
	return inst


func _build_road_ribbon_mesh(left_pts: Array[Vector3], right_pts: Array[Vector3], uv_step: float, skirt_drop: float) -> ArrayMesh:
	var n_seg: int = left_pts.size() - 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Pass 1: Dedicated top surface strip so road normals stay purely upward without skirt tilt
	for si in range(n_seg + 1):
		var u_dist := float(si) * uv_step
		st.set_uv(Vector2(0.15, u_dist))
		st.add_vertex(left_pts[si])
		st.set_uv(Vector2(0.85, u_dist))
		st.add_vertex(right_pts[si])
	for si in range(n_seg):
		var b0 := si * 2
		var b1 := (si + 1) * 2
		st.add_index(b0)
		st.add_index(b1)
		st.add_index(b0 + 1)
		st.add_index(b0 + 1)
		st.add_index(b1)
		st.add_index(b1 + 1)

	# Pass 2: Left outward curb skirt (-r2 side)
	var drop_v := Vector3(0.0, skirt_drop, 0.0)
	var left_base := (n_seg + 1) * 2
	for si in range(n_seg + 1):
		var u_dist := float(si) * uv_step
		st.set_uv(Vector2(0.0, u_dist))
		st.add_vertex(left_pts[si])
		st.set_uv(Vector2(0.15, u_dist))
		st.add_vertex(left_pts[si] - drop_v)
	for si in range(n_seg):
		var b0 := left_base + si * 2
		var b1 := left_base + (si + 1) * 2
		st.add_index(b0)
		st.add_index(b0 + 1)
		st.add_index(b1 + 1)
		st.add_index(b0)
		st.add_index(b1 + 1)
		st.add_index(b1)

	# Pass 3: Right outward curb skirt (+r2 side)
	var right_base := left_base + (n_seg + 1) * 2
	for si in range(n_seg + 1):
		var u_dist := float(si) * uv_step
		st.set_uv(Vector2(0.85, u_dist))
		st.add_vertex(right_pts[si])
		st.set_uv(Vector2(1.0, u_dist))
		st.add_vertex(right_pts[si] - drop_v)
	for si in range(n_seg):
		var b0 := right_base + si * 2
		var b1 := right_base + (si + 1) * 2
		st.add_index(b1)
		st.add_index(b1 + 1)
		st.add_index(b0 + 1)
		st.add_index(b1)
		st.add_index(b0 + 1)
		st.add_index(b0)

	st.generate_normals()
	return st.commit()


func _override_glb_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var dup := mi.mesh.duplicate() as Mesh
			for si in range(dup.get_surface_count()):
				dup.surface_set_material(si, mat)
			mi.mesh = dup
	for ch in node.get_children():
		_override_glb_material(ch, mat)


func _build_fishing_dock(root: Node3D, colliders: StaticBody3D, terrain: Node3D) -> void:
	var v_xz := Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z)
	var shore_guess := v_xz + v_xz.normalized() * 257.0
	var eps := 18.0
	var hL := _sample_h(terrain, shore_guess.x - eps, shore_guess.y)
	var hR := _sample_h(terrain, shore_guess.x + eps, shore_guess.y)
	var hU := _sample_h(terrain, shore_guess.x, shore_guess.y - eps)
	var hD := _sample_h(terrain, shore_guess.x, shore_guess.y + eps)
	var sea_normal := Vector2(hL - hR, hU - hD)
	if sea_normal.length_squared() < 0.0001:
		sea_normal = v_xz.normalized()
	else:
		sea_normal = sea_normal.normalized()

	# Step along sea_normal to find the exact 0.0m shoreline crossing
	var shore_xy := shore_guess
	for step_i in range(56):
		var cand := shore_guess - sea_normal * 40.0 + sea_normal * (float(step_i) * 2.0)
		if _sample_h(terrain, cand.x, cand.y) <= 0.0:
			shore_xy = cand
			break

	var dock_yaw := atan2(sea_normal.x, sea_normal.y)
	var tangent := Vector2(-sea_normal.y, sea_normal.x)
	_dock_shore_xy = shore_xy
	_dock_yaw = dock_yaw

	var dock := Node3D.new()
	dock.name = "FishingDock"
	dock.position = Vector3(shore_xy.x, 0.0, shore_xy.y)
	dock.rotation.y = dock_yaw
	root.add_child(dock)

	var d_basis := Basis(Vector3.UP, dock_yaw)
	var fdir := "res://assets/fishing/"

	# 0a. Fisherman's Cottage on the upper sandy coastal rise beside the pier approach
	var cottage_xy := shore_xy - sea_normal * 44.0 + tangent * 12.0
	_dock_cottage_xy = cottage_xy
	_build_house(root, colliders, terrain, {
		"name": "FishermanCottage",
		"offset": cottage_xy - v_xz,
		"unscaled_offset": true,
		"w": 4,
		"d": 6,
		"stories": 1,
		"style": "plaster",
		"roof": "slate",
		"yaw": dock_yaw + PI * 0.45,
		"is_tower": false,
		"open_door": true,
		"civic": false,
	})

	# Cottage coastal porch barrels, crates, chest, oar, and rustic fence
	var cot_yaw := dock_yaw + PI * 0.45
	var cot_basis := Basis(Vector3.UP, cot_yaw)
	var cot_side_a := cottage_xy + tangent * (-2.6 * V_SCALE) + sea_normal * (-1.4 * V_SCALE)
	var cot_side_ay := _sample_h(terrain, cot_side_a.x, cot_side_a.y)
	_spawn_glb_scene(root, fdir + "barrel.glb", Vector3(cot_side_a.x, cot_side_ay, cot_side_a.y), cot_yaw + 0.3, Vector3.INF, Vector3.ONE * V_SCALE)
	_spawn_glb_scene(root, fdir + "crate.glb", Vector3(cot_side_a.x + sea_normal.x * (1.15 * V_SCALE), cot_side_ay, cot_side_a.y + sea_normal.y * (1.15 * V_SCALE)), cot_yaw - 0.2, Vector3.INF, Vector3.ONE * V_SCALE)
	_spawn_glb_scene(root, fdir + "tool-paddle.glb", Vector3(cot_side_a.x - sea_normal.x * (0.85 * V_SCALE), cot_side_ay + 0.08, cot_side_a.y - sea_normal.y * (0.85 * V_SCALE)), 0.0, Vector3(0.25, cot_yaw, 0.12), Vector3.ONE * V_SCALE)
	_add_box_collider(colliders, Transform3D(cot_basis, Vector3(cot_side_a.x, cot_side_ay + 0.55 * V_SCALE, cot_side_a.y)), Vector3(2.2, 1.1, 1.4) * V_SCALE)

	# Rustic terrain-following timber rail framing the seaward side of Fisherman's Cottage
	var fence_pts: Array[Vector3] = []
	for fi in range(-2, 3):
		var fp2 := cottage_xy + sea_normal * (4.2 * V_SCALE) + tangent * (float(fi) * 2.2 * V_SCALE)
		var fy := _sample_h(terrain, fp2.x, fp2.y)
		fence_pts.append(Vector3(fp2.x, fy, fp2.y))
		_add_box_visual(root, "CottageFencePost_%d" % fi, Vector3(fp2.x, fy + 0.64, fp2.y), Vector3(0.20, 1.48, 0.20), _mat_wood_dark)
		_add_cylinder_collider(colliders, Vector3(fp2.x, fy + 0.64, fp2.y), 0.18, 1.48)
	for si_f in range(fence_pts.size() - 1):
		var a := fence_pts[si_f]
		var b := fence_pts[si_f + 1]
		var mid := (a + b) * 0.5
		var dvec := b - a
		var dlen := dvec.length()
		var ry_yaw := atan2(dvec.x, dvec.z)
		var rx_pitch := -atan2(dvec.y, maxf(Vector2(dvec.x, dvec.z).length(), 0.01))
		_add_box_visual(root, "CottageFenceRailHi_%d" % si_f, mid + Vector3(0.0, 1.08, 0.0), Vector3(0.12, 0.12, dlen), _mat_wood_dark, Vector3(rx_pitch, ry_yaw, 0.0))
		_add_box_visual(root, "CottageFenceRailLo_%d" % si_f, mid + Vector3(0.0, 0.62, 0.0), Vector3(0.12, 0.12, dlen), _mat_wood_dark, Vector3(rx_pitch, ry_yaw, 0.0))

	# 0b. Terrain-draped Cobble Pathway from Village South Gatehouse aligned straight onto the Harbor Wharf
	var gate_xy := Vector2(VILLAGE_CENTER.x, VILLAGE_CENTER.z + 55.0 * V_SCALE)
	var entry_w := dock.position + d_basis * Vector3(0.0, 0.0, -10.35)
	var entry_xy := Vector2(entry_w.x, entry_w.z)
	var ctrl_xy := entry_xy - sea_normal * 64.0

	var path_pts: Array[Vector3] = []
	var path_dirs: Array[Vector2] = []
	var n_seg := 48
	for si in range(n_seg + 1):
		var t := float(si) / float(n_seg)
		var omt := 1.0 - t
		var p2 := omt * omt * gate_xy + 2.0 * omt * t * ctrl_xy + t * t * entry_xy
		var dp := 2.0 * omt * (ctrl_xy - gate_xy) + 2.0 * t * (entry_xy - ctrl_xy)
		if dp.length_squared() < 0.0001:
			dp = entry_xy - gate_xy
		var py := _sample_h(terrain, p2.x, p2.y)
		path_pts.append(Vector3(p2.x, py, p2.y))
		path_dirs.append(dp.normalized())

	var half_w := 1.75
	var y_lift := 0.09
	var p_left: Array[Vector3] = []
	var p_right: Array[Vector3] = []
	for si in range(n_seg + 1):
		var p := path_pts[si]
		var f2 := path_dirs[si]
		var r2 := Vector2(-f2.y, f2.x)
		var lx := p.x - r2.x * half_w
		var lz := p.z - r2.y * half_w
		var rx := p.x + r2.x * half_w
		var rz := p.z + r2.y * half_w
		p_left.append(Vector3(lx, _sample_h(terrain, lx, lz) + y_lift, lz))
		p_right.append(Vector3(rx, _sample_h(terrain, rx, rz) + y_lift, rz))

	var path_mi := MeshInstance3D.new()
	path_mi.name = "PierPathway"
	path_mi.mesh = _build_road_ribbon_mesh(p_left, p_right, 1.2, 0.55)
	path_mi.material_override = _mat_cobble
	path_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(path_mi)

	# Roadside wooden lantern posts along the pier pathway (emissive glow without excess OmniLights)
	for li in [6, 14, 22, 30, 38, 44]:
		var lp := path_pts[li]
		var ld := path_dirs[li]
		var lr := Vector2(-ld.y, ld.x)
		var side := 1.0 if (li % 16 != 6) else -1.0
		var post_xz := Vector2(lp.x, lp.z) + lr * (side * 2.35)
		var post_y := _sample_h(terrain, post_xz.x, post_xz.y)
		var post_pos := Vector3(post_xz.x, post_y + 1.25, post_xz.y)
		_add_cylinder_visual(root, "PierPathLantern_%d" % li, post_pos, 0.08, 0.11, 2.70, _mat_dock_oak)
		_add_cylinder_collider(colliders, post_pos, 0.15, 2.70)
		var sconce_yaw := atan2(-lr.x * side, -lr.y * side)
		var sconce_pos := Vector3(post_xz.x - lr.x * side * 0.12, post_y + 2.35, post_xz.y - lr.y * side * 0.12)
		_spawn_wall_sconce(root, sconce_pos, sconce_yaw, false)

	# Cottage cobble doorway spur connecting PierPathway up to Fisherman's Cottage front
	var spur_start := path_pts[n_seg - 8]
	var spur_start_xz := Vector2(spur_start.x, spur_start.z)
	var spur_end_xz := cottage_xy - tangent * (3.8 * V_SCALE)
	var spur_segs := 6
	var f_spur := (spur_end_xz - spur_start_xz).normalized()
	var r_spur := Vector2(-f_spur.y, f_spur.x)
	var s_left: Array[Vector3] = []
	var s_right: Array[Vector3] = []
	for si in range(spur_segs + 1):
		var t := float(si) / float(spur_segs)
		var p2 := spur_start_xz.lerp(spur_end_xz, t)
		var hw := 1.05
		var lx := p2.x - r_spur.x * hw
		var lz := p2.y - r_spur.y * hw
		var rx := p2.x + r_spur.x * hw
		var rz := p2.y + r_spur.y * hw
		s_left.append(Vector3(lx, _sample_h(terrain, lx, lz) + 0.08, lz))
		s_right.append(Vector3(rx, _sample_h(terrain, rx, rz) + 0.08, rz))
	var spur_mi := MeshInstance3D.new()
	spur_mi.name = "CottageCobbleSpur"
	spur_mi.mesh = _build_road_ribbon_mesh(s_left, s_right, 1.1, 0.45)
	spur_mi.material_override = _mat_cobble
	spur_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spur_mi)

	# 1. Flush Timber Entry Threshold Apron (solid twin platform.glb bays + oak curb sill sealing PierPathway -> Wharf)
	var wharf_base_y := 0.80
	var wharf_top_y := wharf_base_y + 0.928  # 1.728 m
	var pier_base_y := 0.34
	var pier_top_y := pier_base_y + 1.3123   # 1.6523 m

	for ap_x: float in [-0.90, 0.90]:
		_spawn_glb_scene(dock, fdir + "platform.glb", Vector3(ap_x, wharf_top_y - 0.218, -9.60), 0.0, Vector3(-0.015, 0.0, 0.0), Vector3(0.74, 1.0, 0.92))
	_add_box_visual(dock, "WharfThresholdSill", Vector3(0.0, wharf_top_y - 0.05, -10.68), Vector3(3.86, 0.16, 0.24), _mat_dock_oak)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(0.0, wharf_top_y - 0.19, -9.60)), Vector3(3.75, 0.38, 2.40))
	for side_s: float in [-1.0, 1.0]:
		_add_cylinder_visual(dock, "WharfEntryPost", Vector3(side_s * 1.96, wharf_top_y + 1.15, -10.55), 0.10, 0.13, 2.75, _mat_dock_oak)
		_add_rope_ring_visual(dock, "WharfEntryRope", Vector3(side_s * 1.96, wharf_top_y + 0.52, -10.55), 0.10, 0.15, _mat_rope)
		_spawn_wall_sconce(dock, Vector3(side_s * 1.82, wharf_top_y + 2.28, -10.55), -side_s * PI * 0.5, side_s < 0.0)
		_add_cylinder_collider(colliders, dock.position + d_basis * Vector3(side_s * 1.96, wharf_top_y + 1.15, -10.55), 0.16, 2.75)

	# 2. Broad Wharf Plaza & Covered Fish-Market Stall (7.5m x 5.0m at z = -8.5..-3.5, top y=1.728)
	for wx_off in [-2.50, 0.0, 2.50]:
		for wz_off in [-7.25, -4.75]:
			_spawn_glb_scene(dock, fdir + "structure-platform.glb", Vector3(float(wx_off), wharf_base_y, float(wz_off)))
	for px in [-3.62, -1.25, 1.25, 3.62]:
		for pz in [-8.35, -6.00, -3.65]:
			_add_cylinder_visual(dock, "WharfOakPiling", Vector3(float(px), -0.40, float(pz)), 0.13, 0.16, 4.18, _mat_dock_oak)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(0.0, wharf_top_y - 0.22, -6.00)), Vector3(7.55, 0.44, 5.05))

	# West Wharf Fish-Market Stall (slanted warm cloth canopy on timber posts so Pier-Head Pavilion remains unique)
	var mat_stall_awning := _make_matte_mat(Color(0.58, 0.23, 0.19), 0.92)
	var mat_awning_trim := _make_matte_mat(Color(0.84, 0.76, 0.58), 0.92)
	for sx_p in [-3.35, -1.65]:
		for sz_p in [-7.45, -4.55]:
			var sp_h := 3.35 if sx_p < -2.5 else 3.00
			_add_cylinder_visual(dock, "WharfStallPost", Vector3(sx_p, wharf_top_y + sp_h * 0.5, sz_p), 0.08, 0.09, sp_h, _mat_dock_oak)
	_add_box_visual(dock, "WharfStallCanopy", Vector3(-2.45, wharf_top_y + 3.18, -6.00), Vector3(2.25, 0.09, 3.35), mat_stall_awning, Vector3(0.0, 0.0, -0.18))
	_add_box_visual(dock, "WharfStallValance", Vector3(-1.38, wharf_top_y + 2.92, -6.00), Vector3(0.06, 0.18, 3.32), mat_awning_trim)
	_add_box_visual(dock, "WharfStallCounter", Vector3(-2.05, wharf_top_y + 0.54, -6.00), Vector3(0.76, 1.08, 2.30), _mat_wood_trim)
	_spawn_wall_sconce(dock, Vector3(-1.58, wharf_top_y + 2.55, -6.00), PI * 0.5, true)
	_spawn_glb_scene(dock, fdir + "chest.glb", Vector3(-2.95, wharf_top_y + 0.02, -7.25), 0.35, Vector3.INF, Vector3.ONE * 1.08)
	_spawn_glb_scene(dock, fdir + "barrel.glb", Vector3(-3.00, wharf_top_y + 0.02, -5.95), 1.4, Vector3.INF, Vector3.ONE * 1.06)
	_spawn_glb_scene(dock, fdir + "crate.glb", Vector3(-2.85, wharf_top_y + 0.02, -4.85), -0.25, Vector3.INF, Vector3.ONE * 1.08)
	_spawn_glb_scene(dock, fdir + "tool-paddle.glb", Vector3(-2.20, wharf_top_y + 0.02, -7.35), 0.0, Vector3(0.22, 0.40, 0.14), Vector3.ONE * 1.25)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(-2.55, wharf_top_y + 0.62, -6.02)), Vector3(1.95, 1.25, 3.25))

	# East Wharf Cargo Cluster & Harbor Mooring Railings framing Main Pier entrance
	_spawn_glb_scene(dock, fdir + "barrel.glb", Vector3(2.85, wharf_top_y + 0.02, -7.05), 0.7, Vector3.INF, Vector3.ONE * 1.10)
	_spawn_glb_scene(dock, fdir + "crate-bottles.glb", Vector3(2.85, wharf_top_y + 0.02, -5.75), -0.45, Vector3.INF, Vector3.ONE * 1.08)
	_spawn_glb_scene(dock, fdir + "crate.glb", Vector3(2.20, wharf_top_y + 0.02, -4.55), 0.20, Vector3.INF, Vector3.ONE * 1.05)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(2.70, wharf_top_y + 0.46, -5.90)), Vector3(1.45, 0.95, 3.15))

	# Wharf perimeter mooring posts & hemp-rope guard spans (center 2.5m pier entry left clear)
	var wharf_rail_segments: Array[Array] = [
		[Vector2(-3.62, -8.35), Vector2(-3.62, -3.65)],
		[Vector2(-3.62, -3.65), Vector2(-1.25, -3.65)],
		[Vector2( 3.62, -8.35), Vector2( 3.62, -3.65)],
		[Vector2( 3.62, -3.65), Vector2( 1.25, -3.65)],
	]
	for rseg in wharf_rail_segments:
		var a2: Vector2 = rseg[0]
		var b2: Vector2 = rseg[1]
		for pt2 in [a2, b2]:
			_add_cylinder_visual(dock, "WharfGuardPost", Vector3(pt2.x, wharf_top_y + 0.46, pt2.y), 0.09, 0.11, 0.96, _mat_dock_oak)
			_add_rope_ring_visual(dock, "WharfGuardRopeWrap", Vector3(pt2.x, wharf_top_y + 0.80, pt2.y), 0.09, 0.13, _mat_rope)
		_spawn_rope_span(dock, "WharfRopeTop", Vector3(a2.x, wharf_top_y + 0.82, a2.y), Vector3(b2.x, wharf_top_y + 0.82, b2.y), 0.036, _mat_rope)
		_spawn_rope_span(dock, "WharfRopeMid", Vector3(a2.x, wharf_top_y + 0.46, a2.y), Vector3(b2.x, wharf_top_y + 0.46, b2.y), 0.030, _mat_rope)

	# 3. Main Stepped Timber Pier Spine extending over cove water (z = -3.5..16.5, top y=1.652)
	# Uses flat structure-platform.glb decks (no protruding interior tile bollards) carried on deep oak bents.
	var pier_deck_base_y := pier_top_y - 0.928 # 0.7243 m
	var pier_zs: Array[float] = [-2.25, 0.25, 2.75, 5.25, 7.75, 10.25, 12.75, 15.25]
	for pz in pier_zs:
		_spawn_glb_scene(dock, fdir + "structure-platform.glb", Vector3(0.0, pier_deck_base_y, pz))
	var spine_bents: Array[float] = [-3.50, -1.00, 1.50, 4.00, 6.50, 9.00, 11.50, 14.00, 16.50]
	for bz_idx in range(spine_bents.size()):
		var bz: float = spine_bents[bz_idx]
		# Cross-brace girder connecting each bent below deck height
		_spawn_rope_span(dock, "PierBentBrace", Vector3(-1.14, 0.48, bz), Vector3(1.14, 0.48, bz), 0.065, _mat_dock_oak)
		for px_p: float in [-1.14, 1.14]:
			var at_wharf_seam: bool = bz < -3.0
			var at_head_seam: bool = bz > 16.0
			var at_east_gangway: bool = px_p > 0.0 and bz > 3.1 and bz < 5.5
			var at_west_slip: bool = px_p < 0.0 and bz > 9.8 and bz < 13.0
			var under_only: bool = at_wharf_seam or at_head_seam or at_east_gangway or at_west_slip
			var is_tall_bollard: bool = (not under_only) and (bz_idx == 2 or bz_idx == 4 or bz_idx == 7)
			var post_top := pier_top_y - 0.12 if under_only else pier_top_y + (1.06 if is_tall_bollard else 0.88)
			var post_bot := -4.20
			_add_cylinder_visual(dock, "PierOakPiling", Vector3(px_p, (post_top + post_bot) * 0.5, bz), 0.11, 0.15, post_top - post_bot, _mat_dock_oak)
			if not under_only:
				_add_rope_ring_visual(dock, "PierPostRopeTop", Vector3(px_p, pier_top_y + 0.74, bz), 0.11, 0.15, _mat_rope)
				if is_tall_bollard:
					_add_rope_ring_visual(dock, "PierPostRopeLow", Vector3(px_p, pier_top_y + 0.36, bz), 0.12, 0.17, _mat_rope)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(0.0, pier_top_y - 0.19, 6.50)), Vector3(2.50, 0.38, 20.10))

	# Dedicated gate posts strictly at East Finger Gangway & West Boat-Slip openings (no overlap with bents)
	for gp: Vector2 in [Vector2(1.14, 3.10), Vector2(1.14, 5.45), Vector2(-1.14, 9.80), Vector2(-1.14, 13.00)]:
		_add_cylinder_visual(dock, "PierOpeningPost", Vector3(gp.x, pier_top_y + 0.44, gp.y), 0.09, 0.11, 0.90, _mat_dock_oak)
		_add_rope_ring_visual(dock, "PierOpeningRope", Vector3(gp.x, pier_top_y + 0.74, gp.y), 0.09, 0.13, _mat_rope)

	# Continuous hemp-rope guard rails along open pier sides connecting existing Wharf & PierHead boundary posts
	var pier_rail_segments: Array[Array] = [
		[Vector2(-1.20, -3.65), Vector2(-1.14, -1.00)],
		[Vector2(-1.14, -1.00), Vector2(-1.14,  9.80)],
		[Vector2(-1.14, 13.00), Vector2(-1.25, 16.65)],
		[Vector2( 1.20, -3.65), Vector2( 1.14, -1.00)],
		[Vector2( 1.14, -1.00), Vector2( 1.14,  3.10)],
		[Vector2( 1.14,  5.45), Vector2( 1.25, 16.65)],
	]
	for pseg in pier_rail_segments:
		var pa: Vector2 = pseg[0]
		var pb: Vector2 = pseg[1]
		_spawn_rope_span(dock, "PierRopeTop", Vector3(pa.x, pier_top_y + 0.76, pa.y), Vector3(pb.x, pier_top_y + 0.76, pb.y), 0.032, _mat_rope)
		_spawn_rope_span(dock, "PierRopeMid", Vector3(pa.x, pier_top_y + 0.42, pa.y), Vector3(pb.x, pier_top_y + 0.42, pb.y), 0.025, _mat_rope)

	# 3b. Tiered East Boat-Slip Gangway Ramp & Low-Water Finger Landing (top y = 0.65m)
	var low_top_y := 0.65
	_spawn_glb_scene(dock, fdir + "platform-planks.glb", Vector3(2.05, 0.90, 4.25), 0.0, Vector3(0.37, PI * 0.5, 0.0), Vector3(0.90, 1.0, 1.05))
	_add_box_collider(colliders, Transform3D(d_basis * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, 0.37), dock.position + d_basis * Vector3(2.05, 1.06, 4.25)), Vector3(1.85, 0.34, 2.75))

	for lz in [4.25, 6.75, 9.25]:
		_spawn_glb_scene(dock, fdir + "platform.glb", Vector3(3.85, low_top_y - 0.228, lz))
	for lpx in [2.72, 4.98]:
		for lpz in [3.15, 6.75, 10.35]:
			_add_cylinder_visual(dock, "FingerDockPiling", Vector3(lpx, (low_top_y + 0.62 - 3.80) * 0.5, lpz), 0.11, 0.14, low_top_y + 4.42, _mat_dock_oak)
			_add_rope_ring_visual(dock, "FingerDockRope", Vector3(lpx, low_top_y + 0.38, lpz), 0.11, 0.16, _mat_rope)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(3.85, low_top_y - 0.14, 6.75)), Vector3(2.50, 0.28, 7.60))
	_spawn_glb_scene(dock, fdir + "crate.glb", Vector3(4.35, low_top_y, 9.55), -0.35, Vector3.INF, Vector3.ONE * 0.72)
	_spawn_glb_scene(dock, fdir + "barrel.glb", Vector3(3.35, low_top_y, 9.65), 1.15, Vector3.INF, Vector3.ONE * 0.70)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(3.85, low_top_y + 0.42, 9.60)), Vector3(1.85, 0.90, 1.25))

	# 4. Asymmetrical Harbor Pier-Head Plaza (3x2 flat structure-platform.glb bays = 7.5m x 5.0m at z = 16.5..21.5, top y=1.652)
	for tx in [-2.50, 0.0, 2.50]:
		for tz in [17.75, 20.25]:
			_spawn_glb_scene(dock, fdir + "structure-platform.glb", Vector3(float(tx), pier_deck_base_y, float(tz)))
	for tx_p: float in [-3.62, -1.25, 1.25, 3.62]:
		for tz_p: float in [16.65, 19.00, 21.35]:
			var is_interior: bool = absf(tx_p) < 2.0 and tz_p > 17.0 and tz_p < 20.5
			var is_outer_corner: bool = absf(tx_p) > 3.0 and tz_p > 20.5
			var head_bot := -4.50
			if is_interior:
				var under_top := pier_top_y - 0.14
				_add_cylinder_visual(dock, "PierHeadUnderPiling", Vector3(tx_p, (under_top + head_bot) * 0.5, tz_p), 0.12, 0.16, under_top - head_bot, _mat_dock_oak)
			else:
				var post_top := pier_top_y + (1.16 if is_outer_corner else 0.92)
				_add_cylinder_visual(dock, "PierHeadOakPiling", Vector3(tx_p, (post_top + head_bot) * 0.5, tz_p), 0.12, 0.16, post_top - head_bot, _mat_dock_oak)
				_add_rope_ring_visual(dock, "PierHeadPostRope", Vector3(tx_p, pier_top_y + 0.76, tz_p), 0.12, 0.16, _mat_rope)
				if is_outer_corner:
					_add_rope_ring_visual(dock, "PierHeadBollardRope", Vector3(tx_p, pier_top_y + 0.40, tz_p), 0.13, 0.18, _mat_rope)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(0.0, pier_top_y - 0.19, 19.00)), Vector3(7.55, 0.38, 5.05))

	# West Harbormaster Watch Canopy & Tally Desk (single-story open timber gable pavilion echoing village slate roofs)
	var mat_pier_slate := _make_matte_mat(Color(0.25, 0.28, 0.33), 0.90)
	var pav_x := -2.25
	var pav_z := 18.95
	var pav_post_h := 3.22
	for px_o: float in [-1.05, 1.05]:
		for pz_o: float in [-1.20, 1.20]:
			var p_pos := Vector3(pav_x + px_o, pier_top_y + pav_post_h * 0.5, pav_z + pz_o)
			_add_cylinder_visual(dock, "HarborPavilionPost", p_pos, 0.095, 0.12, pav_post_h, _mat_dock_oak)
			_add_box_visual(dock, "HarborPavilionPlinth", Vector3(pav_x + px_o, pier_top_y + 0.11, pav_z + pz_o), Vector3(0.30, 0.22, 0.30), _mat_stone_foundation)
			# Subtle diagonal knee brace along roof eaves
			var brace_in := -px_o * 0.45
			_spawn_rope_span(dock, "HarborPavilionBrace", Vector3(pav_x + px_o, pier_top_y + 2.52, pav_z + pz_o), Vector3(pav_x + px_o + brace_in, pier_top_y + 3.14, pav_z + pz_o), 0.06, _mat_dock_oak)
		# Wall-plate beam along Z
		_add_box_visual(dock, "HarborPavilionEave", Vector3(pav_x + px_o, pier_top_y + 3.20, pav_z), Vector3(0.18, 0.18, 2.75), _mat_dock_oak)
	# Pitched Slate Shingle Gable Roof (port & starboard slopes + ridge beam + overhang fascia)
	_add_box_visual(dock, "HarborPavilionRoofW", Vector3(pav_x - 0.68, pier_top_y + 3.56, pav_z), Vector3(1.56, 0.12, 2.96), mat_pier_slate, Vector3(0.0, 0.0, 0.42))
	_add_box_visual(dock, "HarborPavilionRoofE", Vector3(pav_x + 0.68, pier_top_y + 3.56, pav_z), Vector3(1.56, 0.12, 2.96), mat_pier_slate, Vector3(0.0, 0.0, -0.42))
	_add_box_visual(dock, "HarborPavilionRidge", Vector3(pav_x, pier_top_y + 3.88, pav_z), Vector3(0.22, 0.20, 3.04), _mat_dock_oak)
	# Hanging Iron Lantern inside Canopy Ridge
	var pav_lamp := Vector3(pav_x, pier_top_y + 3.12, pav_z)
	_spawn_rope_span(dock, "PavilionLampChain", Vector3(pav_x, pier_top_y + 3.80, pav_z), pav_lamp + Vector3(0.0, 0.14, 0.0), 0.022, _mat_iron)
	_add_box_visual(dock, "PavilionLampCap", pav_lamp + Vector3(0.0, 0.12, 0.0), Vector3(0.24, 0.06, 0.24), _mat_iron)
	var pav_glow := _add_box_visual(dock, "PavilionLampGlow", pav_lamp, Vector3(0.16, 0.20, 0.16), _mat_lantern_glow)
	pav_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box_visual(dock, "PavilionLampBase", pav_lamp - Vector3(0.0, 0.12, 0.0), Vector3(0.20, 0.05, 0.20), _mat_iron)
	var pav_light := OmniLight3D.new()
	pav_light.position = pav_lamp
	pav_light.light_color = Color(1.0, 0.78, 0.44)
	pav_light.light_energy = 1.05
	pav_light.omni_range = 9.5
	pav_light.shadow_enabled = false
	pav_light.distance_fade_enabled = true
	pav_light.distance_fade_begin = 95.0
	pav_light.distance_fade_length = 30.0
	dock.add_child(pav_light)
	_register_night_light(pav_light, 1.05)
	# Grounded Harbormaster tally counter + cargo crates inside open canopy (West half, leaving East side walkable)
	_add_box_visual(dock, "HarborTallyDesk", Vector3(pav_x - 0.62, pier_top_y + 0.42, pav_z), Vector3(0.60, 0.84, 1.45), _mat_wood_trim)
	_spawn_glb_scene(dock, fdir + "chest.glb", Vector3(pav_x + 0.45, pier_top_y + 0.02, pav_z - 0.68), 0.25, Vector3.INF, Vector3.ONE * 0.72)
	_spawn_glb_scene(dock, fdir + "barrel.glb", Vector3(pav_x - 0.55, pier_top_y + 0.02, pav_z + 0.85), 0.90, Vector3.INF, Vector3.ONE * 0.72)
	_add_box_collider(colliders, Transform3D(d_basis, dock.position + d_basis * Vector3(pav_x - 0.58, pier_top_y + 0.48, pav_z)), Vector3(0.85, 0.96, 1.95))

	# East Harbor Beacon Crane cleanly seated inside southeast bay with iron cap & framed harbor lantern
	var crane_base := Vector3(2.65, pier_top_y, 20.05)
	_add_box_visual(dock, "HarborCranePlinth", crane_base + Vector3(0.0, 0.09, 0.0), Vector3(0.42, 0.18, 0.42), _mat_iron)
	_add_cylinder_visual(dock, "HarborCraneMast", crane_base + Vector3(0.0, 1.95, 0.0), 0.11, 0.15, 3.90, _mat_dock_oak)
	_add_box_visual(dock, "HarborCraneCap", crane_base + Vector3(0.0, 3.88, 0.0), Vector3(0.28, 0.10, 0.28), _mat_iron)
	_spawn_rope_span(dock, "HarborCraneBrace", crane_base + Vector3(0.0, 2.48, 0.0), crane_base + Vector3(0.54, 3.50, 0.62), 0.068, _mat_dock_oak)
	_spawn_rope_span(dock, "HarborCraneJib", crane_base + Vector3(0.0, 3.55, -0.10), crane_base + Vector3(0.98, 3.68, 1.28), 0.082, _mat_dock_oak)
	_add_rope_ring_visual(dock, "HarborCraneLash", crane_base + Vector3(0.0, 3.54, 0.0), 0.12, 0.18, _mat_rope)
	var beacon_tip := crane_base + Vector3(0.92, 3.64, 1.20)
	_add_box_visual(dock, "BeaconPulley", beacon_tip, Vector3(0.18, 0.16, 0.18), _mat_iron)
	_spawn_rope_span(dock, "BeaconHangRope", beacon_tip - Vector3(0.0, 0.06, 0.0), beacon_tip - Vector3(0.0, 0.64, 0.0), 0.022, _mat_rope)
	var beacon_pos := beacon_tip - Vector3(0.0, 0.76, 0.0)
	_add_box_visual(dock, "BeaconCap", beacon_pos + Vector3(0.0, 0.16, 0.0), Vector3(0.30, 0.07, 0.30), _mat_iron)
	for b_sx: float in [-0.11, 0.11]:
		for b_sz: float in [-0.11, 0.11]:
			_add_box_visual(dock, "BeaconStrut", beacon_pos + Vector3(b_sx, 0.0, b_sz), Vector3(0.035, 0.28, 0.035), _mat_iron)
	var b_glow := _add_box_visual(dock, "BeaconGlow", beacon_pos, Vector3(0.20, 0.24, 0.20), _mat_lantern_glow)
	b_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box_visual(dock, "BeaconBase", beacon_pos - Vector3(0.0, 0.16, 0.0), Vector3(0.26, 0.06, 0.26), _mat_iron)
	var beacon_light := OmniLight3D.new()
	beacon_light.position = beacon_pos
	beacon_light.light_color = Color(1.0, 0.78, 0.42)
	beacon_light.light_energy = 1.25
	beacon_light.omni_range = 12.0
	beacon_light.shadow_enabled = false
	beacon_light.distance_fade_enabled = true
	beacon_light.distance_fade_begin = 95.0
	beacon_light.distance_fade_length = 30.0
	dock.add_child(beacon_light)
	_register_night_light(beacon_light, 1.25)
	_spawn_glb_scene(dock, fdir + "crate-bottles.glb", Vector3(2.15, pier_top_y + 0.02, 19.35), 0.45, Vector3.INF, Vector3.ONE * 0.74)
	_spawn_glb_scene(dock, fdir + "barrel.glb", Vector3(2.85, pier_top_y + 0.02, 18.45), -0.8, Vector3.INF, Vector3.ONE * 0.76)

	# Continuous seaward & side hemp-rope railings connecting existing Pier-Head perimeter pilings (0 duplicate posts)
	var head_rail_segments: Array[Array] = [
		[Vector2(-1.25, 16.65), Vector2(-3.62, 16.65)],
		[Vector2(-3.62, 16.65), Vector2(-3.62, 21.35)],
		[Vector2(-3.62, 21.35), Vector2( 3.62, 21.35)],
		[Vector2( 3.62, 21.35), Vector2( 3.62, 16.65)],
		[Vector2( 3.62, 16.65), Vector2( 1.25, 16.65)],
	]
	for hseg in head_rail_segments:
		var ha: Vector2 = hseg[0]
		var hb: Vector2 = hseg[1]
		_spawn_rope_span(dock, "PierHeadRopeTop", Vector3(ha.x, pier_top_y + 0.76, ha.y), Vector3(hb.x, pier_top_y + 0.76, hb.y), 0.032, _mat_rope)
		_spawn_rope_span(dock, "PierHeadRopeMid", Vector3(ha.x, pier_top_y + 0.42, ha.y), Vector3(hb.x, pier_top_y + 0.42, hb.y), 0.026, _mat_rope)

	# 5. Moored Rowboats alongside East Low-Water Finger Slip & West Main Pier + Beached Skiff
	_spawn_glb_scene(dock, fdir + "boat-row-large.glb", Vector3(7.15, -0.14, 7.6), -0.08, Vector3.INF, Vector3.ONE * 1.35)
	_add_box_collider(colliders, Transform3D(d_basis * Basis(Vector3.UP, -0.08), dock.position + d_basis * Vector3(7.15, 0.28, 7.6)), Vector3(2.60, 0.72, 2.75) * 1.35)

	_spawn_glb_scene(dock, fdir + "boat-row-small.glb", Vector3(-3.35, -0.14, 11.4), 0.10, Vector3.INF, Vector3.ONE * 1.35)
	_add_box_collider(colliders, Transform3D(d_basis * Basis(Vector3.UP, 0.10), dock.position + d_basis * Vector3(-3.35, 0.28, 11.4)), Vector3(2.55, 0.72, 2.30) * 1.35)

	var beach_boat_w := dock.position + d_basis * Vector3(-8.2, 0.0, -6.2)
	var beach_boat_y := _sample_h(terrain, beach_boat_w.x, beach_boat_w.z) - 0.06
	_spawn_glb_scene(dock, fdir + "boat-row-small.glb", Vector3(-8.2, beach_boat_y, -6.2), 0.0, Vector3(0.08, 0.45, -0.06), Vector3.ONE * 1.35)
	_spawn_glb_scene(dock, fdir + "tool-paddle.glb", Vector3(-6.6, beach_boat_y + 0.15, -6.0), 0.0, Vector3(1.42, 0.65, 0.0), Vector3.ONE * 1.35)
	_add_box_collider(colliders, Transform3D(d_basis * Basis(Vector3.UP, 0.45), Vector3(beach_boat_w.x, beach_boat_y + 0.42, beach_boat_w.z)), Vector3(2.55, 0.72, 2.30) * 1.35)

	# 6. Coastal Sand Rocks & 3-Post Lashed Harbor Mooring Dolphins
	var cove_rocks: Array[Dictionary] = [
		{"off": Vector2(-12.5, -12.5), "glb": "rocks-sand-a.glb", "yaw": 0.4, "scale": 1.00},
		{"off": Vector2( 11.4, -13.2), "glb": "rocks-sand-b.glb", "yaw": 1.9, "scale": 1.05},
		{"off": Vector2( 14.5,  -7.5), "glb": "rocks-sand-c.glb", "yaw": 2.7, "scale": 0.90},
		{"off": Vector2(-15.5, -18.5), "glb": "rocks-sand-b.glb", "yaw": 1.1, "scale": 0.95},
		{"off": Vector2( 16.5, -24.5), "glb": "rocks-sand-a.glb", "yaw": 3.4, "scale": 1.10},
		{"off": Vector2(-21.0, -11.5), "glb": "rocks-sand-c.glb", "yaw": 2.1, "scale": 1.15},
	]
	for rk in cove_rocks:
		var roff: Vector2 = rk["off"]
		var rworld := dock.position + d_basis * Vector3(roff.x, 0.0, roff.y)
		var ry := _sample_h(terrain, rworld.x, rworld.z) - 0.55
		var rscale := Vector3.ONE * float(rk["scale"])
		var rinst := _spawn_glb_scene(dock, fdir + String(rk["glb"]), Vector3(roff.x, ry, roff.y), float(rk["yaw"]), Vector3.INF, rscale)
		if rinst != null:
			_override_glb_material(rinst, _mat_coastal_rock)
		_add_cylinder_collider(colliders, Vector3(rworld.x, ry + 1.2, rworld.z), 1.9 * float(rk["scale"]), 2.6)

	for dp in [Vector2(-4.4, 7.8), Vector2(8.3, 12.2), Vector2(-5.2, 15.8), Vector2(5.6, 22.4)]:
		_spawn_mooring_dolphin(dock, colliders, d_basis, dp, -4.40, 2.15)


## Lossless static draw-call batcher: merges static child MeshInstance3D surfaces
## per building (and 55m spatial cells for sprawling prop/lantern sets) grouped by
## (material_id, cast_shadow, vertex_format). Leaves colliders & OmniLight3Ds untouched.
func _batch_village_meshes(root: Node3D) -> void:
	for ch in root.get_children():
		if ch is StaticBody3D or ch.name in ["CobblestoneNetwork", "PierPathway", "CottageCobbleSpur"]:
			continue
		if ch is MeshInstance3D or not (ch is Node3D):
			continue
		var split_spatial := (ch.name == "TownProps" or ch.name == "StreetLanterns" or ch.name == "TownTrees")
		_batch_subtree(ch as Node3D, root, split_spatial)


func _batch_subtree(container: Node3D, root: Node3D, split_spatial: bool) -> void:
	var entries: Array[Dictionary] = []
	var stack: Array = [[container, container.transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var cur: Node = item[0]
		var cur_xf: Transform3D = item[1]
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.visible and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				entries.append({"mi": mi, "xf": cur_xf})
		for gc in cur.get_children():
			var next_xf := cur_xf * (gc as Node3D).transform if gc is Node3D else cur_xf
			stack.append([gc, next_xf])
	if entries.size() < 2:
		return

	# Buckets keyed by (spatial_cell, material_id, cast_shadow, surface_format)
	var buckets: Dictionary = {}
	var to_detach: Array[MeshInstance3D] = []
	for ent in entries:
		var mi: MeshInstance3D = ent["mi"]
		var rel_xform: Transform3D = ent["xf"]
		if rel_xform.basis.determinant() <= 1e-6:
			continue
		var m := mi.mesh
		var cell_tag := "0,0"
		var cell_origin := Vector3.ZERO
		if split_spatial:
			var p := rel_xform.origin
			var cx := int(floor(p.x / 52.0))
			var cz := int(floor(p.z / 52.0))
			cell_tag = "%d,%d" % [cx, cz]
			cell_origin = Vector3((float(cx) + 0.5) * 52.0, 0.0, (float(cz) + 0.5) * 52.0)
		var local_xform := Transform3D(Basis.IDENTITY, -cell_origin) * rel_xform if split_spatial else rel_xform
		var can_strip_all := true
		var is_arr := m is ArrayMesh
		for si in range(m.get_surface_count()):
			if is_arr and (m as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				can_strip_all = false
				continue
			var mat: Material = mi.material_override if mi.material_override != null else mi.get_active_material(si)
			var mat_key := "0"
			if mat != null:
				if (mat is StandardMaterial3D) and not _is_runtime_animated_mat(mat):
					mat_key = "s:" + _material_signature(mat as StandardMaterial3D)
				else:
					mat_key = "id:" + str(mat.get_instance_id())
			var fmt: int = int((m as ArrayMesh).surface_get_format(si)) if is_arr else -1
			var bkey := "%s|%s|%d|%d" % [cell_tag, mat_key, int(mi.cast_shadow), fmt]
			if not buckets.has(bkey):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				buckets[bkey] = {
					"cell": cell_tag,
					"cell_origin": cell_origin,
					"shadow": mi.cast_shadow,
					"mat": mat,
					"st": st,
				}
			(buckets[bkey]["st"] as SurfaceTool).append_from(m, si, local_xform)
		if can_strip_all:
			to_detach.append(mi)

	if buckets.is_empty():
		return

	# Group merged surfaces cleanly by (cell_tag, cast_shadow) so each building or cell
	# becomes only 1 MeshInstance3D per shadow mode!
	var cell_meshes: Dictionary = {}
	for bkey in buckets:
		var b: Dictionary = buckets[bkey]
		var ck := "%s|%d" % [b["cell"], int(b["shadow"])]
		if not cell_meshes.has(ck):
			cell_meshes[ck] = {"shadow": b["shadow"], "cell_origin": b["cell_origin"], "parts": []}
		(cell_meshes[ck]["parts"] as Array).append(b)

	var batch_holder := Node3D.new()
	batch_holder.name = container.name + "_Batched"
	root.add_child(batch_holder)
	for ck in cell_meshes:
		var cm: Dictionary = cell_meshes[ck]
		var arr_mesh := ArrayMesh.new()
		var parts: Array = cm["parts"]
		var surf_mats: Array[Material] = []
		for part in parts:
			var st := part["st"] as SurfaceTool
			arr_mesh = st.commit(arr_mesh)
			surf_mats.append(part["mat"] as Material)
		for si in range(surf_mats.size()):
			if surf_mats[si] != null:
				arr_mesh.surface_set_material(si, surf_mats[si])
		var out_mi := MeshInstance3D.new()
		out_mi.name = "Batch_" + ck.replace("|", "_")
		out_mi.position = cm["cell_origin"] as Vector3
		out_mi.mesh = arr_mesh
		out_mi.cast_shadow = int(cm["shadow"]) as GeometryInstance3D.ShadowCastingSetting
		if split_spatial:
			var aabb := arr_mesh.get_aabb()
			var half_diag := aabb.size.length() * 0.5
			var base_vis := 220.0 if container.name == "TownProps" else (240.0 if container.name == "StreetLanterns" else 260.0)
			out_mi.visibility_range_end = base_vis + half_diag
			out_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			out_mi.set_meta("base_vis_range", out_mi.visibility_range_end)
		batch_holder.add_child(out_mi)

	for i in range(to_detach.size() - 1, -1, -1):
		var mi := to_detach[i]
		mi.mesh = null
		if mi.get_child_count() == 0:
			var p := mi.get_parent()
			if p != null:
				p.remove_child(mi)
			mi.queue_free()
