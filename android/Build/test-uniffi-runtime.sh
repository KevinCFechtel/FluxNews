#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
GRADLEW="${ANDROID_DIR}/gradlew"
TEST_CLASS="de.circledev.fluxnews.nativeapp.UniFFIRuntimeSmokeTest"
ARGUMENT_SERIAL="${1:-}"

usage() {
  echo "Usage: test-uniffi-runtime.sh [device-serial]"
}

[[ $# -le 1 ]] || {
  usage >&2
  exit 2
}
[[ -x "${GRADLEW}" ]] || {
  echo "Gradle Wrapper is missing or not executable: ${GRADLEW}" >&2
  exit 1
}
command -v adb >/dev/null 2>&1 || {
  echo "Required command missing: adb" >&2
  exit 1
}

if [[ -n "${ARGUMENT_SERIAL}" && -n "${ANDROID_SERIAL:-}" && "${ARGUMENT_SERIAL}" != "${ANDROID_SERIAL}" ]]; then
  echo "The device serial argument and ANDROID_SERIAL disagree." >&2
  exit 2
fi

SERIAL="${ARGUMENT_SERIAL:-${ANDROID_SERIAL:-}}"
if [[ -z "${SERIAL}" ]]; then
  devices=()
  skip_header=1
  while IFS=$'\t' read -r candidate state _; do
    if [[ "${skip_header}" == "1" ]]; then
      skip_header=0
      continue
    fi
    [[ "${state}" == "device" ]] && devices+=("${candidate}")
  done < <(adb devices)

  case "${#devices[@]}" in
    0)
      echo "No usable Android device is connected. Supply a serial after connecting a device." >&2
      exit 1
      ;;
    1) SERIAL="${devices[0]}" ;;
    *)
      echo "Multiple Android devices are connected. Supply a device serial explicitly:" >&2
      printf '  %s\n' "${devices[@]}" >&2
      exit 2
      ;;
  esac
fi

[[ "$(adb -s "${SERIAL}" get-state)" == "device" ]] || {
  echo "Android device is not usable: ${SERIAL}" >&2
  exit 1
}

API_LEVEL="$(adb -s "${SERIAL}" shell getprop ro.build.version.sdk | tr -d '\r')"
ABI_LIST="$(adb -s "${SERIAL}" shell getprop ro.product.cpu.abilist | tr -d '\r')"
DEVICE_NAME="$(adb -s "${SERIAL}" shell getprop ro.product.model | tr -d '\r')"
EMULATOR="$(adb -s "${SERIAL}" shell getprop ro.kernel.qemu | tr -d '\r')"

echo "Device serial: ${SERIAL}"
echo "Device: ${DEVICE_NAME}"
echo "Android API: ${API_LEVEL}"
echo "ABIs: ${ABI_LIST}"
echo "Emulator: ${EMULATOR}"
echo "Running developmentDebug UniFFI runtime smoke only."

ANDROID_SERIAL="${SERIAL}" exec "${GRADLEW}" --project-dir "${ANDROID_DIR}" \
  connectedDevelopmentDebugAndroidTest \
  "-Pandroid.testInstrumentationRunnerArguments.class=${TEST_CLASS}"
