extends Control

var game: Node2D
var hp_fill: ColorRect
var hp_label: Label
var xp_fill: ColorRect
var lv_label: Label
var time_label: Label
var kill_label: Label
var low_overlay: ColorRect
var pause_btn: Button
var t := 0.0
var _hp_bg: ColorRect
var _xp_bar: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	low_overlay = ColorRect.new()
	low_overlay.color = Color(1.0, 0.15, 0.15, 0.0)
	low_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	low_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(low_overlay)

	_hp_bg = ColorRect.new()
	_hp_bg.name = "HpBg"
	_hp_bg.color = Color(0, 0, 0, 0.45)
	_hp_bg.size = Vector2(232, 20)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.position = Vector2(2, 2)
	hp_fill.size = Vector2(228, 16)
	hp_fill.color = Color(0.35, 0.9, 0.45)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bg.add_child(hp_fill)
	hp_label = _make_label("100/100", 12, Color(1, 1, 1, 0.92))
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_bg.add_child(hp_label)

	time_label = _make_label("00:00", 30, Color(1, 1, 1, 0.95))
	time_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	time_label.offset_left = -90
	time_label.offset_right = 90
	time_label.offset_top = 8
	time_label.offset_bottom = 54
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(time_label)

	kill_label = _make_label("击杀 0", 15, Color(1, 1, 1, 0.75))
	kill_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(kill_label)

	pause_btn = Button.new()
	pause_btn.name = "PauseBtn"
	pause_btn.text = "II"
	pause_btn.focus_mode = Control.FOCUS_ALL
	pause_btn.focus_neighbor_left = NodePath("../KillLabel")
	pause_btn.add_theme_font_size_override("font_size", 16)
	pause_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.18)
	pause_btn.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color(1, 1, 1, 0.16)
	pause_btn.add_theme_stylebox_override("hover", sbh)
	pause_btn.add_theme_stylebox_override("pressed", sb)
	pause_btn.add_theme_stylebox_override("focus", sbh)
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.pressed.connect(func(): game.menus.toggle_pause())
	# 键盘/手柄：E / Start 亦可暂停，但按钮支持 Enter/Space
	pause_btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ENTER or ev.keycode == KEY_SPACE):
			game.menus.toggle_pause()
	)
	add_child(pause_btn)

	_xp_bar = ColorRect.new()
	_xp_bar.name = "XpBar"
	_xp_bar.color = Color(0, 0, 0, 0.5)
	_xp_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_bar)
	xp_fill = ColorRect.new()
	xp_fill.position = Vector2.ZERO
	xp_fill.size = Vector2(0, 10)
	xp_fill.color = Color(0.3, 0.8, 1.0)
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_child(xp_fill)

	lv_label = _make_label("LV 1", 14, Color(0.55, 0.9, 1.0))
	lv_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(lv_label)

	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _update_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	# 安全区域：基于视口宽高比动态边距，20:9 时左右留白更大但不裁切
	var is_wide: bool = vp.x / maxf(vp.y, 1.0) > 1.95
	var margin: float = 16.0
	var top_margin: float = 14.0 if not is_wide else 12.0
	# HP 背景
	if _hp_bg:
		_hp_bg.position = Vector2(margin, top_margin)
	# 击杀标签与暂停按钮避免重叠：宽屏时击杀右移
	if kill_label:
		kill_label.offset_left = -260 if is_wide else -240
		kill_label.offset_right = -64 if is_wide else -64
		kill_label.offset_top = 16
		kill_label.offset_bottom = 40
	if pause_btn:
		pause_btn.offset_left = -56
		pause_btn.offset_right = -14
		pause_btn.offset_top = 12
		pause_btn.offset_bottom = 50
		# 超宽屏时略缩小按钮
		if is_wide:
			pause_btn.custom_minimum_size = Vector2(42, 36)
		else:
			pause_btn.custom_minimum_size = Vector2(0, 0)
	# 等级与 XP：底部安全区
	if lv_label:
		lv_label.offset_left = margin
		lv_label.offset_right = 160
		lv_label.offset_top = -46
		lv_label.offset_bottom = -22
	if _xp_bar:
		_xp_bar.offset_top = -16
		_xp_bar.offset_bottom = -6
		# 超宽屏底部边距加大避免与手势条重叠
		if is_wide:
			_xp_bar.offset_top = -18
	# 时间标签保持居中，不受宽高比影响
	if time_label:
		var w: float = 90.0
		time_label.offset_left = -w
		time_label.offset_right = w


func _make_label(txt: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _process(delta: float) -> void:
	t += delta
	var pl: Node2D = game.player
	if pl == null:
		return
	var pct := clampf(pl.hp / pl.max_hp, 0.0, 1.0)
	hp_fill.size.x = 228.0 * pct
	hp_fill.color = Color(0.35, 0.9, 0.45) if pct > 0.5 else (Color(0.95, 0.8, 0.3) if pct > 0.25 else Color(0.95, 0.35, 0.3))
	hp_label.text = "%d/%d" % [int(ceilf(pl.hp)), int(pl.max_hp)]
	var xp_pct := clampf(float(pl.xp) / float(pl.xp_needed()), 0.0, 1.0)
	xp_fill.size.x = maxf(_xp_bar.size.x, 0.0) * xp_pct
	lv_label.text = "LV %d" % pl.level
	var secs := int(game.elapsed)
	time_label.text = "%d:%02d" % [floori(game.elapsed / 60.0), secs % 60]
	kill_label.text = "击杀 %d" % game.kills
	if pct < 0.3 and not pl.dead:
		low_overlay.color.a = 0.09 + 0.05 * sin(t * 6.0)
	else:
		low_overlay.color.a = 0.0
