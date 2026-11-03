extends RefCounted
## Local lights, camera framing and finishing touches for a Godot 4.x 3D scene. One static function per step.
## Checked against Godot 4.7.2.stable class reference (Light3D, OmniLight3D, VisualInstance3D, Camera3D,
## CameraAttributesPractical, Viewport, GPUParticles3D, ParticleProcessMaterial).
##
##   const LCP := preload("res://path/to/lights_camera_post.gd")
##   LCP.add_fill_light($Player)                     # character readable in shade, lights ONLY the character
##   LCP.add_local_light($Lantern, Vector3(0, 0.8, 0)) # a "pocket of warmth" from an object that exists
##   LCP.reframe_tighter($Camera3D, $Player.global_position + Vector3.UP, 45.0)
##   LCP.apply_dof($Camera3D, 6.0)                   # cinematic separation (gameplay trade-off!)
##   LCP.apply_antialiasing(get_viewport())          # MSAA 2x + TAA
##   LCP.add_vignette_grain(self, preload("res://shaders/vignette_grain.gdshader"))
##   LCP.add_dust(self, Vector3(0, 1, 0), Vector3(10, 3, 10))

const FILL_LAYER := 2   # render layer reserved for "lit by the character fill light" (1-based, as in the editor)


## Small light that follows the character and lights ONLY it (light_cull_mask), so the character stays
## readable in shadow without brightening the walls around it. Energy 0.7 is the value used in the source video.
## Note: the cull mask is ignored by SDFGI, VoxelGI, LightmapGI and volumetric fog (Godot docs).
static func add_fill_light(character: Node3D, o := {}) -> OmniLight3D:
	var layer_bit := 1 << (int(o.get("layer", FILL_LAYER)) - 1)
	# The character's meshes must be on the fill layer (keep layer 1 so everything else still sees them).
	for vi in character.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers |= layer_bit
	var light := OmniLight3D.new()
	light.name = "FillLight"
	light.light_cull_mask = layer_bit
	light.light_energy = float(o.get("energy", 0.7))
	light.light_color = o.get("color", Color(1.0, 0.95, 0.9))
	light.omni_range = float(o.get("range", 3.0))
	light.shadow_enabled = false
	light.light_specular = 0.2      # avoid a visible hot spot on the character
	light.position = o.get("offset", Vector3(0.6, 1.4, 0.8))   # in front of / above the character, local space
	character.add_child(light)
	return light


## Warm local light from an object that EXISTS in the scene (lantern, torch, window, fire): pockets of warmth
## that make sense to the player, not arbitrary decorative lamps. No shadows by default (cost: see
## godot-render-performance); enable them only for the few lights that need them.
static func add_local_light(source: Node3D, offset := Vector3.ZERO, o := {}) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "LocalLight"
	light.light_color = o.get("color", Color(1.0, 0.72, 0.42))
	light.light_energy = float(o.get("energy", 1.5))
	light.omni_range = float(o.get("range", 4.0))
	light.omni_attenuation = float(o.get("attenuation", 1.5))
	light.shadow_enabled = bool(o.get("shadows", false))
	light.position = offset
	source.add_child(light)
	return light


## Glow for windows / lantern glass: emission on the material that covers the glowing part.
static func make_emissive(mat: BaseMaterial3D, color := Color(1.0, 0.75, 0.45), energy := 1.5) -> void:
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy


## Narrower FOV + camera moved back along its view line so the target keeps its on-screen size:
## the background looks bigger relative to the character (more "cinematic"), but the player sees less of the
## world. Do not apply blindly to gameplay cameras.
static func reframe_tighter(camera: Camera3D, target: Vector3, new_fov: float) -> void:
	var dist := camera.global_position.distance_to(target)
	var new_dist := dist * tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(new_fov) * 0.5)
	var dir := (camera.global_position - target).normalized()
	camera.global_position = target + dir * new_dist
	camera.fov = new_fov
	camera.look_at(target, Vector3.UP)


## Subtle far depth of field: everything beyond focus_distance + a transition fades into blur.
## Distances in world units. Keep the amount low; it is for separation, not for hiding the world.
static func apply_dof(camera: Camera3D, focus_distance: float, o := {}) -> CameraAttributesPractical:
	var attr := camera.attributes as CameraAttributesPractical
	if attr == null:
		attr = CameraAttributesPractical.new()
		camera.attributes = attr
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = focus_distance
	attr.dof_blur_far_transition = float(o.get("transition", focus_distance * 0.5))
	attr.dof_blur_amount = float(o.get("amount", 0.08))
	return attr


## MSAA 2x + TAA (the source video's choice). MSAA cleans geometry edges, TAA cleans shader/alpha-scissor
## aliasing (foliage, grass). Godot docs: TAA is not complete; particles and skinned meshes may ghost.
## Measured pitfall: MSAA + SDFGI/SSAO drew horizontal banding on flat ground (Godot 4.7.2, AMD). If you see it,
## call apply_antialiasing(vp, {"msaa": Viewport.MSAA_DISABLED}) to keep TAA only.
static func apply_antialiasing(viewport: Viewport, o := {}) -> void:
	viewport.msaa_3d = o.get("msaa", Viewport.MSAA_2X)
	viewport.use_taa = bool(o.get("taa", true))


## Alpha-to-coverage on an alpha-scissor foliage material (StandardMaterial3D): with MSAA on, cut-out leaf/grass
## edges get anti-aliased. Requires MSAA; no effect without it. Custom shaders: render_mode alpha_to_coverage +
## ALPHA_ANTIALIASING_EDGE + ALPHA_TEXTURE_COORDINATE (see godot-vegetation-shaders leaf_canopy.gdshader).
static func enable_foliage_alpha_to_coverage(mat: BaseMaterial3D, edge := 0.3) -> void:
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	mat.alpha_antialiasing_edge = edge


## Full-screen vignette + grain (assets/vignette_grain.gdshader) on a CanvasLayer above the 3D view.
## Put your UI on a higher CanvasLayer so it is not darkened/grained.
static func add_vignette_grain(parent: Node, shader: Shader, o := {}) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "PostVignetteGrain"
	layer.layer = int(o.get("layer", 0))
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for k in ["vignette_strength", "vignette_radius", "grain_amount"]:
		if o.has(k):
			mat.set_shader_parameter(k, o[k])
	rect.material = mat
	layer.add_child(rect)
	parent.add_child(layer)
	return layer


## Floating dust motes: a few hundred tiny, slow, unshaded particles in a box. Small and not distracting.
static func add_dust(parent: Node3D, center: Vector3, extents: Vector3, o := {}) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.amount = int(o.get("amount", 300))
	p.lifetime = float(o.get("lifetime", 8.0))
	p.preprocess = p.lifetime          # already floating on the first frame
	p.position = center
	p.visibility_aabb = AABB(-extents, extents * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = Vector3(0, 0.01, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.direction = Vector3(1, 0.2, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(o.get("size", 0.015))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = o.get("color", Color(1.0, 0.95, 0.85, 0.5))
	# Soft round mote: an untextured quad reads as a hard white square at high resolution.
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	mat.albedo_texture = tex
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p
