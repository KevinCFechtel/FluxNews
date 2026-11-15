#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="$ROOT/Build/release.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
check_failure() {
  local expected="$1"; shift
  if "$@" >"$tmp/out" 2>&1; then
    echo "Expected failure: $*" >&2
    exit 1
  fi
  grep -F -- "$expected" "$tmp/out" >/dev/null || {
    cat "$tmp/out" >&2
    echo "Missing expected diagnostic: $expected" >&2
    exit 1
  }
}
bash -n "$RELEASE"
bash "$RELEASE" --help >"$tmp/help"
grep -F -- '--debug' "$tmp/help" >/dev/null
check_failure "Unknown platform" bash "$RELEASE" nonsense
check_failure "Version code and name must be provided together" bash "$RELEASE" android --version-code 12
check_failure "Version code must be a positive integer" bash "$RELEASE" android --version-code nope --version-name 3.0.0
check_failure "Invalid version name" bash "$RELEASE" android --version-code 12 --version-name invalid
check_failure "Missing Google Play production upload-signing properties" bash "$RELEASE" android --target play

check_failure "--debug cannot be combined" bash "$RELEASE" android --target play --debug
check_failure "--debug cannot be combined" bash "$RELEASE" macos --target developer-id --debug
check_failure "Unsupported target" bash "$RELEASE" macos --target fdroid

check_failure "--debug cannot be combined" bash "$RELEASE" macos --target appstore --debug

# Exercise each platform's committed default version without invoking Gradle/Xcode.
# The fixture contains only the release CLI, version files, and stubbed platform scripts.
fixture="$tmp/repo"
mkdir -p "$fixture/Build/versions" "$fixture/android/Build" "$fixture/apple/ios/Build" "$fixture/apple/macos/Build"
cp "$RELEASE" "$fixture/Build/release.sh"
printf 'VERSION_NAME=3.4.5\nBUILD_NUMBER=2026101802\n' > "$fixture/Build/versions/android.properties"
printf 'VERSION_NAME=3.4.6\nBUILD_NUMBER=2026101803\n' > "$fixture/Build/versions/ios.properties"
printf 'VERSION_NAME=3.4.7\nBUILD_NUMBER=2026101804\n' > "$fixture/Build/versions/macos.properties"
for stub in "$fixture/android/Build/build-app.sh" "$fixture/apple/ios/Build/build-app.sh" "$fixture/apple/macos/Build/build-app.sh"; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\n' > "$stub"
done
check_output() {
  local expected="$1"; shift
  local actual
  actual="$("$@")" || {
    echo "Command failed unexpectedly: $*" >&2
    exit 1
  }
  [[ "$actual" == "$expected" ]] || {
    printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual" >&2
    exit 1
  }
}
check_output "productionRelease 2026101802 3.4.5" bash "$fixture/Build/release.sh" android
check_output "productionRelease 2026101803 3.4.6" bash "$fixture/Build/release.sh" ios
check_output "--build-number 2026101804 --version-name 3.4.7" bash "$fixture/Build/release.sh" macos
check_output "productionRelease 2026101901 3.5.0" bash "$fixture/Build/release.sh" android --version-code 2026101901 --version-name 3.5.0
rm "$fixture/Build/versions/ios.properties"
check_failure "Missing platform version file" bash "$fixture/Build/release.sh" ios
printf 'VERSION_NAME=3.4.6\n' > "$fixture/Build/versions/ios.properties"
check_failure "Missing version code or name in platform version file" bash "$fixture/Build/release.sh" ios

echo "Release CLI argument contract: PASS"
