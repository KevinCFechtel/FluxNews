#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
PROJECT="${REPOSITORY_DIR}/apple/ios/FluxNews.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-${REPOSITORY_DIR}/.build/DerivedData}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-8X9VDP43J9}"
CONFIGURATION="Upgrade Test"
BUILD_NUMBER=""
VERSION_NAME=""

usage() {
  cat <<'EOF'
Usage: archive.sh [developmentRelease|productionRelease] [buildNumber versionName]
       archive.sh [--configuration "Release|Upgrade Test"] [--build-number BUILD_NUMBER] [--version-name VERSION_NAME]

Examples:
  archive.sh
  archive.sh --build-number 115
  archive.sh productionRelease 3001 3.0.0
  archive.sh developmentRelease 3001 3.0.0
  archive.sh --configuration "Upgrade Test" --build-number 3001 --version-name 3.0.0

Release archives the parallel native-development identity.
Upgrade Test archives the production identity used for Flutter-to-native upgrade validation.
EOF
}

if [[ $# -gt 0 && "${1}" != -* ]]; then
  case "$1" in
    developmentRelease) CONFIGURATION=Release ;;
    productionRelease) CONFIGURATION="Upgrade Test" ;;
    *) echo "Unknown archive variant: $1" >&2; exit 2 ;;
  esac
  shift
  if [[ $# -gt 0 && "${1}" != -* ]]; then
    [[ $# -ge 2 && "${2}" != -* ]] || { echo "Pass buildNumber and versionName together." >&2; exit 2; }
    BUILD_NUMBER="$1"; VERSION_NAME="$2"; shift 2
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { echo "Missing value for --configuration." >&2; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --version-name)
      [[ $# -ge 2 ]] || { echo "Missing version name." >&2; exit 2; }
      VERSION_NAME="$2"; shift 2 ;;
    --build-number)
      [[ $# -ge 2 ]] || { echo "Missing value for --build-number." >&2; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${CONFIGURATION}" in
  Release)
    IDENTITY_NAME="NativeDev"
    EXPECTED_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews.nativeDev"
    EXPECTED_WIDGET_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews.nativeDev.FluxNewsWidgets"
    EXPECTED_APP_GROUP_IDENTIFIER="group.dev.kevincfechtel.fluxNews.nativeDev"
    DEFAULT_ARCHIVE_PATH="${REPOSITORY_DIR}/.build/Archives/FluxNews-nativeDev.xcarchive"
    ;;
  "Upgrade Test")
    IDENTITY_NAME="UpgradeTest"
    EXPECTED_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews"
    EXPECTED_WIDGET_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews.FluxNewsWidgets"
    EXPECTED_APP_GROUP_IDENTIFIER="group.dev.kevincfechtel.fluxNews"
    DEFAULT_ARCHIVE_PATH="${REPOSITORY_DIR}/.build/Archives/FluxNews-upgradeTest.xcarchive"
    ;;
  *)
    echo "Unsupported configuration: ${CONFIGURATION}" >&2
    echo 'Expected "Release" or "Upgrade Test".' >&2
    exit 2
    ;;
esac

ARCHIVE_PATH="${ARCHIVE_PATH:-${DEFAULT_ARCHIVE_PATH}}"

source "${SCRIPT_DIR}/versioning.sh"
[[ -z "${BUILD_NUMBER}" || -n "${VERSION_NAME}" ]] || { echo "Pass versionName with buildNumber." >&2; exit 2; }
flux_ios_prepare_version_settings "${BUILD_NUMBER}" "${VERSION_NAME}"

for command_name in awk codesign plutil xcodebuild /usr/libexec/PlistBuddy; do
  command -v "${command_name}" >/dev/null 2>&1 || { echo "Required command missing: ${command_name}" >&2; exit 1; }
done

"${REPOSITORY_DIR}/apple/Build/build-uniffi.sh"

build_settings="$(xcodebuild \
  -project "${PROJECT}" \
  -scheme FluxNews \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -derivedDataPath "${DERIVED_DATA}" \
  -showBuildSettings -quiet)"
configured_bundle_identifier="$(awk -F ' = ' '$1 ~ /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER$/ { print $2; exit }' <<<"${build_settings}")"
[[ "${configured_bundle_identifier}" == "${EXPECTED_BUNDLE_IDENTIFIER}" ]] || {
  echo "Refusing to archive unexpected Bundle ID: ${configured_bundle_identifier:-<missing>}" >&2
  echo "Expected: ${EXPECTED_BUNDLE_IDENTIFIER}" >&2
  exit 1
}
configured_team="$(awk -F ' = ' '$1 ~ /^[[:space:]]*DEVELOPMENT_TEAM$/ { print $2; exit }' <<<"${build_settings}")"
if [[ -z "${configured_team}" && -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Automatic signing requires an Apple Developer Team ID." >&2
  echo "Set DEVELOPMENT_TEAM locally or configure the project in Xcode; no team is stored by this script." >&2
  exit 1
fi

configured_build_number="$(awk -F ' = ' '$1 ~ /^[[:space:]]*CURRENT_PROJECT_VERSION$/ { print $2; exit }' <<<"${build_settings}")"
[[ -n "${BUILD_NUMBER}" ]] || BUILD_NUMBER="${configured_build_number}"
flux_ios_prepare_version_settings "${BUILD_NUMBER}" "${VERSION_NAME}"
[[ "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]] || {
  echo "Configured build number is not a positive integer: ${BUILD_NUMBER:-<missing>}" >&2
  exit 1
}

rm -rf -- "${ARCHIVE_PATH}"
mkdir -p "$(dirname -- "${ARCHIVE_PATH}")"

xcodebuild_args=(
  -project "${PROJECT}"
  -scheme FluxNews
  -configuration "${CONFIGURATION}"
  -destination "generic/platform=iOS"
  -derivedDataPath "${DERIVED_DATA}"
  -archivePath "${ARCHIVE_PATH}"
  -allowProvisioningUpdates
  CODE_SIGN_STYLE=Automatic
  "${IOS_VERSION_SETTINGS[@]}"
  SWIFT_COMPILATION_MODE=wholemodule
)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  xcodebuild_args+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}")
fi

FLUX_UNIFFI_PREPARED=1 xcodebuild "${xcodebuild_args[@]}" archive

archived_app="${ARCHIVE_PATH}/Products/Applications/FluxNews.app"
archived_info_plist="${archived_app}/Info.plist"
archived_widget="${archived_app}/PlugIns/FluxNewsWidgets.appex"
archived_widget_info_plist="${archived_widget}/Info.plist"

[[ -d "${archived_app}" ]] || { echo "Archived app is missing: ${archived_app}" >&2; exit 1; }
[[ -x "${archived_app}/FluxNews" ]] || { echo "Archived executable is missing: ${archived_app}/FluxNews" >&2; exit 1; }
[[ -d "${archived_widget}" ]] || { echo "Archived widget extension is missing: ${archived_widget}" >&2; exit 1; }

archived_bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${archived_info_plist}")"
[[ "${archived_bundle_identifier}" == "${EXPECTED_BUNDLE_IDENTIFIER}" ]] || {
  echo "Refusing archive with unexpected Bundle ID: ${archived_bundle_identifier}" >&2
  echo "Expected: ${EXPECTED_BUNDLE_IDENTIFIER}" >&2
  exit 1
}

archived_widget_bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${archived_widget_info_plist}")"
[[ "${archived_widget_bundle_identifier}" == "${EXPECTED_WIDGET_BUNDLE_IDENTIFIER}" ]] || {
  echo "Unexpected widget Bundle ID: ${archived_widget_bundle_identifier}" >&2
  echo "Expected: ${EXPECTED_WIDGET_BUNDLE_IDENTIFIER}" >&2
  exit 1
}

archived_build_number="$(plutil -extract CFBundleVersion raw "${archived_info_plist}")"
archived_version_name="$(plutil -extract CFBundleShortVersionString raw "${archived_info_plist}")"
[[ "${archived_build_number}" == "${BUILD_NUMBER}" ]] || {
  echo "Archived build number mismatch: ${archived_build_number} (expected ${BUILD_NUMBER})." >&2
  exit 1
}

if [[ -n "${VERSION_NAME}" && "${archived_version_name}" != "${VERSION_NAME}" ]]; then
  echo "Archived version name mismatch: ${archived_version_name} (expected ${VERSION_NAME})." >&2; exit 1
fi
widget_version_name="$(plutil -extract CFBundleShortVersionString raw "${archived_widget_info_plist}")"
widget_build_number="$(plutil -extract CFBundleVersion raw "${archived_widget_info_plist}")"
[[ "${widget_version_name}" == "${archived_version_name}" && "${widget_build_number}" == "${archived_build_number}" ]] || { echo "Widget version/build mismatch." >&2; exit 1; }

archived_package_type="$(plutil -extract CFBundlePackageType raw "${archived_info_plist}")"
[[ "${archived_package_type}" == "APPL" ]] || {
  echo "Archived package type mismatch: ${archived_package_type} (expected APPL)." >&2
  exit 1
}

archived_icon_name="$(plutil -extract CFBundleIconName raw "${archived_info_plist}")"
[[ "${archived_icon_name}" == "AppIcon" ]] || {
  echo "Archived icon name mismatch: ${archived_icon_name} (expected AppIcon)." >&2
  exit 1
}

for icon_resource in \
  "${archived_app}/Assets.car" \
  "${archived_app}/AppIcon60x60@2x.png" \
  "${archived_app}/AppIcon76x76@2x~ipad.png"; do
  [[ -f "${icon_resource}" ]] || {
    echo "Archived app icon resource is missing: ${icon_resource}" >&2
    exit 1
  }
done

ENTITLEMENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/flux-ios-entitlements.XXXXXX")"
trap 'rm -f -- "${ENTITLEMENTS_FILE}"' EXIT

verify_app_group_entitlement() {
  local component="$1"
  if ! codesign -d --entitlements - --xml "${component}" > "${ENTITLEMENTS_FILE}" 2>/dev/null; then
    echo "Could not extract signed entitlements for ${component}." >&2
    exit 1
  fi
  if [[ ! -s "${ENTITLEMENTS_FILE}" ]] || ! plutil -lint "${ENTITLEMENTS_FILE}" >/dev/null 2>&1; then
    echo "Signed entitlements for ${component} are missing or not a valid XML plist." >&2
    exit 1
  fi
  local actual_group
  actual_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "${ENTITLEMENTS_FILE}" 2>/dev/null || true)"
  [[ "${actual_group}" == "${EXPECTED_APP_GROUP_IDENTIFIER}" ]] || {
    echo "Unexpected App Group entitlement for ${component}: ${actual_group:-<missing>}" >&2
    echo "Expected: ${EXPECTED_APP_GROUP_IDENTIFIER}" >&2
    exit 1
  }
}

verify_app_group_entitlement "${archived_app}"
verify_app_group_entitlement "${archived_widget}"

codesign --verify --strict --verbose=2 "${archived_widget}"
codesign --verify --deep --strict --verbose=2 "${archived_app}"

echo "${IDENTITY_NAME} archive: ${ARCHIVE_PATH}"
echo "Host Bundle ID: ${archived_bundle_identifier}"
echo "Widget Bundle ID: ${archived_widget_bundle_identifier}"
echo "App Group: ${EXPECTED_APP_GROUP_IDENTIFIER}"
echo "Version: ${archived_version_name}"
echo "Build number: ${archived_build_number}"
echo "Package type: ${archived_package_type}"
echo "Icon name: ${archived_icon_name}"
echo "App icon resources: Assets.car, AppIcon60x60@2x.png, AppIcon76x76@2x~ipad.png"
