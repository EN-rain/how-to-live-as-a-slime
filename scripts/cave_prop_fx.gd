class_name CavePropFX
extends RefCounted
## Shared visual builders aligning DungeonCaveBuilder & TerritoryBuilder to Crystal Cave's
## standards: landmark_rock.gdshader, cave_water.gdshader, 5-layer fire VFX, speleothems,
## hanging vines/roots, fractured crag boulders, bark-textured fallen logs, and MultiMesh nature flora.

const CaveSys := preload("res://terrain/cave_system.gd")
const LAYER_TERRAIN := 1
const LAYER_OBSTACLES := 4

static var _shared_cache: Dictionary = {}


static func _get_tex(path: String) -> Texture2D:
	if _shared_cache.has(path):
		return _shared_cache[path] as Texture2D
	var t := load(path) as Texture2D
	_shared_cache[path] = t
	return t


static func make_rock_shader_mat(cfg: Dictionary = {}) -> ShaderMaterial:
	var sh := load("res://shaders/landmark_rock.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter(&"rock_texture", _get_tex("res://terrain/textures/rock_albedo.jpg"))
	mat.set_shader_parameter(&"floor_texture", _get_tex("res://terrain/textures/dirt_albedo.jpg"))
	mat.set_shader_parameter(&"rock_warm_tint", cfg.get("warm_tint", Color(0.76, 0.72, 0.65)))
	mat.set_shader_parameter(&"rock_cool_tint", cfg.get("cool_tint", Color(0.46, 0.50, 0.58)))
	mat.set_shader_parameter(&"moss_tint", cfg.get("moss_tint", Color(0.32, 0.66, 0.24)))
	mat.set_shader_parameter(&"triplanar_scale", float(cfg.get("triplanar_scale", 0.26)))
	mat.set_shader_parameter(&"normal_bump_strength", float(cfg.get("bump", 1.25)))
	mat.set_shader_parameter(&"meadow_blend_enable", float(cfg.get("meadow_blend", 1.0)))
	mat.set_shader_parameter(&"meadow_sky_min", float(cfg.get("meadow_sky_min", 0.76)))
	mat.set_shader_parameter(&"abyss_glow_pos", cfg.get("abyss_pos", Vector3(0.0, -9999.0, 0.0)))
	mat.set_shader_parameter(&"abyss_glow_col", cfg.get("abyss_col", Color(0.18, 0.42, 0.52)))
	mat.set_shader_parameter(&"abyss_glow_radius", float(cfg.get("abyss_radius", 18.0)))
	for p_key: String in ["rough_dry", "rough_wet", "spec_dry", "spec_wet", "spec_light_strength", "bump_detail_scale"]:
		if cfg.has(p_key):
			mat.set_shader_parameter(StringName(p_key), float(cfg[p_key]))
	return mat


static func make_cave_water_mat(
	shallow: Color = Color(0.05, 0.34, 0.30),
	deep: Color = Color(0.01, 0.07, 0.08),
	foam: Color = Color(0.56, 0.78, 0.72),
	is_waterfall: bool = false,
	impact_pos: Vector3 = Vector3(0.0, -9999.0, 0.0),
	flow_speed: float = 0.28
) -> ShaderMaterial:
	var sh := load("res://terrain/cave_water.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter(&"is_waterfall", is_waterfall)
	mat.set_shader_parameter(&"shallow_color", shallow)
	mat.set_shader_parameter(&"deep_color", deep)
	mat.set_shader_parameter(&"foam_color", foam)
	mat.set_shader_parameter(&"waterfall_impact_world", impact_pos)
	mat.set_shader_parameter(&"flow_speed", flow_speed)
	return mat


static func make_bark_mat(tint: Color = Color(0.86, 0.80, 0.74), uv_scale: Vector2 = Vector2(2.0, 3.0)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _get_tex("res://assets/nature/Bark_NormalTree.png")
	mat.normal_enabled = true
	mat.normal_texture = _get_tex("res://assets/nature/Bark_NormalTree_Normal.png")
	mat.normal_scale = 1.15
	mat.albedo_color = tint
	mat.roughness = 0.92
	mat.metallic = 0.02
	mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	return mat


static func make_diffuse_rock_mat(tint: Color = Color(0.68, 0.70, 0.74)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _get_tex("res://assets/nature/Rocks_Diffuse.png")
	mat.albedo_color = tint
	mat.roughness = 0.93
	mat.metallic = 0.02
	mat.uv1_scale = Vector3(2.2, 2.2, 1.0)
	return mat


static func mount_baked_cavern(
	parent: Node3D,
	res_prefix: String,
	rock_mat: ShaderMaterial,
	mount_floor: bool = true,
	local_offset: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mesh := load(res_prefix + "_mesh.res") as Mesh
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = res_prefix.get_file() + "_Mesh"
	mi.mesh = mesh
	mi.material_override = rock_mat
	mi.position = local_offset
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	parent.add_child(mi)

	if mount_floor:
		var floor_sh := load(res_prefix + "_floor_shape.res") as Shape3D
		if floor_sh != null:
			var sb_f := StaticBody3D.new()
			sb_f.name = "BakedFloorCol"
			sb_f.collision_layer = LAYER_TERRAIN
			sb_f.collision_mask = 0
			sb_f.position = local_offset
			var cs_f := CollisionShape3D.new()
			cs_f.shape = floor_sh
			sb_f.add_child(cs_f)
			parent.add_child(sb_f)

	var wall_sh := load(res_prefix + "_wall_shape.res") as Shape3D
	if wall_sh != null:
		var sb_w := StaticBody3D.new()
		sb_w.name = "BakedWallCol"
		sb_w.collision_layer = LAYER_OBSTACLES
		sb_w.collision_mask = 0
		sb_w.position = local_offset
		var cs_w := CollisionShape3D.new()
		cs_w.shape = wall_sh
		sb_w.add_child(cs_w)
		parent.add_child(sb_w)

	return mi


## Extracts first MeshInstance3D mesh + material cleanly from a .gltf scene for MultiMesh batching.
static func extract_gltf_mesh(gltf_path: String) -> Mesh:
	var key := "mesh_" + gltf_path
	if _shared_cache.has(key):
		return _shared_cache[key] as Mesh
	var ps := load(gltf_path) as PackedScene
	if ps == null:
		return null
	var root := ps.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			found = (cur as MeshInstance3D).mesh.duplicate() as Mesh
			# Copy override material if present on scene node
			for si in range(found.get_surface_count()):
				var om := (cur as MeshInstance3D).get_surface_override_material(si)
				if om != null:
					found.surface_set_material(si, om)
			break
		for ch in cur.get_children():
			stack.append(ch)
	root.free()
	_shared_cache[key] = found
	return found


static func spawn_gltf_batch(
	parent: Node3D,
	batch_name: String,
	gltf_path: String,
	transforms: Array[Transform3D],
	mat_override: Material = null,
	cast_shadows: bool = false
) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var mesh := extract_gltf_mesh(gltf_path)
	if mesh == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = batch_name
	mmi.multimesh = mm
	if mat_override != null:
		mmi.material_override = mat_override
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Builds tapered organic limestone stalactite/stalagmite with fluted vertical ribs (matching Crystal Cave).
static func build_speleothem_mesh(length: float, base_r: float, seed_val: float, is_ceiling: bool) -> ArrayMesh:
	var key := "spel_%.1f_%.2f_%s_%.1f" % [length, base_r, "c" if is_ceiling else "f", fmod(seed_val, 7.0)]
	if _shared_cache.has(key):
		return _shared_cache[key] as ArrayMesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 10
	var rings := 7
	var pts: Array = []
	var uvs: Array = []
	var cols: Array = []
	var outs: Array = []

	for ri in range(rings + 1):
		var v := float(ri) / float(rings)
		var y := -v * length if is_ceiling else v * length
		# Flared base, graceful drip taper toward pointed tip
		var taper := pow(maxf(1.0 - v * 0.90, 0.06), 1.35)
		var ring_r := base_r * taper * (1.0 + 0.14 * sin(v * 9.0 + seed_val))
		var rp: Array[Vector3] = []
		var ruv: Array[Vector2] = []
		var rc: Array[Color] = []
		var ro: Array[Vector3] = []
		for si in segs:
			var u := float(si) / float(segs)
			var ang := u * TAU
			var rib := 1.0 + 0.18 * sin(ang * 4.0 + v * 3.0 + seed_val) + 0.10 * cos(ang * 7.0 - seed_val)
			var rr := ring_r * rib
			var px := cos(ang) * rr
			var pz := sin(ang) * rr
			rp.append(Vector3(px, y, pz))
			ruv.append(Vector2(u * 2.0, v * length * 0.45))
			# Darker near root (AO), slightly brighter damp mineral tip
			var ao := lerpf(0.38, 0.85, v)
			rc.append(Color(ao, 0.08, 0.48, 0.55))
			ro.append(Vector3(px, 0.25 if not is_ceiling else -0.25, pz).normalized())
		pts.append(rp)
		uvs.append(ruv)
		cols.append(rc)
		outs.append(ro)

	CaveSys._emit_smooth_grid(st, pts, uvs, cols, outs, false, true, false, 0.0)
	st.generate_tangents()
	var m := st.commit()
	_shared_cache[key] = m
	return m


static func spawn_speleothem_cluster(
	parent: Node3D,
	specs: Array[Dictionary],
	mat: Material
) -> void:
	for i in range(specs.size()):
		var s: Dictionary = specs[i]
		var pos: Vector3 = s["pos"]
		var len_m: float = float(s.get("len", 3.4))
		var rad_m: float = float(s.get("rad", 0.42))
		var ceil_flag: bool = bool(s.get("ceiling", true))
		var seed_v: float = float(i) * 2.37 + float(s.get("seed", 0.0))
		var mi := MeshInstance3D.new()
		mi.mesh = build_speleothem_mesh(len_m, rad_m, seed_v, ceil_flag)
		mi.material_override = mat
		mi.position = pos
		mi.rotation.y = fmod(seed_v * 1.9, TAU)
		parent.add_child(mi)
		if bool(s.get("collider", false)):
			var sb := StaticBody3D.new()
			sb.collision_layer = LAYER_OBSTACLES
			sb.collision_mask = 0
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = rad_m * 0.72
			cap.height = len_m
			cs.shape = cap
			sb.position = Vector3(0.0, (-len_m if ceil_flag else len_m) * 0.5, 0.0)
			sb.add_child(cs)
			mi.add_child(sb)


## Crossed hanging root/vine drapes (matches CaveVines in Crystal Cave).
static func spawn_vine_batch(parent: Node3D, points: Array[Dictionary]) -> void:
	if points.is_empty():
		return
	var key := "vine_mesh_shared"
	var mesh: ArrayMesh = _shared_cache.get(key, null)
	if mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 6
		for i in segs:
			var t0 := float(i) / float(segs)
			var t1 := float(i + 1) / float(segs)
			var w0 := lerpf(0.24, 0.03, t0)
			var w1 := lerpf(0.24, 0.03, t1)
			var x0 := sin(t0 * 4.5) * 0.06
			var x1 := sin(t1 * 4.5) * 0.06
			for ang: float in [0.0, PI * 0.5]:
				var ca := cos(ang); var sa := sin(ang)
				var d0 := Vector3(w0 * ca, 0.0, w0 * sa)
				var d1 := Vector3(w1 * ca, 0.0, w1 * sa)
				var n := Vector3(-sa, 0.0, ca)
				var a0 := Vector3(x0, -t0, 0.0) - d0
				var b0 := Vector3(x0, -t0, 0.0) + d0
				var a1 := Vector3(x1, -t1, 0.0) - d1
				var b1 := Vector3(x1, -t1, 0.0) + d1
				st.set_normal(n); st.set_uv(Vector2(0.0, t0)); st.add_vertex(a0)
				st.set_normal(n); st.set_uv(Vector2(1.0, t0)); st.add_vertex(b0)
				st.set_normal(n); st.set_uv(Vector2(1.0, t1)); st.add_vertex(b1)
				st.set_normal(n); st.set_uv(Vector2(0.0, t0)); st.add_vertex(a0)
				st.set_normal(n); st.set_uv(Vector2(1.0, t1)); st.add_vertex(b1)
				st.set_normal(n); st.set_uv(Vector2(0.0, t1)); st.add_vertex(a1)
		mesh = st.commit()
		_shared_cache[key] = mesh

	var vine_mat := StandardMaterial3D.new()
	vine_mat.albedo_texture = _get_tex("res://assets/nature/Leaves.png")
	vine_mat.albedo_color = Color(0.26, 0.34, 0.22)
	vine_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	vine_mat.alpha_scissor_threshold = 0.38
	vine_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	vine_mat.roughness = 0.88

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in range(points.size()):
		var pt: Dictionary = points[i]
		var basis := Basis.from_euler(Vector3(0.0, float(pt.get("rot", float(i) * 1.3)), 0.0))
		var sx := float(pt.get("width", 1.1))
		var sy := float(pt.get("len", 3.5))
		basis = basis.scaled(Vector3(sx, sy, sx))
		mm.set_instance_transform(i, Transform3D(basis, pt["pos"] as Vector3))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CaveVines"
	mmi.multimesh = mm
	mmi.material_override = vine_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## Attaches Crystal Cave's 5-layer animated flame VFX onto any brazier/sconce torch bowl!
static func attach_torch_fire(parent: Node3D, pos: Vector3, seed_idx: int, flame_scale: float = 0.65) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "FireVFX_%d" % seed_idx
	pivot.position = pos
	pivot.scale = Vector3.ONE * flame_scale
	parent.add_child(pivot)

	var noise_tex := CaveSys._get_fire_noise_tex()
	var flipbook_tex := CaveSys._get_fire_flipbook_tex()
	var coal_mesh := CaveSys._build_brazier_coal_bed_mesh()
	var cards_mesh := CaveSys._build_crossed_flame_cards_mesh()

	var coal_shader := load("res://terrain/cave_weird_torch.gdshader") as Shader
	var card_shader := load("res://shaders/torch_flame_card.gdshader") as Shader
	var part_shader := load("res://shaders/torch_flame_particle.gdshader") as Shader
	var smoke_shader := load("res://shaders/torch_smoke.gdshader") as Shader
	var ember_shader := load("res://shaders/torch_ember.gdshader") as Shader
	var haze_shader := load("res://shaders/torch_heat_haze.gdshader") as Shader

	var side_seed := float(seed_idx) * 1.37
	var vfx_bounds := AABB(Vector3(-1.8, -0.5, -1.8), Vector3(3.6, 5.5, 3.6))

	# 1. Glowing coal ember bed
	var coal_mat := ShaderMaterial.new()
	coal_mat.shader = coal_shader
	coal_mat.set_shader_parameter(&"veil_tex", noise_tex)
	coal_mat.set_shader_parameter(&"torch_side_seed", side_seed)
	coal_mat.set_shader_parameter(&"awaken_amount", 0.0)
	var coal_mi := MeshInstance3D.new()
	coal_mi.mesh = coal_mesh
	coal_mi.material_override = coal_mat
	coal_mi.position = Vector3(0.0, -0.02, 0.0)
	coal_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(coal_mi)

	# 2. Refractive heat haze
	if haze_shader != null:
		var haze_mat := ShaderMaterial.new()
		haze_mat.shader = haze_shader
		haze_mat.render_priority = -1
		haze_mat.set_shader_parameter(&"noise_tex", noise_tex)
		haze_mat.set_shader_parameter(&"torch_seed", side_seed)
		haze_mat.set_shader_parameter(&"awaken_amount", 0.0)
		var haze_q := QuadMesh.new()
		haze_q.size = Vector2(1.25, 1.75)
		var haze_mi := MeshInstance3D.new()
		haze_mi.mesh = haze_q
		haze_mi.material_override = haze_mat
		haze_mi.position = Vector3(0.0, 1.12, 0.0)
		haze_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		haze_mi.visibility_range_end = 42.0
		pivot.add_child(haze_mi)

	# 3. Crossed shader flame cards at core
	var card_mat := ShaderMaterial.new()
	card_mat.shader = card_shader
	card_mat.render_priority = 1
	card_mat.set_shader_parameter(&"noise_tex", noise_tex)
	card_mat.set_shader_parameter(&"torch_seed", side_seed)
	card_mat.set_shader_parameter(&"awaken_amount", 0.0)
	var cards_mi := MeshInstance3D.new()
	cards_mi.mesh = cards_mesh
	cards_mi.material_override = card_mat
	cards_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(cards_mi)

	# 4. 4x4 animated flipbook flame particles
	if part_shader != null:
		var fp_mat := ShaderMaterial.new()
		fp_mat.shader = part_shader
		fp_mat.render_priority = 2
		fp_mat.set_shader_parameter(&"flipbook_tex", flipbook_tex)
		var fp_q := QuadMesh.new()
		fp_q.size = Vector2(0.88, 1.12)
		var fp_pm := ParticleProcessMaterial.new()
		fp_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		fp_pm.emission_sphere_radius = 0.24
		fp_pm.direction = Vector3(0.0, 1.0, 0.0)
		fp_pm.spread = 14.0
		fp_pm.initial_velocity_min = 0.85
		fp_pm.initial_velocity_max = 1.45
		fp_pm.gravity = Vector3(0.0, 0.72, 0.0)
		fp_pm.damping_min = 0.35
		fp_pm.damping_max = 0.65
		fp_pm.scale_min = 0.65
		fp_pm.scale_max = 1.05
		fp_pm.anim_speed_min = 0.85
		fp_pm.anim_speed_max = 1.25
		fp_pm.anim_offset_max = 1.0
		var fp_gp := GPUParticles3D.new()
		fp_gp.amount = 16
		fp_gp.lifetime = 0.92
		fp_gp.preprocess = 1.4
		fp_gp.local_coords = true
		fp_gp.custom_aabb = vfx_bounds
		fp_gp.process_material = fp_pm
		fp_gp.draw_pass_1 = fp_q
		fp_gp.material_override = fp_mat
		fp_gp.position = Vector3(0.0, 0.06, 0.0)
		fp_gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(fp_gp)

	# 5. Rising smoke + embers
	if smoke_shader != null:
		var sm_mat := ShaderMaterial.new()
		sm_mat.shader = smoke_shader
		sm_mat.render_priority = 0
		sm_mat.set_shader_parameter(&"noise_tex", noise_tex)
		var sm_q := QuadMesh.new()
		sm_q.size = Vector2(1.12, 1.12)
		var sm_pm := ParticleProcessMaterial.new()
		sm_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		sm_pm.emission_sphere_radius = 0.22
		sm_pm.direction = Vector3(0.0, 1.0, 0.0)
		sm_pm.spread = 12.0
		sm_pm.initial_velocity_min = 0.68
		sm_pm.initial_velocity_max = 1.02
		sm_pm.gravity = Vector3(0.0, 0.14, 0.0)
		sm_pm.scale_min = 0.75
		sm_pm.scale_max = 1.15
		sm_pm.anim_offset_max = 1.0
		var sm_gp := GPUParticles3D.new()
		sm_gp.amount = 10
		sm_gp.lifetime = 2.5
		sm_gp.preprocess = 2.5
		sm_gp.local_coords = true
		sm_gp.custom_aabb = vfx_bounds
		sm_gp.process_material = sm_pm
		sm_gp.draw_pass_1 = sm_q
		sm_gp.material_override = sm_mat
		sm_gp.position = Vector3(0.0, 0.85, 0.0)
		sm_gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(sm_gp)

	if ember_shader != null:
		var em_mat := ShaderMaterial.new()
		em_mat.shader = ember_shader
		em_mat.render_priority = 3
		var em_q := QuadMesh.new()
		em_q.size = Vector2(0.08, 0.10)
		var em_pm := ParticleProcessMaterial.new()
		em_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		em_pm.emission_ring_axis = Vector3.UP
		em_pm.emission_ring_radius = 0.36
		em_pm.emission_ring_inner_radius = 0.08
		em_pm.direction = Vector3(0.0, 1.0, 0.0)
		em_pm.spread = 20.0
		em_pm.initial_velocity_min = 1.0
		em_pm.initial_velocity_max = 1.9
		em_pm.gravity = Vector3(0.0, 0.32, 0.0)
		em_pm.scale_min = 0.7
		em_pm.scale_max = 1.25
		em_pm.anim_offset_max = 1.0
		var em_gp := GPUParticles3D.new()
		em_gp.amount = 18
		em_gp.lifetime = 1.65
		em_gp.preprocess = 1.8
		em_gp.local_coords = true
		em_gp.custom_aabb = vfx_bounds
		em_gp.process_material = em_pm
		em_gp.draw_pass_1 = em_q
		em_gp.material_override = em_mat
		em_gp.position = Vector3(0.0, 0.04, 0.0)
		em_gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(em_gp)

	return pivot


## Builds an angular fractured granite boulder (NOT a smooth pill sphere), with baked AO/SkyVis vertex colors
## so it renders seamlessly with landmark_rock.gdshader!
static func spawn_fractured_boulder(
	parent: Node3D,
	pos: Vector3,
	radii: Vector3,
	rock_mat: Material,
	seed_idx: int,
	with_collider: bool = true
) -> MeshInstance3D:
	var ico := SphereMesh.new()
	ico.radial_segments = 11
	ico.rings = 7
	ico.is_hemisphere = false
	var st := SurfaceTool.new()
	st.create_from(ico, 0)
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var sf := float(seed_idx) * 2.13

	# Compute deterministic cleavage planes so boulder has sharp angular facets & flat resting base
	var planes: Array[Vector3] = [
		Vector3(0.75, 0.55, 0.35).rotated(Vector3.UP, sf).normalized(),
		Vector3(-0.65, 0.42, 0.62).rotated(Vector3.UP, sf * 1.7).normalized(),
		Vector3(0.28, 0.86, -0.42).rotated(Vector3.UP, sf * 0.6).normalized(),
		Vector3(-0.40, -0.25, -0.88).rotated(Vector3.UP, sf * 2.1).normalized(),
	]

	var cols := PackedColorArray()
	cols.resize(verts.size())
	for i in range(verts.size()):
		var d := verts[i].normalized()
		# Planar facet clipping + ridged strata
		var fac := 1.0
		for pn: Vector3 in planes:
			var dp := d.dot(pn)
			if dp > 0.52:
				fac = minf(fac, 0.52 / dp + (dp - 0.52) * 0.28)
		var rib := 1.0 + 0.14 * sin(d.x * 5.2 + sf) * cos(d.z * 4.7 - sf) + 0.09 * sin(d.y * 8.0 + d.x * 3.0)
		var y_squash := d.y
		if y_squash < -0.25:
			y_squash = lerpf(y_squash, -0.25, 0.45)  # Solid heavy resting footprint
		var pv := Vector3(d.x * radii.x * fac * rib, y_squash * radii.y * fac * rib, d.z * radii.z * fac * rib)
		verts[i] = pv
		var sky_v := clampf(0.28 + 0.38 * maxf(d.y, 0.0), 0.0, 0.66)
		var ao_v := clampf(0.45 + 0.50 * clampf((d.y + 0.8) / 1.6, 0.0, 1.0), 0.2, 1.0)
		cols[i] = Color(ao_v, sky_v, 0.14, 0.55)

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var m_tmp := ArrayMesh.new()
	m_tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st_n := SurfaceTool.new()
	st_n.create_from(m_tmp, 0)
	st_n.generate_normals()

	var mi := MeshInstance3D.new()
	mi.mesh = st_n.commit()
	mi.material_override = rock_mat
	mi.position = pos
	mi.rotation = Vector3(0.05 * sin(sf), sf * 0.9, 0.04 * cos(sf))
	parent.add_child(mi)

	if with_collider:
		var sb := StaticBody3D.new()
		sb.collision_layer = LAYER_OBSTACLES
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = radii * 1.48
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


## Multi-segment bent bark-textured fallen log with root buttress flare, broken branch stubs, and shelf fungi.
static func spawn_bark_fallen_log(
	parent: Node3D,
	pos: Vector3,
	rot_y: float,
	tilt_z: float,
	length: float,
	radius: float,
	seed_idx: int,
	bark_mat: Material,
	add_collider: bool = true
) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation = Vector3(0.0, rot_y, tilt_z)
	parent.add_child(root)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 9
	var segs := 12
	var pts: Array = []
	var uvs: Array = []
	var cols: Array = []
	var outs: Array = []
	var sf := float(seed_idx) * 1.73

	for ri in range(rings + 1):
		var u := float(ri) / float(rings)  # 0 = buttress root base, 1 = broken crown end
		var x := (u - 0.5) * length
		var y_arc := sin(u * PI) * 0.08
		var z_bow := sin(u * PI * 1.2 + sf) * 0.16
		var r_flare := 1.0 + 0.45 * pow(maxf(1.0 - u * 4.5, 0.0), 2.0) - u * 0.18
		var rp: Array[Vector3] = []
		var ruv: Array[Vector2] = []
		var rc: Array[Color] = []
		var ro: Array[Vector3] = []
		for si in segs:
			var v := float(si) / float(segs)
			var ang := v * TAU
			var bark_ridge := 1.0 + 0.09 * sin(ang * 5.0 + u * 6.0 + sf) + 0.05 * cos(ang * 8.0)
			var rr := radius * r_flare * bark_ridge
			var py := y_arc + cos(ang) * rr
			var pz := z_bow + sin(ang) * rr
			rp.append(Vector3(x, py, pz))
			ruv.append(Vector2(v, u * length * 0.42))
			rc.append(Color.WHITE)
			ro.append(Vector3(0.0, cos(ang), sin(ang)).normalized())
		pts.append(rp)
		uvs.append(ruv)
		cols.append(rc)
		outs.append(ro)

	CaveSys._emit_smooth_grid(st, pts, uvs, cols, outs, false, true, false, 0.0)
	st.generate_tangents()
	var trunk_mi := MeshInstance3D.new()
	trunk_mi.mesh = st.commit()
	trunk_mi.material_override = bark_mat
	root.add_child(trunk_mi)

	# Add 2 broken short branch stubs along the trunk silhouette
	for bi in range(2):
		var stub := CylinderMesh.new()
		stub.top_radius = radius * 0.22
		stub.bottom_radius = radius * 0.42
		stub.height = radius * 2.2
		stub.radial_segments = 8
		var smi := MeshInstance3D.new()
		smi.mesh = stub
		smi.material_override = bark_mat
		var bx := lerpf(-length * 0.22, length * 0.28, float(bi))
		smi.position = Vector3(bx, radius * 0.85, (0.28 if bi == 0 else -0.26) * radius)
		smi.rotation = Vector3(0.65 if bi == 0 else -0.58, 0.2 * float(bi + 1), -0.42)
		root.add_child(smi)

	if add_collider:
		var sb := StaticBody3D.new()
		sb.collision_layer = LAYER_OBSTACLES
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius * 0.96
		cap.height = length
		cs.shape = cap
		cs.rotation.z = PI * 0.5
		sb.add_child(cs)
		root.add_child(sb)

	return root
