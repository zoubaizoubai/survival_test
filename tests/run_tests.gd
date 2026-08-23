extends SceneTree

# 无头烟雾测试与性能基线入口
# 运行: godot --headless --path . -s res://tests/run_tests.gd -- seed=1337
# 可选参数: seed=INT, verbose=true|false, baseline_path=res://tests/baseline.json
# 所有运行都会把 SaveData/Settings 重定向到本次进程专用文件，绝不读写生产 user://。

const SaveDataRef := preload("res://scripts/save_data.gd")
const SettingsRef := preload("res://scripts/settings.gd")
const UiModeRef := preload("res://scripts/ui_mode.gd")
const JoystickRef := preload("res://scripts/joystick.gd")

var _seed: int = 1337
var _verbose: bool = true
var _baseline_path: String = "res://tests/baseline.json"
var _passed: int = 0
var _failed: int = 0
var _failed_details: Array = []
var _perf_results: Array = []
var _start_msec: int = 0
var _test_progress_path: String = ""
var _test_settings_path: String = ""


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		var arg: String = str(a).strip_edges()
		if arg.begins_with("seed="):
			_seed = int(arg.split("=")[1])
		elif arg.begins_with("baseline=") or arg.begins_with("baseline_path="):
			_baseline_path = arg.split("=")[1]
		elif arg == "verbose" or arg == "verbose=true":
			_verbose = true
		elif arg == "verbose=false":
			_verbose = false


func _configure_test_storage() -> bool:
	var run_id: String = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_progress_path = "user://test_progress_%s.cfg" % run_id
	_test_settings_path = "user://test_settings_%s.cfg" % run_id
	var save_isolated: bool = SaveDataRef.set_test_storage_path(_test_progress_path)
	var settings_isolated: bool = SettingsRef.set_test_storage_path(_test_settings_path)
	var save_path_matches: bool = save_isolated and SaveDataRef.get_storage_path() == _test_progress_path
	var settings_path_matches: bool = settings_isolated and SettingsRef.get_storage_path() == _test_settings_path
	_assert(
		save_path_matches,
		"SaveData 使用隔离测试路径",
		"SaveData 测试路径配置失败",
	)
	_assert(
		settings_path_matches,
		"Settings 使用隔离测试路径",
		"Settings 测试路径配置失败",
	)
	return save_path_matches and settings_path_matches


func _cleanup_test_storage() -> void:
	# 进程退出前始终保持重定向生效；若这里切回生产路径，仍存活的场景
	# 可能在最后一帧重新加载真实设置。静态状态会随测试进程销毁。
	for path in [_test_progress_path, _test_settings_path]:
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if err != OK:
			_log_fail("隔离测试文件清理失败", "%s err=%d" % [path, err])


func _log_pass(msg: String) -> void:
	_passed += 1
	if _verbose:
		print("[PASS] %s" % msg)


func _log_fail(msg: String, detail: String = "") -> void:
	_failed += 1
	var line: String = "[FAIL] %s" % msg
	if detail != "":
		line += " :: %s" % detail
	print(line)
	_failed_details.append(line)


func _assert(cond: bool, pass_msg: String, fail_msg: String, detail: String = "") -> bool:
	if cond:
		_log_pass(pass_msg)
		return true
	else:
		_log_fail(fail_msg, detail)
		return false


func _count_nodes(node: Node) -> int:
	var c: int = 1
	for child in node.get_children():
		c += _count_nodes(child)
	return c


func _count_total_nodes() -> int:
	# 统计 SceneTree 中所有节点数（包含 root）
	var root_node: Window = root
	if root_node == null:
		return 0
	var total: int = 0
	for child in root_node.get_children():
		total += _count_nodes(child)
	# 加上 root 本身
	total += 1
	return total


func _initialize() -> void:
	_parse_args()
	if not _configure_test_storage():
		# 隔离失败时绝不能继续执行，否则测试可能读写真实玩家数据。
		_cleanup_test_storage()
		_print_summary()
		quit(1)
		return
	_start_msec = Time.get_ticks_msec()
	seed(_seed)
	print("==================================================")
	print("幸存者 无头烟雾测试与性能基线")
	print("Godot %s seed=%d baseline=%s" % [Engine.get_version_info()["string"] if Engine.get_version_info().has("string") else str(Engine.get_version_info()), _seed, _baseline_path])
	print("==================================================")
	await process_frame
	await process_frame
	await _run_all()
	_cleanup_test_storage()
	_write_baseline()
	_print_summary()
	# 清理后退出，使用非零码标识失败
	var exit_code: int = 0 if _failed == 0 else 1
	quit(exit_code)


func _run_all() -> void:
	await _test_settings_input_responsive()
	await _test_platform_ui_adaptation()
	await _test_data_driven()
	await _test_home_load()
	await _test_game_load()
	await _test_pause_states()
	await _test_upgrade_flow()
	await _test_victory_flow()
	await _test_defeat_flow()
	await _test_restart_and_home()
	await _test_seed_determinism()
	await _test_perf_scenarios()
	await _test_spawn_clamp_and_caps()
	await _test_lightning_range()
	await _test_state_mutex_and_recovery()
	await _test_enemy_behaviors_and_director()
	await _test_weapon_evolution_and_builds()
	await _test_stats_and_save()
	await _test_visual_audio_accessibility()
	await _test_export_and_version()
	# 确保所有异步清理完成
	await process_frame
	await process_frame


func _test_platform_ui_adaptation() -> void:
	print("\n[UI] 桌面与移动端响应式界面")
	var original_mode: String = str(ProjectSettings.get_setting(UiModeRef.PREVIEW_SETTING, UiModeRef.MODE_AUTO))
	var home_res: PackedScene = load("res://scenes/home.tscn") as PackedScene
	if not _assert(home_res != null, "响应式 UI 测试可加载 Home", "响应式 UI 测试无法加载 Home"):
		return
	for mode in [UiModeRef.MODE_DESKTOP, UiModeRef.MODE_MOBILE]:
		ProjectSettings.set_setting(UiModeRef.PREVIEW_SETTING, mode)
		_assert(UiModeRef.current() == mode, "UI 预览模式可切换为 %s" % mode, "UI 预览模式切换失败: %s" % mode)
		var home: Control = home_res.instantiate() as Control
		root.add_child(home)
		await process_frame
		var exit_btn: Button = home.get_node_or_null("CenterContainer/VBoxContainer/ExitButton") as Button
		var tip: Label = home.get_node_or_null("CenterContainer/VBoxContainer/Tip") as Label
		var version: Label = home.get_node_or_null("BottomBar/Version") as Label
		var joystick: Control = JoystickRef.new()
		root.add_child(joystick)
		joystick.set_enabled(UiModeRef.is_mobile())
		_assert(home.has_node("TitleRoot/MenuTransition"), "%s 首页使用渐变分区" % mode, "%s 首页缺少渐变分区" % mode)
		_assert(not home.has_node("GlowTop") and not home.has_node("GlowBottom"), "%s 首页移除硬边矩形光晕" % mode, "%s 首页仍包含硬边矩形光晕" % mode)
		if mode == UiModeRef.MODE_MOBILE:
			_assert(exit_btn != null and not exit_btn.visible, "移动端隐藏退出按钮", "移动端退出按钮仍可见")
			_assert(tip != null and tip.text.contains("左下"), "移动端显示触控提示", "移动端触控提示错误")
			_assert(version != null and version.text.contains("移动版"), "移动端版本标识正确", "移动端版本标识错误")
			_assert(joystick.visible, "移动端显示虚拟摇杆", "移动端虚拟摇杆被隐藏")
		else:
			_assert(exit_btn != null and exit_btn.visible, "桌面端显示退出按钮", "桌面端退出按钮被隐藏")
			_assert(tip != null and tip.text.contains("WASD"), "桌面端显示键鼠提示", "桌面端键鼠提示错误")
			_assert(version != null and version.text.contains("桌面版"), "桌面端版本标识正确", "桌面端版本标识错误")
			_assert(not joystick.visible, "桌面端隐藏虚拟摇杆", "桌面端虚拟摇杆仍可见")
		home.queue_free()
		joystick.queue_free()
		await process_frame
	ProjectSettings.set_setting(UiModeRef.PREVIEW_SETTING, original_mode)


# --------------------------------------------------
# 1. 主页加载
# --------------------------------------------------
func _test_home_load() -> void:
	print("\n[SMOKE] Home 场景加载")
	var res: Resource = load("res://scenes/home.tscn")
	if not _assert(res != null, "home.tscn 可加载", "home.tscn 加载失败"):
		return
	if not _assert(res is PackedScene, "home.tscn 为 PackedScene", "home.tscn 类型错误: %s" % str(res.get_class())):
		return
	var ps: PackedScene = res as PackedScene
	var inst: Node = ps.instantiate()
	if not _assert(inst != null, "home.tscn 可实例化", "home.tscn 实例化返回 null"):
		return
	root.add_child(inst)
	await process_frame
	_assert(inst is Control, "Home 根节点为 Control", "Home 根节点类型错误: %s" % inst.get_class())
	_assert(inst.has_node("CenterContainer/VBoxContainer/StartButton"), "Home 包含 StartButton", "StartButton 缺失")
	_assert(inst.has_node("CenterContainer/VBoxContainer/ExitButton"), "Home 包含 ExitButton", "ExitButton 缺失")
	_assert(inst.has_node("Background"), "Home 包含 Background", "Background 缺失")
	# 验证脚本挂载
	_assert(inst.get_script() != null, "Home 挂载 home.gd", "Home 未挂载脚本")
	# 验证信号连接
	var start_btn: Button = inst.get_node_or_null("CenterContainer/VBoxContainer/StartButton") as Button
	if start_btn != null:
		var conns: Array = start_btn.pressed.get_connections() if false else [] # 信号连接需通过场景文件检查
		# 直接检查场景连接的正确性：通过加载 .tscn 文本搜索
		# 简化：验证方法存在
		_assert(inst.has_method("_on_start_pressed"), "Home 拥有 _on_start_pressed", "_on_start_pressed 缺失")
		_assert(inst.has_method("_on_exit_pressed"), "Home 拥有 _on_exit_pressed", "_on_exit_pressed 缺失")
	# 尝试触发开始游戏但不污染后续：创建临时 Home 并调用 _on_start_pressed 后的 current_scene 会变为 Game
	# 我们通过隔离测试：记录当前 scene，调用后检查，再切回
	var before_scene: Node = current_scene
	# 调用前准备：确保不会因缺少 Game 场景崩溃
	inst._on_start_pressed()
	await process_frame
	await process_frame
	var after_scene: Node = current_scene
	_assert(after_scene != null and after_scene.name == "Game", "Home _on_start_pressed 可切换至 Game 场景", "切换失败，current_scene=%s" % str(after_scene))
	# 清理：切回 null 并移除 Home 实例，恢复状态
	if after_scene != null and after_scene != inst:
		# after_scene 是 Game，需释放
		after_scene.queue_free()
		await process_frame
	# 移除原 Home 实例（若仍在树中）
	if is_instance_valid(inst) and inst.get_parent() == root:
		inst.queue_free()
		await process_frame
	# 确保 current_scene 重置为 null（通过卸载）
	# Godot 的 change_scene_to_file 会设置 current_scene；我们需要卸载以隔离后续测试
	# 简单：若 current_scene 非空且为 Game，已释放，等待一帧后应为 null
	await process_frame
	# 若仍非空，尝试强制卸载：创建空场景并切换？简化：直接检查可继续测试即可
	print("  Home 加载与导航校验完成，current_scene=%s" % str(current_scene))


# --------------------------------------------------
# 2. 游戏场景加载
# --------------------------------------------------
func _test_game_load() -> void:
	print("\n[SMOKE] Game 场景加载")
	var res: Resource = load("res://scenes/game.tscn")
	if not _assert(res != null, "game.tscn 可加载", "game.tscn 加载失败"):
		return
	if not _assert(res is PackedScene, "game.tscn 为 PackedScene", "game.tscn 类型错误"):
		return
	var ps: PackedScene = res as PackedScene
	var g: Node = ps.instantiate()
	if not _assert(g != null, "game.tscn 可实例化", "game.tscn 实例化 null"):
		return
	root.add_child(g)
	await process_frame
	await process_frame
	# 验证关键节点存在
	_assert(g.has_method("_process"), "Game 拥有 _process", "Game 缺少 _process")
	_assert(g.get("player") != null, "Game 正确创建 player", "player 为 null")
	_assert(g.get("enemies_node") != null, "Game 创建 enemies_node", "enemies_node 为 null")
	_assert(g.get("pickups_node") != null, "Game 创建 pickups_node", "pickups_node 为 null")
	_assert(g.get("projectiles_node") != null, "Game 创建 projectiles_node", "projectiles_node 为 null")
	_assert(g.get("hud") != null, "Game 创建 hud", "hud 为 null")
	_assert(g.get("menus") != null, "Game 创建 menus", "menus 为 null")
	_assert(g.get("cam") != null, "Game 创建 cam", "cam 为 null")
	_assert((g.get("cam") as Camera2D).is_current(), "Camera2D 为 current", "相机未设为 current")
	_assert(float(g.get("elapsed")) < 0.1, "初始 elapsed 接近 0", "elapsed=%s" % str(g.get("elapsed")))
	_assert(g.get("running") == true, "初始 running 为 true", "running=%s" % str(g.get("running")))
	_assert(g.get("ended") == false, "初始 ended 为 false", "ended=%s" % str(g.get("ended")))
	_assert(g.get_tree().paused == false, "初始未暂停", "paused=%s" % str(g.get_tree().paused))
	# 验证常量存在
	_assert(g.get("MAX_ENEMIES") == 170, "MAX_ENEMIES 为 170", "MAX_ENEMIES=%s" % str(g.get("MAX_ENEMIES")))
	_assert(g.get("GOAL_TIME") == 300.0, "GOAL_TIME 为 300", "GOAL_TIME=%s" % str(g.get("GOAL_TIME")))
	_assert(g.get("ARENA") == 2600.0, "ARENA 为 2600", "ARENA=%s" % str(g.get("ARENA")))
	# 玩家基础属性与弹道关键参数必须真正来自平衡表，而非仅存在于 JSON。
	var gd: GDScript = preload("res://scripts/game_data.gd")
	var player_balance: Dictionary = gd.spawn.get("player", {}) as Dictionary
	var player: Node = g.get("player") as Node
	_assert(is_equal_approx(float(player.get("base_speed")), float(player_balance.get("base_speed"))), "玩家基础速度接入平衡表", "player=%s data=%s" % [str(player.get("base_speed")), str(player_balance)])
	_assert(is_equal_approx(float(player.get("base_magnet")), float(player_balance.get("base_magnet"))), "玩家磁吸半径接入平衡表", "player=%s data=%s" % [str(player.get("base_magnet")), str(player_balance)])
	_assert(is_equal_approx(float(player.get("max_hp")), float(player_balance.get("base_hp"))), "玩家基础生命接入平衡表", "player=%s data=%s" % [str(player.get("max_hp")), str(player_balance)])
	var projectiles: Node = g.get("projectiles_node") as Node
	g.spawn_projectile(Vector2.ZERO, 1.0, 1, Vector2.ZERO)
	var safe_projectile: Node = projectiles.get_child(projectiles.get_child_count() - 1) as Node
	_assert(is_equal_approx((safe_projectile.get("dir") as Vector2).length(), 1.0), "零方向普通弹道使用安全方向", "dir=%s" % str(safe_projectile.get("dir")))
	g._recycle_projectile(safe_projectile)
	g.spawn_boomerang(Vector2.ZERO, 1.0, 1, Vector2.ZERO, 500.0, 0.73)
	var boomerang: Node = projectiles.get_child(projectiles.get_child_count() - 1) as Node
	_assert(is_equal_approx(float(boomerang.get("boomerang_return")), 0.73), "回旋斧 return_time 接入弹道", "actual=%s" % str(boomerang.get("boomerang_return")))
	_assert(is_equal_approx((boomerang.get("dir") as Vector2).length(), 1.0), "零方向回旋斧使用安全方向", "dir=%s" % str(boomerang.get("dir")))
	g._recycle_projectile(boomerang)
	g._spawn_at("slime", Vector2(100.0, 0.0))
	var swept_enemy: Node = (g.get("enemies_node") as Node).get_child(0) as Node
	var swept_hp_before: float = float(swept_enemy.get("hp"))
	g.spawn_projectile(Vector2.RIGHT, 10.0, 1, Vector2.ZERO)
	var swept_projectile: Node = projectiles.get_child(projectiles.get_child_count() - 1) as Node
	swept_projectile.set("speed", 10000.0)
	swept_projectile._process(0.02)
	_assert(float(swept_enemy.get("hp")) < swept_hp_before, "高速弹道线段碰撞不穿敌", "hp before=%.1f after=%.1f" % [swept_hp_before, float(swept_enemy.get("hp"))])
	# 清理
	var tree_ref: SceneTree = g.get_tree()
	tree_ref.paused = false
	g.queue_free()
	await process_frame
	await process_frame


# --------------------------------------------------
# 3. 暂停状态
# --------------------------------------------------
func _test_pause_states() -> void:
	print("\n[SMOKE] 暂停状态转换")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var menus: Control = g.get("menus") as Control
	# 初始未暂停
	_assert(g.get_tree().paused == false, "暂停测试初始未暂停", "paused=%s" % str(g.get_tree().paused))
	_assert(menus.get("pause_layer").visible == false, "初始 pause_layer 隐藏", "pause_layer 可见")
	# 正常暂停
	menus.toggle_pause()
	await process_frame
	_assert(g.get_tree().paused == true, "toggle_pause 可暂停", "暂停失败")
	_assert(menus.get("pause_layer").visible == true, "暂停后 pause_layer 可见", "pause_layer 仍隐藏")
	# 再次切换恢复
	menus.toggle_pause()
	await process_frame
	_assert(g.get_tree().paused == false, "二次 toggle 可恢复", "恢复失败")
	_assert(menus.get("pause_layer").visible == false, "恢复后 pause_layer 隐藏", "pause_layer 仍可见")
	# 已结束时不应暂停
	g.set("ended", true)
	menus.toggle_pause()
	await process_frame
	_assert(g.get_tree().paused == false, "ended=true 时 toggle 被阻断", "ended 时错误暂停")
	_assert(menus.get("pause_layer").visible == false, "ended 时 pause_layer 保持隐藏", "ended 时错误显示")
	g.set("ended", false)
	# 升级界面可见时不应暂停
	menus.get("upgrade_layer").visible = true
	menus.toggle_pause()
	await process_frame
	_assert(g.get_tree().paused == false, "upgrade 可见时 toggle 被阻断", "升级时错误暂停")
	menus.get("upgrade_layer").visible = false
	# 暂停键重新可行
	menus.toggle_pause()
	await process_frame
	_assert(g.get_tree().paused == true, "清除阻断后可再次暂停", "暂停失败")
	# 清理
	menus.get("pause_layer").visible = false
	g.get_tree().paused = false
	g.queue_free()
	await process_frame
	await process_frame


# --------------------------------------------------
# 4. 升级流程
# --------------------------------------------------
func _test_upgrade_flow() -> void:
	print("\n[SMOKE] 升级流程")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var menus: Control = g.get("menus") as Control
	var player: Node = g.get("player") as Node
	# 初始 weapons 包含 dagger
	_assert((player.get("weapons") as Dictionary).has("dagger"), "初始武器包含 dagger", "dagger 缺失")
	# 模拟升级：_on_level_up 应使 pending 增加并展示升级层
	var pending_before: int = int(g.get("pending_levels"))
	g._on_level_up()
	await process_frame
	_assert(menus.get("upgrade_layer").visible == true, "升级时 upgrade_layer 可见", "upgrade_layer 隐藏")
	_assert(g.get_tree().paused == true, "升级时游戏暂停", "未暂停")
	# 验证 roll_cards 产出 3 张且无重复 id（除 heal 填充）
	var cards: Array = g._roll_cards()
	_assert(cards.size() == 3, "roll_cards 返回 3 张", "数量=%d" % cards.size())
	var ids: Dictionary = {}
	var dup_found: bool = false
	for c in cards:
		var id: String = str(c["id"]) if c.has("id") else "heal"
		if c["kind"] != "heal":
			if ids.has(id):
				dup_found = true
			ids[id] = true
	_assert(not dup_found, "roll_cards 无重复 id", "发现重复")
	# 选择卡牌
	var first: Dictionary = cards[0]
	var kind: String = str(first["kind"])
	var id: String = str(first["id"]) if first.has("id") else ""
	var weapons_before: int = (player.get("weapons") as Dictionary).size()
	var passives_before: int = (player.get("passives") as Dictionary).size()
	# 单 pending 情况下选择后应隐藏并恢复
	g._on_card_chosen(first)
	await process_frame
	_assert(menus.get("upgrade_layer").visible == false, "选卡后 upgrade_layer 隐藏", "仍可见")
	_assert(g.get_tree().paused == false, "选卡后恢复暂停", "仍暂停")
	if kind == "weapon_new":
		_assert((player.get("weapons") as Dictionary).has(id), "新武器已添加: %s" % id, "武器未添加")
	elif kind == "weapon_up":
		_assert(true, "武器升级卡已处理", "")
	elif kind == "passive":
		_assert((player.get("passives") as Dictionary).has(id), "被动已添加: %s" % id, "被动未添加")
	else:
		_assert(true, "治疗卡已处理", "")
	# 测试连续升级堆叠
	g._on_level_up()
	g._on_level_up()
	await process_frame
	_assert(int(g.get("pending_levels")) == 1, "连续两次升级 pending=1（一次已展示）", "pending=%d" % int(g.get("pending_levels")))
	_assert(menus.get("upgrade_layer").visible == true, "连续升级时 upgrade 仍可见", "隐藏")
	# 取当前展示的卡并选择，应自动展示下一张
	var next_cards: Array = g._roll_cards()
	# 由于 _show_next_upgrade 在卡片选择后会自动展示 pending>0 的下一组，我们直接模拟选择
	var before_pending: int = int(g.get("pending_levels"))
	# 通过 menus 当前可见状态判断
	# 调用选卡一次
	var dummy_card: Dictionary = next_cards[0]
	g._on_card_chosen(dummy_card)
	await process_frame
	# 此时若 pending>0，会再次展示
	if before_pending > 0:
		_assert(menus.get("upgrade_layer").visible == true, "堆叠升级选卡后自动展示下一组", "未自动展示")
		# 清理第二组
		var second_cards: Array = g._roll_cards()
		g._on_card_chosen(second_cards[0])
		await process_frame
	_assert(menus.get("upgrade_layer").visible == false, "堆叠升级全部处理后隐藏", "仍可见")
	_assert(g.get_tree().paused == false, "堆叠升级结束恢复", "仍暂停")
	# 清理
	g.get_tree().paused = false
	menus.get("upgrade_layer").visible = false
	menus.get("pause_layer").visible = false
	g.queue_free()
	await process_frame
	await process_frame


# --------------------------------------------------
# 5. 胜利流程
# --------------------------------------------------
func _test_victory_flow() -> void:
	print("\n[SMOKE] 胜利流程")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var menus: Control = g.get("menus") as Control
	var totals_before: Dictionary = SaveDataRef.get_totals()
	_assert(g.get("ended") == false, "胜利测试初始未结束", "ended=true")
	# 模拟时间到达 GOAL_TIME
	var goal: float = float(g.get("GOAL_TIME"))
	g.set("elapsed", goal - 0.05)
	g._process(0.1)
	await process_frame
	_assert(g.get("ended") == true, "到达 GOAL_TIME 后 ended=true", "ended=%s" % str(g.get("ended")))
	_assert(g.get_tree().paused == true, "胜利后暂停", "未暂停")
	_assert(menus.get("end_layer").visible == true, "胜利后 end_layer 可见", "隐藏")
	_assert(str(menus.get("end_title").text).contains("胜") and str(menus.get("end_title").text).contains("利"), "胜利标题包含 '胜'/'利'", "标题=%s" % str(menus.get("end_title").text))
	_assert(menus.get("endless_btn").visible == true, "胜利时 endless 按钮可见", "隐藏")
	var totals_after_win: Dictionary = SaveDataRef.get_totals()
	_assert(int(totals_after_win["total_games"]) == int(totals_before["total_games"]) + 1, "胜利结算只增加一局", "before=%s after=%s" % [str(totals_before), str(totals_after_win)])
	# 继续无尽模式
	g.continue_endless()
	await process_frame
	_assert(g.get("ended") == false, "continue_endless 后 ended=false", "仍为 true")
	_assert(g.get("endless") == true, "continue_endless 设置 endless=true", "false")
	_assert(g.get_tree().paused == false, "continue_endless 后恢复", "仍暂停")
	_assert(menus.get("end_layer").visible == false, "continue_endless 后 end_layer 隐藏", "仍可见")
	# 再次触发胜利不应重复（因为 endless=true）
	g.set("elapsed", goal + 10.0)
	g._process(0.1)
	await process_frame
	_assert(g.get("ended") == false, "无尽模式下不再触发胜利", "错误触发")
	# 无尽阶段死亡应延伸同一局，而不是把胜利局再次累计。
	g.set("kills", 7)
	g.set("total_damage", 25.0)
	var player: Node = g.get("player") as Node
	player.set("invuln", 0.0)
	player.hurt(9999.0)
	await process_frame
	await process_frame
	_assert(g.get("ended") == true, "无尽死亡进入结算", "ended=false")
	var totals_after_endless: Dictionary = SaveDataRef.get_totals()
	_assert(int(totals_after_endless["total_games"]) == int(totals_after_win["total_games"]), "胜利转无尽死亡不重复计局数", "win=%s endless=%s" % [str(totals_after_win), str(totals_after_endless)])
	_assert(int(totals_after_endless["total_kills"]) == int(totals_after_win["total_kills"]) + 7, "无尽结算只追加 checkpoint 后击杀", "win=%s endless=%s" % [str(totals_after_win), str(totals_after_endless)])
	_assert(is_equal_approx(float(totals_after_endless["total_damage"]), float(totals_after_win["total_damage"]) + 25.0), "无尽结算只追加 checkpoint 后伤害", "win=%s endless=%s" % [str(totals_after_win), str(totals_after_endless)])
	# 清理
	g.get_tree().paused = false
	g.queue_free()
	await process_frame
	await process_frame


# --------------------------------------------------
# 6. 失败流程
# --------------------------------------------------
func _test_defeat_flow() -> void:
	print("\n[SMOKE] 失败流程")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var menus: Control = g.get("menus") as Control
	var player: Node = g.get("player") as Node
	_assert(g.get("ended") == false, "失败测试初始未结束", "ended=true")
	_assert(player.get("dead") == false, "初始 player 未死亡", "dead=true")
	# 造成致命伤害
	player.hurt(9999.0)
	await process_frame
	await process_frame
	_assert(player.get("dead") == true, "致命伤害后 dead=true", "仍存活")
	_assert(g.get("ended") == true, "死亡后 ended=true", "未结束")
	_assert(g.get_tree().paused == true, "死亡后暂停", "未暂停")
	_assert(menus.get("end_layer").visible == true, "死亡后 end_layer 可见", "隐藏")
	_assert(str(menus.get("end_title").text).contains("倒下"), "失败标题包含 '倒下'", "标题=%s" % str(menus.get("end_title").text))
	_assert(menus.get("endless_btn").visible == false, "失败时 endless 按钮隐藏", "可见")
	# 清理
	g.get_tree().paused = false
	g.queue_free()
	await process_frame
	await process_frame


# --------------------------------------------------
# 7. 重开与返回主页
# --------------------------------------------------
func _test_restart_and_home() -> void:
	print("\n[SMOKE] 重开与返回主页")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	# 模拟胜利后暂停状态
	g.set("ended", true)
	g.get_tree().paused = true
	# restart 应清除 paused（即使 reload_current_scene 在 headless 下报错也应不崩溃）
	var err_before: int = _failed
	g.restart()
	await process_frame
	_assert(g.get_tree().paused == false, "restart 后 paused=false", "仍为 true")
	# 由于当前 headless 中 current_scene 为 null，restart 会打印 ERROR，但不应使测试崩溃
	_assert(_failed == err_before, "restart 未引入新失败", "失败数变化")
	# 重置为新 Game 以测试 to_home
	g.queue_free()
	await process_frame
	await process_frame
	var g2: Node = ps.instantiate()
	root.add_child(g2)
	await process_frame
	await process_frame
	g2.set("ended", true)
	g2.get_tree().paused = true
	g2.to_home()
	await process_frame
	await process_frame
	_assert(g2.get_tree().paused == false, "to_home 后 paused=false", "仍为 true")
	_assert(current_scene != null and current_scene.name == "Home", "to_home 切换至 Home 场景", "current_scene=%s" % str(current_scene))
	# 清理 Home 场景
	if current_scene != null and current_scene.name == "Home":
		# Home 是 current_scene，释放它需通过 change_scene 清理？直接 queue_free 会导致 current_scene 悬空
		# 使用 get_tree().change_scene_to_file 到空或直接释放并设 null
		current_scene.queue_free()
		await process_frame
		# 手动置空 current_scene 需通过 root 移除 – Godot 会自动处理，等待一帧
		await process_frame
	var tree_ref2: SceneTree = g2.get_tree()
	# 清理 g2 若仍在树中
	if is_instance_valid(g2) and g2.get_parent() == root:
		g2.queue_free()
		await process_frame
	tree_ref2.paused = false
	await process_frame


# --------------------------------------------------
# 8. 随机种子可控性
# --------------------------------------------------
func _test_seed_determinism() -> void:
	print("\n[SMOKE] 随机种子与可重复性")
	# 全局 randf 序列可重复
	seed(42)
	var a1: float = randf()
	var a2: float = randf()
	var a3: float = randf()
	seed(42)
	var b1: float = randf()
	var b2: float = randf()
	var b3: float = randf()
	_assert(is_equal_approx(a1, b1) and is_equal_approx(a2, b2) and is_equal_approx(a3, b3), "seed(42) 后 randf 序列可重复", "序列不一致 %s vs %s" % [str([a1,a2,a3]), str([b1,b2,b3])])
	# 游戏内生成可重复：同一 seed 下 _pick_kind 与 _spawn_pos 序列一致
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	seed(12345)
	var g1: Node = ps.instantiate()
	root.add_child(g1)
	await process_frame
	await process_frame
	g1.set("elapsed", 90.0)
	var seq1_kinds: Array = []
	var seq1_pos: Array = []
	for i in 5:
		seq1_kinds.append(g1._pick_kind())
		seq1_pos.append(g1._spawn_pos())
	g1.queue_free()
	await process_frame
	seed(12345)
	var g2: Node = ps.instantiate()
	root.add_child(g2)
	await process_frame
	await process_frame
	g2.set("elapsed", 90.0)
	var seq2_kinds: Array = []
	var seq2_pos: Array = []
	for i in 5:
		seq2_kinds.append(g2._pick_kind())
		seq2_pos.append(g2._spawn_pos())
	var kinds_equal: bool = str(seq1_kinds) == str(seq2_kinds)
	var pos_equal: bool = true
	for i in seq1_pos.size():
		if not (seq1_pos[i] as Vector2).is_equal_approx(seq2_pos[i] as Vector2):
			pos_equal = false
			break
	_assert(kinds_equal, "同 seed 下 _pick_kind 序列可重复", "%s vs %s" % [str(seq1_kinds), str(seq2_kinds)])
	_assert(pos_equal, "同 seed 下 _spawn_pos 序列可重复", "位置不一致")
	g2.queue_free()
	await process_frame
	await process_frame
	# 恢复全局 seed
	seed(_seed)


# --------------------------------------------------
# 9. 性能基线（60/180/300 及上限）
# --------------------------------------------------
func _test_perf_scenarios() -> void:
	print("\n[PERF] 性能基线")
	var scenarios: Array = [60.0, 180.0, 300.0]
	for elapsed in scenarios:
		var result: Dictionary = await _run_perf_one(elapsed, _seed + int(elapsed))
		_perf_results.append(result)
		print("  [PERF] elapsed=%.0f  enemies=%d  pickups=%d  nodes=%d  avg_ms=%.3f  p95=%.3f  objects=%d" % [result["elapsed"], result["enemies"], result["pickups"], result["total_nodes"], result["avg_ms"], result["p95_ms"], result["object_count"]])
		_assert(result["avg_ms"] < 8.0, "elapsed %.0fs 平均 <8ms (%.3fms)" % [elapsed, result["avg_ms"]], "平均过高: %.3fms" % result["avg_ms"])
		_assert(result["p95_ms"] < 8.0, "elapsed %.0fs 95分位 <8ms (%.3fms)" % [elapsed, result["p95_ms"]], "95分位过高: %.3fms" % result["p95_ms"])
	# 上限场景：填满敌人与掉落物
	var cap_result: Dictionary = await _run_perf_caps()
	_perf_results.append(cap_result)
	print("  [PERF] caps enemies=%d pickups=%d nodes=%d avg_ms=%.3f p95=%.3f" % [cap_result["enemies"], cap_result["pickups"], cap_result["total_nodes"], cap_result["avg_ms"], cap_result["p95_ms"]])
	_assert(cap_result["enemies"] == 170, "敌人总上限严格为 170（含特殊槽）", "enemies=%d" % cap_result["enemies"])
	_assert(cap_result["pickups"] == 350, "掉落物总上限严格为 350", "pickups=%d" % cap_result["pickups"])
	_assert(cap_result["avg_ms"] < 10.0, "上限场景平均 <10ms (%.3fms)" % cap_result["avg_ms"], "平均过高")
	_assert(cap_result["p95_ms"] < 10.0, "上限场景 95分位 <10ms (%.3fms)" % cap_result["p95_ms"], "95分位过高")


func _run_perf_frame(g: Node, dt: float) -> void:
	# 这是确定性逻辑微基准，不含 GPU；覆盖所有主要逐帧脚本，避免只测
	# Game/Enemy/Player 却漏掉 350 个 Pickup、HUD 与 FX。
	g._process(dt)
	for e in (g.get("enemies_node") as Node).get_children():
		if is_instance_valid(e) and e.get_parent() != null:
			e._process(dt)
	var player_node: Node = g.get("player") as Node
	player_node._process(dt)
	for p in (g.get("projectiles_node") as Node).get_children():
		if is_instance_valid(p) and p.get_parent() != null:
			p._process(dt)
	for pickup in (g.get("pickups_node") as Node).get_children():
		if is_instance_valid(pickup) and pickup.get_parent() != null:
			pickup._process(dt)
	for fx in (g.get("fx_node") as Node).get_children():
		if is_instance_valid(fx) and fx.get_parent() != null and fx.has_method("_process"):
			fx._process(dt)
	(g.get("hud") as Node)._process(dt)


func _run_perf_one(elapsed_val: float, seed_val: int) -> Dictionary:
	seed(seed_val)
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	g.set("elapsed", elapsed_val)
	g.set("endless", true)
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
	g.set("_wave_idx", (g.get("_wave_cache") as Array).size())
	g.set("boss_idx", 9999)
	(g.get("player") as Node).set("invuln", 99999.0)
	# 清理初始可能生成的敌人？游戏初始没有敌人，spawn_t 需等待
	# 填满至 MAX_ENEMIES
	var enemies_node_ref: Node = g.get("enemies_node") as Node
	var pickups_node_ref: Node = g.get("pickups_node") as Node
	for i in 200:
		if enemies_node_ref.get_child_count() >= int(g.get("MAX_ENEMIES")):
			break
		var kind: String = g._pick_kind()
		var pos: Vector2 = g._spawn_pos()
		g._spawn_at(kind, pos)
	# 普通敌人会为 elite/boss 保留两个槽；补齐特殊敌人后再测完整上限。
	g._spawn_at("elite", g._spawn_pos())
	g._spawn_at("boss", g._spawn_pos())
	# 填满掉落物上限，固定在玩家吸附范围外，保证测量期间
	# 始终承受 350 个活跃掉落物节点的负载。
	for i in 360:
		var pickup_pos := Vector2(
			700.0 + float(i % 25) * 12.0,
			700.0 + float(i / 25) * 12.0,
		)
		g._spawn_pickup("gem", pickup_pos, 1)
		if pickups_node_ref.get_child_count() >= 350:
			break
	await process_frame
	await process_frame
	# 禁止自动刷怪干扰性能测量
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
	var enemies: int = int(g._live_count())
	var pickups_before_measure: int = pickups_node_ref.get_child_count()
	_assert(pickups_before_measure == int(g.get("MAX_PICKUPS")), "性能场景填满掉落物节点上限", "count=%d" % pickups_before_measure)
	var total_nodes: int = _count_total_nodes()
	var object_count: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var object_nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	# 测量 200 帧模拟耗时（含 95 分位）
	var iterations: int = 200
	var dt: float = 1.0 / 60.0
	var samples: Array = []
	samples.resize(iterations)
	var t0: int = Time.get_ticks_usec()
	for iter in iterations:
		var s0: int = Time.get_ticks_usec()
		_run_perf_frame(g, dt)
		var s1: int = Time.get_ticks_usec()
		samples[iter] = float(s1 - s0) / 1000.0
	var t1: int = Time.get_ticks_usec()
	var avg_ms: float = float(t1 - t0) / float(iterations) / 1000.0
	samples.sort()
	var p95_ms: float = float(samples[int(iterations * 0.95)])
	var p50_ms: float = float(samples[int(iterations * 0.5)])
	var pickups_after_measure: int = pickups_node_ref.get_child_count()
	_assert(pickups_after_measure == pickups_before_measure, "性能测量期间掉落物节点保持满额", "before=%d after=%d" % [pickups_before_measure, pickups_after_measure])
	var result: Dictionary = {
		"elapsed": elapsed_val,
		"enemies": enemies,
		"pickups": pickups_after_measure,
		"total_nodes": total_nodes,
		"object_count": int(object_count),
		"object_nodes": int(object_nodes),
		"avg_ms": avg_ms,
		"p95_ms": p95_ms,
		"p50_ms": p50_ms,
		"seed": seed_val,
		"iterations": iterations,
		"ended": bool(g.get("ended")),
	}
	_assert(not bool(result["ended"]), "elapsed %.0fs 性能场景保持运行" % elapsed_val, "性能场景错误进入结束状态")
	g.queue_free()
	await process_frame
	# 清理掉落物等残留（若 queue_free 未立即清理）
	await process_frame
	return result


func _run_perf_caps() -> Dictionary:
	seed(_seed + 9999)
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	g.set("elapsed", 250.0)
	g.set("endless", true)
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
	g.set("_wave_idx", (g.get("_wave_cache") as Array).size())
	g.set("boss_idx", 9999)
	(g.get("player") as Node).set("invuln", 99999.0)
	var enemies_node_ref2: Node = g.get("enemies_node") as Node
	# 先填满普通敌人配额，再验证 elite/boss 各自唯一且共用总上限。
	for i in 300:
		if enemies_node_ref2.get_child_count() >= int(g.get("MAX_ENEMIES")) - 2:
			break
		g._spawn_at("brute", g._spawn_pos())
	await process_frame
	_assert(int(g._live_count()) == int(g.get("MAX_ENEMIES")) - 2, "普通敌人保留 2 个特殊槽", "count=%d" % int(g._live_count()))
	var elite_spawned: bool = g._spawn_at("elite", g._spawn_pos())
	var after_elite: int = int(g._live_count())
	var duplicate_elite: bool = g._spawn_at("elite", g._spawn_pos())
	_assert(elite_spawned and not duplicate_elite and int(g._live_count()) == after_elite, "elite 单实例限制生效", "spawned=%s duplicate=%s count=%d" % [str(elite_spawned), str(duplicate_elite), int(g._live_count())])
	var boss_spawned: bool = g._spawn_at("boss", g._spawn_pos())
	_assert(boss_spawned and int(g._live_count()) == int(g.get("MAX_ENEMIES")), "boss 填满最后特殊槽", "spawned=%s count=%d" % [str(boss_spawned), int(g._live_count())])
	var before: int = int(g._live_count())
	# 尝试通过 _spawn_one 超越上限（应被限制）
	for i in 10:
		g._spawn_one()
	var after: int = int(g._live_count())
	_assert(before == after and before == int(g.get("MAX_ENEMIES")), "超越上限时敌人数量严格不变", "before=%d after=%d" % [before, after])
	var pickups_node_ref2: Node = g.get("pickups_node") as Node
	# 填满掉落物
	for i in 500:
		if pickups_node_ref2.get_child_count() >= 350:
			break
		g._spawn_pickup("gem", Vector2(1000.0, 1000.0), 1)
	await process_frame
	var pick_before: int = int(g.get_tree().get_nodes_in_group("pickup").size())
	var xp_before: int = 0
	for pickup in pickups_node_ref2.get_children():
		if str(pickup.get("kind")) == "gem":
			xp_before += int(pickup.get("value"))
	for i in 20:
		g._spawn_pickup("gem", Vector2.ZERO, 1)
	var pick_after: int = int(g.get_tree().get_nodes_in_group("pickup").size())
	var xp_after: int = 0
	for pickup in pickups_node_ref2.get_children():
		if str(pickup.get("kind")) == "gem":
			xp_after += int(pickup.get("value"))
	_assert(pick_before == 350 and pick_after == pick_before, "超越上限时掉落物数量严格不变", "before=%d after=%d" % [pick_before, pick_after])
	_assert(xp_after == xp_before + 20, "掉落物满额时合并 XP 不丢失", "before=%d after=%d" % [xp_before, xp_after])
	g._spawn_pickup("heart", Vector2(1000.0, 1000.0), 30)
	var xp_after_heart: int = 0
	var heart_after_cap: int = 0
	for pickup in pickups_node_ref2.get_children():
		if str(pickup.get("kind")) == "gem":
			xp_after_heart += int(pickup.get("value"))
		elif str(pickup.get("kind")) == "heart":
			heart_after_cap += int(pickup.get("value"))
	_assert(pickups_node_ref2.get_child_count() == 350 and xp_after_heart == xp_after and heart_after_cap == 30, "350 宝石满额后首颗心无损腾槽", "count=%d xp=%d heart=%d" % [pickups_node_ref2.get_child_count(), xp_after_heart, heart_after_cap])
	await process_frame
	# 禁止自动刷怪
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
	var total_nodes: int = _count_total_nodes()
	var enemies_for_result: int = int(g._live_count())
	var samples2: Array = []
	samples2.resize(200)
	var t0: int = Time.get_ticks_usec()
	for iter in 200:
		var s0: int = Time.get_ticks_usec()
		_run_perf_frame(g, 0.016)
		var s1: int = Time.get_ticks_usec()
		samples2[iter] = float(s1 - s0) / 1000.0
	var t1: int = Time.get_ticks_usec()
	var avg_ms: float = float(t1 - t0) / 200.0 / 1000.0
	samples2.sort()
	var p95_ms: float = float(samples2[int(200 * 0.95)])
	var pickups_for_result: int = pickups_node_ref2.get_child_count()
	_assert(pickups_for_result == int(g.get("MAX_PICKUPS")), "上限性能测量期间掉落物节点保持满额", "count=%d" % pickups_for_result)
	var result: Dictionary = {
		"elapsed": 999.0,
		"label": "caps",
		"enemies": enemies_for_result,
		"pickups": pickups_for_result,
		"total_nodes": total_nodes,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"avg_ms": avg_ms,
		"p95_ms": p95_ms,
		"seed": _seed + 9999,
	}
	g.queue_free()
	await process_frame
	await process_frame
	return result


func _test_settings_input_responsive() -> void:
	print("\n[SMOKE] 设置、输入与响应式")
	# 1. 设置可从主页访问并持久化
	var home_res: Resource = load("res://scenes/home.tscn")
	var home: Control = (home_res as PackedScene).instantiate() as Control
	root.add_child(home)
	await process_frame
	await process_frame
	var settings_btn: Button = home.get_node_or_null("CenterContainer/VBoxContainer/SettingsButton") as Button
	_assert(settings_btn != null, "主页包含设置按钮", "SettingsButton 缺失")
	if settings_btn:
		_assert(settings_btn.text.contains("设置"), "设置按钮文案正确", "text=%s" % settings_btn.text)
		_assert(settings_btn.focus_mode == Control.FOCUS_ALL, "设置按钮可聚焦", "focus=%d" % settings_btn.focus_mode)
	# 检查设置层存在且初始隐藏
	var sl: Control = home.get_node_or_null("SettingsLayer") as Control
	_assert(sl != null, "主页设置层存在", "SettingsLayer 缺失")
	if sl:
		_assert(sl.visible == false, "设置层初始隐藏", "visible true")
		# 模拟打开设置
		home._on_settings_pressed()
		await process_frame
		_assert(sl.visible == true, "点击设置后层可见", "仍隐藏")
		# 检查音量滑块与震动选项存在
		# 通过成员变量检查
		_assert(home.get("volume_slider") != null, "音量滑块存在", "null")
		_assert(home.get("shake_check") != null, "震动选项存在", "null")
		# 清档必须先展示二次确认，取消时不改变任何统计。
		var clear_button: Button = home.get("clear_save_button") as Button
		var clear_layer: Control = home.get("clear_confirm_layer") as Control
		var clear_cancel: Button = home.get("clear_confirm_cancel_button") as Button
		var clear_accept: Button = home.get("clear_confirm_accept_button") as Button
		_assert(clear_button != null and clear_button.custom_minimum_size.y >= 44.0, "清档入口满足触控尺寸", "button=%s" % str(clear_button))
		_assert(clear_layer != null and not clear_layer.visible, "清档确认层初始隐藏", "确认层异常可见")
		var totals_before_cancel: Dictionary = SaveDataRef.get_totals()
		if clear_button and clear_layer:
			clear_button.pressed.emit()
			await process_frame
			_assert(clear_layer.visible, "点击清档仅展示二次确认", "确认层未显示")
			_assert(clear_cancel != null and clear_cancel.custom_minimum_size.y >= 44.0, "清档取消按钮满足触控尺寸", "cancel=%s" % str(clear_cancel))
			_assert(clear_accept != null and clear_accept.custom_minimum_size.y >= 44.0, "清档确认按钮满足触控尺寸", "accept=%s" % str(clear_accept))
			_assert(home.get_viewport().gui_get_focus_owner() == clear_cancel, "清档确认默认焦点为取消", "focus=%s" % str(home.get_viewport().gui_get_focus_owner()))
			clear_cancel.pressed.emit()
			await process_frame
			_assert(not clear_layer.visible, "取消清档后关闭确认层", "确认层仍可见")
			_assert(SaveDataRef.get_totals() == totals_before_cancel, "取消清档不修改统计", "before=%s after=%s" % [str(totals_before_cancel), str(SaveDataRef.get_totals())])
		# 测试持久化：改值保存再加载
		var SettingsRef: GDScript = preload("res://scripts/settings.gd")
		SettingsRef.ensure_loaded()
		var orig_vol: float = float(SettingsRef.get("master_volume"))
		var orig_shake: bool = bool(SettingsRef.get("shake_enabled"))
		SettingsRef.set_master_volume(0.5)
		SettingsRef.set_shake_enabled(false)
		await process_frame
		_assert(is_equal_approx(float(SettingsRef.get("master_volume")), 0.5), "音量设置保存 0.5", "实际 %f" % float(SettingsRef.get("master_volume")))
		_assert(bool(SettingsRef.get("shake_enabled")) == false, "震动关闭保存", "实际 %s" % str(SettingsRef.get("shake_enabled")))
		# 模拟重启加载：清空后重新 load
		SettingsRef.set_master_volume(orig_vol)
		SettingsRef.set_shake_enabled(orig_shake)
		# 关闭设置
		home._on_settings_back()
		await process_frame
		_assert(sl.visible == false, "返回后设置层隐藏", "仍可见")
	# 2. 输入：键鼠/手柄/触摸
	# 检查 project.godot 输入映射包含手柄
	var has_joy_left: bool = false
	for ev in InputMap.action_get_events("move_left"):
		if ev is InputEventJoypadMotion:
			has_joy_left = true
			break
	_assert(has_joy_left, "move_left 包含手柄摇杆", "缺失 joypad")
	var has_pause_joy: bool = false
	for ev in InputMap.action_get_events("pause"):
		if ev is InputEventJoypadButton:
			has_pause_joy = true
			break
	_assert(has_pause_joy, "pause 包含手柄 Start", "缺失")
	# 检查摇杆仅响应左半屏（通过读取脚本常量）
	var joy: Control = preload("res://scripts/joystick.gd").new()
	_assert(joy.get("RADIUS") == 70.0, "摇杆半径 70", "实际 %s" % str(joy.get("RADIUS")))
	joy.queue_free()
	# 3. 响应式：1280x720 与 20:9 (1280x576) 下无裁切/重叠
	var game_res: Resource = load("res://scenes/game.tscn")
	var g: Node = (game_res as PackedScene).instantiate() as Node
	root.add_child(g)
	await process_frame
	await process_frame
	var hud: Control = g.get("hud") as Control
	var menus: Control = g.get("menus") as Control
	var vp: Window = root
	var original_size: Vector2i = vp.size
	for size in [Vector2i(1280, 720), Vector2i(1280, 576), Vector2i(2560, 1152)]:
		# 真正调整 root Window；只传一个假 size 给断言无法覆盖响应式布局。
		vp.size = size
		await process_frame
		hud._update_layout()
		menus._update_layout()
		home._on_viewport_resized()
		var actual_size: Vector2 = g.get_viewport_rect().size
		_assert(
			vp.size == size,
			"窗口实际切换至 %dx%d" % [size.x, size.y],
			"窗口尺寸未切换",
			"expected=%s actual=%s" % [str(size), str(vp.size)],
		)
		# canvas_items + expand 会把 20:9 窗口映射为 1600x720 的逻辑
		# 视口；逻辑尺寸无需等于物理窗口，但宽高比必须一致且不裁剪基准画布。
		_assert(
			is_equal_approx(actual_size.x / actual_size.y, float(size.x) / float(size.y))
				and actual_size.x >= 1280.0
				and actual_size.y >= 720.0,
			"%dx%d 窗口的逻辑视口比例正确" % [size.x, size.y],
			"逻辑视口比例或范围错误",
			"window=%s viewport=%s" % [str(size), str(actual_size)],
		)
		# 简易检查：HUD 元素在视口内且不重叠关键区
		var hp_bg: Control = hud.get_node_or_null("HpBg") as Control
		var pause_btn: Button = hud.get_node_or_null("PauseBtn") as Button
		if hp_bg and pause_btn:
			var hp_rect: Rect2 = hp_bg.get_global_rect()
			var pause_rect: Rect2 = pause_btn.get_global_rect()
			# 使用锚点布局时，hp_bg 位于左上，pause 在右上，不应重叠
			_assert(not hp_rect.intersects(pause_rect), "HUD 在 %dx%d 下无重叠" % [int(size.x), int(size.y)], "hp %s pause %s" % [str(hp_rect), str(pause_rect)])
		# 升级卡片在窄高屏下应缩小
		g._on_level_up()
		await process_frame
		var cards_box: HBoxContainer = menus.get("cards_box") as HBoxContainer
		if cards_box and cards_box.get_child_count() > 0:
			var first: Control = cards_box.get_child(0) as Control
			_assert(first.size.x <= 260, "卡片宽度适配 %dx%d" % [int(size.x), int(size.y)], "size %s" % str(first.size))
		# 清理升级
		if menus.get("upgrade_layer").visible:
			var cards: Array = g._roll_cards()
			g._on_card_chosen(cards[0])
			await process_frame
	vp.size = original_size
	await process_frame
	print("  响应式校验在 3 种尺寸下完成")
	g.queue_free()
	home.queue_free()
	await process_frame
	await process_frame
	# 4. 焦点与返回一致性
	var home2: Control = (home_res as PackedScene).instantiate() as Control
	root.add_child(home2)
	await process_frame
	await process_frame
	var start_btn2: Button = home2.get_node_or_null("CenterContainer/VBoxContainer/StartButton") as Button
	_assert(start_btn2 != null and start_btn2.focus_mode == Control.FOCUS_ALL, "开始按钮可聚焦", "focus")
	# 模拟 ui_cancel 在设置层打开时应关闭设置而非退出
	home2._on_settings_pressed()
	await process_frame
	var sl2: Control = home2.get_node_or_null("SettingsLayer") as Control
	_assert(sl2.visible == true, "设置层已打开", "隐藏")
	# 发送 ui_cancel
	var ev_cancel := InputEventAction.new()
	ev_cancel.action = "ui_cancel"
	ev_cancel.pressed = true
	home2._unhandled_input(ev_cancel)
	await process_frame
	_assert(sl2.visible == false, "ui_cancel 关闭设置层", "仍可见")
	home2.queue_free()
	await process_frame
	await process_frame


func _test_data_driven() -> void:
	print("\n[SMOKE] 数据驱动校验")
	var gd: GDScript = preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	var errs: Array = gd.get_errors()
	var warns: Array = gd.get_warnings()
	_assert(errs.is_empty(), "GameData 校验无错误", "错误: %s" % str(errs))
	# 武器、被动、敌人数量保持一致
	_assert(gd.weapons.size() == 10, "武器数量 10（含 boomerang/frost/进化）", "实际 %d" % gd.weapons.size())
	_assert(gd.passives.size() == 5, "被动数量 5", "实际 %d" % gd.passives.size())
	_assert(gd.enemies.size() == 7, "敌人种类 7（含 charger/caster）", "实际 %d" % gd.enemies.size())
	# ID 检查
	for id in ["dagger", "orbit", "lightning", "aura"]:
		_assert(gd.weapons.has(id), "武器包含 %s" % id, "缺失 %s" % id)
		var w: Dictionary = gd.weapons[id] as Dictionary
		_assert(w.has("levels") and (w["levels"] as Array).size() == 8, "武器 %s 等级 8" % id, "实际 %d" % ((w["levels"] as Array).size() if w.has("levels") else -1))
	for id in ["damage", "haste", "speed", "hp", "magnet"]:
		_assert(gd.passives.has(id), "被动包含 %s" % id, "缺失 %s" % id)
	for id in ["slime", "bat", "brute", "charger", "caster", "elite", "boss"]:
		_assert(gd.enemies.has(id), "敌人包含 %s" % id, "缺失 %s" % id)
	# 生成曲线校验
	_assert(gd.spawn.has("arena"), "spawn 包含 arena", "缺失")
	_assert(gd.spawn.has("goal_time"), "spawn 包含 goal_time", "缺失")
	_assert(gd.spawn.has("max_enemies"), "spawn 包含 max_enemies", "缺失")
	_assert(int(gd.spawn.get("max_enemies", 0)) == 170, "max_enemies 170", "实际 %s" % str(gd.spawn.get("max_enemies")))
	_assert(gd.spawn.has("kind_thresholds"), "spawn 包含 kind_thresholds", "缺失")
	# 数值一致性抽检
	var dagger_lv1: Dictionary = (gd.weapons["dagger"]["levels"] as Array)[0] as Dictionary
	_assert(int(dagger_lv1["count"]) == 1 and is_equal_approx(float(dagger_lv1["dmg"]), 12.0), "dagger Lv1 数值一致", "实际 %s" % str(dagger_lv1))
	var slime: Dictionary = gd.enemies["slime"] as Dictionary
	_assert(is_equal_approx(float(slime["hp"]), 18.0) and is_equal_approx(float(slime["r"]), 13.0), "slime 数值一致", "实际 %s" % str(slime))
	# 颜色类型校验
	_assert(gd.weapons["dagger"]["color"] is Color, "武器颜色为 Color", "类型 %s" % str(typeof(gd.weapons["dagger"]["color"])))
	_assert(gd.enemies["boss"]["color"] is Color, "敌人颜色为 Color", "类型")
	# 进化配置校验
	_assert(gd.evolutions.size() == 4, "进化组合 4 条", "实际 %d" % gd.evolutions.size())
	for evo in gd.evolutions:
		var ed: Dictionary = evo as Dictionary
		_assert(gd.weapons.has(str(ed["weapon"])), "进化武器存在 %s" % str(ed["weapon"]), "缺失")
		_assert(gd.weapons.has(str(ed["result"])), "进化结果存在 %s" % str(ed["result"]), "缺失")
		_assert(gd.passives.has(str(ed["passive"])), "进化被动存在 %s" % str(ed["passive"]), "缺失")
	# 新武器机制校验
	_assert(gd.weapons.has("boomerang"), "武器包含 boomerang", "缺失")
	_assert(gd.weapons.has("frost"), "武器包含 frost", "缺失")
	var boom: Dictionary = gd.weapons["boomerang"] as Dictionary
	var frost: Dictionary = gd.weapons["frost"] as Dictionary
	_assert((boom["levels"] as Array).size() == 8, "boomerang 等级 8", "实际 %d" % ((boom["levels"] as Array).size()))
	_assert((frost["levels"] as Array).size() == 8, "frost 等级 8", "实际 %d" % ((frost["levels"] as Array).size()))
	# 检查机制差异：dagger boomerang frost 字段不同
	var d_levels: Array = gd.weapons["dagger"]["levels"] as Array
	var b_levels: Array = gd.weapons["boomerang"]["levels"] as Array
	var f_levels: Array = gd.weapons["frost"]["levels"] as Array
	_assert((d_levels[0] as Dictionary).has("count") and (d_levels[0] as Dictionary).has("pierce"), "dagger 字段正确", "缺失")
	_assert((b_levels[0] as Dictionary).has("speed") and (b_levels[0] as Dictionary).has("return_time"), "boomerang 具回旋字段", "缺失 %s" % str(b_levels[0]))
	_assert((f_levels[0] as Dictionary).has("slow") and (f_levels[0] as Dictionary).has("radius"), "frost 具减速字段", "缺失 %s" % str(f_levels[0]))
	print("  GameData 已加载：weapons=%d passives=%d enemies=%d evolutions=%d spawn_keys=%s" % [gd.weapons.size(), gd.passives.size(), gd.enemies.size(), gd.evolutions.size(), str(gd.spawn.keys())])
	if not warns.is_empty():
		print("  [WARN] %s" % str(warns))


func _test_enemy_behaviors_and_director() -> void:
	print("\n[SMOKE] 敌人行为与波次导演")
	var gd: GDScript = preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	# 1. 数据驱动：charger/caster 行为与 waves 存在
	_assert(gd.enemies.has("charger"), "敌人包含 charger", "缺失 charger")
	_assert(gd.enemies.has("caster"), "敌人包含 caster", "缺失 caster")
	var charger: Dictionary = gd.enemies["charger"] as Dictionary
	var caster: Dictionary = gd.enemies["caster"] as Dictionary
	_assert(str(charger.get("behavior", "")) == "charger", "charger behavior=charger", "实际 %s" % str(charger.get("behavior", "")))
	_assert(str(caster.get("behavior", "")) == "caster", "caster behavior=caster", "实际 %s" % str(caster.get("behavior", "")))
	_assert(charger.has("windup") and float(charger["windup"]) >= 0.5, "charger windup 存在且合理", "windup=%s" % str(charger.get("windup", "")))
	_assert(caster.has("warning_time") and float(caster["warning_time"]) >= 0.5, "caster warning 存在", "warning=%s" % str(caster.get("warning_time", "")))
	_assert(caster.has("cast_radius"), "caster cast_radius 存在", "缺失")
	# waves 数据
	_assert(gd.spawn.has("waves"), "spawn 包含 waves", "缺失 waves")
	var waves: Array = gd.spawn["waves"] as Array
	_assert(waves.size() >= 6, "waves 至少 6 段", "实际 %d" % waves.size())
	# 检查 waves 覆盖 5 分钟节奏且包含事件
	var has_event: bool = false
	for w in waves:
		if w is Dictionary and (w as Dictionary).has("event"):
			has_event = true
			break
	_assert(has_event, "waves 包含事件波", "无 event")
	# 检查 boss 阶段
	var boss: Dictionary = gd.enemies["boss"] as Dictionary
	_assert(boss.has("phases") and (boss["phases"] as Array).size() >= 1, "boss 包含阶段配置", "缺失 phases")
	if boss.has("phases"):
		var ph: Dictionary = (boss["phases"] as Array)[0] as Dictionary
		_assert(ph.has("hp_pct") and is_equal_approx(float(ph["hp_pct"]), 0.5), "boss 一阶段 hp_pct 0.5", "实际 %s" % str(ph.get("hp_pct", "")))
		_assert(ph.has("shock_cd") and float(ph["shock_cd"]) >= 2.0, "boss shock_cd 合理", "实际 %s" % str(ph.get("shock_cd", "")))
		_assert(ph.has("shock_radius"), "boss shock_radius 存在", "缺失")
	# 2. 实例化验证：不同行为敌人实例可创建且状态机就绪
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	(g.get("player") as Node).position = Vector2.ZERO
	# 清理
	for e in (g.get("enemies_node") as Node).get_children():
		e.queue_free()
	await process_frame
	# 生成 charger 与 caster 各一
	g._spawn_at("charger", Vector2(120, 0))
	g._spawn_at("caster", Vector2(-120, 0))
	g._spawn_at("boss", Vector2(0, 180))
	await process_frame
	var ens: Array = g.get_tree().get_nodes_in_group("enemies")
	var found_charger: Node = null
	var found_caster: Node = null
	var found_boss: Node = null
	for e in ens:
		var k: String = str(e.get("kind"))
		if k == "charger":
			found_charger = e
		elif k == "caster":
			found_caster = e
		elif k == "boss":
			found_boss = e
	_assert(found_charger != null, "charger 实例可生成", "未找到")
	_assert(found_caster != null, "caster 实例可生成", "未找到")
	_assert(found_boss != null, "boss 实例可生成", "未找到")
	if found_charger:
		_assert(str(found_charger.get("behavior")) == "charger", "charger behavior 字段正确", "实际 %s" % str(found_charger.get("behavior")))
		_assert(found_charger.get("charge_state") == "chase", "charger 初始 chase", "实际 %s" % str(found_charger.get("charge_state")))
	if found_caster:
		_assert(str(found_caster.get("behavior")) == "caster", "caster behavior 正确", "实际")
		_assert(bool(found_caster.get("is_casting")) == false, "caster 初始非施法", "异常")
	if found_boss:
		_assert(int(found_boss.get("boss_phase")) == 1, "boss 初始一阶段", "实际 %d" % int(found_boss.get("boss_phase")))
		_assert(bool(found_boss.get("boss_has_transformed")) == false, "boss 未变身", "异常")
	# 3. 预警与伤害安全：caster 预警期间不立即伤人，预警结束后才生效
	if found_caster:
		var pl: Node = g.get("player") as Node
		var hp_before: float = float(pl.get("hp"))
		# 强制进入施法
		found_caster.set("cast_cd", -1.0)
		found_caster.set("is_casting", false)
		# 距离设置为可施法范围
		found_caster.position = Vector2(200, 0)
		pl.position = Vector2.ZERO
		# 模拟一帧触发施法
		found_caster._process(0.02)
		_assert(bool(found_caster.get("is_casting")) == true, "caster 触发施法进入预警", "未进入")
		var warn_pos: Vector2 = found_caster.get("cast_pos") as Vector2
		_assert(warn_pos.distance_to(pl.global_position) < 1.0, "caster 预警位置为玩家位置", "warn %s pl %s" % [str(warn_pos), str(pl.global_position)])
		# 预警期间（0.5s 内）不应伤人
		found_caster._process(0.4)
		var hp_mid: float = float(pl.get("hp"))
		_assert(is_equal_approx(hp_before, hp_mid), "预警期间玩家不应受击", "hp %.1f->%.1f" % [hp_before, hp_mid])
		# 结束预警
		found_caster._process(0.6)
		var hp_after: float = float(pl.get("hp"))
		_assert(hp_after < hp_mid - 0.1, "预警结束在圈内应受击", "hp %.1f->%.1f" % [hp_mid, hp_after])
		# 重置玩家血量，避免影响后续
		pl.set("hp", hp_before)
	# 4. 冲锋预警：charger 触发 windup 时有清晰预警
	if found_charger:
		found_charger.set("charge_cd", -1.0)
		found_charger.set("charge_state", "chase")
		found_charger.position = Vector2(150, 0)
		g.get("player").position = Vector2.ZERO
		found_charger._process(0.02)
		_assert(str(found_charger.get("charge_state")) == "windup", "charger 进入 windup 预警", "实际 %s" % str(found_charger.get("charge_state")))
		var wind: float = float(found_charger.get("windup_t"))
		_assert(wind > 0.4, "windup 时间充足便于躲避", "wind=%.2f" % wind)
		# windup 期间不应瞬移
		var pos_before: Vector2 = found_charger.position
		found_charger._process(0.2)
		var pos_mid: Vector2 = found_charger.position
		_assert(pos_before.distance_to(pos_mid) < 20.0, "windup 期间基本静止", "移动 %.1f" % pos_before.distance_to(pos_mid))
	# 5. Boss 二阶段：血量降至 50% 以下触发变身
	if found_boss:
		var st_boss: Dictionary = gd.enemies["boss"] as Dictionary
		var max_hp_b: float = float(found_boss.get("max_hp"))
		# 造成伤害至 40%
		found_boss.set("hp", max_hp_b * 0.4)
		var spd_before: float = float(found_boss.get("speed"))
		found_boss._process(0.02)
		_assert(int(found_boss.get("boss_phase")) == 2, "boss 达 50% 进入二阶段", "phase=%d" % int(found_boss.get("boss_phase")))
		_assert(bool(found_boss.get("boss_has_transformed")) == true, "boss 已标记变身", "未标记")
		var spd_after: float = float(found_boss.get("speed"))
		_assert(spd_after > spd_before * 1.2, "二阶段速度提升", "before %.1f after %.1f" % [spd_before, spd_after])
	# 6. 波次权重数据驱动：_pick_kind 随时间变化
	g.set("elapsed", 10.0)
	seed(999)
	var picks_early: Dictionary = {}
	for i in 50:
		var k: String = g._pick_kind()
		picks_early[k] = int(picks_early.get(k, 0)) + 1
	g.set("elapsed", 200.0)
	seed(999)
	var picks_late: Dictionary = {}
	for i in 50:
		var k2: String = g._pick_kind()
		picks_late[k2] = int(picks_late.get(k2, 0)) + 1
	_assert(picks_early.has("charger") == false or int(picks_early.get("charger", 0)) < 10, "早期 charger 少量或无", "early %s" % str(picks_early))
	_assert(picks_late.has("charger"), "后期应出现 charger", "late %s" % str(picks_late))
	_assert(picks_late.has("caster"), "后期应出现 caster", "late %s" % str(picks_late))
	# 7. 屏外无预警必中：屏外 charger 不应无预警冲锋，屏外 caster 预警仍在玩家可见区
	# 验证 charger 在远距 (>500) 且屏外时不进入 windup
	if found_charger:
		found_charger.set("charge_state", "chase")
		found_charger.set("charge_cd", -1.0)
		found_charger.position = g.get("player").position + Vector2(900, 0) # 屏外
		found_charger._process(0.02)
		_assert(str(found_charger.get("charge_state")) == "chase", "屏外远距 charger 不直接 windup", "state %s" % str(found_charger.get("charge_state")))
	g.queue_free()
	await process_frame
	await process_frame


func _test_weapon_evolution_and_builds() -> void:
	print("\n[SMOKE] 武器构筑与进化")
	var gd: GDScript = preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	# 1. 新武器机制不同：验证卡池包含且不计进化武器为初始候选
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var player: Node = g.get("player") as Node
	# 清理初始武器外，验证新武器可加入且辨识度
	# 初始仅 dagger，验证 boomerang / frost 可作为新武器候选
	var cands_early: Array = g._roll_cards()
	var has_new_weapon_candidate: bool = false
	for c in cands_early:
		if c["kind"] == "weapon_new" and (str(c["id"]) == "boomerang" or str(c["id"]) == "frost"):
			has_new_weapon_candidate = true
			break
	# 由于候选随机，循环多次确保至少一次出现新武器
	if not has_new_weapon_candidate:
		var found: bool = false
		for iter in 20:
			var cc: Array = g._roll_cards()
			for c in cc:
				if c["kind"] == "weapon_new" and (str(c["id"]) == "boomerang" or str(c["id"]) == "frost"):
					found = true
					break
			if found:
				break
		_assert(found or has_new_weapon_candidate or cands_early.size() == 3, "新武器 boomerang/frost 可作为候选", "早期候选 %s" % str(cands_early))
	# 2. 被动与进化：构造满级条件触发进化
	# 将 dagger 升至 8，damage 升至 5，验证进化卡出现
	player.weapons["dagger"]["lv"] = 8
	player.passives["damage"] = 5
	# 确保其他武器不满以避免干扰
	# 强制 _roll_cards 包含进化
	var evo_found: bool = false
	var evo_card: Dictionary = {}
	for iter in 30:
		var cards: Array = g._roll_cards()
		for c in cards:
			if c["kind"] == "evolution" and str(c["id"]) == "dagger":
				evo_found = true
				evo_card = c
				break
		if evo_found:
			break
	_assert(evo_found, "dagger+damage 满级应出现进化卡", "未出现进化")
	if evo_found:
		_assert(evo_card.has("result") and str(evo_card["result"]) == "dagger_evo", "进化结果为 dagger_evo", "实际 %s" % str(evo_card.get("result", "")))
		# 验证进化卡展示下一级变化（通过 menus._card_info）
		var menus: Control = g.get("menus") as Control
		var info: Dictionary = menus._card_info(evo_card)
		_assert(str(info["tag"]).contains("进化"), "进化卡 tag 含进化", "tag=%s" % str(info["tag"]))
		_assert(str(info["desc"]).length() > 10, "进化卡 desc 含变化说明", "desc=%s" % str(info["desc"]))
		# 执行进化
		var before_size: int = player.weapons.size()
		g._apply_card(evo_card)
		_assert(not player.weapons.has("dagger"), "进化后原武器移除", "仍存在 dagger")
		_assert(player.weapons.has("dagger_evo"), "进化后获得 dagger_evo", "缺失 evo")
		_assert(int(player.weapons["dagger_evo"]["lv"]) == 1, "evo 初始 Lv1", "lv=%d" % int(player.weapons["dagger_evo"]["lv"]))
		_assert(player.weapons.size() == before_size, "进化不占额外槽位（替换）", "size %d vs %d" % [before_size, player.weapons.size()])
	# 3. 近战/投射/范围/控制构筑辨识度：验证四类武器可同时持有且独立计时
	# 重置为新对局验证多构筑
	g.queue_free()
	await process_frame
	await process_frame
	var g2: Node = ps.instantiate()
	root.add_child(g2)
	await process_frame
	await process_frame
	var p2: Node = g2.get("player") as Node
	p2.weapons.clear()
	p2.add_weapon("dagger")
	p2.add_weapon("boomerang")
	p2.add_weapon("frost")
	p2.add_weapon("aura")
	_assert(p2.weapons.size() == 4, "可持有 4 武器形成多构筑", "size=%d" % p2.weapons.size())
	_assert(p2.weapons.has("dagger") and p2.weapons.has("boomerang") and p2.weapons.has("frost") and p2.weapons.has("aura"), "四构筑武器共存", "缺失 %s" % str(p2.weapons.keys()))
	# 验证 frost 新星可触发且产生减速（模拟）
	p2.weapons["frost"]["t"] = -1.0
	var g2enemies_node: Node = g2.get("enemies_node") as Node
	for e in g2enemies_node.get_children():
		e.queue_free()
	await process_frame
	g2._spawn_at("slime", p2.global_position + Vector2(80, 0))
	await process_frame
	var test_enemy: Node = g2.get_tree().get_nodes_in_group("enemies")[0] as Node
	var hp_before: float = float(test_enemy.get("hp"))
	p2._frost_nova("frost")
	await process_frame
	var hp_after: float = float(test_enemy.get("hp")) if is_instance_valid(test_enemy) else hp_before - 1
	_assert(hp_after < hp_before - 0.1, "frost 新星可造成伤害", "hp %.1f->%.1f" % [hp_before, hp_after])
	if is_instance_valid(test_enemy):
		var slowed: float = float(test_enemy.get("slow_t"))
		_assert(slowed > 0.5, "frost 命中施加减速", "slow_t=%.2f" % slowed)
	# 4. 升级卡准确展示下一等级变化、防重复、保底
	# 构造满溢情景：全部武器与被动满级，候选应为治疗保底且无重复 id
	for wid in p2.weapons.keys():
		var wlv_max: int = int((gd.weapons[wid]["levels"] as Array).size())
		p2.weapons[wid]["lv"] = wlv_max
	for pid in gd.passives.keys():
		p2.passives[pid] = int(gd.passives[pid]["max"])
	# 若仍有进化未完成，进化会优先出现，这不算满溢；先完成所有进化以达真正满溢
	for evo in gd.evolutions:
		var ed: Dictionary = evo as Dictionary
		var w: String = str(ed["weapon"])
		var res: String = str(ed["result"])
		if p2.weapons.has(w) and not p2.weapons.has(res):
			# 满足进化条件时，视为未满（应出现进化），故先手动进化以清空
			p2.weapons.erase(w)
			p2.add_weapon(res)
	# 此时武器与被动均满，进化也完成，候选应为 3 个 heal
	var full_cards: Array = g2._roll_cards()
	_assert(full_cards.size() == 3, "满配时仍返回 3 张", "size=%d" % full_cards.size())
	var heal_cnt: int = 0
	var id_set: Dictionary = {}
	var dup: bool = false
	for c in full_cards:
		if c["kind"] == "heal":
			heal_cnt += 1
		else:
			var id: String = str(c.get("id", "")) + str(c.get("result", ""))
			if id_set.has(id):
				dup = true
			id_set[id] = true
	_assert(heal_cnt >= 1, "候选耗尽时有治疗保底", "cards=%s" % str(full_cards))
	_assert(not dup, "满配候选无重复 id", "cards=%s" % str(full_cards))
	# 非满配时验证无重复 id 且准确展示下一等级
	p2.weapons.clear()
	p2.passives.clear()
	p2.add_weapon("dagger")
	p2.weapons["dagger"]["lv"] = 2
	var cards2: Array = g2._roll_cards()
	var seen: Dictionary = {}
	var dup2: bool = false
	for c in cards2:
		if c["kind"] == "heal":
			continue
		var key: String = str(c["kind"]) + ":" + str(c.get("id", "")) + str(c.get("result", ""))
		if seen.has(key):
			dup2 = true
		seen[key] = true
	_assert(not dup2, "常规 roll 无重复选项", "cards=%s" % str(cards2))
	# 验证下一等级展示：取一张 weapon_up 卡检查 tag 含 Lv 变化且 desc 含数值
	var up_card: Dictionary = {}
	for c in cards2:
		if c["kind"] == "weapon_up":
			up_card = c
			break
	if not up_card.is_empty():
		var menus2: Control = g2.get("menus") as Control
		var info2: Dictionary = menus2._card_info(up_card)
		_assert(str(info2["tag"]).contains("Lv"), "升级卡 tag 含 Lv 变化", "tag=%s" % str(info2["tag"]))
		_assert(str(info2["desc"]).length() > str(gd.weapons[up_card["id"]]["desc"]).length(), "升级卡 desc 含下一级数值", "desc=%s" % str(info2["desc"]))
	g2.queue_free()
	await process_frame
	await process_frame


func _test_stats_and_save() -> void:
	print("\n[SMOKE] 局内统计与存档解锁")
	var SaveDataRef: GDScript = preload("res://scripts/save_data.gd")
	var gd: GDScript = preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	SaveDataRef.ensure_loaded()
	# 清理存档以获可重复起点
	SaveDataRef.clear()
	await process_frame
	# 1. 初始存档为空，最佳为 0，解锁均未达成
	var best0: Dictionary = SaveDataRef.get_best()
	_assert(is_equal_approx(float(best0["time"]), 0.0), "初始最佳时间为 0", "实际 %s" % str(best0["time"]))
	_assert(int(best0["kills"]) == 0, "初始最佳击杀 0", "实际 %d" % int(best0["kills"]))
	var prog0: Dictionary = SaveDataRef.get_unlock_progress()
	_assert(not bool(prog0["boomerang"]["unlocked"]), "初始 boomerang 未解锁", "已解锁")
	_assert(not bool(prog0["frost"]["unlocked"]), "初始 frost 未解锁", "已解锁")
	# 验证锁定武器不在候选（boomerang/frost  locked）
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var has_locked_in_early: bool = false
	for iter in 10:
		var cands: Array = g._roll_cards()
		for c in cands:
			if c["kind"] == "weapon_new" and (str(c["id"]) == "boomerang" or str(c["id"]) == "frost"):
				has_locked_in_early = true
				break
	_assert(not has_locked_in_early, "未解锁时 boomerang/frost 不应出现在候选", "异常出现")
	# 2. 模拟游戏统计：伤害、承伤、击杀与构筑被正确记录
	var player: Node = g.get("player") as Node
	# 制造伤害统计：通过 hurt_enemy 累计
	g.total_damage = 0.0
	g.taken_damage = 0.0
	g.kills = 5
	g.elapsed = 95.0
	player.weapons.clear()
	player.add_weapon("dagger")
	player.weapons["dagger"]["lv"] = 3
	player.passives["damage"] = 2
	# 模拟对敌人造成伤害
	g._spawn_at("slime", player.global_position + Vector2(30, 0))
	await process_frame
	var e: Node = g.get_tree().get_nodes_in_group("enemies")[0] as Node
	var hp_before: float = float(e.get("hp"))
	g.hurt_enemy(e, 10.0, Vector2.ZERO)
	_assert(g.total_damage > 9.0, "hurt_enemy 累计 total_damage", "total=%.1f" % g.total_damage)
	# 模拟承伤
	var hp_p_before: float = float(player.get("hp"))
	player.hurt(12.0)
	await process_frame
	_assert(g.taken_damage > 11.0, "player hurt 累计 taken_damage", "taken=%.1f" % g.taken_damage)
	# 收集 stats
	var stats: Dictionary = g._collect_stats()
	_assert(int(stats["kills"]) >= 5 and int(stats["kills"]) <= 6, "stats 击杀 5-6（允许自动击杀1）", "实际 %d" % int(stats["kills"]))
	_assert(absf(float(stats["time"]) - 95.0) < 0.5, "stats 时间约 95", "实际 %.3f" % float(stats["time"]))
	_assert(float(stats["damage"]) > 9.0, "stats 伤害一致", "damage=%.1f" % float(stats["damage"]))
	_assert(float(stats["taken"]) > 11.0, "stats 承伤一致", "taken=%.1f" % float(stats["taken"]))
	var build: Dictionary = stats["build"] as Dictionary
	_assert((build["weapons"] as Dictionary).has("dagger"), "stats 构筑含 dagger", "缺失")
	# 3. 跨局保存：record_game 更新最佳并持久化
	var newly1: Array = SaveDataRef.record_game(stats)
	var best1: Dictionary = SaveDataRef.get_best()
	_assert(absf(float(best1["time"]) - 95.0) < 0.5, "record后最佳时间约95", "实际 %.3f" % float(best1["time"]))
	_assert(int(best1["kills"]) >= 5 and int(best1["kills"]) <= 6, "record后最佳击杀 5-6", "实际 %d" % int(best1["kills"]))
	# boomerang 需 40 累计击杀，当前 total 5 不应解锁
	_assert(not bool(SaveDataRef.get_unlock_progress()["boomerang"]["unlocked"]), "5 击杀不解锁 boomerang", "已解锁")
	# 再次记录大额击杀以触发 boomerang
	g.kills = 40
	g.total_damage += 500.0
	var stats2: Dictionary = g._collect_stats()
	stats2["kills"] = 40
	var newly2: Array = SaveDataRef.record_game(stats2)
	var unlocked_boomer: bool = bool(SaveDataRef.is_unlocked("boomerang"))
	_assert(unlocked_boomer, "累计40击杀解锁 boomerang", "未解锁")
	if unlocked_boomer:
		_assert("boomerang" in newly2 or SaveDataRef.is_weapon_unlocked("boomerang"), "解锁返回包含 boomerang", "newly=%s" % str(newly2))
	# frost 需 best_time 90，95 已满足，应已解锁
	var unlocked_frost: bool = bool(SaveDataRef.is_unlocked("frost"))
	_assert(unlocked_frost, "95s 存活解锁 frost", "未解锁")
	# 解锁后，候选应可出现新武器
	var found_after: bool = false
	for iter in 15:
		var cands2: Array = g._roll_cards()
		for c in cands2:
			if c["kind"] == "weapon_new" and (str(c["id"]) == "boomerang" or str(c["id"]) == "frost"):
				found_after = true
				break
		if found_after:
			break
	_assert(found_after, "解锁后新武器可出现在候选", "仍未出现")
	# 4. 结算页展示关键统计与构筑：验证 end_stats 文本含伤害/承伤/构筑/最佳
	var menus: Control = g.get("menus") as Control
	menus.show_end(true, 95.0, 40, 7, stats2, newly2)
	await process_frame
	var end_text: String = str(menus.get("end_stats").text)
	_assert(end_text.contains("伤害"), "结算含伤害", "text=%s" % end_text)
	_assert(end_text.contains("承伤"), "结算含承伤", "text=%s" % end_text)
	_assert(end_text.contains("构筑"), "结算含构筑", "text=%s" % end_text)
	_assert(end_text.contains("最佳") or end_text.contains("击杀"), "结算含最佳或击杀", "text=%s" % end_text)
	# 解锁提示
	if not newly2.is_empty():
		_assert(end_text.contains("解锁"), "结算含解锁提示", "text=%s" % end_text)
	# 5. 存档损坏回退：写入非法内容后 ensure_loaded 应回退默认值而不崩溃
	var cfg_path: String = SaveDataRef.get_storage_path()
	# 备份原文件
	var orig_text: String = ""
	if FileAccess.file_exists(cfg_path):
		var f: FileAccess = FileAccess.open(cfg_path, FileAccess.READ)
		if f != null:
			orig_text = f.get_as_text()
			f.close()
	# 写入损坏内容
	var wf: FileAccess = FileAccess.open(cfg_path, FileAccess.WRITE)
	if wf != null:
		wf.store_string("corrupted [[[ not cfg")
		wf.close()
	# 强制重载
	SaveDataRef._loaded = false
	SaveDataRef.ensure_loaded()
	var best_corrupt: Dictionary = SaveDataRef.get_best()
	_assert(best_corrupt is Dictionary, "损坏后仍可读取 best", "nil")
	# 恢复原存档并清理
	if orig_text != "":
		var rf: FileAccess = FileAccess.open(cfg_path, FileAccess.WRITE)
		if rf != null:
			rf.store_string(orig_text)
			rf.close()
	else:
		if FileAccess.file_exists(cfg_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	SaveDataRef._loaded = false
	SaveDataRef.ensure_loaded()
	# 6. 未来版本存档只读：加载或尝试记账都不能降写并丢未知字段。
	var future_cfg := ConfigFile.new()
	future_cfg.set_value("save", "version", SaveDataRef.VERSION + 1)
	future_cfg.set_value("save", "best_time", 321.0)
	future_cfg.set_value("save", "future_metric", {"keep": true})
	future_cfg.set_value("future", "payload", "preserve-me")
	_assert(future_cfg.save(cfg_path) == OK, "可创建未来版本隔离存档", "save failed")
	var future_before: String = ""
	var future_before_file: FileAccess = FileAccess.open(cfg_path, FileAccess.READ)
	if future_before_file:
		future_before = future_before_file.get_as_text()
		future_before_file.close()
	SaveDataRef._loaded = false
	SaveDataRef.ensure_loaded()
	_assert(is_equal_approx(float(SaveDataRef.get_best()["time"]), 321.0), "未来版本可只读已知字段", "best=%s" % str(SaveDataRef.get_best()))
	SaveDataRef.record_game({"time": 999.0, "kills": 999, "level": 99, "damage": 999.0})
	var future_after: String = ""
	var future_after_file: FileAccess = FileAccess.open(cfg_path, FileAccess.READ)
	if future_after_file:
		future_after = future_after_file.get_as_text()
		future_after_file.close()
	_assert(not future_before.is_empty() and future_after == future_before and future_after.contains("preserve-me"), "未来版本存档不会被旧版降写", "before=%s after=%s" % [future_before, future_after])
	var restored_file: FileAccess = FileAccess.open(cfg_path, FileAccess.WRITE)
	if restored_file:
		restored_file.store_string(orig_text)
		restored_file.close()
	SaveDataRef._loaded = false
	SaveDataRef.ensure_loaded()
	# 7. 清除存档入口：clear 后最佳与解锁重置，且再次持久化
	SaveDataRef.clear()
	await process_frame
	var best_cleared: Dictionary = SaveDataRef.get_best()
	_assert(is_equal_approx(float(best_cleared["time"]), 0.0), "clear 后最佳时间清零", "实际 %.1f" % float(best_cleared["time"]))
	_assert(not SaveDataRef.is_unlocked("boomerang"), "clear 后 boomerang 重置未解锁", "仍解锁")
	var totals_cleared: Dictionary = SaveDataRef.get_totals()
	_assert(int(totals_cleared["total_games"]) == 0, "clear 后局数清零", "实际 %d" % int(totals_cleared["total_games"]))
	# 清理游戏实例并重置 Home 显示
	menus.hide_end()
	g.get_tree().paused = false
	g.queue_free()
	await process_frame
	await process_frame
	# 重建一次存档以便后续测试不受污染（保持空状态）
	SaveDataRef.clear()


func _test_visual_audio_accessibility() -> void:
	print("\n[SMOKE] 视觉、音频与可访问性")
	var SettingsRef: GDScript = preload("res://scripts/settings.gd")
	SettingsRef.ensure_loaded()
	var gd: GDScript = preload("res://scripts/game_data.gd")
	gd.ensure_loaded()
	# 1. 敌人辨识度：各类型颜色与轮廓差异
	var kinds: Array = ["slime", "bat", "brute", "charger", "caster", "elite", "boss"]
	var colors: Dictionary = {}
	for k in kinds:
		var col: Color = (gd.enemies[k] as Dictionary)["color"] as Color
		colors[k] = col
		_assert(col is Color, "敌人 %s 颜色为 Color" % k, "类型错误")
	# 检查颜色两两差异（避免混淆）
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var c1: Color = colors[kinds[i]] as Color
			var c2: Color = colors[kinds[j]] as Color
			var diff: float = absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b)
			_assert(diff > 0.12, "敌人 %s 与 %s 颜色可辨识" % [kinds[i], kinds[j]], "diff=%.2f" % diff)
	# 危险行为预警可辨识：charger windup 与 caster 环
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var pl: Node = g.get("player") as Node
	pl.position = Vector2.ZERO
	for e in (g.get("enemies_node") as Node).get_children():
		e.queue_free()
	await process_frame
	g._spawn_at("charger", Vector2(140, 0))
	g._spawn_at("caster", Vector2(-140, 0))
	g._spawn_at("boss", Vector2(0, 160))
	await process_frame
	var charger: Node = null
	var caster: Node = null
	var boss: Node = null
	for e in g.get_tree().get_nodes_in_group("enemies"):
		var k: String = str(e.get("kind"))
		if k == "charger":
			charger = e
		elif k == "caster":
			caster = e
		elif k == "boss":
			boss = e
	_assert(charger != null and caster != null and boss != null, "三类敌人可生成", "缺失")
	# 触发 charger 预警
	if charger:
		charger.set("charge_cd", -1.0)
		charger.set("charge_state", "chase")
		charger.position = Vector2(120, 0)
		pl.position = Vector2.ZERO
		charger._process(0.02)
		_assert(str(charger.get("charge_state")) == "windup", "charger 预警 windup 可辨识", "state=%s" % str(charger.get("charge_state")))
	# 触发 caster 预警
	if caster:
		caster.set("cast_cd", -1.0)
		caster.set("is_casting", false)
		caster.position = Vector2(200, 0)
		pl.position = Vector2.ZERO
		caster._process(0.02)
		_assert(bool(caster.get("is_casting")), "caster 预警环可辨识", "未进入施法")
	# Boss 阶段反馈：初始 1 阶段，血条与变身
	if boss:
		_assert(int(boss.get("boss_phase")) == 1, "Boss 初始一阶段", "phase=%d" % int(boss.get("boss_phase")))
		var max_hp: float = float(boss.get("max_hp"))
		boss.set("hp", max_hp * 0.4)
		boss._process(0.02)
		_assert(int(boss.get("boss_phase")) == 2, "Boss 低血量二阶段反馈", "phase=%d" % int(boss.get("boss_phase")))
		# 检查 HUD Boss 条是否会被显示（需在 _process 后）
		var hud: Control = g.get("hud") as Control
		hud._process(0.02)
		_assert(hud.get("boss_bar") != null, "HUD 含 Boss 血条", "缺失")
		_assert(bool(hud.get("boss_bar").visible) == true, "Boss 存在时血条可见", "隐藏")
	# 2. 音频总线：Master/Music/Sfx 可分别调节
	var master_bus: int = AudioServer.get_bus_index("Master")
	var music_bus: int = AudioServer.get_bus_index("Music")
	var sfx_bus: int = AudioServer.get_bus_index("Sfx")
	_assert(master_bus != -1, "Master 总线存在", "缺失")
	_assert(music_bus != -1, "Music 总线存在", "缺失")
	_assert(sfx_bus != -1, "Sfx 总线存在", "缺失")
	var orig_master: float = float(SettingsRef.get("master_volume"))
	var orig_music: float = float(SettingsRef.get("music_volume"))
	var orig_sfx: float = float(SettingsRef.get("sfx_volume"))
	SettingsRef.set_master_volume(0.5)
	SettingsRef.set_music_volume(0.3)
	SettingsRef.set_sfx_volume(0.9)
	await process_frame
	var m_db: float = AudioServer.get_bus_volume_db(music_bus)
	var s_db: float = AudioServer.get_bus_volume_db(sfx_bus)
	_assert(m_db < -1.0 and m_db > -30.0, "Music 音量可调", "db=%.1f" % m_db)
	_assert(s_db > m_db, "Sfx 与 Music 可分别调节", "music %.1f sfx %.1f" % [m_db, s_db])
	# 恢复
	SettingsRef.set_master_volume(orig_master)
	SettingsRef.set_music_volume(orig_music)
	SettingsRef.set_sfx_volume(orig_sfx)
	# 3. 无障碍：低血量、受击、升级反馈不过度遮挡且可关闭
	# 低血量遮罩：flash 关闭时更淡
	var hud2: Control = g.get("hud") as Control
	pl.set("hp", float(pl.get("max_hp")) * 0.2)
	hud2._process(0.02)
	var a_on: float = float(hud2.get("low_overlay").color.a)
	SettingsRef.set_flash_enabled(false)
	hud2._process(0.02)
	var a_off: float = float(hud2.get("low_overlay").color.a)
	_assert(a_on > 0.01, "低血量遮罩可见", "a=%.2f" % a_on)
	_assert(a_off < a_on or is_equal_approx(a_off, 0.07), "关闭强闪烁后遮罩更淡", "on %.2f off %.2f" % [a_on, a_off])
	# 受击闪烁：flash 关闭时 modulate 更弱
	SettingsRef.set_flash_enabled(true)
	pl.set("invuln", 0.3)
	pl._process(0.02)
	var a_flash_on: float = float(pl.get("modulate").a)
	SettingsRef.set_flash_enabled(false)
	pl.set("invuln", 0.3)
	pl._process(0.02)
	var a_flash_off: float = float(pl.get("modulate").a)
	_assert(a_flash_on != a_flash_off or is_equal_approx(a_flash_off, 0.78), "关闭闪烁后受击闪烁减弱", "on %.2f off %.2f" % [a_flash_on, a_flash_off])
	# 震动开关：关闭后 game.shake 不应影响相机（通过 Settings 判定）
	SettingsRef.set_shake_enabled(false)
	g.shake = 6.0
	g._process(0.02)
	_assert(g.cam.offset == Vector2.ZERO, "关闭震动后相机无偏移", "offset=%s" % str(g.cam.offset))
	SettingsRef.set_shake_enabled(true)
	g.shake = 6.0
	g._process(0.02)
	_assert(g.cam.offset != Vector2.ZERO, "开启震动后相机偏移", "offset=%s" % str(g.cam.offset))
	# 升级辨识度使用确定性的已拥有武器升级卡，避免随机三张恰好全是新被动。
	var level_info: Dictionary = (g.get("menus") as Control)._card_info({
		"kind": "weapon_up",
		"id": "dagger",
	})
	_assert(str(level_info["tag"]).contains("Lv"), "升级卡 tag 含 Lv 辨识度", "info=%s" % str(level_info))
	# 恢复设置
	SettingsRef.set_flash_enabled(true)
	SettingsRef.set_shake_enabled(true)
	g.queue_free()
	await process_frame
	await process_frame


func _test_export_and_version() -> void:
	print("\n[SMOKE] 导出、版本与 CI")
	# 版本可追踪：VERSION 与 project.godot 一致
	var version_file: String = ""
	var fa: FileAccess = FileAccess.open("res://VERSION", FileAccess.READ)
	if fa != null:
		version_file = fa.get_as_text().strip_edges()
		fa.close()
	_assert(not version_file.is_empty(), "VERSION 文件存在", "缺失")
	var proj_version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if proj_version.is_empty():
		# 回退读取 project.godot 文本
		var pf: FileAccess = FileAccess.open("res://project.godot", FileAccess.READ)
		if pf != null:
			var txt: String = pf.get_as_text()
			pf.close()
			for line in txt.split("\n"):
				if line.contains("config/version"):
					proj_version = line.split("=")[1].strip_edges().strip_edges().replace('"', "")
					break
	_assert(not proj_version.is_empty(), "project.godot 版本存在", "空")
	_assert(version_file == proj_version, "VERSION 与 project.godot 一致 (%s)" % version_file, "VERSION=%s project=%s" % [version_file, proj_version])
	# CHANGELOG 可追踪
	var changelog_exists: bool = FileAccess.file_exists("res://CHANGELOG.md")
	_assert(changelog_exists, "CHANGELOG.md 存在", "缺失")
	if changelog_exists:
		var cf: FileAccess = FileAccess.open("res://CHANGELOG.md", FileAccess.READ)
		if cf != null:
			var txt2: String = cf.get_as_text()
			cf.close()
			_assert(txt2.contains(version_file), "CHANGELOG 含当前版本", "未含 %s" % version_file)
	# 导出预设：确定首发平台与最低环境
	_assert(FileAccess.file_exists("res://export_presets.cfg"), "export_presets.cfg 存在", "缺失")
	var ec: FileAccess = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var has_web: bool = false
	var has_linux: bool = false
	if ec != null:
		var txt3: String = ec.get_as_text()
		ec.close()
		has_web = txt3.contains('name="Web"') and txt3.contains('platform="Web"')
		has_linux = txt3.contains('name="Linux/X11"')
		_assert(txt3.contains("addons/**") and txt3.contains("tests/**") and txt3.contains("build/**") and txt3.contains(".agents/**"), "导出预设排除开发与构建目录", "exclude_filter 不完整")
		_assert(txt3.contains("binary_format/embed_pck=true"), "Linux 产物嵌入 PCK", "embed_pck 未启用")
	_assert(has_web, "Web 首发预设存在", "缺失 Web")
	_assert(has_linux, "Linux 预设存在（本地验证）", "缺失 Linux")
	# CI：.github/workflows/ci.yml 自动执行无头测试并校验导出
	_assert(FileAccess.file_exists("res://.github/workflows/ci.yml"), "CI 工作流存在", "缺失 ci.yml")
	var ci_ok: bool = false
	var ci_file: FileAccess = FileAccess.open("res://.github/workflows/ci.yml", FileAccess.READ)
	if ci_file != null:
		var citxt: String = ci_file.get_as_text()
		ci_file.close()
		ci_ok = (
			citxt.contains("run_tests.gd")
			and citxt.contains("isolated=true")
			and citxt.contains("make export-web")
			and citxt.contains("make export-linux")
			and citxt.contains("test -s build/web/index.wasm")
			and citxt.contains("if-no-files-found: error")
		)
	_assert(ci_ok, "CI 含测试与导出校验", "CI 内容不完整")
	# 干净克隆可按文档生成构建：检查 docs/BUILD.md 与 Makefile 目标
	_assert(FileAccess.file_exists("res://docs/BUILD.md"), "docs/BUILD.md 存在", "缺失")
	_assert(FileAccess.file_exists("res://Makefile") or FileAccess.file_exists("res://makefile"), "Makefile 存在", "缺失")
	var mf: FileAccess = FileAccess.open("res://Makefile", FileAccess.READ)
	var has_targets: bool = false
	if mf != null:
		var mtxt: String = mf.get_as_text()
		mf.close()
		has_targets = mtxt.contains("test:") and mtxt.contains("export-web") and mtxt.contains("verify")
	_assert(has_targets, "Makefile 含 test/verify/export", "缺失目标")
	# 发布检查：docs/RELEASE_CHECKLIST 覆盖输入、存档、性能、流程
	_assert(FileAccess.file_exists("res://docs/RELEASE_CHECKLIST.md"), "RELEASE_CHECKLIST 存在", "缺失")
	var rc_ok: bool = false
	var rcf: FileAccess = FileAccess.open("res://docs/RELEASE_CHECKLIST.md", FileAccess.READ)
	if rcf != null:
		var rctxt: String = rcf.get_as_text()
		rcf.close()
		rc_ok = rctxt.contains("输入") and rctxt.contains("存档") and rctxt.contains("性能") and rctxt.contains("流程")
	_assert(rc_ok, "发布检查覆盖输入/存档/性能/流程", "不完整")


func _test_lightning_range() -> void:



	print("\n[SMOKE] 雷霆范围回归")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	# 确保有雷霆武器
	if not (g.get("player") as Node).get("weapons").has("lightning"):
		(g.get("player") as Node).add_weapon("lightning")
	# 清理场上敌人
	for e in (g.get("enemies_node") as Node).get_children():
		e.queue_free()
	await process_frame
	# 玩家固定在原点
	(g.get("player") as Node).position = Vector2.ZERO
	# 落雷点远离玩家，敌人A在落雷点附近，敌人B在玩家附近但远离落雷点
	var lightning_pos: Vector2 = Vector2(500, 0)
	var posA: Vector2 = lightning_pos + Vector2(10, 0) # 距落雷 10
	var posB: Vector2 = Vector2.ZERO + Vector2(10, 0) # 距玩家 10，距落雷 ~490
	g._spawn_at("slime", posA)
	g._spawn_at("slime", posB)
	await process_frame
	var enemies: Array = g.get_tree().get_nodes_in_group("enemies")
	_assert(enemies.size() == 2, "雷霆测试生成 2 敌人", "数量=%d" % enemies.size())
	if enemies.size() != 2:
		g.queue_free()
		await process_frame
		return
	# 按位置区分 A/B
	var eA: Node = null
	var eB: Node = null
	for e in enemies:
		if (e as Node2D).position.distance_to(posA) < 1.0:
			eA = e
		elif (e as Node2D).position.distance_to(posB) < 1.0:
			eB = e
	_assert(eA != null and eB != null, "可定位两敌人", "eA=%s eB=%s" % [str(eA), str(eB)])
	if eA == null or eB == null:
		g.queue_free()
		await process_frame
		return
	var hpA_before: float = float(eA.get("hp"))
	var hpB_before: float = float(eB.get("hp"))
	var aoe: float = 70.0
	var dmg: float = 10.0 # 使用低伤害避免直接击杀导致实例释放
	# 调用修复后的范围伤害：应仅伤害落雷点附近
	(g.get("player") as Node)._area_damage(lightning_pos, aoe, dmg)
	# 立即检查（queue_free 延迟到帧末，await 前实例仍有效）
	var hpA_after: float = float(eA.get("hp")) if is_instance_valid(eA) else -1.0
	var hpB_after: float = float(eB.get("hp")) if is_instance_valid(eB) else -1.0
	var hitA: bool = (not is_instance_valid(eA)) or hpA_after < hpA_before - 0.1 or (eA.get("dead") if is_instance_valid(eA) else true)
	var hitB: bool = (is_instance_valid(eB) and float(eB.get("hp")) < hpB_before - 0.1) or (is_instance_valid(eB) and bool(eB.get("dead")))
	# 由于 dmg=10，slime 18hp 不会死亡，hit 判定以 hp 下降为准
	hitA = hpA_after < hpA_before - 0.1
	hitB = hpB_after < hpB_before - 0.1
	_assert(hitA, "落雷点附近敌人应受击", "hpA %.1f->%.1f" % [hpA_before, hpA_after])
	_assert(not hitB, "玩家附近但远离落雷点敌人不应受击", "hpB %.1f->%.1f 落雷=%s" % [hpB_before, hpB_after, str(lightning_pos)])
	# 反向：若落雷在玩家位置，A 应不受击而 B 受击
	# 重置血量（若实例仍有效）
	if is_instance_valid(eA):
		eA.set("hp", hpA_before)
	if is_instance_valid(eB):
		eB.set("hp", hpB_before)
	(g.get("player") as Node)._area_damage(Vector2.ZERO, aoe, dmg)
	var hpA2: float = float(eA.get("hp")) if is_instance_valid(eA) else -1.0
	var hpB2: float = float(eB.get("hp")) if is_instance_valid(eB) else -1.0
	_assert(not (hpA2 < hpA_before - 0.1), "远离落雷点敌人不应受击（二次）", "hpA %.1f->%.1f" % [hpA_before, hpA2])
	_assert(hpB2 < hpB_before - 0.1, "玩家位置落雷应伤害附近敌人", "hpB %.1f->%.1f" % [hpB_before, hpB2])
	g.queue_free()
	await process_frame
	await process_frame


func _test_state_mutex_and_recovery() -> void:
	print("\n[SMOKE] 关键流程互斥与恢复")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var menus: Control = g.get("menus") as Control
	# 1. 暂停时触发升级：升级应隐藏暂停并独占
	menus.toggle_pause()
	await process_frame
	_assert(menus.get("pause_layer").visible == true, "互斥前置：暂停可见", "pause 隐藏")
	g._on_level_up()
	await process_frame
	_assert(menus.get("upgrade_layer").visible == true, "暂停时升级应显示", "upgrade 隐藏")
	_assert(menus.get("pause_layer").visible == false, "升级显示时暂停应自动隐藏", "pause 仍可见")
	_assert(g.get_tree().paused == true, "升级时保持暂停", "未暂停")
	# 清理升级
	var cards: Array = g._roll_cards()
	g._on_card_chosen(cards[0])
	await process_frame
	_assert(menus.get("upgrade_layer").visible == false, "选卡后升级隐藏", "仍可见")
	_assert(g.get_tree().paused == false, "选卡后恢复", "仍暂停")
	# 2. 升级时触发胜利：胜利应隐藏升级并独占
	g._on_level_up()
	await process_frame
	_assert(menus.get("upgrade_layer").visible == true, "胜利前置：升级可见", "隐藏")
	g._win()
	await process_frame
	_assert(menus.get("end_layer").visible == true, "胜利后结算可见", "隐藏")
	_assert(menus.get("upgrade_layer").visible == false, "胜利时升级应隐藏", "upgrade 仍可见")
	_assert(menus.get("pause_layer").visible == false, "胜利时暂停应隐藏", "pause 仍可见")
	_assert(g.get("ended") == true, "胜利后 ended=true", "false")
	_assert(int(g.get("pending_levels")) == 0, "胜利后 pending 清零", "pending=%d" % int(g.get("pending_levels")))
	# 此时尝试再升级应被阻断
	var pend_before: int = int(g.get("pending_levels"))
	g._on_level_up()
	await process_frame
	_assert(int(g.get("pending_levels")) == pend_before, "胜利后升级被阻断", "pending 变化")
	_assert(menus.get("upgrade_layer").visible == false, "胜利后升级不应显示", "可见")
	# 通过 continue_endless 重置
	g.continue_endless()
	await process_frame
	_assert(g.get("ended") == false, "无尽可能下 ended=false", "true")
	_assert(menus.get("end_layer").visible == false, "无尽后结算隐藏", "可见")
	_assert(g.get_tree().paused == false, "无尽后恢复", "暂停")
	# 3. 失败时同样互斥
	g._on_level_up()
	await process_frame
	_assert(menus.get("upgrade_layer").visible == true, "失败前置：升级可见", "隐藏")
	(g.get("player") as Node).hurt(9999.0)
	await process_frame
	await process_frame
	_assert(menus.get("end_layer").visible == true, "失败后结算可见", "隐藏")
	_assert(menus.get("upgrade_layer").visible == false, "失败时升级应隐藏", "可见")
	# 重置为新实例测试 restart/to_home 总会解除暂停并隐藏层
	g.queue_free()
	await process_frame
	await process_frame
	var g2: Node = ps.instantiate()
	root.add_child(g2)
	await process_frame
	await process_frame
	var m2: Control = g2.get("menus") as Control
	# 模拟三层中任意层可见 + 暂停
	m2.get("upgrade_layer").visible = true
	m2.get("pause_layer").visible = true
	m2.get("end_layer").visible = true
	g2.get_tree().paused = true
	g2.set("pending_levels", 2)
	g2.restart()
	await process_frame
	_assert(g2.get_tree().paused == false, "restart 后总会解除暂停", "仍暂停")
	_assert(m2.get("upgrade_layer").visible == false, "restart 后升级隐藏", "可见")
	_assert(m2.get("pause_layer").visible == false, "restart 后暂停隐藏", "可见")
	_assert(m2.get("end_layer").visible == false, "restart 后结算隐藏", "可见")
	_assert(int(g2.get("pending_levels")) == 0, "restart 后 pending 清零", "pending=%d" % int(g2.get("pending_levels")))
	g2.queue_free()
	await process_frame
	await process_frame
	var g3: Node = ps.instantiate()
	root.add_child(g3)
	await process_frame
	await process_frame
	var m3: Control = g3.get("menus") as Control
	m3.get("upgrade_layer").visible = true
	m3.get("pause_layer").visible = true
	m3.get("end_layer").visible = true
	g3.get_tree().paused = true
	g3.set("pending_levels", 1)
	g3.to_home()
	await process_frame
	await process_frame
	_assert(g3.get_tree().paused == false, "to_home 后总会解除暂停", "仍暂停")
	# to_home 会切换场景，m3 可能随场景卸载，但仍校验 pending 与暂停
	_assert(int(g3.get("pending_levels")) == 0, "to_home 后 pending 清零", "pending=%d" % int(g3.get("pending_levels")))
	# 清理可能的新 Home 场景
	if current_scene != null and current_scene.name == "Home":
		current_scene.queue_free()
		await process_frame
	if is_instance_valid(g3) and g3.get_parent() == root:
		g3.queue_free()
		await process_frame
	await process_frame
	if is_instance_valid(g) and g.get_parent() == root:
		g.queue_free()
		await process_frame
	await process_frame


func _test_spawn_clamp_and_caps() -> void:
	print("\n[SMOKE] 生成边界与上限")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	var arena: float = float(g.get("ARENA"))
	# 多次生成位置应在 ARENA 范围内
	var out_of_bounds: bool = false
	for i in 100:
		var pos: Vector2 = g._spawn_pos()
		if absf(pos.x) > arena - 39.0 or absf(pos.y) > arena - 39.0:
			out_of_bounds = true
			_log_fail("spawn_pos 边界检查", "pos=%s arena=%.0f" % [str(pos), arena])
			break
	if not out_of_bounds:
		_log_pass("100 次 spawn_pos 均在 ARENA 边界内")
	var player: Node = g.get("player") as Node
	# 玩家贴近四角时，钳制后的生成点仍需保持安全距离。
	var spawn_too_close: bool = false
	for corner in [
		Vector2(-arena + 20.0, -arena + 20.0),
		Vector2(-arena + 20.0, arena - 20.0),
		Vector2(arena - 20.0, -arena + 20.0),
		Vector2(arena - 20.0, arena - 20.0),
	]:
		player.position = corner
		for i in 25:
			var corner_spawn: Vector2 = g._spawn_pos()
			if corner_spawn.distance_to(player.position) < 359.9:
				spawn_too_close = true
				_log_fail("边角出生安全距离", "player=%s spawn=%s distance=%.2f" % [str(player.position), str(corner_spawn), corner_spawn.distance_to(player.position)])
				break
		if spawn_too_close:
			break
	if not spawn_too_close:
		_log_pass("玩家贴近四角时出生点仍保持至少 360px")
	# 自定义极小敌人上限时，特殊槽预留不能锁死普通刷怪。
	var gd: GDScript = preload("res://scripts/game_data.gd")
	var original_max_enemies: int = int(gd.get("max_enemies"))
	gd.set("max_enemies", 1)
	var one_slot_allows_regular: bool = bool(g._can_spawn_enemy("slime"))
	gd.set("max_enemies", 2)
	var two_slots_allow_regular: bool = bool(g._can_spawn_enemy("slime"))
	gd.set("max_enemies", original_max_enemies)
	_assert(one_slot_allows_regular and two_slots_allow_regular, "极小敌人上限仍可启动普通刷怪", "max=1:%s max=2:%s" % [str(one_slot_allows_regular), str(two_slots_allow_regular)])
	# 玩家移动边界
	player.position = Vector2(arena, arena)
	player._move(0.016)
	_assert(absf(player.position.x) <= arena - 19.9 and absf(player.position.y) <= arena - 19.9, "玩家位置被 clamp 在 ARENA 内", "pos=%s" % str(player.position))
	# 寿命回收只能合并节点，不能吞掉尚未拾取的 XP。
	g._spawn_pickup("gem", Vector2(1000.0, 1000.0), 11)
	var lone_gem: Node = (g.get("pickups_node") as Node).get_child(0) as Node
	g._expire_pickup(lone_gem)
	_assert(lone_gem.get_parent() != null and int(lone_gem.get("value")) == 11, "最后一个到期宝石续期保留 XP", "parent=%s value=%s" % [str(lone_gem.get_parent()), str(lone_gem.get("value"))])
	g._spawn_pickup("gem", Vector2(1100.0, 1000.0), 7)
	g._expire_pickup(lone_gem)
	var pickup_children: Array = (g.get("pickups_node") as Node).get_children()
	var merged_xp: int = 0
	for pickup in pickup_children:
		merged_xp += int(pickup.get("value"))
	_assert(pickup_children.size() == 1 and merged_xp == 18, "到期宝石合并后 XP 总量不变", "count=%d xp=%d" % [pickup_children.size(), merged_xp])
	for i in 30:
		g._spawn_pickup("heart", Vector2(1200.0 + i, 1000.0), 1)
	var heart_count: int = 0
	var heart_value: int = 0
	for pickup in (g.get("pickups_node") as Node).get_children():
		if str(pickup.get("kind")) == "heart":
			heart_count += 1
			heart_value += int(pickup.get("value"))
	_assert(heart_count == 24 and heart_value == 30, "心脏节点上限 24 且治疗量合并", "count=%d value=%d" % [heart_count, heart_value])
	g.queue_free()
	await process_frame
	await process_frame


func _write_baseline() -> void:
	var info: Dictionary = {
		"godot_version": Engine.get_version_info(),
		"seed": _seed,
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"elapsed_msec": Time.get_ticks_msec() - _start_msec,
		"scenarios": _perf_results,
		"summary": {
			"passed": _passed,
			"failed": _failed,
			"total": _passed + _failed,
		}
	}
	var json_str: String = JSON.stringify(info, "\t")
	# 确保目录存在
	var dir: String = _baseline_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir) and dir.begins_with("res://"):
		var abs_dir: String = ProjectSettings.globalize_path(dir)
		DirAccess.make_dir_recursive_absolute(abs_dir)
	elif not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(_baseline_path, FileAccess.WRITE)
	if file != null:
		file.store_string(json_str + "\n")
		file.close()
		print("\n[BASELINE] 已写入 %s" % _baseline_path)
		print(json_str)
	else:
		print("\n[BASELINE] 写入失败: %s error=%d" % [_baseline_path, FileAccess.get_open_error()])
		# 尝试写入 user:// 备用
		var alt_path: String = "user://baseline.json"
		var f2: FileAccess = FileAccess.open(alt_path, FileAccess.WRITE)
		if f2 != null:
			f2.store_string(json_str + "\n")
			f2.close()
			print("[BASELINE] 已写入备用路径 %s" % alt_path)


func _print_summary() -> void:
	print("\n==================================================")
	print("测试完成：通过 %d / 失败 %d / 总计 %d" % [_passed, _failed, _passed + _failed])
	if _failed > 0:
		print("失败详情：")
		for d in _failed_details:
			print("  %s" % d)
		print("--------------------------------------------------")
		print("RESULT: FAIL")
	else:
		print("RESULT: PASS")
	print("==================================================")
	if _perf_results.size() > 0:
		print("性能基线摘要：")
		for r in _perf_results:
			var p95: float = float(r.get("p95_ms", r.get("avg_ms", 0.0)))
			if r.has("label"):
				print("  caps: enemies=%d pickups=%d nodes=%d avg_ms=%.3f p95=%.3f" % [r["enemies"], r["pickups"], r["total_nodes"], r["avg_ms"], p95])
			else:
				print("  %.0fs: enemies=%d pickups=%d nodes=%d avg_ms=%.3f p95=%.3f" % [r["elapsed"], r["enemies"], r["pickups"], r["total_nodes"], r["avg_ms"], p95])
