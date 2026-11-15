#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE="${REPOSITORY_DIR}/core/Cargo.toml"
CRATE="flux-uniffi"
OUTPUT_PACKAGE_DIR="${SCRIPT_DIR}/Products/FluxUniFFI"
MACOS_DEPLOYMENT_TARGET="15.0"
IOS_DEPLOYMENT_TARGET="17.0"

for command_name in cargo lipo install_name_tool otool plutil rustup vtool xcodebuild; do
  command -v "${command_name}" >/dev/null 2>&1 || { echo "Required command missing: ${command_name}" >&2; exit 1; }
done

targets=(
  aarch64-apple-darwin
  x86_64-apple-darwin
  aarch64-apple-ios
  aarch64-apple-ios-sim
)

for target in "${targets[@]}"; do
  rustup target list --installed | grep -qx "${target}" || {
    echo "Required Rust target is not installed: ${target}" >&2
    echo "Install it with: rustup target add ${target}" >&2
    exit 1
  }
done

for target in "${targets[@]}"; do
  case "${target}" in
    *-apple-darwin)
      MACOSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}" \
        cargo build --manifest-path "${WORKSPACE}" --package "${CRATE}" --release --locked --target "${target}"
      ;;
    *-apple-ios*)
      IPHONEOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
        cargo build --manifest-path "${WORKSPACE}" --package "${CRATE}" --release --locked --target "${target}"
      ;;
  esac
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/flux-uniffi-apple.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT

PACKAGE_DIR="${work_dir}/FluxUniFFI"
XCFRAMEWORK="${PACKAGE_DIR}/FluxUniFFI.xcframework"
SOURCES_DIR="${PACKAGE_DIR}/Sources"
MACOS_DIR="${PACKAGE_DIR}/MacOS"
PACKAGE_HEADERS_DIR="${PACKAGE_DIR}/Headers"
macos_library="${work_dir}/macos/libflux_uniffi.dylib"
ios_framework="${work_dir}/ios/FluxUniFFI.framework"
ios_simulator_framework="${work_dir}/ios-simulator/FluxUniFFI.framework"
headers_dir="${work_dir}/Headers"

mkdir -p \
  "$(dirname -- "${macos_library}")" \
  "${ios_framework}/Headers" \
  "${ios_framework}/Modules" \
  "${ios_simulator_framework}/Headers" \
  "${ios_simulator_framework}/Modules" \
  "${headers_dir}" \
  "${SOURCES_DIR}" \
  "${MACOS_DIR}" \
  "${PACKAGE_HEADERS_DIR}"

(
  cd "${REPOSITORY_DIR}/core"
  cargo run --manifest-path "${WORKSPACE}" --package "${CRATE}" --bin uniffi-bindgen --locked -- \
    generate "${REPOSITORY_DIR}/core/target/aarch64-apple-darwin/release/libflux_uniffi.dylib" \
    --crate flux_uniffi --language swift --out-dir "${headers_dir}"
)

lipo -create \
  "${REPOSITORY_DIR}/core/target/aarch64-apple-darwin/release/libflux_uniffi.dylib" \
  "${REPOSITORY_DIR}/core/target/x86_64-apple-darwin/release/libflux_uniffi.dylib" \
  -output "${macos_library}"
cp "${REPOSITORY_DIR}/core/target/aarch64-apple-ios/release/libflux_uniffi.dylib" "${ios_framework}/FluxUniFFI"
cp "${REPOSITORY_DIR}/core/target/aarch64-apple-ios-sim/release/libflux_uniffi.dylib" "${ios_simulator_framework}/FluxUniFFI"

for library in "${macos_library}"; do
  [[ -f "${library}" ]] || { echo "Missing UniFFI library: ${library}" >&2; exit 1; }
  install_name_tool -id "@rpath/libflux_uniffi.dylib" "${library}"
done
cp "${macos_library}" "${MACOS_DIR}/libflux_uniffi.dylib"
for framework_binary in "${ios_framework}/FluxUniFFI" "${ios_simulator_framework}/FluxUniFFI"; do
  [[ -f "${framework_binary}" ]] || { echo "Missing UniFFI framework binary: ${framework_binary}" >&2; exit 1; }
  install_name_tool -id "@rpath/FluxUniFFI.framework/FluxUniFFI" "${framework_binary}"
done

cp "${headers_dir}/flux_uniffi.swift" "${SOURCES_DIR}/flux_uniffi.swift"
rm "${headers_dir}/flux_uniffi.swift"
cp "${headers_dir}/flux_uniffiFFI.modulemap" "${headers_dir}/module.modulemap"
cp "${headers_dir}/flux_uniffiFFI.h" "${PACKAGE_HEADERS_DIR}/flux_uniffiFFI.h"
cp "${headers_dir}/module.modulemap" "${PACKAGE_HEADERS_DIR}/module.modulemap"

for framework in "${ios_framework}" "${ios_simulator_framework}"; do
  cp "${headers_dir}/flux_uniffiFFI.h" "${framework}/Headers/flux_uniffiFFI.h"
  cp "${headers_dir}/module.modulemap" "${framework}/Headers/module.modulemap"
  cat > "${framework}/Modules/module.modulemap" <<'EOF'
framework module flux_uniffiFFI {
  header "../Headers/flux_uniffiFFI.h"
  export *
}
EOF
done

create_framework_info_plist() {
  local framework="$1"
  local platform="$2"
  local info_plist="${framework}/Info.plist"

  plutil -create xml1 "${info_plist}"
  plutil -insert CFBundleExecutable -string FluxUniFFI "${info_plist}"
  plutil -insert CFBundleIdentifier -string dev.kevincfechtel.flux.uniffi "${info_plist}"
  plutil -insert CFBundleName -string FluxUniFFI "${info_plist}"
  plutil -insert CFBundlePackageType -string FMWK "${info_plist}"
  plutil -insert CFBundleShortVersionString -string 1.0 "${info_plist}"
  plutil -insert CFBundleSupportedPlatforms -json "[\"${platform}\"]" "${info_plist}"
  plutil -insert CFBundleVersion -string 1 "${info_plist}"
  plutil -insert MinimumOSVersion -string 17.0 "${info_plist}"
}

create_framework_info_plist "${ios_framework}" iPhoneOS
create_framework_info_plist "${ios_simulator_framework}" iPhoneSimulator

rm -rf -- "${XCFRAMEWORK}"
xcodebuild -create-xcframework \
  -framework "${ios_framework}" \
  -framework "${ios_simulator_framework}" \
  -output "${XCFRAMEWORK}"

lipo "${macos_library}" -verify_arch arm64
lipo "${macos_library}" -verify_arch x86_64
lipo "${ios_framework}/FluxUniFFI" -verify_arch arm64
lipo "${ios_simulator_framework}/FluxUniFFI" -verify_arch arm64

verify_minimum_os() {
  local library="$1"
  local architecture="$2"
  local minimum="$3"
  local build_metadata
  build_metadata="$(vtool -arch "${architecture}" -show-build "${library}")"
  grep -Eq "(^|[[:space:]])(minos|version)[[:space:]]+${minimum}([[:space:]]|$)" <<<"${build_metadata}" || {
    echo "Unexpected minimum OS in ${library} (${architecture}); expected ${minimum}:" >&2
    echo "${build_metadata}" >&2
    exit 1
  }
}

verify_minimum_os "${macos_library}" arm64 "${MACOS_DEPLOYMENT_TARGET}"
verify_minimum_os "${macos_library}" x86_64 "${MACOS_DEPLOYMENT_TARGET}"
verify_minimum_os "${ios_framework}/FluxUniFFI" arm64 "${IOS_DEPLOYMENT_TARGET}"
verify_minimum_os "${ios_simulator_framework}/FluxUniFFI" arm64 "${IOS_DEPLOYMENT_TARGET}"

[[ "$(otool -D "${macos_library}" | tail -n 1)" == "@rpath/libflux_uniffi.dylib" ]] || {
  echo "Unexpected macOS UniFFI install name" >&2
  exit 1
}
for framework_binary in "${ios_framework}/FluxUniFFI" "${ios_simulator_framework}/FluxUniFFI"; do
  [[ "$(otool -D "${framework_binary}" | tail -n 1)" == "@rpath/FluxUniFFI.framework/FluxUniFFI" ]] || {
    echo "Unexpected iOS UniFFI install name: ${framework_binary}" >&2
    exit 1
  }
done

for required in \
  "${MACOS_DIR}/libflux_uniffi.dylib" \
  "${SOURCES_DIR}/flux_uniffi.swift" \
  "${PACKAGE_HEADERS_DIR}/flux_uniffiFFI.h" \
  "${PACKAGE_HEADERS_DIR}/module.modulemap" \
  "${XCFRAMEWORK}/Info.plist"; do
  [[ -f "${required}" ]] || { echo "Missing packaged UniFFI artifact: ${required}" >&2; exit 1; }
done

rm -rf -- "${OUTPUT_PACKAGE_DIR}"
mkdir -p "$(dirname -- "${OUTPUT_PACKAGE_DIR}")"
mv "${PACKAGE_DIR}" "${OUTPUT_PACKAGE_DIR}"

echo "FluxUniFFI package: ${OUTPUT_PACKAGE_DIR}"
