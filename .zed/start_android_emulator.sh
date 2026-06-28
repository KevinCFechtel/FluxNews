#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_ROOT="${SCRIPT_DIR:h}"
readonly FLUTTER="$PROJECT_ROOT/vendor/flutter/bin/flutter"
readonly SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
readonly ADB="$SDK_ROOT/platform-tools/adb"
readonly EMULATOR="$SDK_ROOT/emulator/emulator"
readonly AVD_NAME="${FLUXNEWS_ANDROID_AVD:-Pixel_10_Pro}"
readonly DEVICE_ID="${FLUXNEWS_ANDROID_DEVICE_ID:-emulator-5554}"

if [[ ! -x "$ADB" || ! -x "$EMULATOR" ]]; then
  echo "Android SDK tools were not found below $SDK_ROOT."
  exit 1
fi

if ! "$ADB" -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
  if ! "$EMULATOR" -list-avds | grep -Fxq "$AVD_NAME"; then
    echo "Android AVD $AVD_NAME is not available."
    exit 1
  fi

  nohup "$EMULATOR" -avd "$AVD_NAME" -port 5554 \
    >"${TMPDIR:-/tmp}/fluxnews-android-emulator.log" 2>&1 &!
fi

for _ in {1..180}; do
  if [[ "$("$ADB" -s "$DEVICE_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 1
done

if [[ "$("$ADB" -s "$DEVICE_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; then
  echo "Android emulator $DEVICE_ID did not finish booting within 180 seconds."
  exit 1
fi

"$ADB" -s "$DEVICE_ID" shell input keyevent 82 >/dev/null 2>&1 || true

if [[ "${1:-}" == "--run" ]]; then
  exec "$FLUTTER" run -d "$DEVICE_ID"
fi
