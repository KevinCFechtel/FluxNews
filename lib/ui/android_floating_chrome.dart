import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';

enum AndroidFloatingChromeEdge { top, bottom }

/// Extends the scaffold surface behind floating Android chrome and fades it
/// gradually into scrolling content. This reduces rapid contrast changes below
/// translucent controls while keeping the list visibly continuous.
class AndroidFloatingChromeEdgeScrim extends StatelessWidget {
  const AndroidFloatingChromeEdgeScrim({
    super.key,
    required this.edge,
    this.chromeExtent = 0,
    this.transitionExtent = 25,
  });

  final AndroidFloatingChromeEdge edge;

  /// Chrome height that is not already represented by the system/Scaffold
  /// media padding. The top floating header uses this; extended bottom chrome
  /// is already included in `MediaQuery.padding.bottom` by `Scaffold`.
  final double chromeExtent;
  final double transitionExtent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaPadding = MediaQuery.paddingOf(context);
    final systemOrChromeInset = edge == AndroidFloatingChromeEdge.top
        ? mediaPadding.top
        : mediaPadding.bottom;
    final protectedExtent = systemOrChromeInset + chromeExtent;
    final extent = protectedExtent + transitionExtent;
    final baseColor = theme.scaffoldBackgroundColor;
    final isTop = edge == AndroidFloatingChromeEdge.top;
    const curveStops = <double>[0, 0.16, 0.34, 0.51, 0.68, 0.84, 1];
    const curveOpacities = <double>[0, 0.15, 0.25, 0.45, 0.55, 0.70, 1];
    final opacities = isTop ? curveOpacities.reversed : curveOpacities;
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
              stops: curveStops,
            ),
          ),
        ),
      ),
    );
  }
}

class AndroidStatusBarScrim extends StatelessWidget {
  const AndroidStatusBarScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final trueBlack = theme.brightness == Brightness.dark &&
        colorScheme.surface == Colors.black;
    final baseColor = trueBlack ? Colors.black : theme.scaffoldBackgroundColor;
    final topColor = baseColor.withValues(
      alpha: highContrast ? 0.98 : 0.92,
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: highContrast ? 0 : 8,
          sigmaY: highContrast ? 0 : 8,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                topColor,
                topColor.withValues(alpha: highContrast ? 0.96 : 0.86),
                topColor.withValues(alpha: 0),
              ],
              stops: const [0, 0.78, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class AndroidTabletSidebarHeader extends StatelessWidget {
  const AndroidTabletSidebarHeader({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
        child: Row(
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: FaIcon(FontAwesomeIcons.bookOpen, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AndroidFloatingFeedHeader extends StatelessWidget {
  const AndroidFloatingFeedHeader({
    super.key,
    required this.title,
    required this.newsCount,
    required this.showCount,
    required this.onOpenDrawer,
    this.useAccentColor = true,
  });

  final String title;
  final int newsCount;
  final bool showCount;
  final VoidCallback onOpenDrawer;
  final bool useAccentColor;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final accentColor =
        useAccentColor ? Theme.of(context).colorScheme.primary : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AndroidFloatingSurface(
          accentColor: accentColor,
          child: IconButton(
            icon: const FaIcon(FontAwesomeIcons.bookOpen, size: 18),
            onPressed: onOpenDrawer,
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          fit: FlexFit.loose,
          child: AndroidFloatingSurface(
            accentColor: accentColor,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (showCount) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    label: '${strings.itemCount}: $newsCount',
                    child: Text(
                      '$newsCount',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AndroidFloatingToolbar extends StatelessWidget {
  const AndroidFloatingToolbar({
    super.key,
    required this.children,
    this.leadingChildren = const <Widget>[],
    this.trailingChildren = const <Widget>[],
    this.useAccentColor = true,
  });

  final List<Widget> children;
  final List<Widget> leadingChildren;
  final List<Widget> trailingChildren;
  final bool useAccentColor;

  @override
  Widget build(BuildContext context) {
    return AndroidFloatingSurface(
      accentColor:
          useAccentColor ? Theme.of(context).colorScheme.primary : null,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...leadingChildren,
          if (children.isNotEmpty)
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ...trailingChildren,
        ],
      ),
    );
  }
}

class AndroidFloatingSurface extends StatelessWidget {
  const AndroidFloatingSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.accentColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(24));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final trueBlack = theme.brightness == Brightness.dark &&
        colorScheme.surface == Colors.black;
    final baseColor = trueBlack
        ? Colors.black
        : theme.brightness == Brightness.dark
            ? Color.alphaBlend(
                Colors.black.withValues(alpha: 0.22),
                colorScheme.surfaceContainer,
              )
            : colorScheme.surfaceContainer;
    final opacity = highContrast
        ? 0.94
        : trueBlack
            ? 0.72
            : theme.brightness == Brightness.dark
                ? 0.82
                : 0.72;
    final surfaceColor = baseColor.withValues(alpha: opacity);
    final tintedSurfaceColor = accentColor == null
        ? surfaceColor
        : Color.alphaBlend(
            accentColor!.withValues(
              alpha: highContrast
                  ? 0.30
                  : theme.brightness == Brightness.dark
                      ? 0.18
                      : 0.24,
            ),
            surfaceColor,
          );
    final borderColor = accentColor?.withValues(
          alpha: highContrast
              ? 0.90
              : theme.brightness == Brightness.dark
                  ? 0.50
                  : 0.68,
        ) ??
        colorScheme.outlineVariant.withValues(
          alpha: highContrast ? 0.75 : 0.42,
        );

    return Material(
      elevation: highContrast
          ? 1
          : theme.brightness == Brightness.dark
              ? 2
              : 3,
      shadowColor: colorScheme.shadow.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.16 : 0.22,
      ),
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: highContrast ? 0 : 12,
          sigmaY: highContrast ? 0 : 12,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tintedSurfaceColor,
            borderRadius: radius,
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
