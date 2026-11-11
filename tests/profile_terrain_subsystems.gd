extends SceneTree

func _init() -> void:
	print("--- Profiling Subsystems of Main Scene ---")
	call_deferred("_run")

func _run() -> void:
	var scn := load("res://scenes/main.tscn") as PackedScene
	var inst := scn.instantiate()

	var terrain := inst.get_node("TerrainScene") as TerrainScene
	print("Profiling TerrainScene subcomponents:")

	var t0 := Time.get_ticks_msec()
	terrain._setup_noise()
	print("  _setup_noise: %d ms" % (Time.get_ticks_msec() - t0))

	var terrain_node := terrain.get_node_or_null("Terrain") as MeshInstance3D
	t0 = Time.get_ticks_msec()
	if terrain_node:
		terrain._build_terrain_mesh(terrain_node)
	print("  _build_terrain_mesh (with collision): %d ms" % (Time.get_ticks_msec() - t0))

	var water_node := terrain.get_node_or_null("Water") as MeshInstance3D
	t0 = Time.get_ticks_msec()
	if water_node:
		terrain._build_water_mesh(water_node)
	print("  _build_water_mesh: %d ms" % (Time.get_ticks_msec() - t0))

	var grass_node := terrain.get_node_or_null("Grass") as MultiMeshInstance3D
	t0 = Time.get_ticks_msec()
	if grass_node:
		terrain._build_grass_multimesh(grass_node)
	print("  _build_grass_multimesh: %d ms" % (Time.get_ticks_msec() - t0))

	var wispy_node := terrain.get_node_or_null("GrassWispy") as MultiMeshInstance3D
	t0 = Time.get_ticks_msec()
	if wispy_node:
		terrain._build_grass_wispy_multimesh(wispy_node)
	print("  _build_grass_wispy_multimesh: %d ms" % (Time.get_ticks_msec() - t0))

	var trees_node := terrain.get_node_or_null("Trees") as Node3D
	t0 = Time.get_ticks_msec()
	if trees_node:
		terrain._build_trees(trees_node)
	print("  _build_trees (with tree colliders): %d ms" % (Time.get_ticks_msec() - t0))

	var rocks_node := terrain.get_node_or_null("Rocks") as Node3D
	t0 = Time.get_ticks_msec()
	if rocks_node:
		terrain._build_rocks(rocks_node)
	print("  _build_rocks (with rock colliders): %d ms" % (Time.get_ticks_msec() - t0))

	var veg_node := terrain.get_node_or_null("Vegetation") as Node3D
	t0 = Time.get_ticks_msec()
	if veg_node:
		terrain._build_vegetation(veg_node)
	print("  _build_vegetation: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	terrain._build_cave()
	print("  _build_cave: %d ms" % (Time.get_ticks_msec() - t0))

	inst.free()
	quit(0)

