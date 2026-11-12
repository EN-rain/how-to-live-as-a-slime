class_name CaveLayout
extends RefCounted
## Single source of truth for the redesigned cave layout (P0 -> P6).
## All positions are in cave-local coordinates Vector3(u, floor_y, s):
##   u = metres to the RIGHT of the mouth axis, s = metres INTO the mountain,
##   y = absolute world height of the walkable floor.
## Both the layout map renderer and the P1 SDF Marching-Cubes baker consume this exact data.

## World position of the mouth centre (visible natural hillside facing Spawn Meadow).
const ORIGIN := Vector3(-24.0, 27.2, -52.0)
## Unit vector INTO the mountain (NNW) and unit vector to the RIGHT (ENE).
const FWD_XZ := Vector2(-0.425105, -0.905144)
const RIGHT_XZ := Vector2(0.905144, -0.425105)

## Target overworld karst hill surface height directly above the Collapse Hall (dome apex is ~50.5 m).
## A 6-10 m limestone cap makes the collapsed skylight geologically believable and reachable via ledges.
const MOUNTAIN_SURFACE_OVER_HALL := 56.5

## Passages: polylines of nodes {p: Vector3(u, floor_y, s), w: clear width, h: ceiling height above floor}.
const TUNNELS := {
	"twilight_passage": [
		{"p": Vector3(0.0, 27.2, -3.5), "w": 11.0, "h": 7.4},
		{"p": Vector3(-2.0, 25.9, 12.0), "w": 10.8, "h": 7.8},
		{"p": Vector3(-10.5, 24.4, 26.0), "w": 11.5, "h": 8.8},
		{"p": Vector3(-22.0, 23.4, 35.5), "w": 12.0, "h": 9.0},
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
	## Deep Descent Passage: sweeps continuously East then South in a flowing curve from
	## the distant Geode Pocket down into Abyssal Atrium (far from Collapse Hall Spawn).
	"deep_descent": [
		{"p": Vector3(5.5, 15.1, 52.5), "w": 11.4, "h": 9.2},
		{"p": Vector3(14.5, 14.5, 49.5), "w": 12.2, "h": 9.2},
		{"p": Vector3(26.5, 13.6, 55.5), "w": 12.6, "h": 9.4},
		{"p": Vector3(36.0, 12.5, 70.0), "w": 13.0, "h": 9.5},
		{"p": Vector3(40.0, 11.2, 92.0), "w": 13.8, "h": 10.0},
		{"p": Vector3(38.0, 10.1, 112.0), "w": 14.5, "h": 10.2},
	],
	## Lake Chasm Passage: flowing curve gliding tangentially onto the NNE Organic Lake promenade.
	"lake_tunnel": [
		{"p": Vector3(38.0, 10.1, 112.0), "w": 14.5, "h": 10.2},
		{"p": Vector3(35.5, 9.4, 121.0), "w": 14.8, "h": 10.6},
		{"p": Vector3(28.5, 8.6, 129.0), "w": 15.5, "h": 11.2},
		{"p": Vector3(19.5, 7.9, 134.8), "w": 16.5, "h": 11.8},
		{"p": Vector3(10.9, 7.5, 141.3), "w": 18.0, "h": 12.5},
	],
	## Organic Lagoon Shoreline Promenade: continuous 360-degree dry walkable rock ledge winding around
	## headlands, the deep southern peninsula, ESE lagoon bay, and NNW grotto cove.
	"lake_shoreline": [
		{"p": Vector3(11.6, 7.5, 140.6), "w": 8.6, "h": 7.0},
		{"p": Vector3(25.7, 7.5, 151.1), "w": 8.6, "h": 7.0},
		{"p": Vector3(29.2, 7.5, 165.1), "w": 8.6, "h": 7.0},
		{"p": Vector3(52.4, 7.5, 175.3), "w": 8.6, "h": 7.0},
		{"p": Vector3(57.8, 7.5, 194.8), "w": 8.6, "h": 7.0},
		{"p": Vector3(34.3, 7.5, 204.9), "w": 8.6, "h": 7.0},
		{"p": Vector3(13.7, 7.5, 207.7), "w": 8.6, "h": 7.0},
		{"p": Vector3(-3.1, 7.5, 202.2), "w": 8.6, "h": 7.0},
		{"p": Vector3(-19.5, 7.5, 210.7), "w": 8.6, "h": 7.0},
		{"p": Vector3(-41.6, 7.5, 210.0), "w": 8.6, "h": 7.0},
		{"p": Vector3(-57.1, 7.5, 197.7), "w": 8.6, "h": 7.0},
		{"p": Vector3(-54.5, 7.5, 180.3), "w": 8.6, "h": 7.0},
		{"p": Vector3(-51.6, 7.5, 165.6), "w": 8.6, "h": 7.0},
		{"p": Vector3(-51.7, 7.5, 146.0), "w": 8.6, "h": 7.0},
		{"p": Vector3(-32.0, 7.5, 135.1), "w": 8.6, "h": 7.0},
		{"p": Vector3(-8.4, 7.5, 135.2), "w": 8.6, "h": 7.0},
		{"p": Vector3(11.6, 7.5, 140.6), "w": 8.6, "h": 7.0},
	],
	## Vault Door Passage: sweeping tangential S-curve descending deeper from the WSW lake promenade to the Ancient Big Door.
	"door_tunnel": [
		{"p": Vector3(-57.1, 7.5, 197.7), "w": 13.5, "h": 10.5},
		{"p": Vector3(-69.5, 6.6, 190.5), "w": 12.8, "h": 9.8},
		{"p": Vector3(-82.0, 5.5, 178.0), "w": 12.5, "h": 9.5},
		{"p": Vector3(-102.0, 4.5, 162.0), "w": 12.5, "h": 9.5},
		{"p": Vector3(-120.0, 3.6, 140.0), "w": 12.8, "h": 9.8},
		{"p": Vector3(-136.0, 2.8, 118.0), "w": 13.0, "h": 10.0},
		{"p": Vector3(-154.0, 2.3, 100.0), "w": 13.5, "h": 10.4},
		{"p": Vector3(-168.0, 2.0, 82.0), "w": 14.5, "h": 11.2},
		{"p": Vector3(-178.0, 2.0, 72.0), "w": 16.0, "h": 12.0},
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
	"abyssal_atrium": {"c": Vector3(38.0, 10.1, 112.0), "rx": 16.0, "rz": 15.0, "h": 15.0},
	"underground_lake": {"c": Vector3(-5.0, 7.5, 178.0), "rx": 44.5, "rz": 34.5, "h": 10.0},
	"vault_sanctum": {"c": Vector3(-179.0, 2.0, 71.0), "rx": 22.0, "rz": 20.0, "h": 24.0},
}

## Geological floor & roof features.
const MOUND := {"c": Vector3(-62.0, 18.5, 68.0), "r": 12.0, "rise": 3.4}
const RUBBLE_CREST := {"c": Vector3(-35.0, 23.5, 44.0), "r": 6.8, "rise": 1.6}
const POOL := {"c": Vector3(-48.0, 16.0, 87.5), "rx": 10.2, "rz": 5.8, "water_y": 17.35}
const SKYLIGHT := {"c": Vector3(-62.0, 56.5, 68.0), "r": 6.4}
const WATERFALL := Vector3(-52.5, 17.35, 91.5)

## Outflow Stream spline (shared between CaveSystem mesh builder and SlimeMotor water detection).
const STREAM_CTRL: Array[Vector3] = [
	Vector3(-42.5, 17.35, 90.2),
	Vector3(-39.5, 16.92, 92.2),
	Vector3(-35.0, 16.66, 95.0),
	Vector3(-27.5, 16.84, 98.2),
	Vector3(-20.0, 16.16, 99.5),
	Vector3(-13.0, 16.44, 96.2),
	Vector3(-7.0, 15.54, 92.5),
	Vector3(-2.8, 15.66, 85.2),
	Vector3(0.5, 14.98, 78.0),
	Vector3(1.5, 15.32, 70.0),
	Vector3(1.8, 14.60, 63.5),
]

## Big Subterranean Lake feature (organic expanded multi-cove cavern lagoon + sculpted deep abyssal crystal basin).
const UNDERGROUND_LAKE := {"c": Vector3(-5.0, 3.6, 178.0), "rx": 44.5, "rz": 34.5, "water_y": 6.40}
const LAKE_ABYSS_PIT := {"c": Vector3(-14.5, 1.40, 186.5), "rx": 12.5, "rz": 9.8, "yaw": -0.32}

## Monumental Ancient Big Door at the terminus of Vault Sanctum.
const ANCIENT_DOOR := {
	"pos": Vector3(-190.5, 2.0, 59.5),
	"yaw": 0.7854, # Facing inward along (+1, +1) toward chamber center (-179, 71)
	"width": 8.6,
	"height": 11.0,
	"depth": 2.4,
}

## Climbable ledge route spiralling up the Collapse Hall's west/north wall to the Skylight Rim exit.
const LEDGE_ROUTE := [
	Vector3(-56.0, 18.6, 54.0),
	Vector3(-73.0, 24.0, 52.0),
	Vector3(-88.0, 30.2, 61.5),
	Vector3(-88.5, 36.8, 78.5),
	Vector3(-76.5, 42.6, 88.5),
	Vector3(-66.0, 47.4, 80.5),
	Vector3(-58.5, 50.8, 76.5),
	Vector3(-54.0, 53.4, 73.0),
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
		"slime": Vector3(0.0, 27.2, -10.0),
		"cam": Vector3(6.0, 30.8, -28.0),
		"look": Vector3(-0.5, 29.5, 4.0),
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
		"label": "9. Big Underground Lake (Organic multi-cove lagoon, peninsula & karst islets)",
		"slime": Vector3(10.9, 7.5, 141.3),
		"cam": Vector3(15.5, 13.8, 134.0),
		"look": Vector3(-8.0, 7.2, 174.0),
		"fov": 62.0,
	},
	{
		"file": "shot_10_ancient_door.png",
		"label": "10. Ancient Big Door (Monumental carved portal & braziers)",
		"slime": Vector3(-179.5, 2.0, 70.5),
		"cam": Vector3(-173.0, 4.8, 77.0),
		"look": Vector3(-190.0, 5.5, 60.0),
		"fov": 56.0,
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


static func lake_shore_radius_scale(theta: float) -> float:
	var peninsula_s := 0.40 * exp(-pow(wrapf(theta - 1.48, -PI, PI) / 0.44, 2.0))
	var spit_ne := 0.22 * exp(-pow(wrapf(theta + 0.58, -PI, PI) / 0.36, 2.0))
	var cove_ese := 0.28 * exp(-pow(wrapf(theta - 0.32, -PI, PI) / 0.48, 2.0))
	var cove_nnw := 0.26 * exp(-pow(wrapf(theta + 2.08, -PI, PI) / 0.50, 2.0))
	var cove_wsw := 0.16 * exp(-pow(wrapf(theta - 2.35, -PI, PI) / 0.42, 2.0))
	var ripple := 0.055 * sin(theta * 5.0 + 0.7) + 0.035 * cos(theta * 7.0 - 1.1)
	return clampf(1.0 + cove_ese + cove_nnw + cove_wsw - peninsula_s - spit_ne + ripple, 0.52, 1.32)


static func lake_shore_point(theta: float, radial_mult: float = 1.0) -> Vector2:
	var lake_c: Vector3 = UNDERGROUND_LAKE["c"]
	var rx: float = float(UNDERGROUND_LAKE["rx"])
	var rz: float = float(UNDERGROUND_LAKE["rz"])
	var sc := lake_shore_radius_scale(theta) * radial_mult
	return Vector2(lake_c.x + cos(theta) * rx * sc, lake_c.z + sin(theta) * rz * sc)


static func world_spawn_facing_yaw() -> float:
	var a := to_world(SPAWN)
	var b := to_world(SPAWN_LOOK_AT)
	var d := b - a
	return atan2(d.x, d.z)
