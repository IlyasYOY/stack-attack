#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# Export into a fresh directory so retries cannot publish leftover files.
out=$(mktemp -d "$PROJECT_ROOT/build/pages.XXXXXX")
trap 'rm -rf "$out"' EXIT
mkdir "$out/site"
run_godot pages-release --headless --path "$PROJECT_ROOT" --export-release Web "$out/site/index.html"
cp notices/GODOT_{LICENSE,COPYRIGHT}.txt "$out/site/"
git rev-parse HEAD > "$out/site/source-commit.txt"
(cd "$out/site" && zip -q "$out/web.zip" ./*)
bash scripts/with_playwright.sh scripts/release/check_web.py "$out/web.zip"
# Only replace the previous local artifact after this export boots.
rm -rf build/pages
mv "$out/site" build/pages
