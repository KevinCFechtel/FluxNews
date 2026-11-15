#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
VARIANT="productionRelease"
ARCHIVE_PATH="${ARCHIVE_PATH:-}"
EXPORT_PATH="${EXPORT_PATH:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-8X9VDP43J9}"

usage() {
  cat <<'EOF'
Usage: export-appstore.sh [developmentRelease|productionRelease]
       export-appstore.sh [developmentRelease|productionRelease] [--archive ARCHIVE_PATH] [--export-path EXPORT_PATH]

Variants:
  developmentRelease  NativeDev identity (explicit opt-in).
  productionRelease   Production identity (default), for App Store Connect export.

Examples:
  ./apple/ios/Build/archive.sh productionRelease 3001 3.0.0
  ./apple/ios/Build/export-appstore.sh productionRelease
  ./apple/ios/Build/export-appstore.sh developmentRelease
  ./apple/ios/Build/export-appstore.sh

The script exports a local App Store Connect IPA for manual Transporter upload.
It does not upload, invite testers, or publish anything.
EOF
}

if [[ $# -gt 0 && "${1}" != -* ]]; then
  case "$1" in
    developmentRelease|productionRelease) VARIANT="$1"; shift ;;
    *) echo "Unknown export variant: $1" >&2; exit 2 ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || { echo "Missing value for --archive." >&2; exit 2; }
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --export-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --export-path." >&2; exit 2; }
      EXPORT_PATH="$2"
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

case "${VARIANT}" in
  developmentRelease)
    IDENTITY_NAME="NativeDev"
    EXPECTED_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews.nativeDev"
    EXPECTED_WIDGET_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews.nativeDev.FluxNewsWidgets"
    EXPECTED_APP_GROUP_IDENTIFIER="group.dev.kevincfechtel.fluxNews.nativeDev"
    EXPECTED_DISPLAY_NAME="FluxNews Dev"
    DEFAULT_ARCHIVE_PATH="${REPOSITORY_DIR}/.build/Archives/FluxNews-nativeDev.xcarchive"
    DEFAULT_EXPORT_PATH="${REPOSITORY_DIR}/dist/TestFlightExport"
    ;;
  productionRelease)
    IDENTITY_NAME="Production (Flutter upgrade)"
    EXPECTED_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews"
    EXPECTED_WIDGET_BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews.FluxNewsWidgets"
    EXPECTED_APP_GROUP_IDENTIFIER="group.dev.kevincfechtel.fluxNews"
    EXPECTED_DISPLAY_NAME="FluxNews"
    DEFAULT_ARCHIVE_PATH="${REPOSITORY_DIR}/.build/Archives/FluxNews-upgradeTest.xcarchive"
    DEFAULT_EXPORT_PATH="${REPOSITORY_DIR}/dist/ProductionExport"
    ;;
esac

[[ -n "${ARCHIVE_PATH}" ]] || ARCHIVE_PATH="${DEFAULT_ARCHIVE_PATH}"
[[ -n "${EXPORT_PATH}" ]] || EXPORT_PATH="${DEFAULT_EXPORT_PATH}"

for command_name in plutil unzip xcodebuild codesign /usr/libexec/PlistBuddy; do
  command -v "${command_name}" >/dev/null 2>&1 || { echo "Required command missing: ${command_name}" >&2; exit 1; }
done

archived_app="${ARCHIVE_PATH}/Products/Applications/FluxNews.app"
archived_info_plist="${archived_app}/Info.plist"
[[ -d "${archived_app}" ]] || { echo "Archive not found: ${ARCHIVE_PATH}" >&2; echo "Run archive.sh first." >&2; exit 1; }
[[ -f "${archived_info_plist}" ]] || { echo "Archived application Info.plist is missing: ${archived_info_plist}" >&2; exit 1; }
[[ -x "${archived_app}/FluxNews" ]] || { echo "Archived executable is missing: ${archived_app}/FluxNews" >&2; exit 1; }
archived_bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${archived_info_plist}")"
[[ "${archived_bundle_identifier}" == "${EXPECTED_BUNDLE_IDENTIFIER}" ]] || {
  echo "Refusing export of unexpected Bundle ID: ${archived_bundle_identifier}" >&2
  echo "Expected: ${EXPECTED_BUNDLE_IDENTIFIER}" >&2
  exit 1
}

archived_widget="${archived_app}/PlugIns/FluxNewsWidgets.appex"
archived_widget_info_plist="${archived_widget}/Info.plist"
[[ -d "${archived_widget}" && -f "${archived_widget_info_plist}" ]] || {
  echo "Widget extension missing from archive: ${archived_widget}" >&2
  exit 1
}
archived_widget_bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${archived_widget_info_plist}")"
[[ "${archived_widget_bundle_identifier}" == "${EXPECTED_WIDGET_BUNDLE_IDENTIFIER}" ]] || {
  echo "Unexpected archived widget Bundle ID: ${archived_widget_bundle_identifier}" >&2
  exit 1
}
archived_display_name="$(plutil -extract CFBundleDisplayName raw "${archived_info_plist}")"
[[ "${archived_display_name}" == "${EXPECTED_DISPLAY_NAME}" ]] || {
  echo "Unexpected archived display name: ${archived_display_name}" >&2
  exit 1
}
archived_build_number="$(plutil -extract CFBundleVersion raw "${archived_info_plist}")"
archived_version_name="$(plutil -extract CFBundleShortVersionString raw "${archived_info_plist}")"
widget_build_number="$(plutil -extract CFBundleVersion raw "${archived_widget_info_plist}")"
widget_version_name="$(plutil -extract CFBundleShortVersionString raw "${archived_widget_info_plist}")"
[[ -n "${archived_build_number}" && -n "${archived_version_name}" &&
   "${widget_build_number}" == "${archived_build_number}" &&
   "${widget_version_name}" == "${archived_version_name}" ]] || {
  echo "Archive app/widget version mismatch." >&2
  exit 1
}

# An archive from a different Apple identity must never be exported as an upgrade.
entitlements_file="$(mktemp "${TMPDIR:-/tmp}/flux-export-entitlements.XXXXXX")"
trap 'rm -f -- "${entitlements_file}"' EXIT
for component in "${archived_app}" "${archived_widget}"; do
  codesign --verify --strict "${component}" || {
    echo "Invalid archived signature: ${component}" >&2
    exit 1
  }
  # Explicit XML is required: codesign's default entitlement representation
  # is not guaranteed to be a property list readable by PlistBuddy.
  if ! codesign -d --entitlements - --xml "${component}" > "${entitlements_file}" 2>/dev/null; then
    echo "Cannot extract signed entitlements from ${component}." >&2
    exit 1
  fi
  if [[ ! -s "${entitlements_file}" ]] || ! plutil -lint "${entitlements_file}" >/dev/null 2>&1; then
    echo "Signed entitlements are missing or not a valid XML plist for ${component}." >&2
    exit 1
  fi
  group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "${entitlements_file}" 2>/dev/null || true)"
  [[ "${group}" == "${EXPECTED_APP_GROUP_IDENTIFIER}" ]] || {
    echo "Unexpected App Group entitlement: ${group:-<missing>}" >&2
    exit 1
  }
done

export_options_plist="$(mktemp "${TMPDIR:-/tmp}/flux-export.XXXXXX.plist")"
ipa_info_plist=""
widget_ipa_info_plist=""
trap 'rm -f -- "${entitlements_file}" "${export_options_plist}" "${ipa_info_plist}" "${widget_ipa_info_plist}"' EXIT
plutil -create xml1 "${export_options_plist}"
plutil -insert method -string app-store-connect "${export_options_plist}"
plutil -insert destination -string export "${export_options_plist}"
plutil -insert signingStyle -string automatic "${export_options_plist}"
plutil -insert teamID -string "${DEVELOPMENT_TEAM}" "${export_options_plist}"
plutil -insert manageAppVersionAndBuildNumber -bool false "${export_options_plist}"
plutil -insert uploadSymbols -bool true "${export_options_plist}"

rm -rf -- "${EXPORT_PATH}"
mkdir -p "${EXPORT_PATH}"

echo "Exporting ${IDENTITY_NAME} archive for manual TestFlight upload."
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${export_options_plist}" \
  -exportPath "${EXPORT_PATH}" \
  -allowProvisioningUpdates

ipa_candidates=("${EXPORT_PATH}"/*.ipa)
[[ -f "${ipa_candidates[0]}" ]] || { echo "No IPA was produced in ${EXPORT_PATH}." >&2; exit 1; }
[[ ! -e "${ipa_candidates[1]:-}" ]] || { echo "Multiple IPAs were produced in ${EXPORT_PATH}." >&2; exit 1; }
exported_ipa="${ipa_candidates[0]}"

ipa_info_entry=""
widget_ipa_info_entry=""
while IFS= read -r candidate; do
  case "${candidate}" in
    Payload/*.app/Info.plist) ipa_info_entry="${candidate}" ;;
    Payload/*.app/PlugIns/FluxNewsWidgets.appex/Info.plist) widget_ipa_info_entry="${candidate}" ;;
  esac
done < <(unzip -Z1 "${exported_ipa}")
[[ -n "${ipa_info_entry}" && -n "${widget_ipa_info_entry}" ]] || {
  echo "Exported IPA is missing the app or FluxNewsWidgets Info.plist." >&2
  exit 1
}

ipa_info_plist="$(mktemp "${TMPDIR:-/tmp}/flux-ipa-info.XXXXXX.plist")"
widget_ipa_info_plist="$(mktemp "${TMPDIR:-/tmp}/flux-widget-ipa-info.XXXXXX.plist")"
unzip -p "${exported_ipa}" "${ipa_info_entry}" > "${ipa_info_plist}"
unzip -p "${exported_ipa}" "${widget_ipa_info_entry}" > "${widget_ipa_info_plist}"
exported_bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${ipa_info_plist}")"
[[ "${exported_bundle_identifier}" == "${EXPECTED_BUNDLE_IDENTIFIER}" ]] || {
  echo "Refusing exported IPA with unexpected Bundle ID: ${exported_bundle_identifier}" >&2
  echo "Expected: ${EXPECTED_BUNDLE_IDENTIFIER}" >&2
  exit 1
}
exported_widget_bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${widget_ipa_info_plist}")"
[[ "${exported_widget_bundle_identifier}" == "${EXPECTED_WIDGET_BUNDLE_IDENTIFIER}" ]] || {
  echo "Exported widget Bundle ID mismatch: ${exported_widget_bundle_identifier}" >&2
  exit 1
}
exported_build_number="$(plutil -extract CFBundleVersion raw "${ipa_info_plist}")"
exported_version_name="$(plutil -extract CFBundleShortVersionString raw "${ipa_info_plist}")"
exported_widget_build_number="$(plutil -extract CFBundleVersion raw "${widget_ipa_info_plist}")"
exported_widget_version_name="$(plutil -extract CFBundleShortVersionString raw "${widget_ipa_info_plist}")"
[[ "${exported_build_number}" == "${archived_build_number}" &&
   "${exported_version_name}" == "${archived_version_name}" &&
   "${exported_widget_build_number}" == "${exported_build_number}" &&
   "${exported_widget_version_name}" == "${exported_version_name}" ]] || {
  echo "Exported app/widget version differs from the archive." >&2
  exit 1
}
exported_display_name="$(plutil -extract CFBundleDisplayName raw "${ipa_info_plist}")"
[[ "${exported_display_name}" == "${EXPECTED_DISPLAY_NAME}" ]] || {
  echo "Exported display name mismatch: ${exported_display_name} (expected ${EXPECTED_DISPLAY_NAME})." >&2
  exit 1
}

echo "IPA: ${exported_ipa}"
echo "Variant: ${VARIANT}"
echo "Bundle ID: ${exported_bundle_identifier}"
echo "Widget Bundle ID: ${exported_widget_bundle_identifier}"
echo "Version: ${exported_version_name}"
echo "Build number: ${exported_build_number}"
echo "Display name: ${exported_display_name}"
echo "Ready for manual upload with Transporter; nothing was uploaded."
