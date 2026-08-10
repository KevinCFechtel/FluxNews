import 'dart:ui';

const double compactWindowHeightBreakpoint = 480;
const double mediumWindowWidthBreakpoint = 600;
const double iosPermanentSidebarWidthBreakpoint = 800;
const double minimumSidebarWidth = 260;
const double maximumSidebarWidth = 360;

bool useTwoPaneLayout(Size size) {
  return size.width >= mediumWindowWidthBreakpoint &&
      size.height >= compactWindowHeightBreakpoint;
}

bool useIOSPermanentSidebar({
  required bool isTablet,
  required double availableWidth,
}) {
  return isTablet && availableWidth >= iosPermanentSidebarWidthBreakpoint;
}

/// A tablet list needs a standalone top spacer only when no collapsing large
/// title owns that space. This keeps Android tablet chrome offset while iPad
/// can build and animate its actual large title.
bool useStandaloneTabletListHeaderInset({
  required bool isTablet,
  required double topContentInset,
  required bool hasLargeTitleController,
}) {
  return isTablet && topContentInset > 0 && !hasLargeTitleController;
}

/// Keeps the final news item scrollable past an overlaid bottom toolbar.
///
/// With `Scaffold.extendBody`, Flutter exposes the occupied bottom chrome as
/// bottom media padding. Lists without bottom floating chrome must not consume
/// that padding a second time.
double floatingNewsListBottomInset({
  required bool hasFloatingBottomToolbar,
  required double mediaBottomPadding,
}) {
  if (!hasFloatingBottomToolbar) return 0;
  return mediaBottomPadding.clamp(0.0, double.infinity).toDouble();
}

double adaptiveSidebarWidth(double availableWidth) {
  return (availableWidth * 0.28).clamp(
    minimumSidebarWidth,
    maximumSidebarWidth,
  );
}

Rect? verticalSeparatingDisplayFeature(
  Size windowSize,
  Iterable<Rect> avoidBounds,
) {
  for (final bounds in avoidBounds) {
    final spansHeight = bounds.top <= 0 && bounds.bottom >= windowSize.height;
    final liesInsideWindow = bounds.left > 0 && bounds.right < windowSize.width;
    if (spansHeight && liesInsideWindow) return bounds;
  }
  return null;
}

Rect? horizontalSeparatingDisplayFeature(
  Size windowSize,
  Iterable<Rect> avoidBounds,
) {
  for (final bounds in avoidBounds) {
    final spansWidth = bounds.left <= 0 && bounds.right >= windowSize.width;
    final liesInsideWindow =
        bounds.top > 0 && bounds.bottom < windowSize.height;
    if (spansWidth && liesInsideWindow) return bounds;
  }
  return null;
}
