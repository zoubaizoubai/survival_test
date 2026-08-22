extends RefCounted
class_name GameData

# 集中数值管理 - 从 res://data/balance.json 读取，启动时校验
# 若文件缺失或校验失败，回退至内置默认值，保证游戏可运行

const BALANCE_PATH := "res://data/balance.json"

static var weapons: Dictionary = {}
static var passives: Dictionary = {}
static var enemies: Dictionary = {}
static var spawn: Dictionary = {}
static var evolutions: Array = []
static var unlocks: Dictionary = {}
static var arena: float = 2600.0
static var goal_time: float = 300.0
static var max_enemies: int = 170
static var spawn_radius: float = 820.0

static var _loaded: bool = false
static var _errors: Array = []
static var _warnings: Array = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	_load_all()
	_loaded = true


static func is_loaded() -> bool:
	return _loaded


static func get_errors() -> Array:
	ensure_loaded()
	return _errors.duplicate()


static func get_warnings() -> Array:
	ensure_loaded()
	return _warnings.duplicate()


static func _load_all() -> void:
	_errors.clear()
	_warnings.clear()
	var file := FileAccess.open(BALANCE_PATH, FileAccess.READ)
	if file == null:
		_warnings.append("无法读取 %s (error %d)，使用内置默认值" % [BALANCE_PATH, FileAccess.get_open_error()])
		_load_defaults()
		_validate()
		return
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		_errors.append("JSON 解析失败 %s: %s (at line %d)" % [BALANCE_PATH, json.get_error_message(), json.get_error_line()])
		_load_defaults()
		_validate()
		return
	var data: Variant = json.data
	if not data is Dictionary:
		_errors.append("根对象非 Dictionary")
		_load_defaults()
		_validate()
		return
	var dict: Dictionary = data as Dictionary
	weapons = _parse_weapons(dict.get("weapons", {}))
	passives = _parse_passives(dict.get("passives", {}))
	enemies = _parse_enemies(dict.get("enemies", {}))
	spawn = dict.get("spawn", {}) as Dictionary
	evolutions = _parse_evolutions(dict.get("evolutions", []))
	unlocks = _parse_unlocks(dict.get("unlocks", {}))
	# 兼容：若 spawn 为空则回退
	if spawn.is_empty():
		_warnings.append("spawn 为空，使用内置默认值")
		spawn = _default_spawn()
	# 同步快捷字段
	arena = float(spawn.get("arena", 2600.0))
	goal_time = float(spawn.get("goal_time", 300.0))
	max_enemies = int(spawn.get("max_enemies", 170))
	spawn_radius = float(spawn.get("spawn_radius", 820.0))
	_validate()


static func _load_defaults() -> void:
	weapons = _default_weapons()
	passives = _default_passives()
	enemies = _default_enemies()
	spawn = _default_spawn()
	evolutions = _default_evolutions()
	unlocks = _default_unlocks()
	arena = float(spawn["arena"])
	goal_time = float(spawn["goal_time"])
	max_enemies = int(spawn["max_enemies"])
	spawn_radius = float(spawn["spawn_radius"])


static func _parse_weapons(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		_errors.append("weapons 非 Dictionary")
		return _default_weapons()
	var dict: Dictionary = raw as Dictionary
	for id in dict.keys():
		var v: Variant = dict[id]
		if not v is Dictionary:
			_errors.append("weapons[%s] 非 Dictionary" % str(id))
			continue
		var wd: Dictionary = v as Dictionary
		var color_raw: Variant = wd.get("color", {})
		var color: Color = _to_color(color_raw, "weapons[%s].color" % str(id))
		var levels_raw: Variant = wd.get("levels", [])
		if not levels_raw is Array:
			_errors.append("weapons[%s].levels 非 Array" % str(id))
			continue
		var levels: Array = []
		for lv in levels_raw as Array:
			if lv is Dictionary:
				levels.append((lv as Dictionary).duplicate(true))
			else:
				_errors.append("weapons[%s].levels 元素非 Dictionary" % str(id))
		var entry: Dictionary = {
			"name": str(wd.get("name", id)),
			"color": color,
			"desc": str(wd.get("desc", "")),
			"levels": levels,
		}
		if wd.has("evo"):
			entry["evo"] = bool(wd["evo"])
		if wd.has("locked"):
			entry["locked"] = bool(wd["locked"])
		if wd.has("unlock_id"):
			entry["unlock_id"] = str(wd["unlock_id"])
		out[id] = entry
	if out.is_empty():
		_warnings.append("weapons 为空，回退默认值")
		return _default_weapons()
	return out


static func _parse_passives(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		_errors.append("passives 非 Dictionary")
		return _default_passives()
	var dict: Dictionary = raw as Dictionary
	for id in dict.keys():
		var v: Variant = dict[id]
		if not v is Dictionary:
			_errors.append("passives[%s] 非 Dictionary" % str(id))
			continue
		var pd: Dictionary = v as Dictionary
		var color_raw: Variant = pd.get("color", {})
		var color: Color = _to_color(color_raw, "passives[%s].color" % str(id))
		out[id] = {
			"name": str(pd.get("name", id)),
			"desc": str(pd.get("desc", "")),
			"max": int(pd.get("max", 1)),
			"color": color,
		}
	if out.is_empty():
		_warnings.append("passives 为空，回退默认值")
		return _default_passives()
	return out


static func _parse_evolutions(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			_errors.append("evolutions 非 Array")
		return _default_evolutions()
	for idx in (raw as Array).size():
		var v: Variant = (raw as Array)[idx]
		if not v is Dictionary:
			_errors.append("evolutions[%d] 非 Dictionary" % idx)
			continue
		var d: Dictionary = v as Dictionary
		if not d.has("weapon") or not d.has("passive") or not d.has("result"):
			_errors.append("evolutions[%d] 缺少 weapon/passive/result" % idx)
			continue
		out.append(d.duplicate(true))
	if out.is_empty():
		_warnings.append("evolutions 为空，使用默认值")
		return _default_evolutions()
	return out


static func _parse_unlocks(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		if raw is Array and (raw as Array).is_empty():
			return _default_unlocks()
		_errors.append("unlocks 非 Dictionary")
		return _default_unlocks()
	for id in (raw as Dictionary).keys():
		var v: Variant = (raw as Dictionary)[id]
		if not v is Dictionary:
			_errors.append("unlocks[%s] 非 Dictionary" % str(id))
			continue
		var d: Dictionary = v as Dictionary
		if not d.has("name") or not d.has("desc"):
			_errors.append("unlocks[%s] 缺少 name/desc" % str(id))
			continue
		out[id] = d.duplicate(true)
	if out.is_empty():
		_warnings.append("unlocks 为空，使用默认值")
		return _default_unlocks()
	return out


static func _parse_enemies(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		_errors.append("enemies 非 Dictionary")
		return _default_enemies()
	var dict: Dictionary = raw as Dictionary
	for id in dict.keys():
		var v: Variant = dict[id]
		if not v is Dictionary:
			_errors.append("enemies[%s] 非 Dictionary" % str(id))
			continue
		var ed: Dictionary = v as Dictionary
		var color_raw: Variant = ed.get("color", {})
		var color: Color = _to_color(color_raw, "enemies[%s].color" % str(id))
		var entry: Dictionary = {
			"hp": float(ed.get("hp", 10.0)),
			"spd": float(ed.get("spd", 50.0)),
			"dmg": float(ed.get("dmg", 5.0)),
			"r": float(ed.get("r", 10.0)),
			"xp": int(ed.get("xp", 1)),
			"color": color,
		}
		# 保留扩展行为字段（数据驱动），不校验具体类型以保持前向兼容
		for ek in ed.keys():
			if ek in ["hp", "spd", "dmg", "r", "xp", "color"]:
				continue
			entry[ek] = ed[ek]
		# 嵌套 phases 颜色需转换为 Color
		if entry.has("phases") and entry["phases"] is Array:
			var phases: Array = entry["phases"] as Array
			for pi in phases.size():
				var ph: Variant = phases[pi]
				if ph is Dictionary:
					var pd: Dictionary = ph as Dictionary
					if pd.has("color"):
						pd["color"] = _to_color(pd["color"], "enemies[%s].phases[%d].color" % [str(id), pi])
		out[id] = entry
	if out.is_empty():
		_warnings.append("enemies 为空，回退默认值")
		return _default_enemies()
	return out


static func _to_color(raw: Variant, ctx: String) -> Color:
	if raw is Color:
		return raw as Color
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		var r: float = float(d.get("r", 1.0))
		var g: float = float(d.get("g", 1.0))
		var b: float = float(d.get("b", 1.0))
		var a: float = float(d.get("a", 1.0))
		return Color(r, g, b, a)
	if raw is String:
		var s: String = raw as String
		var c: Color = Color.from_string(s, Color.WHITE)
		return c
	if raw is Array:
		var arr: Array = raw as Array
		if arr.size() >= 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]) if arr.size() >= 4 else 1.0)
	_warnings.append("%s 颜色格式无法解析，使用白色" % ctx)
	return Color.WHITE


static func _validate() -> void:
	# 武器校验
	for id in weapons.keys():
		var w: Dictionary = weapons[id] as Dictionary
		if not w.has("name") or str(w["name"]).is_empty():
			_errors.append("weapons[%s].name 缺失" % str(id))
		if not w.has("levels") or not w["levels"] is Array or (w["levels"] as Array).is_empty():
			_errors.append("weapons[%s].levels 缺失或空" % str(id))
		else:
			var levels: Array = w["levels"] as Array
			for idx in levels.size():
				var lv: Variant = levels[idx]
				if not lv is Dictionary:
					_errors.append("weapons[%s].levels[%d] 非 Dictionary" % [str(id), idx])
					continue
				var d: Dictionary = lv as Dictionary
				# 按武器类型检查必要字段
				match str(id):
					"dagger":
						for k in ["count", "dmg", "cd", "pierce"]:
							if not d.has(k):
								_errors.append("weapons[dagger].levels[%d] 缺少 %s" % [idx, k])
					"orbit":
						for k in ["orbs", "dmg", "radius", "rot"]:
							if not d.has(k):
								_errors.append("weapons[orbit].levels[%d] 缺少 %s" % [idx, k])
					"lightning":
						for k in ["cd", "strikes", "dmg", "aoe"]:
							if not d.has(k):
								_errors.append("weapons[lightning].levels[%d] 缺少 %s" % [idx, k])
					"aura":
						for k in ["radius", "dps"]:
							if not d.has(k):
								_errors.append("weapons[aura].levels[%d] 缺少 %s" % [idx, k])
	# 被动校验
	for id in passives.keys():
		var p: Dictionary = passives[id] as Dictionary
		if not p.has("name") or str(p["name"]).is_empty():
			_errors.append("passives[%s].name 缺失" % str(id))
		if not p.has("max") or int(p["max"]) <= 0:
			_errors.append("passives[%s].max 非法" % str(id))
	# 敌人校验
	for id in enemies.keys():
		var e: Dictionary = enemies[id] as Dictionary
		for k in ["hp", "spd", "dmg", "r", "xp"]:
			if not e.has(k):
				_errors.append("enemies[%s] 缺少 %s" % [str(id), k])
		if e.has("r") and float(e["r"]) <= 0:
			_errors.append("enemies[%s].r 非法" % str(id))
	# 生成曲线校验
	if spawn.has("arena") and float(spawn["arena"]) <= 0:
		_errors.append("spawn.arena 非法")
	if spawn.has("goal_time") and float(spawn["goal_time"]) <= 0:
		_errors.append("spawn.goal_time 非法")
	if spawn.has("max_enemies") and int(spawn["max_enemies"]) <= 0:
		_errors.append("spawn.max_enemies 非法")
	if spawn.has("boss_times"):
		var bt: Variant = spawn["boss_times"]
		if not bt is Array:
			_errors.append("spawn.boss_times 非 Array")
		else:
			for v in bt as Array:
				if not v is float and not v is int:
					_errors.append("spawn.boss_times 元素非数值")
	if spawn.has("kind_thresholds"):
		var kt: Variant = spawn["kind_thresholds"]
		if not kt is Array:
			_errors.append("spawn.kind_thresholds 非 Array")
		else:
			for entry in kt as Array:
				if not entry is Dictionary:
					_errors.append("spawn.kind_thresholds 元素非 Dictionary")
					continue
				var d: Dictionary = entry as Dictionary
				if not d.has("elapsed_lt") or not d.has("weights"):
					_errors.append("spawn.kind_thresholds 元素缺少 elapsed_lt/weights")
	if spawn.has("waves"):
		var wv: Variant = spawn["waves"]
		if not wv is Array:
			_errors.append("spawn.waves 非 Array")
		else:
			for wi in (wv as Array).size():
				var w: Variant = (wv as Array)[wi]
				if not w is Dictionary:
					_errors.append("spawn.waves[%d] 非 Dictionary" % wi)
					continue
				var wd: Dictionary = w as Dictionary
				if not wd.has("t") or not wd.has("weights"):
					_errors.append("spawn.waves[%d] 缺少 t/weights" % wi)
				if wd.has("weights") and not wd["weights"] is Dictionary:
					_errors.append("spawn.waves[%d].weights 非 Dictionary" % wi)
	# 进化校验
	for idx in evolutions.size():
		var ev: Variant = evolutions[idx]
		if not ev is Dictionary:
			continue
		var ed: Dictionary = ev as Dictionary
		for k in ["weapon", "passive", "result"]:
			if not ed.has(k):
				_errors.append("evolutions[%d] 缺少 %s" % [idx, k])
		if ed.has("weapon") and not weapons.has(str(ed["weapon"])):
			_errors.append("evolutions[%d] weapon %s 不存在" % [idx, str(ed["weapon"])])
		if ed.has("passive") and not passives.has(str(ed["passive"])):
			_errors.append("evolutions[%d] passive %s 不存在" % [idx, str(ed["passive"])])
		if ed.has("result") and not weapons.has(str(ed["result"])):
			_errors.append("evolutions[%d] result %s 不存在" % [idx, str(ed["result"])])
	# 解锁校验
	for id in unlocks.keys():
		var u: Dictionary = unlocks[id] as Dictionary
		if not u.has("kind") or not u.has("need"):
			_errors.append("unlocks[%s] 缺少 kind/need" % str(id))
	# boss 阶段校验（enemies[boss].phases）
	if enemies.has("boss") and (enemies["boss"] as Dictionary).has("phases"):
		var phs: Variant = (enemies["boss"] as Dictionary)["phases"]
		if not phs is Array:
			_errors.append("enemies[boss].phases 非 Array")
		else:
			for pi in (phs as Array).size():
				var pp: Variant = (phs as Array)[pi]
				if not pp is Dictionary:
					_errors.append("enemies[boss].phases[%d] 非 Dictionary" % pi)
					continue
				var pd2: Dictionary = pp as Dictionary
				if not pd2.has("hp_pct"):
					_errors.append("enemies[boss].phases[%d] 缺少 hp_pct" % pi)


# ---------- 内置默认值（与原 hardcode 完全一致，保证回退行为不变） ----------
static func _default_weapons() -> Dictionary:
	return {
		"dagger": {
			"name": "飞刀", "color": Color(0.65, 0.9, 1.0),
			"desc": "自动射向最近的敌人，可穿透",
			"levels": [
				{"count": 1, "dmg": 12.0, "cd": 0.85, "pierce": 1},
				{"count": 2, "dmg": 12.0, "cd": 0.85, "pierce": 1},
				{"count": 2, "dmg": 16.0, "cd": 0.78, "pierce": 2},
				{"count": 3, "dmg": 16.0, "cd": 0.72, "pierce": 2},
				{"count": 3, "dmg": 21.0, "cd": 0.66, "pierce": 3},
				{"count": 4, "dmg": 21.0, "cd": 0.60, "pierce": 3},
				{"count": 5, "dmg": 26.0, "cd": 0.54, "pierce": 4},
				{"count": 6, "dmg": 32.0, "cd": 0.46, "pierce": 5},
			],
		},
		"orbit": {
			"name": "环绕之刃", "color": Color(0.75, 0.85, 1.0),
			"desc": "利刃围绕你旋转，切碎靠近的敌人",
			"levels": [
				{"orbs": 2, "dmg": 10.0, "radius": 70.0, "rot": 3.2},
				{"orbs": 3, "dmg": 10.0, "radius": 74.0, "rot": 3.4},
				{"orbs": 3, "dmg": 14.0, "radius": 78.0, "rot": 3.6},
				{"orbs": 4, "dmg": 14.0, "radius": 82.0, "rot": 3.8},
				{"orbs": 5, "dmg": 18.0, "radius": 86.0, "rot": 4.0},
				{"orbs": 5, "dmg": 23.0, "radius": 92.0, "rot": 4.3},
				{"orbs": 6, "dmg": 28.0, "radius": 98.0, "rot": 4.6},
				{"orbs": 7, "dmg": 34.0, "radius": 105.0, "rot": 5.0},
			],
		},
		"lightning": {
			"name": "雷霆", "color": Color(0.8, 0.9, 1.0),
			"desc": "闪电随机劈向屏幕内的敌人并溅射",
			"levels": [
				{"cd": 2.4, "strikes": 1, "dmg": 30.0, "aoe": 70.0},
				{"cd": 2.2, "strikes": 2, "dmg": 30.0, "aoe": 70.0},
				{"cd": 2.0, "strikes": 2, "dmg": 42.0, "aoe": 80.0},
				{"cd": 1.8, "strikes": 3, "dmg": 42.0, "aoe": 80.0},
				{"cd": 1.6, "strikes": 3, "dmg": 56.0, "aoe": 90.0},
				{"cd": 1.4, "strikes": 4, "dmg": 56.0, "aoe": 90.0},
				{"cd": 1.2, "strikes": 5, "dmg": 72.0, "aoe": 100.0},
				{"cd": 1.0, "strikes": 6, "dmg": 90.0, "aoe": 110.0},
			],
		},
		"aura": {
			"name": "圣光领域", "color": Color(1.0, 0.88, 0.45),
			"desc": "神圣领域持续灼烧周围的敌人",
			"levels": [
				{"radius": 90.0, "dps": 12.0},
				{"radius": 105.0, "dps": 12.0},
				{"radius": 105.0, "dps": 18.0},
				{"radius": 120.0, "dps": 18.0},
				{"radius": 135.0, "dps": 26.0},
				{"radius": 150.0, "dps": 26.0},
				{"radius": 165.0, "dps": 36.0},
				{"radius": 185.0, "dps": 48.0},
			],
		},
		"boomerang": {
			"name": "回旋斧", "color": Color(0.52, 0.85, 0.35),
			"desc": "投掷回旋斧，往返穿透敌人",
			"levels": [
				{"count": 1, "dmg": 16.0, "cd": 1.6, "pierce": 2, "speed": 420.0, "return_time": 0.45},
				{"count": 1, "dmg": 16.0, "cd": 1.5, "pierce": 3, "speed": 430.0, "return_time": 0.45},
				{"count": 1, "dmg": 20.0, "cd": 1.4, "pierce": 3, "speed": 440.0, "return_time": 0.45},
				{"count": 2, "dmg": 20.0, "cd": 1.3, "pierce": 3, "speed": 450.0, "return_time": 0.45},
				{"count": 2, "dmg": 26.0, "cd": 1.2, "pierce": 4, "speed": 460.0, "return_time": 0.45},
				{"count": 2, "dmg": 32.0, "cd": 1.0, "pierce": 4, "speed": 475.0, "return_time": 0.45},
				{"count": 3, "dmg": 38.0, "cd": 0.9, "pierce": 5, "speed": 490.0, "return_time": 0.45},
				{"count": 3, "dmg": 45.0, "cd": 0.8, "pierce": 6, "speed": 500.0, "return_time": 0.45},
			],
		},
		"frost": {
			"name": "寒霜新星", "color": Color(0.55, 0.75, 1.0),
			"desc": "周期性冰环冲击，减速敌人",
			"levels": [
				{"radius": 110.0, "dmg": 14.0, "cd": 3.2, "slow": 0.30, "slow_time": 1.2},
				{"radius": 125.0, "dmg": 14.0, "cd": 2.9, "slow": 0.35, "slow_time": 1.3},
				{"radius": 125.0, "dmg": 20.0, "cd": 2.9, "slow": 0.35, "slow_time": 1.3},
				{"radius": 140.0, "dmg": 20.0, "cd": 2.6, "slow": 0.40, "slow_time": 1.4},
				{"radius": 155.0, "dmg": 28.0, "cd": 2.6, "slow": 0.40, "slow_time": 1.5},
				{"radius": 170.0, "dmg": 36.0, "cd": 2.3, "slow": 0.45, "slow_time": 1.6},
				{"radius": 185.0, "dmg": 44.0, "cd": 2.0, "slow": 0.50, "slow_time": 1.8},
				{"radius": 200.0, "dmg": 56.0, "cd": 1.8, "slow": 0.55, "slow_time": 2.0},
			],
		},
		"dagger_evo": {
			"name": "风暴飞刀·极", "color": Color(0.85, 0.97, 1.0),
			"desc": "飞刀·进化：数量与穿透质变，风暴席卷",
			"evo": true,
			"levels": [
				{"count": 7, "dmg": 48.0, "cd": 0.38, "pierce": 8},
			],
		},
		"boomerang_evo": {
			"name": "回旋风暴·极", "color": Color(0.62, 0.95, 0.45),
			"desc": "回旋斧·进化：四斧齐旋，极速往返",
			"evo": true,
			"levels": [
				{"count": 4, "dmg": 52.0, "cd": 0.65, "pierce": 8, "speed": 520.0, "return_time": 0.4},
			],
		},
		"frost_evo": {
			"name": "永冬领域·极", "color": Color(0.72, 0.85, 1.0),
			"desc": "寒霜·进化：超大范围永冻，新星常驻",
			"evo": true,
			"levels": [
				{"radius": 250.0, "dmg": 72.0, "cd": 1.45, "slow": 0.65, "slow_time": 2.8},
			],
		},
		"orbit_evo": {
			"name": "轨道绞肉机·极", "color": Color(0.88, 0.92, 1.0),
			"desc": "环刃·进化：八刃超旋，半径质变",
			"evo": true,
			"levels": [
				{"orbs": 9, "dmg": 42.0, "radius": 125.0, "rot": 5.8},
			],
		},
	}


static func _default_passives() -> Dictionary:
	return {
		"damage": {"name": "力量祝福", "desc": "所有伤害 +15%", "max": 5, "color": Color(1.0, 0.45, 0.4)},
		"haste": {"name": "急速祝福", "desc": "武器冷却 -8%", "max": 5, "color": Color(1.0, 0.8, 0.35)},
		"speed": {"name": "疾风祝福", "desc": "移动速度 +10%", "max": 4, "color": Color(0.5, 0.95, 0.6)},
		"hp": {"name": "生命祝福", "desc": "生命上限 +25 并回复 25", "max": 5, "color": Color(1.0, 0.5, 0.65)},
		"magnet": {"name": "磁力祝福", "desc": "拾取范围 +45%", "max": 4, "color": Color(0.55, 0.75, 1.0)},
	}


static func _default_evolutions() -> Array:
	return [
		{"weapon": "dagger", "passive": "damage", "need_weapon_lv": 8, "need_passive_lv": 5, "result": "dagger_evo", "name": "风暴飞刀"},
		{"weapon": "orbit", "passive": "speed", "need_weapon_lv": 8, "need_passive_lv": 4, "result": "orbit_evo", "name": "轨道绞肉机"},
		{"weapon": "boomerang", "passive": "haste", "need_weapon_lv": 8, "need_passive_lv": 5, "result": "boomerang_evo", "name": "回旋风暴"},
		{"weapon": "frost", "passive": "magnet", "need_weapon_lv": 8, "need_passive_lv": 4, "result": "frost_evo", "name": "永冬领域"},
	]


static func _default_unlocks() -> Dictionary:
	return {
		"boomerang": {"name": "回旋斧", "desc": "累计击杀 40 敌人解锁", "kind": "total_kills", "need": 40, "unlocks_weapon": "boomerang"},
		"frost": {"name": "寒霜新星", "desc": "单局存活 90 秒解锁", "kind": "best_time", "need": 90.0, "unlocks_weapon": "frost"},
		"veteran": {"name": "老兵徽记", "desc": "单局击杀 80 敌人解锁（外观）", "kind": "kills", "need": 80, "unlocks_cosmetic": "veteran_badge"},
	}


static func _default_enemies() -> Dictionary:
	return {
		"slime": {"hp": 18.0, "spd": 72.0, "dmg": 8.0, "r": 13.0, "xp": 1, "color": Color(0.4, 0.85, 0.45), "behavior": "chase"},
		"bat": {"hp": 11.0, "spd": 135.0, "dmg": 6.0, "r": 10.0, "xp": 1, "color": Color(0.8, 0.5, 0.95), "behavior": "chase"},
		"brute": {"hp": 65.0, "spd": 48.0, "dmg": 16.0, "r": 19.0, "xp": 3, "color": Color(0.95, 0.55, 0.3), "behavior": "chase"},
		"charger": {"hp": 28.0, "spd": 68.0, "dmg": 14.0, "r": 14.0, "xp": 2, "color": Color(0.98, 0.62, 0.18), "behavior": "charger", "windup": 0.75, "dash_speed": 380.0, "dash_time": 0.45, "charge_cd": 2.2, "charge_range": 280.0, "charge_dmg_mult": 1.6},
		"caster": {"hp": 22.0, "spd": 75.0, "dmg": 12.0, "r": 12.0, "xp": 2, "color": Color(0.65, 0.45, 0.98), "behavior": "caster", "cast_cd": 3.0, "warning_time": 0.9, "cast_radius": 75.0, "cast_range_min": 120.0, "cast_range_max": 420.0},
		"elite": {"hp": 420.0, "spd": 62.0, "dmg": 22.0, "r": 27.0, "xp": 0, "color": Color(1.0, 0.85, 0.3), "behavior": "chase"},
		"boss": {"hp": 3200.0, "spd": 44.0, "dmg": 32.0, "r": 46.0, "xp": 0, "color": Color(0.9, 0.25, 0.3), "behavior": "boss", "phases": [{"hp_pct": 0.5, "spd_mult": 1.35, "color": Color(0.98, 0.3, 0.32), "shock_cd": 4.0, "shock_radius": 120.0, "shock_dmg": 20.0, "shock_warning": 0.85, "summon_interval": 5.5, "summon_count": 2}]},
	}


static func _default_spawn() -> Dictionary:
	return {
		"arena": 2600.0,
		"goal_time": 300.0,
		"max_enemies": 170,
		"spawn_radius": 820.0,
		"spawn_interval": {"base": 1.8, "per_second": 0.006, "min": 0.45, "max": 1.8},
		"batch": {"base": 1, "per_45sec": 1},
		"elite_interval": 40.0,
		"boss_times": [150.0, 250.0],
		"kind_thresholds": [
			{"elapsed_lt": 25.0, "weights": {"slime": 1.0}},
			{"elapsed_lt": 60.0, "weights": {"slime": 0.75, "bat": 0.25}},
			{"elapsed_lt": 95.0, "weights": {"slime": 0.5, "bat": 0.3, "brute": 0.2}},
			{"elapsed_lt": 135.0, "weights": {"slime": 0.4, "bat": 0.25, "brute": 0.15, "charger": 0.2}},
			{"elapsed_lt": 180.0, "weights": {"slime": 0.3, "bat": 0.2, "brute": 0.15, "charger": 0.175, "caster": 0.175}},
			{"elapsed_lt": 9999.0, "weights": {"slime": 0.22, "bat": 0.18, "brute": 0.18, "charger": 0.21, "caster": 0.21}},
		],
		"waves": [
			{"t": 0.0, "label": "opening", "weights": {"slime": 1.0}},
			{"t": 30.0, "label": "bat_swarm", "weights": {"slime": 0.7, "bat": 0.3}},
			{"t": 70.0, "label": "brute_pressure", "weights": {"slime": 0.5, "bat": 0.3, "brute": 0.2}},
			{"t": 95.0, "label": "charger_intro", "weights": {"slime": 0.4, "bat": 0.25, "brute": 0.15, "charger": 0.2}, "event": "charger_wave", "count": 6},
			{"t": 130.0, "label": "caster_intro", "weights": {"slime": 0.35, "bat": 0.2, "brute": 0.15, "charger": 0.15, "caster": 0.15}, "event": "caster_ring", "count": 1},
			{"t": 175.0, "label": "mixed", "weights": {"slime": 0.28, "bat": 0.18, "brute": 0.18, "charger": 0.18, "caster": 0.18}},
			{"t": 215.0, "label": "brute_charger_caster", "weights": {"bat": 0.18, "brute": 0.22, "charger": 0.3, "caster": 0.3}, "event": "mix_wave", "count": 8},
			{"t": 255.0, "label": "finale", "weights": {"brute": 0.28, "charger": 0.26, "caster": 0.26, "bat": 0.2}, "event": "finale", "count": 10},
		],
		"enemy_scaling": {"hp_per_sec": 0.011, "speed_per_sec": 0.0005, "speed_max": 1.2, "speed_rand_min": 0.92, "speed_rand_max": 1.08, "dmg_per_sec": 0.0022},
		"player": {"base_speed": 235.0, "base_magnet": 95.0, "base_hp": 100.0},
	}
