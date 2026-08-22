# 示例：烟雾用例模板
# 命名遵循 tests/test_<feature>.gd
# 实际执行由 tests/run_tests.gd 驱动；此文件可作为独立入口演示：
#   godot --headless --path . -s res://tests/test_smoke.gd
extends SceneTree

# 最小示例：验证 home 与 game 可加载
func _initialize() -> void:
	seed(1337)
	print("[test_smoke] 演示入口 – 建议使用 tests/run_tests.gd 作为统一入口")
	var home: Resource = load("res://scenes/home.tscn")
	var game: Resource = load("res://scenes/game.tscn")
	assert(home != null, "home.tscn 加载失败")
	assert(game != null, "game.tscn 加载失败")
	var h: Node = (home as PackedScene).instantiate()
	var g: Node = (game as PackedScene).instantiate()
	root.add_child(h)
	root.add_child(g)
	await process_frame
	print("[test_smoke] home/game 实例化 OK，节点数=%d" % g.get_tree().get_nodes_in_group("enemies").size())
	h.queue_free()
	g.queue_free()
	await process_frame
	print("[test_smoke] PASS – 更完整校验请运行 make test")
	quit(0)
