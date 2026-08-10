import 'package:flutter/material.dart';

enum FloatingChromeEdge { top, bottom }

const double floatingChromeGradientTransitionExtent = 25;
const List<double> floatingChromeGradientStops = <double>[
  0,
  0.16,
  0.34,
  0.51,
  0.68,
  0.84,
  1,
];
const List<double> floatingChromeGradientLightOpacities = <double>[
  0,
  0.12,
  0.20,
  0.36,
  0.46,
  0.62,
  0.9,
];
const List<double> floatingChromeGradientDarkOpacities = <double>[
  0,
  0.15,
  0.25,
  0.45,
  0.55,
  0.70,
  0.9,
];

/// Fades scrolling content into the scaffold background near floating chrome.
///
/// Android floating layouts use the user-tuned curve below. The full
/// background color is reached only at the physical screen edge.
class FloatingChromeEdgeGradient extends StatelessWidget {
  const FloatingChromeEdgeGradient({
    super.key,
    required this.edge,
    this.chromeExtent = 0,
    this.transitionExtent = floatingChromeGradientTransitionExtent,
    this.includeMediaPadding = true,
  });

  final FloatingChromeEdge edge;

  /// Chrome height that is not represented by [MediaQuery.padding].
  final double chromeExtent;
  final double transitionExtent;
  final bool includeMediaPadding;

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final mediaInset = includeMediaPadding
        ? edge == FloatingChromeEdge.top
            ? mediaPadding.top
            : mediaPadding.bottom
        : 0.0;
    final extent = mediaInset + chromeExtent + transitionExtent;
    final theme = Theme.of(context);
    final baseColor = theme.scaffoldBackgroundColor;
    final themeOpacities = theme.brightness == Brightness.dark
        ? floatingChromeGradientDarkOpacities
        : floatingChromeGradientLightOpacities;
    final opacities = edge == FloatingChromeEdge.top
        ? themeOpacities.reversed
        : themeOpacities;
    final colors = opacities
        .map((opacity) => baseColor.withValues(alpha: opacity))
        .toList(growable: false);

    return IgnorePointer(
      child: SizedBox(
        height: extent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: floatingChromeGradientStops,
            ),
          ),
        ),
      ),
    );
  }
}
