# 构建说明

## 首发平台

- **Web (HTML5)** — 最低环境：支持 WebGL2 / WebAssembly 的现代浏览器（Chrome ≥ 90, Firefox ≥ 90, Safari ≥ 15）。CI 首验证此平台。
- **Linux/X11 x86_64** — 本地验证与桌面分发，需求 Godot 4.7 运行时。

版本：`VERSION` 与 `project.godot:config/version` 均为 `0.3.0`，以 `CHANGELOG.md` 追踪。

## 干净克隆构建

```bash
git clone <repo>
cd 幸存者
# 校验可加载
make verify   # 或 godot --headless --path . --quit-after 2
# 全量测试 + 性能基线（332 断言）
make test     # 等价 godot --headless --path . -s res://tests/run_tests.gd -- seed=1337
make perf     # 查看 tests/baseline.json
# 导出
make export-web   # 需已安装 Web 模板，产物 build/web/index.html
make export-linux # 需已安装 Linux 模板，产物 build/linux/幸存者.x86_64
make export-all
```

### 导出模板安装

- 编辑器：`Editor → Manage Export Templates → Download`
- 命令行：`godot --headless --install-export-templates` 或使用 `chickensoft-games/setup-godot` 的 `include-templates: true`

无模板时 `make export-*` 会提示缺模板但预设校验仍通过（CI 的 `Check export presets` 步骤）。

## 版本与变更

- `VERSION` 文本与 `project.godot` 同步
- `CHANGELOG.md` 按 `0.1.0 → 0.3.0` 记录功能
- 发版前更新两者并打 tag：`git tag v0.3.0 && git push --tags`

## CI

见 `.github/workflows/ci.yml`：

1. `godot --version`
2. `headless --quit-after 2`
3. `headless -s res://tests/run_tests.gd -- seed=1337`（332 断言）
4. `export_presets.cfg` 存在性与 `Web` 预设检查
5. `godot --export-release Web build/web/index.html`
6. 上传 `baseline.json` 与 `build/web/` 产物

本地复现 CI：`make verify && make test && make export-web`
