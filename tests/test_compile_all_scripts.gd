extends SceneTree

func _initialize() -> void:
	print("--- SCANNING AND COMPILING ALL GDSCRIPTS IN PROJECT ---")
	var project_scripts: Array[String] = []
	_collect_scripts("res://autoload", project_scripts)
	_collect_scripts("res://scripts", project_scripts)
	_collect_scripts("res://terrain", project_scripts)
	_collect_scripts("res://main_menu", project_scripts)
	_collect_scripts("res://ui", project_scripts)
	
	var fail_count := 0
	for path in project_scripts:
		var scr = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
		if scr == null:
			print("FAIL: Compilation error in %s" % path)
			fail_count += 1
		else:
			var gd_scr := scr as GDScript
			if gd_scr == null:
				print("FAIL: Not a GDScript: %s" % path)
				fail_count += 1
			else:
				print("OK: %s" % path)
	
	print("--- SCANNED %d SCRIPTS: %d FAILURES ---" % [project_scripts.size(), fail_count])
	quit(0 if fail_count == 0 else 1)

func _collect_scripts(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f != "." and f != "..":
			var p := dir_path.path_join(f)
			if d.current_is_dir():
				_collect_scripts(p, out)
			elif f.ends_with(".gd"):
				out.append(p)
		f = d.get_next()
	d.list_dir_end()

