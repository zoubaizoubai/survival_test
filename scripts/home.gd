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
	var lines: Array = []
	for uid in prog.keys():
		var u: Dictionary = prog[uid] as Dictionary
		var unlocked: bool = bool(u.get("unlocked", false))
		var desc: String = str(u.get("desc", ""))
		var name: String = str(u.get("name", uid))
		lines.append("%s: %s [%s]" % [name, desc, "已解锁" if unlocked else "未解锁"])
	info.text = "\n".join(lines)


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
	panel.custom_minimum_size = Vector2(440, 500)
	panel.add_theme_stylebox_override("panel", UiStyle.texture_box("res://assets/ui/panel.png", 48.0, 22.0))
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	# 标题
	var title := Label.new()
	title.text = "设  置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiStyle.INK)
	vbox.add_child(title)
	vbox.add_child(_make_separator())
	# 音量行
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 12)
	vol_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var vol_title := Label.new()
	vol_title.text = "主音量"
	vol_title.custom_minimum_size = Vector2(80, 0)
	vol_title.add_theme_font_size_override("font_size", 14)
	vol_title.add_theme_color_override("font_color", UiStyle.INK)
	vol_row.add_child(vol_title)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = Settings.master_volume
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.focus_mode = Control.FOCUS_ALL
	volume_slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(volume_slider)
	volume_label = Label.new()
	volume_label.text = "%d%%" % int(Settings.master_volume * 100)
	volume_label.custom_minimum_size = Vector2(44, 0)
	volume_label.add_theme_font_size_override("font_size", 14)
	volume_label.add_theme_color_override("font_color", UiStyle.WOOD)
	vol_row.add_child(volume_label)
	vbox.add_child(vol_row)
	# 音乐行
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 12)
	music_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var music_title := Label.new()
	music_title.text = "音乐"
	music_title.custom_minimum_size = Vector2(80, 0)
	music_title.add_theme_font_size_override("font_size", 14)
	music_title.add_theme_color_override("font_color", UiStyle.INK)
	music_row.add_child(music_title)
	music_slider = HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	music_slider.value = Settings.music_volume
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.focus_mode = Control.FOCUS_ALL
	music_slider.value_changed.connect(_on_music_changed)
	music_row.add_child(music_slider)
	music_label = Label.new()
	music_label.text = "%d%%" % int(Settings.music_volume * 100)
	music_label.custom_minimum_size = Vector2(44, 0)
	music_label.add_theme_font_size_override("font_size", 14)
	music_label.add_theme_color_override("font_color", UiStyle.WOOD)
	music_row.add_child(music_label)
	vbox.add_child(music_row)
	# 音效行
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	sfx_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sfx_title := Label.new()
	sfx_title.text = "音效"
	sfx_title.custom_minimum_size = Vector2(80, 0)
	sfx_title.add_theme_font_size_override("font_size", 14)
	sfx_title.add_theme_color_override("font_color", UiStyle.INK)
	sfx_row.add_child(sfx_title)
	sfx_slider = HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = Settings.sfx_volume
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.focus_mode = Control.FOCUS_ALL
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sfx_row.add_child(sfx_slider)
	sfx_label = Label.new()
	sfx_label.text = "%d%%" % int(Settings.sfx_volume * 100)
	sfx_label.custom_minimum_size = Vector2(44, 0)
	sfx_label.add_theme_font_size_override("font_size", 14)
	sfx_label.add_theme_color_override("font_color", UiStyle.WOOD)
	sfx_row.add_child(sfx_label)
	vbox.add_child(sfx_row)
	# 震动行
	var shake_row := HBoxContainer.new()
	shake_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var shake_label := Label.new()
	shake_label.text = "屏幕震动"
	shake_label.custom_minimum_size = Vector2(80, 0)
	shake_label.add_theme_font_size_override("font_size", 14)
	shake_label.add_theme_color_override("font_color", UiStyle.INK)
	shake_row.add_child(shake_label)
	shake_check = CheckBox.new()
	shake_check.text = "开启"
	shake_check.button_pressed = Settings.shake_enabled
	shake_check.focus_mode = Control.FOCUS_ALL
	shake_check.toggled.connect(_on_shake_toggled)
	shake_row.add_child(shake_check)
	shake_row.add_child(Control.new()) # spacer
	var shake_spacer := Control.new()
	shake_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shake_row.add_child(shake_spacer)
	vbox.add_child(shake_row)
	# 强闪烁行
	var flash_row := HBoxContainer.new()
	flash_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var flash_label := Label.new()
	flash_label.text = "强闪烁"
	flash_label.custom_minimum_size = Vector2(80, 0)
	flash_label.add_theme_font_size_override("font_size", 14)
	flash_label.add_theme_color_override("font_color", UiStyle.INK)
	flash_row.add_child(flash_label)
	flash_check = CheckBox.new()
	flash_check.text = "开启"
	flash_check.button_pressed = Settings.flash_enabled
	flash_check.focus_mode = Control.FOCUS_ALL
	flash_check.toggled.connect(_on_flash_toggled)
	flash_row.add_child(flash_check)
	var flash_spacer := Control.new()
	flash_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flash_row.add_child(flash_spacer)
	vbox.add_child(flash_row)
	# FPS 行（显示选项）
	var fps_row := HBoxContainer.new()
	fps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var fps_label := Label.new()
	fps_label.text = "显示信息"
	fps_label.custom_minimum_size = Vector2(80, 0)
	fps_label.add_theme_font_size_override("font_size", 14)
	fps_label.add_theme_color_override("font_color", UiStyle.INK)
	fps_row.add_child(fps_label)
	fps_check = CheckBox.new()
	fps_check.text = "显示 FPS"
	fps_check.button_pressed = Settings.fps_visible
	fps_check.focus_mode = Control.FOCUS_ALL
	fps_check.toggled.connect(_on_fps_toggled)
	fps_row.add_child(fps_check)
	var fps_spacer := Control.new()
	fps_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_spacer)
	vbox.add_child(fps_row)
	vbox.add_child(_make_separator())
	# 按钮行
	# 解锁进度与清除存档
	vbox.add_child(_make_separator())
	var unlock_title := Label.new()
	unlock_title.text = "进 度"
	unlock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_title.add_theme_font_size_override("font_size", 14)
	unlock_title.add_theme_color_override("font_color", UiStyle.WOOD)
	vbox.add_child(unlock_title)
	var unlock_info := Label.new()
	unlock_info.name = "UnlockInfo"
	unlock_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unlock_info.add_theme_font_size_override("font_size", 12)
	unlock_info.add_theme_color_override("font_color", Color(UiStyle.INK.r, UiStyle.INK.g, UiStyle.INK.b, 0.75))
	vbox.add_child(unlock_info)
	var clear_btn := Button.new()
	clear_btn.text = "清除存档"
	clear_btn.custom_minimum_size = Vector2(140, 38)
	clear_btn.focus_mode = Control.FOCUS_ALL
	clear_btn.add_theme_font_size_override("font_size", 12)
	var sb_clear := StyleBoxFlat.new()
	sb_clear.bg_color = Color(0.95, 0.35, 0.35, 0.12)
	sb_clear.set_corner_radius_all(8)
	sb_clear.set_border_width_all(1)
	sb_clear.border_color = Color(0.95, 0.35, 0.35, 0.35)
	clear_btn.add_theme_stylebox_override("normal", sb_clear)
	clear_btn.add_theme_stylebox_override("hover", sb_clear)
	clear_btn.add_theme_stylebox_override("pressed", sb_clear)
	clear_btn.pressed.connect(func():
		SaveData.clear()
		_refresh_stats_display()
		_refresh_unlock_info()
	)
	var cc := CenterContainer.new()
	cc.add_child(clear_btn)
	vbox.add_child(cc)
	# 初始化解锁信息
	call_deferred("_refresh_unlock_info")
	vbox.add_child(_make_separator())
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	var back_btn := Button.new()
	back_btn.text = "返回"
	back_btn.custom_minimum_size = Vector2(160, 44)
	back_btn.focus_mode = Control.FOCUS_ALL
	back_btn.add_theme_font_size_override("font_size", 15)
	var sb_back := StyleBoxFlat.new()
	sb_back.bg_color = Color(0.93, 0.42, 0.3)
	sb_back.set_corner_radius_all(10)
	sb_back.content_margin_left = 16
	sb_back.content_margin_right = 16
	sb_back.content_margin_top = 8
	sb_back.content_margin_bottom = 8
	back_btn.add_theme_stylebox_override("normal", sb_back)
	back_btn.add_theme_stylebox_override("hover", sb_back)
	back_btn.add_theme_stylebox_override("pressed", sb_back)
	back_btn.add_theme_stylebox_override("focus", sb_back)
	back_btn.pressed.connect(_on_settings_back)
	btn_row.add_child(back_btn)
	var reset_btn := Button.new()
	reset_btn.text = "恢复默认"
	reset_btn.custom_minimum_size = Vector2(120, 44)
	reset_btn.focus_mode = Control.FOCUS_ALL
	reset_btn.add_theme_font_size_override("font_size", 13)
	var sb_reset := StyleBoxFlat.new()
	sb_reset.bg_color = Color(1, 1, 1, 0.08)
	sb_reset.set_corner_radius_all(10)
	sb_reset.set_border_width_all(1)
	sb_reset.border_color = Color(1, 1, 1, 0.15)
	reset_btn.add_theme_stylebox_override("normal", sb_reset)
	reset_btn.add_theme_stylebox_override("hover", sb_reset)
	reset_btn.add_theme_stylebox_override("pressed", sb_reset)
	reset_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	reset_btn.pressed.connect(_on_reset_pressed)
	btn_row.add_child(reset_btn)
	vbox.add_child(btn_row)
	# 触摸/返回：点击 dim 关闭
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_settings_back()
	)


func _make_separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(1, 1, 1, 0.08)
	return sep


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
	_hide_settings()


func _show_settings() -> void:
	if settings_layer == null:
		_build_settings_layer()
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
	if settings_layer and settings_layer.visible:
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
