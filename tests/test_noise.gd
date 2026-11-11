extends SceneTree

func _initialize() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4

	var continent_radius := 2600.0
	var flat_center_radius := 300.0

	var test_points := [
		["Spawn Center", Vector2(0.0, 0.0)],
		["Near Valley Knoll", Vector2(40.0, -30.0)],
		["Northern Mountain Foothill", Vector2(0.0, -450.0)],
		["Northern Mountain Summit", Vector2(0.0, -900.0)],
		["Western Stepped Mesa", Vector2(-700.0, 0.0)],
		["Eastern Rolling Steppe", Vector2(700.0, 0.0)],
		["Southern Lowland Meadow", Vector2(0.0, 800.0)],
		["Approaching Coast", Vector2(0.0, 2200.0)],
		["Sandy Shoreline", Vector2(0.0, 2600.0)],
		["Open Ocean Shelf", Vector2(0.0, 3000.0)],
	]

	for pt in test_points:
		var name: String = pt[0]
		var v: Vector2 = pt[1]
		var x := v.x
		var z := v.y
		var dist := v.length()

		var warp_macro := noise.get_noise_2d(x * 0.0006 + 120.0, z * 0.0006 - 180.0) * 550.0
		var warp_bays := noise.get_noise_2d(x * 0.0016 - 250.0, z * 0.0016 + 210.0) * 180.0
		var eff_dist := dist + warp_macro + warp_bays

		var spawn_blend := smoothstep(flat_center_radius * 0.35, flat_center_radius * 1.4, dist)
		var valley_floor := 22.0
		var valley_contour := noise.get_noise_2d(x * 0.012 + 10.0, z * 0.012 + 10.0) * 3.5

		var north_bias := smoothstep(-150.0, -600.0, z)
		var mtn_ridge1 := 1.0 - absf(noise.get_noise_2d(x * 0.0018 + 80.0, z * 0.0018 - 120.0)) * 2.1
		var mtn_ridge2 := 1.0 - absf(noise.get_noise_2d(x * 0.0035 - 50.0, z * 0.0035 + 90.0)) * 1.8
		var mtn_peaks := maxf(mtn_ridge1 * 0.7 + mtn_ridge2 * 0.3, 0.0) * 115.0 * north_bias

		var west_bias := smoothstep(-150.0, -550.0, x)
		var mesa_noise := noise.get_noise_2d(x * 0.0028 + 150.0, z * 0.0028 - 70.0) * 45.0
		var mesa_ratio := mesa_noise / 14.0
		var mesa_stepped := floorf(mesa_ratio) * 14.0 + smoothstep(0.2, 0.8, mesa_ratio - floorf(mesa_ratio)) * 14.0
		var western_mesas := maxf(mesa_stepped, 0.0) * west_bias

		var east_bias := smoothstep(100.0, 500.0, x)
		var rolling_highlands := noise.get_noise_2d(x * 0.0035 - 100.0, z * 0.0035 + 100.0) * 35.0 * east_bias

		var rolling_hills := noise.get_noise_2d(x * 0.004, z * 0.004) * 18.0 * spawn_blend
		var micro_contour := noise.get_noise_2d(x * 0.010, z * 0.010) * 5.0

		var land_h := valley_floor + valley_contour + mtn_peaks + western_mesas + rolling_highlands + rolling_hills + micro_contour

		var continent_factor := smoothstep(continent_radius + 150.0, continent_radius - 120.0, eff_dist)
		var sea_bed := -22.0 + noise.get_noise_2d(x * 0.003 - 200.0, z * 0.003 + 200.0) * 3.5
		var final_h := lerpf(sea_bed, land_h, continent_factor)

		print("%-28s (x=%5.0f, z=%5.0f): y=%5.1f" % [name, x, z, final_h])
	quit(0)
