extends Node2D

signal died(enemy)

const GameData := preload("res://scripts/game_data.gd")
const Settings := preload("res://scripts/settings.gd")

# 保留内置默认值作为回退，实际数值由 data/balance.json 提供
const STATS_FALLBACK := {
	"slime": {"hp": 18.0, "spd": 72.0, "dmg": 8.0, "r": 13.0, "xp": 1, "color": Color(0.4, 0.85, 0.45), "behavior": "chase"},
	"bat": {"hp": 11.0, "spd": 135.0, "dmg": 6.0, "r": 10.0, "xp": 1, "color": Color(0.8, 0.5, 0.95), "behavior": "chase"},
	"brute": {"hp": 65.0, "spd": 48.0, "dmg": 16.0, "r": 19.0, "xp": 3, "color": Color(0.95, 0.55, 0.3), "behavior": "chase"},
	"charger": {"hp": 28.0, "spd": 68.0, "dmg": 14.0, "r": 14.0, "xp": 2, "color": Color(0.98, 0.62, 0.18), "behavior": "charger", "windup": 0.75, "dash_speed": 380.0, "dash_time": 0.45, "charge_cd": 2.2, "charge_range": 280.0, "charge_dmg_mult": 1.6},
	"caster": {"hp": 22.0, "spd": 75.0, "dmg": 12.0, "r": 12.0, "xp": 2, "color": Color(0.65, 0.45, 0.98), "behavior": "caster", "cast_cd": 3.0, "warning_time": 0.9, "cast_radius": 75.0, "cast_range_min": 120.0, "cast_range_max": 420.0},
	"elite": {"hp": 420.0, "spd": 62.0, "dmg": 22.0, "r": 27.0, "xp": 0, "color": Color(1.0, 0.85, 0.3), "behavior": "chase"},
	"boss": {"hp": 3200.0, "spd": 44.0, "dmg": 32.0, "r": 46.0, "xp": 0, "color": Color(0.9, 0.25, 0.3), "behavior": "boss", "phases": [{"hp_pct": 0.5, "spd_mult": 1.35, "color": Color(0.98, 0.3, 0.32), "shock_cd": 4.0, "shock_radius": 120.0, "shock_dmg": 20.0, "shock_warning": 0.85, "summon_interval": 5.5, "summon_count": 2}]},
}
var STATS: Dictionary:
	get:
		GameData.ensure_loaded()
		return GameData.enemies if not GameData.enemies.is_empty() else STATS_FALLBACK

var game: Node2D
var kind := "slime"
var hp := 1.0
var max_hp := 1.0
var speed := 100.0
var dmg := 8.0
var radius := 12.0
var xp_value := 1
var base_color := Color.WHITE
var behavior := "chase"
var dead := false
var flash := 0.0
var attack_cd := 0.0
var kb := Vector2.ZERO
var wob := 0.0
var wobble_seed := 0.0

# charger 状态
var charge_state := "chase"
var charge_cd := 0.0
var windup_t := 0.0
var dash_t := 0.0
var dash_dir := Vector2.ZERO

# caster 状态
var cast_cd := 0.0
var cast_warning_t := 0.0
var cast_pos := Vector2.ZERO
var cast_radius := 75.0
var is_casting := false

# boss 状态
var boss_phase := 1
var boss_shock_cd := 0.0
var boss_warning_t := 0.0
var boss_shock_pos := Vector2.ZERO
var boss_shock_radius := 120.0
var boss_summon_t := 0.0
var boss_has_transformed := false

# 减速状态（frost）
var slow_t := 0.0
var slow_factor := 1.0


func _ready() -> void:
	add_to_group("enemies")
	GameData.ensure_loaded()
	var st: Dictionary = (GameData.enemies.get(kind, STATS_FALLBACK[kind]) as Dictionary) if GameData.enemies.has(kind) else (STATS[kind] as Dictionary)
	var scaling: Dictionary = GameData.spawn.get("enemy_scaling", {}) as Dictionary
	var hp_s: float = float(scaling.get("hp_per_sec", 0.011))
	var spd_s: float = float(scaling.get("speed_per_sec", 0.0005))
	var spd_m: float = float(scaling.get("speed_max", 1.2))
	var rnd_min: float = float(scaling.get("speed_rand_min", 0.92))
	var rnd_max: float = float(scaling.get("speed_rand_max", 1.08))
	var dmg_s: float = float(scaling.get("dmg_per_sec", 0.0022))
	var t: float = game.elapsed
	max_hp = float(st["hp"]) * (1.0 + t * hp_s)
	hp = max_hp
	speed = float(st["spd"]) * minf(1.0 + t * spd_s, spd_m) * randf_range(rnd_min, rnd_max)
	dmg = float(st["dmg"]) * (1.0 + t * dmg_s)
	radius = float(st["r"])
	xp_value = int(st["xp"])
	base_color = st["color"] as Color
	behavior = str(st.get("behavior", "chase"))
	wobble_seed = randf() * TAU
	# 初始化行为特定状态
	match behavior:
		"charger":
			charge_cd = float(st.get("charge_cd", 2.2)) * randf_range(0.8, 1.0)
			cast_radius = 0.0
		"caster":
			cast_cd = float(st.get("cast_cd", 3.0)) * randf_range(0.7, 1.1)
			cast_radius = float(st.get("cast_radius", 75.0))
		"boss":
			boss_phase = 1
			boss_has_transformed = false
			var phases: Array = st.get("phases", []) as Array
			if not phases.is_empty():
				var ph: Dictionary = phases[0] as Dictionary
				boss_shock_radius = float(ph.get("shock_radius", 120.0))
				boss_shock_cd = float(ph.get("shock_cd", 4.0)) * 0.5
				boss_summon_t = float(ph.get("summon_interval", 5.5))


func _process(delta: float) -> void:
	if dead:
		return
	var flash_enabled: bool = Settings.is_flash_enabled()
	var flash_decay: float = 6.0 if flash_enabled else 9.0
	flash = maxf(flash - delta * flash_decay, 0.0)
	attack_cd -= delta
	slow_t = maxf(slow_t - delta, 0.0)
	if slow_t <= 0.0:
		slow_factor = 1.0
	kb = kb.move_toward(Vector2.ZERO, 700.0 * delta)
	var pl: Node2D = game.player
	if pl == null or pl.dead or game.ended:
		queue_redraw()
		return
	wob += delta
	match behavior:
		"charger":
			_process_charger(delta, pl)
		"caster":
			_process_caster(delta, pl)
		"boss":
			_process_boss(delta, pl)
		_:
			_process_chase(delta, pl)
	queue_redraw()


func _is_on_screen(pos: Vector2, pl: Node2D, margin: float = 0.0) -> bool:
	var off: Vector2 = (pos - pl.global_position).abs()
	return off.x < 760.0 + margin and off.y < 460.0 + margin


func _process_chase(delta: float, pl: Node2D) -> void:
	var to_p: Vector2 = pl.global_position - global_position
	var dir := to_p.normalized()
	var sway := dir.orthogonal() * sin(wob * 3.0 + wobble_seed) * (7.0 if kind == "bat" else 0.0)
	position += (dir * speed * slow_factor + sway + kb) * delta
	position.x = clampf(position.x, -game.ARENA + 20.0, game.ARENA - 20.0)
	position.y = clampf(position.y, -game.ARENA + 20.0, game.ARENA - 20.0)
	if to_p.length() < radius + 14.0 and attack_cd <= 0.0:
		attack_cd = 0.8
		pl.hurt(dmg)


func _process_charger(delta: float, pl: Node2D) -> void:
	var st: Dictionary = (STATS[kind] as Dictionary)
	var windup: float = float(st.get("windup", 0.75))
	var dash_speed: float = float(st.get("dash_speed", 380.0))
	var dash_time: float = float(st.get("dash_time", 0.45))
	var cd_max: float = float(st.get("charge_cd", 2.2))
	var trig_range: float = float(st.get("charge_range", 280.0))
	var dmg_mult: float = float(st.get("charge_dmg_mult", 1.6))
	var to_p: Vector2 = pl.global_position - global_position
	var dist: float = to_p.length()
	match charge_state:
		"chase":
			charge_cd -= delta
			# 普通追踪（稍慢）
			var dir := to_p.normalized()
			position += (dir * speed * slow_factor + kb) * delta
			position.x = clampf(position.x, -game.ARENA + 20.0, game.ARENA - 20.0)
			position.y = clampf(position.y, -game.ARENA + 20.0, game.ARENA - 20.0)
			# 触发冲锋：需在范围内且冷却完毕且同屏（避免屏外无预警必中）
			if charge_cd <= 0.0 and dist < trig_range and dist > 30.0:
				# 额外检查：若敌人完全在屏外则不触发冲锋，改为靠近
				# 但距离 <280 已保证基本在屏内（760/460），故直接进入预警
				charge_state = "windup"
				windup_t = windup
				dash_dir = to_p.normalized()
				flash = 1.0
			else:
				if dist < radius + 14.0 and attack_cd <= 0.0:
					attack_cd = 0.8
					pl.hurt(dmg)
		"windup":
			windup_t -= delta
			flash = 1.0
			# 预警阶段静止或极慢（给玩家反应）
			position += kb * delta * 0.3
			if windup_t <= 0.0:
				charge_state = "dash"
				dash_t = dash_time
				# 重新校准方向为玩家当前位置（可预判躲避）
				dash_dir = (pl.global_position - global_position).normalized()
				if dash_dir == Vector2.ZERO:
					dash_dir = Vector2.RIGHT
		"dash":
			dash_t -= delta
			var move: Vector2 = dash_dir * dash_speed * slow_factor + kb
			position += move * delta
			position.x = clampf(position.x, -game.ARENA + 20.0, game.ARENA - 20.0)
			position.y = clampf(position.y, -game.ARENA + 20.0, game.ARENA - 20.0)
			# 冲锋碰撞伤害（更高）
			var to_p2: Vector2 = pl.global_position - global_position
			if to_p2.length() < radius + 16.0 and attack_cd <= 0.0:
				attack_cd = 0.9
				pl.hurt(dmg * dmg_mult)
				game.shake = maxf(game.shake, 4.0)
			if dash_t <= 0.0:
				charge_state = "chase"
				charge_cd = cd_max


func _process_caster(delta: float, pl: Node2D) -> void:
	var st: Dictionary = (STATS[kind] as Dictionary)
	var warning_time: float = float(st.get("warning_time", 0.9))
	var base_cast_cd: float = float(st.get("cast_cd", 3.0))
	var r: float = float(st.get("cast_radius", 75.0))
	var rmin: float = float(st.get("cast_range_min", 120.0))
	var rmax: float = float(st.get("cast_range_max", 420.0))
	cast_cd -= delta
	if is_casting:
		cast_warning_t -= delta
		flash = 1.0 if fmod(cast_warning_t, 0.2) < 0.1 else 0.5
		if cast_warning_t <= 0.0:
			# 爆炸判定：以预警位置为中心
			is_casting = false
			flash = 0.0
			# 伤害在预警圈内的玩家
			var d2: float = cast_pos.distance_squared_to(pl.global_position)
			var need: float = r + 14.0
			if d2 < need * need:
				pl.hurt(dmg)
				game.shake = maxf(game.shake, 3.0)
			game.spawn_burst(cast_pos, base_color.lightened(0.3), r)
			game.sfx.play("thunder")
			cast_cd = base_cast_cd + randf_range(-0.3, 0.3)
		return
	# 非施法时：保持距离的移动
	var to_p: Vector2 = pl.global_position - global_position
	var dist: float = to_p.length()
	var dir: Vector2 = to_p.normalized() if dist > 1.0 else Vector2.RIGHT
	# 行为：过远则靠近，过近则远离，适中则横向微移
	if dist > rmax:
		position += (dir * speed * slow_factor + kb) * delta
	elif dist < rmin:
		position += (-dir * speed * slow_factor * 0.9 + kb) * delta
	else:
		var strafe := dir.orthogonal() * sin(wob * 2.0 + wobble_seed) * speed * slow_factor * 0.4
		position += (strafe + kb * 0.5) * delta
		# 施法判定：距离适中且冷却完毕
		if cast_cd <= 0.0 and dist >= rmin and dist <= rmax:
			# 预警：记录玩家当前位置，需清晰预警且不在屏外无预警必中
			# 预警位置在玩家附近，始终可见
			is_casting = true
			cast_warning_t = warning_time
			cast_pos = pl.global_position
			cast_radius = r
			flash = 1.0
	position.x = clampf(position.x, -game.ARENA + 20.0, game.ARENA - 20.0)
	position.y = clampf(position.y, -game.ARENA + 20.0, game.ARENA - 20.0)
	# 接触伤害（较低，避免重叠施法与接触）
	if not is_casting and dist < radius + 12.0 and attack_cd <= 0.0:
		attack_cd = 0.9
		pl.hurt(dmg * 0.8)


func _process_boss(delta: float, pl: Node2D) -> void:
	# 阶段切换
	if not boss_has_transformed and hp / max_hp < 0.5:
		boss_has_transformed = true
		boss_phase = 2
		var st0: Dictionary = (STATS[kind] as Dictionary)
		var phases0: Array = st0.get("phases", []) as Array
		if not phases0.is_empty():
			var ph0: Dictionary = phases0[0] as Dictionary
			var mult: float = float(ph0.get("spd_mult", 1.35))
			speed *= mult
			var new_col: Variant = ph0.get("color", base_color)
			if new_col is Color:
				base_color = new_col as Color
			boss_shock_radius = float(ph0.get("shock_radius", 120.0))
			boss_shock_cd = float(ph0.get("shock_cd", 4.0))
			boss_summon_t = float(ph0.get("summon_interval", 5.5))
			game.spawn_burst(global_position, Color(1.0, 0.85, 0.3), 80)
			game.shake = 10.0
		# 震荡波逻辑（仅二阶段）
	if boss_phase == 2:
		boss_shock_cd -= delta
		boss_summon_t -= delta
		if boss_warning_t > 0.0:
			boss_warning_t -= delta
			flash = 1.0 if fmod(boss_warning_t, 0.18) < 0.09 else 0.6
			if boss_warning_t <= 0.0:
				flash = 0.0
				var d2: float = boss_shock_pos.distance_squared_to(pl.global_position)
				var need: float = boss_shock_radius + 14.0
				if d2 < need * need:
					var dmg_ph: Dictionary = ((STATS[kind] as Dictionary).get("phases", []) as Array)[0] as Dictionary if not (STATS[kind] as Dictionary).get("phases", []).is_empty() else {}
					pl.hurt(float(dmg_ph.get("shock_dmg", 20.0)))
					game.shake = 8.0
				game.spawn_burst(boss_shock_pos, base_color.lightened(0.35), boss_shock_radius)
				var cd_ph: Dictionary = ((STATS[kind] as Dictionary).get("phases", []) as Array)[0] as Dictionary if not (STATS[kind] as Dictionary).get("phases", []).is_empty() else {}
				boss_shock_cd = float(cd_ph.get("shock_cd", 4.0))
		elif boss_shock_cd <= 0.0:
			# 开始预警
			var stb: Dictionary = (STATS[kind] as Dictionary)
			var ph: Dictionary = ((stb.get("phases", []) as Array)[0] as Dictionary) if not (stb.get("phases", []) as Array).is_empty() else {}
			var warn: float = float(ph.get("shock_warning", 0.85))
			boss_warning_t = warn
			boss_shock_pos = pl.global_position
			boss_shock_radius = float(ph.get("shock_radius", 120.0))
			flash = 1.0
		# 召唤小怪
		if boss_summon_t <= 0.0:
			var ph2: Dictionary = ((STATS[kind] as Dictionary).get("phases", []) as Array)[0] as Dictionary if not (STATS[kind] as Dictionary).get("phases", []).is_empty() else {}
			var cnt: int = int(ph2.get("summon_count", 2))
			for i in cnt:
				if game._live_count() < game.MAX_ENEMIES:
					var off: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(30.0, 90.0)
					game._spawn_at("charger" if randf() < 0.5 else "caster", global_position + off)
			boss_summon_t = float(ph2.get("summon_interval", 5.5))
	# 通用追踪
	var to_p: Vector2 = pl.global_position - global_position
	var dir := to_p.normalized()
	# boss 在预警时减速，便于玩家预判
	var move_spd: float = speed * (0.35 if boss_warning_t > 0.0 else 1.0)
	position += (dir * move_spd * slow_factor + kb) * delta
	position.x = clampf(position.x, -game.ARENA + 20.0, game.ARENA - 20.0)
	position.y = clampf(position.y, -game.ARENA + 20.0, game.ARENA - 20.0)
	if to_p.length() < radius + 16.0 and attack_cd <= 0.0:
		attack_cd = 0.7
		pl.hurt(dmg)


func apply_slow(factor: float, dur: float) -> void:
	if dead:
		return
	slow_factor = minf(slow_factor, 1.0 - factor)
	slow_factor = clampf(slow_factor, 0.15, 1.0)
	slow_t = maxf(slow_t, dur)
	# 视觉反馈：短暂闪蓝
	flash = maxf(flash, 0.6 if Settings.is_flash_enabled() else 0.25)


func take_hit(amount: float, kdir: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	hp -= amount
	flash = 1.0 if Settings.is_flash_enabled() else 0.45
	kb += kdir
	game.spawn_damage_text(global_position, str(int(amount)), Color(1.0, 1.0, 0.85))
	if hp <= 0.0:
		dead = true
		died.emit(self)
		queue_free()


func _draw() -> void:
	# 预警绘制（在本体绘制之前，保证可见）
	if behavior == "charger" and charge_state == "windup":
		var to_pl: Vector2 = (game.player.global_position - global_position) if game and game.player else Vector2.ZERO
		# 预警线
		var warn_col := Color(1.0, 0.3, 0.2, 0.85)
		draw_line(Vector2.ZERO, to_pl, warn_col, 3.0)
		draw_line(Vector2.ZERO, to_pl, Color(1, 1, 1, 0.35), 1.0)
		# 闪烁外框
		var a: float = 0.5 + 0.5 * sin(wob * 12.0)
		draw_rect(Rect2(-radius - 6.0, -radius - 6.0, (radius + 6.0) * 2, (radius + 6.0) * 2), Color(1, 0.2, 0.2, 0.3 + a * 0.2), false, 2.5)
	if behavior == "caster" and is_casting:
		var local_pos: Vector2 = cast_pos - global_position
		var pct: float = 1.0 - clampf(cast_warning_t / 0.9, 0.0, 1.0)
		var col := Color(0.65, 0.45, 0.98, 0.18 + pct * 0.12)
		var bord := Color(0.85, 0.6, 1.0, 0.7 + pct * 0.3)
		draw_circle(local_pos, cast_radius, col)
		draw_arc(local_pos, cast_radius, 0, TAU, 48, bord, 2.5, true)
		# 倒计时刻度
		var tick: float = TAU * (1.0 - pct)
		draw_arc(local_pos, cast_radius + 4.0, -PI / 2.0, -PI / 2.0 + tick, 32, Color(1, 0.9, 0.4, 0.9), 3.0, true)
		# 中心感叹号提示
		draw_circle(local_pos, 6.0, Color(1, 0.35, 0.35, 0.85))
	if behavior == "boss" and boss_warning_t > 0.0:
		var local_boss: Vector2 = boss_shock_pos - global_position
		var pct2: float = 1.0 - clampf(boss_warning_t / 0.85, 0.0, 1.0)
		draw_circle(local_boss, boss_shock_radius, Color(0.9, 0.25, 0.3, 0.12 + pct2 * 0.1))
		draw_arc(local_boss, boss_shock_radius, 0, TAU, 64, Color(1.0, 0.35, 0.35, 0.75), 3.0, true)
		draw_arc(local_boss, boss_shock_radius + 6.0, 0, TAU * (1.0 - pct2), 48, Color(1, 0.9, 0.3, 0.9), 2.5, true)
	# 本体绘制
	var is_slowed: bool = slow_t > 0.05
	var col := base_color.lerp(Color(1, 1, 1), flash * 0.75)
	if is_slowed:
		col = col.lerp(Color(0.6, 0.8, 1.0), 0.35 * clampf(slow_t / 2.0, 0.0, 1.0))
	match kind:
		"slime":
			var bob := sin(wob * 6.0 + wobble_seed) * 2.0
			draw_circle(Vector2(0, bob + 2.0), radius, Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.35))
			draw_circle(Vector2(0, bob), radius, col)
			draw_arc(Vector2(0, bob), radius, 0, TAU, 16, Color(0, 0, 0, 0.45), 2.0, true)
			draw_circle(Vector2(-radius * 0.3, bob - radius * 0.3), radius * 0.22, Color(1, 1, 1, 0.85))
		"bat":
			var flap := sin(wob * 12.0 + wobble_seed) * 0.5
			var wing_col: Color = col.darkened(0.18)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-radius * 1.9, -radius * flap), Vector2(-radius * 0.3, -radius * 0.2), Vector2(-radius * 1.4, radius * 0.9),
			]), col)
			draw_polyline(PackedVector2Array([Vector2(-radius * 1.9, -radius * flap), Vector2(-radius * 0.3, -radius * 0.2), Vector2(-radius * 1.4, radius * 0.9)]), Color(0,0,0,0.5), 2.0, true)
			draw_colored_polygon(PackedVector2Array([
				Vector2(radius * 1.9, -radius * flap), Vector2(radius * 0.3, -radius * 0.2), Vector2(radius * 1.4, radius * 0.9),
			]), col)
			draw_polyline(PackedVector2Array([Vector2(radius * 1.9, -radius * flap), Vector2(radius * 0.3, -radius * 0.2), Vector2(radius * 1.4, radius * 0.9)]), Color(0,0,0,0.5), 2.0, true)
			draw_circle(Vector2.ZERO, radius * 0.85, col.darkened(0.25))
			draw_circle(Vector2.ZERO, radius * 0.85, Color(0,0,0,0.45), false, 1.8)
			draw_circle(Vector2.ZERO, radius * 0.4, Color(1, 1, 1, 0.9))
		"brute":
			draw_rect(Rect2(-radius - 1, -radius - 1, radius * 2 + 2, radius * 2 + 2), Color(0,0,0,0.5))
			draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), col)
			draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), col.darkened(0.45), false, 3.0)
			draw_rect(Rect2(-radius * 0.4, -radius * 0.4, radius * 0.8, radius * 0.8), col.darkened(0.35))
		"charger":
			# 菱形冲锋者 + 方向箭头
			var pts := PackedVector2Array([Vector2(0, -radius - 2.0), Vector2(radius + 2.0, 0), Vector2(0, radius + 2.0), Vector2(-radius - 2.0, 0)])
			draw_colored_polygon(pts, col)
			draw_polyline(pts, col.darkened(0.35), 2.5, true)
			var fwd: Vector2 = dash_dir if charge_state == "dash" else (game.player.global_position - global_position).normalized() if game and game.player else Vector2.RIGHT
			if charge_state == "windup" or charge_state == "dash":
				draw_line(Vector2.ZERO, fwd * (radius + 8.0), Color(1, 1, 1, 0.9), 2.0)
			draw_circle(Vector2.ZERO, radius * 0.35, Color(1, 1, 1, 0.88))
		"caster":
			# 法杖型：主体圆 + 顶部符文
			draw_circle(Vector2.ZERO, radius, col)
			draw_circle(Vector2.ZERO, radius * 0.62, col.darkened(0.28))
			var rune_a: float = wob * 3.0
			for i in 3:
				var ang: float = rune_a + TAU * i / 3.0
				var p: Vector2 = Vector2.from_angle(ang) * (radius * 0.85)
				draw_circle(p, 2.5, Color(0.9, 0.85, 1.0, 0.9))
			if is_casting:
				draw_arc(Vector2.ZERO, radius + 7.0, 0, TAU, 24, Color(0.85, 0.6, 1.0, 0.8), 2.0, true)
		"elite":
			for i in 8:
				var ang := TAU * i / 8.0
				var tip := Vector2.from_angle(ang) * (radius + 10.0)
				var b0 := Vector2.from_angle(ang - 0.28) * radius
				var b1 := Vector2.from_angle(ang + 0.28) * radius
				draw_colored_polygon(PackedVector2Array([tip, b0, b1]), col.darkened(0.15))
			draw_circle(Vector2.ZERO, radius, col)
			draw_circle(Vector2.ZERO, radius * 0.55, col.darkened(0.3))
		"boss":
			var pts2 := PackedVector2Array()
			for i in 6:
				pts2.append(Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * radius)
			draw_colored_polygon(pts2, col)
			draw_polygon(pts2, PackedColorArray([Color(1, 1, 1, 0.0)]), PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
			draw_arc(Vector2.ZERO, radius * 0.65, 0, TAU, 32, Color(1, 1, 1, 0.5), 3.0, true)
			draw_circle(Vector2.ZERO, radius * 0.28, Color(1.0, 0.95, 0.6))
			if boss_phase == 2:
				# 二阶段光环
				draw_arc(Vector2.ZERO, radius + 10.0, 0, TAU, 32, Color(1.0, 0.3, 0.3, 0.35 + 0.15 * sin(wob * 4.0)), 3.0, true)
	if is_slowed:
		# 减速光环
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 16, Color(0.55, 0.78, 1.0, 0.5), 1.5, true)
	if hp < max_hp and not dead:
		var w := radius * 2.2
		var pct := clampf(hp / max_hp, 0.0, 1.0)
		var top := -radius - 11.0
		if behavior == "boss":
			w = radius * 2.8
			top = -radius - 18.0
		draw_rect(Rect2(-w * 0.5, top, w, 4.0), Color(0, 0, 0, 0.55))
		var bar_c := Color(0.35, 0.95, 0.45)
		if pct <= 0.25:
			bar_c = Color(1.0, 0.35, 0.3)
		elif pct <= 0.5:
			bar_c = Color(1.0, 0.8, 0.3)
		draw_rect(Rect2(-w * 0.5, top, w * pct, 4.0), bar_c)
