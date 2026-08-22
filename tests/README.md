# 无头烟雾测试与性能基线

## 单条可重复命令

```bash
make test
# 或直接
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tests/run_tests.gd -- seed=1337
# 使用系统 godot（若已加入 PATH）
godot --headless --path . -s res://tests/run_tests.gd -- seed=1337
```

- `SEED` 可控：`make test SEED=42` 或 `... -- seed=42`，用于复现压力场景与随机生成。
- 失败时退出码非零，适合 CI。

## 覆盖范围

- **场景加载**：`home.tscn` / `game.tscn` 可无头 `load()` + `instantiate()`，校验关键节点与脚本挂载。
- **关键状态**：
  - 暂停：`toggle_pause()` 正常暂停/恢复；`ended=true` 或 `upgrade_layer` 可见时被阻断。
  - 升级：`_on_level_up()` -> `show_upgrades()` -> `_on_card_chosen()`，含连续升级堆叠。
  - 胜利：`elapsed >= GOAL_TIME` 触发 `_win()`，`continue_endless()` 重置。
  - 失败：`player.hurt(9999)` 触发 `_lose()`。
  - 重开：`restart()` 清除暂停（headless 下 `reload_current_scene` 会报 `current_scene is null`，但不崩溃）。
  - 返回主页：`to_home()` 切换至 `Home` 且清除暂停。
  - 种子：`seed(N)` 后 `randf` 与 `_pick_kind`/`_spawn_pos` 序列可重复。
  - 边界：`_spawn_pos` 钳制在 `ARENA` 内；玩家 `clamp`；敌人/掉落物上限。

## 性能基线

每次 `make test` 会在 `tests/baseline.json` 写入：

- Godot 版本、seed、时间戳
- 4 个场景：
  - `elapsed=60`  – 前期（slime 主导）
  - `elapsed=180` – 中期（+bat/brute，首 Boss 已触发）
  - `elapsed=300` – 后期（GOAL_TIME，含两 Boss）
  - `caps` – 敌人 170、上限掉落物 ~350 的压力上限
- 每个场景记录：`enemies`、`pickups`、`total_nodes`（`_count_total_nodes()`）、`object_count` / `object_nodes`（`Performance`）、`avg_ms`（200 帧 `Time.get_ticks_usec()` 平均）。

代表性压力通过 `seed` + `elapsed` 控制 `_pick_kind` 与 `_spawn_pos`，并通过 `MAX_ENEMIES=170` 与 `pickup >350` 的钳制验证上限。`avg_ms` 为 headless 下的逻辑耗时（不含渲染），阈值 `<8ms`（上限场景 `<10ms`）。

## 文件约定

- 入口：`tests/run_tests.gd`（`extends SceneTree`，`_initialize` 驱动）
- 未来用例：`tests/test_<feature>.gd`（见 `test_smoke.gd` / `test_perf.gd` 示例）
- 基线：`tests/baseline.json`（提交保存，用于回归对比）

## 本地验证

```bash
make verify   # 仅校验无头可加载
make perf     # 查看当前基线
```

要求 Godot 4.7。
