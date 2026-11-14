extends SceneTree
## Generates default Inspector .tres configs, cave_layout.tres, and res://terrain/cave/cave.tscn
## so the entire cave layout, lighting rig, and configs are editable in the Godot Editor.

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://terrain/cave")

	var bake_cfg := CaveBakeConfig.new()
	ResourceSaver.save(bake_cfg, "res://terrain/cave/default_bake_config.tres")

	var scatter_cfg := CaveScatterConfig.new()
	ResourceSaver.save(scatter_cfg, "res://terrain/cave/default_scatter_config.tres")

	var water_cfg := CaveWaterConfig.new()
	ResourceSaver.save(water_cfg, "res://terrain/cave/default_water_config.tres")

	var layout_data := CaveLayout.build_default_layout_data()
	ResourceSaver.save(layout_data, CaveLayout.ACTIVE_LAYOUT_PATH)

	# Build cave.tscn
	var root := CaveSystem.new()
	root.name = "Cave"
	root.bake_config = ResourceLoader.load("res://terrain/cave/default_bake_config.tres")
	root.scatter_config = ResourceLoader.load("res://terrain/cave/default_scatter_config.tres")
	root.water_config = ResourceLoader.load("res://terrain/cave/default_water_config.tres")
	root.layout_data = ResourceLoader.load(CaveLayout.ACTIVE_LAYOUT_PATH)

	var origin := CaveOriginNode.new()
	origin.name = "CaveOrigin"
	origin.position = Vector3(CaveLayout.ORIGIN.x, 0.0, CaveLayout.ORIGIN.z)
	origin.basis = Basis(
		Vector3(CaveLayout.RIGHT_XZ.x, 0.0, CaveLayout.RIGHT_XZ.y),
		Vector3.UP,
		Vector3(CaveLayout.FWD_XZ.x, 0.0, CaveLayout.FWD_XZ.y)
	)
	root.add_child(origin)
	origin.owner = root
	origin.populate_from_constants()
	for child in origin.get_children():
		child.owner = root

	# Build CaveLighting child hierarchy
	var rig := Node3D.new()
	rig.name = "CaveLighting"
	root.add_child(rig)
	rig.owner = root

	var probe := ReflectionProbe.new()
	probe.name = "CaveInteriorProbe"
	probe.interior = true
	probe.box_projection = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.38, 0.43, 0.52, 1.0)
	probe.ambient_color_energy = 0.65
	probe.basis = Basis(
		Vector3(CaveLayout.RIGHT_XZ.x, 0.0, CaveLayout.RIGHT_XZ.y),
		Vector3.UP,
		Vector3(-CaveLayout.FWD_XZ.x, 0.0, -CaveLayout.FWD_XZ.y)
	)
	probe.position = CaveLayout.to_world(Vector3(-68.0, 24.0, 116.0))
	probe.size = Vector3(286.0, 56.0, 244.0)
	rig.add_child(probe)
	probe.owner = root

	var key_spot := SpotLight3D.new()
	key_spot.name = "SkylightKeySpot"
	var sky_c_spot: Vector3 = CaveLayout.SKYLIGHT["c"]
	var mound_c_spot: Vector3 = CaveLayout.MOUND["c"]
	var sky_from := CaveLayout.to_world(Vector3(sky_c_spot.x + 2.0, 64.0, sky_c_spot.z - 2.0))
	var sky_aim := CaveLayout.to_world(Vector3(mound_c_spot.x, 20.0, mound_c_spot.z))
	key_spot.light_color = Color(1.0, 0.95, 0.84, 1.0)
	key_spot.light_energy = 3.4
	key_spot.spot_range = 74.0
	key_spot.spot_attenuation = 0.85
	key_spot.spot_angle = 40.0
	key_spot.spot_angle_attenuation = 2.05
	key_spot.shadow_enabled = true
	key_spot.shadow_bias = 0.08
	key_spot.shadow_normal_bias = 0.2
	key_spot.shadow_blur = 0.0
	rig.add_child(key_spot)
	key_spot.owner = root
	key_spot.look_at_from_position(sky_from, sky_aim, Vector3.UP)

	var accents := [
		["CollapseBounceOmni", Vector3(-56.0, 26.5, 67.0), Color(0.98, 0.88, 0.72), 1.15, 29.0, 1.45],
		["TwilightArchOmni", Vector3(-34.0, 22.5, 42.0), Color(0.95, 0.78, 0.52), 1.35, 22.0, 1.50],
		["GrottoArchOmni", Vector3(-42.0, 20.8, 86.0), Color(0.32, 0.86, 0.98), 1.65, 24.0, 1.45],
		["SpiralLedgeStartOmni", Vector3(-73.0, 23.5, 81.0), Color(0.65, 0.55, 1.0), 1.45, 22.0, 1.45],
		["GeodeCrystalOmni", Vector3(5.5, 20.8, 55.0), Color(0.56, 0.72, 1.0), 4.20, 44.0, 0.85],
		["UndergroundLakeOmni", Vector3(-6.0, 15.2, 178.0), Color(0.58, 0.92, 1.00), 5.10, 116.0, 0.60],
		["VaultDoorOmni", Vector3(-183.6, 7.2, 66.4), Color(0.96, 0.80, 0.56), 3.65, 42.0, 0.96],
	]
	for a: Array in accents:
		var omni := OmniLight3D.new()
		omni.name = String(a[0])
		omni.position = CaveLayout.to_world(a[1] as Vector3)
		omni.light_color = a[2] as Color
		omni.light_energy = float(a[3])
		omni.omni_range = float(a[4])
		omni.omni_attenuation = float(a[5])
		omni.shadow_enabled = false
		rig.add_child(omni)
		omni.owner = root

	var ps := PackedScene.new()
	var pack_err := ps.pack(root)
	if pack_err != OK:
		push_error("Failed to pack cave.tscn: %s" % pack_err)
		quit(1)
		return
	var save_err := ResourceSaver.save(ps, "res://terrain/cave/cave.tscn")
	if save_err != OK:
		push_error("Failed to save cave.tscn: %s" % save_err)
		quit(1)
		return
	print("Generated cave.tscn + 4 Inspector .tres configs successfully!")
	root.free()
	quit(0)

