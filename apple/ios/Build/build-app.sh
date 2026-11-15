#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
PROJECT="${REPOSITORY_DIR}/apple/ios/FluxNews.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-${REPOSITORY_DIR}/.build/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Upgrade Test}"
PERFORMANCE_DIAGNOSTICS=0
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 11 Pro Max}"
BUILD_NUMBER=""
VERSION_NAME=""

usage() {
  cat <<'EOF'
Usage: build-app.sh [developmentDebug|developmentRelease|productionRelease] [buildNumber versionName]
       build-app.sh [--configuration CONFIGURATION] [--build-number N] [--version-name V] [--performance-diagnostics] [--destination DESTINATION]

Examples:
  build-app.sh
  build-app.sh developmentDebug  # explicit debug\n  build-app.sh productionRelease 3001 3.0.0
  build-app.sh developmentRelease 3001 3.0.0
  build-app.sh --configuration "Upgrade Test" --build-number 3001 --version-name 3.0.0
  build-app.sh --configuration Release --performance-diagnostics --destination 'generic/platform=iOS'
  build-app.sh --destination 'generic/platform=iOS'
EOF
}

if [[ $# -gt 0 && "${1}" != -* ]]; then
  case "$1" in
    developmentDebug) CONFIGURATION=Debug ;;
    developmentRelease) CONFIGURATION=Release ;;
    productionRelease) CONFIGURATION="Upgrade Test" ;;
    *) echo "Unknown variant: $1" >&2; exit 2 ;;
  esac
  shift
  if [[ $# -gt 0 && "${1}" != -* ]]; then
    [[ $# -ge 2 && "${2}" != -* ]] || { echo "Pass buildNumber and versionName together." >&2; exit 2; }
    BUILD_NUMBER="$1"; VERSION_NAME="$2"; shift 2
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { echo "Missing value for --configuration." >&2; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || { echo "Missing build number." >&2; exit 2; }
      BUILD_NUMBER="$2"; shift 2 ;;
    --version-name)
      [[ $# -ge 2 ]] || { echo "Missing version name." >&2; exit 2; }
      VERSION_NAME="$2"; shift 2 ;;
    --destination)
      [[ $# -ge 2 ]] || { echo "Missing value for --destination." >&2; exit 2; }
      DESTINATION="$2"
      shift 2
      ;;
    --performance-diagnostics)
      PERFORMANCE_DIAGNOSTICS=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${CONFIGURATION}" in
  Debug|Release|"Upgrade Test") ;;
  *)
    echo "Unsupported Xcode configuration: ${CONFIGURATION}" >&2
    echo 'Use Debug, Release, or "Upgrade Test".' >&2
    exit 1
    ;;
esac

if [[ "${PERFORMANCE_DIAGNOSTICS}" -eq 1 && "${CONFIGURATION}" != Release ]]; then
  echo 'Performance diagnostics require the Release configuration.' >&2
  exit 1
fi

source "${SCRIPT_DIR}/versioning.sh"
[[ -z "${BUILD_NUMBER}" && -z "${VERSION_NAME}" || -n "${BUILD_NUMBER}" && -n "${VERSION_NAME}" ]] || { echo "Pass build number and version name together." >&2; exit 2; }
flux_ios_prepare_version_settings "${BUILD_NUMBER}" "${VERSION_NAME}"

run_xcodebuild() {
  if [[ "${PERFORMANCE_DIAGNOSTICS}" -eq 1 ]]; then
    xcodebuild \
      -project "${PROJECT}" \
      -scheme FluxNews \
      -configuration "${CONFIGURATION}" \
      -destination "${DESTINATION}" \
      -derivedDataPath "${DERIVED_DATA}" \
      SWIFT_ACTIVE_COMPILATION_CONDITIONS=FLUX_PERFORMANCE_DIAGNOSTICS \
      ${IOS_VERSION_SETTINGS[@]+"${IOS_VERSION_SETTINGS[@]}"} \
      "$@"
  else
    xcodebuild \
      -project "${PROJECT}" \
      -scheme FluxNews \
      -configuration "${CONFIGURATION}" \
      -destination "${DESTINATION}" \
      -derivedDataPath "${DERIVED_DATA}" \
      ${IOS_VERSION_SETTINGS[@]+"${IOS_VERSION_SETTINGS[@]}"} \
      "$@"
  fi
}

"${REPOSITORY_DIR}/apple/Build/build-uniffi.sh"

FLUX_UNIFFI_PREPARED=1 run_xcodebuild build

build_settings="$(run_xcodebuild -showBuildSettings -quiet)"
target_build_dir="$(awk -F ' = ' '$1 ~ /^[[:space:]]*TARGET_BUILD_DIR$/ { print $2; exit }' <<<"${build_settings}")"
[[ -n "${target_build_dir}" ]] || { echo "Could not determine the Xcode output directory." >&2; exit 1; }
app_path="${target_build_dir}/FluxNews.app"
[[ -d "${app_path}" ]] || { echo "Built app is missing: ${app_path}" >&2; exit 1; }

echo "FluxNews ${CONFIGURATION} app: ${app_path}"
