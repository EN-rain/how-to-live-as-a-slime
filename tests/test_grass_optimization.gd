extends SceneTree

func _init() -> void:
	print("--- Testing Optimized Grass Generation ---")
	call_deferred("_run")

func _run() -> void:
	var scn := load("res://scenes/main.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)

	var terrain := inst.get_node("TerrainScene") as TerrainScene

	var t0 := Time.get_ticks_msec()
	var data := terrain.build_grass_data(Vector2(-150.0, -159.0))
	var elapsed := Time.get_ticks_msec() - t0
	var c_count: int = data.get("common", []).size()
	var w_count: int = data.get("wispy", []).size()
	print("Grass data built in %d ms: common=%d, wispy=%d, total=%d" % [
		elapsed, c_count, w_count, c_count + w_count
	])

	inst.free()
	quit(0)

