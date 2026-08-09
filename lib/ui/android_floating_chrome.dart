import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';

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

class AndroidFloatingFeedHeader extends StatelessWidget {
  const AndroidFloatingFeedHeader({
    super.key,
    required this.title,
    required this.newsCount,
    required this.showCount,
    this.useAccentColor = true,
  });

  final String title;
  final int newsCount;
  final bool showCount;
  final bool useAccentColor;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final accentColor =
        useAccentColor ? Theme.of(context).colorScheme.primary : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment:
          showCount ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: AndroidFloatingSurface(
            accentColor: accentColor,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        if (showCount)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Semantics(
              label: '${strings.itemCount}: $newsCount',
              child: AndroidFloatingSurface(
                accentColor: accentColor,
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                child: Text(
                  '$newsCount',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
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
        : theme.brightness == Brightness.dark
            ? 0.88
            : 0.78;
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
