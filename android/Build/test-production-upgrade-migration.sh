#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd -- "${ANDROID_DIR}/.." && pwd)"
GRADLEW="${ANDROID_DIR}/gradlew"
PACKAGE="de.circle_dev.flux_news"
ACTIVITY="de.circledev.fluxnews.nativeapp.MigrationProbeActivity"
SERIAL="${1:-${ANDROID_SERIAL:-}}"

usage() { echo "Usage: test-production-upgrade-migration.sh <physical-device-serial>"; }
[[ $# -le 1 && -n "${SERIAL}" ]] || { usage >&2; exit 2; }
if [[ $# -eq 1 && -n "${ANDROID_SERIAL:-}" && "$1" != "${ANDROID_SERIAL}" ]]; then
  echo "The device serial argument and ANDROID_SERIAL disagree." >&2
  exit 2
fi
[[ -f "${ANDROID_DIR}/migration-signing.properties" ]] || { echo "Missing gitignored android/migration-signing.properties." >&2; exit 1; }
[[ -x "${GRADLEW}" ]] || { echo "Gradle Wrapper is missing or not executable." >&2; exit 1; }
command -v adb >/dev/null || { echo "Required command missing: adb" >&2; exit 1; }
command -v apksigner >/dev/null || { echo "Required command missing: apksigner" >&2; exit 1; }
[[ "$(adb -s "${SERIAL}" get-state)" == "device" ]] || { echo "Android device is not usable: ${SERIAL}" >&2; exit 1; }
IS_EMULATOR="$(adb -s "${SERIAL}" shell getprop ro.kernel.qemu | tr -d '\r')"

if [[ "${IS_EMULATOR}" == "1" && "${FLUX_ALLOW_MIGRATION_EMULATOR:-0}" != "1" ]]; then
  echo "E1-F production acceptance requires a physical device." >&2
  echo "For a non-final emulator proof, rerun with FLUX_ALLOW_MIGRATION_EMULATOR=1." >&2
  exit 1
fi

if [[ "${IS_EMULATOR}" == "1" ]]; then
  echo "WARNING: Running E1-F on an emulator. This validates migration mechanics but is not final physical-device acceptance."
fi
adb -s "${SERIAL}" shell pm path "${PACKAGE}" >/dev/null || { echo "${PACKAGE} is not installed." >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
INSTALLED_APK_PATH="$(adb -s "${SERIAL}" shell pm path "${PACKAGE}" | tr -d '\r' | awk -F: 'NR==1 { print $2 }')"
adb -s "${SERIAL}" pull "${INSTALLED_APK_PATH}" "${TMP_DIR}/installed.apk" >/dev/null
if ! unzip -l "${TMP_DIR}/installed.apk" | grep -F 'libflutter.so' >/dev/null; then
  echo "Installed package is not the expected Flutter legacy APK; refusing to replace it." >&2
  exit 1
fi

INSTALLED_VERSION="$(adb -s "${SERIAL}" shell dumpsys package "${PACKAGE}" | tr -d '\r' | awk -F= '/versionCode=/ { print $2; exit }' | awk '{ print $1 }')"
[[ "${INSTALLED_VERSION}" =~ ^[0-9]+$ ]] || { echo "Could not read installed versionCode." >&2; exit 1; }
PROBE_VERSION=$((INSTALLED_VERSION + 1))

"${GRADLEW}" --project-dir "${ANDROID_DIR}" assembleProductionMigrationProbe "-PfluxMigrationVersionCode=${PROBE_VERSION}"
PROBE_APK="${ANDROID_DIR}/app/build/outputs/apk/production/migrationProbe/app-production-migrationProbe.apk"
[[ -f "${PROBE_APK}" ]] || { echo "Migration probe APK was not produced." >&2; exit 1; }

installed_signer="$(apksigner verify --print-certs "${TMP_DIR}/installed.apk" | awk -F: '/Signer #1 certificate SHA-256 digest:/ { gsub(/ /, "", $2); print $2; exit }')"
probe_signer="$(apksigner verify --print-certs "${PROBE_APK}" | awk -F: '/Signer #1 certificate SHA-256 digest:/ { gsub(/ /, "", $2); print $2; exit }')"
[[ -n "${installed_signer}" && -n "${probe_signer}" ]] || { echo "Could not determine APK signers." >&2; exit 1; }
[[ "${installed_signer}" == "${probe_signer}" ]] || {
  echo "Signer mismatch; refusing installation." >&2
  echo "installed=${installed_signer}" >&2
  echo "probe=${probe_signer}" >&2
  exit 1
}

echo "Installing the signed production migration probe as an in-place update (versionCode ${PROBE_VERSION})."
adb -s "${SERIAL}" install -r "${PROBE_APK}"
adb -s "${SERIAL}" shell am start -W -n "${PACKAGE}/${ACTIVITY}" >/dev/null
REPORT="$(adb -s "${SERIAL}" shell run-as "${PACKAGE}" cat "cache/legacy-migration-probe.json" | tr -d '\r')"
[[ -n "${REPORT}" ]] || { echo "Migration probe did not produce a report." >&2; exit 1; }
printf '%s\n' "${REPORT}"
for gate in '"productionPackage":true' '"urlReadable":true' '"apiKeyReadable":true' '"readable":true' '"sourceFingerprintsUnchanged":true' '"keystoreAliasesUnchanged":true'; do
  grep -q "${gate}" <<<"${REPORT}" || { echo "E1-F probe gate failed: ${gate}" >&2; exit 1; }
done
