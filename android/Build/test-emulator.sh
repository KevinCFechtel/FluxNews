#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
GRADLEW="${ANDROID_DIR}/gradlew"
LOCAL_TEST_SCRIPT="${SCRIPT_DIR}/test.sh"
APP_ID="de.circle_dev.flux_news.native.dev"
MAIN_ACTIVITY="de.circledev.fluxnews.nativeapp.MainActivity"
ARGUMENT_AVD="${1:-}"
BOOT_TIMEOUT_SECONDS="240"

usage() {
  cat <<'EOF'
Usage: test-emulator.sh [avd-name]

Builds and validates the development app, installs it on one Android emulator,
launches MainActivity, and verifies that the app process stays alive.

If an emulator is already running, it is reused and avd-name must be omitted.
If no emulator is running:
  - one configured AVD is selected automatically;
  - with multiple configured AVDs, pass the desired AVD name explicitly.

The emulator is intentionally left running for manual UI testing. Existing app
data is preserved so account configuration survives repeated test runs.
EOF
}

[[ $# -le 1 ]] || {
  usage >&2
  exit 2
}
case "${ARGUMENT_AVD}" in
  --help|-h)
    usage
    exit 0
    ;;
esac

[[ -x "${GRADLEW}" ]] || {
  echo "Gradle Wrapper is missing or not executable: ${GRADLEW}" >&2
  exit 1
}
[[ -f "${LOCAL_TEST_SCRIPT}" ]] || {
  echo "Android test gate is missing: ${LOCAL_TEST_SCRIPT}" >&2
  exit 1
}
command -v adb >/dev/null 2>&1 || {
  echo "Required command missing: adb" >&2
  exit 1
}

find_emulator_binary() {
  if command -v emulator >/dev/null 2>&1; then
    command -v emulator
    return 0
  fi

  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "${sdk_root}" && "$(uname -s)" == "Darwin" ]]; then
    sdk_root="${HOME}/Library/Android/sdk"
  fi

  if [[ -n "${sdk_root}" && -x "${sdk_root}/emulator/emulator" ]]; then
    printf '%s\n' "${sdk_root}/emulator/emulator"
    return 0
  fi

  return 1
}

emulator_serials() {
  adb devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 != "" { print $1 }'
}

wait_for_boot() {
  local serial="$1"
  local deadline=$((SECONDS + BOOT_TIMEOUT_SECONDS))

  echo "Waiting for ${serial} to finish booting..."
  while (( SECONDS < deadline )); do
    local state boot_completed boot_animation
    state="$(adb -s "${serial}" get-state 2>/dev/null || true)"
    if [[ "${state}" == "device" ]]; then
      boot_completed="$(adb -s "${serial}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      boot_animation="$(adb -s "${serial}" shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r' || true)"
      if [[ "${boot_completed}" == "1" && "${boot_animation}" == "stopped" ]]; then
        adb -s "${serial}" shell input keyevent 82 >/dev/null 2>&1 || true
        return 0
      fi
    fi
    sleep 2
  done

  echo "Timed out after ${BOOT_TIMEOUT_SECONDS}s waiting for emulator ${serial}." >&2
  return 1
}

# macOS still ships Bash 3.2, so deliberately avoid mapfile/readarray and namerefs (local -n).
running_emulators=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && running_emulators+=("${line}")
done < <(emulator_serials)

SERIAL=""
case "${#running_emulators[@]}" in
  0)
    EMULATOR_BIN="$(find_emulator_binary || true)"
    [[ -n "${EMULATOR_BIN}" ]] || {
      echo "Android Emulator was not found. Install it with Android Studio's SDK Manager or add it to PATH." >&2
      exit 1
    }

    configured_avds=()
    while IFS= read -r line; do
      [[ -n "${line}" ]] && configured_avds+=("${line}")
    done < <("${EMULATOR_BIN}" -list-avds)

    [[ "${#configured_avds[@]}" -gt 0 ]] || {
      echo "No Android Virtual Device is configured. Create an AVD in Android Studio Device Manager first." >&2
      exit 1
    }

    if [[ -n "${ARGUMENT_AVD}" ]]; then
      AVD="${ARGUMENT_AVD}"
      found=0
      for candidate in "${configured_avds[@]}"; do
        [[ "${candidate}" == "${AVD}" ]] && found=1
      done
      [[ "${found}" == "1" ]] || {
        echo "Unknown AVD: ${AVD}" >&2
        echo "Configured AVDs:" >&2
        printf '  %s\n' "${configured_avds[@]}" >&2
        exit 2
      }
    elif [[ "${#configured_avds[@]}" -eq 1 ]]; then
      AVD="${configured_avds[0]}"
    else
      echo "Multiple AVDs are configured. Choose one explicitly:" >&2
      printf '  %s\n' "${configured_avds[@]}" >&2
      echo "Example: ./android/Build/test-emulator.sh ${configured_avds[0]}" >&2
      exit 2
    fi

    echo "Starting Android emulator: ${AVD}"
    EMULATOR_LOG="${TMPDIR:-/tmp}/fluxnews-emulator-${AVD//[^A-Za-z0-9._-]/_}.log"
    "${EMULATOR_BIN}" -avd "${AVD}" >"${EMULATOR_LOG}" 2>&1 &
    EMULATOR_PID=$!
    echo "Emulator PID: ${EMULATOR_PID}"
    echo "Emulator log: ${EMULATOR_LOG}"

    deadline=$((SECONDS + BOOT_TIMEOUT_SECONDS))
    while (( SECONDS < deadline )); do
      detected_emulators=()
      while IFS= read -r line; do
        [[ -n "${line}" ]] && detected_emulators+=("${line}")
      done < <(emulator_serials)

      if [[ "${#detected_emulators[@]}" -eq 1 ]]; then
        SERIAL="${detected_emulators[0]}"
        break
      fi
      if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
        echo "Android Emulator exited before becoming available. See ${EMULATOR_LOG}." >&2
        exit 1
      fi
      sleep 2
    done
    [[ -n "${SERIAL}" ]] || {
      echo "Timed out waiting for the Android Emulator to register with adb." >&2
      exit 1
    }
    ;;
  1)
    [[ -z "${ARGUMENT_AVD}" ]] || {
      echo "An emulator is already running (${running_emulators[0]}). Omit the AVD argument or stop it first." >&2
      exit 2
    }
    SERIAL="${running_emulators[0]}"
    echo "Reusing running Android emulator: ${SERIAL}"
    ;;
  *)
    echo "Multiple Android emulators are running. Keep exactly one emulator active:" >&2
    printf '  %s\n' "${running_emulators[@]}" >&2
    exit 2
    ;;
esac

wait_for_boot "${SERIAL}"

API_LEVEL="$(adb -s "${SERIAL}" shell getprop ro.build.version.sdk | tr -d '\r')"
DEVICE_NAME="$(adb -s "${SERIAL}" shell getprop ro.product.model | tr -d '\r')"
ABI_LIST="$(adb -s "${SERIAL}" shell getprop ro.product.cpu.abilist | tr -d '\r')"

echo
echo "Emulator serial: ${SERIAL}"
echo "Device: ${DEVICE_NAME}"
echo "Android API: ${API_LEVEL}"
echo "ABIs: ${ABI_LIST}"

echo
echo "=== Local Android gate ==="
bash "${LOCAL_TEST_SCRIPT}"

echo
echo "=== Install developmentDebug on emulator ==="
ANDROID_SERIAL="${SERIAL}" "${GRADLEW}" --project-dir "${ANDROID_DIR}" installDevelopmentDebug

echo
echo "=== Launch FluxNews ==="
adb -s "${SERIAL}" logcat -c
adb -s "${SERIAL}" shell am force-stop "${APP_ID}"
LAUNCH_OUTPUT="$(adb -s "${SERIAL}" shell am start -W -n "${APP_ID}/${MAIN_ACTIVITY}")"
printf '%s\n' "${LAUNCH_OUTPUT}"

if ! grep -q '^Status: ok' <<<"${LAUNCH_OUTPUT}"; then
  echo "FluxNews MainActivity did not report a successful launch." >&2
  adb -s "${SERIAL}" logcat -d -t 200 >&2 || true
  exit 1
fi

sleep 2
APP_PID="$(adb -s "${SERIAL}" shell pidof "${APP_ID}" 2>/dev/null | tr -d '\r' || true)"
if [[ -z "${APP_PID}" ]]; then
  echo "FluxNews exited immediately after launch. Recent emulator log follows:" >&2
  adb -s "${SERIAL}" logcat -d -t 200 >&2 || true
  exit 1
fi

echo
echo "FluxNews emulator smoke test passed (PID ${APP_PID})."
echo "The emulator and app remain open for manual UI testing. App data was preserved."
echo "Specialized E1 runtime/transport and production migration proofs remain separate scripts."
