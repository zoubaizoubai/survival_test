extends Object

const WOOD := Color(0.42, 0.27, 0.14)
const CREAM := Color(0.96, 0.90, 0.78)
const CORAL := Color(0.94, 0.42, 0.38)
const INK := Color(0.18, 0.12, 0.08)
const TEAL := Color(0.12, 0.18, 0.22)
const UI_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc_ui.woff2"

static var _ui_font: Font
static var _ui_theme: Theme


static func ui_font() -> Font:
	if _ui_font == null:
		_ui_font = load(UI_FONT_PATH) as Font
		if _ui_font == null:
			var system_font := SystemFont.new()
			system_font.font_names = PackedStringArray(["sans-serif"])
			system_font.allow_system_fallback = true
			_ui_font = system_font
	return _ui_font


static func ui_theme() -> Theme:
	if _ui_theme == null:
		_ui_theme = Theme.new()
		_ui_theme.default_font = ui_font()
	return _ui_theme


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
	b.add_theme_font_override("font", ui_font())
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
	var focus: StyleBoxFlat = hover.duplicate()
	focus.set_border_width_all(3)
	focus.border_color = Color(1.0, 0.92, 0.72, 0.78) if accent else Color(1, 1, 1, 0.52)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)


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
	sb.shadow_color = Color(0, 0, 0, 0.22 if state != 2 else 0.12)
	sb.shadow_size = 5 if state != 2 else 2
	sb.shadow_offset = Vector2(0, 2 if state != 2 else 1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func apply_label(l: Label, size: int, col: Color, outline: bool = true) -> void:
	l.add_theme_font_override("font", ui_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", maxi(3, int(size / 8)))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
