#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="${SCRIPT_DIR}/Products/FluxUniFFI"
XCFRAMEWORK="${PACKAGE_DIR}/FluxUniFFI.xcframework"
SOURCES="${PACKAGE_DIR}/Sources/flux_uniffi.swift"

[[ -f "${SOURCES}" ]] || { echo "Missing generated Swift bindings: ${SOURCES}" >&2; exit 1; }
[[ -f "${XCFRAMEWORK}/Info.plist" ]] || { echo "Missing XCFramework metadata: ${XCFRAMEWORK}/Info.plist" >&2; exit 1; }

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/flux-uniffi-ios-proof.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT

proof_source="${work_dir}/UniFFIiOSProof.swift"
cat > "${proof_source}" <<'EOF'
import Foundation
import flux_uniffiFFI

func verifyUniFFIiOSLink(config: InitializationConfig) throws -> Flux {
    try Flux.initialize(config: config)
}
EOF

verify_slice() {
  local sdk="$1"
  local target="$2"
  local library_identifier="$3"
  local framework_dir="${XCFRAMEWORK}/${library_identifier}/FluxUniFFI.framework"
  local library="${framework_dir}/FluxUniFFI"
  local headers="${framework_dir}/Headers"
  local output="${work_dir}/${library_identifier}.dylib"

  [[ -f "${library}" ]] || { echo "Missing iOS UniFFI framework binary: ${library}" >&2; exit 1; }
  [[ -f "${headers}/module.modulemap" ]] || { echo "Missing iOS UniFFI module map: ${headers}/module.modulemap" >&2; exit 1; }

  xcrun --sdk "${sdk}" swiftc \
    -target "${target}" \
    -sdk "$(xcrun --sdk "${sdk}" --show-sdk-path)" \
    -F "$(dirname -- "${framework_dir}")" \
    -I "${headers}" \
    "${SOURCES}" "${proof_source}" \
    -framework FluxUniFFI \
    -emit-library \
    -o "${output}"
}

verify_slice iphoneos arm64-apple-ios17.0 ios-arm64
verify_slice iphonesimulator arm64-apple-ios17.0-simulator ios-arm64-simulator

echo "iOS UniFFI Swift compile/link proof passed"
