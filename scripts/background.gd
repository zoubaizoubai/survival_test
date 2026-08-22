extends Node2D

var game: Node2D


func _draw() -> void:
	var a: float = game.ARENA
	draw_rect(Rect2(-a - 400, -a - 400, (a + 400) * 2, (a + 400) * 2), Color(0.07, 0.10, 0.09))
	draw_rect(Rect2(-a, -a, a * 2, a * 2), Color(0.10, 0.14, 0.13))
	draw_rect(Rect2(-a, -a, a * 2, a * 2), Color(0.45, 0.62, 0.48, 0.35), false, 5.0)
	var step := 130.0
	var line_c := Color(1, 1, 1, 0.032)
	var x := -a
	while x <= a:
		draw_line(Vector2(x, -a), Vector2(x, a), line_c, 1.0)
		draw_line(Vector2(-a, x), Vector2(a, x), line_c, 1.0)
		x += step
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 260:
		var p := Vector2(rng.randf_range(-a, a), rng.randf_range(-a, a))
		draw_circle(p, rng.randf_range(1.5, 4.5), Color(1, 1, 1, rng.randf_range(0.02, 0.06)))
