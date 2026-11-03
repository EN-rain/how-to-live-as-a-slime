class_name SaveManager
extends RefCounted

## Handles saving and loading the player's current sandbox run, best records,
## and graphics/audio settings to `user://slime_save.cfg`.

const SAVE_PATH := "user://slime_save.cfg"


static func has_save(path: String = SAVE_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	return cfg.has_section_key("run", "active") and bool(cfg.get_value("run", "active", false))


static func save_run(
		player: Slime,
		edibles: Array[Dictionary],
		mobs: Array[Dictionary],
		elapsed_time: float,
		path: String = SAVE_PATH
	) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("run", "active", true)
	cfg.set_value("run", "nutrition", player.nutrition)
	cfg.set_value("run", "eaten_count", player.eaten_count)
	cfg.set_value("run", "position", player.global_position)
	cfg.set_value("run", "base_color", player.get_base_color())
	cfg.set_value("run", "elapsed_time", elapsed_time)
	cfg.set_value("run", "edibles", edibles)
	cfg.set_value("run", "mobs", mobs)
	return cfg.save(path) == OK


static func load_run(path: String = SAVE_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	if not bool(cfg.get_value("run", "active", false)):
		return {}
	return {
		"nutrition": float(cfg.get_value("run", "nutrition", 27.0)),
		"eaten_count": int(cfg.get_value("run", "eaten_count", 0)),
		"position": cfg.get_value("run", "position", Vector3(0.0, 1.0, 0.0)),
		"base_color": cfg.get_value("run", "base_color", Color(0.55, 0.9, 0.65)),
		"elapsed_time": float(cfg.get_value("run", "elapsed_time", 0.0)),
		"edibles": cfg.get_value("run", "edibles", []),
		"mobs": cfg.get_value("run", "mobs", []),
	}


static func delete_save(path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		if cfg.has_section("run"):
			cfg.erase_section("run")
		cfg.save(path)


static func record_world_eaten(elapsed_time: float, eaten_count: int, path: String = SAVE_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var prev_worlds := int(cfg.get_value("stats", "worlds_eaten", 0))
	var prev_best := float(cfg.get_value("stats", "best_time", 0.0))
	var worlds := prev_worlds + 1
	var best := elapsed_time if (prev_best <= 0.0 or elapsed_time < prev_best) else prev_best
	cfg.set_value("stats", "worlds_eaten", worlds)
	cfg.set_value("stats", "best_time", best)
	cfg.set_value("stats", "last_eaten_count", eaten_count)
	cfg.save(path)
	return {
		"worlds_eaten": worlds,
		"best_time": best,
	}


static func load_stats(path: String = SAVE_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {"worlds_eaten": 0, "best_time": 0.0}
	return {
		"worlds_eaten": int(cfg.get_value("stats", "worlds_eaten", 0)),
		"best_time": float(cfg.get_value("stats", "best_time", 0.0)),
	}


static func save_settings(volume_db: float, ssao: bool, sdfgi: bool, path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("settings", "volume_db", volume_db)
	cfg.set_value("settings", "ssao_enabled", ssao)
	cfg.set_value("settings", "sdfgi_enabled", sdfgi)
	cfg.save(path)


static func load_settings(path: String = SAVE_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {
			"volume_db": -6.0,
			"ssao_enabled": false,
			"sdfgi_enabled": false,
		}
	return {
		"volume_db": float(cfg.get_value("settings", "volume_db", -6.0)),
		"ssao_enabled": bool(cfg.get_value("settings", "ssao_enabled", false)),
		"sdfgi_enabled": bool(cfg.get_value("settings", "sdfgi_enabled", false)),
	}
