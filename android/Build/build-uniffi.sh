#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_DIR="$(cd -- "${ANDROID_DIR}/.." && pwd)"
CORE_DIR="${REPOSITORY_DIR}/core"
WORKSPACE="${CORE_DIR}/Cargo.toml"
CRATE="flux-uniffi"
UNIFFI_CONFIG="${CORE_DIR}/crates/flux-uniffi/uniffi.toml"
API_LEVEL=29
MODE="${1:-debug}"

usage() {
  echo "Usage: build-uniffi.sh [debug|release]"
}

case "${MODE}" in
  debug|release) ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    echo "Unsupported build mode: ${MODE}" >&2
    usage >&2
    exit 2
    ;;
esac

for command_name in cargo rustup cp mkdir rm grep; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command_name}" >&2
    exit 1
  }
done

[[ -f "${WORKSPACE}" ]] || {
  echo "Rust workspace manifest is missing: ${WORKSPACE}" >&2
  exit 1
}
[[ -f "${UNIFFI_CONFIG}" ]] || {
  echo "UniFFI configuration is missing: ${UNIFFI_CONFIG}" >&2
  exit 1
}

resolve_ndk() {
  if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    printf '%s\n' "${ANDROID_NDK_HOME}"
    return
  fi

  if [[ -n "${ANDROID_NDK_ROOT:-}" ]]; then
    printf '%s\n' "${ANDROID_NDK_ROOT}"
    return
  fi

  local sdk_root candidate selected_ndk="" selected_version=""
  local -a sdk_roots=()
  [[ -n "${ANDROID_HOME:-}" ]] && sdk_roots+=("${ANDROID_HOME}")
  [[ -n "${ANDROID_SDK_ROOT:-}" ]] && sdk_roots+=("${ANDROID_SDK_ROOT}")

  for sdk_root in "${sdk_roots[@]}"; do
    [[ -d "${sdk_root}/ndk" ]] || continue
    for candidate in "${sdk_root}/ndk/"*; do
      [[ -d "${candidate}" ]] || continue
      local candidate_version="${candidate##*/}"
      if [[ -z "${selected_ndk}" || "${candidate_version}" > "${selected_version}" ]]; then
        selected_ndk="${candidate}"
        selected_version="${candidate_version}"
      fi
    done
  done

  [[ -n "${selected_ndk}" ]] || {
    echo "Android NDK not found. Set ANDROID_NDK_HOME, ANDROID_NDK_ROOT, or ANDROID_HOME/ANDROID_SDK_ROOT." >&2
    exit 1
  }
  printf '%s\n' "${selected_ndk}"
}

NDK_DIR="$(resolve_ndk)"
NDK_DIR="${NDK_DIR%/}"
[[ -d "${NDK_DIR}/toolchains/llvm/prebuilt" ]] || {
  echo "Android NDK is incomplete or invalid: ${NDK_DIR}" >&2
  exit 1
}

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) HOST_TAGS=(darwin-arm64 darwin-x86_64) ;;
  Darwin-x86_64) HOST_TAGS=(darwin-x86_64 darwin-arm64) ;;
  Linux-x86_64) HOST_TAGS=(linux-x86_64) ;;
  Linux-aarch64) HOST_TAGS=(linux-aarch64) ;;
  *)
    echo "Unsupported host for Android NDK toolchain discovery: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

TOOLCHAIN_DIR=""
for host_tag in "${HOST_TAGS[@]}"; do
  candidate="${NDK_DIR}/toolchains/llvm/prebuilt/${host_tag}"
  if [[ -d "${candidate}" ]]; then
    TOOLCHAIN_DIR="${candidate}"
    break
  fi
done
[[ -n "${TOOLCHAIN_DIR}" ]] || {
  echo "No compatible Android NDK host toolchain found in: ${NDK_DIR}/toolchains/llvm/prebuilt" >&2
  exit 1
}

NDK_VERSION="${NDK_DIR##*/}"
echo "Using Android NDK ${NDK_VERSION} (${TOOLCHAIN_DIR##*/}) with API ${API_LEVEL}."

abis=(arm64-v8a x86_64)
if [[ "${FLUX_ANDROID_INCLUDE_ARMV7:-0}" == "1" ]]; then
  abis+=(armeabi-v7a)
fi
targets=(aarch64-linux-android x86_64-linux-android)
if [[ "${FLUX_ANDROID_INCLUDE_ARMV7:-0}" == "1" ]]; then
  targets+=(armv7-linux-androideabi)
fi
target_envs=(aarch64_linux_android x86_64_linux_android)
if [[ "${FLUX_ANDROID_INCLUDE_ARMV7:-0}" == "1" ]]; then
  target_envs+=(armv7_linux_androideabi)
fi
target_uppers=(AARCH64_LINUX_ANDROID X86_64_LINUX_ANDROID)
if [[ "${FLUX_ANDROID_INCLUDE_ARMV7:-0}" == "1" ]]; then
  target_uppers+=(ARMV7_LINUX_ANDROIDEABI)
fi
for target in "${targets[@]}"; do
  rustup target list --installed | grep -Fxq "${target}" || {
    echo "Required Rust target is not installed: ${target}" >&2
    echo "Install it with: rustup target add ${target}" >&2
    exit 1
  }
done

PROFILE="${MODE}"
OUTPUT_DIR="${SCRIPT_DIR}/Products/${MODE}"
BINDINGS_DIR="${SCRIPT_DIR}/Products/Bindings/${MODE}/kotlin"
rm -rf -- "${OUTPUT_DIR}"

verify_library() {
  local library="$1"
  local abi="$2"

  [[ -s "${library}" ]] || {
    echo "Missing or empty UniFFI library: ${library}" >&2
    exit 1
  }

  if command -v file >/dev/null 2>&1; then
    local description
    description="$(file -b "${library}")"
    local elf_class="ELF 64-bit"
  [[ "${abi}" == "armeabi-v7a" ]] && elf_class="ELF 32-bit"
  [[ "${description}" == *"${elf_class}"* && "${description}" == *"shared object"* ]] || {
      echo "Expected an ELF shared library, found: ${description}" >&2
      exit 1
    }
    case "${abi}" in
      arm64-v8a) [[ "${description}" == *"ARM aarch64"* ]] ;;
      x86_64) [[ "${description}" == *"x86-64"* ]] ;;
      armeabi-v7a) [[ "${description}" == *"ELF 32-bit"* && "${description}" == *"ARM"* ]] ;;
    esac || {
      echo "Unexpected ELF architecture for ${abi}: ${description}" >&2
      exit 1
    }
    echo "Verified ${abi}: ${description}"
  fi
}

for index in "${!targets[@]}"; do
  target="${targets[${index}]}"
  abi="${abis[${index}]}"
  target_env="${target_envs[${index}]}"
  target_upper="${target_uppers[${index}]}"
  clang_target="${target}"
  [[ "${target}" == "armv7-linux-androideabi" ]] && clang_target="armv7a-linux-androideabi"
  clang="${TOOLCHAIN_DIR}/bin/${clang_target}${API_LEVEL}-clang"
  clangxx="${TOOLCHAIN_DIR}/bin/${clang_target}${API_LEVEL}-clang++"
  llvm_ar="${TOOLCHAIN_DIR}/bin/llvm-ar"
  source_library="${CORE_DIR}/target/${target}/${PROFILE}/libflux_uniffi.so"
  output_library="${OUTPUT_DIR}/${abi}/libflux_uniffi.so"

  [[ -x "${clang}" && -x "${clangxx}" && -x "${llvm_ar}" ]] || {
    echo "Android NDK toolchain is missing a compiler or archiver for ${target} at API ${API_LEVEL}." >&2
    exit 1
  }

  echo "Building ${CRATE} for ${abi} (${target}, ${MODE})."
  cargo_args=(build --locked --manifest-path "${WORKSPACE}" --package "${CRATE}" --target "${target}")
  [[ "${MODE}" == "release" ]] && cargo_args+=(--release)
  env \
    "CARGO_TARGET_DIR=${CORE_DIR}/target" \
    "CARGO_TARGET_${target_upper}_LINKER=${clang}" \
    "CARGO_TARGET_${target_upper}_AR=${llvm_ar}" \
    "CC_${target_env}=${clang}" \
    "CXX_${target_env}=${clangxx}" \
    "AR_${target_env}=${llvm_ar}" \
    cargo "${cargo_args[@]}"

  [[ -s "${source_library}" ]] || {
    echo "Cargo completed but did not produce the expected ${MODE} library: ${source_library}" >&2
    exit 1
  }
  mkdir -p "$(dirname -- "${output_library}")"
  cp "${source_library}" "${output_library}"
  verify_library "${output_library}" "${abi}"
done

rm -rf -- "${BINDINGS_DIR}"
mkdir -p "${BINDINGS_DIR}"
(
  cd "${CORE_DIR}"
  cargo run --locked --manifest-path "${WORKSPACE}" --package "${CRATE}" --bin uniffi-bindgen -- \
    generate "${OUTPUT_DIR}/arm64-v8a/libflux_uniffi.so" \
    --crate flux_uniffi --language kotlin --out-dir "${BINDINGS_DIR}"
)

BINDING_FILE="${BINDINGS_DIR}/uniffi/flux_uniffi/flux_uniffi.kt"
[[ -s "${BINDING_FILE}" ]] || {
  echo "UniFFI Kotlin binding generation did not produce flux_uniffi.kt." >&2
  exit 1
}
if grep -R -F -- "java.lang.ref.Cleaner" "${BINDINGS_DIR}" >/dev/null; then
  echo "Generated Kotlin bindings still use java.lang.ref.Cleaner." >&2
  exit 1
fi
grep -R -F -- "com.sun.jna.internal.Cleaner" "${BINDINGS_DIR}" >/dev/null || {
  echo "Generated Kotlin bindings do not use the JNA Cleaner fallback." >&2
  exit 1
}

echo "Android UniFFI ${MODE} artifacts: ${OUTPUT_DIR}"
