extends Node2D

var game: Node2D
var dir := Vector2.RIGHT
var speed := 560.0
var dmg := 10.0
var pierce := 1
var life := 1.5
var hit_ids := {}
var is_boomerang := false
var boomerang_t := 0.0
var boomerang_return := 0.45
var boomerang_has_returned := false


func _ready() -> void:
	rotation = dir.angle()


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		if game:
			game._recycle_projectile(self)
		else:
			queue_free()
		return
	if is_boomerang:
		boomerang_t += delta
		if not boomerang_has_returned and boomerang_t >= boomerang_return:
			boomerang_has_returned = true
			# 翻转向玩家
			if game and game.player:
				dir = (game.player.global_position - global_position).normalized()
				if dir == Vector2.ZERO:
					dir = -dir
				rotation = dir.angle()
		elif boomerang_has_returned and game and game.player:
			# 归航：轻微导向
			var to_p: Vector2 = game.player.global_position - global_position
			dir = dir.lerp(to_p.normalized(), 6.0 * delta).normalized()
			rotation = dir.angle()
			# 若接近玩家则回收视为结束（避免一直飞）
			if to_p.length() < 18.0 and life < 1.0:
				if game:
					game._recycle_projectile(self)
				else:
					queue_free()
				return
	position += dir * speed * delta
	# 碰撞：使用注册表与平方距离，避免 pow
	for e in game.get_enemies() if game else []:
		if e.dead or hit_ids.has(e.get_instance_id()):
			continue
		var rad: float = e.radius + 7.0
		if global_position.distance_squared_to(e.global_position) < rad * rad:
			hit_ids[e.get_instance_id()] = true
			game.hurt_enemy(e, dmg, dir * 130.0)
			pierce -= 1
			if pierce <= 0:
				if game:
					game._recycle_projectile(self)
				else:
					queue_free()
				return


func _draw() -> void:
	if is_boomerang:
		# 回旋斧：双头斧
		draw_line(Vector2(-22, 0), Vector2(-10, 0), Color(0.55, 0.85, 0.45, 0.35), 3.0)
		var col := Color(0.62, 0.93, 0.45) if not boomerang_has_returned else Color(0.85, 0.96, 0.6)
		draw_rect(Rect2(-4, -6, 12, 12), col)
		draw_rect(Rect2(-4, -6, 12, 12), col.darkened(0.35), false, 2.0)
		# 旋转感
		var ang: float = fmod(boomerang_t * 18.0, TAU)
		draw_line(Vector2.ZERO, Vector2.from_angle(ang) * 9.0, Color(1,1,1,0.9), 2.0)
		return
	draw_line(Vector2(-26, 0), Vector2(-8, 0), Color(0.6, 0.9, 1.0, 0.35), 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(11, 0), Vector2(-5, 4.5), Vector2(-2, 0), Vector2(-5, -4.5),
	]), Color(0.85, 0.97, 1.0))
