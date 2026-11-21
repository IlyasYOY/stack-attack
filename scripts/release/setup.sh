#!/usr/bin/env bash
# Install the pinned editor and templates on a fresh GitHub Ubuntu runner.
set -euo pipefail
version=4.7.2-stable
url="https://github.com/godotengine/godot-builds/releases/download/$version"
case "$1" in
  editor)
    curl -fsSL --retry 3 "$url/Godot_v${version}_linux.x86_64.zip" -o "$RUNNER_TEMP/godot.zip"
    echo "9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65  $RUNNER_TEMP/godot.zip" | sha512sum --check
    mkdir -p "$RUNNER_TEMP/godot"
    unzip -q "$RUNNER_TEMP/godot.zip" -d "$RUNNER_TEMP/godot"
    chmod +x "$RUNNER_TEMP/godot/Godot_v${version}_linux.x86_64"
    echo "GODOT_BIN=$RUNNER_TEMP/godot/Godot_v${version}_linux.x86_64" >> "$GITHUB_ENV"
    ;;
  templates)
    curl -fsSL --retry 3 "$url/Godot_v${version}_export_templates.tpz" -o "$RUNNER_TEMP/templates.tpz"
    echo "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079  $RUNNER_TEMP/templates.tpz" | sha512sum --check
    dest="$XDG_DATA_HOME/godot/export_templates/4.7.2.stable"
    mkdir -p "$dest" "$XDG_CONFIG_HOME/godot"
    unzip -jq "$RUNNER_TEMP/templates.tpz" templates/{android_debug.apk,android_release.apk,web_nothreads_debug.zip,web_nothreads_release.zip,icudt_godot.dat,version.txt} -d "$dest"
    ;;
  *) exit 2 ;;
esac
