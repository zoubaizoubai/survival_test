extends RefCounted
class_name SaveData

# 轻量存档：跨启动保存最佳记录与解锁，带版本迁移与损坏回退
# 存储于 user://progress.cfg，使用 ConfigFile

const SAVE_PATH := "user://progress.cfg"
const VERSION := 1

static var _loaded: bool = false
static var _data: Dictionary = {}
static var _dirty: bool = false

# 默认存档结构
static func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		"best_time": 0.0,
		"best_kills": 0,
		"best_level": 1,
		"best_damage": 0.0,
		"total_kills": 0,
		"total_games": 0,
		"total_damage": 0.0,
		"unlocks": {}, # id -> true
	}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_load()
	_loaded = true


static func _load() -> void:
	_data = _defaults()
	var cfg := ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("[SaveData] 损坏或无法读取 %s err=%d，使用默认值" % [SAVE_PATH, err])
		_dirty = false
		return
	# 版本
	var ver: int = int(cfg.get_value("save", "version", VERSION))
	if ver != VERSION:
		# 轻量迁移：保留可用字段，其余回退默认值
		push_warning("[SaveData] 版本迁移 %d -> %d" % [ver, VERSION])
		_data["version"] = VERSION
	# 读取字段，缺失则保留默认值
	for k in _data.keys():
		if k == "unlocks":
			continue
		if cfg.has_section_key("save", k):
			_data[k] = cfg.get_value("save", k)
	# 解锁
	if cfg.has_section("unlocks"):
		for key in cfg.get_section_keys("unlocks"):
			_data["unlocks"][key] = bool(cfg.get_value("unlocks", key, false))
	else:
		_data["unlocks"] = {}
	# 校验：确保类型正确，损坏回退
	if not _data["unlocks"] is Dictionary:
		push_warning("[SaveData] unlocks 非 Dict，回退")
		_data["unlocks"] = {}
	_dirty = false


static func _save() -> void:
	var cfg := ConfigFile.new()
	for k in _data.keys():
		if k == "unlocks":
			continue
		cfg.set_value("save", k, _data[k])
	for uk in (_data["unlocks"] as Dictionary).keys():
		cfg.set_value("unlocks", uk, true)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_error("[SaveData] 保存失败 %s err=%d" % [SAVE_PATH, err])
	else:
		_dirty = false


static func get_data() -> Dictionary:
	ensure_loaded()
	return _data.duplicate(true)


static func get_best() -> Dictionary:
	ensure_loaded()
	return {
		"time": float(_data.get("best_time", 0.0)),
		"kills": int(_data.get("best_kills", 0)),
		"level": int(_data.get("best_level", 1)),
		"damage": float(_data.get("best_damage", 0.0)),
	}


static func get_totals() -> Dictionary:
	ensure_loaded()
	return {
		"total_kills": int(_data.get("total_kills", 0)),
		"total_games": int(_data.get("total_games", 0)),
		"total_damage": float(_data.get("total_damage", 0.0)),
	}


static func is_unlocked(id: String) -> bool:
	ensure_loaded()
	# 未定义解锁视为已解锁（不锁基础内容）
	var gd := preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	if not gd.unlocks.has(id):
		return true
	return bool((_data["unlocks"] as Dictionary).get(id, false))


static func is_weapon_unlocked(weapon_id: String) -> bool:
	ensure_loaded()
	var gd := preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	# 若武器标记 locked 且有 unlock_id，则检查该解锁
	if not gd.weapons.has(weapon_id):
		return true
	var w: Dictionary = gd.weapons[weapon_id] as Dictionary
	if not bool(w.get("locked", false)):
		return true
	var unlock_id: String = str(w.get("unlock_id", weapon_id))
	return is_unlocked(unlock_id)


static func check_and_unlock(stats: Dictionary) -> Array:
	ensure_loaded()
	var gd := preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	var newly: Array = []
	for uid in gd.unlocks.keys():
		if bool((_data["unlocks"] as Dictionary).get(uid, false)):
			continue
		var u: Dictionary = gd.unlocks[uid] as Dictionary
		var kind: String = str(u.get("kind", ""))
		var need: float = float(u.get("need", 999999.0))
		var met: bool = false
		match kind:
			"total_kills":
				met = float(_data.get("total_kills", 0)) >= need
			"best_time":
				met = float(_data.get("best_time", 0.0)) >= need
			"kills":
				met = float(stats.get("kills", 0)) >= need
			"time":
				met = float(stats.get("time", 0.0)) >= need
			"level":
				met = float(stats.get("level", 0)) >= need
			"damage":
				met = float(stats.get("damage", 0.0)) >= need
			_:
				# 通用：检查 stats 中同名键
				if stats.has(kind):
					met = float(stats[kind]) >= need
		if met:
			(_data["unlocks"] as Dictionary)[uid] = true
			newly.append(uid)
	if not newly.is_empty():
		_save()
	return newly


static func record_game(stats: Dictionary) -> Array:
	# stats: {time, kills, level, damage, taken, build: {weapons, passives}}
	ensure_loaded()
	var t: float = float(stats.get("time", 0.0))
	var k: int = int(stats.get("kills", 0))
	var lv: int = int(stats.get("level", 1))
	var dmg: float = float(stats.get("damage", 0.0))
	# 更新最佳
	if t > float(_data.get("best_time", 0.0)):
		_data["best_time"] = t
	if k > int(_data.get("best_kills", 0)):
		_data["best_kills"] = k
	if lv > int(_data.get("best_level", 1)):
		_data["best_level"] = lv
	if dmg > float(_data.get("best_damage", 0.0)):
		_data["best_damage"] = dmg
	_data["total_kills"] = int(_data.get("total_kills", 0)) + k
	_data["total_games"] = int(_data.get("total_games", 0)) + 1
	_data["total_damage"] = float(_data.get("total_damage", 0.0)) + dmg
	_save()
	# 解锁检测（基于最新 totals 与本局 stats 合并）
	var merged: Dictionary = stats.duplicate(true)
	merged["total_kills"] = _data["total_kills"]
	merged["best_time"] = _data["best_time"]
	return check_and_unlock(merged)


static func clear() -> void:
	_data = _defaults()
	var dir: String = SAVE_PATH.get_base_dir()
	# ConfigFile 删除：直接覆盖为空后保存默认值或删除文件
	var cfg := ConfigFile.new()
	# 尝试删除文件
	if FileAccess.file_exists(SAVE_PATH):
		var abs_path: String = ProjectSettings.globalize_path(SAVE_PATH)
		var err: int = DirAccess.remove_absolute(abs_path)
		if err != OK:
			# 回退：覆盖为默认值
			_save()
			return
	_dirty = false
	_loaded = true


static func get_unlock_progress() -> Dictionary:
	ensure_loaded()
	var gd := preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	var out: Dictionary = {}
	for uid in gd.unlocks.keys():
		var u: Dictionary = gd.unlocks[uid] as Dictionary
		out[uid] = {
			"name": str(u.get("name", uid)),
			"desc": str(u.get("desc", "")),
			"unlocked": bool((_data["unlocks"] as Dictionary).get(uid, false)),
			"kind": str(u.get("kind", "")),
			"need": float(u.get("need", 0.0)),
		}
	return out
