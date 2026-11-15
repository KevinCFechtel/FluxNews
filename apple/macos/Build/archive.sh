#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
TEAM="${DEVELOPMENT_TEAM:-8X9VDP43J9}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/.build/Archives/FluxNews-macos-production.xcarchive}"
BUILD_NUMBER=""; VERSION_NAME=""
usage() {
  echo "Usage: bash apple/macos/Build/archive.sh <buildNumber> <versionName>"
  echo "Creates a macOS production xcarchive; App Store distribution signing is validated after export."
}
if [[ "${1:-}" == --help ]]; then usage; exit 0; fi
[[ $# -eq 2 ]] || { usage >&2; exit 2; }
BUILD_NUMBER="$1"; VERSION_NAME="$2"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid build number" >&2; exit 2; }
[[ "$VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || { echo "Invalid version" >&2; exit 2; }
for cmd in xcodebuild codesign plutil; do command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 1; }; done
"$SCRIPT_DIR/build-uniffi.sh"
FLUX_UNIFFI_PREPARED=1 xcodebuild \
  -project "$ROOT/apple/macos/FluxNews.xcodeproj" \
  -scheme FluxNews -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$ROOT/.build/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$VERSION_NAME" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO archive
APP="$ARCHIVE_PATH/Products/Applications/FluxNews.app"
[[ -d "$APP" ]] || { echo "Missing archived app: $APP" >&2; exit 1; }
"$SCRIPT_DIR/verify-sandbox.sh" "$APP" archive
echo "macOS production archive: $ARCHIVE_PATH"
