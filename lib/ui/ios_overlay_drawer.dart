import 'package:material_ui/material_ui.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import 'ios_liquid_glass_style.dart';

const double _iosOverlayDrawerMaximumWidth = 360;

/// Width of the temporary iOS navigation surface. It follows the available
/// compact width but remains narrow enough to leave the current view visible.
double iosOverlayDrawerWidth(double availableWidth) => (availableWidth * 0.88)
    .clamp(0.0, _iosOverlayDrawerMaximumWidth)
    .toDouble();

/// A temporary iOS navigation sidebar backed by Flutter's Drawer route.
///
/// Keeping the Drawer underneath preserves the familiar edge swipe, scrim,
/// accessibility semantics and back-navigation behavior while the visible
/// surface uses the same Liquid Glass treatment as the permanent iPad sidebar.
class IOSOverlayDrawer extends StatelessWidget {
  const IOSOverlayDrawer({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<FluxNewsThemeState>();
    final useTrueBlack = themeState.useBlackMode &&
        Theme.of(context).brightness == Brightness.dark;
    final settings = iosLiquidGlassSidebarSettings(
      context,
      useTrueBlack: useTrueBlack,
    );

    return Drawer(
      width: iosOverlayDrawerWidth(MediaQuery.sizeOf(context).width),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 12),
          child: GlassContainer(
            useOwnLayer: true,
            quality: GlassQuality.standard,
            settings: settings,
            shape: const LiquidRoundedSuperellipse(borderRadius: 28),
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: iosLiquidGlassSidebarHeaderPadding,
                    child: Row(
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.bookOpen,
                          size: 18,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.fluxNews,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
