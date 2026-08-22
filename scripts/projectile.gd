extends Node2D

var game: Node2D
var dir := Vector2.RIGHT
var speed := 560.0
var dmg := 10.0
var pierce := 1
var life := 1.5
var hit_ids := {}


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
	draw_line(Vector2(-26, 0), Vector2(-8, 0), Color(0.6, 0.9, 1.0, 0.35), 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(11, 0), Vector2(-5, 4.5), Vector2(-2, 0), Vector2(-5, -4.5),
	]), Color(0.85, 0.97, 1.0))
