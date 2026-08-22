extends Object

const KIND_CANVAS := {
	"player": 128.0,
	"slime": 96.0,
	"bat": 96.0,
	"brute": 128.0,
	"charger": 128.0,
	"caster": 112.0,
	"elite": 144.0,
	"boss": 192.0,
}

const ICON_ALIAS := {
	"dagger_evo": "dagger",
	"orbit_evo": "orbit",
	"boomerang_evo": "boomerang",
	"frost_evo": "frost",
}

const PASSIVE_ICONS := {
	"damage": "damage",
	"haste": "haste",
	"speed": "speed",
	"hp": "hp",
	"magnet": "magnet",
}

static var _frames: Dictionary = {}
static var _icons: Dictionary = {}


static func canvas_size(kind: String) -> float:
	return float(KIND_CANVAS.get(kind, 128.0))


static func sprite_scale(kind: String, radius: float) -> float:
	var canvas: float = canvas_size(kind)
	var mult: float = 3.6 if kind == "player" else (2.55 if kind == "boss" else 2.9)
	return (radius * mult) / canvas


static func icon_path(id: String) -> String:
	var key: String = str(ICON_ALIAS.get(id, id))
	if PASSIVE_ICONS.has(id):
		key = str(PASSIVE_ICONS[id])
	return "res://assets/icons/%s.png" % key


static func icon(id: String) -> Texture2D:
	var path: String = icon_path(id)
	if _icons.has(path):
		return _icons[path] as Texture2D
	if not ResourceLoader.exists(path):
		_icons[path] = null
		return null
	var tex: Texture2D = load(path) as Texture2D
	_icons[path] = tex
	return tex


static func frames_for(kind: String) -> SpriteFrames:
	if _frames.has(kind):
		return _frames[kind] as SpriteFrames
	var sf := SpriteFrames.new()
	var loaded := false
	loaded = _add_anim(sf, kind, "idle", ["idle"]) or loaded
	loaded = _add_anim(sf, kind, "walk", ["walk_0", "walk_1", "walk_2", "walk_3"]) or loaded
	loaded = _add_anim(sf, kind, "attack", ["attack_0", "attack_1", "attack_2", "attack_1"]) or loaded
	if kind != "player":
		if not sf.has_animation("idle") and sf.has_animation("walk"):
			sf.add_animation("idle")
			sf.set_animation_speed("idle", 4.0)
			sf.set_animation_loop("idle", true)
			for i in sf.get_frame_count("walk"):
				sf.add_frame("idle", sf.get_frame_texture("walk", i))
	if not loaded:
		_frames[kind] = null
		return null
	if sf.has_animation("walk"):
		sf.set_animation_speed("walk", 8.0 if kind == "player" or kind == "bat" else 6.0)
		sf.set_animation_loop("walk", true)
	if sf.has_animation("attack"):
		sf.set_animation_speed("attack", 10.0)
		sf.set_animation_loop("attack", kind != "player")
	if sf.has_animation("idle"):
		sf.set_animation_speed("idle", 4.0)
		sf.set_animation_loop("idle", true)
	_frames[kind] = sf
	return sf


static func make_sprite(kind: String, radius: float) -> AnimatedSprite2D:
	var sf: SpriteFrames = frames_for(kind)
	if sf == null:
		return null
	var spr := AnimatedSprite2D.new()
	spr.name = "Sprite"
	spr.sprite_frames = sf
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.show_behind_parent = true
	spr.scale = Vector2.ONE * sprite_scale(kind, radius)
	if sf.has_animation("walk"):
		spr.play("walk")
	elif sf.has_animation("idle"):
		spr.play("idle")
	return spr


static func _add_anim(sf: SpriteFrames, kind: String, anim: String, names: Array) -> bool:
	var added := false
	for n in names:
		var path: String = "res://assets/sprites/%s/%s.png" % [kind, n]
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			continue
		if not added:
			sf.add_animation(anim)
			added = true
		sf.add_frame(anim, tex)
	return added
