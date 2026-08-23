extends RefCounted
class_name Settings

# 全局设置持久化 - 保存至 user://settings.cfg
# 支持音量、震动、显示等跨启动保存

const PATH := "user://settings.cfg"

static var master_volume: float = 0.8 # 0..1
static var music_volume: float = 0.7 # 0..1
static var sfx_volume: float = 0.85 # 0..1
static var shake_enabled: bool = true
static var flash_enabled: bool = true # 强闪烁/命中高亮
static var fps_visible: bool = false
static var vibrate_enabled: bool = true

static var _loaded: bool = false
static var _test_storage_path: String = ""


static func get_storage_path() -> String:
	return _test_storage_path if not _test_storage_path.is_empty() else PATH


static func set_test_storage_path(path: String) -> bool:
	if path.is_empty():
		push_error("[Settings] 测试设置路径不能为空")
		return false
	if not path.begins_with("user://"):
		push_error("[Settings] 测试设置路径必须位于 user://")
		return false
	var resolved_path: String = ProjectSettings.globalize_path(path).simplify_path()
	var production_path: String = ProjectSettings.globalize_path(PATH).simplify_path()
	if resolved_path == production_path:
		push_error("[Settings] 测试设置路径不能指向生产设置")
		return false
	_test_storage_path = path
	_reset_runtime_state()
	return true


static func reset_test_storage_path() -> void:
	_test_storage_path = ""
	_reset_runtime_state()


static func _reset_runtime_state() -> void:
	_loaded = false
	_set_defaults()


static func _set_defaults() -> void:
	master_volume = 0.8
	music_volume = 0.7
	sfx_volume = 0.85
	shake_enabled = true
	flash_enabled = true
	fps_visible = false
	vibrate_enabled = true


static func ensure_loaded() -> void:
	if _loaded:
		return
	load_settings()
	_loaded = true


static func reset_to_default() -> void:
	_set_defaults()
	_apply_audio()
	_save_internal()


static func load_settings() -> void:
	_set_defaults()
	var storage_path: String = get_storage_path()
	var cfg := ConfigFile.new()
	var err: int = cfg.load(storage_path)
	if err != OK:
		# 首次启动或无文件，使用默认值并保存一次
		if err != ERR_FILE_NOT_FOUND:
			push_warning("[Settings] 损坏或无法读取 %s err=%d，使用默认值" % [storage_path, err])
		_apply_audio()
		_save_internal()
		_loaded = true
		return
	master_volume = float(cfg.get_value("audio", "master_volume", 0.8))
	music_volume = float(cfg.get_value("audio", "music_volume", 0.7))
	sfx_volume = float(cfg.get_value("audio", "sfx_volume", 0.85))
	shake_enabled = bool(cfg.get_value("game", "shake_enabled", true))
	flash_enabled = bool(cfg.get_value("game", "flash_enabled", true))
	fps_visible = bool(cfg.get_value("display", "fps_visible", false))
	vibrate_enabled = bool(cfg.get_value("input", "vibrate_enabled", true))
	master_volume = clampf(master_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	_apply_audio()
	_loaded = true


static func save_settings() -> void:
	_save_internal()


static func _save_internal() -> bool:
	var storage_path: String = get_storage_path()
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("game", "shake_enabled", shake_enabled)
	cfg.set_value("game", "flash_enabled", flash_enabled)
	cfg.set_value("display", "fps_visible", fps_visible)
	cfg.set_value("input", "vibrate_enabled", vibrate_enabled)
	var err: int = cfg.save(storage_path)
	if err != OK:
		push_error("[Settings] 保存失败 %s err=%d" % [storage_path, err])
		return false
	return true


static func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save_settings()


static func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save_settings()


static func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save_settings()


static func set_shake_enabled(v: bool) -> void:
	shake_enabled = v
	save_settings()


static func set_flash_enabled(v: bool) -> void:
	flash_enabled = v
	save_settings()


static func set_fps_visible(v: bool) -> void:
	fps_visible = v
	save_settings()


static func _apply_audio() -> void:
	var m_db: float = linear_to_db(master_volume) if master_volume > 0.001 else -80.0
	var mu_db: float = linear_to_db(music_volume) if music_volume > 0.001 else -80.0
	var s_db: float = linear_to_db(sfx_volume) if sfx_volume > 0.001 else -80.0
	var master_bus: int = AudioServer.get_bus_index("Master")
	if master_bus != -1:
		AudioServer.set_bus_volume_db(master_bus, m_db)
		AudioServer.set_bus_mute(master_bus, master_volume <= 0.001)
	var music_bus: int = AudioServer.get_bus_index("Music")
	if music_bus != -1:
		AudioServer.set_bus_volume_db(music_bus, mu_db)
		AudioServer.set_bus_mute(music_bus, music_volume <= 0.001)
	var sfx_bus: int = AudioServer.get_bus_index("Sfx")
	if sfx_bus != -1:
		AudioServer.set_bus_volume_db(sfx_bus, s_db)
		AudioServer.set_bus_mute(sfx_bus, sfx_volume <= 0.001)


static func is_shake_enabled() -> bool:
	ensure_loaded()
	return shake_enabled


static func is_flash_enabled() -> bool:
	ensure_loaded()
	return flash_enabled


static func get_music_volume() -> float:
	ensure_loaded()
	return music_volume


static func get_sfx_volume() -> float:
	ensure_loaded()
	return sfx_volume


static func get_master_volume() -> float:
	ensure_loaded()
	return master_volume
