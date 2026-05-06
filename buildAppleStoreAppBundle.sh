#!/usr/bin/env bash
# Builds the iOS App Store bundle (IPA) for FluxNews.
#
# Usage:
#   ./buildAppleStoreAppBundle.sh
#
# The script applies any necessary third-party plugin patches before building
# and prints a clear summary of what was patched so patches can be removed
# once the upstream plugin is fixed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# PLUGIN PATCHES
# Remove a patch block once the upstream package ships the fix.
# ─────────────────────────────────────────────────────────────────────────────

# PATCH: audio_service — MPMediaItemArtwork deprecated API (iOS)
#
# Reason : audio_service uses the iOS 10-deprecated
#            [[MPMediaItemArtwork alloc] initWithImage:]
#          on iOS. OEM infotainment systems (e.g. VW Digital Cockpit) query
#          MPNowPlayingInfoCenter via the modern initWithBoundsSize:requestHandler:
#          API and receive no artwork when the deprecated variant is used.
#          CarPlay itself is unaffected.
#
# Upstream: PRs exist but the maintainer is not merging them.
#
# Remove : Delete this entire block once audio_service ships the fix and the
#          version in pubspec.yaml is updated past the fix.
#
AUDIO_SERVICE_PLUGIN=$(find ~/.pub-cache/hosted/pub.dev \
  -path "*/audio_service-*/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m" \
  | sort -V | tail -1)

if [[ -z "$AUDIO_SERVICE_PLUGIN" ]]; then
  echo "⚠️  PATCH audio_service: AudioServicePlugin.m not found in pub-cache — skipping."
else
  if grep -q "initWithBoundsSize" "$AUDIO_SERVICE_PLUGIN"; then
    echo "✅  PATCH audio_service: already applied — skipping."
  else
    # BSD sed (macOS) requires -i '' for in-place editing.
    sed -i '' \
      's/artwork = \[\[MPMediaItemArtwork alloc\] initWithImage: artImage\];/artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artImage.size requestHandler:^UIImage* _Nonnull(CGSize aSize) { return artImage; }];/' \
      "$AUDIO_SERVICE_PLUGIN"
    echo "✅  PATCH audio_service: MPMediaItemArtwork initWithImage → initWithBoundsSize:requestHandler: applied to:"
    echo "    $AUDIO_SERVICE_PLUGIN"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "▶  Building iOS App Store bundle…"
vendor/flutter/bin/flutter build ipa --release

echo ""
echo "✅  Build complete."
echo "    IPA: build/ios/ipa/*.ipa"
