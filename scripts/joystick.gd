extends Control

const RADIUS := 70.0

var vector := Vector2.ZERO
var touch_id := -1
var origin := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			touch_id = event.index
			origin = event.position
			vector = Vector2.ZERO
			queue_redraw()
		elif not event.pressed and event.index == touch_id:
			touch_id = -1
			vector = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == touch_id:
		var d: Vector2 = event.position - origin
		vector = d.limit_length(RADIUS) / RADIUS
		queue_redraw()


func _draw() -> void:
	if touch_id == -1:
		return
	draw_circle(origin, RADIUS, Color(1, 1, 1, 0.06))
	draw_arc(origin, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.25), 2.0, true)
	var knob := origin + vector * RADIUS
	draw_circle(knob, 26.0, Color(0.4, 0.85, 1.0, 0.35))
	draw_circle(knob, 18.0, Color(0.6, 0.92, 1.0, 0.7))
