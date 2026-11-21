#!/usr/bin/env bash
set -euo pipefail
version=${1:?Version required}
sha=${2:?Commit required}
bash scripts/release/build.sh "$version" "$sha"
python3 scripts/release/verify_apk.py build/release/aligned.apk "$version"
bash scripts/with_playwright.sh scripts/release/check_web.py build/release/web.zip
