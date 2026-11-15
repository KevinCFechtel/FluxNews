#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
PROJECT="${REPOSITORY_DIR}/apple/ios/FluxNews.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-${REPOSITORY_DIR}/.build/DerivedData}"

if [[ -z "${DESTINATION:-}" ]]; then
  simulator_udid=""
  simulator_name=""
  while IFS='|' read -r candidate_name candidate_udid candidate_state; do
    if [[ "${candidate_state}" == "Booted" && "${candidate_name}" == iPhone* ]]; then
      simulator_name="${candidate_name}"
      simulator_udid="${candidate_udid}"
      break
    fi
    if [[ -z "${simulator_udid}" && "${candidate_name}" == iPhone* ]]; then
      simulator_name="${candidate_name}"
      simulator_udid="${candidate_udid}"
    fi
  done < <(xcrun simctl list devices available | sed -nE 's/^[[:space:]]+(.+) \(([A-Fa-f0-9-]{36})\) \((Booted|Shutdown)\).*$/\1|\2|\3/p')

  if [[ -z "${simulator_udid}" ]]; then
    echo "No available iPhone simulator found." >&2
    echo "Use 'xcrun simctl list devices available' to inspect installed simulators." >&2
    exit 1
  fi
  DESTINATION="platform=iOS Simulator,id=${simulator_udid}"
  echo "Testing on ${simulator_name} (${simulator_udid})"
fi

"${REPOSITORY_DIR}/apple/Build/build-uniffi.sh"

# The simulator test gate validates compilation and tests only. Signed device
# artifacts belong to build-app.sh/archive.sh/export-appstore.sh.
FLUX_UNIFFI_PREPARED=1 xcodebuild \
  -project "${PROJECT}" \
  -scheme FluxNews \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
