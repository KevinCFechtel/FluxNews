#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'HELP'
Usage: bash Build/release.sh <android|ios|macos> [--debug] [--version-code N] [--version-name V]
       bash Build/release.sh android --target play --version-code N --version-name V
       bash Build/release.sh ios --target appstore --version-code N --version-name V
       bash Build/release.sh macos --target appstore --version-code N --version-name V
       bash Build/release.sh macos --target developer-id [--version-code N --version-name V]

Defaults to production RELEASE builds (never publishes).
  android: productionRelease APK
  ios:     production identity build (Upgrade Test configuration)
  macos:   Release app
--debug opts into a development/debug build.
--target play creates a signed production AAB; requires signing properties.
--target appstore archives and exports an Apple Store artifact for manual upload.
--target developer-id (macOS) signs and notarizes an outside-store release ZIP.
--version-code is the Android versionCode or Apple CFBundleVersion.
Build/release.sh reads Build/versions/<platform>.properties by default; explicit version arguments override both.
HELP
}

die() { echo "Error: $*" >&2; exit 2; }
[[ $# -gt 0 ]] || { usage >&2; exit 2; }
case "$1" in -h|--help) usage; exit 0;; android|ios|macos) platform="$1"; shift;; *) die "Unknown platform: $1";; esac
debug=0; target=build; version_code=; version_name=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) debug=1; shift;;
    --target) [[ $# -ge 2 ]] || die "Missing --target value"; target="$2"; shift 2;;
    --version-code) [[ $# -ge 2 ]] || die "Missing --version-code value"; version_code="$2"; shift 2;;
    --version-name) [[ $# -ge 2 ]] || die "Missing --version-name value"; version_name="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
done
[[ -z "$version_code" && -z "$version_name" || -n "$version_code" && -n "$version_name" ]] || die "Version code and name must be provided together"
if [[ -z "$version_code" && -z "$version_name" ]]; then
  version_file="$ROOT/Build/versions/${platform}.properties"
  [[ -f "$version_file" ]] || die "Missing platform version file: $version_file"
  version_code="$(sed -n 's/^BUILD_NUMBER=//p' "$version_file")"
  version_name="$(sed -n 's/^VERSION_NAME=//p' "$version_file")"
  [[ -n "$version_code" && -n "$version_name" ]] || die "Missing version code or name in platform version file: $version_file"
fi
if [[ -n "$version_code" ]]; then
  [[ "$version_code" =~ ^[1-9][0-9]*$ ]] || die "Version code must be a positive integer"
  [[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || die "Invalid version name"
fi
args=()
if [[ -n "$version_code" ]]; then args+=("$version_code" "$version_name"); fi
case "$platform:$target" in
  android:build)
    if ((debug)); then variant=developmentDebug; else variant=productionRelease; fi
    exec bash "$ROOT/android/Build/build-app.sh" "$variant" "${args[@]}"
    ;;
  android:play)
    (( !debug )) || die "--debug cannot be combined with --target play"
    [[ -n "$version_code" ]] || die "Play bundle requires explicit version"
    bash "$ROOT/android/Build/build-app.sh" productionBundle "${args[@]}"
    artifact="$ROOT/android/app/build/outputs/bundle/productionRelease/app-production-release.aab"
    [[ -s "$artifact" ]] || die "Production AAB missing or empty: $artifact"
    mkdir -p "$ROOT/dist/android/play"
    cp "$artifact" "$ROOT/dist/android/play/FluxNews-${version_name}-${version_code}.aab"
    echo "Play artifact: $ROOT/dist/android/play/FluxNews-${version_name}-${version_code}.aab (not uploaded)"
    ;;
  ios:build)
    if ((debug)); then variant=developmentDebug; else variant=productionRelease; fi
    exec bash "$ROOT/apple/ios/Build/build-app.sh" "$variant" "${args[@]}"
    ;;
  ios:appstore)
    (( !debug )) || die "--debug cannot be combined with --target appstore"
    [[ -n "$version_code" ]] || die "App Store export requires explicit version"
    bash "$ROOT/apple/ios/Build/archive.sh" productionRelease "${args[@]}"
    export EXPORT_PATH="$ROOT/dist/ios/appstore"
    exec bash "$ROOT/apple/ios/Build/export-appstore.sh" productionRelease
    ;;
  macos:developer-id)
    (( !debug )) || die "--debug cannot be combined with --target developer-id"
    mac_args=()
    if [[ -n "$version_code" ]]; then mac_args+=(--build-number "$version_code" --version-name "$version_name"); fi
    exec bash "$ROOT/apple/macos/Build/release-developer-id.sh" "${mac_args[@]}"
    ;;
  macos:appstore)
    (( !debug )) || die "--debug cannot be combined with --target appstore"
    [[ -n "$version_code" ]] || die "App Store export requires explicit version"
    bash "$ROOT/apple/macos/Build/archive.sh" "${args[@]}"
    exec bash "$ROOT/apple/macos/Build/export-appstore.sh"
    ;;
  macos:build)
    if ((debug)); then export CONFIGURATION=Debug; else export CONFIGURATION=Release; fi
    mac_args=()
    if [[ -n "$version_code" ]]; then mac_args+=(--build-number "$version_code" --version-name "$version_name"); fi
    exec bash "$ROOT/apple/macos/Build/build-app.sh" "${mac_args[@]}"
    ;;
  *) die "Unsupported target '$target' for $platform (F-Droid is pending)";;
esac
