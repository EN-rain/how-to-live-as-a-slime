extends SceneTree
## Verifies VaultCrystalCluster nodes exist with valid meshes/materials in the built warren.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	get_root().add_child(main)
	for i in range(30):
		await physics_frame
		await process_frame
	var tb := main.find_child("BeastTerritories", true, false)
	if tb == null:
		print("FAIL: BeastTerritories missing")
		quit(1)
		return
	var warren := tb.find_child("UndergroundRatWarren", true, false)
	if warren == null:
		print("FAIL: warren missing")
		quit(1)
		return
	var clusters := warren.find_children("VaultCrystalCluster", "MeshInstance3D", true, false)
	print("CLUSTERS=", clusters.size())
	for c in clusters:
		var mi := c as MeshInstance3D
		var mat = mi.material_override
		var sh = mat.shader.resource_path if mat != null and mat is ShaderMaterial else "NONE"
		print("  ", mi.name, " pos=", mi.global_position, " aabb=", mi.get_aabb(), " shader=", sh)
	# nests
	var nests := 0
	var stack: Array[Node] = [warren]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is SphereMesh and (n as MeshInstance3D).material_override is StandardMaterial3D:
			var m = (n as MeshInstance3D).material_override
			if m.albedo_color.is_equal_approx(Color(0.88, 0.93, 0.86)):
				nests += 1
	print("EGG_SAC_MESHINSTANCES~", nests)
	print("PROBE_DONE")
	quit(0)
