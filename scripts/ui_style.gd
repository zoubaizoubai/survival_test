extends Object

const WOOD := Color(0.42, 0.27, 0.14)
const CREAM := Color(0.96, 0.90, 0.78)
const CORAL := Color(0.94, 0.42, 0.38)
const INK := Color(0.18, 0.12, 0.08)
const TEAL := Color(0.12, 0.18, 0.22)


static func tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func texture_box(path: String, margin: float, content: float = -1.0) -> StyleBox:
	var t: Texture2D = tex(path)
	if t == null:
		return flat_panel()
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(margin)
	var c: float = content if content >= 0.0 else margin * 0.45
	sb.content_margin_left = c
	sb.content_margin_right = c
	sb.content_margin_top = c * 0.7
	sb.content_margin_bottom = c * 0.7
	return sb


static func flat_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CREAM.r, CREAM.g, CREAM.b, 0.97)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = WOOD
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


static func flat_button(accent: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CORAL if accent else Color(CREAM.r, CREAM.g, CREAM.b, 0.92)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.border_color = WOOD
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func apply_button(b: Button, accent: bool = false) -> void:
	b.add_theme_font_size_override("font_size", 18 if accent else 15)
	b.add_theme_color_override("font_color", Color.WHITE if accent else INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE if accent else INK)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9) if accent else WOOD)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55 if accent else 0.0))
	b.add_theme_constant_override("outline_size", 4 if accent else 0)
	var normal: StyleBox
	var hover: StyleBox
	var pressed: StyleBox
	if accent:
		normal = texture_box("res://assets/ui/btn_primary.png", 64.0, 18.0)
		hover = texture_box("res://assets/ui/btn_primary_hover.png", 70.0, 18.0)
		pressed = texture_box("res://assets/ui/btn_primary_pressed.png", 64.0, 18.0)
	else:
		normal = texture_box("res://assets/ui/btn_secondary.png", 64.0, 16.0)
		hover = texture_box("res://assets/ui/btn_secondary.png", 64.0, 16.0)
		pressed = texture_box("res://assets/ui/btn_primary_pressed.png", 64.0, 16.0)
		if hover is StyleBoxTexture:
			(hover as StyleBoxTexture).modulate_color = Color(1.08, 1.08, 1.05)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)


static func apply_label(l: Label, size: int, col: Color, outline: bool = true) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", maxi(3, int(size / 8)))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
