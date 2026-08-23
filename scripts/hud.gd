extends Control

const Settings := preload("res://scripts/settings.gd")
const SpriteLibrary := preload("res://scripts/sprite_library.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const UiMode := preload("res://scripts/ui_mode.gd")

var game: Node2D
var hp_fill: Control
var hp_label: Label
var xp_fill: Control
var lv_label: Label
var time_label: Label
var kill_label: Label
var low_overlay: ColorRect
var pause_btn: Button
var t := 0.0
var boss_bar: ColorRect
var boss_fill: ColorRect
var boss_label: Label
var _hp_bg: Control
var _hp_trough: Control
var _xp_bar: Control
var _xp_trough: Control
var _weapon_row: HBoxContainer
var _kill_icon: TextureRect
var _time_bg: PanelContainer
var _controls_hint: PanelContainer
var _mobile_ui := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_ui = UiMode.is_mobile()

	low_overlay = ColorRect.new()
	low_overlay.color = Color(1.0, 0.15, 0.15, 0.0)
	low_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	low_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(low_overlay)

	var hp_parts: Dictionary = _make_framed_bar("HpBg", "res://assets/ui/hp_bar.png", Vector2(300, 88), Color(0.42, 0.86, 0.40), Rect2(0.1680, 0.3046, 0.7441, 0.3775))
	_hp_bg = hp_parts["wrap"]
	hp_fill = hp_parts["fill"]
	_hp_trough = hp_parts["trough"]
	hp_label = _make_label("100/100", 13, Color(UiStyle.INK.r, UiStyle.INK.g, UiStyle.INK.b, 0.95), false)
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_label.offset_left = 56
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_bg.add_child(hp_label)
	add_child(_hp_bg)

	_time_bg = PanelContainer.new()
	_time_bg.name = "TimeBg"
	_time_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var time_sb := StyleBoxFlat.new()
	time_sb.bg_color = Color(0.12, 0.09, 0.07, 0.88)
	time_sb.set_corner_radius_all(14)
	time_sb.set_border_width_all(2)
	time_sb.border_color = Color(0.96, 0.90, 0.78, 0.65)
	time_sb.content_margin_left = 18
	time_sb.content_margin_right = 18
	time_sb.content_margin_top = 6
	time_sb.content_margin_bottom = 6
	_time_bg.add_theme_stylebox_override("panel", time_sb)
	_time_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_time_bg.offset_left = -70
	_time_bg.offset_right = 70
	_time_bg.offset_top = 10
	_time_bg.offset_bottom = 50
	add_child(_time_bg)
	time_label = _make_label("00:00", 26, Color(1.0, 0.96, 0.88), true)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_bg.add_child(time_label)

	var kill_wrap := HBoxContainer.new()
	kill_wrap.name = "KillWrap"
	kill_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	kill_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kill_wrap.add_theme_constant_override("separation", 6)
	add_child(kill_wrap)
	_kill_icon = TextureRect.new()
	_kill_icon.custom_minimum_size = Vector2(22, 22)
	_kill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_kill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_kill_icon.texture = SpriteLibrary.icon("damage")
	_kill_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kill_wrap.add_child(_kill_icon)
	kill_label = _make_label("0", 16, Color(1, 1, 1, 0.92))
	kill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kill_wrap.add_child(kill_label)

	pause_btn = Button.new()
	pause_btn.name = "PauseBtn"
	pause_btn.text = ""
	pause_btn.tooltip_text = "暂停" if _mobile_ui else "暂停（Esc / P）"
	pause_btn.focus_mode = Control.FOCUS_ALL
	pause_btn.custom_minimum_size = Vector2(46, 46)
	var pause_icon := SpriteLibrary.icon("pause")
	if pause_icon:
		pause_btn.icon = pause_icon
		pause_btn.expand_icon = true
	else:
		pause_btn.text = "II"
	pause_btn.add_theme_color_override("icon_normal_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.08, 0.45)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.92, 0.78, 0.35)
	pause_btn.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color(0.28, 0.18, 0.12, 0.7)
	pause_btn.add_theme_stylebox_override("hover", sbh)
	pause_btn.add_theme_stylebox_override("pressed", sb)
	pause_btn.add_theme_stylebox_override("focus", sbh)
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.pressed.connect(func(): game.menus.toggle_pause())
	pause_btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ENTER or ev.keycode == KEY_SPACE):
			game.menus.toggle_pause()
	)
	add_child(pause_btn)

	var xp_parts: Dictionary = _make_framed_bar("XpBar", "res://assets/ui/xp_bar.png", Vector2(420, 126), Color(0.32, 0.72, 0.95), Rect2(0.1367, 0.3052, 0.7754, 0.3766))
	_xp_bar = xp_parts["wrap"]
	xp_fill = xp_parts["fill"]
	_xp_trough = xp_parts["trough"]
	_xp_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	add_child(_xp_bar)

	lv_label = _make_label("LV 1", 14, Color(UiStyle.INK.r, UiStyle.INK.g, UiStyle.INK.b, 0.92), false)
	lv_label.position = Vector2(78, 40)
	lv_label.size = Vector2(74, 42)
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_bar.add_child(lv_label)

	_weapon_row = HBoxContainer.new()
	_weapon_row.name = "WeaponRow"
	_weapon_row.add_theme_constant_override("separation", 8)
	_weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	add_child(_weapon_row)
	for i in 4:
		var slot := TextureRect.new()
		slot.name = "Weapon%d" % i
		slot.custom_minimum_size = Vector2(40, 40)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.modulate = Color(1, 1, 1, 0.35)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_weapon_row.add_child(slot)

	_build_controls_hint()

	boss_bar = ColorRect.new()
	boss_bar.name = "BossBar"
	boss_bar.color = Color(0.12, 0.08, 0.08, 0.7)
	boss_bar.size = Vector2(520, 16)
	boss_bar.visible = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(boss_bar)
	boss_fill = ColorRect.new()
	boss_fill.color = Color(0.9, 0.25, 0.3)
	boss_fill.size = Vector2(516, 12)
	boss_fill.position = Vector2(2, 2)
	boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar.add_child(boss_fill)
	boss_label = _make_label("BOSS", 12, Color(1, 1, 1, 0.95))
	boss_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boss_bar.add_child(boss_label)

	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _build_controls_hint() -> void:
	_controls_hint = PanelContainer.new()
	_controls_hint.name = "ControlsHint"
	_controls_hint.visible = not _mobile_ui
	_controls_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.035, 0.055, 0.06, 0.78)
	hint_style.set_corner_radius_all(12)
	hint_style.set_border_width_all(1)
	hint_style.border_color = Color(1.0, 0.92, 0.78, 0.20)
	hint_style.content_margin_left = 14
	hint_style.content_margin_right = 14
	hint_style.content_margin_top = 7
	hint_style.content_margin_bottom = 7
	_controls_hint.add_theme_stylebox_override("panel", hint_style)
	_controls_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(_controls_hint)
	var hint_label := _make_label("WASD / 方向键移动   ·   Esc 暂停", 12, Color(1, 1, 1, 0.72), false)
	_controls_hint.add_child(hint_label)


func _update_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var is_wide: bool = vp.x / maxf(vp.y, 1.0) > 1.95
	var margin: float = 16.0
	var top_margin: float = 10.0 if not is_wide else 8.0
	if _hp_bg:
		_hp_bg.position = Vector2(margin, top_margin)
		_hp_bg.size = Vector2(300, 88)
		_layout_trough(_hp_bg)
	var kill_wrap: Control = get_node_or_null("KillWrap") as Control
	if kill_wrap:
		kill_wrap.offset_left = -250 if is_wide else -230
		kill_wrap.offset_right = -72
		kill_wrap.offset_top = 16
		kill_wrap.offset_bottom = 44
	if pause_btn:
		pause_btn.offset_left = -58
		pause_btn.offset_right = -12
		pause_btn.offset_top = 10
		pause_btn.offset_bottom = 54
	if _xp_bar:
		_xp_bar.offset_left = -210
		_xp_bar.offset_right = 210
		_xp_bar.offset_top = -134
		_xp_bar.offset_bottom = -8
		_xp_bar.size = Vector2(420, 126)
		_layout_trough(_xp_bar)
	if _weapon_row:
		_weapon_row.offset_left = -200
		_weapon_row.offset_right = -16
		_weapon_row.offset_top = -178
		_weapon_row.offset_bottom = -134
	if boss_bar:
		boss_bar.position = Vector2((vp.x - boss_bar.size.x) * 0.5, 58)
	if _time_bg:
		_time_bg.offset_left = -70
		_time_bg.offset_right = 70
		_time_bg.offset_top = 10
		_time_bg.offset_bottom = 50
	if _controls_hint:
		_controls_hint.offset_left = margin
		_controls_hint.offset_right = margin + 300
		_controls_hint.offset_top = -60
		_controls_hint.offset_bottom = -16


func _make_framed_bar(bar_name: String, frame_path: String, bar_size: Vector2, fill_color: Color, trough_uv: Rect2) -> Dictionary:
	var wrap := Control.new()
	wrap.name = bar_name
	wrap.custom_minimum_size = bar_size
	wrap.size = bar_size
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.clip_contents = true
	wrap.set_meta("trough_uv", trough_uv)
	var frame := TextureRect.new()
	frame.name = "Frame"
	frame.texture = UiStyle.tex(frame_path)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(frame)
	var trough := Control.new()
	trough.name = "Trough"
	trough.clip_contents = true
	trough.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(trough)
	var fill := Panel.new()
	fill.name = "Fill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = fill_color
	fsb.set_corner_radius_all(20)
	fill.add_theme_stylebox_override("panel", fsb)
	trough.add_child(fill)
	_layout_trough(wrap)
	return {"wrap": wrap, "trough": trough, "fill": fill}


func _layout_trough(wrap: Control) -> void:
	if wrap == null:
		return
	var frame: TextureRect = wrap.get_node_or_null("Frame") as TextureRect
	var trough: Control = wrap.get_node_or_null("Trough") as Control
	if trough == null:
		return
	var uv: Rect2 = wrap.get_meta("trough_uv", Rect2(0.17, 0.30, 0.74, 0.38)) as Rect2
	var drawn: Rect2 = _displayed_tex_rect(wrap, frame)
	trough.position = Vector2(drawn.position.x + drawn.size.x * uv.position.x, drawn.position.y + drawn.size.y * uv.position.y)
	trough.size = Vector2(drawn.size.x * uv.size.x, drawn.size.y * uv.size.y)


func _displayed_tex_rect(wrap: Control, frame: TextureRect) -> Rect2:
	if wrap == null:
		return Rect2()
	var s: Vector2 = wrap.size
	if frame == null or frame.texture == null:
		return Rect2(Vector2.ZERO, s)
	var ts: Vector2 = frame.texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Rect2(Vector2.ZERO, s)
	var sc: float = minf(s.x / ts.x, s.y / ts.y)
	var ds: Vector2 = ts * sc
	return Rect2((s - ds) * 0.5, ds)


func _set_fill(fill: Control, trough: Control, pct: float) -> void:
	if fill == null or trough == null:
		return
	var h: float = trough.size.y
	fill.position = Vector2.ZERO
	fill.size = Vector2(trough.size.x * clampf(pct, 0.0, 1.0), h)
	if fill is Panel:
		var sb: StyleBox = (fill as Panel).get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).set_corner_radius_all(int(round(h * 0.5)))


func _set_fill_color(fill: Control, col: Color) -> void:
	if fill is Panel:
		var sb: StyleBox = (fill as Panel).get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).bg_color = col
	elif fill is ColorRect:
		(fill as ColorRect).color = col


func _make_label(txt: String, font_size: int, col: Color, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 4)
	else:
		l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.0))
		l.add_theme_constant_override("outline_size", 0)
	return l


func _process(delta: float) -> void:
	t += delta
	if _controls_hint and _controls_hint.visible:
		_controls_hint.modulate.a = clampf((8.0 - t) / 2.0, 0.0, 1.0)
	var pl: Node2D = game.player
	if pl == null:
		return
	var pct := clampf(pl.hp / pl.max_hp, 0.0, 1.0)
	_set_fill(hp_fill, _hp_trough, pct)
	_set_fill_color(hp_fill, Color(0.42, 0.86, 0.40) if pct > 0.5 else (Color(0.95, 0.78, 0.28) if pct > 0.25 else Color(0.95, 0.35, 0.3)))
	hp_label.text = "%d/%d" % [int(ceilf(pl.hp)), int(pl.max_hp)]
	var xp_pct := clampf(float(pl.xp) / float(maxi(pl.xp_needed(), 1)), 0.0, 1.0)
	_set_fill(xp_fill, _xp_trough, xp_pct)
	lv_label.text = "LV %d" % pl.level
	time_label.text = "%d:%02d" % [floori(game.elapsed / 60.0), int(game.elapsed) % 60]
	kill_label.text = "%d" % game.kills
	_refresh_weapons(pl)
	var flash_on: bool = Settings.is_flash_enabled()
	if pct < 0.3 and not pl.dead:
		low_overlay.color.a = (0.09 + 0.05 * sin(t * 6.0)) if flash_on else 0.07
	else:
		low_overlay.color.a = 0.0
	var boss: Node = null
	for e in game.get_enemies():
		if e.kind == "boss" and not e.dead:
			boss = e
			break
	if boss != null:
		boss_bar.visible = true
		var bpct: float = clampf(float(boss.hp) / float(boss.max_hp), 0.0, 1.0)
		boss_fill.size.x = 516.0 * bpct
		boss_fill.color = Color(0.9, 0.25, 0.3) if bpct > 0.5 else (Color(0.95, 0.55, 0.2) if int(boss.boss_phase) == 1 else Color(0.98, 0.3, 0.32))
		boss_label.text = "BOSS %d%% %s" % [int(bpct * 100), "· 狂暴" if int(boss.boss_phase) == 2 else ""]
	else:
		boss_bar.visible = false


func _refresh_weapons(pl: Node2D) -> void:
	if _weapon_row == null:
		return
	var ids: Array = pl.weapons.keys()
	for i in 4:
		var slot: TextureRect = _weapon_row.get_child(i) as TextureRect
		if slot == null:
			continue
		if i < ids.size():
			slot.texture = SpriteLibrary.icon(str(ids[i]))
			slot.modulate = Color.WHITE
		else:
			slot.texture = SpriteLibrary.icon("dagger")
			slot.modulate = Color(1, 1, 1, 0.18)
