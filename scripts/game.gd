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

const GameData := preload("res://scripts/game_data.gd")

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

var elapsed := 0.0
var kills := 0
var running := true
var ended := false
var endless := false
var pending_levels := 0
var spawn_t := 1.0
var elite_t := 45.0
var boss_idx := 0
var shake := 0.0


func _ready() -> void:
	GameData.ensure_loaded()
	var _gd_errs: Array = GameData.get_errors()
	for e in _gd_errs:
		push_error("[GameData] %s" % str(e))
	var _gd_warns: Array = GameData.get_warnings()
	for w in _gd_warns:
		push_warning("[GameData] %s" % str(w))
	# 同步生成器初始值（若数据驱动覆盖）
	if GameData.spawn.has("elite_interval"):
		elite_t = float(GameData.spawn["elite_interval"])
	sfx = SfxScript.new()
	add_child(sfx)
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
	menus = MenusScript.new()
	menus.name = "Menus"
	menus.game = self
	ui.add_child(menus)
	player.died.connect(_lose)
	player.leveled_up.connect(_on_level_up)


func _process(delta: float) -> void:
	if not running or ended:
		return
	elapsed += delta
	_update_spawner(delta)
	if elapsed >= GOAL_TIME and not endless:
		_win()
		return
	cam.position = player.position
	if shake > 0.01:
		shake = maxf(shake - delta * 26.0, 0.0)
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		cam.offset = Vector2.ZERO


func _update_spawner(delta: float) -> void:
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
		boss_idx += 1
		_spawn_at("boss", _spawn_pos())


func _live_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func _spawn_pos() -> Vector2:
	var p: Vector2 = player.position
	var ang := randf() * TAU
	var r := SPAWN_R + randf_range(-40.0, 160.0)
	var pos := p + Vector2.from_angle(ang) * r
	pos.x = clampf(pos.x, -ARENA + 40.0, ARENA - 40.0)
	pos.y = clampf(pos.y, -ARENA + 40.0, ARENA - 40.0)
	return pos


func _pick_kind() -> String:
	# 数据驱动：读取 spawn.kind_thresholds，按 elapsed 匹配首个阈值后按权重随机
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
	if _live_count() >= MAX_ENEMIES:
		return
	_spawn_at(_pick_kind(), _spawn_pos())


func _spawn_at(kind: String, pos: Vector2) -> void:
	var e := EnemyScript.new()
	e.game = self
	e.kind = kind
	e.position = pos
	e.died.connect(_on_enemy_died)
	enemies_node.add_child(e)


func hurt_enemy(e: Node2D, dmg: float, kdir: Vector2 = Vector2.ZERO) -> void:
	if ended or not is_instance_valid(e) or e.dead:
		return
	e.take_hit(dmg * player.damage_mult(), kdir)


func spawn_damage_text(pos: Vector2, text_value: String, color_value: Color = Color(1, 1, 1)) -> void:
	if get_tree().get_nodes_in_group("float_text").size() > 60:
		return
	var t := Fx.FloatText.new()
	t.position = pos + Vector2(randf_range(-10, 10), -16) - Vector2(60, 10)
	t.size = Vector2(120, 20)
	t.text_value = text_value
	t.color_value = color_value
	fx_node.add_child(t)


func spawn_burst(pos: Vector2, col: Color, r: float = 18.0) -> void:
	var b := Fx.Burst.new()
	b.position = pos
	b.color_v = col
	b.max_r = maxf(r * 1.6, 22.0)
	fx_node.add_child(b)


func fx_lightning(pos: Vector2) -> void:
	var l := Fx.Lightning.new()
	l.target = pos
	fx_node.add_child(l)


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


func _spawn_pickup(kind: String, pos: Vector2, value: int) -> void:
	if kind == "gem" and get_tree().get_nodes_in_group("pickup").size() > 350:
		return
	var g := PickupScript.new()
	g.kind = kind
	g.value = value
	g.position = pos
	pickups_node.add_child(g)


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
	for id in WEAPONS:
		if not player.weapons.has(id):
			if player.weapons.size() < 4:
				cands.append({"kind": "weapon_new", "id": id})
		else:
			if player.weapons[id]["lv"] < WEAPONS[id]["levels"].size():
				cands.append({"kind": "weapon_up", "id": id})
	for id in PASSIVES:
		if player.passives.get(id, 0) < PASSIVES[id]["max"]:
			cands.append({"kind": "passive", "id": id})
	cands.shuffle()
	var picked: Array = []
	for c in cands:
		if picked.size() >= 3:
			break
		var dup := false
		for p in picked:
			if p["id"] == c["id"]:
				dup = true
				break
		if not dup:
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
		"heal":
			player.heal(40)


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
	menus.show_end(true, elapsed, kills, player.level)


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
	menus.show_end(false, elapsed, kills, player.level)


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
	get_tree().reload_current_scene()


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
