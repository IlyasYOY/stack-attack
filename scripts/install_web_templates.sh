#!/usr/bin/env bash
# Install only Web templates from the checksum-pinned official archive.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
version="4.7.2"
if [[ "$expected_version" != "$version.stable."* ]]; then
  echo 'Update the pinned template installer alongside .godot-version.' >&2
  exit 1
fi
checksum="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
archive="build/cache/Godot_v${version}-stable_export_templates.tpz"
case "$(uname -s)" in
  Darwin) data_home="$HOME/Library/Application Support/Godot" ;;
  Linux) data_home="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
  *) echo 'Supported template install platforms: macOS and Linux.' >&2; exit 1 ;;
esac
destination="$data_home/export_templates/$version.stable"
mkdir -p build/cache
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 --continue-at - \
    --output "$archive.part" \
    "https://downloads.godotengine.org/?version=$version&flavor=stable&slug=export_templates.tpz"
  printf '%s  %s\n' "$checksum" "$archive.part" | shasum -a 512 --check
  mv "$archive.part" "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 512 --check
mkdir -p "$destination"
unzip -j -q -o "$archive" templates/web_nothreads_debug.zip \
  templates/web_nothreads_release.zip templates/icudt_godot.dat templates/version.txt \
  -d "$destination"
[[ "$(cat "$destination/version.txt")" == "$version.stable" ]]
echo "Web templates installed: $destination"
