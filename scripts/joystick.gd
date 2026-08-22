extends Control

const RADIUS := 70.0
const MARGIN := 24.0

var vector := Vector2.ZERO
var touch_id := -1
var origin := Vector2.ZERO
var _base_pos := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_update_position)
	_update_position()


func _update_position() -> void:
	# 将摇杆基座固定在左下安全区，适配 20:9 等宽屏
	var vp: Vector2 = get_viewport_rect().size
	var is_wide: bool = vp.x / maxf(vp.y, 1.0) > 1.95
	var margin_x: float = MARGIN + (16.0 if is_wide else 0.0)
	var margin_y: float = MARGIN + (8.0 if is_wide else 0.0)
	# 基座位置用于绘制与触摸判定
	_base_pos = Vector2(margin_x + RADIUS, vp.y - margin_y - RADIUS)
	# 触摸未激活时不绘制，激活时以 origin 为中心


func _input(event: InputEvent) -> void:
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
	if touch_id == -1:
		# 未触摸时绘制半透明基座提示（左下），便于发现
		var vp: Vector2 = get_viewport_rect().size
		var base: Vector2 = Vector2(MARGIN + RADIUS, vp.y - MARGIN - RADIUS)
		var is_wide: bool = vp.x / maxf(vp.y, 1.0) > 1.95
		if is_wide:
			base.x += 16.0
		draw_circle(base, RADIUS, Color(1, 1, 1, 0.03))
		draw_arc(base, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.12), 1.5, true)
		return
	draw_circle(origin, RADIUS, Color(1, 1, 1, 0.06))
	draw_arc(origin, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.25), 2.0, true)
	var knob := origin + vector * RADIUS
	draw_circle(knob, 26.0, Color(0.4, 0.85, 1.0, 0.35))
	draw_circle(knob, 18.0, Color(0.6, 0.92, 1.0, 0.7))
