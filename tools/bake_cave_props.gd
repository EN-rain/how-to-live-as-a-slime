extends SceneTree
## Offline Cave Props Baker.
## Precomputes all deterministic props transforms for the World Cave
## (boulders, crystals, pebbles, speleothems, flora) and saves them into
## res://terrain/cave/cave_props_cache.dat, reducing runtime cave setup from 2.4s to <15ms.

func _init() -> void:
	print("=== Baking Cave Props Cache ===")
	call_deferred("_run")

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute("res://terrain/cave")

	print("1. Instantiating TerrainScene to sample surface heights...")
	var terrain_sc := load("res://terrain/terrain.tscn") as PackedScene
	var terrain := terrain_sc.instantiate() as TerrainScene
	terrain.set("enable_cave", true)
	root.add_child(terrain)

	print("2. Computing deterministic cave props transforms...")
	var data: Dictionary = CaveSystem.compute_cave_props(terrain, 1337)
	print("   Boulders: %d grouped" % data["boulders"]["grouped"].size())
	print("   Crystals: %d shards" % data["crystals"]["xforms"].size())
	print("   Pebbles: %d instances" % data["pebbles"]["xforms"].size())
	print("   Speleothems: %d instances" % data["speleothems"]["xforms"].size())
	print("   Flora: %d grass blades, %d ferns, %d plants, %d bushes, %d shelf fungi, %d grotto mushrooms" % [
		data["flora"]["grass_xf"].size(),
		data["flora"]["fern_xf"].size(),
		data["flora"]["plant_xf"].size(),
		data["flora"]["bush_xf"].size(),
		data["flora"]["shelf_xf"].size(),
		data["flora"]["grotto_mush_xf"].size()
	])

	print("3. Saving to res://terrain/cave/cave_props_cache.dat...")
	var f := FileAccess.open("res://terrain/cave/cave_props_cache.dat", FileAccess.WRITE)
	if f != null:
		f.store_var(data, true)
		f.close()
		print("   Saved successfully! File size: %d bytes" % FileAccess.get_file_as_bytes("res://terrain/cave/cave_props_cache.dat").size())
	else:
		push_error("Failed to write cave_props_cache.dat!")

	terrain.free()
	var elapsed := Time.get_ticks_msec() - t0
	print("=== Cave Props Bake Complete in %d ms ===" % elapsed)
	quit(0)
