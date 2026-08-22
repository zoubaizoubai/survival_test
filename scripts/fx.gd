extends Node2D

class FloatText extends Label:
	var life := 0.7
	var vy := -46.0
	var color_value := Color.WHITE
	var text_value := ""

	func _init() -> void:
		add_to_group("float_text")

	func _ready() -> void:
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_theme_font_size_override("font_size", 13)
		add_theme_color_override("font_color", color_value)
		add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		add_theme_constant_override("outline_size", 4)
		text = text_value

	func _process(delta: float) -> void:
		life -= delta
		position.y += vy * delta
		vy *= 0.94
		modulate.a = clampf(life / 0.35, 0.0, 1.0)
		if life <= 0.0:
			queue_free()


class Burst extends Node2D:
	var color_v := Color.WHITE
	var max_r := 20.0
	var life := 0.35
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		if t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := t / life
		var r := max_r * (0.3 + 0.7 * k)
		var a := 1.0 - k
		draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(color_v.r, color_v.g, color_v.b, a * 0.8), 3.0)
		for i in 8:
			var ang := TAU * i / 8.0
			draw_line(Vector2.from_angle(ang) * r * 0.7, Vector2.from_angle(ang) * r * 1.15, Color(color_v.r, color_v.g, color_v.b, a), 2.0)


class Lightning extends Node2D:
	var target := Vector2.ZERO
	var life := 0.22
	var t := 0.0
	var pts := PackedVector2Array()

	func _ready() -> void:
		var start := target + Vector2(randf_range(-60, 60), -430)
		pts.append(start)
		var segs := 7
		for i in range(1, segs):
			var k := float(i) / float(segs)
			pts.append(start.lerp(target, k) + Vector2(randf_range(-26, 26), 0))
		pts.append(target)

	func _process(delta: float) -> void:
		t += delta
		if t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := 1.0 - t / life
		draw_polyline(pts, Color(0.75, 0.85, 1.0, a), 3.0)
		draw_polyline(pts, Color(1, 1, 1, a * 0.9), 1.2)
		var ir := 34.0 * (0.4 + 0.6 * (t / life))
		draw_arc(target, ir, 0, TAU, 20, Color(0.8, 0.9, 1.0, a), 2.5)
