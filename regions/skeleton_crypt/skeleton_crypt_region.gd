class_name SkeletonCryptRegion
extends Node3D
## Authoritative dressing/lighting profile container for Skeleton Crypt.

const SkeletonCryptProfile = preload("res://regions/skeleton_crypt/skeleton_crypt_profile.gd")

@export var profile: SkeletonCryptProfile


func get_profile() -> SkeletonCryptProfile:
	if profile == null:
		profile = load("res://regions/skeleton_crypt/skeleton_crypt_default_profile.tres") as SkeletonCryptProfile
		if profile == null:
			profile = SkeletonCryptProfile.new()
	return profile
