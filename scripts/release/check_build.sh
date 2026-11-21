#!/usr/bin/env bash
set -euo pipefail
version=${1:?Version required}
sha=${2:?Commit required}
bash scripts/release/build.sh "$version" "$sha"
python3 scripts/release/verify_apk.py build/release/aligned.apk "$version"
if [[ -z "${BROWSER_PYTHON:-}" ]]; then
  BROWSER_PYTHON="$RUNNER_TEMP/browser/bin/python"
  python3 -m venv "$RUNNER_TEMP/browser"
  playwright_requirement=$(python3 - <<'PY'
import tomllib
with open("pyproject.toml", "rb") as project:
    dependencies = tomllib.load(project)["dependency-groups"]["web"]
print(next(item for item in dependencies if item.startswith("playwright==")))
PY
)
  "$BROWSER_PYTHON" -m pip install "$playwright_requirement"
fi
"$BROWSER_PYTHON" scripts/release/check_web.py build/release/web.zip
