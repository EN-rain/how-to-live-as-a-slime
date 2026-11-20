@tool
class_name RatWarrenRegion
extends Node3D
## Standalone scene & authoritative region container for Rat Warren exterior/interior.
## Keeps baked cave coordinates bound to WorldLandmarks.RAT_WARREN_OFFSET.
## In the Godot Editor, previews the baked SurfaceNets cavern mesh directly; at runtime,
## TerritoryBuilder mounts the full Gnawed Ruins, Swamp, and Underground Rat Warren inside it.

const RatWarrenProfile = preload("res://regions/rat_warren/rat_warren_profile.gd")
const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
const CavePropFX = preload("res://scripts/cave_prop_fx.gd")

@export var profile: RatWarrenProfile
@export var preview_in_editor: bool = true:
	set(v):
		preview_in_editor = v
		if is_inside_tree() and Engine.is_editor_hint():
			_sync_editor_preview()


func _ready() -> void:
	if Engine.is_editor_hint():
		_sync_editor_preview()
	else:
		clear_editor_preview()


func clear_editor_preview() -> void:
	var prev := get_node_or_null("RatWarrenEditorPreview")
	if prev != null:
		prev.queue_free()


func _sync_editor_preview() -> void:
	clear_editor_preview()
	if not preview_in_editor:
		return
	var prev := Node3D.new()
	prev.name = "RatWarrenEditorPreview"
	prev.position = Vector3(WorldLandmarks.RAT_WARREN_OFFSET.x, 0.0, WorldLandmarks.RAT_WARREN_OFFSET.y)
	add_child(prev)

	var mat := CavePropFX.make_rock_shader_mat({
		"warm_tint": Color(0.32, 0.31, 0.30),
		"cool_tint": Color(0.18, 0.21, 0.26),
		"moss_tint": Color(0.17, 0.25, 0.14),
		"floor_warm_tint": Color(0.30, 0.28, 0.24),
		"floor_cool_tint": Color(0.17, 0.18, 0.20),
		"noise_scale": 0.14,
		"macro_scale": 0.032,
		"roughness": 0.96,
		"cutout_radius": 8.2,
		"entrance_pos": Vector3(WorldLandmarks.RAT_WARREN_BAKED.x, WorldLandmarks.RAT_FORECOURT_Y + 0.5, 282.0),
		"entrance_glow": Vector3(WorldLandmarks.RAT_WARREN_BAKED.x, WorldLandmarks.RAT_FORECOURT_Y + 2.5, 280.0),
		"hub_glow": Vector3(WorldLandmarks.RAT_WARREN_BAKED.x, 13.5, 244.5),
		"ambient_floor": 0.22,
	})
	var rock_tex := load("res://assets/nature/Rocks_Diffuse.png") as Texture2D
	if rock_tex != null:
		mat.set_shader_parameter(&"rock_texture", rock_tex)
		mat.set_shader_parameter(&"floor_texture", rock_tex)
	CavePropFX.mount_baked_cavern(prev, "res://terrain/cave/rat_warren", mat, false)


func get_profile() -> RatWarrenProfile:
	if profile == null:
		profile = load("res://regions/rat_warren/rat_warren_default_profile.tres") as RatWarrenProfile
		if profile == null:
			profile = RatWarrenProfile.new()
	return profile
