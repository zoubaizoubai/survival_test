extends Control

const RADIUS := 70.0
const MARGIN := 24.0

var vector := Vector2.ZERO
var touch_id := -1
var origin := Vector2.ZERO
var _base_pos := Vector2.ZERO
var _enabled := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_update_position)
	_update_position()
	set_process_input(_enabled)


func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	set_process_input(value)
	if not value:
		touch_id = -1
		vector = Vector2.ZERO
	queue_redraw()


func _update_position() -> void:
	# 将摇杆基座固定在左下安全区，适配 20:9 等宽屏
	var vp: Vector2 = get_viewport_rect().size
	var is_wide: bool = vp.x / maxf(vp.y, 1.0) > 1.95
	var margin_x: float = MARGIN + (16.0 if is_wide else 0.0)
	var margin_y: float = MARGIN + (8.0 if is_wide else 0.0)
	# 基座位置用于绘制与触摸判定
	_base_pos = Vector2(margin_x + RADIUS, vp.y - margin_y - RADIUS)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			# 仅在左下区域激活，避免与暂停按钮等冲突
			var vp: Vector2 = get_viewport_rect().size
			if event.position.x < vp.x * 0.35 and event.position.y > vp.y * 0.5:
				touch_id = event.index
				origin = event.position
				vector = Vector2.ZERO
				queue_redraw()
			else:
				# 忽略右半屏触摸
				return
		elif not event.pressed and event.index == touch_id:
			touch_id = -1
			vector = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == touch_id:
		var d: Vector2 = event.position - origin
		vector = d.limit_length(RADIUS) / RADIUS
		queue_redraw()
	elif event is InputEventKey or event is InputEventJoypadMotion or event is InputEventJoypadButton:
		# 键盘/手柄输入由 player.get_vector 处理，此处仅保持触摸向量
		pass


func _draw() -> void:
	if not _enabled:
		return
	if touch_id == -1:
		_draw_base(_base_pos, 0.68)
		draw_circle(_base_pos, 18.0, Color(0.94, 0.42, 0.38, 0.32))
		draw_arc(_base_pos, 18.0, 0, TAU, 28, Color(1.0, 0.92, 0.78, 0.32), 2.0, true)
		return
	_draw_base(origin, 1.0)
	var knob := origin + vector * RADIUS
	draw_circle(knob, 28.0, Color(0.18, 0.12, 0.08, 0.52))
	draw_circle(knob, 23.0, Color(0.94, 0.42, 0.38, 0.88))
	draw_arc(knob, 23.0, 0, TAU, 32, Color(1.0, 0.92, 0.78, 0.72), 2.0, true)


func _draw_base(center: Vector2, strength: float) -> void:
	draw_circle(center, RADIUS + 4.0, Color(0.04, 0.05, 0.055, 0.24 * strength))
	draw_circle(center, RADIUS, Color(0.18, 0.12, 0.08, 0.20 * strength))
	draw_circle(center, RADIUS - 8.0, Color(0.05, 0.08, 0.09, 0.20 * strength))
	draw_arc(center, RADIUS, 0, TAU, 48, Color(0.96, 0.90, 0.78, 0.46 * strength), 2.5, true)
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var marker: Vector2 = center + direction * (RADIUS - 14.0)
		draw_circle(marker, 3.0, Color(1.0, 0.92, 0.78, 0.46 * strength))
