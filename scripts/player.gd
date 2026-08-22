extends Node2D

signal hp_changed(hp_value: float, max_hp_value: float)
signal xp_changed(xp_value: int, needed: int, level_value: int)
signal leveled_up
signal died

const ProjectileScript := preload("res://scripts/projectile.gd")
const Settings := preload("res://scripts/settings.gd")
const SpriteLibrary := preload("res://scripts/sprite_library.gd")

const BASE_SPEED := 235.0
const BASE_MAGNET := 95.0
const BASE_HP := 100.0

var game: Node2D
var move_vec := Vector2.ZERO
var facing := Vector2.RIGHT
var hp := BASE_HP
var max_hp := BASE_HP
var level := 1
var xp := 0
var invuln := 0.0
var dead := false
var weapons := {}
var passives := {}
var orbit_angle := 0.0
var orbit_hits := {}
var time_alive := 0.0
var anim: AnimatedSprite2D
var _attack_t := 0.0


func _ready() -> void:
	add_to_group("player")
	max_hp = BASE_HP
	hp = max_hp
	add_weapon("dagger")
	anim = SpriteLibrary.make_sprite("player", 15.0)
	if anim:
		add_child(anim)
		anim.animation_finished.connect(_on_anim_finished)


func _process(delta: float) -> void:
	if dead:
		return
	time_alive += delta
	invuln = maxf(invuln - delta, 0.0)
	_move(delta)
	_update_weapons(delta)
	var flash_on: bool = Settings.is_flash_enabled()
	if invuln <= 0.0:
		modulate.a = 1.0
	else:
		modulate.a = 0.55 + 0.45 * absf(sin(time_alive * 30.0)) if flash_on else 0.78
	_attack_t = maxf(_attack_t - delta, 0.0)
	_update_anim()
	queue_redraw()


func _move(delta: float) -> void:
	var input_vec: Vector2 = game.joystick.vector
	if input_vec.length() <= 0.15:
		input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_vec = input_vec.limit_length(1.0)
	if move_vec.length() > 0.05:
		facing = move_vec.normalized()
	position += move_vec * speed() * delta
	position.x = clampf(position.x, -game.ARENA + 20.0, game.ARENA - 20.0)
	position.y = clampf(position.y, -game.ARENA + 20.0, game.ARENA - 20.0)


func speed() -> float:
	return BASE_SPEED * (1.0 + 0.1 * passives.get("speed", 0))


func magnet_radius() -> float:
	return BASE_MAGNET * (1.0 + 0.45 * passives.get("magnet", 0))


func damage_mult() -> float:
	return 1.0 + 0.15 * passives.get("damage", 0)


func cd_mult() -> float:
	return maxf(1.0 - 0.08 * passives.get("haste", 0), 0.6)


func wstat(id: String) -> Dictionary:
	return game.WEAPONS[id]["levels"][weapons[id]["lv"] - 1]


func add_weapon(id: String) -> void:
	weapons[id] = {"lv": 1, "t": 0.0}


func add_passive(id: String) -> void:
	passives[id] = passives.get(id, 0) + 1
	if id == "hp":
		max_hp += 25.0
		heal(25.0)


func heal(v: float) -> void:
	if dead:
		return
	hp = minf(hp + v, max_hp)
	hp_changed.emit(hp, max_hp)


func gain_xp(v: int) -> void:
	xp += v
	var need := xp_needed()
	while xp >= need:
		xp -= need
		level += 1
		leveled_up.emit()
		need = xp_needed()
	xp_changed.emit(xp, xp_needed(), level)


func xp_needed() -> int:
	return 5 + (level - 1) * 7 + int(pow(level - 1, 1.6) * 2.0)


func hurt(dmg: float) -> void:
	if dead or invuln > 0.0 or game.ended:
		return
	hp -= dmg
	if game and game.has_method("add_taken"):
		game.add_taken(dmg)
	invuln = 0.45
	game.shake = 6.0
	game.sfx.play("hurt")
	game.spawn_damage_text(global_position, "-%d" % int(dmg), Color(1.0, 0.35, 0.35))
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit()


func _update_weapons(delta: float) -> void:
	for id in weapons:
		var w: Dictionary = weapons[id]
		match id:
			"dagger", "dagger_evo":
				w["t"] -= delta
				if w["t"] <= 0.0:
					if _fire_dagger(id):
						w["t"] = wstat(id)["cd"] * cd_mult()
					else:
						w["t"] = 0.2
			"boomerang", "boomerang_evo":
				w["t"] -= delta
				if w["t"] <= 0.0:
					if _fire_boomerang(id):
						w["t"] = wstat(id)["cd"] * cd_mult()
					else:
						w["t"] = 0.25
			"lightning":
				w["t"] -= delta
				if w["t"] <= 0.0:
					_fire_lightning()
					w["t"] = wstat("lightning")["cd"] * cd_mult()
			"aura":
				w["t"] -= delta
				if w["t"] <= 0.0:
					_aura_tick()
					w["t"] = 0.5
			"frost", "frost_evo":
				w["t"] -= delta
				if w["t"] <= 0.0:
					_frost_nova(id)
					w["t"] = wstat(id)["cd"] * cd_mult()
	orbit_angle += orbit_rot() * delta
	_orbit_damage(delta)


func orbit_rot() -> float:
	if weapons.has("orbit"):
		return wstat("orbit")["rot"]
	if weapons.has("orbit_evo"):
		return wstat("orbit_evo")["rot"]
	return 0.0


func orb_positions() -> Array:
	var wid: String = "orbit" if weapons.has("orbit") else "orbit_evo"
	var st := wstat(wid)
	var arr: Array = []
	var n: int = st["orbs"]
	for i in n:
		arr.append(Vector2.from_angle(orbit_angle + TAU * i / n) * st["radius"])
	return arr


func _nearest_enemy(max_d: float) -> Node2D:
	var best: Node2D = null
	var bd := max_d * max_d
	for e in game.get_enemies():
		if e.dead:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _fire_dagger(wid: String = "dagger") -> bool:
	var target := _nearest_enemy(900.0)
	if target == null:
		return false
	var st := wstat(wid)
	var n: int = st["count"]
	var dir0: Vector2 = (target.global_position - global_position).normalized()
	for i in n:
		var spread := deg_to_rad(-8.0 * (n - 1) * 0.5 + 8.0 * i)
		var d := dir0.rotated(spread)
		game.spawn_projectile(d, st["dmg"], st["pierce"], position + d * 16.0)
	game.sfx.play("shoot")
	_play_attack()
	return true


func _fire_boomerang(wid: String = "boomerang") -> bool:
	var target := _nearest_enemy(880.0)
	if target == null:
		return false
	var st := wstat(wid)
	var n: int = int(st.get("count", 1))
	var dir0: Vector2 = (target.global_position - global_position).normalized()
	for i in n:
		var spread := deg_to_rad(-10.0 * (n - 1) * 0.5 + 10.0 * i)
		var d := dir0.rotated(spread)
		var spd: float = float(st.get("speed", 450.0))
		var pierce: int = int(st.get("pierce", 2))
		var dmg: float = float(st.get("dmg", 16.0))
		game.spawn_boomerang(d, dmg, pierce, position + d * 14.0, spd)
	game.sfx.play("shoot")
	_play_attack()
	return true


func _frost_nova(wid: String = "frost") -> void:
	var st := wstat(wid)
	var rad: float = float(st.get("radius", 120.0))
	var dmg: float = float(st.get("dmg", 14.0))
	var slow: float = float(st.get("slow", 0.3))
	var slow_time: float = float(st.get("slow_time", 1.2))
	# 特效：冰环爆发
	game.spawn_frost_nova(global_position, rad, slow)
	for e in game.get_enemies():
		if e.dead:
			continue
		var d2: float = global_position.distance_squared_to(e.global_position)
		var need: float = rad + e.radius
		if d2 < need * need:
			game.hurt_enemy(e, dmg, (e.global_position - global_position).normalized() * 60.0)
			if e.has_method("apply_slow"):
				e.apply_slow(slow, slow_time)
	game.sfx.play("thunder")


func _fire_lightning() -> void:
	var st := wstat("lightning")
	var pool: Array = []
	for e in game.get_enemies():
		if e.dead:
			continue
		var off: Vector2 = (e.global_position - global_position).abs()
		if off.x < 760.0 and off.y < 460.0:
			pool.append(e)
	if pool.is_empty():
		return
	pool.shuffle()
	var hits: int = mini(st["strikes"], pool.size())
	for i in hits:
		var e: Node2D = pool[i]
		game.fx_lightning(e.global_position)
		_area_damage(e.global_position, st["aoe"], st["dmg"])
	game.sfx.play("thunder")


func _area_damage(pos: Vector2, r: float, dmg: float) -> void:
	var rr: float = r
	for e in game.get_enemies():
		if e.dead:
			continue
		# 距离平方避免 sqrt
		var dist2: float = pos.distance_squared_to(e.global_position)
		var rad: float = rr + e.radius
		if dist2 < rad * rad:
			game.hurt_enemy(e, dmg, (e.global_position - pos).normalized() * 80.0)


func _aura_tick() -> void:
	var st := wstat("aura")
	var r: float = st["radius"]
	var dmg: float = st["dps"] * 0.5
	for e in game.get_enemies():
		if e.dead:
			continue
		var dist2: float = global_position.distance_squared_to(e.global_position)
		var rad: float = r + e.radius
		if dist2 < rad * rad:
			game.hurt_enemy(e, dmg)


func _orbit_damage(delta: float) -> void:
	if not weapons.has("orbit") and not weapons.has("orbit_evo"):
		return
	if orbit_hits.size() > 300:
		orbit_hits.clear()
	var oid: String = "orbit" if weapons.has("orbit") else "orbit_evo"
	var st := wstat(oid)
	var positions := orb_positions()
	for e in game.get_enemies():
		if e.dead:
			continue
		var eid: int = e.get_instance_id()
		if orbit_hits.has(eid):
			orbit_hits[eid] -= delta
			if orbit_hits[eid] > 0.0:
				continue
		for op in positions:
			var og: Vector2 = global_position + op
			var rad: float = 12.0 + e.radius
			if og.distance_squared_to(e.global_position) < rad * rad:
				game.hurt_enemy(e, st["dmg"], (e.global_position - global_position).normalized() * 150.0)
				orbit_hits[eid] = 0.45
				break


func _play_attack() -> void:
	_attack_t = 0.35
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("attack"):
		if anim.animation != "attack":
			anim.play("attack")


func _on_anim_finished() -> void:
	if anim and anim.animation == "attack":
		_attack_t = 0.0
		_update_anim()


func _update_anim() -> void:
	if anim == null:
		return
	anim.flip_h = facing.x < 0.0
	if _attack_t > 0.0 and anim.sprite_frames.has_animation("attack"):
		if anim.animation != "attack" or not anim.is_playing():
			anim.play("attack")
		return
	var moving: bool = move_vec.length() > 0.08
	var want: String = "walk" if moving else "idle"
	if not anim.sprite_frames.has_animation(want):
		want = "walk" if anim.sprite_frames.has_animation("walk") else "idle"
	if anim.animation != want or not anim.is_playing():
		anim.play(want)


func _draw() -> void:
	var flash_on2: bool = Settings.is_flash_enabled()
	draw_set_transform(Vector2(0, 10.0), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, 13.0, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# frost 预警环（与 aura 叠加）
	if weapons.has("frost") or weapons.has("frost_evo"):
		var fid: String = "frost" if weapons.has("frost") else "frost_evo"
		var fst := wstat(fid)
		var fr: float = float(fst.get("radius", 120.0))
		var wt: float = float(weapons[fid].get("t", 0.0))
		var cd: float = float(fst.get("cd", 3.0)) * cd_mult()
		var pct: float = 1.0 - clampf(wt / maxf(cd, 0.1), 0.0, 1.0)
		draw_arc(Vector2.ZERO, fr, 0, TAU * pct, 48, Color(0.55, 0.75, 1.0, 0.18), 2.0, true)
	if weapons.has("aura"):
		var st := wstat("aura")
		var r: float = st["radius"] * (1.0 + 0.03 * sin(time_alive * 4.0))
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.9, 0.5, 0.055))
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(1.0, 0.85, 0.4, 0.22), 2.0, true)
	if weapons.has("orbit") or weapons.has("orbit_evo"):
		for pos in orb_positions():
			draw_circle(pos, 9.0, Color(0.75, 0.85, 1.0, 0.95))
			draw_circle(pos, 4.5, Color(1, 1, 1, 0.95))
	if anim == null:
		draw_circle(Vector2.ZERO, 15.0, Color(0.12, 0.35, 0.5))
		draw_circle(Vector2.ZERO, 11.0, Color(0.35, 0.85, 1.0))
		draw_circle(Vector2.ZERO, 5.0, Color(1, 1, 1))
		var tip := facing * 21.0
		draw_colored_polygon(PackedVector2Array([tip, facing.rotated(0.5) * 12.0, facing.rotated(-0.5) * 12.0]), Color(0.8, 0.97, 1.0))
	if hp < max_hp * 0.3 and not dead:
		var a := (0.25 + 0.2 * sin(time_alive * 8.0)) if flash_on2 else 0.16
		draw_arc(Vector2.ZERO, 19.0, 0, TAU, 32, Color(1.0, 0.3, 0.3, a), 2.5, true)
