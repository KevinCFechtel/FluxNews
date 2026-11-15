#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
GENERATED_DIR="${REPOSITORY_DIR}/apple/macos/FluxNews/Generated"
PACKAGE_DIR="${REPOSITORY_DIR}/apple/Build/Products/FluxUniFFI"
XCFRAMEWORK="${PACKAGE_DIR}/FluxUniFFI.xcframework"
MACOS_LIBRARY="${PACKAGE_DIR}/MacOS/libflux_uniffi.dylib"

if [[ "${FLUX_UNIFFI_PREPARED:-0}" != "1" ]]; then
  "${REPOSITORY_DIR}/apple/Build/build-uniffi.sh"
fi

for required in \
  "${MACOS_LIBRARY}" \
  "${PACKAGE_DIR}/Sources/flux_uniffi.swift" \
  "${PACKAGE_DIR}/Headers/flux_uniffiFFI.h" \
  "${PACKAGE_DIR}/Headers/module.modulemap"; do
  [[ -f "${required}" ]] || { echo "Missing packaged UniFFI artifact: ${required}" >&2; exit 1; }
done

rm -rf -- "${GENERATED_DIR}"
mkdir -p "${GENERATED_DIR}"
cp "${PACKAGE_DIR}/Sources/flux_uniffi.swift" "${GENERATED_DIR}/flux_uniffi.swift"
cp "${PACKAGE_DIR}/Headers/flux_uniffiFFI.h" "${GENERATED_DIR}/flux_uniffiFFI.h"
cp "${PACKAGE_DIR}/Headers/module.modulemap" "${GENERATED_DIR}/module.modulemap"

if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
  embedded_library="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/libflux_uniffi.dylib"

  mkdir -p "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
  cp "${MACOS_LIBRARY}" "${embedded_library}"

  if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    codesign \
      --force \
      --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      --timestamp=none \
      "${embedded_library}"
  fi
fi
