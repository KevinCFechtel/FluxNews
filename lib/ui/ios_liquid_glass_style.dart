import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flux_news/ui/floating_chrome_edge_gradient.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const EdgeInsetsDirectional iosLiquidGlassSidebarHeaderPadding =
    EdgeInsetsDirectional.fromSTEB(20, 24, 20, 16);
const double iosToolbarIconExtent = 24;

/// Keeps the iOS toolbar geometry stable while Sync changes between its
/// refresh and progress states.
class IOSSyncStatusIcon extends StatelessWidget {
  const IOSSyncStatusIcon({
    super.key,
    required this.syncing,
    required this.color,
  });

  final bool syncing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: iosToolbarIconExtent,
      child: Center(
        child: syncing
            ? CupertinoActivityIndicator(radius: 9, color: color)
            : Icon(Icons.refresh, size: iosToolbarIconExtent, color: color),
      ),
    );
  }
}

/// Owns the iOS news-list edge treatment behind floating controls.
///
/// Keeping this behind a Flux News facade lets the current Flutter
/// approximation be replaced by iOS-native scroll-edge APIs without changing
/// the surrounding phone and tablet layouts.
class IOSNewsScrollEdgeEffect extends StatelessWidget {
  const IOSNewsScrollEdgeEffect({
    super.key,
    required this.child,
    required this.topChromeExtent,
    required this.hasBottomControls,
  });

  final Widget child;
  final double topChromeExtent;
  final bool hasBottomControls;

  @override
  Widget build(BuildContext context) {
    return GlassScrollEdgeEffect(
      topFadeHeight: topChromeExtent + floatingChromeGradientTransitionExtent,
      bottomFadeHeight: MediaQuery.paddingOf(context).bottom +
          floatingChromeGradientTransitionExtent,
      fadeBottom: hasBottomControls,
      style: GlassScrollEdgeStyle.soft,
      fadeColor: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }
}

const _lightHighContrastGlassSettings = LiquidGlassSettings(
  glassColor: Color(0x3DFFFFFF),
  thickness: 25,
  blur: 16,
  chromaticAberration: 0.02,
  lightIntensity: 0.8,
  ambientStrength: 0.2,
  ambientRim: 0.35,
  fresnelStrength: 1.4,
  saturation: 1.0,
  backerColor: Color(0x80FFFFFF),
  whitenStrength: 0.15,
  shadowElevation: 2,
);

const _darkHighContrastGlassSettings = LiquidGlassSettings(
  glassColor: Color(0x26FFFFFF),
  thickness: 25,
  blur: 16,
  chromaticAberration: 0.02,
  lightIntensity: 0.55,
  ambientStrength: 0.12,
  saturation: 1.1,
  backerColor: Color(0x59000000),
  shadowElevation: 1.5,
);

// A clearer preset that lets more of the content and refraction show through
// instead of producing a frosted surface. It is paired with Premium quality
// where available by [iosLiquidGlassQuality].
const _lightClearGlassSettings = LiquidGlassSettings(
  glassColor: Color(0x52FFFFFF),
  thickness: 34,
  blur: 4,
  chromaticAberration: 0.04,
  lightIntensity: 1.0,
  ambientStrength: 0.12,
  ambientRim: 0.55,
  fresnelStrength: 1.65,
  refractiveIndex: 1.28,
  saturation: 1.35,
  glowIntensity: 1.0,
  backerColor: Color(0x4DFFFFFF),
  whitenStrength: 0.08,
  shadowElevation: 1.5,
);

const _darkClearGlassSettings = LiquidGlassSettings(
  glassColor: Color(0x52000000),
  thickness: 34,
  blur: 4,
  chromaticAberration: 0.04,
  lightIntensity: 0.75,
  ambientStrength: 0.08,
  ambientRim: 0.45,
  fresnelStrength: 1.55,
  refractiveIndex: 1.28,
  saturation: 1.4,
  glowIntensity: 0.95,
  backerColor: Color(0x4D000000),
  shadowElevation: 1.0,
);

// Menus cover a larger and more varied part of the article list than the
// compact controls. Their clear-mode recipe therefore retains refraction at
// the edges while using a denser neutral tint for consistently readable text.
const _lightClearMenuGlassSettings = LiquidGlassSettings(
  glassColor: Color(0xB3FFFFFF),
  thickness: 24,
  blur: 14,
  chromaticAberration: 0.015,
  lightIntensity: 0.7,
  ambientStrength: 0.18,
  ambientRim: 0.35,
  fresnelStrength: 1.25,
  refractiveIndex: 1.2,
  saturation: 1.0,
  backerColor: Color(0xA6FFFFFF),
  whitenStrength: 0.08,
  shadowElevation: 2,
);

const _darkClearMenuGlassSettings = LiquidGlassSettings(
  glassColor: Color(0xB3000000),
  thickness: 24,
  blur: 14,
  chromaticAberration: 0.015,
  lightIntensity: 0.55,
  ambientStrength: 0.12,
  ambientRim: 0.3,
  fresnelStrength: 1.2,
  refractiveIndex: 1.2,
  saturation: 1.0,
  backerColor: Color(0xA6000000),
  shadowElevation: 1.2,
);

LiquidGlassSettings iosLiquidGlassSettings(
  BuildContext context, {
  required bool useClearEffect,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  if (useClearEffect) {
    return isLight ? _lightClearGlassSettings : _darkClearGlassSettings;
  }
  return isLight
      ? _lightHighContrastGlassSettings
      : _darkHighContrastGlassSettings;
}

LiquidGlassSettings iosLiquidGlassMenuSettings(
  BuildContext context, {
  required bool useClearEffect,
}) {
  if (!useClearEffect) {
    return iosLiquidGlassSettings(context, useClearEffect: false);
  }
  return Theme.of(context).brightness == Brightness.light
      ? _lightClearMenuGlassSettings
      : _darkClearMenuGlassSettings;
}

/// A quieter recipe for form fields. Inputs remain translucent, but do not
/// visually compete with the floating navigation and primary actions.
LiquidGlassSettings iosLiquidGlassInputSettings(
  BuildContext context, {
  required bool useClearEffect,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return iosLiquidGlassSettings(
    context,
    useClearEffect: useClearEffect,
  ).copyWith(
    thickness: 12,
    chromaticAberration: 0.008,
    lightIntensity: isLight ? 0.32 : 0.28,
    ambientStrength: 0.06,
    ambientRim: 0.12,
    fresnelStrength: 0.55,
    glowIntensity: 0.25,
    shadowElevation: 0,
    backerColor: isLight ? const Color(0x24FFFFFF) : const Color(0x20000000),
    whitenStrength: isLight ? 0.03 : 0,
  );
}

/// Stable, legible glass for the large iPad navigation surface. The sidebar
/// deliberately stays frosted even when compact controls use Clear Glass;
/// its dense labels should not inherit a highly refractive recipe.
LiquidGlassSettings iosLiquidGlassSidebarSettings(
  BuildContext context, {
  bool useTrueBlack = false,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  final usesBlackSurface = useTrueBlack && !isLight;
  return iosLiquidGlassSettings(
    context,
    useClearEffect: false,
  ).copyWith(
    glassColor: usesBlackSurface ? const Color(0x18000000) : null,
    thickness: 18,
    blur: 18,
    chromaticAberration: 0.008,
    lightIntensity: isLight ? 0.5 : (usesBlackSurface ? 0.28 : 0.4),
    ambientStrength: usesBlackSurface ? 0.05 : 0.1,
    ambientRim: usesBlackSurface ? 0.16 : 0.22,
    fresnelStrength: usesBlackSurface ? 0.7 : 0.85,
    glowIntensity: usesBlackSurface ? 0.2 : 0.35,
    backerColor: isLight
        ? const Color(0x70FFFFFF)
        : (usesBlackSurface ? Colors.black : const Color(0x66000000)),
    whitenStrength: isLight ? 0.08 : 0,
    shadowElevation: usesBlackSurface ? 0.8 : 1.5,
  );
}

GlassQuality iosLiquidGlassQuality({required bool useClearEffect}) =>
    useClearEffect ? GlassQuality.premium : GlassQuality.standard;

Color iosLiquidGlassForeground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? CupertinoColors.black
        : CupertinoColors.white;
