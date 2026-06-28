#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_ROOT="${SCRIPT_DIR:h}"
readonly FLUTTER="$PROJECT_ROOT/vendor/flutter/bin/flutter"
readonly DEVICE_ID="${FLUXNEWS_IOS_SIMULATOR_ID:-C3BC45FD-B303-4602-89CD-319DB0793B74}"

if ! xcrun simctl list devices available | grep -q "$DEVICE_ID"; then
  echo "iOS simulator $DEVICE_ID is not available."
  exit 1
fi

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE_ID" -b

if [[ "${1:-}" == "--run" ]]; then
  exec "$FLUTTER" run -d "$DEVICE_ID"
fi
