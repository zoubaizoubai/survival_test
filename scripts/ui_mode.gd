extends RefCounted

const PREVIEW_SETTING := "ui/platform/preview_mode"
const MODE_AUTO := "auto"
const MODE_MOBILE := "mobile"
const MODE_DESKTOP := "desktop"


static func current() -> String:
	for argument in OS.get_cmdline_user_args():
		var arg: String = str(argument).trim_prefix("--")
		if arg.begins_with("ui_mode="):
			var requested: String = arg.get_slice("=", 1).to_lower()
			if requested == MODE_MOBILE or requested == MODE_DESKTOP:
				return requested
	var preview: String = str(ProjectSettings.get_setting(PREVIEW_SETTING, MODE_AUTO)).to_lower()
	if preview == MODE_MOBILE or preview == MODE_DESKTOP:
		return preview
	if OS.has_feature("android") or OS.has_feature("ios"):
		return MODE_MOBILE
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return MODE_MOBILE
	return MODE_DESKTOP


static func is_mobile() -> bool:
	return current() == MODE_MOBILE


static func can_quit() -> bool:
	return not is_mobile() and not OS.has_feature("web")


static func platform_label() -> String:
	return "移动版" if is_mobile() else "桌面版"


static func home_input_hint() -> String:
	if is_mobile():
		return "拖动左下区域移动  ·  自动攻击  ·  撑过 5 分钟"
	return "WASD / 方向键移动  ·  自动攻击  ·  Esc 暂停"
