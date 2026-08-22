#!/usr/bin/env bash
set -e
SEED="${1:-1337}"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
if command -v godot >/dev/null 2>&1; then
	GODOT_BIN="godot"
fi
exec "$GODOT_BIN" --headless --path . -s res://tests/run_tests.gd -- seed="$SEED"
