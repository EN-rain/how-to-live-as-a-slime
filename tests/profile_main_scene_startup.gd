extends SceneTree

func _init() -> void:
	print("--- Profiling Main Scene Startup & Loading ---")
	call_deferred("_run")

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	print("1. Loading packed scene...")
	var scn := load("res://scenes/main.tscn") as PackedScene
	var t_load := Time.get_ticks_msec() - t0
	print("   PackedScene loaded in %d ms" % t_load)

	var t1 := Time.get_ticks_msec()
	print("2. Instantiating scene tree...")
	var inst := scn.instantiate()
	var t_inst := Time.get_ticks_msec() - t1
	print("   Instantiated in %d ms" % t_inst)

	var t2 := Time.get_ticks_msec()
	print("3. Adding to root and running _ready()...")
	root.add_child(inst)
	var t_ready := Time.get_ticks_msec() - t2
	print("   Added to tree & _ready() completed in %d ms" % t_ready)

	var t3 := Time.get_ticks_msec()
	print("4. Stepping 3 frames to settle render & physics...")
	await process_frame
	await physics_frame
	await process_frame
	var t_frames := Time.get_ticks_msec() - t3
	print("   3 frames rendered in %d ms" % t_frames)

	var total := Time.get_ticks_msec() - t0
	print("TOTAL STARTUP TIME: %d ms" % total)

	inst.free()
	quit(0)

