# 示例：性能基线模板
# 演示如何记录 60/180/300 与上限场景的帧耗时与节点数
# 实际基线由 tests/run_tests.gd 生成并写入 tests/baseline.json
extends SceneTree

func _initialize() -> void:
	seed(1337)
	print("[test_perf] 演示 – 压力场景采样")
	var ps: PackedScene = load("res://scenes/game.tscn") as PackedScene
	for elapsed in [60.0, 180.0, 300.0]:
		var g: Node = ps.instantiate()
		root.add_child(g)
		await process_frame
		await process_frame
		g.set("elapsed", elapsed)
		g.set("spawn_t", 9999.0)
		g.set("elite_t", 9999.0)
		var en: Node = g.get("enemies_node") as Node
		for i in 200:
			if en.get_child_count() >= 170:
				break
			g._spawn_at(g._pick_kind(), g._spawn_pos())
		await process_frame
		var t0: int = Time.get_ticks_usec()
		for iter in 100:
			g._process(0.016)
		var avg_ms: float = float(Time.get_ticks_usec() - t0) / 100.0 / 1000.0
		print("[test_perf] elapsed=%.0f enemies=%d avg_ms=%.3f nodes=%d" % [elapsed, en.get_child_count(), avg_ms, g.get_tree().get_node_count() if g.get_tree().has_method("get_node_count") else 0])
		g.queue_free()
		await process_frame
	print("[test_perf] 演示完成 – 完整基线见 tests/baseline.json")
	quit(0)
