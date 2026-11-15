#!/usr/bin/env bash
# B1 checks the app as signed on disk, not the source entitlements.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: verify-sandbox.sh /path/to/FluxNews.app development|adhoc|archive|distribution|developer-id

development: Apple Development signatures, same team and matching App Group
             provisioning for host and widget.
adhoc:       verify signatures and Sandbox entitlements only; NOT a B1 acceptance.
archive:      verify archive signatures, team and Sandbox entitlements before export.
distribution: verify Apple Distribution team and Sandbox entitlements.
developer-id: verify Developer ID Application team and Sandbox entitlements.
USAGE
}
if [[ "$#" == 1 && "$1" == "--help" ]]; then usage; exit 0; fi
if [[ "$#" != 2 ]]; then usage >&2; exit 2; fi

APP_DIR="$1"
MODE="$2"
EXPECTED_TEAM_ID="8X9VDP43J9"
HOST_ID="dev.kevincfechtel.fluxNews"
WIDGET_ID="dev.kevincfechtel.fluxNews.FluxNewsWidgets"
GROUP_ID="group.dev.kevincfechtel.fluxNews"
case "$MODE" in development|adhoc|archive|distribution|developer-id) ;; *) echo "Invalid signing mode: $MODE" >&2; exit 2 ;; esac
for cmd in codesign plutil security /usr/libexec/PlistBuddy; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing tool: $cmd" >&2; exit 1; }
done
[[ -d "$APP_DIR" ]] || { echo "App not found: $APP_DIR" >&2; exit 1; }
WIDGET="$APP_DIR/Contents/PlugIns/FluxNewsWidgets.appex"
LIBRARY="$APP_DIR/Contents/Frameworks/libflux_uniffi.dylib"
[[ -d "$WIDGET" && -f "$LIBRARY" ]] || { echo "Missing widget or Rust library" >&2; exit 1; }

HOST_INFO="$APP_DIR/Contents/Info.plist"
WIDGET_INFO="$WIDGET/Contents/Info.plist"
plutil -lint "$HOST_INFO" "$WIDGET_INFO" >/dev/null
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
equal() {
  if [[ "$1" != "$2" ]]; then
    echo "$3: expected '$2', got '$1'" >&2
    exit 1
  fi
}
equal "$(plist "$HOST_INFO" CFBundleIdentifier)" "$HOST_ID" "Host bundle ID"
equal "$(plist "$WIDGET_INFO" CFBundleIdentifier)" "$WIDGET_ID" "Widget bundle ID"
equal "$(plist "$WIDGET_INFO" NSExtension:NSExtensionPointIdentifier)" "com.apple.widgetkit-extension" "Widget point"
for key in CFBundleVersion CFBundleShortVersionString; do
  host_value="$(plist "$HOST_INFO" "$key")"
  widget_value="$(plist "$WIDGET_INFO" "$key")"
  [[ -n "$host_value" ]] || { echo "Missing version: $key" >&2; exit 1; }
  equal "$widget_value" "$host_value" "Host/widget $key"
done

for component in "$LIBRARY" "$WIDGET" "$APP_DIR"; do
  codesign --verify --strict --verbose=2 "$component"
done
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

tmp="$(mktemp -d /tmp/flux-sandbox.XXXXXX)"
trap 'rm -rf -- "$tmp"' EXIT
signed_entitlements() {
  codesign -d --entitlements :- "$1" > "$2" 2>/dev/null
  plutil -lint "$2" >/dev/null
}
signed_entitlements "$APP_DIR" "$tmp/host.plist"
signed_entitlements "$WIDGET" "$tmp/widget.plist"
for key in com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.files.user-selected.read-write; do
  equal "$(plist "$tmp/host.plist" "$key")" true "Host entitlement $key"
done
equal "$(plist "$tmp/widget.plist" com.apple.security.app-sandbox)" true "Widget Sandbox"
for file in "$tmp/host.plist" "$tmp/widget.plist"; do
  equal "$(plist "$file" com.apple.security.application-groups:0)" "$GROUP_ID" "App Group ($file)"
done

if [[ "$MODE" == developer-id ]]; then
  for component in "$APP_DIR" "$WIDGET" "$LIBRARY"; do
    details="$(codesign -dvvv "$component" 2>&1)"
    grep -F "Authority=Developer ID Application:" <<< "$details" >/dev/null || { echo "Developer ID Application authority missing: $component" >&2; exit 1; }
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "$details" | head -n 1)"
    equal "$team" "$EXPECTED_TEAM_ID" "Developer ID team ($component)"
  done
fi

if [[ "$MODE" == archive ]]; then
  for component in "$APP_DIR" "$WIDGET"; do
    details="$(codesign -dvvv "$component" 2>&1)"
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "$details" | head -n 1)"
    equal "$team" "$EXPECTED_TEAM_ID" "Archive team ($component)"
  done
fi

if [[ "$MODE" == distribution ]]; then
  for component in "$APP_DIR" "$WIDGET"; do
    details="$(codesign -dvvv "$component" 2>&1)"
    grep -F 'Authority=Apple Distribution' <<< "$details" >/dev/null || { echo "Apple Distribution authority missing: $component" >&2; exit 1; }
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "$details" | head -n 1)"
    equal "$team" "$EXPECTED_TEAM_ID" "Distribution team ($component)"
  done
fi

if [[ "$MODE" == development ]]; then
  for component in "$APP_DIR" "$WIDGET"; do
    details="$(codesign -dvvv "$component" 2>&1)"
    grep -F 'Authority=Apple Development' <<< "$details" >/dev/null || {
      echo "Apple Development authority missing: $component" >&2; exit 1
    }
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "$details" | head -n 1)"
    equal "$team" "$EXPECTED_TEAM_ID" "Signing team ($component)"
  done
  index=0
  for component in "$APP_DIR" "$WIDGET"; do
    index=$((index + 1))
    profile="$component/Contents/embedded.provisionprofile"
    [[ -f "$profile" ]] || {
      echo "Development provisioning profile missing: $component. Check the App Group and Xcode signing." >&2
      exit 1
    }
    security cms -D -i "$profile" > "$tmp/profile$index.plist"
    plutil -lint "$tmp/profile$index.plist" >/dev/null
    equal "$(plist "$tmp/profile$index.plist" TeamIdentifier:0)" "$EXPECTED_TEAM_ID" "Provisioning team"
    equal "$(plist "$tmp/profile$index.plist" Entitlements:com.apple.security.application-groups:0)" "$GROUP_ID" "Provisioned App Group"
  done
fi
echo "Signed Sandbox validation passed ($MODE): $APP_DIR"
