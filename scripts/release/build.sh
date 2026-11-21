#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../common.sh"
version=${1:?Version required}
sha=${2:?Source SHA required}
code=$(python3 scripts/release/version.py "$version")
[[ "$(git rev-parse HEAD)" == "$sha" ]]
out="$PROJECT_ROOT/build/release"
mkdir "$out"
source_dir=$(mktemp -d)
trap 'rm -rf "$source_dir"' EXIT
git archive "$sha" | tar -x -C "$source_dir"
# Edit only the archive's Android export settings. Both exports use this same source.
python3 - "$source_dir/export_presets.cfg" "$version" "$code" <<'PY'
import configparser
import sys
from pathlib import Path

path, version, code = sys.argv[1:]
preset = configparser.ConfigParser(interpolation=None)
preset.read(path)
android = next(section for section in preset if preset[section].get("name") == '"Android"')
preset[android + ".options"].update({
    "version/code": code, "version/name": f'"{version}"',
    "package/unique_name": '"org.ilyasyoy.stackattack"', "package/signed": "false",
})
with Path(path).open("w") as output:
    preset.write(output, space_around_delimiters=False)
PY
run_godot release-import --headless --editor --path "$source_dir" --import
run_godot release-apk --headless --path "$source_dir" --export-release Android "$out/unsigned.apk"
tools="$ANDROID_HOME/build-tools/36.1.0"
"$tools/zipalign" -P 16 -f 4 "$out/unsigned.apk" "$out/aligned.apk"
mkdir "$out/web"
run_godot release-web --headless --path "$source_dir" --export-release Web "$out/web/index.html"
cp "$source_dir"/notices/GODOT_{LICENSE,COPYRIGHT}.txt "$out/web/"
printf '%s\n' "Stack Attack $version" "Source commit: $sha" \
  'Extract all files together. Run python3 -m http.server 8765 in this directory.' \
  'Open http://127.0.0.1:8765/ in a WebGL 2 browser.' > "$out/web/README.txt"
(cd "$out/web" && zip -q -r "$out/web.zip" .)
