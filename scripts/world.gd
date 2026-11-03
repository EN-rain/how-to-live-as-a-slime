class_name GameWorld
extends Node3D

## Reusable World scene controller with Inspector-editable lighting, post-processing,
## navigation mesh obstacle carving, and palette settings. The scene hierarchy
## (environment, sun, ground, walls, obstacles, and navigation region) lives in `scenes/world.tscn`.

const LightingPreset := preload("res://scripts/lighting_preset.gd")

const OUTLINE_WIDTH := 0.02
const GROUND_OUTLINE_COLOR := Color(0.09, 0.07, 0.12)
const TREE_VISIBILITY_END := 130.0
const ROCK_VISIBILITY_END := 110.0
const NAV_HALF_EXTENT := 48.0
const NAV_GRID_STEPS := 48
const GROUND_HALF_EXTENT := 50.0
const NAV_SURFACE_OFFSET := 0.05

@export_group("Lighting & Sun")
@export_range(10.0, 80.0, 1.0) var sun_elevation_deg: float = 32.0
@export_range(-180.0, 180.0, 1.0) var sun_azimuth_deg: float = -50.0
@export_range(0.2, 4.0, 0.05) var sun_energy: float = 1.6
@export var sun_color: Color = Color(1.0, 0.86, 0.77)
@export_range(20.0, 150.0, 1.0) var shadow_max_distance: float = 55.0

@export_group("Environment & Quality")
## SDFGI is expensive on integrated GPUs. Off by default for 60+ fps budget.
@export var sdfgi_enabled: bool = false
## SSAO costs ~55 fps on integrated GPUs. Off by default; toggle in Inspector or Settings.
@export var ssao_enabled: bool = false
@export_range(0.5, 2.0, 0.05) var tonemap_exposure: float = 1.0
@export_range(0.5, 2.0, 0.05) var tonemap_saturation: float = 1.1
@export var fog_enabled: bool = true
@export_range(5.0, 120.0, 1.0) var fog_depth_begin: float = 42.0
@export_range(20.0, 300.0, 1.0) var fog_depth_end: float = 150.0
@export_range(0.0, 1.0, 0.05) var fog_density: float = 0.55

@export_group("Navigation")
## Clearance radius carved around trees and rocks in the NavigationMesh.
@export_range(0.5, 3.0, 0.05) var tree_nav_clearance: float = 1.25
@export_range(0.5, 3.0, 0.05) var rock_nav_clearance: float = 1.35

@export_group("Terrain")
## Rolling hills so the arena is not a flat plane. Set false for the old box ground.
@export var terrain_enabled: bool = true
## Approximate peak height in metres.
@export_range(0.0, 8.0, 0.1) var terrain_amplitude: float = 5.0
## The starting area stays flat inside this radius so nothing spawns on a slope.
@export_range(2.0, 30.0, 0.5) var terrain_flat_radius: float = 7.0
@export_range(0.01, 0.2, 0.005) var terrain_frequency: float = 0.075
## Ground mesh / navmesh resolution. Smaller is smoother and more expensive.
@export_range(1.0, 4.0, 0.5) var terrain_cell_size: float = 2.0

@export_group("Palette")
@export var ground_color: Color = Color(0.45, 0.62, 0.32)
@export var trunk_color: Color = Color(0.42, 0.29, 0.2)
@export var leaf_color: Color = Color(0.32, 0.55, 0.3)
@export var rock_color: Color = Color(0.5, 0.52, 0.55)

@export_group("Nodes")
@export var world_environment: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var nav_region: NavigationRegion3D
@export var ground_mesh: MeshInstance3D
@export var ground_collision: CollisionShape3D
@export var trees_root: Node3D
@export var rocks_root: Node3D


func _ready() -> void:
	if world_environment == null:
		world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun_light == null:
		sun_light = get_node_or_null("Sun") as DirectionalLight3D
	if nav_region == null:
		nav_region = get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if ground_mesh == null:
		ground_mesh = get_node_or_null("NavigationRegion3D/Ground/Mesh") as MeshInstance3D
	if ground_collision == null:
		ground_collision = get_node_or_null("NavigationRegion3D/Ground/Collision") as CollisionShape3D
	if trees_root == null:
		trees_root = get_node_or_null("NavigationRegion3D/Trees") as Node3D
	if rocks_root == null:
		rocks_root = get_node_or_null("NavigationRegion3D/Rocks") as Node3D

	_apply_terrain()
	_snap_props_to_terrain()
	apply_lighting_settings()
	apply_palette_materials()
	_setup_navigation_mesh()


## World-space ground elevation. Terrain is a sum of low-frequency waves, scaled
## down to zero near the spawn point so the opening area stays flat.
func terrain_height(x: float, z: float) -> float:
	if not terrain_enabled:
		return 0.0
	var f := terrain_frequency
	var h := sin(x * f) * cos(z * f * 0.85) * 1.1
	h += sin((x + z) * f * 1.45) * 0.45
	h += cos(x * f * 0.55 - z * f * 0.7) * 0.65
	# Mid-frequency swells give the map a few visible rises without steep walls.
	h += sin(x * f * 3.1 + z * f * 2.3) * 0.25
	h += cos(x * f * 2.4 - z * f * 3.0) * 0.18
	# Named mounds give the map readable landmarks instead of uniform noise.
	h += 2.20 * _terrain_bump(x, z, 28.0, -30.0, 16.0)
	h += 1.60 * _terrain_bump(x, z, -32.0, 22.0, 18.0)
	h -= 1.20 * _terrain_bump(x, z, -20.0, -34.0, 14.0)
	h += 1.00 * _terrain_bump(x, z, 40.0, 30.0, 12.0)
	h += 0.90 * _terrain_bump(x, z, -10.0, 42.0, 11.0)
	var flat := smoothstep(terrain_flat_radius, terrain_flat_radius + 8.0, sqrt(x * x + z * z))
	return h * flat * (terrain_amplitude / 3.3)


## Smooth radial hill used by `terrain_height`.
func _terrain_bump(x: float, z: float, cx: float, cz: float, radius: float) -> float:
	var dx := (x - cx) / radius
	var dz := (z - cz) / radius
	return exp(-(dx * dx + dz * dz) * 0.5)


## Builds the hilly ground mesh and matching concave collision from `terrain_height`.
func _apply_terrain() -> void:
	if ground_mesh == null:
		return
	if not terrain_enabled:
		var box := BoxMesh.new()
		box.size = Vector3(GROUND_HALF_EXTENT * 2.0, 1.0, GROUND_HALF_EXTENT * 2.0)
		ground_mesh.position = Vector3(0.0, -0.5, 0.0)
		ground_mesh.mesh = box
		if ground_collision != null:
			ground_collision.position = Vector3(0.0, -0.5, 0.0)
			var shape := BoxShape3D.new()
			shape.size = box.size
			ground_collision.shape = shape
		return

	ground_mesh.position = Vector3.ZERO
	if ground_collision != null:
		ground_collision.position = Vector3.ZERO

	var step := terrain_cell_size
	var count := int(round(GROUND_HALF_EXTENT * 2.0 / step))
	var stride := count + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gz in stride:
		var z := -GROUND_HALF_EXTENT + float(gz) * step
		for gx in stride:
			var x := -GROUND_HALF_EXTENT + float(gx) * step
			st.set_uv(Vector2(float(gx) / float(count), float(gz) / float(count)))
			st.add_vertex(Vector3(x, terrain_height(x, z), z))
	for gz in count:
		for gx in count:
			var i0 := gz * stride + gx
			var i1 := i0 + 1
			var i2 := (gz + 1) * stride + gx + 1
			var i3 := (gz + 1) * stride + gx
			# Godot treats clockwise triangles as front-facing; this winding is +Y.
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i3)
	st.generate_normals()
	var mesh := st.commit()
	ground_mesh.mesh = mesh
	if ground_collision != null:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		ground_collision.shape = shape


## Trees and rocks are authored at y = 0 in the scene; sit them on the terrain.
func _snap_props_to_terrain() -> void:
	for root in [trees_root, rocks_root]:
		if root == null:
			continue
		for prop in root.get_children():
			var p := prop as Node3D
			if p != null:
				p.position.y = terrain_height(p.position.x, p.position.z)


func apply_lighting_settings() -> void:
	if world_environment != null:
		var env := world_environment.environment
		if env == null:
			env = Environment.new()
			world_environment.environment = env
		LightingPreset.apply_sky(env)
		LightingPreset.apply_tonemap(env, {
			"exposure": tonemap_exposure,
			"saturation": tonemap_saturation,
		})
		if ssao_enabled:
			LightingPreset.apply_ambient_occlusion(env, {"radius": 1.0, "intensity": 1.4, "ssil": false})
		else:
			env.ssao_enabled = false
			env.ssil_enabled = false
		if sdfgi_enabled:
			LightingPreset.apply_sdfgi(env, {"min_cell_size": 0.5})
		else:
			env.sdfgi_enabled = false
		if fog_enabled:
			LightingPreset.apply_fog(env, {
				"depth_begin": fog_depth_begin,
				"depth_end": fog_depth_end,
				"density": fog_density,
				"sky_affect": 0.0,
			})
		else:
			env.fog_enabled = false

	if sun_light != null:
		LightingPreset.apply_sun(sun_light, {
			"elevation_deg": sun_elevation_deg,
			"azimuth_deg": sun_azimuth_deg,
			"energy": sun_energy,
			"color": sun_color,
		})
		# Keep PCSS off (light_angular_distance = 0) and use 2 cascades over 55 m
		# for maximum integrated-GPU performance (see godot-render-performance).
		sun_light.light_angular_distance = 0.0
		sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun_light.directional_shadow_max_distance = shadow_max_distance
		sun_light.shadow_bias = 0.04


func apply_palette_materials() -> void:
	if ground_mesh != null:
		ground_mesh.material_override = ToonMaterial.make(
			ground_color, OUTLINE_WIDTH, GROUND_OUTLINE_COLOR, false
		)
		ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var tree_mat := ToonMaterial.shared(leaf_color, OUTLINE_WIDTH)
	if trees_root != null:
		for tree in trees_root.get_children():
			_apply_toon_recursive(
				tree,
				tree_mat,
				TREE_VISIBILITY_END,
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			)

	var rock_mat := ToonMaterial.shared(rock_color, OUTLINE_WIDTH)
	if rocks_root != null:
		for rock in rocks_root.get_children():
			# Rocks are low to the ground; disabling their shadow caster saves shadow pass draw calls.
			_apply_toon_recursive(
				rock,
				rock_mat,
				ROCK_VISIBILITY_END,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)


func _apply_toon_recursive(
		node: Node,
		mat: ShaderMaterial,
		vis_end: float,
		shadow_mode: GeometryInstance3D.ShadowCastingSetting
	) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		mi.material_override = mat
		mi.visibility_range_end = vis_end
		mi.cast_shadow = shadow_mode
	for child in node.get_children():
		_apply_toon_recursive(child, mat, vis_end, shadow_mode)


func set_ssao(enabled: bool) -> void:
	ssao_enabled = enabled
	apply_lighting_settings()


func set_sdfgi(enabled: bool) -> void:
	sdfgi_enabled = enabled
	apply_lighting_settings()


## Builds an obstacle-aware NavigationMesh across the ground that carves out
## cells occupied by trees and rocks so `NavigationAgent3D` routes around them.
func _setup_navigation_mesh() -> void:
	if nav_region == null:
		return

	var obstacles: Array[Vector3] = []
	if trees_root != null:
		for tree in trees_root.get_children():
			var t := tree as Node3D
			if t != null:
				obstacles.append(Vector3(t.position.x, t.position.z, tree_nav_clearance))
	if rocks_root != null:
		for rock in rocks_root.get_children():
			var r := rock as Node3D
			if r != null:
				obstacles.append(Vector3(r.position.x, r.position.z, rock_nav_clearance))

	var nav_mesh := NavigationMesh.new()
	var step := (NAV_HALF_EXTENT * 2.0) / float(NAV_GRID_STEPS)
	var stride := NAV_GRID_STEPS + 1
	var verts := PackedVector3Array()
	verts.resize(stride * stride)

	for gz in stride:
		var z := -NAV_HALF_EXTENT + float(gz) * step
		for gx in stride:
			var x := -NAV_HALF_EXTENT + float(gx) * step
			verts[gz * stride + gx] = Vector3(x, terrain_height(x, z) + NAV_SURFACE_OFFSET, z)

	nav_mesh.set_vertices(verts)

	for gz in NAV_GRID_STEPS:
		for gx in NAV_GRID_STEPS:
			var cx := -NAV_HALF_EXTENT + (float(gx) + 0.5) * step
			var cz := -NAV_HALF_EXTENT + (float(gz) + 0.5) * step
			if _is_cell_blocked(cx, cz, step * 0.5, obstacles):
				continue
			var i0 := gz * stride + gx
			var i1 := i0 + 1
			var i2 := (gz + 1) * stride + gx + 1
			var i3 := (gz + 1) * stride + gx
			nav_mesh.add_polygon(PackedInt32Array([i0, i1, i2, i3]))

	nav_region.navigation_mesh = nav_mesh


## Blocks a cell when the obstacle circle overlaps the cell *square*, not just
## its centre. Centre-only tests miss obstacles sitting on a grid line: the
## nearest cell centre can be sqrt(2) * half beyond the clearance, so the
## navmesh would keep a hole-free path straight through a rock.
func _is_cell_blocked(cx: float, cz: float, half: float, obstacles: Array[Vector3]) -> bool:
	for obs in obstacles:
		var dx := maxf(absf(cx - obs.x) - half, 0.0)
		var dz := maxf(absf(cz - obs.y) - half, 0.0)
		if dx * dx + dz * dz < obs.z * obs.z:
			return true
	return false
