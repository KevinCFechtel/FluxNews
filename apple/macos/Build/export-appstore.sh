#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/.build/Archives/FluxNews-macos-production.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT/dist/macos/appstore}"
TEAM="${DEVELOPMENT_TEAM:-8X9VDP43J9}"
if [[ "${1:-}" == --help ]]; then
  echo "Usage: bash apple/macos/Build/export-appstore.sh [--help]"
  echo "Requires a signed production archive; prepares a PKG for manual Transporter upload."
  exit 0
fi
[[ $# -eq 0 ]] || { echo "Unexpected argument: $1" >&2; exit 2; }
for cmd in xcodebuild plutil codesign; do command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 1; }; done
APP="$ARCHIVE_PATH/Products/Applications/FluxNews.app"
[[ -d "$APP" ]] || { echo "Missing macOS archive app: $APP" >&2; exit 1; }
"$SCRIPT_DIR/verify-sandbox.sh" "$APP" archive
options="$(mktemp "${TMPDIR:-/tmp}/flux-macos-export.XXXXXX.plist")"
trap 'rm -f "$options"' EXIT
plutil -create xml1 "$options"
plutil -insert method -string app-store-connect "$options"
plutil -insert destination -string export "$options"
plutil -insert signingStyle -string automatic "$options"
plutil -insert teamID -string "$TEAM" "$options"
mkdir -p "$EXPORT_PATH"
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" -exportOptionsPlist "$options" -allowProvisioningUpdates
shopt -s nullglob
packages=("$EXPORT_PATH"/*.pkg)
(( ${#packages[@]} > 0 )) || { echo "No App Store PKG exported in $EXPORT_PATH" >&2; exit 1; }
for pkg in "${packages[@]}"; do [[ -s "$pkg" ]] || { echo "Empty exported PKG: $pkg" >&2; exit 1; }; done
echo "macOS App Store Connect PKG(s): ${packages[*]}"
echo "Ready for manual Transporter upload; nothing was uploaded."
