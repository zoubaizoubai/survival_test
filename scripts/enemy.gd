extends Node2D

signal died(enemy)

const GameData := preload("res://scripts/game_data.gd")

# 保留内置默认值作为回退，实际数值由 data/balance.json 提供
const STATS_FALLBACK := {
	"slime": {"hp": 18.0, "spd": 72.0, "dmg": 8.0, "r": 13.0, "xp": 1, "color": Color(0.4, 0.85, 0.45)},
	"bat": {"hp": 11.0, "spd": 135.0, "dmg": 6.0, "r": 10.0, "xp": 1, "color": Color(0.8, 0.5, 0.95)},
	"brute": {"hp": 65.0, "spd": 48.0, "dmg": 16.0, "r": 19.0, "xp": 3, "color": Color(0.95, 0.55, 0.3)},
	"elite": {"hp": 420.0, "spd": 62.0, "dmg": 22.0, "r": 27.0, "xp": 0, "color": Color(1.0, 0.85, 0.3)},
	"boss": {"hp": 3200.0, "spd": 44.0, "dmg": 32.0, "r": 46.0, "xp": 0, "color": Color(0.9, 0.25, 0.3)},
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
var dead := false
var flash := 0.0
var attack_cd := 0.0
var kb := Vector2.ZERO
var wob := 0.0
var wobble_seed := 0.0


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
	wobble_seed = randf() * TAU


func _process(delta: float) -> void:
	if dead:
		return
	flash = maxf(flash - delta * 6.0, 0.0)
	attack_cd -= delta
	kb = kb.move_toward(Vector2.ZERO, 700.0 * delta)
	var pl: Node2D = game.player
	if pl == null or pl.dead or game.ended:
		queue_redraw()
		return
	wob += delta
	var to_p: Vector2 = pl.global_position - global_position
	var dir := to_p.normalized()
	var sway := dir.orthogonal() * sin(wob * 3.0 + wobble_seed) * (7.0 if kind == "bat" else 0.0)
	position += (dir * speed + sway + kb) * delta
	position.x = clampf(position.x, -game.ARENA + 20.0, game.ARENA - 20.0)
	position.y = clampf(position.y, -game.ARENA + 20.0, game.ARENA - 20.0)
	if to_p.length() < radius + 14.0 and attack_cd <= 0.0:
		attack_cd = 0.8
		pl.hurt(dmg)
	queue_redraw()


func take_hit(amount: float, kdir: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	hp -= amount
	flash = 1.0
	kb += kdir
	game.spawn_damage_text(global_position, str(int(amount)), Color(1.0, 1.0, 0.85))
	if hp <= 0.0:
		dead = true
		died.emit(self)
		queue_free()


func _draw() -> void:
	var col := base_color.lerp(Color(1, 1, 1), flash * 0.75)
	match kind:
		"slime":
			var bob := sin(wob * 6.0 + wobble_seed) * 2.0
			draw_circle(Vector2(0, bob + 2.0), radius, Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.35))
			draw_circle(Vector2(0, bob), radius, col)
			draw_circle(Vector2(-radius * 0.3, bob - radius * 0.3), radius * 0.22, Color(1, 1, 1, 0.85))
		"bat":
			var flap := sin(wob * 12.0 + wobble_seed) * 0.5
			draw_colored_polygon(PackedVector2Array([
				Vector2(-radius * 1.9, -radius * flap), Vector2(-radius * 0.3, -radius * 0.2), Vector2(-radius * 1.4, radius * 0.9),
			]), col)
			draw_colored_polygon(PackedVector2Array([
				Vector2(radius * 1.9, -radius * flap), Vector2(radius * 0.3, -radius * 0.2), Vector2(radius * 1.4, radius * 0.9),
			]), col)
			draw_circle(Vector2.ZERO, radius * 0.85, col.darkened(0.25))
			draw_circle(Vector2.ZERO, radius * 0.4, Color(1, 1, 1, 0.9))
		"brute":
			draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), col)
			draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), col.darkened(0.45), false, 3.0)
			draw_rect(Rect2(-radius * 0.4, -radius * 0.4, radius * 0.8, radius * 0.8), col.darkened(0.35))
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
			var pts := PackedVector2Array()
			for i in 6:
				pts.append(Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * radius)
			draw_colored_polygon(pts, col)
			draw_polygon(pts, PackedColorArray([Color(1, 1, 1, 0.0)]), PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
			draw_arc(Vector2.ZERO, radius * 0.65, 0, TAU, 32, Color(1, 1, 1, 0.5), 3.0, true)
			draw_circle(Vector2.ZERO, radius * 0.28, Color(1.0, 0.95, 0.6))
	if hp < max_hp and not dead:
		var w := radius * 2.2
		var pct := clampf(hp / max_hp, 0.0, 1.0)
		var top := -radius - 11.0
		draw_rect(Rect2(-w * 0.5, top, w, 4.0), Color(0, 0, 0, 0.55))
		var bar_c := Color(0.35, 0.95, 0.45)
		if pct <= 0.25:
			bar_c = Color(1.0, 0.35, 0.3)
		elif pct <= 0.5:
			bar_c = Color(1.0, 0.8, 0.3)
		draw_rect(Rect2(-w * 0.5, top, w * pct, 4.0), bar_c)
