#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
GRADLEW="${ANDROID_DIR}/gradlew"

[[ -x "${GRADLEW}" ]] || {
  echo "Gradle Wrapper is missing or not executable: ${GRADLEW}" >&2
  exit 1
}

# The test gate validates compilation, unit tests, and lint only. APK/AAB
# artifacts belong to build-app.sh and its signing-specific variants.
exec "${GRADLEW}" --project-dir "${ANDROID_DIR}" testDevelopmentDebugUnitTest lintDevelopmentDebug
