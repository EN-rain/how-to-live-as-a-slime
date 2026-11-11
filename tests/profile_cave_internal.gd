extends SceneTree

func _init() -> void:
	print("--- Profiling CaveSystem internal builders ---")
	call_deferred("_run")

func _run() -> void:
	var scn := load("res://scenes/main.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	var terrain := inst.get_node("TerrainScene") as TerrainScene
	var cave := terrain.get_node("Cave") as CaveSystem

	var t0 := Time.get_ticks_msec()
	cave._load_rock_meshes()
	print("  _load_rock_meshes: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	var rock_meshes := cave._load_rock_meshes()
	cave._build_rock_convex_shapes(rock_meshes)
	print("  _build_rock_convex_shapes: %d ms" % (Time.get_ticks_msec() - t0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + 9091
	var rock_shapes := cave._build_rock_convex_shapes(rock_meshes)
	var bb := cave.get_node_or_null("CaveBoulderBody") as StaticBody3D

	t0 = Time.get_ticks_msec()
	var fallen_log_xf := cave._build_boulders_and_trees(terrain, bb, rock_meshes, rock_shapes, rng)
	print("  _build_boulders_and_trees: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	cave._build_skylight_beams_and_dust()
	print("  _build_skylight_beams_and_dust: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	cave._build_crystals(rng)
	print("  _build_crystals: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	cave._build_water_features()
	print("  _build_water_features: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	cave._build_pebbles(rng)
	print("  _build_pebbles: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	cave._build_speleothems(bb, rng)
	print("  _build_speleothems: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	cave._build_flora(terrain, fallen_log_xf, rng)
	print("  _build_flora: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	cave._build_ancient_big_door()
	print("  _build_ancient_big_door: %d ms" % (Time.get_ticks_msec() - t0))

	inst.free()
	quit(0)

