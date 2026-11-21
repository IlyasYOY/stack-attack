#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${BROWSER_PYTHON:-}" ]]; then
  BROWSER_PYTHON="$RUNNER_TEMP/browser/bin/python"
  if [[ ! -x "$BROWSER_PYTHON" ]]; then
    python3 -m venv "$RUNNER_TEMP/browser"
  fi
  playwright_requirement=$(python3 - <<'PY'
import tomllib
with open("pyproject.toml", "rb") as project:
    dependencies = tomllib.load(project)["dependency-groups"]["web"]
print(next(item for item in dependencies if item.startswith("playwright==")))
PY
)
  "$BROWSER_PYTHON" -m pip install "$playwright_requirement"
fi
"$BROWSER_PYTHON" "$@"
