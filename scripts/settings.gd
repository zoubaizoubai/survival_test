extends RefCounted
class_name Settings

# 全局设置持久化 - 保存至 user://settings.cfg
# 支持音量、震动、显示等跨启动保存

const PATH := "user://settings.cfg"

static var master_volume: float = 0.8 # 0..1
static var shake_enabled: bool = true
static var fps_visible: bool = false
static var vibrate_enabled: bool = true

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	load_settings()
	_loaded = true


static func reset_to_default() -> void:
	master_volume = 0.8
	shake_enabled = true
	fps_visible = false
	vibrate_enabled = true
	_apply_audio()
	_save_internal()


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(PATH)
	if err != OK:
		# 首次启动或无文件，使用默认值并保存一次
		_apply_audio()
		_save_internal()
		_loaded = true
		return
	master_volume = float(cfg.get_value("audio", "master_volume", 0.8))
	shake_enabled = bool(cfg.get_value("game", "shake_enabled", true))
	fps_visible = bool(cfg.get_value("display", "fps_visible", false))
	vibrate_enabled = bool(cfg.get_value("input", "vibrate_enabled", true))
	master_volume = clampf(master_volume, 0.0, 1.0)
	_apply_audio()
	_loaded = true


static func save_settings() -> void:
	_save_internal()


static func _save_internal() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("game", "shake_enabled", shake_enabled)
	cfg.set_value("display", "fps_visible", fps_visible)
	cfg.set_value("input", "vibrate_enabled", vibrate_enabled)
	cfg.save(PATH)


static func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save_settings()


static func set_shake_enabled(v: bool) -> void:
	shake_enabled = v
	save_settings()


static func set_fps_visible(v: bool) -> void:
	fps_visible = v
	save_settings()


static func _apply_audio() -> void:
	var db: float = linear_to_db(master_volume) if master_volume > 0.001 else -80.0
	var bus: int = AudioServer.get_bus_index("Master")
	if bus != -1:
		AudioServer.set_bus_volume_db(bus, db)
		AudioServer.set_bus_mute(bus, master_volume <= 0.001)


static func is_shake_enabled() -> bool:
	ensure_loaded()
	return shake_enabled


static func get_master_volume() -> float:
	ensure_loaded()
	return master_volume
