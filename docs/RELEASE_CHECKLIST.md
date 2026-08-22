# 发布检查清单

## 版本与文档

- [ ] `VERSION` 与 `project.godot:config/version` 一致（如 `0.3.0`）
- [ ] `CHANGELOG.md` 已补充本版变更与日期
- [ ] `docs/BUILD.md` 中首发平台与最低环境准确

## 自动化

- [ ] CI 绿灯：`headless load`、`332 断言`、`export presets`、`Web export` 均通过
- [ ] `tests/baseline.json` 已更新且 `avg_ms <8`、`p95 <8`（`caps <10`）
- [ ] `make verify && make test` 本地可重复

## 手动验收（1280×720 基准，触摸+鼠标+手柄）

- [ ] **输入**：WASD/方向键、左摇杆、鼠标点击、触摸摇杆（左半屏 `x<0.35w && y>0.5h`）、`Pause`/`Start` 暂停/继续
- [ ] **流程**：开始游戏 → 击杀 → 升级三选一无重复/治疗保底 → 暂停/继续 → 胜利 300s → 无尽 → 死亡 → 重开/回主页
- [ ] **武器构筑**：dagger / orbit / lightning / aura / boomerang / frost 各可触发，进化（Lv8+被动满）出现且替换不占槽
- [ ] **敌人**：slime/bat/brute/charger(cast 线预警)/caster(环预警)/elite/boss(血条+二阶段) 可辨识
- [ ] **存档**：最佳时间/击杀跨启动保存；累计 40 击杀开回旋、90s 开寒霜；损坏 `user://progress.cfg` 回退；设置内清除存档有效
- [ ] **音视**：Master/Music/Sfx 分别可调；音乐循环；震动/强闪烁可关闭且低血/受击反馈弱化；Boss 血条、在 1280×720 与 20:9 (1280×576) 下无裁切
- [ ] **性能**：中端机 60FPS，170 敌人+350 拾取 95 分位 <0.4ms（实测 0.3ms）

## 导出

- [ ] `export_presets.cfg` 含 `Web` 与 `Linux/X11`，`export_path` 为 `build/web/index.html` / `build/linux/幸存者.x86_64`
- [ ] `make export-web` 产物可在本地 `python -m http.server` 于浏览器验证可启动
- [ ] 版本号与变更说明已随构建产物记录（如 `build/web/version.txt` 拷贝自 `VERSION`）

## 发布

- [ ] 打 tag `v0.3.0` 并推送
- [ ] 产物上传至 itch.io / 静态托管，附 `BUILD.md` 链接与浏览器要求
