extends Node2D

signal hp_changed(hp_value: float, max_hp_value: float)
signal xp_changed(xp_value: int, needed: int, level_value: int)
signal leveled_up
signal died

const ProjectileScript := preload("res://scripts/projectile.gd")

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


func _ready() -> void:
	add_to_group("player")
	max_hp = BASE_HP
	hp = max_hp
	add_weapon("dagger")


func _process(delta: float) -> void:
	if dead:
		return
	time_alive += delta
	invuln = maxf(invuln - delta, 0.0)
	_move(delta)
	_update_weapons(delta)
	modulate.a = 1.0 if invuln <= 0.0 else 0.55 + 0.45 * absf(sin(time_alive * 30.0))
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
			"dagger":
				w["t"] -= delta
				if w["t"] <= 0.0:
					if _fire_dagger():
						w["t"] = wstat("dagger")["cd"] * cd_mult()
					else:
						w["t"] = 0.2
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
	orbit_angle += orbit_rot() * delta
	_orbit_damage(delta)


func orbit_rot() -> float:
	if weapons.has("orbit"):
		return wstat("orbit")["rot"]
	return 0.0


func orb_positions() -> Array:
	var st := wstat("orbit")
	var arr: Array = []
	var n: int = st["orbs"]
	for i in n:
		arr.append(Vector2.from_angle(orbit_angle + TAU * i / n) * st["radius"])
	return arr


func _nearest_enemy(max_d: float) -> Node2D:
	var best: Node2D = null
	var bd := max_d * max_d
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _fire_dagger() -> bool:
	var target := _nearest_enemy(900.0)
	if target == null:
		return false
	var st := wstat("dagger")
	var n: int = st["count"]
	var dir0: Vector2 = (target.global_position - global_position).normalized()
	for i in n:
		var spread := deg_to_rad(-8.0 * (n - 1) * 0.5 + 8.0 * i)
		var d := dir0.rotated(spread)
		var p := ProjectileScript.new()
		p.game = game
		p.dir = d
		p.dmg = st["dmg"]
		p.pierce = st["pierce"]
		p.position = position + d * 16.0
		game.projectiles_node.add_child(p)
	game.sfx.play("shoot")
	return true


func _fire_lightning() -> void:
	var st := wstat("lightning")
	var pool: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
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
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if global_position.distance_to(e.global_position) < r + e.radius:
			game.hurt_enemy(e, dmg, (e.global_position - pos).normalized() * 80.0)


func _aura_tick() -> void:
	var st := wstat("aura")
	var r: float = st["radius"]
	var dmg: float = st["dps"] * 0.5
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if global_position.distance_to(e.global_position) < r + e.radius:
			game.hurt_enemy(e, dmg)


func _orbit_damage(delta: float) -> void:
	if not weapons.has("orbit"):
		return
	if orbit_hits.size() > 300:
		orbit_hits.clear()
	var st := wstat("orbit")
	var positions := orb_positions()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var eid: int = e.get_instance_id()
		if orbit_hits.has(eid):
			orbit_hits[eid] -= delta
			if orbit_hits[eid] > 0.0:
				continue
		for op in positions:
			var og: Vector2 = global_position + op
			if og.distance_to(e.global_position) < 12.0 + e.radius:
				game.hurt_enemy(e, st["dmg"], (e.global_position - global_position).normalized() * 150.0)
				orbit_hits[eid] = 0.45
				break


func _draw() -> void:
	if weapons.has("aura"):
		var st := wstat("aura")
		var r: float = st["radius"] * (1.0 + 0.03 * sin(time_alive * 4.0))
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.9, 0.5, 0.055))
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(1.0, 0.85, 0.4, 0.22), 2.0, true)
	if weapons.has("orbit"):
		for pos in orb_positions():
			draw_circle(pos, 9.0, Color(0.75, 0.85, 1.0, 0.95))
			draw_circle(pos, 4.5, Color(1, 1, 1, 0.95))
	draw_circle(Vector2.ZERO, 15.0, Color(0.12, 0.35, 0.5))
	draw_circle(Vector2.ZERO, 11.0, Color(0.35, 0.85, 1.0))
	draw_circle(Vector2.ZERO, 5.0, Color(1, 1, 1))
	var tip := facing * 21.0
	draw_colored_polygon(PackedVector2Array([tip, facing.rotated(0.5) * 12.0, facing.rotated(-0.5) * 12.0]), Color(0.8, 0.97, 1.0))
	if hp < max_hp * 0.3 and not dead:
		var a := 0.25 + 0.2 * sin(time_alive * 8.0)
		draw_arc(Vector2.ZERO, 19.0, 0, TAU, 32, Color(1.0, 0.3, 0.3, a), 2.5, true)
