# 幸存者 测试与验证
# 单条可重复命令: make test
# 需 Godot 4.7 已安装（godot 或 /Applications/Godot.app/Contents/MacOS/Godot）

GODOT_BIN ?= /Applications/Godot.app/Contents/MacOS/Godot
GODOT_FALLBACK ?= godot
SEED ?= 1337
BASELINE ?= res://tests/baseline.json

.PHONY: test smoke perf verify headless export-web export-linux export-all clean version help

test:
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		$(GODOT_FALLBACK) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED) baseline=$(BASELINE); \
	else \
		$(GODOT_BIN) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED) baseline=$(BASELINE); \
	fi

smoke:
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		$(GODOT_FALLBACK) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED); \
	else \
		$(GODOT_BIN) --headless --path . -s res://tests/run_tests.gd -- seed=$(SEED); \
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
	@mkdir -p build/web
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		echo "Exporting Web..."; \
		$(GODOT_FALLBACK) --headless --path . --export-release Web build/web/index.html || echo "Web export needs templates (see docs/BUILD.md)"; \
	else \
		$(GODOT_BIN) --headless --path . --export-release Web build/web/index.html || echo "Web export needs templates"; \
	fi
	@ls -lh build/web/ 2>&1 | head -n 20 || true

export-linux:
	@mkdir -p build/linux
	@if command -v $(GODOT_FALLBACK) >/dev/null 2>&1; then \
		$(GODOT_FALLBACK) --headless --path . --export-release "Linux/X11" build/linux/幸存者.x86_64 || echo "Linux export needs templates"; \
	else \
		$(GODOT_BIN) --headless --path . --export-release "Linux/X11" build/linux/幸存者.x86_64 || echo "Linux export needs templates"; \
	fi
	@ls -lh build/linux/ 2>&1 | head -n 20 || true

export-all: export-web export-linux
	@echo "All exports attempted (check build/)"

clean:
	rm -rf build/
	rm -f user://progress.cfg 2>/dev/null || true
	@echo "clean"

help:
	@echo "Targets: test smoke verify perf version export-web export-linux export-all clean help"
	@echo "  test        无头全量 332 断言 +  perf 基线"
	@echo "  verify      仅校验项目可加载"
	@echo "  export-web  导出 Web (build/web/index.html) 需模板"
	@echo "  export-linux 导出 Linux (build/linux/幸存者.x86_64)"


