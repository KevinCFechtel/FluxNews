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
  if ! grep -q "initWithImage: artImage" "$AUDIO_SERVICE_PLUGIN"; then
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

# PATCH: audio_service — pixel-unique artwork in setMediaItem: (iOS)
#
# Reason : VW infotainment (and likely other OEM head units) reads
#          MPNowPlayingInfoCenter exactly once per track-change event, triggered
#          by setMediaItem:. It then compares the new artwork pixels with its
#          internally cached pixels from the previous track. When consecutive
#          tracks share the same image (e.g. the default artwork), the comparison
#          returns equal and VW suppresses the artwork update entirely.
#
#          The fix renders each artwork into a fresh CGContext and overlays a
#          single 1×1 pixel that alternates between near-black and near-white
#          (alpha 1/255 ≈ 0.4%) on every call. This is visually imperceptible
#          but guarantees unique pixel bytes for every setMediaItem: call, so
#          VW always detects a content change and updates its display.
#
# Upstream: No upstream fix planned (audio_service does not target OEM head units).
#
# Remove : Delete this block once audio_service handles OEM delta-detection natively.
#
if [[ -z "$AUDIO_SERVICE_PLUGIN" ]]; then
  echo "⚠️  PATCH audio_service unique-artwork: AudioServicePlugin.m not found — skipping."
else
  if grep -q "_uniqueArt" "$AUDIO_SERVICE_PLUGIN"; then
    echo "✅  PATCH audio_service unique-artwork: already applied — skipping."
  else
    _PATCH_PY=$(mktemp /tmp/fluxnews_patch_XXXXXX.py)
    cat > "$_PATCH_PY" << 'PYEOF'
import os, sys

path = os.environ["AUDIO_SERVICE_PLUGIN"]
with open(path) as f:
    content = f.read()

# Target the iOS initWithBoundsSize line produced by patch 1.
# The 20-space indent places it inside the #if TARGET_OS_IPHONE branch of setMediaItem:.
marker = (
    "                    artwork = [[MPMediaItemArtwork alloc] "
    "initWithBoundsSize:artImage.size "
    "requestHandler:^UIImage* _Nonnull(CGSize aSize) { return artImage; }];"
)
if marker not in content:
    sys.exit(1)  # patch 1 not yet applied or marker not found

replacement = (
    "                    static BOOL _artworkTick = NO; _artworkTick = !_artworkTick;\n"
    "                    UIGraphicsBeginImageContextWithOptions(artImage.size, NO, artImage.scale);\n"
    "                    [artImage drawAtPoint:CGPointZero];\n"
    "                    [[UIColor colorWithWhite:(_artworkTick ? 0.0 : 1.0) alpha:1.0/255.0] setFill];\n"
    "                    UIRectFill(CGRectMake(0, 0, 1, 1));\n"
    "                    UIImage *_uniqueArt = UIGraphicsGetImageFromCurrentImageContext() ?: artImage;\n"
    "                    UIGraphicsEndImageContext();\n"
    "                    artwork = [[MPMediaItemArtwork alloc] "
    "initWithBoundsSize:_uniqueArt.size "
    "requestHandler:^UIImage* _Nonnull(CGSize aSize) { return _uniqueArt; }];"
)
content = content.replace(marker, replacement, 1)
with open(path, "w") as f:
    f.write(content)
PYEOF
    if AUDIO_SERVICE_PLUGIN="$AUDIO_SERVICE_PLUGIN" python3 "$_PATCH_PY"; then
      echo "✅  PATCH audio_service unique-artwork: pixel-unique artwork applied to:"
      echo "    $AUDIO_SERVICE_PLUGIN"
    else
      echo "⚠️  PATCH audio_service unique-artwork: marker not found (patch 1 required first) — skipping."
    fi
    rm -f "$_PATCH_PY"
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
