#!/usr/bin/env bash
# Install a signed macOS Sandbox app. Production Developer ID is the default.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
SOURCE_APP="${SOURCE_APP:-}"
RELEASE_DIR="${REPOSITORY_DIR}/dist/macos/developer-id"
INSTALL_MODE="${INSTALL_MODE:-developer-id}"
case "$INSTALL_MODE" in developer-id|development) ;; *) echo "Invalid INSTALL_MODE: $INSTALL_MODE" >&2; exit 2;; esac
INSTALLED_APP="/Applications/FluxNews.app"
BUNDLE_IDENTIFIER="dev.kevincfechtel.fluxNews"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flux-install-local.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
if [[ -z "$SOURCE_APP" ]]; then
  shopt -s nullglob
  archives=("$RELEASE_DIR"/FluxNews-*-macos-*.zip)
  shopt -u nullglob
  (( ${#archives[@]} > 0 )) || { echo "No Developer ID release ZIP found in $RELEASE_DIR" >&2; exit 1; }
  latest_archive="${archives[0]}"
  for candidate in "${archives[@]:1}"; do
    [[ "$candidate" -nt "$latest_archive" ]] && latest_archive="$candidate"
  done
  echo "Installing Developer ID release: $latest_archive"
  ditto -x -k "$latest_archive" "$TEMP_DIR"
  SOURCE_APP="$TEMP_DIR/FluxNews.app"
fi
[[ -d "$SOURCE_APP" && ! -L "$SOURCE_APP" ]] || { echo "Signed app missing: $SOURCE_APP" >&2; exit 1; }
"$SCRIPT_DIR/verify-sandbox.sh" "$SOURCE_APP" "$INSTALL_MODE"
if [[ -e "$INSTALLED_APP" || -L "$INSTALLED_APP" ]]; then
  [[ -d "$INSTALLED_APP" && ! -L "$INSTALLED_APP" ]] || { echo "Refusing unexpected installation path" >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INSTALLED_APP/Contents/Info.plist")" == "$BUNDLE_IDENTIFIER" ]] || { echo "Refusing unrelated app" >&2; exit 1; }
fi
stage="$(mktemp -d /Applications/.FluxNews-stage.XXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
staged="$stage/FluxNews.app"
ditto "$SOURCE_APP" "$staged"
"$SCRIPT_DIR/verify-sandbox.sh" "$staged" "$INSTALL_MODE"
osascript -e "tell application id \"$BUNDLE_IDENTIFIER\" to quit" >/dev/null 2>&1 || true
for _ in {1..10}; do pgrep -x FluxNews >/dev/null 2>&1 || break; sleep 1; done
if pgrep -x FluxNews >/dev/null 2>&1; then echo "FluxNews is still running" >&2; exit 1; fi
if [[ -e "$INSTALLED_APP" ]]; then rm -rf -- "$INSTALLED_APP"; fi
mv -- "$staged" "$INSTALLED_APP"
"$SCRIPT_DIR/verify-sandbox.sh" "$INSTALLED_APP" "$INSTALL_MODE"
open -n "$INSTALLED_APP"
echo "Installed signed sandbox app: $INSTALLED_APP"
echo "Persistent app data and Keychain were not deleted."
