# 幸存者 测试与验证
# 单条可重复命令: make test
# 需 Godot 4.7 已安装（godot 或 /Applications/Godot.app/Contents/MacOS/Godot）

GODOT_BIN ?= /Applications/Godot.app/Contents/MacOS/Godot
GODOT_FALLBACK ?= godot
SEED ?= 1337
BASELINE ?= res://tests/baseline.json

.PHONY: test smoke perf verify export-web export-linux export-all clean version help

test:
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		$(GODOT_FALLBACK) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED) baseline=$(BASELINE) isolated=true; \
	else \
		$(GODOT_BIN) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED) baseline=$(BASELINE) isolated=true; \
	fi

smoke:
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		$(GODOT_FALLBACK) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED) isolated=true; \
	else \
		$(GODOT_BIN) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED) isolated=true; \
	fi

verify:
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		$(GODOT_FALLBACK) --headless --path . --quit-after 2; \
	else \
		$(GODOT_BIN) --headless --path . --quit-after 2; \
	fi
	@echo "headless load OK"

perf:
	@echo "性能基线已在 tests/baseline.json，每次 make test 都会更新"
	@cat tests/baseline.json | head -n 80

version:
	@echo "VERSION $$(cat VERSION)"
	@grep 'config/version' project.godot || echo "no version in project.godot"
	@echo "Godot $$(/Applications/Godot.app/Contents/MacOS/Godot --version 2>&1 | head -n1 || godot --version 2>&1 | head -n1)"

export-web:
	@rm -rf build/web
	@mkdir -p build/web
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		echo "Exporting Web..."; \
		$(GODOT_FALLBACK) --headless --path . --export-release Web build/web/index.html; \
	else \
		$(GODOT_BIN) --headless --path . --export-release Web build/web/index.html; \
	fi
	@for artifact in index.html index.js index.wasm index.pck; do \
		test -s "build/web/$$artifact" || { echo "Missing Web artifact: build/web/$$artifact" >&2; exit 1; }; \
	done
	@cp VERSION build/web/version.txt
	@test -s build/web/version.txt
	@ls -lh build/web/

export-linux:
	@rm -rf build/linux
	@mkdir -p build/linux
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		$(GODOT_FALLBACK) --headless --path . --export-release "Linux/X11" build/linux/幸存者.x86_64; \
	else \
		$(GODOT_BIN) --headless --path . --export-release "Linux/X11" build/linux/幸存者.x86_64; \
	fi
	@test -s build/linux/幸存者.x86_64 || { echo "Missing Linux artifact: build/linux/幸存者.x86_64" >&2; exit 1; }
	@cp VERSION build/linux/version.txt
	@test -s build/linux/version.txt
	@ls -lh build/linux/

export-all: export-web export-linux
	@echo "All exports completed and validated (see build/)"

clean:
	rm -rf build/
	@echo "clean"

help:
	@echo "Targets: test smoke verify perf version export-web export-linux export-all clean help"
	@echo "  test        隔离 user:// 的无头全量测试 + perf 基线"
	@echo "  verify      仅校验项目可加载"
	@echo "  export-web  严格导出并校验 Web 四件套（需模板）"
	@echo "  export-linux 严格导出并校验 Linux 可执行文件"
