import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/functions/settings_backup_service.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  Widget _buildLogo(BuildContext context) {
    final bool isLightMode =
        MediaQuery.of(context).platformBrightness == Brightness.light;

    return isLightMode
        ? Image.asset(
            'assets/Flux_News_Starticon_Transparent.png',
            width: 180,
            height: 180,
          )
        : Image.asset(
            'assets/Flux_News_Starticon_Invert_Transparent.png',
            width: 180,
            height: 180,
          );
  }

  Widget _buildAndroidAutoBackupRestoreButton(BuildContext context) {
    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              debugPrint(
                  'SettingsBackupService: Android auto backup restore button tapped.');
              await SettingsBackupService
                  .maybePromptForAndroidAutoBackupRestore(
                context,
                context.read<FluxNewsState>(),
                ignoreHandledFingerprint: true,
                showNoBackupMessage: true,
              );
            },
            child: Text(AppLocalizations.of(context)!.checkAndroidAutoBackup),
          ),
        ),
      ],
    );
  }

  Widget _buildIOSActionButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
    required bool primary,
  }) {
    final appState = context.read<FluxNewsState>();
    final baseSettings = iosLiquidGlassSettings(
      context,
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    final foreground =
        primary ? CupertinoColors.white : iosLiquidGlassForeground(context);
    final settings = primary
        ? baseSettings.copyWith(
            glassColor: accent.withValues(alpha: 0.42),
            backerColor: accent.withValues(alpha: 0.32),
            whitenStrength: 0,
            shadowElevation: 1.2,
          )
        : baseSettings;

    return SizedBox(
      width: double.infinity,
      child: GlassButton.custom(
        label: label,
        onTap: onPressed,
        height: 52,
        useOwnLayer: true,
        quality: iosLiquidGlassQuality(
          useClearEffect: appState.iosClearLiquidGlass,
        ),
        settings: settings,
        style: primary ? GlassButtonStyle.prominent : GlassButtonStyle.filled,
        shape: const LiquidRoundedSuperellipse(borderRadius: 18),
        glowColor: primary ? accent.withValues(alpha: 0.28) : null,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  Widget _buildPhoneLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLogo(context),
                  const SizedBox(height: 24),
                  Text(
                    FluxNewsState.applicationName,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Platform.isIOS
                ? _buildIOSActionButton(
                    context,
                    label: AppLocalizations.of(context)!.login,
                    primary: true,
                    onPressed: () {
                      Navigator.pushNamed(
                          context, FluxNewsState.loginRouteString);
                    },
                  )
                : ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(
                          context, FluxNewsState.loginRouteString);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: Text(AppLocalizations.of(context)!.login,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary)),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Platform.isIOS
                ? _buildIOSActionButton(
                    context,
                    label: AppLocalizations.of(context)!.restoreSettings,
                    primary: false,
                    onPressed: () {
                      Navigator.pushNamed(
                          context, FluxNewsState.restoreSettingsRouteString);
                    },
                  )
                : OutlinedButton(
                    onPressed: () {
                      Navigator.pushNamed(
                          context, FluxNewsState.restoreSettingsRouteString);
                    },
                    child: Text(AppLocalizations.of(context)!.restoreSettings),
                  ),
          ),
          _buildAndroidAutoBackupRestoreButton(context),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLogo(context),
                      const SizedBox(height: 32),
                      Text(
                        FluxNewsState.applicationName,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontSize: 36),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!
                            .provideMinifluxCredentials,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Platform.isIOS
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildIOSActionButton(
                              context,
                              label: AppLocalizations.of(context)!.login,
                              primary: true,
                              onPressed: () {
                                Navigator.pushNamed(
                                    context, FluxNewsState.loginRouteString);
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildIOSActionButton(
                              context,
                              label:
                                  AppLocalizations.of(context)!.restoreSettings,
                              primary: false,
                              onPressed: () {
                                Navigator.pushNamed(context,
                                    FluxNewsState.restoreSettingsRouteString);
                              },
                            ),
                          ],
                        ),
                      )
                    : Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                FluxNewsState.applicationName,
                                style: theme.textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pushNamed(
                                      context, FluxNewsState.loginRouteString);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                ),
                                child: Text(AppLocalizations.of(context)!.login,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary)),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () {
                                  Navigator.pushNamed(context,
                                      FluxNewsState.restoreSettingsRouteString);
                                },
                                child: Text(AppLocalizations.of(context)!
                                    .restoreSettings),
                              ),
                              _buildAndroidAutoBackupRestoreButton(context),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return Scaffold(
      body: SafeArea(
        child: appState.isTablet
            ? _buildTabletLayout(context)
            : _buildPhoneLayout(context),
      ),
    );
  }
}
