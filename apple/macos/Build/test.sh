#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
PROJECT="${REPOSITORY_DIR}/apple/macos/FluxNews.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-${REPOSITORY_DIR}/.build/DerivedData-macos}"
DESTINATION="${DESTINATION:-platform=macOS}"

python3 "${REPOSITORY_DIR}/apple/macos/Build/check-localization.py"
for script in build-app.sh install-local.sh verify-sandbox.sh release-developer-id.sh; do
  bash -n "${SCRIPT_DIR}/${script}"
done
"${SCRIPT_DIR}/verify-sandbox.sh" --help >/dev/null

"${REPOSITORY_DIR}/apple/Build/build-uniffi.sh"

# The test gate validates compilation and tests only. Installable/signed app
# artifacts belong to build-app.sh and release-developer-id.sh.
FLUX_UNIFFI_PREPARED=1 xcodebuild \
  -project "${PROJECT}" \
  -scheme FluxNews \
  -configuration Debug \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
