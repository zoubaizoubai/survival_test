extends Control

var game: Node2D
var upgrade_layer: Control
var pause_layer: Control
var end_layer: Control
var cards_box: HBoxContainer
var end_title: Label
var end_stats: Label
var endless_btn: Button
var _cards_scroll: ScrollContainer
var _focused_card_idx: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var uv := VBoxContainer.new()
	uv.name = "UpgradeV"
	uv.alignment = BoxContainer.ALIGNMENT_CENTER
	uv.add_theme_constant_override("separation", 22)
	uv.add_child(_make_label("升 级 ！选择一项强化", 26, Color(1.0, 0.9, 0.5)))
	# 包裹卡片的滚动容器以适配超宽/窄高
	_cards_scroll = ScrollContainer.new()
	_cards_scroll.name = "CardsScroll"
	_cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cards_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	cards_box = HBoxContainer.new()
	cards_box.name = "CardsBox"
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_box.add_theme_constant_override("separation", 20)
	_cards_scroll.add_child(cards_box)
	uv.add_child(_cards_scroll)
	upgrade_layer = _make_dim_layer(uv)
	upgrade_layer.name = "UpgradeLayer"

	var pv := VBoxContainer.new()
	pv.name = "PauseV"
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 14)
	pv.add_child(_make_label("已暂停", 34, Color.WHITE))
	pv.add_child(_spacer(10))
	var resume_btn := _make_button("继续游戏", true)
	resume_btn.name = "ResumeBtn"
	resume_btn.pressed.connect(toggle_pause)
	pv.add_child(_center(resume_btn))
	var restart_btn := _make_button("重新开始")
	restart_btn.name = "RestartBtn"
	restart_btn.pressed.connect(func(): game.restart())
	pv.add_child(_center(restart_btn))
	var home_btn := _make_button("回到主页")
	home_btn.name = "HomeBtn"
	home_btn.pressed.connect(func(): game.to_home())
	pv.add_child(_center(home_btn))
	# 设置按钮（从暂停进入设置，需返回暂停）
	var settings_btn := _make_button("设置")
	settings_btn.name = "SettingsBtn"
	settings_btn.pressed.connect(func():
		# 设置请在主页调整
		if game.menus.pause_layer.visible:
			print("设置请在主页调整")
	)
	pv.add_child(_center(settings_btn))
	pause_layer = _make_dim_layer(pv)
	pause_layer.name = "PauseLayer"

	var ev := VBoxContainer.new()
	ev.name = "EndV"
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_theme_constant_override("separation", 12)
	end_title = _make_label("", 44, Color.WHITE)
	end_title.name = "EndTitle"
	ev.add_child(end_title)
	end_stats = _make_label("", 17, Color(1, 1, 1, 0.85))
	end_stats.name = "EndStats"
	ev.add_child(end_stats)
	ev.add_child(_spacer(16))
	endless_btn = _make_button("继续无尽模式", true)
	endless_btn.name = "EndlessBtn"
	endless_btn.pressed.connect(func(): game.continue_endless())
	ev.add_child(_center(endless_btn))
	var again_btn := _make_button("再来一局")
	again_btn.name = "AgainBtn"
	again_btn.pressed.connect(func(): game.restart())
	ev.add_child(_center(again_btn))
	var ehome_btn := _make_button("回到主页")
	ehome_btn.name = "EHomeBtn"
	ehome_btn.pressed.connect(func(): game.to_home())
	ev.add_child(_center(ehome_btn))
	end_layer = _make_dim_layer(ev)
	end_layer.name = "EndLayer"

	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _update_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var is_wide: bool = vp.x / maxf(vp.y, 1.0) > 1.95
	var is_short: bool = vp.y < 650
	# 调整升级卡片尺寸与间距以适配不同比例
	if cards_box:
		cards_box.add_theme_constant_override("separation", 12 if is_short or is_wide else 20)
		for child in cards_box.get_children():
			if child is PanelContainer:
				if is_short:
					child.custom_minimum_size = Vector2(200, 170)
				elif is_wide:
					child.custom_minimum_size = Vector2(220, 180)
				else:
					child.custom_minimum_size = Vector2(250, 210)
	# 调整字体在窄高屏下的大小
	if end_title:
		end_title.add_theme_font_size_override("font_size", 36 if is_short else 44)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		toggle_pause()
	# 手柄/键盘在升级界面导航
	if upgrade_layer.visible:
		if Input.is_action_just_pressed("ui_cancel"):
			# 禁止通过取消关闭升级，必须选择
			get_viewport().set_input_as_handled()
		elif Input.is_action_just_pressed("ui_left"):
			_focus_card((_focused_card_idx - 1) % max(1, cards_box.get_child_count()))
		elif Input.is_action_just_pressed("ui_right"):
			_focus_card((_focused_card_idx + 1) % max(1, cards_box.get_child_count()))
		elif Input.is_action_just_pressed("ui_accept"):
			var idx: int = _focused_card_idx
			if idx >= 0 and idx < cards_box.get_child_count():
				var card_node: PanelContainer = cards_box.get_child(idx) as PanelContainer
				if card_node and card_node.has_meta("card_data"):
					var c: Dictionary = card_node.get_meta("card_data") as Dictionary
					game._on_card_chosen(c)


func _focus_card(idx: int) -> void:
	if cards_box == null or cards_box.get_child_count() == 0:
		return
	_focused_card_idx = clampi(idx, 0, cards_box.get_child_count() - 1)
	for i in cards_box.get_child_count():
		var child: Control = cards_box.get_child(i) as Control
		if child:
			child.modulate = Color(1.15, 1.15, 1.15) if i == _focused_card_idx else Color.WHITE
			if i == _focused_card_idx:
				child.grab_focus()


func _make_dim_layer(content: Control) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(center)
	center.add_child(content)
	return layer


func _make_label(txt: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _center(n: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(n)
	return cc


func _make_button(text_value: String, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(230, 48)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.42, 0.3) if accent else Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if not accent:
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.2)
	b.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = sb.bg_color.lightened(0.12) if accent else Color(1, 1, 1, 0.15)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = sb.bg_color.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func show_upgrades(cards: Array) -> void:
	if pause_layer.visible:
		pause_layer.visible = false
	if end_layer.visible:
		end_layer.visible = false
	for child in cards_box.get_children():
		child.queue_free()
	for i in cards.size():
		var card: PanelContainer = _make_card(cards[i])
		card.set_meta("card_data", cards[i])
		card.focus_mode = Control.FOCUS_ALL
		# 触摸与鼠标
		card.mouse_entered.connect(func(): card.modulate = Color(1.15, 1.15, 1.15))
		card.mouse_exited.connect(func(): 
			if cards_box.get_children().find(card) != _focused_card_idx:
				card.modulate = Color.WHITE
		)
		cards_box.add_child(card)
	upgrade_layer.visible = true
	_update_layout()
	_focused_card_idx = 0
	# 延迟一帧后聚焦首卡
	await get_tree().process_frame
	_focus_card(0)


func hide_upgrades() -> void:
	upgrade_layer.visible = false


func toggle_pause() -> void:
	if game.ended or upgrade_layer.visible or end_layer.visible:
		return
	if pause_layer.visible:
		pause_layer.visible = false
		get_tree().paused = false
	else:
		pause_layer.visible = true
		get_tree().paused = true
		# 焦点置于继续按钮，支持键盘/手柄
		await get_tree().process_frame
		var pv: VBoxContainer = pause_layer.get_node_or_null("CenterContainer/PauseV") as VBoxContainer
		if pv:
			var btn: Button = pv.get_node_or_null("CenterContainer/ResumeBtn") as Button
			# 实际结构为 CenterContainer 套 VBox，再 Center 套 Button，需遍历
			for child in pv.get_children():
				if child is CenterContainer:
					var b: Button = child.get_child(0) as Button
					if b and b.text == "继续游戏":
						b.grab_focus()
						break


func show_end(win: bool, time_sec: float, kills: int, level: int) -> void:
	if upgrade_layer.visible:
		upgrade_layer.visible = false
	if pause_layer.visible:
		pause_layer.visible = false
	if win:
		end_title.text = "胜 利 ！"
		end_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		end_stats.text = "你坚持了 %d:%02d · 击杀 %d · 等级 %d" % [floori(time_sec / 60.0), int(time_sec) % 60, kills, level]
		endless_btn.visible = true
	else:
		end_title.text = "你倒下了…"
		end_title.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		end_stats.text = "幸存 %d:%02d · 击杀 %d · 等级 %d" % [floori(time_sec / 60.0), int(time_sec) % 60, kills, level]
		endless_btn.visible = false
	end_layer.visible = true
	_update_layout()
	# 焦点至首个可操作按钮
	await get_tree().process_frame
	if win and endless_btn.visible:
		endless_btn.grab_focus()
	else:
		var ev: VBoxContainer = end_layer.get_node_or_null("CenterContainer/EndV") as VBoxContainer
		if ev:
			for child in ev.get_children():
				if child is CenterContainer:
					var b: Button = child.get_child(0) as Button
					if b:
						b.grab_focus()
						break


func hide_end() -> void:
	end_layer.visible = false


func _card_info(c: Dictionary) -> Dictionary:
	match c["kind"]:
		"weapon_new":
			var w: Dictionary = game.WEAPONS[c["id"]]
			return {"title": w["name"], "tag": "新武器", "desc": w["desc"], "color": w["color"]}
		"weapon_up":
			var w2: Dictionary = game.WEAPONS[c["id"]]
			var lv: int = game.player.weapons[c["id"]]["lv"]
			return {"title": w2["name"], "tag": "升级 Lv%d → Lv%d" % [lv, lv + 1], "desc": w2["desc"], "color": w2["color"]}
		"passive":
			var p: Dictionary = game.PASSIVES[c["id"]]
			var cur: int = game.player.passives.get(c["id"], 0)
			return {"title": p["name"], "tag": "祝福 %d/%d" % [cur + 1, p["max"]], "desc": p["desc"], "color": p["color"]}
		_:
			return {"title": "急救包", "tag": "回复", "desc": "立即回复 40 点生命值", "color": Color(0.4, 0.95, 0.6)}


func _make_card(card: Dictionary) -> PanelContainer:
	var info := _card_info(card)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 210)
	panel.focus_mode = Control.FOCUS_ALL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.095, 0.13, 0.97)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = info["color"]
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var tag := Label.new()
	tag.text = info["tag"]
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", info["color"])
	v.add_child(tag)
	var title := Label.new()
	title.text = info["title"]
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(title)
	v.add_child(_spacer(6))
	var desc := Label.new()
	desc.text = info["desc"]
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	var hint := Label.new()
	hint.text = "点击或按 确认 选择"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	v.add_child(hint)
	# 焦点样式
	panel.focus_entered.connect(func(): panel.modulate = Color(1.15, 1.15, 1.15))
	panel.focus_exited.connect(func(): panel.modulate = Color.WHITE)
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game._on_card_chosen(card)
		elif ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ENTER or ev.keycode == KEY_SPACE):
			game._on_card_chosen(card)
		elif ev is InputEventJoypadButton and ev.pressed and (ev.button_index == 0 or ev.button_index == 1): # A/B
			game._on_card_chosen(card)
	)
	return panel
