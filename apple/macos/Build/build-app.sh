#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-${REPOSITORY_DIR}/.build/DerivedData}"
APP_DIR="${APP_DIR:-${REPOSITORY_DIR}/dist/macos/FluxNews.app}"
BUILT_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/FluxNews.app"
APP_ENTITLEMENTS="${REPOSITORY_DIR}/apple/macos/FluxNews/FluxNews.entitlements"
WIDGET_ENTITLEMENTS="${REPOSITORY_DIR}/apple/macos/FluxNewsWidgets/FluxNewsWidgets.entitlements"
HOST_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews"
WIDGET_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews.FluxNewsWidgets"
APP_GROUP_IDENTIFIER="group.dev.kevincfechtel.fluxNews"
DEVELOPMENT_SIGNING="${DEVELOPMENT_SIGNING:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
BUILD_NUMBER=""
VERSION_NAME=""

usage() {
  echo "Usage: bash apple/macos/Build/build-app.sh [--build-number N --version-name V]"
  echo "Default: Release configuration. Set CONFIGURATION=Debug for debug."
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-number) [[ $# -ge 2 ]] || { echo "Missing build number" >&2; exit 2; }; BUILD_NUMBER="$2"; shift 2 ;;
    --version-name) [[ $# -ge 2 ]] || { echo "Missing version name" >&2; exit 2; }; VERSION_NAME="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$BUILD_NUMBER" && -z "$VERSION_NAME" || -n "$BUILD_NUMBER" && -n "$VERSION_NAME" ]] || { echo "Build number and version name must be supplied together" >&2; exit 2; }
if [[ -n "$BUILD_NUMBER" ]]; then
  [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid build number" >&2; exit 2; }
  [[ "$VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || { echo "Invalid version name" >&2; exit 2; }
fi

for command_name in codesign ditto plutil /usr/libexec/PlistBuddy xcodebuild; do
  command -v "${command_name}" >/dev/null 2>&1 || { echo "Required command missing: ${command_name}" >&2; exit 1; }
done

case "${CONFIGURATION}" in
  Debug|Release) ;;
  *)
    echo "Unsupported Xcode configuration: ${CONFIGURATION}" >&2
    exit 1
    ;;
esac

case "${DEVELOPMENT_SIGNING}" in
  0|1) ;;
  *)
    echo "DEVELOPMENT_SIGNING must be 0 or 1." >&2
    exit 1
    ;;
esac

"${SCRIPT_DIR}/build-uniffi.sh"

xcodebuild_args=(
  -project "${REPOSITORY_DIR}/apple/macos/FluxNews.xcodeproj"
  -scheme FluxNews
  -configuration "${CONFIGURATION}"
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED_DATA}"
  ARCHS="arm64 x86_64"
  ONLY_ACTIVE_ARCH=NO
)
if [[ -n "$BUILD_NUMBER" ]]; then
  xcodebuild_args+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$VERSION_NAME")
fi

if [[ "${DEVELOPMENT_SIGNING}" == "1" ]]; then
  xcodebuild_args+=(
    -allowProvisioningUpdates
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=YES
    CODE_SIGN_STYLE=Automatic
    CODE_SIGN_IDENTITY="Apple Development"
    DEVELOPMENT_TEAM=8X9VDP43J9
  )
else
  xcodebuild_args+=(
    CODE_SIGNING_ALLOWED=NO
  )
fi

FLUX_UNIFFI_PREPARED=1 xcodebuild "${xcodebuild_args[@]}" build

rm -rf -- "${APP_DIR}"
mkdir -p "$(dirname -- "${APP_DIR}")"
ditto "${BUILT_APP}" "${APP_DIR}"

# Ad-hoc builds are unsigned until this point so they do not require an Apple
# identity. Development builds retain Xcode's provisioning and target-specific
# signatures; re-signing here would discard their provisioning authorization.
WIDGET_EXTENSION="${APP_DIR}/Contents/PlugIns/FluxNewsWidgets.appex"
UNIFFI_LIBRARY="${APP_DIR}/Contents/Frameworks/libflux_uniffi.dylib"
[[ -d "${WIDGET_EXTENSION}" ]] || { echo "Embedded widget extension is missing: ${WIDGET_EXTENSION}" >&2; exit 1; }
[[ -f "${UNIFFI_LIBRARY}" ]] || { echo "Embedded UniFFI library is missing: ${UNIFFI_LIBRARY}" >&2; exit 1; }
if [[ "${DEVELOPMENT_SIGNING}" == "1" ]]; then
  echo "Using Xcode-configured Apple Development signing."
else
  # Sign nested code explicitly: --deep would replace the extension signature
  # and discard its distinct App Group entitlement.
  codesign --force --sign "${SIGNING_IDENTITY}" --entitlements "${WIDGET_ENTITLEMENTS}" "${WIDGET_EXTENSION}"
  codesign --force --sign "${SIGNING_IDENTITY}" "${UNIFFI_LIBRARY}"
  codesign --force --sign "${SIGNING_IDENTITY}" --entitlements "${APP_ENTITLEMENTS}" "${APP_DIR}"
fi

if [[ "${DEVELOPMENT_SIGNING}" == "1" ]]; then
  "${SCRIPT_DIR}/verify-sandbox.sh" "${APP_DIR}" development
else
  "${SCRIPT_DIR}/verify-sandbox.sh" "${APP_DIR}" adhoc
fi

echo "FluxNews ${CONFIGURATION} app: ${APP_DIR}"
