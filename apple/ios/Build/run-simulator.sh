#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
PROJECT="${REPOSITORY_DIR}/apple/ios/FluxNews.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-${REPOSITORY_DIR}/.build/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Debug}"
REQUESTED_NAME=""

usage() {
  cat <<'EOF'
Usage: run-simulator.sh [SIMULATOR_NAME]

Examples:
  run-simulator.sh
  run-simulator.sh "iPhone 11 Pro Max"
  run-simulator.sh --configuration "Upgrade Test" "iPhone 11 Pro Max"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { echo "Missing value for --configuration." >&2; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      [[ -z "${REQUESTED_NAME}" ]] || { echo "Only one simulator name may be supplied." >&2; exit 2; }
      REQUESTED_NAME="$1"
      shift
      ;;
  esac
done

simulator_udid=""
simulator_name=""
while IFS='|' read -r candidate_name candidate_udid candidate_state; do
  if [[ -n "${REQUESTED_NAME}" && "${candidate_name}" == "${REQUESTED_NAME}" ]]; then
    simulator_name="${candidate_name}"
    simulator_udid="${candidate_udid}"
    break
  fi
  if [[ -z "${REQUESTED_NAME}" && "${candidate_state}" == "Booted" && "${candidate_name}" == iPhone* ]]; then
    simulator_name="${candidate_name}"
    simulator_udid="${candidate_udid}"
    break
  fi
  if [[ -z "${REQUESTED_NAME}" && -z "${simulator_udid}" && "${candidate_name}" == iPhone* ]]; then
    simulator_name="${candidate_name}"
    simulator_udid="${candidate_udid}"
  fi
done < <(xcrun simctl list devices available | sed -nE 's/^[[:space:]]+(.+) \(([A-Fa-f0-9-]{36})\) \((Booted|Shutdown)\).*$/\1|\2|\3/p')

if [[ -z "${simulator_udid}" ]]; then
  if [[ -n "${REQUESTED_NAME}" ]]; then
    echo "No available iOS simulator named '${REQUESTED_NAME}'." >&2
  else
    echo "No available iPhone simulator found." >&2
  fi
  echo "Use 'xcrun simctl list devices available' to inspect installed simulators." >&2
  exit 1
fi

if [[ "$(xcrun simctl list devices | awk -v id="${simulator_udid}" '$0 ~ id && $0 ~ /Booted/ { print "booted"; exit }')" != "booted" ]]; then
  xcrun simctl boot "${simulator_udid}" >/dev/null 2>&1 || true
fi
xcrun simctl bootstatus "${simulator_udid}" -b

"${SCRIPT_DIR}/build-app.sh" \
  --configuration "${CONFIGURATION}" \
  --destination "platform=iOS Simulator,id=${simulator_udid}"

build_settings="$(xcodebuild \
  -project "${PROJECT}" \
  -scheme FluxNews \
  -configuration "${CONFIGURATION}" \
  -destination "platform=iOS Simulator,id=${simulator_udid}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -showBuildSettings -quiet)"
target_build_dir="$(awk -F ' = ' '$1 ~ /^[[:space:]]*TARGET_BUILD_DIR$/ { print $2; exit }' <<<"${build_settings}")"
[[ -n "${target_build_dir}" ]] || { echo "Could not determine the Xcode output directory." >&2; exit 1; }
app_path="${target_build_dir}/FluxNews.app"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${app_path}/Info.plist")"

xcrun simctl install "${simulator_udid}" "${app_path}"

SIMCTL_CHILD_FLUX_DEV_BASE_URL="${FLUX_DEV_BASE_URL:-}" \
SIMCTL_CHILD_FLUX_DEV_API_KEY="${FLUX_DEV_API_KEY:-}" \
xcrun simctl launch "${simulator_udid}" "${bundle_identifier}"

echo "Launched ${bundle_identifier} on ${simulator_name} (${simulator_udid})"
