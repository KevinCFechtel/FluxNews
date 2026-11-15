#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
GRADLEW="${ANDROID_DIR}/gradlew"

[[ -x "${GRADLEW}" ]] || {
  echo "Gradle Wrapper is missing or not executable: ${GRADLEW}" >&2
  exit 1
}

command -v adb >/dev/null 2>&1 || {
  echo "adb is required to generate the Baseline Profile." >&2
  exit 1
}

DEVICE_COUNT="$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')"
[[ "${DEVICE_COUNT}" -eq 1 ]] || {
  echo "Exactly one connected Android device is required; found ${DEVICE_COUNT}." >&2
  exit 1
}

SDK="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
[[ "${SDK}" =~ ^[0-9]+$ ]] || {
  echo "Could not determine the connected device API level." >&2
  exit 1
}
if (( SDK < 33 )); then
  echo "Baseline Profile generation with a connected device requires API 33+; found API ${SDK}." >&2
  exit 1
fi

exec "${GRADLEW}" --project-dir "${ANDROID_DIR}" :app:generateBaselineProfile
