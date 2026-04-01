import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:provider/provider.dart';

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
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
                      MediaQuery.of(context).platformBrightness == Brightness.light
                          ? Image.asset(
                              'assets/Flux_News_Starticon_Transparent.png',
                              width: 180,
                              height: 180,
                            )
                          : Image.asset(
                              'assets/Flux_News_Starticon_Invert_Transparent.png',
                              width: 180,
                              height: 180,
                            ),
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
                          final appState = context.read<FluxNewsState>();
                          appState.welcomeScreenShown = true;
                          appState.storage.write(
                              key: FluxNewsState.secureStorageWelcomeScreenShownKey,
                              value: FluxNewsState.secureStorageTrueString);
                          Navigator.pushNamed(context, FluxNewsState.loginRouteString);
                        },
                      )
                    : ElevatedButton(
                        onPressed: () {
                          final appState = context.read<FluxNewsState>();
                          appState.welcomeScreenShown = true;
                          appState.storage.write(
                              key: FluxNewsState.secureStorageWelcomeScreenShownKey,
                              value: FluxNewsState.secureStorageTrueString);
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
        ),
      ),
    );
  }
}
