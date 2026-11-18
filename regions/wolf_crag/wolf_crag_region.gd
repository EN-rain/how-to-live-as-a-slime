class_name WolfCragRegion
extends Node3D
## Authoritative region container for Howlcrest Wolf Crag (decorations, lights & lookout/hearth markers).

const WolfCragProfile = preload("res://regions/wolf_crag/wolf_crag_profile.gd")

@export var profile: WolfCragProfile


func get_profile() -> WolfCragProfile:
	if profile == null:
		profile = load("res://regions/wolf_crag/wolf_crag_default_profile.tres") as WolfCragProfile
		if profile == null:
			profile = WolfCragProfile.new()
	return profile


func get_effective_settings() -> Dictionary:
	var p := get_profile()
	var d := {
		"crag_center": p.crag_center,
		"grove_radius": p.grove_radius,
		"hearth_light_color": p.hearth_light_color,
		"hearth_light_energy": p.hearth_light_energy,
		"hearth_light_range": p.hearth_light_range,
		"lookout_offset": p.lookout_offset,
		"hearth_offset": p.hearth_offset,
	}
	var lm := get_node_or_null("LookoutMarker") as Marker3D
	if lm != null:
		d["lookout_offset"] = lm.position
	var hm := get_node_or_null("HearthMarker") as Marker3D
	if hm != null:
		d["hearth_offset"] = hm.position
	return d
