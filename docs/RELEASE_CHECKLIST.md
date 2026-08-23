# 发布检查清单

## 版本与文档

- [ ] 当前发布版本为 `0.4.0`；`VERSION` 与 `project.godot:application/config/version` 一致。
- [ ] `CHANGELOG.md` 已补充本版行为变更与日期。
- [ ] `docs/BUILD.md` 中平台、产物与构建要求与当前预设一致。

## 自动化

- [ ] CI 绿灯：无头加载、隔离测试、Web 导出、Linux 导出全部通过。
- [ ] CI 中的导出失败会返回非零，不存在 `|| echo` 等吞错处理。
- [ ] `make verify && make test && make export-all` 在安装模板的干净环境可重复执行。
- [ ] `tests/baseline.json` 在同一机器/同一 Godot 版本下无明显回归；阈值以测试代码为准，不在文档复制固定数字。

## 手动验收

- [ ] **输入**：WASD/方向键、左摇杆、鼠标点击、触摸摇杆、`Pause`/`Start` 暂停与继续。
- [ ] **流程**：开始游戏 → 击杀 → 升级三选一 → 暂停/继续 → 胜利 → 无尽 → 死亡 → 重开/回主页。
- [ ] **武器构筑**：dagger / orbit / lightning / aura / boomerang / frost 均可触发，进化会正确替换基础武器。
- [ ] **敌人**：slime / bat / brute / charger / caster / elite / boss 行为与预警可辨识。
- [ ] **存档**：最佳记录与解锁可跨启动保存；损坏存档可回退；清档流程有明确确认。
- [ ] **音视**：Master / Music / Sfx 可分别调节；震动与强闪烁开关生效；Boss 血条在基准视口与宽屏下无裁切。
- [ ] **性能**：在实际目标设备/浏览器上采集帧率、帧时间与峰值场景；无头逻辑微基准不替代端到端性能验收。

## 导出产物

- [ ] `export_presets.cfg` 的 Web/Linux 预设排除 `addons/**`、`build/**`、`tests/**`、`docs/**`、`tools/**`、`.agents/**`、`.codex/**`、`.beads/**` 与其他开发内容。
- [ ] Web 包含非空的 `index.html`、`index.js`、`index.wasm`、`index.pck`、`version.txt`。
- [ ] Linux 包含非空的 `幸存者.x86_64` 与 `version.txt`，并可在目标 Linux x86_64 环境启动。
- [ ] 用临时 `--export-pack` 审计包内文件，确认没有测试、文档、代理配置或本机符号链接内容。
- [ ] 本地 HTTP 服务器打开 Web 产物，确认能启动并完成一局。

## 发布

- [ ] 根据 `VERSION` 创建对应的 `v<version>` 标签并推送。
- [ ] 只上传通过上述产物校验与手动验收的构建。
