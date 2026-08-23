extends Control

const Settings := preload("res://scripts/settings.gd")
const SaveData := preload("res://scripts/save_data.gd")
const MusicScript := preload("res://scripts/music.gd")
const GameData := preload("res://scripts/game_data.gd")
const UiStyle := preload("res://scripts/ui_style.gd")

var settings_layer: Control
var volume_slider: HSlider
var volume_label: Label
var music_slider: HSlider
var music_label: Label
var sfx_slider: HSlider
var sfx_label: Label
var shake_check: CheckBox
var flash_check: CheckBox
var fps_check: CheckBox
var stats_label: Label
var unlock_label: Label
var music: Node
var clear_save_button: Button
var clear_confirm_layer: Control
var clear_confirm_cancel_button: Button
var clear_confirm_accept_button: Button


func _ready() -> void:
	Settings.ensure_loaded()
	SaveData.ensure_loaded()
	GameData.ensure_loaded()
	_build_settings_layer()
	_build_stats_display()
	if not has_node("Music"):
		music = MusicScript.new()
		music.name = "Music"
		add_child(music)
	# 确保按钮存在时连接（tscn 已有连接，此处补充以防动态创建）
	var start_btn: Button = get_node_or_null("CenterContainer/VBoxContainer/StartButton") as Button
	var settings_btn: Button = get_node_or_null("CenterContainer/VBoxContainer/SettingsButton") as Button
	var exit_btn: Button = get_node_or_null("CenterContainer/VBoxContainer/ExitButton") as Button
	if start_btn:
		start_btn.focus_mode = Control.FOCUS_ALL
	if settings_btn:
		settings_btn.focus_mode = Control.FOCUS_ALL
	if exit_btn:
		exit_btn.focus_mode = Control.FOCUS_ALL
	# 默认焦点
	if start_btn:
		start_btn.grab_focus()
	_rebuild_title_layout()
	# 响应式：监听视口变化
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	# 应用已保存设置
	Settings.ensure_loaded()


func _build_stats_display() -> void:
	var vbox: VBoxContainer = get_node_or_null("CenterContainer/VBoxContainer") as VBoxContainer
	if vbox == null:
		return
	# 避免重复创建
	if has_node("CenterContainer/VBoxContainer/StatsLabel"):
		stats_label = get_node("CenterContainer/VBoxContainer/StatsLabel") as Label
	else:
		stats_label = Label.new()
		stats_label.name = "StatsLabel"
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_label.add_theme_font_size_override("font_size", 13)
		stats_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_label.custom_minimum_size = Vector2(340, 0)
		# 插入在 Title 之后，按钮之前
		var title_idx: int = 0
		for i in vbox.get_child_count():
			if vbox.get_child(i).name == "Title":
				title_idx = i
				break
		vbox.add_child(stats_label)
		vbox.move_child(stats_label, title_idx + 1)
	if has_node("CenterContainer/VBoxContainer/UnlockLabel"):
		unlock_label = get_node("CenterContainer/VBoxContainer/UnlockLabel") as Label
	else:
		unlock_label = Label.new()
		unlock_label.name = "UnlockLabel"
		unlock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlock_label.add_theme_font_size_override("font_size", 12)
		unlock_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.65))
		unlock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unlock_label.custom_minimum_size = Vector2(340, 0)
		vbox.add_child(unlock_label)
		# 放在 Stats 之后
		if stats_label:
			vbox.move_child(unlock_label, stats_label.get_index() + 1)
	_refresh_stats_display()


func _refresh_unlock_info() -> void:
	var info: Label = get_node_or_null("SettingsLayer/CenterContainer/PanelContainer/VBoxContainer/UnlockInfo") as Label
	if info == null:
		return
	var prog: Dictionary = SaveData.get_unlock_progress()
	var parts: Array = []
	for uid in prog.keys():
		var u: Dictionary = prog[uid] as Dictionary
		var name: String = str(u.get("name", uid))
		parts.append("%s %s" % [name, "已解锁" if bool(u.get("unlocked", false)) else "未解锁"])
	info.text = " · ".join(parts) if not parts.is_empty() else "尚无解锁记录"


func _refresh_stats_display() -> void:
	if stats_label == null:
		return
	var best: Dictionary = SaveData.get_best()
	var totals: Dictionary = SaveData.get_totals()
	var bt: float = float(best.get("time", 0.0))
	if bt > 0.01:
		stats_label.text = "最佳 %d:%02d  ·  击杀 %d  ·  等级 %d" % [floori(bt / 60.0), int(bt) % 60, int(best.get("kills", 0)), int(best.get("level", 1))]
	else:
		stats_label.text = "累计击杀 %d  ·  局数 %d" % [int(totals.get("total_kills", 0)), int(totals.get("total_games", 0))]
	if unlock_label:
		var prog: Dictionary = SaveData.get_unlock_progress()
		var locked: Array = []
		var unlocked_n: Array = []
		for uid in prog.keys():
			var info: Dictionary = prog[uid] as Dictionary
			var name: String = str(info.get("name", uid))
			if bool(info.get("unlocked", false)):
				unlocked_n.append(name)
			else:
				locked.append(name)
		if not unlocked_n.is_empty() and locked.is_empty():
			unlock_label.text = "已解锁 " + " · ".join(unlocked_n)
		elif not locked.is_empty():
			unlock_label.text = "未解锁  " + " · ".join(locked)
		else:
			unlock_label.text = ""


func _rebuild_title_layout() -> void:
	if has_node("TitleRoot"):
		return
	var bg: ColorRect = get_node_or_null("Background") as ColorRect
	if bg:
		bg.color = Color(0.10, 0.14, 0.16, 1.0)
	var glow_top: ColorRect = get_node_or_null("GlowTop") as ColorRect
	if glow_top:
		glow_top.color = Color(0.94, 0.42, 0.38, 0.10)
	var old: Control = get_node_or_null("CenterContainer") as Control
	var vbox: VBoxContainer = get_node_or_null("CenterContainer/VBoxContainer") as VBoxContainer
	if vbox == null:
		return
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 10)
	var icon_node: Control = vbox.get_node_or_null("Icon") as Control
	if icon_node:
		icon_node.visible = false
		icon_node.custom_minimum_size = Vector2(0, 0)
	var title: Label = vbox.get_node_or_null("Title") as Label
	if title:
		title.add_theme_font_size_override("font_size", 56)
		title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
		title.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.08, 0.9))
		title.add_theme_constant_override("outline_size", 8)
	var subtitle: Label = vbox.get_node_or_null("Subtitle") as Label
	if subtitle:
		subtitle.text = "活下去，成为最后一人"
		subtitle.add_theme_color_override("font_color", Color(1, 0.93, 0.8, 0.88))
	var divider: Control = vbox.get_node_or_null("Divider") as Control
	if divider:
		divider.visible = false
	var spacer: Control = vbox.get_node_or_null("Spacer1") as Control
	if spacer:
		spacer.custom_minimum_size = Vector2(0, 8)
	var start_btn: Button = vbox.get_node_or_null("StartButton") as Button
	var settings_btn: Button = vbox.get_node_or_null("SettingsButton") as Button
	var exit_btn: Button = vbox.get_node_or_null("ExitButton") as Button
	if start_btn:
		start_btn.text = "开始游戏"
		start_btn.custom_minimum_size = Vector2(280, 56)
		UiStyle.apply_button(start_btn, true)
	if settings_btn:
		settings_btn.text = "设置"
		settings_btn.custom_minimum_size = Vector2(280, 48)
		UiStyle.apply_button(settings_btn, false)
	if exit_btn:
		exit_btn.text = "退出游戏"
		exit_btn.custom_minimum_size = Vector2(280, 48)
		UiStyle.apply_button(exit_btn, false)
	if stats_label:
		stats_label.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 0.82))
		stats_label.add_theme_font_size_override("font_size", 14)
		stats_label.custom_minimum_size = Vector2(340, 0)
	if unlock_label:
		unlock_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7, 0.7))
		unlock_label.custom_minimum_size = Vector2(340, 0)
	# Title → subtitle → stats → unlock → spacer → buttons
	var order: Array = ["Title", "Subtitle", "StatsLabel", "UnlockLabel", "Spacer1", "StartButton", "SettingsButton", "ExitButton", "Tip"]
	var slot := 0
	if icon_node:
		vbox.move_child(icon_node, 0)
		slot = 1
	for n in order:
		var child: Node = vbox.get_node_or_null(n)
		if child:
			vbox.move_child(child, slot)
			slot += 1
	var root := Control.new()
	root.name = "TitleRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	move_child(root, 3)
	var hero := TextureRect.new()
	hero.name = "Hero"
	hero.texture = UiStyle.tex("res://assets/ui/home_hero.png")
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	hero.anchor_right = 0.56
	hero.offset_left = 0
	hero.offset_right = 0
	hero.offset_top = 0
	hero.offset_bottom = 0
	root.add_child(hero)
	var shade := ColorRect.new()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.color = Color(0.05, 0.04, 0.06, 0.18)
	shade.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	shade.anchor_left = 0.48
	root.add_child(shade)
	if old:
		old.anchor_left = 0.46
		old.anchor_right = 1.0
		old.anchor_top = 0.0
		old.anchor_bottom = 1.0
		old.offset_left = 0
		old.offset_right = -16
		old.offset_top = 0
		old.offset_bottom = 0
		old.visible = true
	var tip: Label = vbox.get_node_or_null("Tip") as Label
	if tip:
		tip.text = "触摸左下移动 · 自动攻击 · 撑过 5 分钟"
		tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))


func _on_viewport_resized() -> void:
	# 针对 20:9 等超宽屏，限制中央容器最大宽度并处理安全区域
	var vp: Vector2 = get_viewport_rect().size
	var title: Label = get_node_or_null("CenterContainer/VBoxContainer/Title") as Label
	if title:
		if vp.x / maxf(vp.y, 1.0) > 2.0:
			title.add_theme_font_size_override("font_size", 46)
		else:
			title.add_theme_font_size_override("font_size", 56)
	var hero: TextureRect = get_node_or_null("TitleRoot/Hero") as TextureRect
	if hero:
		hero.anchor_right = 0.62 if vp.x / maxf(vp.y, 1.0) > 1.95 else 0.56


func _build_settings_layer() -> void:
	if has_node("SettingsLayer"):
		settings_layer = get_node("SettingsLayer") as Control
		return
	settings_layer = Control.new()
	settings_layer.name = "SettingsLayer"
	settings_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_layer.visible = false
	settings_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(settings_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	settings_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.clip_contents = true
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(UiStyle.CREAM.r, UiStyle.CREAM.g, UiStyle.CREAM.b, 0.98)
	panel_sb.set_corner_radius_all(18)
	panel_sb.set_border_width_all(5)
	panel_sb.border_color = UiStyle.WOOD
	panel_sb.content_margin_left = 22
	panel_sb.content_margin_right = 22
	panel_sb.content_margin_top = 18
	panel_sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiStyle.INK)
	vbox.add_child(title)
	vbox.add_child(_make_separator())
	volume_slider = _make_settings_slider()
	volume_slider.value = Settings.master_volume
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_label = Label.new()
	vbox.add_child(_make_slider_row("主音量", volume_slider, volume_label, int(Settings.master_volume * 100)))
	music_slider = _make_settings_slider()
	music_slider.value = Settings.music_volume
	music_slider.value_changed.connect(_on_music_changed)
	music_label = Label.new()
	vbox.add_child(_make_slider_row("音乐", music_slider, music_label, int(Settings.music_volume * 100)))
	sfx_slider = _make_settings_slider()
	sfx_slider.value = Settings.sfx_volume
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sfx_label = Label.new()
	vbox.add_child(_make_slider_row("音效", sfx_slider, sfx_label, int(Settings.sfx_volume * 100)))
	vbox.add_child(_make_separator())
	shake_check = CheckBox.new()
	vbox.add_child(_make_check_row("屏幕震动", shake_check, "开启", Settings.shake_enabled, _on_shake_toggled))
	flash_check = CheckBox.new()
	vbox.add_child(_make_check_row("强闪烁", flash_check, "开启", Settings.flash_enabled, _on_flash_toggled))
	fps_check = CheckBox.new()
	vbox.add_child(_make_check_row("显示信息", fps_check, "显示 FPS", Settings.fps_visible, _on_fps_toggled))
	vbox.add_child(_make_separator())
	var unlock_title := Label.new()
	unlock_title.text = "进度"
	unlock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_title.add_theme_font_size_override("font_size", 14)
	unlock_title.add_theme_color_override("font_color", UiStyle.WOOD)
	vbox.add_child(unlock_title)
	var unlock_info := Label.new()
	unlock_info.name = "UnlockInfo"
	unlock_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unlock_info.custom_minimum_size = Vector2(0, 36)
	unlock_info.add_theme_font_size_override("font_size", 12)
	unlock_info.add_theme_color_override("font_color", Color(UiStyle.INK.r, UiStyle.INK.g, UiStyle.INK.b, 0.8))
	vbox.add_child(unlock_info)
	clear_save_button = Button.new()
	clear_save_button.name = "ClearSaveButton"
	clear_save_button.text = "清除存档"
	clear_save_button.custom_minimum_size = Vector2(180, 44)
	clear_save_button.focus_mode = Control.FOCUS_ALL
	clear_save_button.add_theme_font_size_override("font_size", 14)
	clear_save_button.add_theme_color_override("font_color", Color(0.72, 0.22, 0.18))
	clear_save_button.add_theme_color_override("font_hover_color", Color(0.85, 0.2, 0.16))
	var sb_clear := StyleBoxFlat.new()
	sb_clear.bg_color = Color(0.95, 0.35, 0.35, 0.16)
	sb_clear.set_corner_radius_all(10)
	sb_clear.set_border_width_all(2)
	sb_clear.border_color = Color(0.85, 0.32, 0.28, 0.7)
	clear_save_button.add_theme_stylebox_override("normal", sb_clear)
	var sb_clear_h: StyleBoxFlat = sb_clear.duplicate()
	sb_clear_h.bg_color = Color(0.95, 0.35, 0.35, 0.28)
	clear_save_button.add_theme_stylebox_override("hover", sb_clear_h)
	clear_save_button.add_theme_stylebox_override("focus", sb_clear_h)
	clear_save_button.add_theme_stylebox_override("pressed", sb_clear)
	clear_save_button.pressed.connect(_show_clear_confirmation)
	var cc := CenterContainer.new()
	cc.add_child(clear_save_button)
	vbox.add_child(cc)
	call_deferred("_refresh_unlock_info")
	vbox.add_child(_make_separator())
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	var back_btn := Button.new()
	back_btn.text = "返回"
	back_btn.custom_minimum_size = Vector2(150, 44)
	back_btn.focus_mode = Control.FOCUS_ALL
	UiStyle.apply_button(back_btn, true)
	back_btn.pressed.connect(_on_settings_back)
	btn_row.add_child(back_btn)
	var reset_btn := Button.new()
	reset_btn.text = "恢复默认"
	reset_btn.custom_minimum_size = Vector2(130, 44)
	reset_btn.focus_mode = Control.FOCUS_ALL
	reset_btn.add_theme_font_size_override("font_size", 14)
	reset_btn.add_theme_color_override("font_color", UiStyle.INK)
	reset_btn.add_theme_color_override("font_hover_color", UiStyle.WOOD)
	var sb_reset := StyleBoxFlat.new()
	sb_reset.bg_color = Color(1, 1, 1, 0.35)
	sb_reset.set_corner_radius_all(22)
	sb_reset.set_border_width_all(2)
	sb_reset.border_color = UiStyle.WOOD
	sb_reset.content_margin_left = 14
	sb_reset.content_margin_right = 14
	reset_btn.add_theme_stylebox_override("normal", sb_reset)
	var sb_reset_h: StyleBoxFlat = sb_reset.duplicate()
	sb_reset_h.bg_color = Color(1, 1, 1, 0.55)
	reset_btn.add_theme_stylebox_override("hover", sb_reset_h)
	reset_btn.add_theme_stylebox_override("pressed", sb_reset)
	reset_btn.add_theme_stylebox_override("focus", sb_reset_h)
	reset_btn.pressed.connect(_on_reset_pressed)
	btn_row.add_child(reset_btn)
	vbox.add_child(btn_row)
	# 触摸/返回：点击 dim 关闭
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_settings_back()
	)
	_build_clear_confirmation_layer()


func _build_clear_confirmation_layer() -> void:
	if clear_confirm_layer != null:
		return
	clear_confirm_layer = Control.new()
	clear_confirm_layer.name = "ClearSaveConfirmation"
	clear_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clear_confirm_layer.visible = false
	clear_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_layer.add_child(clear_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clear_confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	clear_confirm_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.flat_panel())
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "确认清除存档？"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.72, 0.22, 0.18))
	vbox.add_child(title)
	var message := Label.new()
	message.text = "最佳记录、累计统计和已解锁内容都会被删除。\n此操作无法撤销。"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(380, 54)
	message.add_theme_font_size_override("font_size", 15)
	message.add_theme_color_override("font_color", UiStyle.INK)
	vbox.add_child(message)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)
	clear_confirm_cancel_button = Button.new()
	clear_confirm_cancel_button.name = "CancelButton"
	clear_confirm_cancel_button.text = "取消"
	clear_confirm_cancel_button.custom_minimum_size = Vector2(150, 50)
	clear_confirm_cancel_button.focus_mode = Control.FOCUS_ALL
	clear_confirm_cancel_button.add_theme_font_size_override("font_size", 16)
	clear_confirm_cancel_button.add_theme_color_override("font_color", UiStyle.INK)
	clear_confirm_cancel_button.add_theme_color_override("font_hover_color", UiStyle.WOOD)
	var cancel_normal: StyleBoxFlat = UiStyle.flat_button(false)
	var cancel_hover: StyleBoxFlat = cancel_normal.duplicate()
	cancel_hover.bg_color = Color.WHITE
	clear_confirm_cancel_button.add_theme_stylebox_override("normal", cancel_normal)
	clear_confirm_cancel_button.add_theme_stylebox_override("hover", cancel_hover)
	clear_confirm_cancel_button.add_theme_stylebox_override("pressed", cancel_normal)
	clear_confirm_cancel_button.add_theme_stylebox_override("focus", cancel_hover)
	clear_confirm_cancel_button.pressed.connect(_hide_clear_confirmation)
	btn_row.add_child(clear_confirm_cancel_button)
	clear_confirm_accept_button = Button.new()
	clear_confirm_accept_button.name = "ConfirmButton"
	clear_confirm_accept_button.text = "确认清除"
	clear_confirm_accept_button.custom_minimum_size = Vector2(150, 50)
	clear_confirm_accept_button.focus_mode = Control.FOCUS_ALL
	UiStyle.apply_button(clear_confirm_accept_button, true)
	clear_confirm_accept_button.pressed.connect(_on_clear_save_confirmed)
	btn_row.add_child(clear_confirm_accept_button)
	# CenterContainer 覆盖整个视口并以 PASS 传递未处理输入，因此在模态
	# 根节点接收遮罩点击；绑定背后的 sibling ColorRect 无法稳定收到事件。
	clear_confirm_layer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_hide_clear_confirmation()
	)


func _show_clear_confirmation() -> void:
	if clear_confirm_layer == null:
		_build_clear_confirmation_layer()
	clear_confirm_layer.visible = true
	clear_confirm_cancel_button.call_deferred("grab_focus")


func _hide_clear_confirmation() -> void:
	if clear_confirm_layer:
		clear_confirm_layer.visible = false
	if clear_save_button and clear_save_button.is_visible_in_tree():
		clear_save_button.call_deferred("grab_focus")


func _on_clear_save_confirmed() -> void:
	if not SaveData.clear():
		push_error("[Home] 清除存档失败")
		return
	_hide_clear_confirmation()
	_refresh_stats_display()
	_refresh_unlock_info()


func _make_separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(UiStyle.WOOD.r, UiStyle.WOOD.g, UiStyle.WOOD.b, 0.28)
	return sep


func _make_settings_slider() -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_ALL
	sl.custom_minimum_size = Vector2(0, 22)
	return sl


func _make_slider_row(title_text: String, slider: HSlider, value_label: Label, pct: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = title_text
	title.custom_minimum_size = Vector2(72, 0)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiStyle.INK)
	row.add_child(title)
	row.add_child(slider)
	value_label.text = "%d%%" % pct
	value_label.custom_minimum_size = Vector2(42, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", UiStyle.WOOD)
	row.add_child(value_label)
	return row


func _make_check_row(title_text: String, box: CheckBox, box_text: String, pressed: bool, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = title_text
	title.custom_minimum_size = Vector2(72, 0)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiStyle.INK)
	row.add_child(title)
	box.text = box_text
	box.button_pressed = pressed
	box.focus_mode = Control.FOCUS_ALL
	box.add_theme_color_override("font_color", UiStyle.INK)
	box.add_theme_color_override("font_hover_color", UiStyle.WOOD)
	box.add_theme_color_override("font_pressed_color", UiStyle.INK)
	box.toggled.connect(cb)
	row.add_child(box)
	return row


func _on_volume_changed(v: float) -> void:
	Settings.set_master_volume(v)
	volume_label.text = "%d%%" % int(v * 100)


func _on_music_changed(v: float) -> void:
	Settings.set_music_volume(v)
	music_label.text = "%d%%" % int(v * 100)


func _on_sfx_changed(v: float) -> void:
	Settings.set_sfx_volume(v)
	sfx_label.text = "%d%%" % int(v * 100)


func _on_shake_toggled(v: bool) -> void:
	Settings.set_shake_enabled(v)


func _on_flash_toggled(v: bool) -> void:
	Settings.set_flash_enabled(v)


func _on_fps_toggled(v: bool) -> void:
	Settings.set_fps_visible(v)


func _on_reset_pressed() -> void:
	Settings.reset_to_default()
	volume_slider.value = Settings.master_volume
	volume_label.text = "%d%%" % int(Settings.master_volume * 100)
	music_slider.value = Settings.music_volume
	music_label.text = "%d%%" % int(Settings.music_volume * 100)
	sfx_slider.value = Settings.sfx_volume
	sfx_label.text = "%d%%" % int(Settings.sfx_volume * 100)
	shake_check.button_pressed = Settings.shake_enabled
	flash_check.button_pressed = Settings.flash_enabled
	fps_check.button_pressed = Settings.fps_visible


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_settings_pressed() -> void:
	_show_settings()


func _on_settings_back() -> void:
	if clear_confirm_layer and clear_confirm_layer.visible:
		_hide_clear_confirmation()
	else:
		_hide_settings()


func _show_settings() -> void:
	if settings_layer == null:
		_build_settings_layer()
	if clear_confirm_layer:
		clear_confirm_layer.visible = false
	settings_layer.visible = true
	_refresh_unlock_info()
	# 同步最新值
	volume_slider.value = Settings.master_volume
	music_slider.value = Settings.music_volume
	sfx_slider.value = Settings.sfx_volume
	shake_check.button_pressed = Settings.shake_enabled
	flash_check.button_pressed = Settings.flash_enabled
	fps_check.button_pressed = Settings.fps_visible
	# 焦点
	if volume_slider:
		volume_slider.grab_focus()


func _hide_settings() -> void:
	if clear_confirm_layer:
		clear_confirm_layer.visible = false
	if settings_layer:
		settings_layer.visible = false
	var start_btn: Button = get_node_or_null("CenterContainer/VBoxContainer/StartButton") as Button
	if start_btn == null:
		start_btn = get_node_or_null("CenterContainer/VBoxContainer/StartButton") as Button
	if start_btn:
		start_btn.grab_focus()


func _center(n: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(n)
	return cc


func _unhandled_input(event: InputEvent) -> void:
	if clear_confirm_layer and clear_confirm_layer.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_hide_clear_confirmation()
			get_viewport().set_input_as_handled()
	elif settings_layer and settings_layer.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_hide_settings()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		# 回车/手柄 A 在主页默认开始（若设置未打开）
		if not settings_layer.visible:
			var focus: Control = get_viewport().gui_get_focus_owner()
			if focus == null:
				var start_btn: Button = get_node_or_null("CenterContainer/VBoxContainer/StartButton") as Button
				if start_btn:
					start_btn.grab_focus()
