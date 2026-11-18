class_name ActorModelLibrary
extends RefCounted
## Auto-detected registry of shipped actor models under assets/{npcs,animals,mobs}.

const CATEGORY_DIRS := {
	"npc": "res://assets/npcs/",
	"animal": "res://assets/animals/",
	"mob": "res://assets/mobs/",
}

const SKIP_PREFIXES := {
	"npc": ["arrow", "axe_", "crossbow", "dagger", "mug_", "shield", "spellbook", "staff", "sword_"],
}

var _pools: Dictionary = {}
var _known: Dictionary = {}
var _scenes: Dictionary = {}
var _notes: PackedStringArray = PackedStringArray()


func build() -> void:
	_pools.clear()
	_known.clear()
	_notes = PackedStringArray()
	for cat: String in CATEGORY_DIRS.keys():
		var dir_path: String = CATEGORY_DIRS[cat]
		var list := PackedStringArray()
		var da := DirAccess.open(dir_path)
		if da == null:
			_notes.append("missing dir " + dir_path)
			_pools[cat] = list
			continue
		var skips: Array = SKIP_PREFIXES.get(cat, [])
		da.list_dir_begin()
		var fname := da.get_next()
		while not fname.is_empty():
			if not da.current_is_dir() and (fname.ends_with(".glb") or fname.ends_with(".gltf")):
				var skip := false
				for pref: String in skips:
					if fname.begins_with(pref):
						skip = true
						break
				if not skip:
					var full := dir_path + fname
					list.append(full)
					_known[full] = true
			fname = da.get_next()
		da.list_dir_end()
		list.sort()
		_pools[cat] = list


func category_counts() -> Dictionary:
	var counts := {}
	for cat: String in _pools.keys():
		counts[cat] = (_pools[cat] as PackedStringArray).size()
	return counts


func scan_notes() -> PackedStringArray:
	return _notes


func pool(category: String) -> PackedStringArray:
	return _pools.get(category, PackedStringArray()) as PackedStringArray


func is_known(path: String) -> bool:
	return _known.has(path)


func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scenes.has(path):
		return _scenes[path] as PackedScene
	var ps := load(path) as PackedScene
	if ps != null:
		_scenes[path] = ps
	return ps


func family_members(path: String) -> PackedStringArray:
	var stem := path.get_file().get_basename().split("_")[0]
	var out := PackedStringArray()
	for cat: String in _pools.keys():
		var p_list: PackedStringArray = _pools[cat]
		if not p_list.has(path):
			continue
		for item in p_list:
			if item.get_file().get_basename().split("_")[0] == stem:
				out.append(item)
		return out
	return out


func pick(category: String, exclude_path: String = "", allowed: PackedStringArray = PackedStringArray(), rng: RandomNumberGenerator = null) -> String:
	var src: PackedStringArray = allowed if not allowed.is_empty() else pool(category)
	var candidates := PackedStringArray()
	for item in src:
		if item != exclude_path:
			candidates.append(item)
	if candidates.is_empty():
		return ""
	var idx := rng.randi_range(0, candidates.size() - 1) if rng != null else (hash(exclude_path + category) & 0x7fffffff) % candidates.size()
	return candidates[idx]
