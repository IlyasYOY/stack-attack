#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${APK_SIGNING_KEYSTORE_BASE64:?}" "${APK_SIGNING_STORE_PASSWORD:?}" \
  "${APK_SIGNING_KEY_ALIAS:?}"
private_dir=$(mktemp -d)
trap 'rm -rf "$private_dir"' EXIT
printf '%s' "$APK_SIGNING_KEYSTORE_BASE64" | base64 --decode > "$private_dir/key"
unset APK_SIGNING_KEYSTORE_BASE64
"$ANDROID_HOME/build-tools/36.1.0/apksigner" sign --ks "$private_dir/key" \
  --ks-key-alias "$APK_SIGNING_KEY_ALIAS" --ks-pass env:APK_SIGNING_STORE_PASSWORD \
  --key-pass env:APK_SIGNING_STORE_PASSWORD --v4-signing-enabled false --out "$2" "$1"
