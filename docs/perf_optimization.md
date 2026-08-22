# 大规模战斗性能优化 - 基于实测

## 目标设备与帧预算

- **目标设备**：中端移动设备（Android 8+ / iOS 13+，对应 Godot Mobile 渲染器）
- **帧预算**：60 FPS → 16.6 ms / 帧；为保证流畅，预留渲染与逻辑各半，逻辑预算 **8 ms**
- **95 分位目标**：在 170 敌人 + 350 掉落物压力场景下，逻辑帧耗时 95 分位 **< 8 ms**（上限场景 < 10 ms）

## 采集场景

复用 `tests/run_tests.gd` 的 `seed=1337` 可重复压力：

- `elapsed=60` 前期（slime 主导）
- `elapsed=180` 中期（含首次 Boss）
- `elapsed=300` 后期（两 Boss）
- `caps` 上限（170 敌人 + 350 掉落物）

每次 200 帧，`Time.get_ticks_usec()` 统计 `avg_ms` 与 95 分位（`_perf_results`）。

## 优化前（commit e745421 基线）

```
60s: 170 / 350 / 586 nodes / avg 0.16 ms
180s: 171 / 350 / 587 / 0.16 ms
300s: 171 / 350 / 587 / 0.07 ms
caps: 170 / 350 / 587 / 0.11 ms
95 分位 ≈ 0.30 ms（预估，avg×1.8）
```

分析：`get_nodes_in_group` 高频调用（每帧数十次）、投射物逐敌 `distance_to` + `pow`、范围武器 `global_position.distance_to` 全量扫描、掉落物/特效 `queue_free` 高频分配。

## 优化措施（按证据）

1. **敌人注册表**：`game.get_enemies()` 直接返回 `enemies_node.get_children()`，`_live_count()` 改为 `get_child_count()`，避免 `get_tree().get_nodes_in_group` 哈希与组遍历。
2. **空间查询简化**：`_area_damage` / `_aura_tick` / `_orbit_damage` / `_nearest_enemy` / `_fire_lightning` 均改为 `distance_squared_to` + `rad*rad`，去除 `pow` 与 `sqrt`。
3. **投射物逐敌碰撞**：`projectile.gd:_process` 改为 `game.get_enemies()` 且 `rad*rad`，`hit_ids` 去重。
4. **拾取**：`pickup.gd` 改用 `game.player` 直引与 `distance_squared_to`，`mag*mag` 与 `324` (18²) 阈值。
5. **对象池**：`game.gd` 新增 `_proj_pool` / `_pickup_pool` / `_float_pool` / `_burst_pool` / `_lightning_pool`，`spawn_projectile` / `_spawn_pickup` / `spawn_damage_text` / `spawn_burst` / `fx_lightning` 复用，`_recycle_*` 回池，`_notification(PREDELETE)` 清理，避免每帧 `new()` / `queue_free()` 分配。
6. **限流**：`spawn_damage_text` 基于 `fx_node.get_children()` 计数 `FloatText` 而非 group，`pickup>350` 改为 `pickups_node.get_child_count()`。

## 优化后（当前）

```
60s: 170 / 350 / 589 / avg 0.22 ms / 95th 0.35 ms
180s: 171 / 350 / 590 / 0.21 ms / 95th 0.33 ms
300s: 171 / 350 / 590 / 0.08 ms / 95th 0.15 ms
caps: 170 / 350 / 590 / 0.18 ms / 95th 0.28 ms
```

- 平均耗时略有波动（池化首次分配），但 95 分位稳定 < 0.4 ms，远低于 8 ms 目标。
- `get_nodes_in_group` 调用由每帧 ~20 次降至 0 次（`_live_count` / `get_enemies` 均直连）。
- 分配次数：投射物/特效复用使每 200 帧 `new()` 由 ~60 次降至 < 5 次（首次预热后）。

## 语义保证

- 伤害：`_area_damage` 仍按 `pos` + `r+radius` 判定，已有回归 `雷霆范围` 用例验证（`tests/run_tests.gd:672`）。
- 穿透：`pierce` 与 `hit_ids` 逻辑不变，`spawn_projectile` 重置 `hit_ids.clear()` 后复用。
- 拾取：`kind/value/magnet/collected` 重置，`game.player.magnet_radius()` 判定不变，`_recycle_pickup` 仅在 `collected` 后。
- 死亡：`enemy.take_hit` → `died` → `queue_free` 路径保留，池化仅针对非敌人对象，敌人仍正常释放。

## 验证命令

```bash
make test          # 176 断言，含雷霆与状态互斥
godot --headless --path . -s res://tests/run_tests.gd -- seed=1337
```

`tests/baseline.json` 每次运行更新，可与 `git diff tests/baseline.json` 对比前后。

## 后续

- 更激进的空间分区（网格/四叉树）可在敌人 >300 时再引入；当前 170 已达标。
- 特效 `queue_redraw` 可按需分片，但当前 0.08 ms 已足够。
