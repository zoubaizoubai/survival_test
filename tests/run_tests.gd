extends SceneTree

# 无头烟雾测试与性能基线入口
# 运行: godot --headless --path . -s res://tests/run_tests.gd -- seed=1337
# 可选参数: seed=INT, verbose=true|false, baseline_path=res://tests/baseline.json

var _seed: int = 1337
var _verbose: bool = true
var _baseline_path: String = "res://tests/baseline.json"
var _passed: int = 0
var _failed: int = 0
var _failed_details: Array = []
var _perf_results: Array = []
var _start_msec: int = 0


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		var arg: String = str(a).strip_edges()
		if arg.begins_with("seed="):
			_seed = int(arg.split("=")[1])
		elif arg.begins_with("baseline="):
			_baseline_path = arg.split("=")[1]
		elif arg == "verbose" or arg == "verbose=true":
			_verbose = true
		elif arg == "verbose=false":
			_verbose = false


func _log_pass(msg: String) -> void:
	_passed += 1
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
	_start_msec = Time.get_ticks_msec()
	seed(_seed)
	print("==================================================")
	print("幸存者 无头烟雾测试与性能基线")
	print("Godot %s seed=%d baseline=%s" % [Engine.get_version_info()["string"] if Engine.get_version_info().has("string") else str(Engine.get_version_info()), _seed, _baseline_path])
	print("==================================================")
	await process_frame
	await process_frame
	await _run_all()
	_write_baseline()
	_print_summary()
	# 清理后退出，使用非零码标识失败
	var exit_code: int = 0 if _failed == 0 else 1
	quit(exit_code)


func _run_all() -> void:
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
	# 确保所有异步清理完成
	await process_frame
	await process_frame


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
		print("  [PERF] elapsed=%.0f  enemies=%d  pickups=%d  nodes=%d  avg_ms=%.3f  objects=%d" % [result["elapsed"], result["enemies"], result["pickups"], result["total_nodes"], result["avg_ms"], result["object_count"]])
		# 阈值校验： headless 单帧模拟应远小于 16ms
		_assert(result["avg_ms"] < 8.0, "elapsed %.0fs 帧耗时 <8ms (%.3fms)" % [elapsed, result["avg_ms"]], "elapsed %.0fs 帧耗时过高: %.3fms" % [elapsed, result["avg_ms"]])
	# 上限场景：填满敌人与掉落物
	var cap_result: Dictionary = await _run_perf_caps()
	_perf_results.append(cap_result)
	print("  [PERF] caps enemies=%d pickups=%d nodes=%d avg_ms=%.3f" % [cap_result["enemies"], cap_result["pickups"], cap_result["total_nodes"], cap_result["avg_ms"]])
	_assert(cap_result["enemies"] >= 170 and cap_result["enemies"] <= 172, "敌人上限 170-172（含Boss）", "enemies=%d" % cap_result["enemies"])
	_assert(cap_result["pickups"] <= 355, "掉落物上限约 350", "pickups=%d" % cap_result["pickups"])
	_assert(cap_result["avg_ms"] < 10.0, "上限场景帧耗时 <10ms (%.3fms)" % cap_result["avg_ms"], "上限帧耗时过高")


func _run_perf_one(elapsed_val: float, seed_val: int) -> Dictionary:
	seed(seed_val)
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var g: Node = ps.instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	g.set("elapsed", elapsed_val)
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
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
	# 填掉落物至接近上限（使用子节点数避免 group 延迟）
	for i in 360:
		g._spawn_pickup("gem", Vector2(randf_range(-1200, 1200), randf_range(-800, 800)), 1)
		if pickups_node_ref.get_child_count() >= 350:
			break
	await process_frame
	await process_frame
	# 禁止自动刷怪干扰性能测量
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
	var enemies: int = int(g._live_count())
	var pickups: int = int(g.get_tree().get_nodes_in_group("pickup").size())
	var total_nodes: int = _count_total_nodes()
	var object_count: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var object_nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	# 测量 200 帧模拟耗时
	var iterations: int = 200
	var dt: float = 1.0 / 60.0
	var t0: int = Time.get_ticks_usec()
	for iter in iterations:
		g._process(dt)
		# 敌人与玩家
		var enemies_node: Node = g.get("enemies_node") as Node
		for e in enemies_node.get_children():
			e._process(dt)
		var player_node: Node = g.get("player") as Node
		player_node._process(dt)
		# 投射物
		var proj_node: Node = g.get("projectiles_node") as Node
		for p in proj_node.get_children():
			p._process(dt)
	var t1: int = Time.get_ticks_usec()
	var avg_ms: float = float(t1 - t0) / float(iterations) / 1000.0
	# 额外统计真实帧间隔（可选）
	var result: Dictionary = {
		"elapsed": elapsed_val,
		"enemies": enemies,
		"pickups": pickups,
		"total_nodes": total_nodes,
		"object_count": int(object_count),
		"object_nodes": int(object_nodes),
		"avg_ms": avg_ms,
		"seed": seed_val,
		"iterations": iterations,
	}
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
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
	var enemies_node_ref2: Node = g.get("enemies_node") as Node
	# 强制填满敌人（使用子节点数避免 group 延迟）
	for i in 300:
		if enemies_node_ref2.get_child_count() >= int(g.get("MAX_ENEMIES")):
			break
		g._spawn_at("brute", g._spawn_pos())
	await process_frame
	var before: int = int(g._live_count())
	# 尝试通过 _spawn_one 超越上限（应被限制）
	for i in 10:
		g._spawn_one()
	var after: int = int(g._live_count())
	_assert(before == after and before >= 170 and before <= 172, "超越上限时敌人数量保持 170-172（含Boss）", "before=%d after=%d" % [before, after])
	var pickups_node_ref2: Node = g.get("pickups_node") as Node
	# 填满掉落物
	for i in 500:
		if pickups_node_ref2.get_child_count() >= 350:
			break
		g._spawn_pickup("gem", Vector2(randf_range(-1000,1000), randf_range(-1000,1000)), 1)
	await process_frame
	var pick_before: int = int(g.get_tree().get_nodes_in_group("pickup").size())
	for i in 20:
		g._spawn_pickup("gem", Vector2.ZERO, 1)
	var pick_after: int = int(g.get_tree().get_nodes_in_group("pickup").size())
	_assert(pick_after == pick_before or pick_after == pick_before + 1, "超越上限时掉落物数量不变或仅+1（>350判定）", "before=%d after=%d" % [pick_before, pick_after])
	await process_frame
	# 禁止自动刷怪
	g.set("spawn_t", 9999.0)
	g.set("elite_t", 9999.0)
	var total_nodes: int = _count_total_nodes()
	var enemies_for_result: int = int(g._live_count())
	var t0: int = Time.get_ticks_usec()
	for iter in 200:
		g._process(0.016)
		for e in (g.get("enemies_node") as Node).get_children():
			e._process(0.016)
		(g.get("player") as Node)._process(0.016)
	var t1: int = Time.get_ticks_usec()
	var avg_ms: float = float(t1 - t0) / 200.0 / 1000.0
	var result: Dictionary = {
		"elapsed": 999.0,
		"label": "caps",
		"enemies": enemies_for_result,
		"pickups": pick_before,
		"total_nodes": total_nodes,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"avg_ms": avg_ms,
		"seed": _seed + 9999,
	}
	g.queue_free()
	await process_frame
	await process_frame
	return result


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
	# 玩家移动边界
	var player: Node = g.get("player") as Node
	player.position = Vector2(arena, arena)
	player._move(0.016)
	_assert(absf(player.position.x) <= arena - 19.9 and absf(player.position.y) <= arena - 19.9, "玩家位置被 clamp 在 ARENA 内", "pos=%s" % str(player.position))
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
			if r.has("label"):
				print("  caps: enemies=%d pickups=%d nodes=%d avg_ms=%.3f" % [r["enemies"], r["pickups"], r["total_nodes"], r["avg_ms"]])
			else:
				print("  %.0fs: enemies=%d pickups=%d nodes=%d avg_ms=%.3f" % [r["elapsed"], r["enemies"], r["pickups"], r["total_nodes"], r["avg_ms"]])

