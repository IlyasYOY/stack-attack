#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
target="${1:-all}"
if [[ "$target" != all && "$target" != web && "$target" != android ]]; then
  echo 'Usage: bash scripts/export.sh [all|web|android]' >&2
  exit 2
fi
if [[ "$target" == all || "$target" == android ]]; then
  : "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:?Source the private debug signing env file first}"
  : "${GODOT_ANDROID_KEYSTORE_DEBUG_USER:?Missing debug key alias}"
  : "${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:?Missing debug key password}"
  [[ -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ]]
  : "${ANDROID_HOME:?Activate the Android SDK first}"
fi
run_godot export-import --headless --editor --path "$PROJECT_ROOT" --import
if [[ "$target" == all || "$target" == web ]]; then
  mkdir -p build/web
  run_godot export-web --headless --path "$PROJECT_ROOT" --export-debug Web "$PROJECT_ROOT/build/web/index.html"
  cp notices/GODOT_LICENSE.txt notices/GODOT_COPYRIGHT.txt build/web/
  python3 scripts/record_build.py web
fi
if [[ "$target" == all || "$target" == android ]]; then
  mkdir -p build/android
  run_godot export-android --headless --path "$PROJECT_ROOT" --export-debug Android "$PROJECT_ROOT/build/android/stack-attack-prototype-debug.apk"
  tools="$ANDROID_HOME/build-tools/36.1.0"
  "$tools/apksigner" verify --verbose --print-certs build/android/stack-attack-prototype-debug.apk > build/logs/android-signature.log
  "$tools/aapt" dump badging build/android/stack-attack-prototype-debug.apk > build/logs/android-metadata.log
  "$tools/zipalign" -c -P 16 4 build/android/stack-attack-prototype-debug.apk
  echo 'Android debug export, signature and 16 KiB alignment: PASS'
  python3 scripts/record_build.py android
fi
