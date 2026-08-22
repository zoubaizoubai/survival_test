extends Control

const Settings := preload("res://scripts/settings.gd")

var settings_layer: Control
var volume_slider: HSlider
var volume_label: Label
var shake_check: CheckBox
var fps_check: CheckBox


func _ready() -> void:
	Settings.ensure_loaded()
	_build_settings_layer()
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
	# 响应式：监听视口变化
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	# 应用已保存设置
	Settings.ensure_loaded()


func _on_viewport_resized() -> void:
	# 针对 20:9 等超宽屏，限制中央容器最大宽度并处理安全区域
	var vp: Vector2 = get_viewport_rect().size
	var center: CenterContainer = get_node_or_null("CenterContainer") as CenterContainer
	if center:
		# 在超宽屏下保持内容居中，避免拉伸
		center.custom_minimum_size = Vector2.ZERO
	# 可在此根据 vp 调整字体或间距（示例：超宽时略缩小标题）
	var title: Label = get_node_or_null("CenterContainer/VBoxContainer/Title") as Label
	if title:
		if vp.x / maxf(vp.y, 1.0) > 2.0:
			title.add_theme_font_size_override("font_size", 52)
		else:
			title.add_theme_font_size_override("font_size", 64)


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
	panel.custom_minimum_size = Vector2(420, 360)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.095, 0.13, 0.98)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	# 标题
	var title := Label.new()
	title.text = "设  置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
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
	vol_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
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
	volume_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	vol_row.add_child(volume_label)
	vbox.add_child(vol_row)
	# 震动行
	var shake_row := HBoxContainer.new()
	shake_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var shake_label := Label.new()
	shake_label.text = "屏幕震动"
	shake_label.custom_minimum_size = Vector2(80, 0)
	shake_label.add_theme_font_size_override("font_size", 14)
	shake_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
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
	# FPS 行（显示选项）
	var fps_row := HBoxContainer.new()
	fps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var fps_label := Label.new()
	fps_label.text = "显示信息"
	fps_label.custom_minimum_size = Vector2(80, 0)
	fps_label.add_theme_font_size_override("font_size", 14)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
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
	# 试听
	var sfx_node: Node = get_node_or_null("/root/Home/SettingsLayer") # placeholder
	# 轻量反馈：无需额外音效


func _on_shake_toggled(v: bool) -> void:
	Settings.set_shake_enabled(v)


func _on_fps_toggled(v: bool) -> void:
	Settings.set_fps_visible(v)


func _on_reset_pressed() -> void:
	Settings.reset_to_default()
	volume_slider.value = Settings.master_volume
	volume_label.text = "%d%%" % int(Settings.master_volume * 100)
	shake_check.button_pressed = Settings.shake_enabled
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
	# 同步最新值
	volume_slider.value = Settings.master_volume
	shake_check.button_pressed = Settings.shake_enabled
	fps_check.button_pressed = Settings.fps_visible
	# 焦点
	if volume_slider:
		volume_slider.grab_focus()


func _hide_settings() -> void:
	if settings_layer:
		settings_layer.visible = false
	var start_btn: Button = get_node_or_null("CenterContainer/VBoxContainer/StartButton") as Button
	if start_btn:
		start_btn.grab_focus()


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
