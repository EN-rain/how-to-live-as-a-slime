@tool
class_name SkeletonCryptRegion
extends Node3D
## Standalone scene & authoritative dressing/lighting profile container for Skeleton Crypt.
## Owns the SkeletonDungeonCave child node (instanced inside terrain.tscn alongside Cave).

const SkeletonCryptProfile = preload("res://regions/skeleton_crypt/skeleton_crypt_profile.gd")
const DungeonCaveBuilder = preload("res://scripts/dungeon_cave_builder.gd")

@export var profile: SkeletonCryptProfile
@export var preview_in_editor: bool = true:
	set(v):
		preview_in_editor = v
		var cave := get_node_or_null("SkeletonDungeonCave") as DungeonCaveBuilder
		if cave != null:
			cave.preview_in_editor = v


func _ready() -> void:
	var cave := get_node_or_null("SkeletonDungeonCave") as DungeonCaveBuilder
	if cave != null:
		cave.crypt_region = self
		cave.preview_in_editor = preview_in_editor


func get_profile() -> SkeletonCryptProfile:
	if profile == null:
		profile = load("res://regions/skeleton_crypt/skeleton_crypt_default_profile.tres") as SkeletonCryptProfile
		if profile == null:
			profile = SkeletonCryptProfile.new()
	return profile
