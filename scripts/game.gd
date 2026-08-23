extends Node2D

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const Fx := preload("res://scripts/fx.gd")
const BackgroundScript := preload("res://scripts/background.gd")
const HudScript := preload("res://scripts/hud.gd")
const MenusScript := preload("res://scripts/menus.gd")
const JoystickScript := preload("res://scripts/joystick.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const MusicScript := preload("res://scripts/music.gd")
const SaveData := preload("res://scripts/save_data.gd")
const UiMode := preload("res://scripts/ui_mode.gd")

const GameData := preload("res://scripts/game_data.gd")
const Settings := preload("res://scripts/settings.gd")

const SPECIAL_ENEMY_RESERVE := 2
const SPECIAL_ENEMY_LIMITS := {
	"elite": 1,
	"boss": 1,
}
const MIN_SPAWN_DISTANCE := 360.0
const MAX_PICKUPS := 350
const MAX_HEART_PICKUPS := 24
const PICKUP_LIFETIME := 60.0

# 数值由 data/balance.json 集中管理，此处为兼容层：通过 GameData 暴露，保持原有字段名可通过 g.get() 访问
var ARENA: float:
	get: return GameData.arena
	set(v): GameData.arena = v
var GOAL_TIME: float:
	get: return GameData.goal_time
	set(v): GameData.goal_time = v
var MAX_ENEMIES: int:
	get: return GameData.max_enemies
	set(v): GameData.max_enemies = v
var SPAWN_R: float:
	get: return GameData.spawn_radius
	set(v): GameData.spawn_radius = v
var WEAPONS: Dictionary:
	get: return GameData.weapons
	set(v): GameData.weapons = v
var PASSIVES: Dictionary:
	get: return GameData.passives
	set(v): GameData.passives = v

var player: Node2D
var cam: Camera2D
var world: Node2D
var enemies_node: Node2D
var projectiles_node: Node2D
var pickups_node: Node2D
var fx_node: Node2D
var hud: Control
var menus: Control
var joystick: Control
var sfx: Node
var music: Node

var elapsed := 0.0
var kills := 0
var running := true
var ended := false
var endless := false
var pending_levels := 0
var total_damage := 0.0
var taken_damage := 0.0
var spawn_t := 1.0
var elite_t := 45.0
var boss_idx := 0
var shake := 0.0
var _wave_idx := 0
var _wave_cache: Array = []
var _recorded_stats_checkpoint: Dictionary = {}

# --- 性能优化：对象池与注册表 ---
var _proj_pool: Array = []
var _pickup_pool: Array = []
var _float_pool: Array = []
var _burst_pool: Array = []
var _lightning_pool: Array = []


func _ready() -> void:
	GameData.ensure_loaded()
	var _gd_errs: Array = GameData.get_errors()
	for e in _gd_errs:
		push_error("[GameData] %s" % str(e))
	SaveData.ensure_loaded()
	var _gd_warns: Array = GameData.get_warnings()
	for w in _gd_warns:
		push_warning("[GameData] %s" % str(w))
	if GameData.spawn.has("elite_interval"):
		elite_t = float(GameData.spawn["elite_interval"])
	# 波次导演初始化：缓存并排序 waves
	var wraw: Variant = GameData.spawn.get("waves", [])
	if wraw is Array:
		_wave_cache = (wraw as Array).duplicate()
		# 按 t 排序
		_wave_cache.sort_custom(func(a, b): return float((a as Dictionary).get("t", 0.0)) < float((b as Dictionary).get("t", 0.0)))
	_wave_idx = 0
	# 跳过已过时的波次（若 elapsed 非0启动）
	while _wave_idx < _wave_cache.size() and elapsed >= float((_wave_cache[_wave_idx] as Dictionary).get("t", 0.0)):
		_wave_idx += 1
	sfx = SfxScript.new()
	add_child(sfx)
	music = MusicScript.new()
	add_child(music)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var bg := BackgroundScript.new()
	bg.game = self
	bg.z_index = -10
	world.add_child(bg)
	pickups_node = Node2D.new()
	pickups_node.name = "Pickups"
	world.add_child(pickups_node)
	enemies_node = Node2D.new()
	enemies_node.name = "Enemies"
	world.add_child(enemies_node)
	player = PlayerScript.new()
	player.name = "Player"
	player.game = self
	world.add_child(player)
	projectiles_node = Node2D.new()
	projectiles_node.name = "Projectiles"
	world.add_child(projectiles_node)
	fx_node = Node2D.new()
	fx_node.name = "Fx"
	fx_node.z_index = 40
	world.add_child(fx_node)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	cam.make_current()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	hud = HudScript.new()
	hud.game = self
	ui.add_child(hud)
	joystick = JoystickScript.new()
	joystick.name = "Joystick"
	ui.add_child(joystick)
	joystick.set_enabled(UiMode.is_mobile())
	menus = MenusScript.new()
	menus.name = "Menus"
	menus.game = self
	ui.add_child(menus)
	player.died.connect(_lose)
	player.leveled_up.connect(_on_level_up)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n in _proj_pool:
			if is_instance_valid(n):
				n.queue_free()
		_proj_pool.clear()
		for n in _pickup_pool:
			if is_instance_valid(n):
				n.queue_free()
		_pickup_pool.clear()
		for n in _float_pool:
			if is_instance_valid(n):
				n.queue_free()
		_float_pool.clear()
		for n in _burst_pool:
			if is_instance_valid(n):
				n.queue_free()
		_burst_pool.clear()
		for n in _lightning_pool:
			if is_instance_valid(n):
				n.queue_free()
		_lightning_pool.clear()

func _process(delta: float) -> void:
	if not running or ended:
		return
	elapsed += delta
	_update_spawner(delta)
	if elapsed >= GOAL_TIME and not endless:
		_win()
		return
	cam.position = player.position
	if Settings.is_shake_enabled() and shake > 0.01:
		shake = maxf(shake - delta * 26.0, 0.0)
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		if shake > 0.01:
			shake = maxf(shake - delta * 26.0, 0.0)
		cam.offset = Vector2.ZERO


func _get_wave_weights() -> Dictionary:
	if _wave_cache.is_empty():
		return {}
	var best: Dictionary = {}
	var best_t: float = -1.0
	for w in _wave_cache:
		if not w is Dictionary:
			continue
		var wd: Dictionary = w as Dictionary
		var tt: float = float(wd.get("t", 0.0))
		if tt <= elapsed and tt >= best_t:
			best_t = tt
			best = wd.get("weights", {}) as Dictionary
	return best


func _trigger_wave_event(wd: Dictionary) -> void:
	var ev: String = str(wd.get("event", ""))
	if ev == "":
		return
	var cnt: int = int(wd.get("count", 6))
	# 避免在 capped 时刷爆，尊重上限
	match ev:
		"charger_wave":
			for i in cnt:
				if not _spawn_at("charger", _spawn_pos()):
					break
		"caster_ring":
			# 在玩家周围环形生成 caster 预警展示
			for i in cnt:
				if not _spawn_at("caster", _spawn_pos()):
					break
		"mix_wave":
			for i in cnt:
				var k: String = "charger" if i % 2 == 0 else "caster"
				if i % 4 == 0:
					k = "brute"
				if not _spawn_at(k, _spawn_pos()):
					break
		"finale":
			for i in cnt:
				var kk: String = ["charger", "caster", "brute", "bat"][i % 4]
				if not _spawn_at(kk, _spawn_pos()):
					break
		_:
			for i in cnt:
				if not _spawn_at(_pick_kind(), _spawn_pos()):
					break


func _update_spawner(delta: float) -> void:
	# 波次导演：检查是否进入新 wave 并触发事件
	while _wave_idx < _wave_cache.size() and elapsed >= float((_wave_cache[_wave_idx] as Dictionary).get("t", 0.0)):
		var wd: Dictionary = _wave_cache[_wave_idx] as Dictionary
		_trigger_wave_event(wd)
		_wave_idx += 1
	spawn_t -= delta
	if spawn_t <= 0.0:
		var si: Dictionary = GameData.spawn.get("spawn_interval", {}) as Dictionary
		var base: float = float(si.get("base", 1.8))
		var per: float = float(si.get("per_second", 0.006))
		var mn: float = float(si.get("min", 0.45))
		var mx: float = float(si.get("max", 1.8))
		spawn_t = clampf(base - elapsed * per, mn, mx)
		var batch_cfg: Dictionary = GameData.spawn.get("batch", {}) as Dictionary
		var batch_base: int = int(batch_cfg.get("base", 1))
		var per_45: int = int(batch_cfg.get("per_45sec", 1))
		var batch := batch_base + int(elapsed / 45.0) * per_45
		for i in batch:
			_spawn_one()
	elite_t -= delta
	if elite_t <= 0.0:
		elite_t = float(GameData.spawn.get("elite_interval", 40.0))
		_spawn_at("elite", _spawn_pos())
	var boss_times: Array = GameData.spawn.get("boss_times", [150.0, 250.0]) as Array
	if boss_idx < boss_times.size() and elapsed >= float(boss_times[boss_idx]):
		# Boss 被配额暂时阻塞时保留日程，空出名额后重试。
		if _spawn_at("boss", _spawn_pos()):
			boss_idx += 1


func _live_count() -> int:
	# 直接子节点计数，避免 group 哈希查找
	return enemies_node.get_child_count() if enemies_node else 0


func _live_regular_count() -> int:
	var count := 0
	for e in get_enemies():
		if not SPECIAL_ENEMY_LIMITS.has(str(e.get("kind"))):
			count += 1
	return count


func _live_enemy_kind_count(kind: String) -> int:
	var count := 0
	for e in get_enemies():
		if str(e.get("kind")) == kind:
			count += 1
	return count


func _can_spawn_enemy(kind: String) -> bool:
	if enemies_node == null or _live_count() >= MAX_ENEMIES:
		return false
	if SPECIAL_ENEMY_LIMITS.has(kind):
		return _live_enemy_kind_count(kind) < int(SPECIAL_ENEMY_LIMITS[kind])
	# 极小的自定义上限也至少保留 1 个普通敌人槽，避免
	# MAX_ENEMIES=1/2 时导演永远无法启动。
	var reserve_slots := mini(SPECIAL_ENEMY_RESERVE, maxi(MAX_ENEMIES - 1, 0))
	var regular_limit := MAX_ENEMIES - reserve_slots
	return _live_regular_count() < regular_limit

func get_enemies() -> Array:
	# 注册表：直接返回子节点数组，避免 get_nodes_in_group
	return enemies_node.get_children() if enemies_node else []

func get_pickups() -> Array:
	return pickups_node.get_children() if pickups_node else []


func _spawn_pos() -> Vector2:
	var p: Vector2 = player.position
	var ang := randf() * TAU
	var r := SPAWN_R + randf_range(-40.0, 160.0)
	var bound := maxf(ARENA - 40.0, 0.0)
	var pos := (p + Vector2.from_angle(ang) * r).clamp(Vector2(-bound, -bound), Vector2(bound, bound))
	var best_pos := pos
	var best_distance_sq := p.distance_squared_to(pos)
	var safe_distance_sq := MIN_SPAWN_DISTANCE * MIN_SPAWN_DISTANCE
	if best_distance_sq >= safe_distance_sq:
		return pos
	# 靠近场地边角时，径向点会被钳制到玩家身边。围绕原角度寻找最远的合法点。
	var candidate_radius := maxf(r, MIN_SPAWN_DISTANCE)
	for i in 8:
		var candidate := (p + Vector2.from_angle(ang + TAU * float(i) / 8.0) * candidate_radius).clamp(
			Vector2(-bound, -bound),
			Vector2(bound, bound),
		)
		var candidate_distance_sq := p.distance_squared_to(candidate)
		if candidate_distance_sq > best_distance_sq:
			best_pos = candidate
			best_distance_sq = candidate_distance_sq
		if best_distance_sq >= safe_distance_sq:
			return best_pos
	# 极小测试场地可能无法满足固定距离；此时仍返回矩形内离玩家最远的点。
	for corner in [
		Vector2(-bound, -bound),
		Vector2(-bound, bound),
		Vector2(bound, -bound),
		Vector2(bound, bound),
	]:
		var corner_distance_sq := p.distance_squared_to(corner)
		if corner_distance_sq > best_distance_sq:
			best_pos = corner
			best_distance_sq = corner_distance_sq
	return best_pos


func _pick_kind() -> String:
	# 波次导演优先：若 waves 存在则取最新 wave 的 weights
	var wave_weights: Dictionary = _get_wave_weights()
	if not wave_weights.is_empty():
		var roll_w: float = randf()
		var acc_w: float = 0.0
		for k in wave_weights.keys():
			acc_w += float(wave_weights[k])
			if roll_w < acc_w:
				return str(k)
		return str(wave_weights.keys()[0]) if not wave_weights.is_empty() else "slime"
	# 兼容旧：读取 spawn.kind_thresholds，按 elapsed 匹配首个阈值后按权重随机
	var thresholds: Array = GameData.spawn.get("kind_thresholds", []) as Array
	if thresholds.is_empty():
		# 回退硬编码（保证无数据时行为不变）
		var roll2 := randf()
		if elapsed < 25.0:
			return "slime"
		elif elapsed < 60.0:
			return "slime" if roll2 < 0.75 else "bat"
		elif elapsed < 120.0:
			if roll2 < 0.5:
				return "slime"
			elif roll2 < 0.8:
				return "bat"
			return "brute"
		else:
			if roll2 < 0.4:
				return "slime"
			elif roll2 < 0.7:
				return "bat"
			return "brute"
	var weights: Dictionary = {}
	for entry in thresholds:
		if not entry is Dictionary:
			continue
		var d: Dictionary = entry as Dictionary
		var lt: float = float(d.get("elapsed_lt", 9999.0))
		if elapsed < lt:
			weights = d.get("weights", {}) as Dictionary
			break
	if weights.is_empty():
		# 取最后一条
		var last: Dictionary = thresholds[thresholds.size() - 1] as Dictionary
		weights = last.get("weights", {"slime": 1.0}) as Dictionary
	var roll := randf()
	var acc: float = 0.0
	for kind in weights.keys():
		acc += float(weights[kind])
		if roll < acc:
			return str(kind)
	# 保底：返回首个
	return str(weights.keys()[0]) if not weights.is_empty() else "slime"


func _spawn_one() -> void:
	_spawn_at(_pick_kind(), _spawn_pos())


func _spawn_at(kind: String, pos: Vector2) -> bool:
	if not _can_spawn_enemy(kind):
		return false
	var e := EnemyScript.new()
	e.game = self
	e.kind = kind
	e.position = pos
	e.died.connect(_on_enemy_died)
	enemies_node.add_child(e)
	return true


func hurt_enemy(e: Node2D, dmg: float, kdir: Vector2 = Vector2.ZERO) -> void:
	if ended or not is_instance_valid(e) or e.dead:
		return
	var real: float = dmg * player.damage_mult()
	total_damage += real
	e.take_hit(real, kdir)


func spawn_damage_text(pos: Vector2, text_value: String, color_value: Color = Color(1, 1, 1)) -> void:
	# 限流：基于 fx 子节点中 FloatText 数量，避免 group 查询
	var float_count: int = 0
	for child in fx_node.get_children():
		if child is Fx.FloatText:
			float_count += 1
			if float_count > 60:
				return
	var t: Fx.FloatText
	if _float_pool.size() > 0:
		t = _float_pool.pop_back() as Fx.FloatText
		t.visible = true
	else:
		t = Fx.FloatText.new()
	t.game = self
	t.position = pos + Vector2(randf_range(-10, 10), -16) - Vector2(60, 10)
	t.size = Vector2(120, 20)
	t.text_value = text_value
	t.color_value = color_value
	t.text = text_value
	t.add_theme_color_override("font_color", color_value)
	t.life = 0.7
	t.vy = -46.0
	t.modulate.a = 1.0
	if t.get_parent():
		t.get_parent().remove_child(t)
	fx_node.add_child(t)

func _recycle_float_text(t: Node) -> void:
	if t.get_parent():
		t.get_parent().remove_child(t)
	t.visible = false
	_float_pool.append(t)


func spawn_burst(pos: Vector2, col: Color, r: float = 18.0) -> void:
	var b: Fx.Burst
	if _burst_pool.size() > 0:
		b = _burst_pool.pop_back() as Fx.Burst
		b.visible = true
	else:
		b = Fx.Burst.new()
	b.game = self
	b.position = pos
	b.color_v = col
	b.max_r = maxf(r * 1.6, 22.0)
	b.life = 0.35
	b.t = 0.0
	if b.get_parent():
		b.get_parent().remove_child(b)
	fx_node.add_child(b)

func _recycle_burst(b: Node) -> void:
	if b.get_parent():
		b.get_parent().remove_child(b)
	b.visible = false
	_burst_pool.append(b)


func fx_lightning(pos: Vector2) -> void:
	var l: Fx.Lightning
	if _lightning_pool.size() > 0:
		l = _lightning_pool.pop_back() as Fx.Lightning
		l.visible = true
	else:
		l = Fx.Lightning.new()
	l.game = self
	l.target = pos
	l.life = 0.22
	l.t = 0.0
	l.pts.clear()
	var start := pos + Vector2(randf_range(-60, 60), -430)
	l.pts.append(start)
	var segs: int = 7
	for i in range(1, segs):
		var k: float = float(i) / float(segs)
		l.pts.append(start.lerp(pos, k) + Vector2(randf_range(-26, 26), 0))
	l.pts.append(pos)
	if l.get_parent():
		l.get_parent().remove_child(l)
	fx_node.add_child(l)

func _recycle_lightning(l: Node) -> void:
	if l.get_parent():
		l.get_parent().remove_child(l)
	l.visible = false
	_lightning_pool.append(l)


func _on_enemy_died(e: Node2D) -> void:
	kills += 1
	spawn_burst(e.position, e.base_color, e.radius)
	sfx.play("kill")
	match e.kind:
		"elite":
			_drop_gems(e.position, 10, 3)
			_spawn_pickup("heart", e.position, 30)
		"boss":
			_drop_gems(e.position, 26, 5)
			_spawn_pickup("heart", e.position, 50)
			spawn_burst(e.position, Color(1.0, 0.9, 0.3), 100)
			shake = 10.0
		_:
			_drop_gems(e.position, 1, e.xp_value)


func _drop_gems(pos: Vector2, count: int, value: int) -> void:
	for i in count:
		var off := Vector2(randf_range(-26, 26), randf_range(-26, 26))
		_spawn_pickup("gem", pos + off, value)


func _pickup_kind_count(kind: String) -> int:
	var count := 0
	for pickup in get_pickups():
		if str(pickup.get("kind")) == kind and not bool(pickup.get("collected")):
			count += 1
	return count


func _find_pickup_merge_target(kind: String, pos: Vector2, excluded: Node = null) -> Node:
	var nearest: Node = null
	var nearest_distance_sq := INF
	for pickup in get_pickups():
		if pickup == excluded or bool(pickup.get("collected")) or str(pickup.get("kind")) != kind:
			continue
		var distance_sq: float = pos.distance_squared_to((pickup as Node2D).position)
		if distance_sq < nearest_distance_sq:
			nearest = pickup
			nearest_distance_sq = distance_sq
	return nearest


func _merge_pickup_value(kind: String, pos: Vector2, value: int, excluded: Node = null) -> bool:
	var target := _find_pickup_merge_target(kind, pos, excluded)
	if target == null:
		return false
	target.set("value", int(target.get("value")) + maxi(value, 0))
	target.set("life", PICKUP_LIFETIME)
	(target as CanvasItem).queue_redraw()
	return true


func _compact_pickup_kind(kind: String) -> bool:
	# 把两个同类掉落合为一个以腾出节点，保留两者完整数值。
	var source: Node = null
	for pickup in get_pickups():
		if bool(pickup.get("collected")) or str(pickup.get("kind")) != kind:
			continue
		if source == null:
			source = pickup
			continue
		if _merge_pickup_value(kind, (source as Node2D).position, int(source.get("value")), source):
			_recycle_pickup(source)
			return true
	return false


func _spawn_pickup(kind: String, pos: Vector2, value: int) -> void:
	if pickups_node == null or value <= 0:
		return
	# 心脏也有单独配额；达到配额时合并治疗量，不增加节点。
	if kind == "heart" and _pickup_kind_count("heart") >= MAX_HEART_PICKUPS:
		_merge_pickup_value(kind, pos, value)
		return
	if pickups_node.get_child_count() >= MAX_PICKUPS:
		# 经验不能因节点上限消失：优先合并进最近的宝石。
		if _merge_pickup_value(kind, pos, value):
			return
		# 该类型尚不存在时（典型为 350 个宝石后的首颗心），先无损
		# 压缩另一类型，腾出槽位再生成本次掉落。
		var compact_kind := "heart" if kind == "gem" else "gem"
		if not _compact_pickup_kind(compact_kind):
			return
	var g: Node = null
	if _pickup_pool.size() > 0:
		g = _pickup_pool.pop_back() as Node
	else:
		g = PickupScript.new()
	if g.get_parent():
		g.get_parent().remove_child(g)
	g.call("reset_for_spawn", self, kind, value, pos, PICKUP_LIFETIME)
	pickups_node.add_child(g)


func _expire_pickup(p: Node) -> void:
	# 到期宝石先把 XP 并入其他宝石，避免长局中零散掉落白白消失。
	if str(p.get("kind")) == "gem":
		if not _merge_pickup_value("gem", (p as Node2D).position, int(p.get("value")), p):
			# 最后一个宝石没有合并目标时续期；节点数量仍有硬上限，但 XP
			# 不会仅因寿命到期而丢失。
			p.set("life", PICKUP_LIFETIME)
			return
	_recycle_pickup(p)


func _recycle_pickup(p: Node) -> void:
	if not is_instance_valid(p) or _pickup_pool.has(p):
		return
	if p.get_parent():
		p.get_parent().remove_child(p)
	p.set_process(false)
	(p as CanvasItem).visible = false
	_pickup_pool.append(p)


func _safe_projectile_direction(direction: Vector2, fallback: Vector2 = Vector2.RIGHT) -> Vector2:
	if direction.length_squared() > 0.000001:
		return direction.normalized()
	if fallback.length_squared() > 0.000001:
		return fallback.normalized()
	return Vector2.RIGHT


func spawn_projectile(dir: Vector2, dmg: float, pierce: int, pos: Vector2) -> void:
	var p: Node
	if _proj_pool.size() > 0:
		p = _proj_pool.pop_back()
		p.visible = true
	else:
		p = ProjectileScript.new()
	var shot_dir := _safe_projectile_direction(dir, player.facing if player else Vector2.RIGHT)
	p.set("game", self)
	p.set("dir", shot_dir)
	p.set("dmg", dmg)
	p.set("pierce", pierce)
	p.set("life", 1.5)
	p.set("is_boomerang", false)
	p.set("boomerang_t", 0.0)
	p.set("boomerang_return", 0.45)
	p.set("boomerang_has_returned", false)
	(p.get("hit_ids") as Dictionary).clear()
	p.position = pos
	p.rotation = shot_dir.angle()
	if p.get_parent():
		p.get_parent().remove_child(p)
	projectiles_node.add_child(p)
	(p as CanvasItem).queue_redraw()


func spawn_boomerang(
	dir: Vector2,
	dmg: float,
	pierce: int,
	pos: Vector2,
	spd: float = 520.0,
	return_time: float = 0.45
) -> void:
	var p: Node
	if _proj_pool.size() > 0:
		p = _proj_pool.pop_back()
		p.visible = true
	else:
		p = ProjectileScript.new()
	var shot_dir := _safe_projectile_direction(dir, player.facing if player else Vector2.RIGHT)
	var safe_return_time := maxf(return_time, 0.05)
	p.set("game", self)
	p.set("dir", shot_dir)
	p.set("dmg", dmg)
	p.set("pierce", pierce)
	p.set("speed", spd)
	p.set("life", maxf(1.65, safe_return_time + 1.2))
	p.set("is_boomerang", true)
	p.set("boomerang_t", 0.0)
	p.set("boomerang_has_returned", false)
	p.set("boomerang_return", safe_return_time)
	(p.get("hit_ids") as Dictionary).clear()
	p.position = pos
	p.rotation = shot_dir.angle()
	if p.get_parent():
		p.get_parent().remove_child(p)
	projectiles_node.add_child(p)
	(p as CanvasItem).queue_redraw()


func spawn_frost_nova(pos: Vector2, rad: float, slow: float) -> void:
	# 冰环特效：外圈 + 内爆
	var col := Color(0.55, 0.78, 1.0)
	spawn_burst(pos, col, rad * 0.9)
	# 额外细环
	var b: Fx.Burst
	if _burst_pool.size() > 0:
		b = _burst_pool.pop_back() as Fx.Burst
		b.visible = true
	else:
		b = Fx.Burst.new()
	b.game = self
	b.position = pos
	b.color_v = Color(0.72, 0.88, 1.0, 0.55)
	b.max_r = rad
	b.life = 0.42
	b.t = 0.0
	if b.get_parent():
		b.get_parent().remove_child(b)
	fx_node.add_child(b)
	shake = maxf(shake, 2.0 + rad * 0.01)


func _recycle_projectile(p: Node) -> void:
	if p.get_parent():
		p.get_parent().remove_child(p)
	p.visible = false
	# 重置 boomerang 标记，避免池复用污染
	p.set("is_boomerang", false)
	p.set("boomerang_t", 0.0)
	p.set("boomerang_return", 0.45)
	p.set("boomerang_has_returned", false)
	p.set("speed", 560.0)
	_proj_pool.append(p)


func _on_level_up() -> void:
	if ended:
		return
	pending_levels += 1
	if not menus.upgrade_layer.visible:
		_show_next_upgrade()


func _show_next_upgrade() -> void:
	if ended or menus.end_layer.visible:
		return
	if pending_levels <= 0:
		return
	pending_levels -= 1
	if menus.pause_layer.visible:
		menus.pause_layer.visible = false
	get_tree().paused = true
	menus.show_upgrades(_roll_cards())


func _on_card_chosen(card: Dictionary) -> void:
	_apply_card(card)
	menus.hide_upgrades()
	sfx.play("levelup")
	if pending_levels > 0:
		_show_next_upgrade()
	else:
		get_tree().paused = false


func _roll_cards() -> Array:
	var cands: Array = []
	# 进化优先：检查是否满足任一进化条件
	for evo in GameData.evolutions:
		if not evo is Dictionary:
			continue
		var ed: Dictionary = evo as Dictionary
		var w: String = str(ed.get("weapon", ""))
		var pas: String = str(ed.get("passive", ""))
		var res: String = str(ed.get("result", ""))
		if w == "" or pas == "" or res == "":
			continue
		if not player.weapons.has(w):
			continue
		if player.weapons.has(res):
			continue
		var need_wlv: int = int(ed.get("need_weapon_lv", 8))
		var need_plv: int = int(ed.get("need_passive_lv", 5))
		var cur_wlv: int = int(player.weapons[w]["lv"])
		var cur_plv: int = int(player.passives.get(pas, 0))
		if cur_wlv >= need_wlv and cur_plv >= need_plv:
			# 已满且未进化，加入进化候选
			var evo_cnt: int = 0
			for cc in cands:
				if cc["kind"] == "evolution" and cc["id"] == w:
					evo_cnt += 1
			if evo_cnt == 0:
				cands.append({"kind": "evolution", "id": w, "result": res, "passive": pas, "evo_name": str(ed.get("name", res))})
	# 普通武器新获：排除 evo 武器，且受 4 槽限制
	for id in WEAPONS:
		var winfo: Dictionary = WEAPONS[id] as Dictionary
		if winfo.get("evo", false):
			continue
		if not SaveData.is_weapon_unlocked(id):
			continue
		if not player.weapons.has(id):
			if player.weapons.size() < 4:
				cands.append({"kind": "weapon_new", "id": id})
		else:
			# 若该武器有进化且条件已满足，则不提供普通升级（由进化替代）
			var has_evo_pending: bool = false
			for cc in cands:
				if cc["kind"] == "evolution" and cc["id"] == id:
					has_evo_pending = true
					break
			if has_evo_pending:
				continue
			if player.weapons[id]["lv"] < WEAPONS[id]["levels"].size():
				cands.append({"kind": "weapon_up", "id": id})
	for id in PASSIVES:
		if player.passives.get(id, 0) < PASSIVES[id]["max"]:
			cands.append({"kind": "passive", "id": id})
	cands.shuffle()
	var picked: Array = []
	# 优先保证进化至少出现一张（若存在）
	var evo_in_cands: Array = []
	for c in cands:
		if c["kind"] == "evolution":
			evo_in_cands.append(c)
	if not evo_in_cands.is_empty():
		picked.append(evo_in_cands[0])
	for c in cands:
		if picked.size() >= 3:
			break
		# 去重：同 id 仅一次（进化与原武器视为同 id）
		var dup := false
		for p in picked:
			if p["id"] == c["id"]:
				dup = true
				break
			if c["kind"] == "evolution" and p["kind"] == "evolution" and p["result"] == c["result"]:
				dup = true
				break
		if dup:
			continue
		# 若已挑进化，则不再重复挑同武器的普通升级
		if c["kind"] == "weapon_up":
			var skip: bool = false
			for p in picked:
				if p["kind"] == "evolution" and p["id"] == c["id"]:
					skip = true
					break
			if skip:
				continue
		picked.append(c)
	while picked.size() < 3:
		picked.append({"kind": "heal"})
	return picked


func _apply_card(c: Dictionary) -> void:
	match c["kind"]:
		"weapon_new":
			player.add_weapon(c["id"])
		"weapon_up":
			player.weapons[c["id"]]["lv"] += 1
		"passive":
			player.add_passive(c["id"])
		"evolution":
			var w: String = str(c["id"])
			var res: String = str(c.get("result", w + "_evo"))
			# 替换：移除原武器，加入进化武器 Lv1
			if player.weapons.has(w):
				player.weapons.erase(w)
			player.add_weapon(res)
			# 特效与音效
			spawn_burst(player.global_position, WEAPONS[res]["color"] if WEAPONS.has(res) else Color(1,1,1), 60)
			shake = 8.0
		"heal":
			player.heal(40)


func add_taken(dmg: float) -> void:
	taken_damage += dmg


func _collect_stats() -> Dictionary:
	var build: Dictionary = {
		"weapons": player.weapons.duplicate(true),
		"passives": player.passives.duplicate(true),
	}
	return {
		"time": elapsed,
		"kills": kills,
		"level": player.level,
		"damage": total_damage,
		"taken": taken_damage,
		"build": build,
	}


func _win() -> void:
	if ended:
		return
	ended = true
	pending_levels = 0
	if menus.upgrade_layer.visible:
		menus.hide_upgrades()
	if menus.pause_layer.visible:
		menus.pause_layer.visible = false
	get_tree().paused = true
	var stats: Dictionary = _collect_stats()
	var newly: Array = SaveData.record_game(stats)
	_recorded_stats_checkpoint = stats.duplicate(true)
	menus.show_end(true, elapsed, kills, player.level, stats, newly)


func _lose() -> void:
	if ended:
		return
	ended = true
	pending_levels = 0
	if menus.upgrade_layer.visible:
		menus.hide_upgrades()
	if menus.pause_layer.visible:
		menus.pause_layer.visible = false
	get_tree().paused = true
	shake = 12.0
	spawn_burst(player.position, Color(0.4, 0.85, 1.0), 60)
	var stats2: Dictionary = _collect_stats()
	var newly2: Array
	if _recorded_stats_checkpoint.is_empty():
		newly2 = SaveData.record_game(stats2)
	else:
		# 胜利已记录过这局；无尽结算只延伸最佳成绩与增量统计。
		newly2 = SaveData.extend_recorded_game(stats2, _recorded_stats_checkpoint)
	menus.show_end(false, elapsed, kills, player.level, stats2, newly2)


func continue_endless() -> void:
	endless = true
	ended = false
	if menus.upgrade_layer.visible:
		menus.hide_upgrades()
	if menus.pause_layer.visible:
		menus.pause_layer.visible = false
	get_tree().paused = false
	menus.hide_end()


func restart() -> void:
	if menus:
		if menus.upgrade_layer.visible:
			menus.hide_upgrades()
		if menus.pause_layer.visible:
			menus.pause_layer.visible = false
		if menus.end_layer.visible:
			menus.hide_end()
	pending_levels = 0
	get_tree().paused = false
	var tree := get_tree()
	if tree.current_scene:
		tree.reload_current_scene()
	else:
		# 测试可直接挂载场景实例，此时 current_scene 为 null。
		tree.change_scene_to_file("res://scenes/game.tscn")


func to_home() -> void:
	if menus:
		if menus.upgrade_layer.visible:
			menus.hide_upgrades()
		if menus.pause_layer.visible:
			menus.pause_layer.visible = false
		if menus.end_layer.visible:
			menus.hide_end()
	pending_levels = 0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/home.tscn")
