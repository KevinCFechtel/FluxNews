import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/ui/adaptive_glass_dialog.dart';
import 'package:flux_news/ui/flux_news_body.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:flux_news/ui/search_news_list.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../state_management/flux_news_state.dart';
import '../miniflux/miniflux_backend.dart';
import '../models/news_model.dart';

class Search extends StatelessWidget {
  const Search({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsSearchStatefulWrapper(onInit: () {
      initConfig(context, appState);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return searchLayout(context, appState);
    }));
  }

  // initConfig reads the config values from the persistent storage and sets the state
  // accordingly.
  // It also initializes the database connection.
  Future<void> initConfig(BuildContext context, FluxNewsState appState) async {
    if (!await appState.readConfigValues()) return;
    if (context.mounted) {
      appState.readConfig(context);
      appState.readThemeConfigValues(context);
    }
  }

  Scaffold searchLayout(BuildContext context, FluxNewsState appState) {
    if (Platform.isIOS) {
      return _iosLiquidGlassSearchLayout(context, appState);
    }
    return _materialSearchLayout(context, appState);
  }

  Scaffold _materialSearchLayout(BuildContext context, FluxNewsState appState) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          // set the title of the search page to search text field
          title: TextField(
            controller: appState.searchController,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.searchHint,
              hintStyle: Theme.of(context).textTheme.bodyLarge,
              border:
                  UnderlineInputBorder(borderRadius: BorderRadius.circular(2)),
              suffixIcon: IconButton(
                onPressed: () {
                  _clearSearch(appState);
                },
                icon: const Icon(Icons.clear),
              ),
            ),

            // on change of the search text field, fetch the news list
            onSubmitted: (value) async {
              await _submitSearch(context, appState, value);
            },
          ),
        ),
        // show the news list
        body: const FluxNewsSearchBody(),
        bottomNavigationBar: _bottomBanners(appState));
  }

  Scaffold _iosLiquidGlassSearchLayout(
      BuildContext context, FluxNewsState appState) {
    final strings = AppLocalizations.of(context)!;
    final glassSettings = iosLiquidGlassSettings(
      context,
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassQuality = iosLiquidGlassQuality(
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassForeground = iosLiquidGlassForeground(context);
    final topContentInset = MediaQuery.paddingOf(context).top + 52;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        centerTitle: false,
        buttonSettings: glassSettings,
        leading: GlassIconButton(
          quality: glassQuality,
          useOwnLayer: true,
          settings: glassSettings,
          semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(
            CupertinoIcons.back,
            color: glassForeground,
          ),
        ),
        title: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: GlassSearchBar(
                controller: appState.searchController,
                placeholder: strings.searchHint,
                autofocus: true,
                useOwnLayer: true,
                settings: glassSettings,
                quality: glassQuality,
                searchIconColor: glassForeground.withValues(alpha: 0.65),
                clearIconColor: glassForeground.withValues(alpha: 0.65),
                textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: glassForeground,
                    ),
                placeholderStyle:
                    Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: glassForeground.withValues(alpha: 0.65),
                        ),
                onChanged: (value) {
                  if (value.isEmpty) {
                    _clearSearch(appState, clearController: false);
                  }
                },
                onSubmitted: (value) async {
                  await _submitSearch(context, appState, value);
                },
              ),
            ),
          ),
        ),
      ),
      body: FluxNewsSearchBody(topContentInset: topContentInset),
      bottomNavigationBar: _bottomBanners(appState),
    );
  }

  Widget _bottomBanners(FluxNewsState appState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PersistentDownloadBanner(appState: appState),
        PersistentAudioMiniPlayer(appState: appState),
      ],
    );
  }

  void _clearSearch(FluxNewsState appState, {bool clearController = true}) {
    if (clearController) appState.searchController.clear();
    appState.searchNewsList = Future<List<News>>.value([]);
    appState.refreshView();
  }

  Future<void> _submitSearch(
      BuildContext context, FluxNewsState appState, String value) async {
    if (value.isEmpty) {
      _clearSearch(appState, clearController: false);
      return;
    }

    final searchNewsListResult =
        fetchSearchedNews(appState, value).onError((error, stackTrace) {
      logThis(
          'fetchSearchedNews',
          'Caught an error in fetchSearchedNews function! : ${error.toString()}',
          LogLevel.ERROR);
      if (context.mounted &&
          appState.errorString !=
              AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString =
            AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
      return <News>[];
    });
    appState.searchNewsList = searchNewsListResult;
    appState.refreshView();
  }
}

class FluxNewsSearchBody extends StatelessWidget {
  const FluxNewsSearchBody({
    super.key,
    this.topContentInset = 0,
  });

  final double topContentInset;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // return the body of the search view
    // if there are too many news detected, an error message is shown
    // otherwise the normal list view is returned
    if (appState.tooManyNews) {
      return TooManyNewsWidget(topContentInset: topContentInset);
    } else {
      return SearchNewsList(topContentInset: topContentInset);
    }
  }
}

// this widget replace the normal news list widget, if too many news are detected
// it will pop up an too many news warning dialog and then show the normal news list in the background.
class TooManyNewsWidget extends StatelessWidget {
  const TooManyNewsWidget({
    super.key,
    this.topContentInset = 0,
  });

  final double topContentInset;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    Timer.run(() {
      showTooManyNewsWidget(context).then((value) {
        appState.tooManyNews = false;
        appState.refreshView();
      });
    });
    return SearchNewsList(topContentInset: topContentInset);
  }

  // this is the error dialog which is shown, if a error occurs.
  // to prevent the multi pop up (f.e. if the internet connection ist lost
  // not every function which require the connection should raise a pop up)
  // we check if the error which is shown is a new error.
  Future showTooManyNewsWidget(BuildContext context) async {
    FluxNewsState appState = context.read<FluxNewsState>();
    if (appState.tooManyNews) {
      if (Platform.isIOS) {
        await showAdaptiveGlassDialog<void>(
          context: context,
          title: AppLocalizations.of(context)!.error,
          message: AppLocalizations.of(context)!.tooManyNews,
          settings: iosLiquidGlassMenuSettings(
            context,
            useClearEffect: appState.iosClearLiquidGlass,
          ),
          quality: GlassQuality.standard,
          maxWidth: 340,
          actions: [
            GlassDialogAction(
              label: AppLocalizations.of(context)!.ok,
              isPrimary: true,
              onPressed: () => Navigator.pop(
                context,
                FluxNewsState.cancelContextString,
              ),
            ),
          ],
        );
        return;
      }
      await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog.adaptive(
              title: Text(AppLocalizations.of(context)!.error),
              content: Text(AppLocalizations.of(context)!.tooManyNews),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, FluxNewsState.cancelContextString);
                  },
                  child: Text(AppLocalizations.of(context)!.ok),
                ),
              ],
            );
          });
    }
  }
}

class FluxNewsSearchStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsSearchStatefulWrapper(
      {super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsSearchStatefulWrapper> {
  // init the state of FluxNewsBody to load the config and the data on startup
  @override
  void initState() {
    widget.onInit();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
