class_name RatWarrenRegion
extends Node3D
## Authoritative region container for Rat Warren exterior/interior dressing.
## Keeps baked cave coordinates bound to WorldLandmarks.RAT_WARREN_OFFSET.

const RatWarrenProfile = preload("res://regions/rat_warren/rat_warren_profile.gd")

@export var profile: RatWarrenProfile


func get_profile() -> RatWarrenProfile:
	if profile == null:
		profile = load("res://regions/rat_warren/rat_warren_default_profile.tres") as RatWarrenProfile
		if profile == null:
			profile = RatWarrenProfile.new()
	return profile
