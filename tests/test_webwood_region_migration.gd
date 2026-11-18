extends SceneTree

const WebwoodRegion = preload("res://regions/webwood/webwood_region.gd")
const WebwoodProfile = preload("res://regions/webwood/webwood_profile.gd")

func _initialize() -> void:
	print("--- CHECKPOINT 1: WEBWOOD REGION MIGRATION TEST ---")
	# 1. Default parity on main scene
	var main_ps := load("res://scenes/main.tscn") as PackedScene
	var w1 := main_ps.instantiate()
	root.add_child(w1)
	call_deferred("_run", w1)

func _run(w1: Node) -> void:
	for _i in range(4):
		await physics_frame
		await process_frame

	var t1 := w1.get_node("TerrainScene")
	var reg1: WebwoodRegion = t1.call("get_webwood_region")
	assert(reg1 != null, "World 1 must own WebwoodRegion")
	assert(reg1.sticky_web_zones.size() == 15, "Default Webwood must have 15 sticky web zones")
	var c1: Vector2 = t1.call("get_webwood_center")
	assert(c1.is_equal_approx(Vector2(-410.0, 480.0)), "Default center must match (-410, 480)")
	var trees1: Array = t1.call("get_spider_forest_trees")
	assert(trees1.size() == 413, "Default spider tree count must stay 413 (got %d)" % trees1.size())

	# 2. Second instanced TerrainScene with translated + customized WebwoodProfile
	var terrain_ps := load("res://terrain/terrain.tscn") as PackedScene
	var t2 := terrain_ps.instantiate()
	var prof2 := (load("res://regions/webwood/webwood_default_profile.tres") as WebwoodProfile).duplicate(true) as WebwoodProfile
	prof2.forest_center = Vector2(-500.0, 620.0)
	prof2.trail_start = Vector2(-425.0, 530.0)
	prof2.trail_bend = Vector2(-486.0, 608.0)
	prof2.ground_web_patches[0] = Vector4(6.0, -4.0, 10.0, 0.4)
	t2.set("webwood_profile_override", prof2)
	root.add_child(t2)
	for _i in range(3):
		await physics_frame
		await process_frame

	var reg2: WebwoodRegion = t2.call("get_webwood_region")
	assert(reg2 != null and reg2 != reg1, "World 2 must own a distinct WebwoodRegion")
	var c2: Vector2 = t2.call("get_webwood_center")
	assert(c2.is_equal_approx(Vector2(-500.0, 620.0)), "Translated center must be (-500, 620)")
	var sh_mat := (t2.get_node("Terrain") as MeshInstance3D).material_override as ShaderMaterial
	var u_c2: Vector2 = sh_mat.get_shader_parameter("u_webwood_center")
	assert(u_c2.is_equal_approx(Vector2(-500.0, 620.0)), "Shader u_webwood_center must follow profile")
	assert(reg2.is_in_sticky_web(Vector3(-494.0, 55.0, 616.0)), "Edited ground_web_patches[0] must move sticky trigger")
	assert(not reg2.is_in_sticky_web(Vector3(-410.0, 55.0, 480.0)), "Old center must not trigger in moved World 2")
	# Isolation check: World 1 must remain intact at (-410, 480)
	assert(reg1.is_in_sticky_web(Vector3(-410.0, 55.0, 480.0)), "World 1 sticky zone must not be overwritten by World 2")
	assert(WorldLandmarks.describe_zone(Vector3(-500.0, 60.0, 620.0), 55.0, c2) == "Webwood Spider Forest", "Zone label must follow translated Webwood")

	print("CHECKPOINT_1_WEBWOOD_MIGRATION_PASSED")
	quit(0)
