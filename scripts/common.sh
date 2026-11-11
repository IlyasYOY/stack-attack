#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
cd "$PROJECT_ROOT"
expected_version="$(cat .godot-version)"
if [[ "$("$GODOT_BIN" --version)" != "$expected_version" ]]; then
  echo "Expected Godot $expected_version. Activate the documented toolchain." >&2
  exit 1
fi
mkdir -p build/logs

run_godot() {
  local label="$1"
  shift
  local log="build/logs/$label.log"
  if ! timeout 120s "$GODOT_BIN" "$@" > "$log" 2>&1; then
    cat "$log"
    return 1
  fi
  cat "$log"
  # Some editor/import failures are logged while Godot still returns zero.
  if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$log"; then
    return 1
  fi
}
