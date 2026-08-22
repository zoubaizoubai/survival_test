extends Node2D

var kind := "gem"
var value := 1
var magnet := false
var vel := Vector2.ZERO
var t := 0.0
var collected := false


func _ready() -> void:
	add_to_group("pickup")
	t = randf() * TAU


func _process(delta: float) -> void:
	t += delta
	var pl: Node2D = get_tree().get_first_node_in_group("player")
	if pl == null or pl.dead:
		return
	var d := global_position.distance_to(pl.global_position)
	if d < pl.magnet_radius():
		magnet = true
	if magnet:
		vel = vel.move_toward((pl.global_position - global_position).normalized() * 520.0, 2400.0 * delta)
		position += vel * delta
		if d < 18.0:
			_collect(pl)
	else:
		position.y += sin(t * 3.0) * 6.0 * delta
	queue_redraw()


func _collect(pl: Node2D) -> void:
	if collected:
		return
	collected = true
	if kind == "gem":
		pl.gain_xp(value)
		pl.game.sfx.play("pickup")
	else:
		pl.heal(value)
		pl.game.sfx.play("heal")
	queue_free()


func _draw() -> void:
	if kind == "gem":
		var s := 6.0 if value < 3 else 8.5
		var col := Color(0.35, 0.95, 0.75) if value < 3 else Color(0.4, 0.7, 1.0)
		var bob := sin(t * 4.0) * 1.5
		var pts := PackedVector2Array([
			Vector2(0, -s + bob), Vector2(s * 0.7, bob), Vector2(0, s + bob), Vector2(-s * 0.7, bob),
		])
		pts.append(pts[0])
		draw_colored_polygon(pts, col)
		draw_polyline(pts, col.lightened(0.4), 1.2, true)
	else:
		var pulse := 1.0 + 0.12 * sin(t * 6.0)
		var r := 7.0 * pulse
		var c := Color(1.0, 0.4, 0.55)
		draw_circle(Vector2(-r * 0.45, -r * 0.3), r * 0.62, c)
		draw_circle(Vector2(r * 0.45, -r * 0.3), r * 0.62, c)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-r * 1.02, -r * 0.05), Vector2(r * 1.02, -r * 0.05), Vector2(0, r * 1.1),
		]), c)
