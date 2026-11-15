#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
GRADLEW="${ANDROID_DIR}/gradlew"
TEST_PACKAGE="de.circledev.fluxnews.nativeapp.transport"
TEST_CA="${ANDROID_DIR}/app/src/androidTest/resources/flux-test-user-ca.crt"
USER_CA_DIR="/data/misc/user/0/cacerts-added"
ARGUMENT_SERIAL="${1:-}"

usage() {
  echo "Usage: test-transport-runtime.sh [device-serial]"
  echo
  echo "Runs the E1-C Android transport proof twice on one device: once with the TEST ONLY"
  echo "instrumentation CA absent from the Android user trust store, and once with it installed."
  echo "The public/system CA gate needs outbound internet access on the device."
}

[[ $# -le 1 ]] || {
  usage >&2
  exit 2
}
case "${ARGUMENT_SERIAL}" in
  --help|-h)
    usage
    exit 0
    ;;
esac

[[ -x "${GRADLEW}" ]] || {
  echo "Gradle Wrapper is missing or not executable: ${GRADLEW}" >&2
  exit 1
}
for command_name in adb openssl; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command_name}" >&2
    exit 1
  }
done
[[ -f "${TEST_CA}" ]] || {
  echo "Instrumentation test CA is missing: ${TEST_CA}" >&2
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
RELEASE="$(adb -s "${SERIAL}" shell getprop ro.build.version.release | tr -d '\r')"

echo "Device serial: ${SERIAL}"
echo "Device: ${DEVICE_NAME}"
echo "Android: ${RELEASE} (API ${API_LEVEL})"
echo "ABIs: ${ABI_LIST}"
echo "Running developmentDebug E1-C transport proof only."

CA_HASH="$(openssl x509 -in "${TEST_CA}" -noout -subject_hash_old)"
CA_TARGET="${USER_CA_DIR}/${CA_HASH}.0"

adb_root_available() {
  adb -s "${SERIAL}" root >/dev/null 2>&1 || return 1
  adb -s "${SERIAL}" wait-for-device
  [[ "$(adb -s "${SERIAL}" shell id -u | tr -d '\r')" == "0" ]]
}

remove_test_ca() {
  adb -s "${SERIAL}" shell "rm -f ${CA_TARGET}" >/dev/null 2>&1 || true
}

install_test_ca() {
  adb -s "${SERIAL}" push "${TEST_CA}" "/data/local/tmp/${CA_HASH}.0" >/dev/null
  adb -s "${SERIAL}" shell "mkdir -p ${USER_CA_DIR} && cp /data/local/tmp/${CA_HASH}.0 ${CA_TARGET} && chmod 644 ${CA_TARGET} && chown system:system ${CA_TARGET} && rm -f /data/local/tmp/${CA_HASH}.0"
}

device_has_test_ca() {
  [[ "$(adb -s "${SERIAL}" shell "[ -f ${CA_TARGET} ] && echo yes || echo no" | tr -d '\r')" == "yes" ]]
}

run_phase() {
  local expectation="$1"
  echo
  echo "=== E1-C transport phase: user-installed CA present = ${expectation} ==="
  ANDROID_SERIAL="${SERIAL}" "${GRADLEW}" --project-dir "${ANDROID_DIR}" \
    connectedDevelopmentDebugAndroidTest \
    "-Pandroid.testInstrumentationRunnerArguments.package=${TEST_PACKAGE}" \
    "-Pandroid.testInstrumentationRunnerArguments.fluxUserCaInstalled=${expectation}"
}

# The Android user trust store is written by the user through Settings. Instrumentation cannot
# drive that dialog, so this script performs the equivalent one-time test preparation through adb
# on a development device. It is a test fixture, never a product code path: nothing in src/main
# installs, reads or bypasses a trust anchor.
adb_root_available || {
  echo "This device does not allow adb root, so the TEST ONLY CA cannot be installed into the" >&2
  echo "Android user trust store automatically. Install ${TEST_CA} through" >&2
  echo "Settings > Security > Encryption & credentials > Install a certificate > CA certificate," >&2
  echo "then rerun this script." >&2
  exit 1
}

remove_test_ca
if device_has_test_ca; then
  echo "Could not clear ${CA_TARGET} from the device user trust store." >&2
  exit 1
fi
run_phase false

install_test_ca
if ! device_has_test_ca; then
  echo "Could not install the TEST ONLY CA at ${CA_TARGET}." >&2
  exit 1
fi
run_phase true

echo
echo "E1-C transport proof completed on ${SERIAL} (API ${API_LEVEL})."
echo "The TEST ONLY CA remains installed at ${CA_TARGET}; rerunning this script resets it."
