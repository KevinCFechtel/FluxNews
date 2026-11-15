#!/usr/bin/env bash
set -euo pipefail
# Invoked on a full main checkout with fetch-depth 0.
[[ $# == 4 ]] || { echo "Usage: $0 <scope> <version> <full-sha> <validate|release>" >&2; exit 2; }
scope="$1"; version="$2"; sha="$3"; mode="$4"
[[ "$scope" =~ ^(android|ios|macos|all)$ && "$mode" =~ ^(validate|release)$ ]] || exit 2
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9][a-zA-Z0-9.-]*)?$ ]] || exit 2
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Full 40-character SHA required" >&2; exit 2; }
git cat-file -e "$sha^{commit}"
git merge-base --is-ancestor "$sha" origin/main || { echo "Candidate must be reachable from main" >&2; exit 1; }
git checkout --detach "$sha" >/dev/null
for platform in android ios macos; do
  unset BUILD_NUMBER VERSION_NAME
  source "Build/versions/$platform.properties"
  [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || exit 1
  if [[ "$platform" == android ]]; then (( 10#$BUILD_NUMBER <= 2100000000 )) || exit 1; fi
  if [[ "$scope" == all || "$scope" == "$platform" ]]; then
    [[ "$VERSION_NAME" == "$version" ]] || { echo "$platform version mismatch: $VERSION_NAME vs $version" >&2; exit 1; }
  fi
  printf '%s_code=%s\n' "$platform" "$BUILD_NUMBER"
done
if [[ "$mode" == release ]]; then
  tags=("$scope/v$version")
  if [[ "$scope" == all ]]; then
    tags=("android/v$version" "ios/v$version" "macos/v$version" "v$version")
  fi
  existing_tags=()
  for tag in "${tags[@]}"; do
    remote="$(git ls-remote --tags origin "refs/tags/$tag")" || {
      echo "Unable to verify immutable tag state for $tag" >&2
      exit 1
    }
    [[ -z "$remote" ]] || existing_tags+=("$tag")
  done
  if (( ${#existing_tags[@]} > 0 )); then
    printf 'Existing immutable tag(s): %s\n' "${existing_tags[*]}" >&2
    if [[ "$scope" == all && ${#existing_tags[@]} -lt ${#tags[@]} ]]; then
      echo "Partial combined release state detected; manual recovery is required. Existing tags will not be moved or deleted automatically." >&2
    fi
    exit 1
  fi
fi
printf 'sha=%s\n' "$sha"
