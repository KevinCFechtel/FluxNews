import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  Widget _buildLogo(BuildContext context) {
    final bool isLightMode = MediaQuery.of(context).platformBrightness == Brightness.light;

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
                ? CupertinoButton.filled(
                    child: Text(AppLocalizations.of(context)!.login),
                    onPressed: () {
                      Navigator.pushNamed(context, FluxNewsState.loginRouteString);
                    },
                  )
                : ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, FluxNewsState.loginRouteString);
                    },
                    child: Text(AppLocalizations.of(context)!.login),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Platform.isIOS
                ? CupertinoButton(
                    child: Text(AppLocalizations.of(context)!.restoreSettings),
                    onPressed: () {
                      Navigator.pushNamed(context, FluxNewsState.restoreSettingsRouteString);
                    },
                  )
                : OutlinedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, FluxNewsState.restoreSettingsRouteString);
                    },
                    child: Text(AppLocalizations.of(context)!.restoreSettings),
                  ),
          ),
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
                        style: theme.textTheme.headlineMedium?.copyWith(fontSize: 36),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.provideMinifluxCredentials,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Card(
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
                        Platform.isIOS
                            ? CupertinoButton.filled(
                                child: Text(AppLocalizations.of(context)!.login),
                                onPressed: () {
                                  Navigator.pushNamed(context, FluxNewsState.loginRouteString);
                                },
                              )
                            : ElevatedButton(
                                onPressed: () {
                                  Navigator.pushNamed(context, FluxNewsState.loginRouteString);
                                },
                                child: Text(AppLocalizations.of(context)!.login),
                              ),
                        const SizedBox(height: 12),
                        Platform.isIOS
                            ? CupertinoButton(
                                child: Text(AppLocalizations.of(context)!.restoreSettings),
                                onPressed: () {
                                  Navigator.pushNamed(context, FluxNewsState.restoreSettingsRouteString);
                                },
                              )
                            : OutlinedButton(
                                onPressed: () {
                                  Navigator.pushNamed(context, FluxNewsState.restoreSettingsRouteString);
                                },
                                child: Text(AppLocalizations.of(context)!.restoreSettings),
                              ),
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
    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return Scaffold(
      body: SafeArea(
        child: isTablet ? _buildTabletLayout(context) : _buildPhoneLayout(context),
      ),
    );
  }
}
