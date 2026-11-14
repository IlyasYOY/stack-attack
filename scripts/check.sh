#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
run_godot import --headless --editor --path "$PROJECT_ROOT" --import
run_godot test --headless --path "$PROJECT_ROOT" --script res://tests/test_game.gd
grep -q '^GAME_TEST_PASS:' build/logs/test.log
run_godot run --headless --path "$PROJECT_ROOT" --quit-after 3
grep -q '^STACK_ATTACK_READY$' build/logs/run.log
