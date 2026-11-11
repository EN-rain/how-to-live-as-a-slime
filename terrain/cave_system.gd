@tool
class_name CaveSystem
extends Node3D
## Runtime loader and atmosphere/lighting/set-dressing controller for the baked SDF World Cave.
## Geometry and ConcavePolygonShape3D colliders are baked offline in the sandbox by tools/bake_cave.gd.

const CAVE_MESH_PATH := "res://terrain/cave/cave_mesh.res"
const CAVE_FLOOR_SHAPE_PATH := "res://terrain/cave/cave_floor_shape.res"
const CAVE_WALL_SHAPE_PATH := "res://terrain/cave/cave_wall_shape.res"
const CAVE_PROPS_CACHE_PATH := "res://terrain/cave/cave_props_cache.dat"

const GEOFENCE_OVERWORLD_H := 56.5

@export var greybox_mode: bool = false

static var _shared_sdf: CaveSDF = null
static var _soft_particle_tex: ImageTexture = null
static var _cached_props_data: Dictionary = {}
static var _cached_pebble_mesh: Mesh = null
static var _cached_speleothem_mesh: Mesh = null
static var _cached_crystal_mesh: Mesh = null
static var _cached_water_meshes: Dictionary = {}

var _cached_rock_mat: ShaderMaterial = null
var _grass_shader_mat: ShaderMaterial = null
var _flora_grass_node: MultiMeshInstance3D = null
var _slime_ref: Node3D = null

var _geode_reward_node: Node3D = null
var _geode_reward_mesh: MeshInstance3D = null
var _geode_reward_area: Area3D = null
var _geode_reward_collected: bool = false
var _geode_spin_t: float = 0.0
var _reverb_bus_idx: int = -1


static func get_sdf() -> CaveSDF:
	if _shared_sdf == null:
		_shared_sdf = CaveSDF.new(1337)
	return _shared_sdf


# ==============================================================================
# STATIC TERRAIN & MOTOR INTEGRATION QUERIES
# ==============================================================================

static func apply_overworld_mountain_and_plaza(x: float, z: float, base_land_h: float, _terrain_noise: FastNoiseLite) -> float:
	if x < -320.0 or x > 45.0 or z < -350.0 or z > -60.0:
		return base_land_h
	var cl := CaveLayout.to_local(Vector3(x, 0.0, z))
	if cl.x < -165.0 or cl.x > 55.0 or cl.z < -62.0 or cl.z > 190.0:
		return base_land_h
	return CaveSDF.eval_karst_hill_height(cl.x, cl.z, base_land_h)


static func is_quad_in_portal_cutout(v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3) -> bool:
	return CaveSDF.is_quad_in_cave_cutout(v00, v10, v01, v11)


static func is_in_portal_scatter_exclusion(x: float, z: float, is_grass: bool = false) -> bool:
	if x < -240.0 or x > 15.0 or z < -275.0 or z > -80.0:
		return false
	return CaveSDF.is_in_overworld_scatter_exclusion(x, z, is_grass)


static func is_subterranean_or_cutout(x: float, z: float, foot_y: float, overworld_h: float) -> bool:
	if x < -320.0 or x > 45.0 or z < -350.0 or z > -60.0:
		return false
	var cl := CaveLayout.to_local(Vector3(x, foot_y, z))
	if cl.x < -160.0 or cl.x > 36.0 or cl.z < -25.0 or cl.z > 185.0:
		return false

	# 1. Inside either heightfield cutout (Entrance Outcrop or Skylight hole), always use SDF mesh
	if cl.z > -16.0 and cl.z < 25.0 and cl.x > -22.0 and cl.x < 22.0:
		return true
	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	var d_sky: float = Vector2(cl.x - sky_c.x, cl.z - sky_c.z).length()
	if d_sky < 11.0:
		return true

	# 2. If actor is up on the grassy mountain roof outside the cutouts, use overworld heightfield
	if foot_y >= overworld_h - 2.2:
		return false

	# 3. Actor is below the mountain skin: check if inside/near subterranean cave air
	var sdf := get_sdf()
	return sdf.eval_cave_void_smooth(cl.x, foot_y + 1.1, cl.z) < 3.2


static func sample_sdf_floor_below(x: float, z: float, foot_y: float, overworld_h: float) -> Vector4:
	var sdf := get_sdf()
	var cl := CaveLayout.to_local(Vector3(x, foot_y, z))
	var u := cl.x
	var s := cl.z

	# Use fast analytical smooth SDF when subterranean inside the cave (avoids 3D noise lag on slopes)
	var use_fast := (foot_y < 46.0 and s > 4.0)
	var y_air := foot_y + 1.1
	var f_air := sdf.eval_cave_void_smooth(u, y_air, s) if use_fast else sdf.eval_sdf_full(u, y_air, s, overworld_h)
	if f_air >= 0.0:
		for lift in 3:
			var try_y := foot_y + 1.8 + float(lift) * 0.8
			var try_f := sdf.eval_cave_void_smooth(u, try_y, s) if use_fast else sdf.eval_sdf_full(u, try_y, s, overworld_h)
			if try_f < 0.0:
				y_air = try_y
				f_air = try_f
				break

	var y_prev := y_air
	var step := 0.85
	var y_min := 4.5 if foot_y > 46.0 else maxf(4.5, foot_y - 9.0)
	var hit_y := foot_y
	var found := false
	var nudged := false
	var ln := Vector3.UP
	var eps := 0.45
	var y_cur := y_air - step
	while y_cur >= y_min:
		var f_cur := sdf.eval_cave_void_smooth(u, y_cur, s) if use_fast else sdf.eval_sdf_full(u, y_cur, s, overworld_h)
		if f_air < 0.0 and f_cur >= 0.0:
			var lo := y_cur
			var hi := y_prev
			for _b in 4:
				var mid := 0.5 * (lo + hi)
				var f_mid := sdf.eval_cave_void_smooth(u, mid, s) if use_fast else sdf.eval_sdf_full(u, mid, s, overworld_h)
				if f_mid >= 0.0:
					lo = mid
				else:
					hi = mid
			var cand_y := 0.5 * (lo + hi)
			var gx: float
			var gy: float
			var gz: float
			if use_fast:
				gx = sdf.eval_cave_void_smooth(u + eps, cand_y, s) - sdf.eval_cave_void_smooth(u - eps, cand_y, s)
				gy = sdf.eval_cave_void_smooth(u, cand_y + eps, s) - sdf.eval_cave_void_smooth(u, cand_y - eps, s)
				gz = sdf.eval_cave_void_smooth(u, cand_y, s + eps) - sdf.eval_cave_void_smooth(u, cand_y, s - eps)
			else:
				gx = sdf.eval_sdf_full(u + eps, cand_y, s, overworld_h) - sdf.eval_sdf_full(u - eps, cand_y, s, overworld_h)
				gy = sdf.eval_sdf_full(u, cand_y + eps, s, overworld_h) - sdf.eval_sdf_full(u, cand_y - eps, s, overworld_h)
				gz = sdf.eval_sdf_full(u, cand_y, s + eps, overworld_h) - sdf.eval_sdf_full(u, cand_y, s - eps, overworld_h)
			var cand_ln := Vector3(-gx, -gy, -gz).normalized()
			if cand_ln.y >= 0.45:
				hit_y = cand_y
				ln = cand_ln
				found = true
				break
			# Grazed a vertical or overhanging wall: nudge laterally at most once per query so it never loops endlessly
			if not nudged:
				nudged = true
				var lat := Vector2(cand_ln.x, cand_ln.z)
				if lat.length_squared() > 1e-4:
					lat = lat.normalized() * 0.85
					u += lat.x
					s += lat.y
					f_cur = sdf.eval_cave_void_smooth(u, y_cur, s) if use_fast else sdf.eval_sdf_full(u, y_cur, s, overworld_h)
			else:
				break
		y_prev = y_cur
		f_air = f_cur
		y_cur -= step

	if not found:
		hit_y = maxf(6.5, foot_y - 2.0)
		ln = Vector3.UP

	var wn := (CaveLayout.to_world(ln) - CaveLayout.ORIGIN)
	wn.y = ln.y
	wn = wn.normalized()
	return Vector4(wn.x, wn.y, wn.z, hit_y)


# ==============================================================================
# RUNTIME SCENE BUILDER
# ==============================================================================

func rebuild_cave(terrain_scene: Node3D, seed_val: int = 1337, build_colliders: bool = true) -> void:
	_clear_generated_children()
	_flora_grass_node = null
	_grass_shader_mat = null
	_geode_reward_node = null
	_geode_reward_mesh = null
	_geode_reward_area = null
	_geode_reward_collected = false

	if not ResourceLoader.exists(CAVE_MESH_PATH):
		push_warning("CaveSystem: Baked mesh missing at %s (run tools/bake_cave.gd)" % CAVE_MESH_PATH)
		return

	var cave_mesh := load(CAVE_MESH_PATH) as ArrayMesh
	if cave_mesh == null:
		return

	var shell := MeshInstance3D.new()
	shell.name = "CaveShell"
	shell.mesh = cave_mesh
	shell.material_override = _get_cave_rock_material()
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	shell.custom_aabb = AABB(Vector3(-350.0, 2.0, -350.0), Vector3(450.0, 80.0, 450.0))
	add_child(shell)

	if build_colliders:
		if ResourceLoader.exists(CAVE_FLOOR_SHAPE_PATH):
			var floor_shape := load(CAVE_FLOOR_SHAPE_PATH) as Shape3D
			if floor_shape != null:
				var fb := StaticBody3D.new()
				fb.name = "CaveFloorBody"
				fb.collision_layer = 1
				fb.collision_mask = 0
				var fcs := CollisionShape3D.new()
				fcs.shape = floor_shape
				fb.add_child(fcs)
				shell.add_child(fb)

		if ResourceLoader.exists(CAVE_WALL_SHAPE_PATH):
			var wall_shape := load(CAVE_WALL_SHAPE_PATH) as Shape3D
			if wall_shape != null:
				var wb := StaticBody3D.new()
				wb.name = "CaveWallBody"
				wb.collision_layer = 4
				wb.collision_mask = 0
				var wcs := CollisionShape3D.new()
				wcs.shape = wall_shape
				wb.add_child(wcs)
				shell.add_child(wb)

	_build_interior_lighting_rig()

	var boulder_body: StaticBody3D = null
	if build_colliders:
		boulder_body = StaticBody3D.new()
		boulder_body.name = "CaveBoulderBody"
		boulder_body.collision_layer = 4
		boulder_body.collision_mask = 0
		add_child(boulder_body)

	var rock_meshes := _load_rock_meshes()
	var rock_shapes := _build_rock_convex_shapes(rock_meshes)

	var props_data := _load_or_compute_props(terrain_scene, seed_val)

	# P2: Kitbashed entrance talus, brow crags, breakdown mound boulders & deadwood tree/log
	var fallen_log_xf := _build_boulders_and_trees(terrain_scene, boulder_body, rock_meshes, rock_shapes, null, props_data)

	# P3: Active atmosphere controller and sunbeam shafts
	if not Engine.is_editor_hint():
		var atmos := CaveAtmosphere.new()
		atmos.name = "CaveAtmosphere"
		add_child(atmos)
	_build_skylight_beams_and_dust()

	# P4: Radiating Geode crystal clusters + tiny Fork crawlway mouth teaser crystals
	_build_crystals(null, props_data)

	# P5: Pool basin water, drip waterfall ribbon + splash, outflow stream, river pebbles,
	#     paired speleothems, strictly zero-collision ecological CaveFlora, and the Ancient Big Door
	_build_water_features()
	_build_pebbles(null, props_data)
	_build_speleothems(boulder_body, null, props_data)
	_build_flora(terrain_scene, fallen_log_xf, null, props_data)
	_build_ancient_big_door()

	# P6: Geode Prismatic Crystal Core collectible reward & acoustic zone reverb plumbing
	_build_geode_reward()
	_build_reverb_zones()


func _load_or_compute_props(terrain_scene: Node3D, seed_val: int = 1337) -> Dictionary:
	if not _cached_props_data.is_empty():
		return _cached_props_data

	if FileAccess.file_exists(CAVE_PROPS_CACHE_PATH):
		var f := FileAccess.open(CAVE_PROPS_CACHE_PATH, FileAccess.READ)
		if f != null:
			var d = f.get_var(true)
			f.close()
			if d is Dictionary and not d.is_empty():
				_cached_props_data = d
				return _cached_props_data

	var computed := compute_cave_props(terrain_scene, seed_val)
	_cached_props_data = computed
	var f_out := FileAccess.open(CAVE_PROPS_CACHE_PATH, FileAccess.WRITE)
	if f_out != null:
		f_out.store_var(computed, true)
		f_out.close()
	return _cached_props_data


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _slime_ref == null or not is_instance_valid(_slime_ref):
		var parent := get_parent()
		if parent != null and parent.get_parent() != null:
			_slime_ref = parent.get_parent().get_node_or_null("Slime") as Node3D

	if _grass_shader_mat != null and _slime_ref != null:
		_grass_shader_mat.set_shader_parameter("slime_pos", _slime_ref.global_position)

	if not _geode_reward_collected and _geode_reward_mesh != null and is_instance_valid(_geode_reward_mesh):
		_geode_spin_t += delta
		_geode_reward_mesh.rotation.y = _geode_spin_t * 0.95
		_geode_reward_mesh.position.y = sin(_geode_spin_t * 2.1) * 0.22


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _geode_reward_collected or _geode_reward_node == null:
		return
	var rpos := _geode_reward_node.global_position
	var candidates: Array = []
	var parent := get_parent()
	var main_node := parent.get_parent() if parent != null else null
	if main_node != null:
		var eco := main_node.get_node_or_null("Ecosystem")
		if eco != null and "registered_slimes" in eco:
			candidates.append_array(eco.registered_slimes)
		var direct_slime := main_node.get_node_or_null("Slime")
		if direct_slime != null and not candidates.has(direct_slime):
			candidates.append(direct_slime)

	for s in candidates:
		if not is_instance_valid(s):
			continue
		var sp: Vector3 = (s as Node3D).global_position
		var dx := sp.x - rpos.x
		var dz := sp.z - rpos.z
		var dy := absf(sp.y - rpos.y)
		if (dx * dx + dz * dz) <= 7.84 and dy <= 3.5:
			_collect_geode_reward(s)
			break


func _collect_geode_reward(collector: Variant) -> void:
	if _geode_reward_collected:
		return
	_geode_reward_collected = true

	var target_slime: Variant = collector
	if collector != null and collector is Object and "role" in collector:
		var main_node := get_parent().get_parent() if get_parent() != null else null
		var player_slime := main_node.get_node_or_null("Slime") if main_node != null else null
		if player_slime != null and collector != player_slime and collector.role != 0:
			target_slime = player_slime

	if target_slime != null and target_slime.has_method("add_volume"):
		target_slime.add_volume(8.0)

	if _geode_reward_mesh != null:
		_geode_reward_mesh.visible = false
	if _geode_reward_area != null:
		_geode_reward_area.monitoring = false

	var st := get_tree()
	if st != null:
		st.call_group("hud", "show_toast", "Geode Heart Absorbed! (+8.0 m³)", Color(0.55, 0.94, 1.0), 4.0)

	if DisplayServer.get_name() != "headless":
		var sm := get_node_or_null("/root/SettingsManager")
		if sm != null and sm.has_method("play_ui_sound"):
			sm.play_ui_sound("confirm")


func _on_geode_area_body_entered(body: Node3D) -> void:
	if _geode_reward_collected or body == null:
		return
	var p := body.get_parent()
	if p != null and p.has_method("add_volume"):
		_collect_geode_reward(p)


func is_geode_reward_collected() -> bool:
	return _geode_reward_collected


func _clear_generated_children() -> void:
	for c in get_children():
		remove_child(c)
		c.free()


func _get_cave_rock_material() -> ShaderMaterial:
	if _cached_rock_mat == null:
		_cached_rock_mat = ShaderMaterial.new()
		_cached_rock_mat.shader = load("res://terrain/cave_rock.gdshader") as Shader
		var rock_tex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
		var floor_tex := load("res://assets/nature/PathRocks_Diffuse.png") as Texture2D
		if rock_tex != null:
			_cached_rock_mat.set_shader_parameter("rock_texture", rock_tex)
		if floor_tex != null:
			_cached_rock_mat.set_shader_parameter("floor_texture", floor_tex)
	_cached_rock_mat.set_shader_parameter("greybox_mode", greybox_mode)
	return _cached_rock_mat


# ==============================================================================
# P3: LIGHTING RIG (<= 4 DYNAMIC LIGHTS, EXACTLY 1 SHADOWED)
# ==============================================================================

func _build_interior_lighting_rig() -> void:
	var rig := Node3D.new()
	rig.name = "CaveLighting"
	add_child(rig)

	# Interior Ambient Override (kills outdoor sky-blue ambient leak on Mobile renderer)
	var probe := ReflectionProbe.new()
	probe.name = "CaveInteriorProbe"
	probe.interior = true
	probe.box_projection = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.36, 0.39, 0.46, 1.0)
	probe.ambient_color_energy = 0.52
	var p_center := CaveLayout.to_world(Vector3(-42.0, 31.0, 62.0))
	probe.basis = Basis(
		Vector3(CaveLayout.RIGHT_XZ.x, 0.0, CaveLayout.RIGHT_XZ.y),
		Vector3.UP,
		Vector3(-CaveLayout.FWD_XZ.x, 0.0, -CaveLayout.FWD_XZ.y)
	)
	probe.position = p_center
	probe.size = Vector3(132.0, 46.0, 114.0)
	rig.add_child(probe)

	# 1. KEY LIGHT (Shadowed): Sunbeam spot through the Cenote Skylight onto the Moss Mound
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
	key_spot.look_at_from_position(sky_from, sky_aim, Vector3.UP)

	# 2-9. ACCENT LIGHTS (unshadowed omnis with tight range & falloff so light never bleeds through walls):
	# Warm mound bounce, passage landmark beacons, cool grotto aqua fill, violet geode glow, atrium ambient, lake glow, door torchlight
	var accents := [
		["CollapseBounceOmni", Vector3(-56.0, 26.5, 67.0), Color(0.98, 0.88, 0.72), 1.15, 29.0, 1.45],
		["TwilightArchOmni", Vector3(-34.0, 22.5, 42.0), Color(0.95, 0.78, 0.52), 1.35, 22.0, 1.50],
		["GrottoArchOmni", Vector3(-42.0, 20.8, 86.0), Color(0.32, 0.86, 0.98), 1.65, 24.0, 1.45],
		["SpiralLedgeStartOmni", Vector3(-73.0, 23.5, 81.0), Color(0.65, 0.55, 1.0), 1.45, 22.0, 1.45],
		["GrottoCoolOmni", Vector3(-22.0, 21.5, 95.5), Color(0.42, 0.84, 0.98), 2.10, 32.0, 1.45],
		["GeodeCrystalOmni", Vector3(2.0, 21.8, 56.5), Color(0.68, 0.60, 1.0), 3.25, 26.0, 1.35],
		["AtriumDescentOmni", Vector3(-92.0, 14.5, 104.0), Color(0.52, 0.76, 0.92), 2.05, 30.0, 1.40],
		["UndergroundLakeOmni", Vector3(-32.0, 14.0, 148.0), Color(0.22, 0.74, 0.90), 2.95, 38.0, 1.35],
		["VaultDoorOmni", Vector3(-138.0, 13.5, 82.0), Color(1.0, 0.76, 0.38), 3.10, 28.0, 1.35],
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


# ==============================================================================
# NAVIGATION CORRIDOR SAFETY & SDF SURFACE QUERIES
# ==============================================================================

static func _dist_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _is_clear_of_all_routes(u: float, s: float, min_clear: float) -> bool:
	var pt := Vector2(u, s)
	# Keep player spawn point open
	if pt.distance_to(Vector2(CaveLayout.SPAWN.x, CaveLayout.SPAWN.z)) < min_clear + 2.2:
		return false
	# Keep Geode core & landing clear
	var gc: Vector3 = CaveLayout.CHAMBERS["geode_pocket"]["c"]
	if pt.distance_to(Vector2(gc.x, gc.z)) < min_clear + 1.5:
		return false
	# Keep Collapse Hall central walk point clear
	if pt.distance_to(Vector2(-52.0, 74.0)) < min_clear + 1.5:
		return false
	# Keep Abyssal Atrium center hub clear
	if pt.distance_to(Vector2(-94.0, 106.0)) < min_clear + 2.0:
		return false
	# Keep Underground Lake shore walkway clear
	if pt.distance_to(Vector2(-48.0, 138.0)) < min_clear + 2.0:
		return false
	# Keep Ancient Door dais and frontal approach clear
	if pt.distance_to(Vector2(-140.0, 80.0)) < min_clear + 2.5:
		return false

	for tname: String in ["twilight_passage", "hall_throat", "stream_grotto", "split_crawlway", "deep_descent", "lake_tunnel", "door_tunnel"]:
		var nodes: Array = CaveLayout.TUNNELS[tname]
		var req := min_clear + (2.0 if tname == "split_crawlway" else 1.6)
		for i in range(nodes.size() - 1):
			var pa: Vector3 = nodes[i]["p"]
			var pb: Vector3 = nodes[i + 1]["p"]
			if _dist_to_segment_2d(pt, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)) < req:
				return false

	# Also keep explicit split-crawlway entry corridor clear
	if _dist_to_segment_2d(pt, Vector2(-32.0, 40.5), Vector2(-27.0, 42.5)) < min_clear + 2.2:
		return false

	# Keep Spiral Ledge Exit corridor wide open
	var lpts := CaveLayout.LEDGE_ROUTE
	for i in range(lpts.size() - 1):
		var pa: Vector3 = lpts[i]
		var pb: Vector3 = lpts[i + 1]
		if _dist_to_segment_2d(pt, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)) < min_clear + 2.5:
			return false

	return true


static func _sample_ceiling_y(sdf: CaveSDF, u: float, y_start: float, s: float, y_max: float = 54.0) -> float:
	var y := y_start
	var prev_f := sdf.eval_sdf_full(u, y, s, GEOFENCE_OVERWORLD_H)
	while y < y_max:
		y += 0.6
		var cur_f := sdf.eval_sdf_full(u, y, s, GEOFENCE_OVERWORLD_H)
		if prev_f < 0.0 and cur_f >= 0.0:
			var lo := y - 0.6
			var hi := y
			for _i in 4:
				var mid := 0.5 * (lo + hi)
				if sdf.eval_sdf_full(u, mid, s, GEOFENCE_OVERWORLD_H) >= 0.0:
					hi = mid
				else:
					lo = mid
			return 0.5 * (lo + hi)
		prev_f = cur_f
	return y_max


static func _sample_floor_y(sdf: CaveSDF, u: float, y_start: float, s: float) -> float:
	var wp := CaveLayout.to_world(Vector3(u, y_start, s))
	return sample_sdf_floor_below(wp.x, wp.z, y_start, GEOFENCE_OVERWORLD_H).w


static func _sample_exterior_sdf_y(sdf: CaveSDF, terrain_scene: Node3D, u: float, s: float) -> float:
	var w_xz := CaveLayout.to_world(Vector3(u, 26.0, s))
	var ov_h := float(terrain_scene.call("sample_height", w_xz.x, w_xz.z)) if terrain_scene != null else CaveLayout.ORIGIN.y
	var y_top := maxf(ov_h + 6.0, 38.0)
	var y_prev := y_top
	var prev_f := sdf.eval_sdf_full(u, y_prev, s, ov_h)
	var y_cur := y_prev - 0.5
	while y_cur >= 20.0:
		var cur_f := sdf.eval_sdf_full(u, y_cur, s, ov_h)
		if prev_f < 0.0 and cur_f >= 0.0:
			var lo := y_cur
			var hi := y_prev
			for _b in 5:
				var mid := 0.5 * (lo + hi)
				if sdf.eval_sdf_full(u, mid, s, ov_h) >= 0.0:
					lo = mid
				else:
					hi = mid
			return 0.5 * (lo + hi)
		y_prev = y_cur
		prev_f = cur_f
		y_cur -= 0.5
	return ov_h


# ==============================================================================
# P2: KITBASHED BOULDERS, ENTRANCE BROW TREE & FALLEN MOUND DEADWOOD LOG
# ==============================================================================

static var _extracted_mesh_cache: Dictionary = {}
static var _cached_rock_convex_shapes: Array[ConvexPolygonShape3D] = []
static var _cached_rock_meshes: Array[Mesh] = []


func _load_rock_meshes() -> Array[Mesh]:
	if not _cached_rock_meshes.is_empty():
		return _cached_rock_meshes

	var rock_mat := StandardMaterial3D.new()
	var rock_tex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
	if rock_tex != null:
		rock_mat.albedo_texture = rock_tex
	rock_mat.albedo_color = Color(0.84, 0.82, 0.78)
	rock_mat.roughness = 0.92
	rock_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	rock_mat.cull_mode = BaseMaterial3D.CULL_BACK

	var out: Array[Mesh] = []
	for p: String in [
		"res://assets/nature/Rock_Medium_1.gltf",
		"res://assets/nature/Rock_Medium_2.gltf",
		"res://assets/nature/Rock_Medium_3.gltf",
	]:
		var sc := load(p) as PackedScene
		var found: Mesh = null
		if sc != null:
			var inst := sc.instantiate()
			for c in inst.get_children():
				if c is MeshInstance3D and c.mesh != null:
					found = c.mesh.duplicate()
					break
			inst.free()
		if found != null:
			found.surface_set_material(0, rock_mat)
		out.append(found)
	_cached_rock_meshes = out
	return out


func _build_rock_convex_shapes(rock_meshes: Array[Mesh]) -> Array[ConvexPolygonShape3D]:
	if not _cached_rock_convex_shapes.is_empty():
		return _cached_rock_convex_shapes

	var shapes: Array[ConvexPolygonShape3D] = []
	for m: Mesh in rock_meshes:
		if m != null:
			shapes.append(m.create_convex_shape(false, false))
		else:
			shapes.append(null)
	_cached_rock_convex_shapes = shapes
	return shapes


func _extract_surface_mesh(gltf_path: String, surface_indices: Array[int], mats: Array[Material]) -> Mesh:
	var key := "%s_%s" % [gltf_path, str(surface_indices)]
	if _extracted_mesh_cache.has(key):
		return _extracted_mesh_cache[key]

	var sc := load(gltf_path) as PackedScene
	if sc == null:
		return null
	var inst := sc.instantiate()
	var src: Mesh = null
	for c in inst.get_children():
		if c is MeshInstance3D and c.mesh != null:
			src = c.mesh
			break
	var out_mesh: ArrayMesh = null
	if src != null:
		out_mesh = ArrayMesh.new()
		for i in surface_indices.size():
			var si := surface_indices[i]
			if si < src.get_surface_count():
				var arr := src.surface_get_arrays(si)
				var s_idx := out_mesh.get_surface_count()
				out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				if i < mats.size() and mats[i] != null:
					out_mesh.surface_set_material(s_idx, mats[i])
	inst.free()
	_extracted_mesh_cache[key] = out_mesh
	return out_mesh


static func compute_cave_props(terrain_scene: Node3D, seed_val: int = 1337) -> Dictionary:
	var sdf := get_sdf()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 9091

	# --- 1. BOULDERS ---
	var grouped: Array[Array] = [[], [], []]
	var collider_items: Array[Dictionary] = []
	var add_boulder := func(arch: int, wp: Vector3, rot: Vector3, sc: Vector3, collide: bool) -> void:
		var b := Basis.from_euler(rot).scaled(sc)
		var xf := Transform3D(b, wp)
		grouped[arch % 3].append(xf)
		if collide:
			collider_items.append({"arch": arch % 3, "xf": xf})

	var mouth_boulders := [
		[Vector3(-7.6, 0.0, -3.5), 1.9, true],
		[Vector3(-10.5, 0.0, -6.5), 1.7, true],
		[Vector3(-12.2, 0.0, -3.2), 2.1, true],
		[Vector3(-8.4, 0.0, -7.2), 1.4, true],
		[Vector3(7.6, 0.0, -3.8), 1.9, true],
		[Vector3(10.5, 0.0, -6.5), 1.7, true],
		[Vector3(12.2, 0.0, -2.8), 2.1, true],
		[Vector3(8.2, 0.0, -7.4), 1.3, true],
	]
	for idx in mouth_boulders.size():
		var item: Array = mouth_boulders[idx]
		var loc: Vector3 = item[0]
		var sc_base: float = float(item[1])
		var w_xz := CaveLayout.to_world(loc)
		var gy := _sample_exterior_sdf_y(sdf, terrain_scene, loc.x, loc.z)
		if gy < 23.0 or gy > 32.0:
			continue
		var arch := idx % 3
		var sx := sc_base * rng.randf_range(0.95, 1.25)
		var sy := sc_base * rng.randf_range(0.75, 1.02)
		var sz := sc_base * rng.randf_range(0.95, 1.25)
		var rot := Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))
		add_boulder.call(arch, Vector3(w_xz.x, gy - 0.65 * sy, w_xz.z), rot, Vector3(sx, sy, sz), bool(item[2]))

	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	var rim_angles := [0.65, 1.35, 2.10, 2.85, 3.60, 4.35, 5.10]
	for idx in rim_angles.size():
		var ang: float = rim_angles[idx]
		var r := rng.randf_range(9.2, 12.2)
		var lu := sky_c.x + cos(ang) * r
		var ls := sky_c.z + sin(ang) * r
		if not _is_clear_of_all_routes(lu, ls, 2.6):
			continue
		var w_xz := CaveLayout.to_world(Vector3(lu, 56.0, ls))
		var gy := _sample_exterior_sdf_y(sdf, terrain_scene, lu, ls)
		if gy < 52.0 or gy > 61.0:
			continue
		var sc_base := rng.randf_range(1.2, 1.9)
		add_boulder.call(
			idx % 3,
			Vector3(w_xz.x, gy - 0.58 * sc_base, w_xz.z),
			Vector3(rng.randf_range(-0.16, 0.16), rng.randf_range(0.0, TAU), rng.randf_range(-0.16, 0.16)),
			Vector3(sc_base * 1.15, sc_base * 0.8, sc_base),
			true
		)

	var hall_blocks := [
		[-64.5, 67.0, 1.5], [-68.0, 65.5, 1.7], [-66.5, 72.5, 1.8], [-62.0, 74.5, 1.4],
		[-70.5, 69.0, 2.0], [-72.0, 64.0, 1.6], [-59.0, 75.5, 1.3],
		[-38.5, 44.5, 1.3], [-36.5, 37.5, 1.2], [-27.5, 37.0, 1.2],
	]
	for idx in hall_blocks.size():
		var b_arr: Array = hall_blocks[idx]
		var lu: float = float(b_arr[0])
		var ls: float = float(b_arr[1])
		if not _is_clear_of_all_routes(lu, ls, 2.6):
			continue
		var fy := _sample_floor_y(sdf, lu, 25.0, ls)
		var sc_base: float = float(b_arr[2])
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.35 * sc_base, ls))
		add_boulder.call(
			(idx + 1) % 3,
			wp,
			Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0.0, TAU), rng.randf_range(-0.22, 0.22)),
			Vector3(sc_base * 1.15, sc_base * 0.85, sc_base),
			true
		)

	var brow_loc := Vector3(-11.2, 40.0, 5.2)
	var brow_w := CaveLayout.to_world(brow_loc)
	var brow_y := _sample_exterior_sdf_y(sdf, terrain_scene, brow_loc.x, brow_loc.z)
	var bt_basis := Basis.from_euler(Vector3(0.08, 0.55, -0.22)).scaled(Vector3(2.25, 2.35, 2.25))
	var brow_tree_xf := Transform3D(bt_basis, Vector3(brow_w.x, brow_y - 0.85, brow_w.z))

	var log_base_u := -65.5
	var log_base_s := 71.2
	var log_fy := _sample_floor_y(sdf, log_base_u, 25.0, log_base_s)
	var log_wp := CaveLayout.to_world(Vector3(log_base_u, log_fy + 0.55, log_base_s))
	var log_basis := Basis.from_euler(Vector3(1.42, 0.65, 0.14)).scaled(Vector3(1.95, 2.05, 1.95))
	var fallen_log_xf := Transform3D(log_basis, log_wp)
	var trunk_dir := (log_basis.y).normalized()
	var log_cs_xf := Transform3D(log_basis.orthonormalized(), log_wp + trunk_dir * 3.1)

	# --- 2. CRYSTALS ---
	var crystal_xforms: Array[Transform3D] = []
	var crystal_colors: Array[Color] = []
	var palette := [
		Color(0.24, 0.90, 1.0),
		Color(0.38, 0.62, 1.0),
		Color(0.68, 0.44, 1.0),
		Color(0.52, 0.98, 0.94),
	]
	var gc: Vector3 = CaveLayout.CHAMBERS["geode_pocket"]["c"]
	var seed_pt := Vector3(gc.x, gc.y + 2.2, gc.z)
	for _c in 28:
		var az := rng.randf() * TAU
		var el := rng.randf_range(-0.22, 0.14)
		var d_loc := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)).normalized()
		var r_hit := -1.0
		var r_cur := 3.5
		var prev_d := sdf.eval_sdf_full(seed_pt.x + d_loc.x * r_cur, seed_pt.y + d_loc.y * r_cur, seed_pt.z + d_loc.z * r_cur, GEOFENCE_OVERWORLD_H)
		while r_cur < 11.5:
			r_cur += 0.45
			var hp := seed_pt + d_loc * r_cur
			var cur_d := sdf.eval_sdf_full(hp.x, hp.y, hp.z, GEOFENCE_OVERWORLD_H)
			if prev_d < 0.0 and cur_d >= 0.0:
				r_hit = r_cur - 0.15
				break
			prev_d = cur_d
		if r_hit < 0.0:
			continue
		var lp := seed_pt + d_loc * r_hit
		if lp.z > 59.5 and absf(lp.x - gc.x) < 4.5:
			continue
		if lp.x < -0.5 and lp.z > 50.5 and lp.z < 59.5:
			continue
		if lp.y < gc.y + 0.6 or lp.y > gc.y + 3.4:
			continue
		var eps := 0.35
		var gx := sdf.eval_sdf_full(lp.x + eps, lp.y, lp.z, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(lp.x - eps, lp.y, lp.z, GEOFENCE_OVERWORLD_H)
		var gy := sdf.eval_sdf_full(lp.x, lp.y + eps, lp.z, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(lp.x, lp.y - eps, lp.z, GEOFENCE_OVERWORLD_H)
		var gz := sdf.eval_sdf_full(lp.x, lp.y, lp.z + eps, GEOFENCE_OVERWORLD_H) - sdf.eval_sdf_full(lp.x, lp.y, lp.z - eps, GEOFENCE_OVERWORLD_H)
		var n_loc := Vector3(-gx, -gy, -gz).normalized()
		if n_loc.length_squared() < 0.1:
			n_loc = -d_loc
		if n_loc.y < -0.05:
			continue
		var n_world := Vector3(
			CaveLayout.FWD_XZ.x * n_loc.z + CaveLayout.RIGHT_XZ.x * n_loc.x,
			maxf(n_loc.y, 0.15),
			CaveLayout.FWD_XZ.y * n_loc.z + CaveLayout.RIGHT_XZ.y * n_loc.x
		).normalized()
		var w_anchor := CaveLayout.to_world(lp - n_loc * 0.72)
		var shards := rng.randi_range(4, 6)
		var cluster_col: Color = palette[rng.randi() % palette.size()]
		for _s in shards:
			var splay := Vector3(rng.randf_range(-0.28, 0.28), rng.randf_range(0.0, 0.24), rng.randf_range(-0.28, 0.28))
			var s_dir := (n_world + splay).normalized()
			var b := _basis_align_y(s_dir, rng.randf() * TAU)
			var sc_h := rng.randf_range(1.15, 2.35)
			var sc_w := rng.randf_range(0.58, 1.05)
			b = b.scaled(Vector3(sc_w, sc_h, sc_w))
			crystal_xforms.append(Transform3D(b, w_anchor + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.12, 0.12))))
			crystal_colors.append(cluster_col)

	# Landmark guiding crystal clusters framing Collapse Hall passage mouths & Spiral Ledge route
	var landmark_clusters := [
		# Stream Grotto archway left & right pillars (aqua/cyan beacons)
		[Vector3(-46.5, 19.5, 84.5), Color(0.24, 0.92, 1.0), 1.45, 5],
		[Vector3(-38.0, 19.5, 86.5), Color(0.32, 0.84, 1.0), 1.35, 4],
		# Spiral Ledge trailhead & upper ledge waypoints (violet/amethyst beacons)
		[Vector3(-68.5, 21.5, 82.0), Color(0.68, 0.46, 1.0), 1.40, 5],
		[Vector3(-76.5, 25.0, 74.5), Color(0.64, 0.50, 1.0), 1.25, 4],
		[Vector3(-74.0, 31.0, 56.5), Color(0.52, 0.72, 1.0), 1.25, 4],
		[Vector3(-56.0, 37.5, 51.0), Color(0.38, 0.88, 1.0), 1.25, 4],
		# Deep Descent archway flank (deep blue/cyan beacon)
		[Vector3(-71.5, 19.5, 87.5), Color(0.30, 0.78, 1.0), 1.50, 5],
		# Split-Slime Crawlway mouth teaser crystals (warm violet/cyan)
		[Vector3(-29.5, 19.2, 43.2), Color(0.68, 0.44, 1.0), 0.95, 4],
	]
	for lc_item: Array in landmark_clusters:
		var lpos: Vector3 = lc_item[0]
		var lcol: Color = lc_item[1]
		var lscale: float = float(lc_item[2])
		var lcnt: int = int(lc_item[3])
		var fy_c := _sample_floor_y(sdf, lpos.x, lpos.y + 3.0, lpos.z)
		var w_base := CaveLayout.to_world(Vector3(lpos.x, fy_c - 0.12, lpos.z))
		for s_idx in lcnt:
			var ang_c := (float(s_idx) / float(lcnt)) * TAU + rng.randf_range(-0.25, 0.25)
			var tilt_c := rng.randf_range(0.18, 0.48)
			var dir_c := Vector3(cos(ang_c) * sin(tilt_c), cos(tilt_c), sin(ang_c) * sin(tilt_c)).normalized()
			var b_c := _basis_align_y(dir_c, rng.randf() * TAU)
			var sh := lscale * rng.randf_range(0.85, 1.35)
			var sw := sh * rng.randf_range(0.45, 0.62)
			b_c = b_c.scaled(Vector3(sw, sh, sw))
			var off_xz := Vector3(cos(ang_c) * 0.28, 0.0, sin(ang_c) * 0.28)
			crystal_xforms.append(Transform3D(b_c, w_base + off_xz))
			crystal_colors.append(lcol)

	# --- 3. PEBBLES ---
	var pebble_xforms: Array[Transform3D] = []
	var pool_c: Vector3 = CaveLayout.POOL["c"]
	var rx: float = float(CaveLayout.POOL["rx"])
	var rz: float = float(CaveLayout.POOL["rz"])
	for _i in 85:
		var ang := rng.randf() * TAU
		var rr := rng.randf_range(0.72, 1.15)
		var lu := pool_c.x + cos(ang) * rx * rr
		var ls := pool_c.z + sin(ang) * rz * rr
		var fy := _sample_floor_y(sdf, lu, 21.0, ls)
		if fy > 19.3:
			continue
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.02, ls))
		var scv := rng.randf_range(0.85, 2.35)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))).scaled(Vector3(scv, scv * 0.85, scv))
		pebble_xforms.append(Transform3D(b, wp))

	var grotto_nodes: Array = CaveLayout.TUNNELS["stream_grotto"]
	for i in range(grotto_nodes.size() - 1):
		var pa: Vector3 = grotto_nodes[i]["p"]
		var pb: Vector3 = grotto_nodes[i + 1]["p"]
		for _k in 24:
			var t := rng.randf()
			var p := pa.lerp(pb, t)
			var lu := p.x + rng.randf_range(-2.8, 2.8)
			var ls := p.z + rng.randf_range(-2.8, 2.8)
			var fy := _sample_floor_y(sdf, lu, p.y + 2.0, ls)
			if absf(fy - p.y) > 1.8:
				continue
			var wp := CaveLayout.to_world(Vector3(lu, fy - 0.02, ls))
			var scv := rng.randf_range(0.80, 2.15)
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))).scaled(Vector3(scv, scv * 0.85, scv))
			pebble_xforms.append(Transform3D(b, wp))

	# --- 4. SPELEOTHEMS ---
	var speleo_xforms: Array[Transform3D] = []
	var stalagmites: Array[Dictionary] = []
	var zones := [
		[-12.0, 27.0, 5.5, 10],
		[-49.0, 88.0, 9.5, 16],
		[-78.0, 72.0, 10.0, 14],
		[-22.0, 99.0, 4.5, 12],
	]
	for z_arr: Array in zones:
		var cu: float = float(z_arr[0])
		var cs: float = float(z_arr[1])
		var rad: float = float(z_arr[2])
		var cnt: int = int(z_arr[3])
		for _i in cnt:
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(rad * 0.45, rad)
			var lu := cu + cos(ang) * dist
			var ls := cs + sin(ang) * dist
			if Vector2(lu + 62.0, ls - 68.0).length() < 9.5:
				continue
			if sdf.eval_cave_void_smooth(lu, 22.0, ls) > -0.35:
				continue
			var cy := _sample_ceiling_y(sdf, lu, 22.0, ls, 49.0)
			if cy > 47.0 or cy < 22.5:
				continue
			var fy := _sample_floor_y(sdf, lu, 22.0, ls)
			var gap := cy - fy
			if gap < 4.5:
				continue

			var is_hero := rng.randf() < 0.16
			var len_top := rng.randf_range(3.2, 4.8) if is_hero else rng.randf_range(1.4, 3.0)
			len_top = minf(len_top, gap * 0.42)
			var w_top := len_top * rng.randf_range(0.30, 0.46)
			var b_top := Basis.from_euler(Vector3(PI, rng.randf() * TAU, 0.0)).scaled(Vector3(w_top, len_top, w_top))
			speleo_xforms.append(Transform3D(b_top, CaveLayout.to_world(Vector3(lu, cy + 0.25, ls))))

			if _is_clear_of_all_routes(lu, ls, 4.4) and Vector2(lu + 48.0, ls - 87.5).length() > 11.5:
				var len_bot := len_top * rng.randf_range(0.45, 0.78)
				var w_bot := len_bot * rng.randf_range(0.42, 0.58)
				var wp_bot := CaveLayout.to_world(Vector3(lu, fy - 0.22, ls))
				var b_bot := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).scaled(Vector3(w_bot, len_bot, w_bot))
				speleo_xforms.append(Transform3D(b_bot, wp_bot))
				stalagmites.append({
					"radius": maxf(0.45 * w_bot, 0.35),
					"height": len_bot,
					"pos": wp_bot + Vector3(0.0, len_bot * 0.5, 0.0)
				})

	# --- 5. FLORA ---
	var grass_xf: Array[Transform3D] = []
	var fern_xf: Array[Transform3D] = []
	var plant_xf: Array[Transform3D] = []
	var bush_xf: Array[Transform3D] = []
	var shelf_xf: Array[Transform3D] = []
	var grotto_mush_xf: Array[Transform3D] = []
	var mound_c: Vector3 = CaveLayout.MOUND["c"]

	for _i in 95:
		var ang := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 5.2
		var lu := mound_c.x + cos(ang) * rr
		var ls := mound_c.z + sin(ang) * rr
		if ls < 62.0 or ls > 72.5 or Vector2(lu - pool_c.x, ls - pool_c.z).length() < 12.2:
			continue
		if Vector2(lu - CaveLayout.SPAWN.x, ls - CaveLayout.SPAWN.z).length() < 2.2:
			continue
		var fy := _sample_floor_y(sdf, lu, 26.0, ls)
		if fy < 19.5 or fy > 25.0:
			continue
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.06, ls))
		var sc := rng.randf_range(0.45, 0.72) * (1.0 - 0.35 * smoothstep(3.0, 5.2, rr))
		grass_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * rng.randf_range(0.55, 0.78), sc)), wp))

	for _i in 44:
		var ang := rng.randf() * TAU
		var rr := rng.randf_range(1.6, 10.8)
		var lu := mound_c.x + cos(ang) * rr
		var ls := mound_c.z + sin(ang) * rr
		if Vector2(lu - CaveLayout.SPAWN.x, ls - CaveLayout.SPAWN.z).length() < 2.8:
			continue
		if _dist_to_segment_2d(Vector2(lu, ls), Vector2(-60.2, 57.0), Vector2(-55.5, 63.5)) < 3.5:
			continue
		if _dist_to_segment_2d(Vector2(lu, ls), Vector2(-59.5, 73.5), Vector2(-53.5, 81.5)) < 4.2:
			continue
		if ls < 59.5 or ls > 74.5 or Vector2(lu - pool_c.x, ls - pool_c.z).length() < 12.2:
			continue
		var fy := _sample_floor_y(sdf, lu, 26.0, ls)
		if fy < 19.2:
			continue
		var wp := CaveLayout.to_world(Vector3(lu, fy - 0.06, ls))
		if rng.randf() < 0.56:
			var fsc := rng.randf_range(0.30, 0.48)
			fern_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))).scaled(Vector3(fsc, fsc, fsc)), wp))
		else:
			var psc := rng.randf_range(0.85, 1.35)
			plant_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(psc, psc, psc)), wp))

	var bush_spots := [
		Vector3(-68.0, 22.0, 71.0), Vector3(-69.5, 22.0, 63.5), Vector3(-63.5, 21.0, 75.5),
	]
	for bpt: Vector3 in bush_spots:
		var fy := _sample_floor_y(sdf, bpt.x, bpt.y + 2.0, bpt.z)
		var bsc := rng.randf_range(0.85, 1.35)
		bush_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(bsc, bsc, bsc)), CaveLayout.to_world(Vector3(bpt.x, fy - 0.08, bpt.z))))

	for _i in 65:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var lu := side * rng.randf_range(3.5, 8.2)
		var ls := rng.randf_range(-9.5, -4.8)
		var w_xz := CaveLayout.to_world(Vector3(lu, 26.0, ls))
		var fy := _sample_exterior_sdf_y(sdf, terrain_scene, lu, ls)
		if fy < 25.0 or fy > 27.2:
			continue
		var gsc := rng.randf_range(0.85, 1.30)
		grass_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(gsc, gsc, gsc)), Vector3(w_xz.x, fy - 0.04, w_xz.z)))
		if rng.randf() < 0.16:
			var fsc := rng.randf_range(0.28, 0.42)
			fern_xf.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(fsc, fsc, fsc)), Vector3(w_xz.x, fy - 0.05, w_xz.z)))

	if fallen_log_xf != Transform3D.IDENTITY:
		var trunk_axis := fallen_log_xf.basis.y.normalized()
		var trunk_origin := fallen_log_xf.origin
		for _i in 8:
			var d_along := rng.randf_range(1.2, 5.6)
			var ang := rng.randf_range(-0.9, 0.9)
			var outward := (fallen_log_xf.basis.x.normalized() * cos(ang) + Vector3.UP * sin(ang) * 0.4 + Vector3.UP * 0.4).normalized()
			var pos := trunk_origin + trunk_axis * d_along + outward * 0.42
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15)))
			var sc := rng.randf_range(0.75, 1.30)
			shelf_xf.append(Transform3D(b.scaled(Vector3(sc, sc, sc)), pos))

	for i in range(grotto_nodes.size() - 1):
		var pa: Vector3 = grotto_nodes[i]["p"]
		var pb: Vector3 = grotto_nodes[i + 1]["p"]
		var dir2 := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
		var right2 := Vector2(-dir2.y, dir2.x)
		for _c in 9:
			var t := rng.randf()
			var p := pa.lerp(pb, t)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var bank_dist := rng.randf_range(1.9, 4.1) * side
			var lu := p.x + right2.x * bank_dist + rng.randf_range(-0.6, 0.6)
			var ls := p.z + right2.y * bank_dist + rng.randf_range(-0.6, 0.6)
			if sdf.eval_cave_void_smooth(lu, p.y + 1.2, ls) > -0.1:
				continue
			var fy := _sample_floor_y(sdf, lu, p.y + 2.5, ls)
			if absf(fy - p.y) > 1.8:
				continue
			var msc := rng.randf_range(0.85, 1.65)
			grotto_mush_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))).scaled(Vector3(msc, msc * rng.randf_range(0.9, 1.25), msc)), CaveLayout.to_world(Vector3(lu, fy - 0.04, ls))))

	var lake_c_mush: Vector3 = CaveLayout.UNDERGROUND_LAKE["c"]
	var lake_rx_mush: float = float(CaveLayout.UNDERGROUND_LAKE["rx"])
	var lake_rz_mush: float = float(CaveLayout.UNDERGROUND_LAKE["rz"])
	for _m in 32:
		var th := rng.randf() * TAU
		var rr := rng.randf_range(0.95, 1.22)
		var lu := lake_c_mush.x + cos(th) * lake_rx_mush * rr
		var ls := lake_c_mush.z + sin(th) * lake_rz_mush * rr
		if sdf.eval_cave_void_smooth(lu, 8.5, ls) > -0.1:
			continue
		var fy := _sample_floor_y(sdf, lu, 10.5, ls)
		if fy < 7.5 or fy > 11.5:
			continue
		var msc := rng.randf_range(1.1, 2.0)
		grotto_mush_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))).scaled(Vector3(msc, msc * rng.randf_range(0.9, 1.3), msc)), CaveLayout.to_world(Vector3(lu, fy - 0.04, ls))))

	return {
		"boulders": {
			"grouped": grouped,
			"collider_items": collider_items,
			"brow_tree_xf": brow_tree_xf,
			"fallen_log_xf": fallen_log_xf,
			"log_cs_xf": log_cs_xf,
		},
		"crystals": {
			"xforms": crystal_xforms,
			"colors": crystal_colors,
		},
		"pebbles": {
			"xforms": pebble_xforms,
		},
		"speleothems": {
			"xforms": speleo_xforms,
			"stalagmites": stalagmites,
		},
		"flora": {
			"grass_xf": grass_xf,
			"fern_xf": fern_xf,
			"plant_xf": plant_xf,
			"bush_xf": bush_xf,
			"shelf_xf": shelf_xf,
			"grotto_mush_xf": grotto_mush_xf,
		}
	}


func _build_boulders_and_trees(
	terrain_scene: Node3D,
	boulder_body: StaticBody3D,
	rock_meshes: Array[Mesh],
	rock_shapes: Array[ConvexPolygonShape3D],
	_rng: RandomNumberGenerator = null,
	props_data: Dictionary = {}
) -> Transform3D:
	if props_data.is_empty():
		props_data = _load_or_compute_props(terrain_scene)
	var b_data: Dictionary = props_data.get("boulders", {})
	var grouped: Array = b_data.get("grouped", [[], [], []])
	var collider_items: Array = b_data.get("collider_items", [])
	var brow_tree_xf: Transform3D = b_data.get("brow_tree_xf", Transform3D.IDENTITY)
	var fallen_log_xf: Transform3D = b_data.get("fallen_log_xf", Transform3D.IDENTITY)
	var log_cs_xf: Transform3D = b_data.get("log_cs_xf", Transform3D.IDENTITY)

	var holder := Node3D.new()
	holder.name = "CaveBoulders"
	add_child(holder)

	for a in 3:
		var m: Mesh = rock_meshes[a] if a < rock_meshes.size() else null
		var xforms: Array = grouped[a] if a < grouped.size() else []
		if m == null or xforms.is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "CaveRock%d" % (a + 1)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] as Transform3D)
		mmi.multimesh = mm
		holder.add_child(mmi)

	if boulder_body != null:
		for c_item: Dictionary in collider_items:
			var arch: int = int(c_item["arch"])
			var conv: ConvexPolygonShape3D = rock_shapes[arch] if arch < rock_shapes.size() else null
			if conv != null:
				var cs := CollisionShape3D.new()
				cs.shape = conv
				cs.transform = c_item["xf"] as Transform3D
				boulder_body.add_child(cs)

	var bark_mat := StandardMaterial3D.new()
	bark_mat.albedo_texture = load("res://assets/nature/Bark_NormalTree.png") as Texture2D
	bark_mat.normal_enabled = true
	bark_mat.normal_texture = load("res://assets/nature/Bark_NormalTree_Normal.png") as Texture2D
	bark_mat.roughness = 0.92
	bark_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_texture = load("res://assets/nature/Leaves_NormalTree_C.png") as Texture2D
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_mat.alpha_scissor_threshold = 0.45
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.roughness = 0.85
	leaf_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var brow_tree_mesh := _extract_surface_mesh("res://assets/nature/CommonTree_1.gltf", [0, 1], [bark_mat, leaf_mat])
	if brow_tree_mesh != null and brow_tree_xf != Transform3D.IDENTITY:
		var bt := MeshInstance3D.new()
		bt.name = "EntranceBrowTree"
		bt.mesh = brow_tree_mesh
		bt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		bt.transform = brow_tree_xf
		holder.add_child(bt)

	var dead_bark_mat := bark_mat.duplicate() as StandardMaterial3D
	dead_bark_mat.albedo_color = Color(0.76, 0.72, 0.66)
	var dead_trunk_mesh := _extract_surface_mesh("res://assets/nature/CommonTree_1.gltf", [0], [dead_bark_mat])
	if dead_trunk_mesh != null and fallen_log_xf != Transform3D.IDENTITY:
		var log_mi := MeshInstance3D.new()
		log_mi.name = "FallenDeadwoodLog"
		log_mi.mesh = dead_trunk_mesh
		log_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		log_mi.transform = fallen_log_xf
		holder.add_child(log_mi)

		if boulder_body != null and log_cs_xf != Transform3D.IDENTITY:
			var log_cs := CollisionShape3D.new()
			var log_cap := CapsuleShape3D.new()
			log_cap.radius = 0.68
			log_cap.height = 6.2
			log_cs.shape = log_cap
			log_cs.transform = log_cs_xf
			boulder_body.add_child(log_cs)

	return fallen_log_xf


# ==============================================================================
# P3: SUNBEAM SHAFTS, DUST MOTES & WAITOMO GLOWWORMS
# ==============================================================================

func _build_skylight_beams_and_dust() -> void:
	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	var mound_c: Vector3 = CaveLayout.MOUND["c"]
	var p_top := CaveLayout.to_world(Vector3(sky_c.x + 1.5, 55.8, sky_c.z - 1.5))
	var p_bot := CaveLayout.to_world(Vector3(mound_c.x, 19.6, mound_c.z))

	var beam_shader := load("res://terrain/cave_sunbeam.gdshader") as Shader
	if beam_shader != null:
		var specs := [
			[5.0, 10.6, 0.14, Color(1.0, 0.93, 0.74)],
			[3.4, 7.2, 0.18, Color(1.0, 0.94, 0.78)],
			[1.9, 4.0, 0.22, Color(1.0, 0.96, 0.84)],
		]
		var beams := Node3D.new()
		beams.name = "SkylightBeams"
		add_child(beams)
		var dir := (p_bot - p_top)
		var h_len := dir.length()
		var up_a := -dir.normalized()
		var ref := Vector3.FORWARD if absf(up_a.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var rt := ref.cross(up_a).normalized()
		var fw := up_a.cross(rt).normalized()

		for idx in specs.size():
			var sp: Array = specs[idx]
			var r_top: float = float(sp[0])
			var r_bot: float = float(sp[1])
			var segs := 18
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in segs:
				var a0 := (float(i) / float(segs)) * TAU
				var a1 := (float(i + 1) / float(segs)) * TAU
				var vt0 := Vector3(cos(a0) * r_top, 0.0, sin(a0) * r_top)
				var vt1 := Vector3(cos(a1) * r_top, 0.0, sin(a1) * r_top)
				var vb0 := Vector3(cos(a0) * r_bot, -h_len, sin(a0) * r_bot)
				var vb1 := Vector3(cos(a1) * r_bot, -h_len, sin(a1) * r_bot)
				var n0 := Vector3(cos(a0), 0.15, sin(a0)).normalized()
				var n1 := Vector3(cos(a1), 0.15, sin(a1)).normalized()

				st.set_normal(n0); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(vt0)
				st.set_normal(n1); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(vt1)
				st.set_normal(n1); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(vb1)

				st.set_normal(n0); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(vt0)
				st.set_normal(n1); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(vb1)
				st.set_normal(n0); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(vb0)

			var mi := MeshInstance3D.new()
			mi.name = "SunbeamCone%d" % idx
			mi.mesh = st.commit()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = beam_shader
			mat.set_shader_parameter("beam_color", sp[3] as Color)
			mat.set_shader_parameter("beam_intensity", float(sp[2]))
			mi.material_override = mat
			mi.transform = Transform3D(Basis(rt, up_a, fw), p_top)
			beams.add_child(mi)


# ==============================================================================
# P4: FACETED GEODE CRYSTALS
# ==============================================================================

func _build_crystal_mesh() -> ArrayMesh:
	if _cached_crystal_mesh != null:
		return _cached_crystal_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var r0 := 0.24
	var r1 := 0.17
	var h_shaft := 0.85
	var h_tip := 1.22
	var apex := Vector3(0.0, h_tip, 0.0)

	for i in sides:
		var a0 := (float(i) / float(sides)) * TAU
		var a1 := (float(i + 1) / float(sides)) * TAU
		var amid := 0.5 * (a0 + a1)
		var b0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var u0 := Vector3(cos(a0) * r1, h_shaft, sin(a0) * r1)
		var u1 := Vector3(cos(a1) * r1, h_shaft, sin(a1) * r1)
		var n_side := Vector3(cos(amid), 0.10, sin(amid)).normalized()
		var n_pyr := Vector3(cos(amid), 0.72, sin(amid)).normalized()

		st.set_normal(n_side); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(b0)
		st.set_normal(n_side); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(b1)
		st.set_normal(n_side); st.set_uv(Vector2(1.0, 0.72)); st.add_vertex(u1)

		st.set_normal(n_side); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(b0)
		st.set_normal(n_side); st.set_uv(Vector2(1.0, 0.72)); st.add_vertex(u1)
		st.set_normal(n_side); st.set_uv(Vector2(0.0, 0.72)); st.add_vertex(u0)

		st.set_normal(n_pyr); st.set_uv(Vector2(0.0, 0.72)); st.add_vertex(u0)
		st.set_normal(n_pyr); st.set_uv(Vector2(1.0, 0.72)); st.add_vertex(u1)
		st.set_normal(n_pyr); st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(apex)

	_cached_crystal_mesh = st.commit()
	var cmat := ShaderMaterial.new()
	cmat.shader = load("res://terrain/cave_crystal.gdshader") as Shader
	_cached_crystal_mesh.surface_set_material(0, cmat)
	return _cached_crystal_mesh


static func _basis_align_y(up_dir: Vector3, twist: float) -> Basis:
	var y := up_dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z).rotated(y, twist)


func _build_crystals(_rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	if props_data.is_empty():
		props_data = _load_or_compute_props(null)
	var c_data: Dictionary = props_data.get("crystals", {})
	var xforms: Array = c_data.get("xforms", [])
	var colors: Array = c_data.get("colors", [])
	if xforms.is_empty():
		return

	var cmesh := _build_crystal_mesh()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CaveCrystals"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cmesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] as Transform3D)
		mm.set_instance_color(i, colors[i] as Color)
	mmi.multimesh = mm
	add_child(mmi)


# ==============================================================================
# P5: WATER BASIN POOL, DRIP WATERFALL + SPLASH, OUTFLOW STREAM, PEBBLES,
#     SPELEOTHEMS & STRICTLY ZERO-COLLISION ECOLOGICAL CAVE FLORA
# ==============================================================================

func _build_water_features() -> void:
	var holder := Node3D.new()
	holder.name = "CaveWater"
	add_child(holder)

	var water_shader := load("res://terrain/cave_water.gdshader") as Shader
	if water_shader == null:
		return

	var wf_world := CaveLayout.to_world(CaveLayout.WATERFALL)
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = water_shader
	pool_mat.set_shader_parameter("is_waterfall", false)
	pool_mat.set_shader_parameter("waterfall_impact_world", wf_world)

	var wf_mat := ShaderMaterial.new()
	wf_mat.shader = water_shader
	wf_mat.set_shader_parameter("is_waterfall", true)

	var lake_mat := pool_mat.duplicate() as ShaderMaterial
	lake_mat.set_shader_parameter("shallow_color", Vector3(0.10, 0.48, 0.55))
	lake_mat.set_shader_parameter("deep_color", Vector3(0.02, 0.08, 0.18))
	lake_mat.set_shader_parameter("foam_color", Vector3(0.72, 0.92, 1.0))

	if _cached_water_meshes.has("pool"):
		var p_mi := MeshInstance3D.new()
		p_mi.name = "PoolWater"
		p_mi.mesh = _cached_water_meshes["pool"]
		p_mi.material_override = pool_mat
		p_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(p_mi)

		var l_mi := MeshInstance3D.new()
		l_mi.name = "UndergroundLakeWater"
		l_mi.mesh = _cached_water_meshes["lake"]
		l_mi.material_override = lake_mat
		l_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(l_mi)

		var s_mi := MeshInstance3D.new()
		s_mi.name = "StreamWater"
		s_mi.mesh = _cached_water_meshes["stream"]
		s_mi.material_override = pool_mat
		s_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(s_mi)

		var w_mi := MeshInstance3D.new()
		w_mi.name = "WaterfallRibbon"
		w_mi.mesh = _cached_water_meshes["waterfall"]
		w_mi.material_override = wf_mat
		w_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(w_mi)
		return

	# 1. Carved Pool Water Surface
	var pool_c: Vector3 = CaveLayout.POOL["c"]
	var pool_y: float = float(CaveLayout.POOL["water_y"])
	var rx: float = float(CaveLayout.POOL["rx"]) + 0.35
	var rz: float = float(CaveLayout.POOL["rz"]) + 0.35
	var rings := 22
	var segs := 64

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_verts: Array[Array] = []
	for ir in range(rings + 1):
		var rt := float(ir) / float(rings)
		var arr_row: Array = []
		for iseg in range(segs + 1):
			var th := (float(iseg) / float(segs)) * TAU
			var lp := Vector3(pool_c.x + cos(th) * rx * rt, pool_y, pool_c.z + sin(th) * rz * rt)
			var wp := CaveLayout.to_world(lp)
			var r_col := clampf(1.0 - rt, 0.0, 1.0)
			arr_row.append({"pos": wp, "uv": Vector2(rt * cos(th) * 0.5 + 0.5, rt * sin(th) * 0.5 + 0.5), "col": Color(r_col, 0.0, 0.0, 1.0)})
		ring_verts.append(arr_row)

	for ir in rings:
		for iseg in segs:
			var a: Dictionary = ring_verts[ir][iseg]
			var b: Dictionary = ring_verts[ir][iseg + 1]
			var c: Dictionary = ring_verts[ir + 1][iseg + 1]
			var d: Dictionary = ring_verts[ir + 1][iseg]
			st.set_normal(Vector3.UP); st.set_color(a["col"]); st.set_uv(a["uv"]); st.add_vertex(a["pos"])
			st.set_normal(Vector3.UP); st.set_color(b["col"]); st.set_uv(b["uv"]); st.add_vertex(b["pos"])
			st.set_normal(Vector3.UP); st.set_color(c["col"]); st.set_uv(c["uv"]); st.add_vertex(c["pos"])
			st.set_normal(Vector3.UP); st.set_color(a["col"]); st.set_uv(a["uv"]); st.add_vertex(a["pos"])
			st.set_normal(Vector3.UP); st.set_color(c["col"]); st.set_uv(c["uv"]); st.add_vertex(c["pos"])
			st.set_normal(Vector3.UP); st.set_color(d["col"]); st.set_uv(d["uv"]); st.add_vertex(d["pos"])

	var pool_mi := MeshInstance3D.new()
	pool_mi.name = "PoolWater"
	pool_mi.mesh = st.commit()
	_cached_water_meshes["pool"] = pool_mi.mesh
	pool_mi.material_override = pool_mat
	pool_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(pool_mi)

	# 1b. Big Subterranean Lake Water Surface
	var lake_c: Vector3 = CaveLayout.UNDERGROUND_LAKE["c"]
	var lake_y: float = float(CaveLayout.UNDERGROUND_LAKE["water_y"])
	var l_rx: float = float(CaveLayout.UNDERGROUND_LAKE["rx"]) + 0.5
	var l_rz: float = float(CaveLayout.UNDERGROUND_LAKE["rz"]) + 0.5
	var l_rings := 24
	var l_segs := 64

	lake_mat = pool_mat.duplicate() as ShaderMaterial
	lake_mat.set_shader_parameter("shallow_color", Vector3(0.10, 0.48, 0.55))
	lake_mat.set_shader_parameter("deep_color", Vector3(0.02, 0.08, 0.18))
	lake_mat.set_shader_parameter("foam_color", Vector3(0.72, 0.92, 1.0))

	var st_lake := SurfaceTool.new()
	st_lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lake_ring_verts: Array[Array] = []
	for ir in range(l_rings + 1):
		var rt := float(ir) / float(l_rings)
		var arr_row: Array = []
		for iseg in range(l_segs + 1):
			var th := (float(iseg) / float(l_segs)) * TAU
			var lp := Vector3(lake_c.x + cos(th) * l_rx * rt, lake_y, lake_c.z + sin(th) * l_rz * rt)
			var wp := CaveLayout.to_world(lp)
			var r_col := clampf(1.0 - rt, 0.0, 1.0)
			arr_row.append({"pos": wp, "uv": Vector2(rt * cos(th) * 0.5 + 0.5, rt * sin(th) * 0.5 + 0.5), "col": Color(r_col, 0.0, 0.0, 1.0)})
		lake_ring_verts.append(arr_row)

	for ir in l_rings:
		for iseg in l_segs:
			var a: Dictionary = lake_ring_verts[ir][iseg]
			var b: Dictionary = lake_ring_verts[ir][iseg + 1]
			var c: Dictionary = lake_ring_verts[ir + 1][iseg + 1]
			var d: Dictionary = lake_ring_verts[ir + 1][iseg]
			st_lake.set_normal(Vector3.UP); st_lake.set_color(a["col"]); st_lake.set_uv(a["uv"]); st_lake.add_vertex(a["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(b["col"]); st_lake.set_uv(b["uv"]); st_lake.add_vertex(b["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(c["col"]); st_lake.set_uv(c["uv"]); st_lake.add_vertex(c["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(a["col"]); st_lake.set_uv(a["uv"]); st_lake.add_vertex(a["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(c["col"]); st_lake.set_uv(c["uv"]); st_lake.add_vertex(c["pos"])
			st_lake.set_normal(Vector3.UP); st_lake.set_color(d["col"]); st_lake.set_uv(d["uv"]); st_lake.add_vertex(d["pos"])

	var lake_mi := MeshInstance3D.new()
	lake_mi.name = "UndergroundLakeWater"
	lake_mi.mesh = st_lake.commit()
	_cached_water_meshes["lake"] = lake_mi.mesh
	lake_mi.material_override = lake_mat
	lake_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(lake_mi)

	# 2. Outflow Stream Ribbon following actual baked SDF Stream Grotto riverbed (smooth Catmull-Rom curve)
	var sdf := get_sdf()
	var s_ctrl: Array[Vector3] = [
		Vector3(-44.0, 17.85, 88.5),
		Vector3(-39.5, 17.65, 92.2),
		Vector3(-35.0, 17.35, 95.0),
		Vector3(-27.5, 17.08, 98.2),
		Vector3(-20.0, 16.82, 99.5),
		Vector3(-13.0, 16.52, 96.2),
		Vector3(-7.0, 16.25, 92.5),
		Vector3(-2.8, 15.92, 85.2),
		Vector3(0.5, 15.62, 78.0),
		Vector3(1.5, 15.32, 70.0),
		Vector3(1.8, 15.12, 63.5),
	]
	var s_pts: Array[Vector3] = []
	for seg_i in range(s_ctrl.size() - 1):
		var p0 := s_ctrl[maxi(seg_i - 1, 0)]
		var p1 := s_ctrl[seg_i]
		var p2 := s_ctrl[seg_i + 1]
		var p3 := s_ctrl[mini(seg_i + 2, s_ctrl.size() - 1)]
		for sub in 3:
			var st_t := float(sub) / 3.0
			s_pts.append(p1.cubic_interpolate(p2, p0, p3, st_t))
	s_pts.append(s_ctrl[s_ctrl.size() - 1])

	var st_s := SurfaceTool.new()
	st_s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := 1.28
	var rows_s: Array[Array] = []
	for i in s_pts.size():
		var p := s_pts[i]
		var dir2: Vector2
		if i == 0:
			dir2 = Vector2(s_pts[1].x - p.x, s_pts[1].z - p.z)
		elif i == s_pts.size() - 1:
			dir2 = Vector2(p.x - s_pts[i - 1].x, p.z - s_pts[i - 1].z)
		else:
			dir2 = Vector2(s_pts[i + 1].x - s_pts[i - 1].x, s_pts[i + 1].z - s_pts[i - 1].z)
		dir2 = dir2.normalized()
		var right2 := Vector2(-dir2.y, dir2.x)
		var vfrac := float(i) / float(s_pts.size() - 1)
		var center_fy := _sample_floor_y(sdf, p.x, p.y + 3.0, p.z)
		var water_center_y := center_fy + 0.22 if i > 0 else minf(p.y, center_fy + 0.35)
		var row: Array = []
		for side: float in [-1.0, -0.45, 0.0, 0.45, 1.0]:
			var off := right2 * (half_w * side)
			var y_wing := -0.40 * smoothstep(0.45, 1.0, absf(side))
			var wp := CaveLayout.to_world(Vector3(p.x + off.x, water_center_y + y_wing, p.z + off.y))
			row.append({"pos": wp, "uv": Vector2(side * 0.5 + 0.5, vfrac * 6.0), "col": Color(1.0 - absf(side), 1.0, 0.0, 1.0)})
		rows_s.append(row)

	for r_i in range(rows_s.size() - 1):
		for c_i in 4:
			var a: Dictionary = rows_s[r_i][c_i]
			var b: Dictionary = rows_s[r_i][c_i + 1]
			var c: Dictionary = rows_s[r_i + 1][c_i + 1]
			var d: Dictionary = rows_s[r_i + 1][c_i]
			st_s.set_normal(Vector3.UP); st_s.set_color(a["col"]); st_s.set_uv(a["uv"]); st_s.add_vertex(a["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(b["col"]); st_s.set_uv(b["uv"]); st_s.add_vertex(b["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(c["col"]); st_s.set_uv(c["uv"]); st_s.add_vertex(c["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(a["col"]); st_s.set_uv(a["uv"]); st_s.add_vertex(a["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(c["col"]); st_s.set_uv(c["uv"]); st_s.add_vertex(c["pos"])
			st_s.set_normal(Vector3.UP); st_s.set_color(d["col"]); st_s.set_uv(d["uv"]); st_s.add_vertex(d["pos"])

	var stream_mi := MeshInstance3D.new()
	stream_mi.name = "StreamWater"
	stream_mi.mesh = st_s.commit()
	_cached_water_meshes["stream"] = stream_mi.mesh
	stream_mi.material_override = pool_mat
	stream_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(stream_mi)

	# 3. Thin Drip Waterfall Ribbon (top embedded into back ceiling rock lip) + Soft Splash Spray
	wf_mat = ShaderMaterial.new()
	wf_mat.shader = water_shader
	wf_mat.set_shader_parameter("is_waterfall", true)

	var wf_loc := CaveLayout.WATERFALL
	var wf_ceil_y := clampf(_sample_ceiling_y(sdf, wf_loc.x, wf_loc.y + 2.0, wf_loc.z, 40.0), wf_loc.y + 8.0, 36.5)
	var st_wf := SurfaceTool.new()
	st_wf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w_segs := 6
	var h_segs := 10
	var wf_grid: Array[Array] = []
	for iy in range(h_segs + 1):
		var vt := float(iy) / float(h_segs)
		var y_cur := lerpf(wf_ceil_y + 1.4, wf_loc.y - 0.25, vt)
		var w_half := lerpf(0.45, 1.05, pow(vt, 0.7))
		var row_wf: Array = []
		for ix in range(w_segs + 1):
			var ut := float(ix) / float(w_segs)
			var u_off := (ut * 2.0 - 1.0) * w_half
			var bow := sin(ut * PI) * 0.42 + vt * 1.15 - 0.85
			var lp := Vector3(wf_loc.x + u_off, y_cur, wf_loc.z - bow)
			row_wf.append({"pos": CaveLayout.to_world(lp), "uv": Vector2(ut, vt)})
		wf_grid.append(row_wf)

	for iy in range(h_segs + 1):
		for ix in range(w_segs + 1):
			var p_left: Vector3 = wf_grid[iy][maxi(ix - 1, 0)]["pos"]
			var p_right: Vector3 = wf_grid[iy][mini(ix + 1, w_segs)]["pos"]
			var p_top: Vector3 = wf_grid[maxi(iy - 1, 0)][ix]["pos"]
			var p_bot: Vector3 = wf_grid[mini(iy + 1, h_segs)][ix]["pos"]
			var tu: Vector3 = p_right - p_left
			var tv: Vector3 = p_bot - p_top
			var nrm: Vector3 = tv.cross(tu).normalized()
			wf_grid[iy][ix]["nrm"] = nrm

	for iy in h_segs:
		for ix in w_segs:
			var a: Dictionary = wf_grid[iy][ix]
			var b: Dictionary = wf_grid[iy][ix + 1]
			var c: Dictionary = wf_grid[iy + 1][ix + 1]
			var d: Dictionary = wf_grid[iy + 1][ix]
			st_wf.set_normal(a["nrm"]); st_wf.set_uv(a["uv"]); st_wf.add_vertex(a["pos"])
			st_wf.set_normal(b["nrm"]); st_wf.set_uv(b["uv"]); st_wf.add_vertex(b["pos"])
			st_wf.set_normal(c["nrm"]); st_wf.set_uv(c["uv"]); st_wf.add_vertex(c["pos"])
			st_wf.set_normal(a["nrm"]); st_wf.set_uv(a["uv"]); st_wf.add_vertex(a["pos"])
			st_wf.set_normal(c["nrm"]); st_wf.set_uv(c["uv"]); st_wf.add_vertex(c["pos"])
			st_wf.set_normal(d["nrm"]); st_wf.set_uv(d["uv"]); st_wf.add_vertex(d["pos"])

	var wf_mi := MeshInstance3D.new()
	wf_mi.name = "WaterfallRibbon"
	wf_mi.mesh = st_wf.commit()
	_cached_water_meshes["waterfall"] = wf_mi.mesh
	wf_mi.material_override = wf_mat
	wf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(wf_mi)


func _get_pebble_mesh() -> Mesh:
	if _cached_pebble_mesh != null:
		return _cached_pebble_mesh
	var sc := load("res://assets/nature/Pebble_Round_1.gltf") as PackedScene
	if sc == null:
		return null
	var inst := sc.instantiate()
	var pmesh: Mesh = null
	for c in inst.get_children():
		if c is MeshInstance3D and c.mesh != null:
			pmesh = c.mesh.duplicate()
			break
	inst.free()
	if pmesh == null:
		return null

	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = load("res://assets/nature/PathRocks_Diffuse.png") as Texture2D
	pmat.albedo_color = Color(0.68, 0.72, 0.75)
	pmat.roughness = 0.35
	pmat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	pmat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	pmesh.surface_set_material(0, pmat)
	_cached_pebble_mesh = pmesh
	return _cached_pebble_mesh


func _build_pebbles(_rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	if props_data.is_empty():
		props_data = _load_or_compute_props(null)
	var p_data: Dictionary = props_data.get("pebbles", {})
	var xforms: Array = p_data.get("xforms", [])
	if xforms.is_empty():
		return
	var pmesh := _get_pebble_mesh()
	if pmesh == null:
		return

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CavePebbles"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pmesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] as Transform3D)
	mmi.multimesh = mm
	add_child(mmi)


func _build_speleothem_mesh() -> ArrayMesh:
	if _cached_speleothem_mesh != null:
		return _cached_speleothem_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 5
	var segs := 8
	var profile_r := [0.42, 0.34, 0.24, 0.16, 0.08, 0.02]
	var profile_y := [0.0, 0.25, 0.55, 0.80, 0.96, 1.05]
	for ir in rings:
		for iseg in segs:
			var a0 := (float(iseg) / float(segs)) * TAU
			var a1 := (float(iseg + 1) / float(segs)) * TAU
			var r0: float = float(profile_r[ir])
			var r1: float = float(profile_r[ir + 1])
			var y0: float = float(profile_y[ir])
			var y1: float = float(profile_y[ir + 1])
			var v00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var v10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var v01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var v11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var n0 := Vector3(cos(a0), 0.2, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), 0.2, sin(a1)).normalized()
			st.set_normal(n0); st.set_uv(Vector2(0, y0)); st.add_vertex(v00)
			st.set_normal(n1); st.set_uv(Vector2(1, y0)); st.add_vertex(v10)
			st.set_normal(n1); st.set_uv(Vector2(1, y1)); st.add_vertex(v11)
			st.set_normal(n0); st.set_uv(Vector2(0, y0)); st.add_vertex(v00)
			st.set_normal(n1); st.set_uv(Vector2(1, y1)); st.add_vertex(v11)
			st.set_normal(n0); st.set_uv(Vector2(0, y1)); st.add_vertex(v01)
	_cached_speleothem_mesh = st.commit()
	var smat := StandardMaterial3D.new()
	smat.albedo_texture = load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
	smat.albedo_color = Color(0.72, 0.70, 0.67)
	smat.roughness = 0.72
	smat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_cached_speleothem_mesh.surface_set_material(0, smat)
	return _cached_speleothem_mesh


func _build_speleothems(boulder_body: StaticBody3D, _rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	if props_data.is_empty():
		props_data = _load_or_compute_props(null)
	var s_data: Dictionary = props_data.get("speleothems", {})
	var xforms: Array = s_data.get("xforms", [])
	var stalagmites: Array = s_data.get("stalagmites", [])
	if xforms.is_empty():
		return
	var smesh := _build_speleothem_mesh()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CaveSpeleothems"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = smesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] as Transform3D)
	mmi.multimesh = mm
	add_child(mmi)

	if boulder_body != null:
		for col_info: Dictionary in stalagmites:
			var cs_st := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = float(col_info.get("radius", 0.4))
			cyl.height = float(col_info.get("height", 2.0))
			cs_st.shape = cyl
			cs_st.position = col_info.get("pos", Vector3.ZERO) as Vector3
			boulder_body.add_child(cs_st)


func _build_vine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	var prev_w := 0.22
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var y0 := -t0 * 1.0
		var y1 := -t1 * 1.0
		var w0 := lerpf(prev_w, 0.03, t0)
		var w1 := lerpf(prev_w, 0.03, t1)
		var x0 := sin(t0 * 4.5) * 0.05
		var x1 := sin(t1 * 4.5) * 0.05
		for ang: float in [0.0, PI * 0.5]:
			var ca := cos(ang); var sa := sin(ang)
			var d0 := Vector3(w0 * ca, 0, w0 * sa)
			var d1 := Vector3(w1 * ca, 0, w1 * sa)
			var n := Vector3(-sa, 0.0, ca)
			var a0 := Vector3(x0, y0, 0.0) - d0
			var b0 := Vector3(x0, y0, 0.0) + d0
			var a1 := Vector3(x1, y1, 0.0) - d1
			var b1 := Vector3(x1, y1, 0.0) + d1
			st.set_normal(n); st.set_uv(Vector2(0.0, t0)); st.add_vertex(a0)
			st.set_normal(n); st.set_uv(Vector2(1.0, t0)); st.add_vertex(b0)
			st.set_normal(n); st.set_uv(Vector2(1.0, t1)); st.add_vertex(b1)
			st.set_normal(n); st.set_uv(Vector2(0.0, t0)); st.add_vertex(a0)
			st.set_normal(n); st.set_uv(Vector2(1.0, t1)); st.add_vertex(b1)
			st.set_normal(n); st.set_uv(Vector2(0.0, t1)); st.add_vertex(a1)
	return st.commit()


func _build_flora(terrain_scene: Node3D, fallen_log_xf: Transform3D, _rng: RandomNumberGenerator = null, props_data: Dictionary = {}) -> void:
	var flora := Node3D.new()
	flora.name = "CaveFlora"
	add_child(flora)

	if props_data.is_empty():
		props_data = _load_or_compute_props(terrain_scene)

	var f_data: Dictionary = props_data.get("flora", {})
	var grass_xf: Array = f_data.get("grass_xf", [])
	var fern_xf: Array = f_data.get("fern_xf", [])
	var plant_xf: Array = f_data.get("plant_xf", [])
	var bush_xf: Array = f_data.get("bush_xf", [])
	var shelf_xf: Array = f_data.get("shelf_xf", [])
	var grotto_mush_xf: Array = f_data.get("grotto_mush_xf", [])

	var leaves_tex := load("res://assets/nature/Leaves.png") as Texture2D
	var bush_tex := load("res://assets/nature/Leaves_TwistedTree_C.png") as Texture2D
	var mush_tex := load("res://assets/nature/Mushrooms.png") as Texture2D

	var leaves_mat := StandardMaterial3D.new()
	leaves_mat.albedo_texture = leaves_tex
	leaves_mat.albedo_color = Color(0.84, 0.96, 0.72)
	leaves_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaves_mat.alpha_scissor_threshold = 0.42
	leaves_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaves_mat.roughness = 0.85
	leaves_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_texture = bush_tex
	bush_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	bush_mat.alpha_scissor_threshold = 0.45
	bush_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bush_mat.roughness = 0.85
	bush_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	if terrain_scene != null:
		var ov_grass := terrain_scene.get_node_or_null("Grass") as MultiMeshInstance3D
		if ov_grass != null and ov_grass.material_override is ShaderMaterial:
			_grass_shader_mat = (ov_grass.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	if _grass_shader_mat == null:
		_grass_shader_mat = ShaderMaterial.new()
		_grass_shader_mat.shader = load("res://terrain/grass.gdshader") as Shader
		_grass_shader_mat.set_shader_parameter("grass_texture", load("res://assets/nature/Grass.png") as Texture2D)
		_grass_shader_mat.set_shader_parameter("alpha_scissor_threshold", 0.45)

	var fern_mesh := _extract_surface_mesh("res://assets/nature/Fern_1.gltf", [0], [leaves_mat])
	var plant_mesh := _extract_surface_mesh("res://assets/nature/Plant_1.gltf", [0], [leaves_mat])
	var bush_mesh := _extract_surface_mesh("res://assets/nature/Bush_Common.gltf", [0], [bush_mat])
	var grass_mesh := _extract_surface_mesh("res://assets/nature/Grass_Common_Tall.gltf", [0], [])

	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_texture = mush_tex
	shelf_mat.albedo_color = Color(1.0, 0.92, 0.78)
	shelf_mat.roughness = 0.78
	shelf_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var shelf_mesh := _extract_surface_mesh("res://assets/nature/Mushroom_Laetiporus.gltf", [0], [shelf_mat])

	var grotto_mush_mat := StandardMaterial3D.new()
	grotto_mush_mat.albedo_texture = mush_tex
	grotto_mush_mat.albedo_color = Color(0.84, 0.90, 0.95)
	grotto_mush_mat.emission_enabled = true
	grotto_mush_mat.emission = Color(0.14, 0.50, 0.64)
	grotto_mush_mat.emission_energy_multiplier = 0.06
	grotto_mush_mat.roughness = 0.72
	grotto_mush_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var grotto_mush_mesh := _extract_surface_mesh("res://assets/nature/Mushroom_Common.gltf", [0], [grotto_mush_mat])

	var add_mm := func(n_name: String, m: Mesh, mat_ov: Material, xfs: Array, shadows: bool) -> MultiMeshInstance3D:
		if m == null or xfs.is_empty():
			return null
		var mmi := MultiMeshInstance3D.new()
		mmi.name = n_name
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mat_ov != null:
			mmi.material_override = mat_ov
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i] as Transform3D)
		mmi.multimesh = mm
		flora.add_child(mmi)
		return mmi

	_flora_grass_node = add_mm.call("MoundGrass", grass_mesh, _grass_shader_mat, grass_xf, false)
	add_mm.call("MoundFerns", fern_mesh, null, fern_xf, true)
	add_mm.call("MoundPlants", plant_mesh, null, plant_xf, false)
	add_mm.call("MoundBushes", bush_mesh, null, bush_xf, true)
	add_mm.call("LogShelfFungi", shelf_mesh, null, shelf_xf, true)
	add_mm.call("GrottoMushrooms", grotto_mush_mesh, null, grotto_mush_xf, false)


# ==============================================================================
# P6: GEODE PRISMATIC CRYSTAL CORE COLLECTIBLE & ACOUSTIC REVERB ZONES
# ==============================================================================

func _build_geode_reward() -> void:
	var gc: Vector3 = CaveLayout.CHAMBERS["geode_pocket"]["c"]
	var reward_world := CaveLayout.to_world(Vector3(gc.x, gc.y + 2.25, gc.z - 0.4))

	var root_r := Node3D.new()
	root_r.name = "GeodeReward"
	root_r.position = reward_world
	add_child(root_r)
	_geode_reward_node = root_r

	# Prismatic double-terminated octahedron crystal core
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eq := [Vector3(0.65, 0, 0), Vector3(0, 0, 0.65), Vector3(-0.65, 0, 0), Vector3(0, 0, -0.65)]
	var top := Vector3(0, 1.05, 0)
	var bot := Vector3(0, -0.85, 0)
	for i in 4:
		var a: Vector3 = eq[i]
		var b: Vector3 = eq[(i + 1) % 4]
		var nt := (top - a).cross(b - a).normalized()
		var nb := (b - a).cross(bot - a).normalized()
		st.set_normal(nt); st.set_uv(Vector2(0.0, 0.35)); st.add_vertex(a)
		st.set_normal(nt); st.set_uv(Vector2(1.0, 0.35)); st.add_vertex(b)
		st.set_normal(nt); st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(top)
		st.set_normal(nb); st.set_uv(Vector2(0.0, 0.35)); st.add_vertex(a)
		st.set_normal(nb); st.set_uv(Vector2(0.5, 0.0)); st.add_vertex(bot)
		st.set_normal(nb); st.set_uv(Vector2(1.0, 0.35)); st.add_vertex(b)

	var r_mesh := st.commit()
	var cmat := ShaderMaterial.new()
	cmat.shader = load("res://terrain/cave_crystal.gdshader") as Shader
	cmat.set_shader_parameter("emission_strength", 1.35)
	r_mesh.surface_set_material(0, cmat)

	var mi := MeshInstance3D.new()
	mi.name = "GeodeHeartMesh"
	mi.mesh = r_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_r.add_child(mi)
	_geode_reward_mesh = mi

	var area := Area3D.new()
	area.name = "GeodeRewardArea"
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 1 | SlimeMotor.LAYER_SLIMES
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.6
	cs.shape = sph
	area.add_child(cs)
	area.body_entered.connect(_on_geode_area_body_entered)
	root_r.add_child(area)
	_geode_reward_area = area


func _build_ancient_big_door() -> void:
	var door_info: Dictionary = CaveLayout.ANCIENT_DOOR
	var door_loc: Vector3 = door_info["pos"]
	var door_w := float(door_info["width"])   # 7.4m
	var door_h := float(door_info["height"])  # 9.2m
	var door_d := float(door_info["depth"])   # 2.0m

	var door_world_pos := CaveLayout.to_world(door_loc)
	# Local facing direction
	var yaw_loc := float(door_info["yaw"])
	var fwd_loc := Vector3(sin(yaw_loc), 0.0, cos(yaw_loc)).normalized()
	var fwd_world := Vector3(
		CaveLayout.FWD_XZ.x * fwd_loc.z + CaveLayout.RIGHT_XZ.x * fwd_loc.x,
		0.0,
		CaveLayout.FWD_XZ.y * fwd_loc.z + CaveLayout.RIGHT_XZ.y * fwd_loc.x
	).normalized()
	var right_world := fwd_world.cross(Vector3.UP).normalized()
	var basis_door := Basis(right_world, Vector3.UP, fwd_world)

	var door_root := Node3D.new()
	door_root.name = "AncientBigDoor"
	door_root.transform = Transform3D(basis_door, door_world_pos)
	add_child(door_root)

	# 1. Architectural Materials
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.20, 0.20, 0.22)
	stone_mat.roughness = 0.88
	stone_mat.metallic = 0.05
	stone_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.14, 0.13, 0.15)
	door_mat.roughness = 0.72
	door_mat.metallic = 0.35
	door_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.42, 0.35, 0.22)
	trim_mat.roughness = 0.45
	trim_mat.metallic = 0.85

	var rune_mat := StandardMaterial3D.new()
	rune_mat.albedo_color = Color(1.0, 0.75, 0.28)
	rune_mat.emission_enabled = true
	rune_mat.emission = Color(1.0, 0.72, 0.25)
	rune_mat.emission_energy_multiplier = 2.4

	# Helper to create box mesh instance
	var add_box := func(p_name: String, sz: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = p_name
		var box := BoxMesh.new()
		box.size = sz
		mi.mesh = box
		mi.material_override = mat
		mi.position = pos
		parent.add_child(mi)
		return mi

	# 2. Outer Portal Frame (Massive Stone Arch & Pilasters)
	var p_width := 1.2
	var p_depth := 1.8
	var p_height := door_h
	# Left & Right Pilasters
	add_box.call("PillarLeft", Vector3(p_width, p_height, p_depth), Vector3(-door_w * 0.5 + p_width * 0.5, p_height * 0.5, 0.0), stone_mat, door_root)
	add_box.call("PillarRight", Vector3(p_width, p_height, p_depth), Vector3(door_w * 0.5 - p_width * 0.5, p_height * 0.5, 0.0), stone_mat, door_root)
	# Stepped Plinths (Bases)
	add_box.call("PlinthLeft", Vector3(p_width + 0.4, 0.8, p_depth + 0.4), Vector3(-door_w * 0.5 + p_width * 0.5, 0.4, 0.0), stone_mat, door_root)
	add_box.call("PlinthRight", Vector3(p_width + 0.4, 0.8, p_depth + 0.4), Vector3(door_w * 0.5 - p_width * 0.5, 0.4, 0.0), stone_mat, door_root)
	# Heavy Lintel Arch
	var lintel_h := 1.6
	add_box.call("LintelBeam", Vector3(door_w + 0.6, lintel_h, p_depth + 0.2), Vector3(0.0, door_h - lintel_h * 0.5, 0.0), stone_mat, door_root)
	# Upper Cornice
	add_box.call("Cornice", Vector3(door_w + 1.2, 0.5, p_depth + 0.6), Vector3(0.0, door_h + 0.25, 0.0), stone_mat, door_root)

	# 3. Dual Monumental Door Slabs
	var slab_w := (door_w - p_width * 2.0) * 0.5 - 0.04
	var slab_h := door_h - lintel_h
	var slab_d := 0.55
	var slab_z := -0.25

	add_box.call("DoorSlabLeft", Vector3(slab_w, slab_h, slab_d), Vector3(-slab_w * 0.5 - 0.02, slab_h * 0.5, slab_z), door_mat, door_root)
	add_box.call("DoorSlabRight", Vector3(slab_w, slab_h, slab_d), Vector3(slab_w * 0.5 + 0.02, slab_h * 0.5, slab_z), door_mat, door_root)

	# Heavy Bronze Horizontal Reinforcing Bands
	for b_i in 3:
		var by := 1.2 + float(b_i) * (slab_h - 2.4) * 0.5
		add_box.call("BandLeft_%d" % b_i, Vector3(slab_w - 0.2, 0.26, slab_d + 0.08), Vector3(-slab_w * 0.5 - 0.02, by, slab_z), trim_mat, door_root)
		add_box.call("BandRight_%d" % b_i, Vector3(slab_w - 0.2, 0.26, slab_d + 0.08), Vector3(slab_w * 0.5 + 0.02, by, slab_z), trim_mat, door_root)

	# 4. Central Circular Runic Lock Medallion & Emissive Inlays
	var st_rune := SurfaceTool.new()
	st_rune.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_ring := 1.35
	var r_thick := 0.16
	var r_segs := 32
	var r_center := Vector3(0.0, slab_h * 0.52, slab_z + slab_d * 0.5 + 0.02)
	for ri in r_segs:
		var th0 := (float(ri) / float(r_segs)) * TAU
		var th1 := (float(ri + 1) / float(r_segs)) * TAU
		var v0_in := r_center + Vector3(cos(th0) * (r_ring - r_thick), sin(th0) * (r_ring - r_thick), 0.0)
		var v0_out := r_center + Vector3(cos(th0) * r_ring, sin(th0) * r_ring, 0.0)
		var v1_in := r_center + Vector3(cos(th1) * (r_ring - r_thick), sin(th1) * (r_ring - r_thick), 0.0)
		var v1_out := r_center + Vector3(cos(th1) * r_ring, sin(th1) * r_ring, 0.0)
		st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(v0_in)
		st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(v0_out)
		st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(v1_out)
		st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(v0_in)
		st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(v1_out)
		st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(v1_in)

	# Runic Lintel Emblem
	var glyph_w := 2.8
	var glyph_y := door_h - lintel_h * 0.5
	var glyph_z := p_depth * 0.5 + 0.02
	st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(Vector3(-glyph_w * 0.5, glyph_y - 0.25, glyph_z))
	st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(Vector3(0.0, glyph_y + 0.35, glyph_z))
	st_rune.set_normal(Vector3.FORWARD); st_rune.add_vertex(Vector3(glyph_w * 0.5, glyph_y - 0.25, glyph_z))

	var rune_mesh := st_rune.commit()
	var rune_mi := MeshInstance3D.new()
	rune_mi.name = "RunicRelief"
	rune_mi.mesh = rune_mesh
	rune_mi.material_override = rune_mat
	rune_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door_root.add_child(rune_mi)

	# 5. Flanking Ancient Stone Pedestals & Burning Braziers
	for s_side: float in [-1.0, 1.0]:
		var sx := s_side * (door_w * 0.5 + 1.6)
		var sz := 1.4
		add_box.call("BrazierPedestal_%s" % ("L" if s_side < 0 else "R"), Vector3(0.9, 1.8, 0.9), Vector3(sx, 0.9, sz), stone_mat, door_root)
		add_box.call("BrazierBowl_%s" % ("L" if s_side < 0 else "R"), Vector3(1.15, 0.45, 1.15), Vector3(sx, 1.95, sz), trim_mat, door_root)
		add_box.call("BrazierFlame_%s" % ("L" if s_side < 0 else "R"), Vector3(0.65, 0.25, 0.65), Vector3(sx, 2.2, sz), rune_mat, door_root)

	# 6. Physical Obstacle Collider on Layer 4 (WALLS/OBSTACLES)
	var static_body := StaticBody3D.new()
	static_body.name = "AncientDoorBody"
	static_body.collision_layer = 4
	static_body.collision_mask = 0
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(door_w + 1.0, door_h + 1.0, door_d + 1.0)
	col_shape.shape = box_shape
	col_shape.position = Vector3(0.0, door_h * 0.5, 0.0)
	static_body.add_child(col_shape)
	door_root.add_child(static_body)


func _build_reverb_zones() -> void:
	if Engine.is_editor_hint():
		return
	var bus_name := &"CaveReverb"
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.82
		rev.damping = 0.45
		rev.wet = 0.42
		AudioServer.add_bus_effect(idx, rev)
	_reverb_bus_idx = idx

	var zones := [
		["HallReverbZone", Vector3(-60.0, 28.0, 72.0), Vector3(72.0, 34.0, 48.0), 0.45],
		["GrottoReverbZone", Vector3(-16.0, 19.0, 82.0), Vector3(44.0, 16.0, 44.0), 0.32],
		["LakeReverbZone", Vector3(-34.0, 15.0, 146.0), Vector3(58.0, 24.0, 50.0), 0.58],
		["VaultSanctumReverbZone", Vector3(-135.0, 14.0, 84.0), Vector3(32.0, 18.0, 28.0), 0.40],
	]
	var rz_parent := Node3D.new()
	rz_parent.name = "CaveReverbZones"
	add_child(rz_parent)
	for z: Array in zones:
		var a := Area3D.new()
		a.name = String(z[0])
		a.reverb_bus_enabled = true
		a.reverb_bus_name = bus_name
		a.reverb_bus_amount = float(z[3])
		a.monitoring = false
		a.monitorable = false
		a.position = CaveLayout.to_world(z[1] as Vector3)
		var b_cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = z[2] as Vector3
		b_cs.shape = box
		a.add_child(b_cs)
		rz_parent.add_child(a)
