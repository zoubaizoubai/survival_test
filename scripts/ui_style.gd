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
	# Capsule textures cannot 9-slice at HUD button height (margins exceed size
	# and collapse into a hollow ring). Draw filled StyleBoxFlat capsules instead.
	b.add_theme_font_size_override("font_size", 20 if accent else 16)
	if accent:
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9))
		b.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.05, 0.65))
		b.add_theme_constant_override("outline_size", 4)
	else:
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.75))
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
		b.add_theme_constant_override("outline_size", 3)
	var normal := _capsule(accent, 0)
	var hover := _capsule(accent, 1)
	var pressed := _capsule(accent, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)


static func _capsule(accent: bool, state: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if accent:
		match state:
			1:
				sb.bg_color = CORAL.lightened(0.12)
			2:
				sb.bg_color = CORAL.darkened(0.14)
			_:
				sb.bg_color = CORAL
		sb.border_color = WOOD
		sb.set_border_width_all(3)
	else:
		match state:
			1:
				sb.bg_color = Color(1, 1, 1, 0.16)
				sb.border_color = Color(1, 1, 1, 0.38)
			2:
				sb.bg_color = Color(1, 1, 1, 0.06)
				sb.border_color = Color(1, 1, 1, 0.18)
			_:
				sb.bg_color = Color(1, 1, 1, 0.09)
				sb.border_color = Color(1, 1, 1, 0.24)
		sb.set_border_width_all(2)
	sb.set_corner_radius_all(24)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func apply_label(l: Label, size: int, col: Color, outline: bool = true) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", maxi(3, int(size / 8)))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
