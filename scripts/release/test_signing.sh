#!/usr/bin/env bash
# Exercise the production signing steps with a one-use PKCS12 kept outside the checkout.
set -euo pipefail
umask 077
version=${1:?Version required}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
APK_SIGNING_STORE_PASSWORD=$(openssl rand -hex 32)
export APK_SIGNING_STORE_PASSWORD APK_SIGNING_KEY_ALIAS=disposable-ci
keytool -genkeypair -storetype PKCS12 -keystore "$tmp/test.p12" -alias "$APK_SIGNING_KEY_ALIAS" \
  -storepass:env APK_SIGNING_STORE_PASSWORD -keypass:env APK_SIGNING_STORE_PASSWORD \
  -dname CN=Disposable-CI -keyalg RSA -keysize 2048 -validity 1
fingerprint=$(keytool -exportcert -keystore "$tmp/test.p12" -alias "$APK_SIGNING_KEY_ALIAS" \
  -storepass:env APK_SIGNING_STORE_PASSWORD | sha256sum | cut -d' ' -f1)
APK_SIGNING_KEYSTORE_BASE64=$(base64 -w0 "$tmp/test.p12")
export APK_SIGNING_KEYSTORE_BASE64
bash scripts/release/sign.sh build/release/aligned.apk "$tmp/test.apk"
python3 scripts/release/verify_apk.py "$tmp/test.apk" "$version" "$fingerprint"
if python3 scripts/release/verify_apk.py "$tmp/test.apk" "$version" "$(printf '%064d' 0)" >"$tmp/rejection" 2>&1; then
  echo 'Unexpectedly accepted a different certificate' >&2
  exit 1
fi
grep -F 'ValueError: Unexpected signing certificate' "$tmp/rejection"
