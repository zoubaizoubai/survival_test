# 构建说明

## 版本与首发平台

当前版本为 `0.4.0`。发布时以 `VERSION` 与 `project.godot:application/config/version` 的一致性为准，变更记录见 `CHANGELOG.md`。

- **Web** — 需要支持 WebGL 2 与 WebAssembly 的现代浏览器。
- **Linux/X11 x86_64** — 用于桌面分发与本地验证，PCK 嵌入可执行文件。

发布预设会排除 `addons/`、`build/`、`tests/`、`docs/`、`tools/`、`.agents/`、`.codex/`、`.beads/` 与 CI 等开发内容，避免旧构建、本机符号链接或测试基线进入产物。

## 先决条件

- Godot `4.7.2` （项目兼容 Godot 4.7）
- 已安装对应版本的 Web 与 Linux 导出模板

导出模板可在编辑器中通过 `Editor → Manage Export Templates → Download` 安装；CI 使用 `chickensoft-games/setup-godot` 安装同版本模板。

## 干净克隆构建

```bash
git clone <repo>
cd 幸存者

# 校验项目可加载
make verify

# 隔离 user:// 的无头测试与逻辑性能基线
make test
make perf

# 严格导出：缺模板、Godot 导出失败或产物不完整都会返回非零
make export-web
make export-linux
# 或
make export-all
```

## 产物约定

Web 导出成功后，`build/web/` 至少包含：

- `index.html`
- `index.js`
- `index.wasm`
- `index.pck`
- `version.txt`

Linux 导出成功后，`build/linux/` 至少包含：

- `幸存者.x86_64`（已嵌入 PCK）
- `version.txt`

`make export-*` 会对上述文件做非空校验。任一文件缺失都视为构建失败，不会降级为警告。

## 版本与标签

发版前同步更新 `VERSION`、`project.godot` 与 `CHANGELOG.md`，再使用当前版本创建标签：

```bash
release_version="$(cat VERSION)"
git tag "v${release_version}"
git push --tags
```

## CI

`.github/workflows/ci.yml` 执行：

1. 校验 Godot 版本并无头加载项目。
2. 以 `isolated=true` 运行全量无头测试。
3. 校验 Web/Linux 导出预设。
4. 严格导出并校验 Web 四件套与 `version.txt`。
5. 严格导出并校验 Linux 可执行文件与 `version.txt`。
6. 只有导出成功才上传发布产物；测试基线仍可在失败时作为诊断信息上传。

本地复现 CI：

```bash
make verify && make test && make export-all
```
