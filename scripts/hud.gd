extends Control

const Settings := preload("res://scripts/settings.gd")
const SpriteLibrary := preload("res://scripts/sprite_library.gd")
const UiStyle := preload("res://scripts/ui_style.gd")

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
var boss_bar: ColorRect
var boss_fill: ColorRect
var boss_label: Label
var _hp_bg: Control
var _xp_bar: Control
var _weapon_row: HBoxContainer
var _kill_icon: TextureRect
var _time_bg: NinePatchRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	low_overlay = ColorRect.new()
	low_overlay.color = Color(1.0, 0.15, 0.15, 0.0)
	low_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	low_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(low_overlay)

	_hp_bg = Control.new()
	_hp_bg.name = "HpBg"
	_hp_bg.custom_minimum_size = Vector2(268, 56)
	_hp_bg.size = Vector2(268, 56)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.42, 0.86, 0.40)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bg.add_child(hp_fill)
	var hp_frame := TextureRect.new()
	hp_frame.texture = UiStyle.tex("res://assets/ui/hp_bar.png")
	hp_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hp_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hp_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bg.add_child(hp_frame)
	hp_label = _make_label("100/100", 13, Color(UiStyle.INK.r, UiStyle.INK.g, UiStyle.INK.b, 0.95), false)
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_label.offset_left = 54
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_bg.add_child(hp_label)

	_time_bg = NinePatchRect.new()
	_time_bg.texture = UiStyle.tex("res://assets/ui/panel.png")
	_time_bg.patch_margin_left = 48
	_time_bg.patch_margin_right = 48
	_time_bg.patch_margin_top = 40
	_time_bg.patch_margin_bottom = 40
	_time_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_time_bg.offset_left = -78
	_time_bg.offset_right = 78
	_time_bg.offset_top = 6
	_time_bg.offset_bottom = 52
	_time_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_bg)
	time_label = _make_label("00:00", 26, UiStyle.INK, false)
	time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	_xp_bar = Control.new()
	_xp_bar.name = "XpBar"
	_xp_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_bar)
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.32, 0.72, 0.95)
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_child(xp_fill)
	var xp_frame := TextureRect.new()
	xp_frame.texture = UiStyle.tex("res://assets/ui/xp_bar.png")
	xp_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	xp_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	xp_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	xp_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_child(xp_frame)

	lv_label = _make_label("LV 1", 14, Color(1.0, 0.93, 0.72))
	lv_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(lv_label)

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


func _update_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var is_wide: bool = vp.x / maxf(vp.y, 1.0) > 1.95
	var margin: float = 16.0
	var top_margin: float = 10.0 if not is_wide else 8.0
	if _hp_bg:
		_hp_bg.position = Vector2(margin, top_margin)
		_hp_bg.size = Vector2(268, 56)
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
	if lv_label:
		lv_label.offset_left = margin + 8
		lv_label.offset_right = 140
		lv_label.offset_top = -58
		lv_label.offset_bottom = -32
	if _xp_bar:
		_xp_bar.offset_left = 120
		_xp_bar.offset_right = -16
		_xp_bar.offset_top = -52
		_xp_bar.offset_bottom = -8
		if is_wide:
			_xp_bar.offset_top = -56
	if _weapon_row:
		_weapon_row.offset_left = -200
		_weapon_row.offset_right = -16
		_weapon_row.offset_top = -102
		_weapon_row.offset_bottom = -58
	if boss_bar:
		boss_bar.position = Vector2((vp.x - boss_bar.size.x) * 0.5, 58)
	if _time_bg:
		_time_bg.offset_left = -78
		_time_bg.offset_right = 78


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
	var pl: Node2D = game.player
	if pl == null:
		return
	var pct := clampf(pl.hp / pl.max_hp, 0.0, 1.0)
	# 血槽填在心形木框的内槽
	var trough := Rect2(54, 18, 198, 22)
	hp_fill.position = trough.position
	hp_fill.size = Vector2(trough.size.x * pct, trough.size.y)
	hp_fill.color = Color(0.42, 0.86, 0.40) if pct > 0.5 else (Color(0.95, 0.78, 0.28) if pct > 0.25 else Color(0.95, 0.35, 0.3))
	hp_label.text = "%d/%d" % [int(ceilf(pl.hp)), int(pl.max_hp)]
	var xp_pct := clampf(float(pl.xp) / float(pl.xp_needed()), 0.0, 1.0)
	var xb: Vector2 = _xp_bar.size
	var xtrough := Rect2(xb.x * 0.12, xb.y * 0.34, xb.x * 0.80, xb.y * 0.32)
	xp_fill.position = xtrough.position
	xp_fill.size = Vector2(xtrough.size.x * xp_pct, xtrough.size.y)
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
