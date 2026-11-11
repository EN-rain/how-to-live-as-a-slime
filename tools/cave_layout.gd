class_name CaveLayout
extends RefCounted
## Single source of truth for the redesigned cave layout (P0 -> P6).
## All positions are in cave-local coordinates Vector3(u, floor_y, s):
##   u = metres to the RIGHT of the mouth axis, s = metres INTO the mountain,
##   y = absolute world height of the walkable floor.
## Both the layout map renderer and the P1 SDF Marching-Cubes baker consume this exact data.

## World position of the mouth centre (offset left of the spawn sightline, nestled in a rocky hillside).
const ORIGIN := Vector3(-72.9, 26.0, -126.9)
## Unit vector INTO the mountain (NNW) and unit vector to the RIGHT (ENE).
const FWD_XZ := Vector2(-0.425105, -0.905144)
const RIGHT_XZ := Vector2(0.905144, -0.425105)

## Target overworld karst hill surface height directly above the Collapse Hall (dome apex is ~50.5 m).
## A 6-10 m limestone cap makes the collapsed skylight geologically believable and reachable via ledges.
const MOUNTAIN_SURFACE_OVER_HALL := 56.5

## Passages: polylines of nodes {p: Vector3(u, floor_y, s), w: clear width, h: ceiling height above floor}.
const TUNNELS := {
	"twilight_passage": [
		{"p": Vector3(0.0, 26.0, -12.0), "w": 12.6, "h": 9.2},
		{"p": Vector3(0.0, 25.9, -2.0), "w": 11.5, "h": 8.4},
		{"p": Vector3(-2.0, 25.4, 12.0), "w": 10.6, "h": 8.2},
		{"p": Vector3(-10.5, 24.2, 26.0), "w": 11.2, "h": 8.8},
		{"p": Vector3(-22.0, 23.3, 35.5), "w": 12.0, "h": 9.0},
		{"p": Vector3(-32.0, 23.5, 40.5), "w": 12.8, "h": 9.5},
	],
	"hall_throat": [
		{"p": Vector3(-32.0, 23.5, 40.5), "w": 13.5, "h": 10.5},
		{"p": Vector3(-40.0, 20.8, 49.0), "w": 15.0, "h": 13.0},
		{"p": Vector3(-48.5, 18.5, 58.0), "w": 17.5, "h": 16.0},
	],
	"stream_grotto": [
		{"p": Vector3(-44.0, 18.5, 88.5), "w": 10.6, "h": 8.4},
		{"p": Vector3(-35.0, 17.6, 95.0), "w": 9.6, "h": 7.6},
		{"p": Vector3(-20.0, 17.1, 99.5), "w": 9.6, "h": 7.6},
		{"p": Vector3(-7.0, 16.5, 92.5), "w": 9.6, "h": 7.6},
		{"p": Vector3(0.5, 15.9, 78.0), "w": 9.4, "h": 7.4},
		{"p": Vector3(2.0, 15.4, 63.0), "w": 9.8, "h": 7.8},
	],
	## Deep Descent Passage: branches from South-West Collapse Hall floor and descends into the mountain depths.
	"deep_descent": [
		{"p": Vector3(-68.0, 18.5, 76.0), "w": 13.0, "h": 9.5},
		{"p": Vector3(-76.0, 16.2, 84.0), "w": 12.0, "h": 9.0},
		{"p": Vector3(-84.0, 13.0, 93.0), "w": 11.5, "h": 8.8},
		{"p": Vector3(-92.0, 9.8, 103.0), "w": 12.5, "h": 9.2},
	],
	## Lake Chasm Passage: branches from Abyssal Atrium into the vast Subterranean Lake cavern.
	"lake_tunnel": [
		{"p": Vector3(-92.0, 9.8, 103.0), "w": 12.0, "h": 9.0},
		{"p": Vector3(-79.0, 9.0, 116.0), "w": 12.5, "h": 9.0},
		{"p": Vector3(-65.0, 8.5, 127.0), "w": 13.5, "h": 9.5},
		{"p": Vector3(-50.0, 8.0, 136.0), "w": 15.0, "h": 10.5},
	],
	## Vault Door Passage: branches from Abyssal Atrium leading to the monumental Ancient Big Door.
	"door_tunnel": [
		{"p": Vector3(-92.0, 9.8, 103.0), "w": 11.5, "h": 8.8},
		{"p": Vector3(-105.0, 10.0, 99.0), "w": 11.0, "h": 8.5},
		{"p": Vector3(-118.0, 10.2, 92.0), "w": 11.0, "h": 8.5},
		{"p": Vector3(-128.0, 10.4, 85.0), "w": 11.5, "h": 9.0},
	],
	## Secret route: calibrated to SlimeShapeModel sphere envelope + 0.80m Surface-Nets chord:
	## - Full slime (scale 1.0): outer sphere diam = 4.08 m -> BLOCKED by ~3.65 m clear width.
	## - Split slime (scale <= 0.794): outer sphere diam <= 3.24 m -> FITS CLEANLY.
	"split_crawlway": [
		{"p": Vector3(-27.0, 23.5, 42.5), "w": 3.88, "h": 3.70},
		{"p": Vector3(-18.0, 21.2, 47.5), "w": 3.84, "h": 3.65},
		{"p": Vector3(-8.0, 18.2, 51.5), "w": 3.84, "h": 3.65},
		{"p": Vector3(-2.0, 15.5, 54.5), "w": 3.92, "h": 3.75},
	],
}

## Chambers: ellipsoids {c: Vector3(u, floor_y, s), rx, rz, h}.
const CHAMBERS := {
	"breakdown_fork": {"c": Vector3(-32.5, 23.5, 42.0), "rx": 9.5, "rz": 8.5, "h": 11.0},
	"collapse_hall": {"c": Vector3(-60.0, 18.5, 72.0), "rx": 35.0, "rz": 23.0, "h": 32.0},
	"geode_pocket": {"c": Vector3(2.0, 15.2, 56.0), "rx": 7.5, "rz": 7.5, "h": 12.0},
	"abyssal_atrium": {"c": Vector3(-94.0, 9.8, 106.0), "rx": 16.5, "rz": 14.5, "h": 14.0},
	"underground_lake": {"c": Vector3(-34.0, 7.5, 146.0), "rx": 28.0, "rz": 23.0, "h": 19.5},
	"vault_sanctum": {"c": Vector3(-135.0, 10.4, 82.0), "rx": 13.5, "rz": 11.5, "h": 12.5},
}

## Geological floor & roof features.
const MOUND := {"c": Vector3(-62.0, 18.5, 68.0), "r": 12.0, "rise": 3.4}
const RUBBLE_CREST := {"c": Vector3(-35.0, 23.5, 44.0), "r": 6.8, "rise": 1.6}
const POOL := {"c": Vector3(-48.0, 16.0, 87.5), "rx": 10.2, "rz": 5.8, "water_y": 17.85}
const SKYLIGHT := {"c": Vector3(-62.0, 56.5, 68.0), "r": 6.4}
const WATERFALL := Vector3(-52.5, 17.85, 91.5)

## Big Subterranean Lake feature (vast oval body of cavern water).
const UNDERGROUND_LAKE := {"c": Vector3(-32.0, 6.0, 148.0), "rx": 23.5, "rz": 18.5, "water_y": 7.60}

## Monumental Ancient Big Door at the terminus of Vault Sanctum.
const ANCIENT_DOOR := {
	"pos": Vector3(-144.5, 10.4, 76.5),
	"yaw": 1.08, # Facing inward toward chamber center
	"width": 7.4,
	"height": 9.2,
	"depth": 2.0,
}

## Climbable ledge route spiralling up the Collapse Hall's west/north wall to the Skylight Rim exit.
const LEDGE_ROUTE := [
	Vector3(-56.0, 18.6, 54.0),
	Vector3(-73.0, 24.0, 52.0),
	Vector3(-88.0, 30.2, 61.5),
	Vector3(-88.5, 36.8, 78.5),
	Vector3(-76.5, 41.8, 88.5),
	Vector3(-66.0, 45.0, 80.5),
	Vector3(-58.5, 48.8, 76.5),
	Vector3(-54.0, 52.5, 73.0),
	Vector3(-50.0, 56.0, 68.0),
]
const LEDGE_WIDTH := 8.6
const LEDGE_HEADROOM := 7.2

## Player spawn INSIDE the cave: on the Collapse Hall breakdown mound beside the skylight shaft,
## looking across the hall toward the carved pool basin and grotto mouth.
const SPAWN := Vector3(-56.5, 21.4, 62.5)
const SPAWN_LOOK_AT := Vector3(-48.0, 18.5, 87.5)

## Main route order used for the elevation profile and automated route verification.
const MAIN_ROUTE := ["twilight_passage", "hall_throat", "@collapse_hall", "stream_grotto", "@geode_pocket"]

## 8 Fixed Benchmark Camera Shots (used identically across P1 -> P6 for honest phase-to-phase review).
## Includes real OrbitCamera height/distance shots plus 1 establishing angle for the hall & entrance.
const BENCHMARK_SHOTS := [
	{
		"file": "shot_01_spawn_player_cam.png",
		"label": "1. Player Spawn Camera (OrbitCam behind Slime in Collapse Hall)",
		"slime": Vector3(-56.5, 21.4, 62.5),
		"cam": Vector3(-59.8, 24.4, 57.5),
		"look": Vector3(-50.5, 20.5, 82.0),
		"fov": 46.0,
	},
	{
		"file": "shot_02_entrance_exterior.png",
		"label": "2. Exterior Overhang Mouth (30 m outside on meadow slope)",
		"slime": Vector3(0.5, 26.0, -10.0),
		"cam": Vector3(5.5, 29.5, -28.0),
		"look": Vector3(-0.5, 28.5, 4.0),
		"fov": 50.0,
	},
	{
		"file": "shot_03_twilight_bend.png",
		"label": "3. Twilight Passage Bend (Sightline occlusion before reveal)",
		"slime": Vector3(-6.5, 24.8, 20.0),
		"cam": Vector3(-2.5, 27.2, 13.5),
		"look": Vector3(-16.0, 24.5, 31.0),
		"fov": 48.0,
	},
	{
		"file": "shot_04_breakdown_fork.png",
		"label": "4. Breakdown Fork & Split-Slime Crawlway Mouth",
		"slime": Vector3(-31.5, 24.6, 41.5),
		"cam": Vector3(-35.5, 26.8, 36.5),
		"look": Vector3(-24.0, 23.8, 45.0),
		"fov": 50.0,
	},
	{
		"file": "shot_05_collapse_hall_reveal.png",
		"label": "5. Collapse Hall Reveal (Emerging from throat toward Skylight & Mound)",
		"slime": Vector3(-46.5, 19.3, 56.0),
		"cam": Vector3(-42.5, 23.2, 49.5),
		"look": Vector3(-62.0, 26.0, 70.0),
		"fov": 56.0,
	},
	{
		"file": "shot_06_pool_basin.png",
		"label": "6. Carved Pool Basin & Waterfall Wall (Player-height view)",
		"slime": Vector3(-54.5, 19.0, 80.5),
		"cam": Vector3(-58.5, 21.8, 74.5),
		"look": Vector3(-47.5, 17.8, 89.0),
		"fov": 48.0,
	},
	{
		"file": "shot_07_stream_grotto.png",
		"label": "7. Low Stream Grotto Passage (Compression contrast after hall)",
		"slime": Vector3(-19.5, 17.2, 99.0),
		"cam": Vector3(-27.0, 19.6, 97.5),
		"look": Vector3(-8.0, 17.2, 93.0),
		"fov": 48.0,
	},
	{
		"file": "shot_08_geode_pocket.png",
		"label": "8. Secret Geode Pocket Chamber",
		"slime": Vector3(2.0, 15.3, 60.5),
		"cam": Vector3(1.5, 18.2, 66.0),
		"look": Vector3(2.0, 17.2, 54.0),
		"fov": 52.0,
	},
	{
		"file": "shot_09_underground_lake.png",
		"label": "9. Big Underground Lake (Vast cavern lake & karst column)",
		"slime": Vector3(-48.0, 8.2, 138.0),
		"cam": Vector3(-53.0, 11.5, 133.0),
		"look": Vector3(-32.0, 7.8, 148.0),
		"fov": 56.0,
	},
	{
		"file": "shot_10_ancient_door.png",
		"label": "10. Ancient Big Door (Monumental carved portal & braziers)",
		"slime": Vector3(-136.0, 10.4, 81.0),
		"cam": Vector3(-131.0, 12.5, 84.5),
		"look": Vector3(-144.5, 12.0, 76.5),
		"fov": 54.0,
	},
]


static func to_world(local: Vector3) -> Vector3:
	return Vector3(
		ORIGIN.x + FWD_XZ.x * local.z + RIGHT_XZ.x * local.x,
		local.y,
		ORIGIN.z + FWD_XZ.y * local.z + RIGHT_XZ.y * local.x
	)


static func to_local(world: Vector3) -> Vector3:
	var dx := world.x - ORIGIN.x
	var dz := world.z - ORIGIN.z
	return Vector3(dx * RIGHT_XZ.x + dz * RIGHT_XZ.y, world.y, dx * FWD_XZ.x + dz * FWD_XZ.y)


static func world_spawn_facing_yaw() -> float:
	var a := to_world(SPAWN)
	var b := to_world(SPAWN_LOOK_AT)
	var d := b - a
	return atan2(d.x, d.z)
