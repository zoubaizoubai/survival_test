extends Control

var game: Node2D
var upgrade_layer: Control
var pause_layer: Control
var end_layer: Control
var cards_box: HBoxContainer
var end_title: Label
var end_stats: Label
var endless_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var uv := VBoxContainer.new()
	uv.alignment = BoxContainer.ALIGNMENT_CENTER
	uv.add_theme_constant_override("separation", 22)
	uv.add_child(_make_label("升 级 ！选择一项强化", 26, Color(1.0, 0.9, 0.5)))
	cards_box = HBoxContainer.new()
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_box.add_theme_constant_override("separation", 20)
	uv.add_child(cards_box)
	upgrade_layer = _make_dim_layer(uv)

	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 14)
	pv.add_child(_make_label("已暂停", 34, Color.WHITE))
	pv.add_child(_spacer(10))
	var resume_btn := _make_button("继续游戏", true)
	resume_btn.pressed.connect(toggle_pause)
	pv.add_child(_center(resume_btn))
	var restart_btn := _make_button("重新开始")
	restart_btn.pressed.connect(func(): game.restart())
	pv.add_child(_center(restart_btn))
	var home_btn := _make_button("回到主页")
	home_btn.pressed.connect(func(): game.to_home())
	pv.add_child(_center(home_btn))
	pause_layer = _make_dim_layer(pv)

	var ev := VBoxContainer.new()
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_theme_constant_override("separation", 12)
	end_title = _make_label("", 44, Color.WHITE)
	ev.add_child(end_title)
	end_stats = _make_label("", 17, Color(1, 1, 1, 0.85))
	ev.add_child(end_stats)
	ev.add_child(_spacer(16))
	endless_btn = _make_button("继续无尽模式", true)
	endless_btn.pressed.connect(func(): game.continue_endless())
	ev.add_child(_center(endless_btn))
	var again_btn := _make_button("再来一局")
	again_btn.pressed.connect(func(): game.restart())
	ev.add_child(_center(again_btn))
	var ehome_btn := _make_button("回到主页")
	ehome_btn.pressed.connect(func(): game.to_home())
	ev.add_child(_center(ehome_btn))
	end_layer = _make_dim_layer(ev)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		toggle_pause()


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
	b.focus_mode = Control.FOCUS_NONE
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
	for child in cards_box.get_children():
		child.queue_free()
	for i in cards.size():
		cards_box.add_child(_make_card(cards[i]))
	upgrade_layer.visible = true


func hide_upgrades() -> void:
	upgrade_layer.visible = false


func toggle_pause() -> void:
	if game.ended or upgrade_layer.visible:
		return
	if pause_layer.visible:
		pause_layer.visible = false
		get_tree().paused = false
	else:
		pause_layer.visible = true
		get_tree().paused = true


func show_end(win: bool, time_sec: float, kills: int, level: int) -> void:
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
	panel.add_child(v)
	var tag := Label.new()
	tag.text = info["tag"]
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", info["color"])
	v.add_child(tag)
	var title := Label.new()
	title.text = info["title"]
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(title)
	v.add_child(_spacer(6))
	var desc := Label.new()
	desc.text = info["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	var hint := Label.new()
	hint.text = "点击选择"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	v.add_child(hint)
	panel.mouse_entered.connect(func(): panel.modulate = Color(1.15, 1.15, 1.15))
	panel.mouse_exited.connect(func(): panel.modulate = Color.WHITE)
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game._on_card_chosen(card))
	return panel
