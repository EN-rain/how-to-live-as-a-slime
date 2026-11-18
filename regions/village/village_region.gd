class_name VillageRegion
extends Node3D
## Authoritative region container for Slimebrook Village Core & Harbor markers.

const VillageProfile = preload("res://regions/village/village_profile.gd")

@export var profile: VillageProfile


func get_profile() -> VillageProfile:
	if profile == null:
		profile = load("res://regions/village/village_default_profile.tres") as VillageProfile
		if profile == null:
			profile = VillageProfile.new()
	return profile
