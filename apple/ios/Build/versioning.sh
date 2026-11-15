#!/usr/bin/env bash
# Sourced by build-app.sh and archive.sh. No files in the source tree are edited.

flux_ios_prepare_version_settings() {
  local build_number="${1:-}"
  local version_name="${2:-}"
  IOS_VERSION_SETTINGS=()

  if [[ -n "${build_number}" ]]; then
    # Preserve the existing Flutter production build-number scheme (e.g. 2026092601).
    # App Store Connect performs the authoritative validation at upload time.
    if [[ ! "${build_number}" =~ ^[1-9][0-9]*$ ]]; then
      echo "Invalid iOS build number: ${build_number}. Use a positive decimal integer." >&2
      return 2
    fi
    IOS_VERSION_SETTINGS+=("CURRENT_PROJECT_VERSION=${build_number}")
  fi

  if [[ -n "${version_name}" ]]; then
    if [[ ! "${version_name}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      echo "Invalid Apple marketing version: ${version_name}. Use a numeric version such as 3.0.0 (no -beta suffix)." >&2
      return 2
    fi
    IOS_VERSION_SETTINGS+=("MARKETING_VERSION=${version_name}")
  fi
}
