# 幸存者 测试与验证
# 单条可重复命令: make test
# 需 Godot 4.7 已安装（godot 或 /Applications/Godot.app/Contents/MacOS/Godot）

GODOT_BIN ?= /Applications/Godot.app/Contents/MacOS/Godot
GODOT_FALLBACK ?= godot
SEED ?= 1337
BASELINE ?= res://tests/baseline.json

.PHONY: test smoke perf verify headless

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

