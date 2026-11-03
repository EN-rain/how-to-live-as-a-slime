extends RefCounted
## Directional (sun) shadow QUALITY presets for Godot 4.x, separate from the sun's direction and colour.
## The look of the light (direction, colour, energy) is one decision; the cost of its shadows is another.
## Lower the second before ever removing the first.
## Checked against Godot 4.7.2.stable (DirectionalLight3D, Light3D, RenderingServer, ProjectSettings).
##
##   const ShadowBudget := preload("res://tools/shadow_budget.gd")
##   ShadowBudget.apply($Sun, "medium", 60.0)   # level, shadow max distance in world units
##
## Runtime calls (RenderingServer.*) affect the whole project. The equivalent project settings are
## rendering/lights_and_shadows/directional_shadow/size (default 4096) and
## rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality (default 2 = Soft Low).

const LEVELS := {
	# atlas px, soft filter quality, splits mode, angular distance (PCSS), blur
	"low":    [2048, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, 0.0, 1.0],
	"medium": [4096, RenderingServer.SHADOW_QUALITY_SOFT_LOW, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, 0.0, 1.0],
	"high":   [4096, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, 0.0, 1.0],
	"ultra":  [8192, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, 1.0, 1.5],
}


## max_distance: how far the sun casts shadows. The biggest single lever: shadow splits are spread over this
## distance, so a smaller value gives sharper shadows near the camera and fewer casters in large scenes.
## Set it to what gameplay needs (e.g. 40-100 m for third person), not to the far plane.
## With PCSS on ("ultra"), a SHORTER distance is MORE expensive (measured x2.2 at 200 -> 40): PCSS blurs over a
## world-space size, so denser texels mean more samples. Decide PCSS before tuning the distance.
static func apply(sun: DirectionalLight3D, level := "medium", max_distance := 100.0) -> void:
	var l: Array = LEVELS[level]
	RenderingServer.directional_shadow_atlas_set_size(l[0], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(l[1])
	sun.shadow_enabled = true
	sun.directional_shadow_mode = l[2]
	sun.directional_shadow_max_distance = max_distance
	sun.light_angular_distance = l[3]   # > 0 = PCSS soft shadows: expensive, use for screenshots/cinematics
	sun.shadow_blur = l[4]


static func describe(sun: DirectionalLight3D) -> Dictionary:
	return {
		"shadow_enabled": sun.shadow_enabled,
		"mode": sun.directional_shadow_mode,
		"max_distance": sun.directional_shadow_max_distance,
		"angular_distance": sun.light_angular_distance,
		"blur": sun.shadow_blur,
		"atlas_size_setting": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
		"soft_quality_setting": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),
	}
