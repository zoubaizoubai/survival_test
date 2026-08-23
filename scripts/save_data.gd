extends RefCounted
class_name SaveData

# 轻量存档：跨启动保存最佳记录与解锁，带版本迁移与损坏回退
# 存储于 user://progress.cfg，使用 ConfigFile

const SAVE_PATH := "user://progress.cfg"
const VERSION := 1

static var _loaded: bool = false
static var _data: Dictionary = {}
static var _dirty: bool = false
static var _test_storage_path: String = ""
static var _future_version: int = 0

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


static func get_storage_path() -> String:
	return _test_storage_path if not _test_storage_path.is_empty() else SAVE_PATH


static func set_test_storage_path(path: String) -> bool:
	if path.is_empty():
		push_error("[SaveData] 测试存档路径不能为空")
		return false
	if not path.begins_with("user://"):
		push_error("[SaveData] 测试存档路径必须位于 user://")
		return false
	var resolved_path: String = ProjectSettings.globalize_path(path).simplify_path()
	var production_path: String = ProjectSettings.globalize_path(SAVE_PATH).simplify_path()
	if resolved_path == production_path:
		push_error("[SaveData] 测试存档路径不能指向生产存档")
		return false
	_test_storage_path = path
	_reset_runtime_state()
	return true


static func reset_test_storage_path() -> void:
	_test_storage_path = ""
	_reset_runtime_state()


static func _reset_runtime_state() -> void:
	_loaded = false
	_data = _defaults()
	_dirty = false
	_future_version = 0


static func ensure_loaded() -> void:
	if _loaded:
		return
	_load()
	_loaded = true


static func _load() -> void:
	_data = _defaults()
	_future_version = 0
	var storage_path: String = get_storage_path()
	var cfg := ConfigFile.new()
	var err: int = cfg.load(storage_path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("[SaveData] 损坏或无法读取 %s err=%d，使用默认值" % [storage_path, err])
		_dirty = false
		return
	# 版本
	var ver: int = int(cfg.get_value("save", "version", VERSION))
	var migrated: bool = ver < VERSION
	if migrated:
		# 轻量迁移：保留可用字段，其余回退默认值
		push_warning("[SaveData] 版本迁移 %d -> %d" % [ver, VERSION])
	elif ver > VERSION:
		# 旧版客户端只能只读未来版本的已知字段，绝不能降写并丢弃未知数据。
		_future_version = ver
		push_warning("[SaveData] 存档版本 %d 高于当前支持版本 %d，本次运行只读" % [ver, VERSION])
	# 读取字段，缺失则保留默认值
	for k in _data.keys():
		if k == "version" or k == "unlocks":
			continue
		if cfg.has_section_key("save", k):
			_data[k] = cfg.get_value("save", k)
	_data["version"] = ver if _future_version > VERSION else VERSION
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
	_dirty = migrated
	if migrated:
		_save()


static func _save(allow_future_overwrite: bool = false) -> bool:
	if _future_version > VERSION and not allow_future_overwrite:
		return false
	var storage_path: String = get_storage_path()
	var cfg := ConfigFile.new()
	for k in _data.keys():
		if k == "unlocks":
			continue
		cfg.set_value("save", k, _data[k])
	for uk in (_data["unlocks"] as Dictionary).keys():
		cfg.set_value("unlocks", uk, true)
	var err: int = cfg.save(storage_path)
	if err != OK:
		push_error("[SaveData] 保存失败 %s err=%d" % [storage_path, err])
		return false
	_dirty = false
	return true


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
	if _future_version > VERSION:
		return []
	var previous_unlocks: Dictionary = (_data["unlocks"] as Dictionary).duplicate(true)
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
	if not newly.is_empty() and not _save():
		# 写入失败时不能让当前会话假装已解锁，否则重启后
		# 状态会突然回退。
		_data["unlocks"] = previous_unlocks
		return []
	return newly


static func record_game(stats: Dictionary) -> Array:
	# stats: {time, kills, level, damage, taken, build: {weapons, passives}}
	ensure_loaded()
	if _future_version > VERSION:
		return []
	var previous_data: Dictionary = _data.duplicate(true)
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
	if not _save():
		# 保持内存与磁盘一致，避免结算后显示一个实际未
		# 持久化的“新纪录”。
		_data = previous_data
		return []
	# 解锁检测（基于最新 totals 与本局 stats 合并）
	var merged: Dictionary = stats.duplicate(true)
	merged["total_kills"] = _data["total_kills"]
	merged["best_time"] = _data["best_time"]
	return check_and_unlock(merged)


static func extend_recorded_game(stats: Dictionary, checkpoint: Dictionary) -> Array:
	# 用于已经 record_game 的对局继续无尽模式后再结算。
	# checkpoint 是首次结算时的 stats；只累计其后增量，不重复增加局数。
	ensure_loaded()
	if _future_version > VERSION:
		return []
	var previous_data: Dictionary = _data.duplicate(true)
	var t: float = float(stats.get("time", 0.0))
	var k: int = int(stats.get("kills", 0))
	var lv: int = int(stats.get("level", 1))
	var dmg: float = float(stats.get("damage", 0.0))
	var checkpoint_kills: int = int(checkpoint.get("kills", 0))
	var checkpoint_damage: float = float(checkpoint.get("damage", 0.0))
	if t > float(_data.get("best_time", 0.0)):
		_data["best_time"] = t
	if k > int(_data.get("best_kills", 0)):
		_data["best_kills"] = k
	if lv > int(_data.get("best_level", 1)):
		_data["best_level"] = lv
	if dmg > float(_data.get("best_damage", 0.0)):
		_data["best_damage"] = dmg
	_data["total_kills"] = int(_data.get("total_kills", 0)) + maxi(k - checkpoint_kills, 0)
	_data["total_damage"] = float(_data.get("total_damage", 0.0)) + maxf(dmg - checkpoint_damage, 0.0)
	if not _save():
		_data = previous_data
		return []
	var merged: Dictionary = stats.duplicate(true)
	merged["total_kills"] = _data["total_kills"]
	merged["best_time"] = _data["best_time"]
	return check_and_unlock(merged)


static func clear() -> bool:
	ensure_loaded()
	var previous_data: Dictionary = _data.duplicate(true)
	var previous_dirty: bool = _dirty
	var previous_future_version: int = _future_version
	_data = _defaults()
	var storage_path: String = get_storage_path()
	# ConfigFile 删除：直接覆盖为空后保存默认值或删除文件
	# 尝试删除文件
	if FileAccess.file_exists(storage_path):
		var abs_path: String = ProjectSettings.globalize_path(storage_path)
		var err: int = DirAccess.remove_absolute(abs_path)
		if err != OK:
			# 回退：覆盖为默认值
			push_warning("[SaveData] 删除失败 %s err=%d，尝试覆盖默认存档" % [storage_path, err])
			if not _save(true):
				# 磁盘仍保留旧存档时同步恢复内存，避免 UI 假装清档成功。
				_data = previous_data
				_dirty = previous_dirty
				_future_version = previous_future_version
				return false
			_future_version = 0
			return true
	_dirty = false
	_loaded = true
	_future_version = 0
	return true


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
