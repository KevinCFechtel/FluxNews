#!/usr/bin/env bash
set -euo pipefail

read -r -p "Tag version, e.g. 2.2.0: " version

if [[ -z "$version" ]]; then
  echo "No version entered."
  exit 1
fi

tag="v${version}"

git tag -a "$tag" -m "$tag"
git push origin "$tag"

echo "Created and pushed tag $tag"
