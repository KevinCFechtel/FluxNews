#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 ]] || { echo "Usage: $0 unsigned.apk versionName versionCode" >&2; exit 2; }
src="$1"; version="$2"; code="$3"
[[ -s "$src" && "$code" =~ ^[1-9][0-9]*$ ]] || exit 1
for name in KEYSTORE_BASE64 KEYSTORE_PASSWORD KEY_PASSWORD KEY_ALIAS; do
  [[ -n "${!name:-}" ]] || { echo "Missing required environment secret: $name" >&2; exit 1; }
done
buildtools="${ANDROID_HOME:?}/build-tools/37.0.0"
[[ -x "$buildtools/apksigner" && -x "$buildtools/aapt" ]] || exit 1
mkdir -p dist/android/github
apk="dist/android/github/FluxNews-${version}-${code}-developer.apk"
ks="$(mktemp "${RUNNER_TEMP:-/tmp}/flux-release-key.XXXXXX")"
trap 'rm -f -- "$ks"' EXIT
printf '%s' "$KEYSTORE_BASE64" | base64 --decode > "$ks"
chmod 600 "$ks"
"$buildtools/apksigner" sign --ks "$ks" --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KEYSTORE_PASSWORD --key-pass env:KEY_PASSWORD \
  --out "$apk" "$src"
"$buildtools/apksigner" verify --verbose --print-certs "$apk" > "${RUNNER_TEMP:-/tmp}/flux-apk-signing-verify.txt"
verify_output="${RUNNER_TEMP:-/tmp}/flux-apk-signing-verify.txt"
echo "APK signer certificate diagnostics:"
cat "$verify_output"
fingerprint="$(sed -nE 's/^[[:space:]]*((V[0-9]+(\.[0-9]+)?[[:space:]]+)?Signer( #[0-9]+)?): certificate SHA-?256 digest:[[:space:]]*([[:xdigit:]:]+)[[:space:]]*$/\5/p' "$verify_output" | head -1 | tr -d ':' | tr 'A-F' 'a-f')"
expected="fee5401bc9d59cf5a8a461ba9698c482e87ed8ffb9258786a3d01d0356ea2ebb"
echo "Actual APK signing certificate SHA-256: ${fingerprint:-<unavailable>}"
echo "Expected APK signing certificate SHA-256: $expected"
[[ -n "$fingerprint" && "$fingerprint" == "$expected" ]] || { echo "::error::Wrong developer signing certificate" >&2; exit 1; }
line="$("$buildtools/aapt" dump badging "$apk" | grep '^package:')"
[[ "$line" == *"name='de.circle_dev.flux_news'"* && "$line" == *"versionCode='$code'"* && "$line" == *"versionName='$version'"* ]] || { echo "Signed APK identity mismatch" >&2; exit 1; }
(cd dist/android/github && sha256sum *.apk > SHA256SUMS)
echo "Signed and verified: $apk"
