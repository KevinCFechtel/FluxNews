import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:extended_image/extended_image.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/functions/audio_progress_store.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/background_sync_service.dart';
import 'package:flux_news/functions/settings_backup_service.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/ui/news_list.dart';
import 'package:flux_news/functions/sync_news.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../database/database_backend.dart';
import '../state_management/flux_news_state.dart';
import '../state_management/flux_news_theme_state.dart';
import '../models/news_model.dart';
import 'adaptive_glass_dialog.dart';
import 'adaptive_layout.dart';
import 'android_floating_chrome.dart';
import 'floating_chrome_edge_gradient.dart';
import 'audioplayer.dart';
import 'downloads_overview.dart';
import 'ios_liquid_glass_style.dart';
import 'ios_overlay_drawer.dart';
import 'ios_toolbar_layout.dart';

class FluxNewsBody extends StatelessWidget {
  const FluxNewsBody({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    final mediaQuery = MediaQuery.of(context);
    final avoidBounds = DisplayFeatureSubScreen.avoidBounds(mediaQuery);
    final horizontalFeature = horizontalSeparatingDisplayFeature(
      mediaQuery.size,
      avoidBounds,
    );
    appState.isTablet =
        useTwoPaneLayout(mediaQuery.size) && horizontalFeature == null;

    return FluxNewsBodyStatefulWrapper(onInit: () {
      appState.startUp = true;
      appState.syncProcess = true;
      initConfig(context, appState, false);
      appState.categoryList = queryCategoriesFromDB(appState, context);
      appState.newsList = Future<List<News>>.value([]);
    }, onResume: (inactiveDuration) async {
      logThis(
          'FluxNewsBody',
          'Foreground resume: '
              'inactiveSeconds=${inactiveDuration?.inSeconds} '
              'syncOnStart=${appState.syncOnStart} '
              'backgroundSyncEnabled=${appState.backgroundSyncIntervalMinutes > 0} '
              'syncProcess=${appState.syncProcess} '
              'startupSyncHandled=${appState.startupSyncHandledForUiSession} '
              'minifluxConfigured=${appState.minifluxURL != null && appState.minifluxAPIKey != null} '
              'errorOnMinifluxAuth=${appState.errorOnMinifluxAuth}',
          LogLevel.INFO);
      // Re-initialize config if a headless CarPlay launch left storageValues
      // empty (readAll failed while screen was locked). Now that the app is
      // in the foreground, the Keychain is accessible again.
      if (appState.minifluxURL == null && !appState.syncProcess) {
        logThis(
            'FluxNewsBody',
            'Resumed with null minifluxURL — re-running initConfig',
            LogLevel.INFO);
        await initConfig(context, appState, true);
        return;
      }

      final shouldTreatResumeAsStartup = inactiveDuration == null ||
          inactiveDuration >= const Duration(minutes: 5);
      final shouldRunStartupSync = appState.syncOnStart &&
          appState.backgroundSyncIntervalMinutes > 0 &&
          (!appState.startupSyncHandledForUiSession ||
              shouldTreatResumeAsStartup) &&
          !appState.syncProcess &&
          appState.minifluxURL != null &&
          appState.minifluxAPIKey != null &&
          !appState.errorOnMinifluxAuth;

      if (shouldRunStartupSync) {
        final skipStartupSyncForWidgetAction = await FluxNewsWidgetService
                .shouldSkipStartupSyncForPendingWidgetAction()
            .onError((error, stackTrace) => false);
        appState.startupSyncHandledForUiSession = true;
        if (!skipStartupSyncForWidgetAction && context.mounted) {
          logThis(
              'FluxNewsBody',
              'Running deferred sync on startup after foreground resume',
              LogLevel.INFO);
          await syncNews(appState, context);
        } else {
          logThis(
              'FluxNewsBody',
              'Deferred sync on startup skipped because a widget action is pending',
              LogLevel.INFO);
        }
      } else {
        logThis(
            'FluxNewsBody',
            'Deferred sync on startup not run: '
                'shouldTreatResumeAsStartup=$shouldTreatResumeAsStartup '
                'backgroundSyncEnabled=${appState.backgroundSyncIntervalMinutes > 0}',
            LogLevel.INFO);
      }

      if (!appState.syncProcess &&
          appState.backgroundSyncIntervalMinutes > 0 &&
          context.mounted) {
        try {
          final backgroundSyncFinishedAt =
              await readFluxNewsBackgroundSyncFinishedAt();
          final shouldReloadFromBackgroundSync =
              backgroundSyncFinishedAt != null &&
                  (appState.lastNewsListLoadedAt == null ||
                      backgroundSyncFinishedAt
                          .isAfter(appState.lastNewsListLoadedAt!));

          if (shouldReloadFromBackgroundSync) {
            logThis(
                'FluxNewsBody',
                'Reloading news list from DB after background sync: '
                    'backgroundSyncFinishedAt=${backgroundSyncFinishedAt.toIso8601String()} '
                    'lastNewsListLoadedAt=${appState.lastNewsListLoadedAt?.toIso8601String()}',
                LogLevel.INFO);
            appState.scrollPosition = 0;
            appState.newsList = queryNewsFromDB(appState).whenComplete(() {
              appState.jumpToItem(0);
            });
            appState.lastNewsListLoadedAt = DateTime.now();
            if (!context.mounted) return;
            updateStarredCounter(appState, context);
            await renewAllNewsCount(appState, context);
            appState.refreshView();
          } else {
            logThis(
                'FluxNewsBody',
                'News list reload after resume skipped: '
                    'backgroundSyncFinishedAt=${backgroundSyncFinishedAt?.toIso8601String()} '
                    'lastNewsListLoadedAt=${appState.lastNewsListLoadedAt?.toIso8601String()}',
                LogLevel.INFO);
          }
        } catch (e) {
          logThis(
              'FluxNewsBody',
              'Could not reload news list after foreground resume: $e',
              LogLevel.ERROR);
        }
      } else if (!appState.syncProcess) {
        logThis(
            'FluxNewsBody',
            'News list reload after resume skipped: '
                'backgroundSyncEnabled=${appState.backgroundSyncIntervalMinutes > 0}',
            LogLevel.INFO);
      }

      if (context.mounted) {
        await FluxNewsWidgetService.refreshSnapshotForForegroundOpen(
          appState,
          reason: 'resume',
          force: Platform.isIOS,
        ).onError((error, stackTrace) {
          logThis(
              'FluxNewsBody',
              'Could not refresh widget snapshot after foreground resume: $error',
              LogLevel.ERROR);
        });
      }
    }, child: OrientationBuilder(
      builder: (context, orientation) {
        appState.orientation = orientation;

        if (appState.isTablet) {
          return tabletLayout(context, appState);
        }
        if (avoidBounds.isNotEmpty) {
          return DisplayFeatureSubScreen(
            anchorPoint: Offset.zero,
            child: Builder(
              builder: (subScreenContext) =>
                  smartphoneLayout(subScreenContext, appState),
            ),
          );
        }
        return smartphoneLayout(context, appState);
      },
    ));
  }

  // helper function for the initState() to use async function on init
  Future<void> initConfig(
      BuildContext context, FluxNewsState appState, bool resume) async {
    if (appState.configInitializationInProgress) {
      logThis(
          'FluxNewsBody',
          'Config initialization skipped because it is already running',
          LogLevel.INFO);
      return;
    }
    appState.configInitializationInProgress = true;
    try {
      await _initConfigInternal(context, appState, resume);
    } finally {
      appState.configInitializationInProgress = false;
    }
  }

  Future<bool> _readConfigValuesWithRetry(FluxNewsState appState) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (await appState.readConfigValues()) {
        if (attempt > 1) {
          logThis('FluxNewsBody', 'Config read succeeded on attempt $attempt',
              LogLevel.INFO);
        }
        return true;
      }
      if (attempt < maxAttempts) {
        logThis(
            'FluxNewsBody',
            'Config read attempt $attempt failed; retrying in 1 second',
            LogLevel.WARNING);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return false;
  }

  Future<void> _initConfigInternal(
      BuildContext context, FluxNewsState appState, bool resume) async {
    // read persistent saved config
    final completed = await _readConfigValuesWithRetry(appState);
    if (!completed) {
      appState.configReadFailed = true;
      appState.syncProcess = false;
      appState.startUp = true;
      if (context.mounted) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
      FlutterNativeSplash.remove();
      logThis(
          'FluxNewsBody',
          'Config initialization aborted after failed storage reads; '
              'welcome navigation and follow-up startup actions are suppressed',
          LogLevel.ERROR);
      return;
    }

    if (appState.configReadFailed) {
      appState.configReadFailed = false;
      appState.errorString = '';
      appState.newError = false;
    }

    // One-time migration: rewrite all Keychain items with first_unlock
    // accessibility so they are accessible during headless CarPlay launches.
    // Awaited so migration completes before readConfig() processes storageValues.
    // No isNotEmpty guard — the migration must also run when storageValues was
    // populated by the WhenUnlocked fallback read in readConfigValues().
    await appState.migrateKeychainAccessibility();

    // init the sqlite database in startup
    appState.db = await appState.initializeDB();
    await syncCurrentFeedSettingsOverridesFromDB(appState);
    var skipSavedScrollRestore = false;

    if (completed) {
      if (context.mounted) {
        // set the app bar text to "All News"
        appState.appBarText = AppLocalizations.of(context)!.allNews;
        // read the saved config
        appState.readConfig(context);
        appState.readThemeConfigValues(context);
      }
      logThis(
          'FluxNewsBody',
          'Re-registering background sync after app config load',
          LogLevel.INFO);
      unawaited(
          configureFluxNewsBackgroundSync(appState, reason: 'app_config_load'));
      unawaited(
          SettingsBackupService.refreshAndroidAutoBackupIfPossible(appState));
      unawaited(FluxNewsWidgetService.refreshSnapshotForForegroundOpen(
        appState,
        reason: 'app_start',
        force: Platform.isIOS,
      ));
      unawaited(runPendingForegroundAudioDownloads(appState));

      // set the startup categorie if configured
      if (appState.startupCategorie != 0) {
        if (appState.startupCategorie == 1) {
          // bookmarks selected as startup categorie
          appState.feedIDs = [-1];
          appState.selectedCategoryElementType =
              FluxNewsState.bookmarkedNewsElementType;
          if (context.mounted) {
            appState.appBarText = AppLocalizations.of(context)!.bookmarked;
          }
          appState.selectedID = -1;
        } else {
          Categories? actualCategoryList;
          if (context.mounted) {
            actualCategoryList = await queryCategoriesFromDB(appState, context);
          }
          if (actualCategoryList != null) {
            if (appState.startupCategorie == 2) {
              if (appState.startupCategorieSelectionKey != null) {
                for (Category category in actualCategoryList.categories) {
                  if (category.categoryID ==
                      appState.startupCategorieSelectionKey) {
                    // add the according feeds of this category as a filter
                    appState.feedIDs = category.getFeedIDs();
                    appState.selectedCategoryElementType =
                        FluxNewsState.categoryElementType;
                    // reload the news list with the new filter
                    appState.newsList =
                        queryNewsFromDB(appState).whenComplete(() {
                      appState.jumpToItem(0);
                    });
                    // set the category title as app bar title
                    // and update the news count in the app bar, if the function is activated.
                    appState.appBarText = category.title;
                    appState.selectedID = category.categoryID;
                    if (context.mounted) {
                      actualCategoryList.renewNewsCount(appState, context);
                    }
                  }
                }
              }
            } else if (appState.startupCategorie == 3) {
              if (appState.startupFeedSelectionKey != null) {
                for (Category category in actualCategoryList.categories) {
                  for (Feed feed in category.feeds) {
                    if (feed.feedID == appState.startupFeedSelectionKey) {
                      appState.feedIDs = [feed.feedID];
                      appState.selectedCategoryElementType =
                          FluxNewsState.feedElementType;
                      // reload the news list with the new filter
                      appState.newsList =
                          queryNewsFromDB(appState).whenComplete(() {
                        appState.jumpToItem(0);
                      });
                      // set the feed title as app bar title
                      // and update the news count in the app bar, if the function is activated.
                      appState.appBarText = feed.title;
                      appState.selectedID = feed.feedID;
                      if (context.mounted) {
                        actualCategoryList.renewNewsCount(appState, context);
                      }
                    }
                  }
                }
              }
              appState.categorieStartup = false;
            }
          }
        }
      }

      appState.startUp = false;

      final skipStartupSyncForWidgetAction = await FluxNewsWidgetService
              .shouldSkipStartupSyncForPendingWidgetAction()
          .onError((error, stackTrace) => false);
      skipSavedScrollRestore = skipStartupSyncForWidgetAction;

      if ((appState.syncOnStart && !skipStartupSyncForWidgetAction) ||
          appState.syncNow) {
        appState.startupSyncHandledForUiSession = true;
        // sync on startup or now
        if (context.mounted) {
          await syncNews(appState, context);
        }
      } else {
        if (appState.syncOnStart && skipStartupSyncForWidgetAction) {
          appState.startupSyncHandledForUiSession = true;
        }
        // normal startup, read existing news from database and generate list view
        try {
          appState.newsList = queryNewsFromDB(appState);
          appState.lastNewsListLoadedAt = DateTime.now();
          if (context.mounted) {
            updateStarredCounter(appState, context);
            await renewAllNewsCount(appState, context);
          }
          appState.syncProcess = false;
          await FluxNewsWidgetService.refreshSnapshotForForegroundOpen(
            appState,
            reason: 'startup',
          ).onError((error, stackTrace) {
            logThis(
                'initConfig',
                'Could not refresh widget snapshot after startup: $error',
                LogLevel.ERROR);
          });
        } catch (e) {
          logThis('initConfig', 'Caught an error in initConfig function!',
              LogLevel.ERROR);

          if (context.mounted) {
            if (appState.errorString !=
                AppLocalizations.of(context)!.databaseError) {
              appState.errorString =
                  AppLocalizations.of(context)!.databaseError;
              appState.newError = true;
              appState.refreshView();
            }
          }
          appState.syncProcess = false;
        }
        FlutterNativeSplash.remove();
      }
      if (appState.networkImageCacheMigrated == false) {
        // migrate the network image cache to the new location
        appState.cleanLegacyCache();
      }
      // clear the network image cache of images that are older than the specified duration to prevent the cache from growing indefinitely
      await clearDiskCachedImages(
          duration: Duration(days: appState.imageCacheDurationDays));
      if (context.mounted) {
        await FluxNewsWidgetService.handlePendingWidgetAction(
            context, appState);
      }
    } else {
      appState.syncProcess = false;
      appState.startUp = false;
      appState.refreshView();
      FlutterNativeSplash.remove();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hasNewsConfiguration = appState.minifluxURL != null &&
          appState.minifluxAPIKey != null &&
          !appState.errorOnMinifluxAuth;
      // set the scroll position to the persistent saved scroll position on normal startup
      // if sync on startup is enabled, the scroll position is set to the top of the list
      if (!skipSavedScrollRestore &&
          Platform.isIOS &&
          appState.isTablet &&
          hasNewsConfiguration) {
        // A list-index jump, including index 0, aligns the first card with the
        // top edge and therefore collapses the Liquid Glass large title. iPad
        // starts at the scroll view's true minimum extent instead so the title
        // is fully expanded in both orientations.
        appState.resetListToStart(revealIOSLargeTitle: true);
      } else if (!skipSavedScrollRestore &&
          !appState.syncOnStart &&
          !appState.markAsReadOnScrollOver) {
        appState.jumpToItem(appState.savedScrollPosition);
      }

      if (appState.minifluxURL == null ||
          appState.minifluxAPIKey == null ||
          appState.errorOnMinifluxAuth) {
        // show the welcome screen once before the login screen on first app start
        if (!resume) {
          Navigator.pushNamed(context, FluxNewsState.welcomeRouteString);
        }
      } else {
        appState.startUp = false;
        // if everything is fine with the settings, present the list view
        appState.refreshView();
      }
    });
  }

  Widget smartphoneLayout(BuildContext context, FluxNewsState appState) {
    if (Platform.isIOS) {
      return _IOSLiquidGlassHome(
        drawer: getDrawer(context, appState),
      );
    }
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
    final useFloatingChrome =
        appState.appBarType == FluxNewsState.appBarFloatingType;
    bool useSliverAppBar = appState.useSliverAppBar || useFloatingChrome;
    if (appState.minifluxURL == null ||
        appState.minifluxAPIKey == null ||
        appState.errorOnMinifluxAuth == true) {
      if (appState.startUp) {
        useSliverAppBar = true;
      } else {
        useSliverAppBar = false;
      }
    } else if (appState.errorString.trim().isNotEmpty && appState.newError) {
      useSliverAppBar = false;
    } else if (appState.longSync) {
      useSliverAppBar = false;
    } else if (appState.tooManyNews) {
      useSliverAppBar = false;
    }
    final useScrolloverStatusBarProtection =
        appState.scrolloverAppBar && useSliverAppBar && !useFloatingChrome;
    // start the main view in portrait mode
    final topContentInset = MediaQuery.paddingOf(context).top +
        MediaQuery.textScalerOf(context).scale(20) +
        48;
    final scaffold = Scaffold(
      extendBody: true,
      floatingActionButton: appState.floatingButtonVisible && !useFloatingChrome
          ? GestureDetector(
              onLongPress: () async {
                if (appState.floatingButtonAction ==
                    FluxNewsState.floatingButtonMarkAsReadAction) {
                  // mark news as read
                  await markNewsAsReadInDB(appState);
                  unawaited(
                      FluxNewsWidgetService.updateWidgetSnapshot(appState));
                  if (!context.mounted) return;
                  if (appState.selectedCategoryElementType ==
                      FluxNewsState.categoryElementType) {
                    await queryNextCategoryFromDB(appState, context)
                        .then((value) {
                      if (context.mounted) {
                        setNextCategory(value, appState, context);
                      }
                    });
                  } else if (appState.selectedCategoryElementType ==
                      FluxNewsState.feedElementType) {
                    await queryNextFeedFromDB(appState, context).then((value) {
                      if (context.mounted) {
                        setNextFeed(value, appState, context);
                      }
                    });
                  } else {
                    // refresh news list with the all news state
                    appState.newsList =
                        queryNewsFromDB(appState).whenComplete(() {
                      appState.jumpToItem(0);
                    });

                    // notify the categories to update the news count
                    appCounterState.listUpdated = true;
                    appCounterState.refreshView();
                    appState.refreshView();
                  }
                }
              },
              child: FloatingActionButton(
                  heroTag: appState.glassActionButton
                      ? "glassActionButton"
                      : "normalActionButton",
                  elevation: 4,
                  backgroundColor:
                      appState.glassActionButton ? Colors.transparent : null,
                  onPressed: () async {
                    if (appState.floatingButtonAction ==
                        FluxNewsState.floatingButtonSyncAction) {
                      if (appState.syncProcess) {
                        appState.longSyncAborted = true;
                        appState.refreshView();
                      } else {
                        await syncNews(appState, context);
                      }
                    } else if (appState.floatingButtonAction ==
                        FluxNewsState.floatingButtonMarkAsReadAction) {
                      showDeleteAllDialog(context, appState, appCounterState);
                    }
                  },
                  child: appState.glassActionButton
                      ? ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(10)),
                                border: Border.all(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor),
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor
                                    .withAlpha(85),
                              ),
                              child: appState.floatingButtonAction ==
                                      FluxNewsState.floatingButtonSyncAction
                                  ? appState.syncProcess
                                      ? SizedBox(
                                          height: 60.0,
                                          width: 60.0,
                                          child: CircularProgressIndicator
                                              .adaptive(
                                                  padding: Platform.isAndroid
                                                      ? EdgeInsetsGeometry.all(
                                                          20)
                                                      : null),
                                        )
                                      : SizedBox(
                                          height: 60.0,
                                          width: 60.0,
                                          child: Icon(Icons.refresh,
                                              color: Theme.of(context)
                                                  .appBarTheme
                                                  .iconTheme!
                                                  .color))
                                  : SizedBox(
                                      height: 60.0,
                                      width: 60.0,
                                      child: Icon(Icons.check_circle_outline,
                                          color: Theme.of(context)
                                              .appBarTheme
                                              .iconTheme!
                                              .color)),
                            ),
                          ))
                      : appState.floatingButtonAction ==
                              FluxNewsState.floatingButtonSyncAction
                          ? appState.syncProcess
                              ? const SizedBox(
                                  height: 15.0,
                                  width: 15.0,
                                  child: CircularProgressIndicator.adaptive(),
                                )
                              : Icon(Icons.refresh)
                          : Icon(Icons.check_circle_outline)),
            )
          : null,
      appBar: useSliverAppBar || useFloatingChrome
          ? null
          : AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 65,
              leading: Builder(
                builder: (BuildContext context) {
                  return IconButton(
                    icon: const FaIcon(
                      FontAwesomeIcons.bookOpen,
                    ),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                    tooltip:
                        MaterialLocalizations.of(context).openAppDrawerTooltip,
                  );
                },
              ),
              title: const AppBarTitle(),
              actions: appBarButtons(context),
            ),
      drawer: getDrawer(context, appState),
      body: useFloatingChrome
          ? Stack(
              children: [
                FluxNewsBodyList(topContentInset: topContentInset),
                PositionedDirectional(
                  top: 0,
                  start: 0,
                  end: 0,
                  child: const FloatingChromeEdgeGradient(
                    edge: FloatingChromeEdge.top,
                    chromeExtent: 56,
                  ),
                ),
                const PositionedDirectional(
                  bottom: 0,
                  start: 0,
                  end: 0,
                  child: FloatingChromeEdgeGradient(
                    edge: FloatingChromeEdge.bottom,
                  ),
                ),
                PositionedDirectional(
                  top: MediaQuery.paddingOf(context).top + 8,
                  start: 12,
                  end: 12,
                  child: Consumer<FluxNewsCounterState>(
                    builder: (context, counterState, child) =>
                        AndroidFloatingFeedHeader(
                      title: appState.appBarText.isEmpty
                          ? AppLocalizations.of(context)!.fluxNews
                          : appState.appBarText,
                      newsCount: counterState.appBarNewsCount,
                      showCount: appState.multilineAppBarText,
                      onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                      useAccentColor: appState.androidFloatingAccentTint,
                    ),
                  ),
                ),
              ],
            )
          : useScrolloverStatusBarProtection
              ? Stack(
                  children: [
                    const FluxNewsBodyList(),
                    PositionedDirectional(
                      top: 0,
                      start: 0,
                      end: 0,
                      height: MediaQuery.paddingOf(context).top + 6,
                      child: const IgnorePointer(
                        child: AndroidStatusBarScrim(),
                      ),
                    ),
                  ],
                )
              : const FluxNewsBodyList(),
      bottomNavigationBar: useFloatingChrome
          ? _androidFloatingBottomChrome(context, appState)
          : _BottomBanners(appState: appState),
    );
    if (!useFloatingChrome && !useScrolloverStatusBarProtection) {
      return scaffold;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: scaffold,
    );
  }

  Widget _androidFloatingBottomChrome(
    BuildContext context,
    FluxNewsState appState,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BottomBanners(
          appState: appState,
          respectBottomSafeArea: false,
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 8),
            child: Center(
              child: _androidFloatingToolbar(
                context,
                appState,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _androidFloatingToolbar(
    BuildContext context,
    FluxNewsState appState,
  ) {
    final appBarActions = appBarButtons(
      context,
      hideConfiguredFloatingActionsFromMore: true,
    );
    return AndroidFloatingToolbar(
      useAccentColor: appState.androidFloatingAccentTint,
      leadingChildren: [
        appBarActions.first,
      ],
      trailingChildren: appBarActions.skip(1).toList(growable: false),
      children: _androidFloatingShortcutButtons(context, appState),
    );
  }

  List<Widget> _androidFloatingShortcutButtons(
    BuildContext context,
    FluxNewsState appState,
  ) {
    final strings = AppLocalizations.of(context)!;
    final buttons = <Widget>[];
    for (final action in appState.androidFloatingToolbarActions) {
      if (!FluxNewsState.isToolbarActionAvailableForElementType(
        action,
        appState.selectedCategoryElementType,
      )) {
        continue;
      }
      if (action == FluxNewsState.androidFloatingActionNewsStatus) {
        buttons.add(IconButton(
          icon: Icon(
            appState.newsStatus == FluxNewsState.unreadNewsStatus
                ? Icons.checklist
                : Icons.fiber_new,
          ),
          tooltip: appState.newsStatus == FluxNewsState.unreadNewsStatus
              ? strings.showRead
              : strings.showUnread,
          onPressed: () => _toggleAndroidNewsStatus(
            appState,
            context.read<FluxNewsCounterState>(),
          ),
        ));
      } else if (action == FluxNewsState.androidFloatingActionSortOrder) {
        buttons.add(IconButton(
          icon: const Icon(Icons.sort),
          tooltip:
              appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
                  ? strings.oldestFirst
                  : strings.newestFirst,
          onPressed: () => _toggleAndroidSortOrder(
            appState,
            context.read<FluxNewsCounterState>(),
          ),
        ));
      } else if (action == FluxNewsState.androidFloatingActionMarkAsRead) {
        buttons.add(IconButton(
          icon: const Icon(Icons.check_circle_outline),
          tooltip: _androidMarkScopeLabel(context, appState),
          onPressed: () => showDeleteAllDialog(
            context,
            appState,
            context.read<FluxNewsCounterState>(),
          ),
        ));
      } else if (action ==
          FluxNewsState.floatingToolbarActionMarkAsReadAndNext) {
        buttons.add(IconButton(
          icon: const Icon(Icons.skip_next),
          tooltip: strings.markAsReadAndNext,
          onPressed: () => unawaited(
            _markAndroidAsReadAndAdvance(
              context,
              appState,
              context.read<FluxNewsCounterState>(),
            ),
          ),
        ));
      } else if (action == FluxNewsState.androidFloatingActionPodcasts) {
        buttons.add(IconButton(
          icon: const Icon(Icons.podcasts),
          tooltip: strings.audioDownloadsSettings,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const DownloadsOverview(),
            ),
          ),
        ));
      } else if (action == FluxNewsState.androidFloatingActionSearch) {
        buttons.add(IconButton(
          icon: const Icon(Icons.search),
          tooltip: strings.search,
          onPressed: () =>
              Navigator.pushNamed(context, FluxNewsState.searchRouteString),
        ));
      } else if (action == FluxNewsState.androidFloatingActionSettings) {
        buttons.add(IconButton(
          icon: const Icon(Icons.settings),
          tooltip: strings.settings,
          onPressed: () =>
              Navigator.pushNamed(context, FluxNewsState.settingsRouteString),
        ));
      }
    }
    return buttons;
  }

  List<Widget> androidFloatingToolbarButtons(BuildContext context) {
    final appState = context.read<FluxNewsState>();
    final appBarActions = appBarButtons(
      context,
      hideConfiguredFloatingActionsFromMore: true,
    );
    return <Widget>[
      appBarActions.first,
      ..._androidFloatingShortcutButtons(context, appState),
      ...appBarActions.skip(1),
    ];
  }

  String _androidMarkScopeLabel(
    BuildContext context,
    FluxNewsState appState,
  ) {
    final strings = AppLocalizations.of(context)!;
    if (appState.selectedCategoryElementType == FluxNewsState.feedElementType) {
      return strings.markFeedAsRead;
    }
    if (appState.selectedCategoryElementType ==
        FluxNewsState.categoryElementType) {
      return strings.markCategoryAsRead;
    }
    if (appState.selectedCategoryElementType ==
        FluxNewsState.bookmarkedNewsElementType) {
      return strings.markBookmarkedAsRead;
    }
    return strings.markAllAsRead;
  }

  void _toggleAndroidNewsStatus(
    FluxNewsState appState,
    FluxNewsCounterState appCounterState,
  ) {
    appState.newsStatus = appState.newsStatus == FluxNewsState.unreadNewsStatus
        ? FluxNewsState.allNewsString
        : FluxNewsState.unreadNewsStatus;
    appState.storage.write(
      key: FluxNewsState.secureStorageNewsStatusKey,
      value: appState.newsStatus,
    );
    _reloadAndroidNewsList(appState, appCounterState);
  }

  void _toggleAndroidSortOrder(
    FluxNewsState appState,
    FluxNewsCounterState appCounterState,
  ) {
    appState.sortOrder =
        appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
            ? FluxNewsState.sortOrderOldestFirstString
            : FluxNewsState.sortOrderNewestFirstString;
    appState.storage.write(
      key: FluxNewsState.secureStorageSortOrderKey,
      value: appState.sortOrder,
    );
    _reloadAndroidNewsList(appState, appCounterState);
  }

  void _reloadAndroidNewsList(
    FluxNewsState appState,
    FluxNewsCounterState appCounterState,
  ) {
    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
      appState.jumpToItem(0);
    });
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
    appState.refreshView();
  }

  Future<void> _markAndroidAsReadAndAdvance(
    BuildContext context,
    FluxNewsState appState,
    FluxNewsCounterState appCounterState,
  ) async {
    await markNewsAsReadInDB(appState);
    unawaited(FluxNewsWidgetService.updateWidgetSnapshot(appState));
    if (!context.mounted) return;

    if (appState.selectedCategoryElementType ==
        FluxNewsState.categoryElementType) {
      final next = await queryNextCategoryFromDB(appState, context);
      if (context.mounted) setNextCategory(next, appState, context);
    } else if (appState.selectedCategoryElementType ==
        FluxNewsState.feedElementType) {
      final next = await queryNextFeedFromDB(appState, context);
      if (context.mounted) setNextFeed(next, appState, context);
    } else {
      _reloadAndroidNewsList(appState, appCounterState);
    }
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
  }

  Widget tabletLayout(BuildContext context, FluxNewsState appState) {
    if (Platform.isIOS) {
      return _IOSLiquidGlassHome(
        isTablet: true,
        drawer: getDrawer(context, appState),
      );
    }
    // start the main view in landscape mode, replace the drawer with a fixed list view on the left side
    final scaffold = Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: true,
        // Keep using the persistent window inset even if edge-to-edge layout
        // or an ancestor consumed the regular padding. This keeps Android's
        // navigation bar outside both tablet panes.
        maintainBottomViewPadding: true,
        child: LayoutBuilder(
          builder: (context, constraints) => _androidTabletBody(
            context,
            appState,
            Size(constraints.maxWidth, constraints.maxHeight),
          ),
        ),
      ),
      bottomNavigationBar: _BottomBanners(appState: appState),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: scaffold,
    );
  }

  Widget _androidTabletBody(
    BuildContext context,
    FluxNewsState appState,
    Size availableSize,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final verticalFeature = verticalSeparatingDisplayFeature(
      mediaQuery.size,
      DisplayFeatureSubScreen.avoidBounds(mediaQuery),
    );
    final featureLeft = verticalFeature?.left.clamp(0.0, availableSize.width);
    final featureRight = verticalFeature?.right.clamp(0.0, availableSize.width);
    final leadingPaneWidth = featureLeft ??
        adaptiveSidebarWidth(availableSize.width).clamp(
          0.0,
          availableSize.width,
        );
    final sidebarWidth = verticalFeature == null
        ? leadingPaneWidth
        : leadingPaneWidth.clamp(0.0, maximumSidebarWidth);

    Widget sidebarPane = Align(
      alignment: AlignmentDirectional.topStart,
      child: SizedBox(
        width: sidebarWidth,
        height: availableSize.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AndroidTabletSidebarHeader(
              title: AppLocalizations.of(context)!.fluxNews,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                children: const [CategoryList()],
              ),
            ),
          ],
        ),
      ),
    );
    if (verticalFeature == null) {
      sidebarPane = SizedBox(width: sidebarWidth, child: sidebarPane);
    } else {
      sidebarPane = SizedBox(width: leadingPaneWidth, child: sidebarPane);
    }

    return Row(
      children: [
        sidebarPane,
        if (verticalFeature != null)
          SizedBox(
              width:
                  (featureRight! - featureLeft!).clamp(0.0, double.infinity)),
        Expanded(child: _androidTabletNewsPane(context, appState)),
      ],
    );
  }

  Widget _androidTabletNewsPane(
    BuildContext context,
    FluxNewsState appState,
  ) {
    return Stack(
      children: [
        const FluxNewsBodyList(topContentInset: 64),
        const PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          child: FloatingChromeEdgeGradient(
            edge: FloatingChromeEdge.top,
            chromeExtent: 56,
          ),
        ),
        PositionedDirectional(
          top: 8,
          start: 12,
          end: 12,
          child: Align(
            alignment: AlignmentDirectional.topEnd,
            child: _androidFloatingToolbar(context, appState),
          ),
        ),
      ],
    );
  }

  Widget getDrawer(BuildContext context, FluxNewsState appState) {
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
    // update the categories, feeds and news counter, if there were updates to the list view
    if (appCounterState.listUpdated) {
      appState.categoryList = queryCategoriesFromDB(appState, context);
      appCounterState.listUpdated = false;
    }
    if (Platform.isIOS) {
      return const IOSOverlayDrawer(
        child: CategoryList(
          iosSidebar: true,
          closeDrawerOnSelection: true,
        ),
      );
    }
    // return the Material drawer on Android
    return Drawer(
        child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              children: [
                Padding(
                    padding: const EdgeInsets.only(top: 75.0, bottom: 40.0),
                    child: Row(children: [
                      const Padding(
                          padding: EdgeInsets.only(left: 18.0),
                          child: FaIcon(
                            FontAwesomeIcons.bookOpen,
                          )),
                      Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            AppLocalizations.of(context)!.fluxNews,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ))
                    ])),
                const CategoryList(closeDrawerOnSelection: true),
              ],
            )));
  }

  List<Widget> appBarButtons(
    BuildContext context, {
    bool hideConfiguredFloatingActionsFromMore = false,
  }) {
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
    FluxNewsState appState = context.read<FluxNewsState>();
    final floatingToolbarActions = hideConfiguredFloatingActionsFromMore
        ? appState.androidFloatingToolbarActions.toSet()
        : const <String>{};
    final availableFloatingToolbarActions =
        FluxNewsState.androidFloatingToolbarAvailableActions.where(
      (action) => FluxNewsState.isToolbarActionAvailableForElementType(
        action,
        appState.selectedCategoryElementType,
      ),
    );
    final showMoreButton = !hideConfiguredFloatingActionsFromMore ||
        availableFloatingToolbarActions.any(
          (action) => !floatingToolbarActions.contains(action),
        );
    // define the app bar buttons to sync with miniflux,
    // search for news and switch between all and only unread news view
    // and the navigation to the settings
    return <Widget>[
      // here is the sync part
      IconButton(
        tooltip: appState.syncProcess
            ? AppLocalizations.of(context)!.cancel
            : AppLocalizations.of(context)!.syncNews,
        onPressed: () async {
          if (appState.syncProcess) {
            appState.longSyncAborted = true;
            appState.refreshView();
          } else {
            await syncNews(appState, context);
          }
        },
        icon: appState.syncProcess
            ? const SizedBox(
                height: 15.0,
                width: 15.0,
                child: CircularProgressIndicator.adaptive(),
              )
            : const Icon(
                Icons.refresh,
              ),
      ),
      // here is the popup menu where the user can search,
      // choose between all and only unread news view
      // and navigate to the settings
      if (showMoreButton)
        PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            color: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(8.0),
                bottomRight: Radius.circular(8.0),
                topLeft: Radius.circular(8.0),
                topRight: Radius.circular(8.0),
              ),
            ),
            itemBuilder: (context) {
              return [
                // the search button
                if (!floatingToolbarActions
                    .contains(FluxNewsState.androidFloatingActionSearch))
                  PopupMenuItem<int>(
                    value: 0,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(
                            Icons.search,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.search,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ],
                    ),
                  ),
                // the switch between all and only unread news view
                if (!floatingToolbarActions
                    .contains(FluxNewsState.androidFloatingActionNewsStatus))
                  PopupMenuItem<int>(
                    value: 1,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Icon(
                            appState.newsStatus ==
                                    FluxNewsState.unreadNewsStatus
                                ? Icons.checklist
                                : Icons.fiber_new,
                          ),
                        ),
                        Expanded(
                          child: appState.newsStatus ==
                                  FluxNewsState.unreadNewsStatus
                              ? Text(
                                  AppLocalizations.of(context)!.showRead,
                                  overflow: TextOverflow.visible,
                                )
                              : Text(
                                  AppLocalizations.of(context)!.showUnread,
                                  overflow: TextOverflow.visible,
                                ),
                        )
                      ],
                    ),
                  ),
                // the selection of the sort order of the news (newest first or oldest first)
                if (!floatingToolbarActions
                    .contains(FluxNewsState.androidFloatingActionSortOrder))
                  PopupMenuItem<int>(
                    value: 2,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(
                            Icons.sort,
                          ),
                        ),
                        Expanded(
                          child: appState.sortOrder ==
                                  FluxNewsState.sortOrderNewestFirstString
                              ? Text(
                                  AppLocalizations.of(context)!.oldestFirst,
                                  overflow: TextOverflow.visible,
                                )
                              : Text(
                                  AppLocalizations.of(context)!.newestFirst,
                                  overflow: TextOverflow.visible,
                                ),
                        )
                      ],
                    ),
                  ),
                if (!floatingToolbarActions
                    .contains(FluxNewsState.androidFloatingActionMarkAsRead))
                  PopupMenuItem<int>(
                    value: 3,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(
                            Icons.check_circle_outline,
                          ),
                        ),
                        Expanded(
                          child: appState.selectedCategoryElementType ==
                                  FluxNewsState.feedElementType
                              ? Text(
                                  AppLocalizations.of(context)!.markFeedAsRead,
                                  overflow: TextOverflow.visible,
                                )
                              : appState.selectedCategoryElementType ==
                                      FluxNewsState.categoryElementType
                                  ? Text(
                                      AppLocalizations.of(context)!
                                          .markCategoryAsRead,
                                      overflow: TextOverflow.visible,
                                    )
                                  : appState.selectedCategoryElementType ==
                                          FluxNewsState
                                              .bookmarkedNewsElementType
                                      ? Text(
                                          AppLocalizations.of(context)!
                                              .markBookmarkedAsRead,
                                          overflow: TextOverflow.visible,
                                        )
                                      : Text(
                                          AppLocalizations.of(context)!
                                              .markAllAsRead,
                                          overflow: TextOverflow.visible,
                                        ),
                        ),
                      ],
                    ),
                  ),
                if (FluxNewsState.isToolbarActionAvailableForElementType(
                      FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
                      appState.selectedCategoryElementType,
                    ) &&
                    !floatingToolbarActions.contains(
                        FluxNewsState.floatingToolbarActionMarkAsReadAndNext))
                  PopupMenuItem<int>(
                    value: 4,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(Icons.skip_next),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.markAsReadAndNext,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!floatingToolbarActions
                    .contains(FluxNewsState.androidFloatingActionPodcasts))
                  PopupMenuItem<int>(
                    value: 5,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(
                            Icons.podcasts,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!
                                .audioDownloadsSettings,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ],
                    ),
                  ),
                // the navigation to the settings
                if (!floatingToolbarActions
                    .contains(FluxNewsState.androidFloatingActionSettings))
                  PopupMenuItem<int>(
                    value: 6,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(
                            Icons.settings,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.settings,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ],
                    ),
                  ),
              ];
            },
            onSelected: (value) {
              if (value == 0) {
                // navigate to the search page
                Navigator.pushNamed(context, FluxNewsState.searchRouteString);
              } else if (value == 1) {
                _toggleAndroidNewsStatus(appState, appCounterState);
              } else if (value == 2) {
                _toggleAndroidSortOrder(appState, appCounterState);
              } else if (value == 3) {
                showDeleteAllDialog(context, appState, appCounterState);
              } else if (value == 4) {
                unawaited(
                  _markAndroidAsReadAndAdvance(
                    context,
                    appState,
                    appCounterState,
                  ),
                );
              } else if (value == 5) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const DownloadsOverview(),
                  ),
                );
              } else if (value == 6) {
                // navigate to the settings page
                Navigator.pushNamed(context, FluxNewsState.settingsRouteString);
              }
            }),
    ];
  }
}

class _IOSLiquidGlassHome extends StatefulWidget {
  const _IOSLiquidGlassHome({this.drawer, this.isTablet = false});

  final Widget? drawer;
  final bool isTablet;

  @override
  State<_IOSLiquidGlassHome> createState() => _IOSLiquidGlassHomeState();
}

class _IOSLiquidGlassHomeState extends State<_IOSLiquidGlassHome> {
  final GlassLargeTitleController _largeTitleController =
      GlassLargeTitleController();
  FluxNewsState? _attachedAppState;
  ScrollController? _previousScrollController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<FluxNewsState>();
    if (identical(_attachedAppState, appState)) return;
    _restoreScrollController();
    _attachedAppState = appState;
    _previousScrollController = appState.scrollController;
    appState.scrollController = _largeTitleController.scrollController;
  }

  @override
  void dispose() {
    _restoreScrollController();
    _largeTitleController.dispose();
    super.dispose();
  }

  void _restoreScrollController() {
    final appState = _attachedAppState;
    if (appState != null &&
        identical(appState.scrollController,
            _largeTitleController.scrollController) &&
        _previousScrollController != null) {
      appState.scrollController = _previousScrollController!;
    }
    _attachedAppState = null;
    _previousScrollController = null;
  }

  Future<void> _sync(FluxNewsState appState) async {
    if (appState.syncProcess) {
      appState.longSyncAborted = true;
      appState.refreshView();
      return;
    }
    await syncNews(
      appState,
      context,
      onSuccessfulListReset: _revealExpandedTitleAfterListChange,
    );
  }

  void _revealExpandedTitleAfterListChange() {
    final appState = _attachedAppState;
    if (!mounted || appState == null) return;
    appState.resetListToStart(revealIOSLargeTitle: true);
  }

  Future<void> _refreshList(FluxNewsState appState) async {
    final appCounterState = context.read<FluxNewsCounterState>();
    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
      _revealExpandedTitleAfterListChange();
    });
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
    appState.refreshView();
  }

  Future<void> _toggleReadFilter(FluxNewsState appState) async {
    appState.newsStatus = appState.newsStatus == FluxNewsState.unreadNewsStatus
        ? FluxNewsState.allNewsString
        : FluxNewsState.unreadNewsStatus;
    await appState.storage.write(
      key: FluxNewsState.secureStorageNewsStatusKey,
      value: appState.newsStatus,
    );
    await _refreshList(appState);
  }

  Future<void> _toggleSortOrder(FluxNewsState appState) async {
    appState.sortOrder =
        appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
            ? FluxNewsState.sortOrderOldestFirstString
            : FluxNewsState.sortOrderNewestFirstString;
    await appState.storage.write(
      key: FluxNewsState.secureStorageSortOrderKey,
      value: appState.sortOrder,
    );
    await _refreshList(appState);
  }

  Future<void> _markAsReadAndAdvance(FluxNewsState appState) async {
    final appCounterState = context.read<FluxNewsCounterState>();
    await markNewsAsReadInDB(appState);
    unawaited(FluxNewsWidgetService.updateWidgetSnapshot(appState));
    if (!mounted) return;

    if (appState.selectedCategoryElementType ==
        FluxNewsState.categoryElementType) {
      final next = await queryNextCategoryFromDB(appState, context);
      if (mounted) setNextCategory(next, appState, context);
    } else if (appState.selectedCategoryElementType ==
        FluxNewsState.feedElementType) {
      final next = await queryNextFeedFromDB(appState, context);
      if (mounted) setNextFeed(next, appState, context);
    } else {
      await _refreshList(appState);
    }
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
  }

  String _markScopeLabel(BuildContext context, FluxNewsState appState) {
    final strings = AppLocalizations.of(context)!;
    if (appState.selectedCategoryElementType == FluxNewsState.feedElementType) {
      return strings.markFeedAsRead;
    }
    if (appState.selectedCategoryElementType ==
        FluxNewsState.categoryElementType) {
      return strings.markCategoryAsRead;
    }
    if (appState.selectedCategoryElementType ==
        FluxNewsState.bookmarkedNewsElementType) {
      return strings.markBookmarkedAsRead;
    }
    return strings.markAllAsRead;
  }

  List<String> _availableToolbarActions(FluxNewsState appState) {
    return FluxNewsState.iosToolbarAvailableActions
        .where(
          (action) => FluxNewsState.isToolbarActionAvailableForElementType(
            action,
            appState.selectedCategoryElementType,
          ),
        )
        .toList(growable: false);
  }

  List<Widget> _menuItems(
    FluxNewsState appState, {
    Set<String> excludedActions = const <String>{},
  }) {
    final strings = AppLocalizations.of(context)!;
    final groups = <List<Widget>>[
      <Widget>[
        if (!excludedActions
            .contains(FluxNewsState.androidFloatingActionSearch))
          GlassMenuItem(
            title: strings.search,
            icon: const Icon(Icons.search),
            height: 56,
            maxLines: 2,
            onTap: () =>
                Navigator.pushNamed(context, FluxNewsState.searchRouteString),
          ),
        if (!excludedActions
            .contains(FluxNewsState.androidFloatingActionNewsStatus))
          GlassMenuItem(
            title: appState.newsStatus == FluxNewsState.unreadNewsStatus
                ? strings.showRead
                : strings.showUnread,
            icon: Icon(appState.newsStatus == FluxNewsState.unreadNewsStatus
                ? Icons.checklist
                : Icons.fiber_new),
            height: 56,
            maxLines: 2,
            onTap: () => unawaited(_toggleReadFilter(appState)),
          ),
        if (!excludedActions
            .contains(FluxNewsState.androidFloatingActionSortOrder))
          GlassMenuItem(
            title:
                appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
                    ? strings.oldestFirst
                    : strings.newestFirst,
            icon: const Icon(Icons.sort),
            height: 56,
            maxLines: 2,
            onTap: () => unawaited(_toggleSortOrder(appState)),
          ),
      ],
      <Widget>[
        if (!excludedActions
            .contains(FluxNewsState.androidFloatingActionMarkAsRead))
          GlassMenuItem(
            title: _markScopeLabel(context, appState),
            icon: const Icon(Icons.check_circle_outline),
            height: 56,
            maxLines: 2,
            onTap: () => showDeleteAllDialog(
              context,
              appState,
              context.read<FluxNewsCounterState>(),
            ),
          ),
        if (FluxNewsState.isToolbarActionAvailableForElementType(
              FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
              appState.selectedCategoryElementType,
            ) &&
            !excludedActions
                .contains(FluxNewsState.floatingToolbarActionMarkAsReadAndNext))
          GlassMenuItem(
            title: strings.markAsReadAndNext,
            icon: const Icon(Icons.skip_next),
            height: 56,
            maxLines: 2,
            onTap: () => unawaited(_markAsReadAndAdvance(appState)),
          ),
      ],
      <Widget>[
        if (!excludedActions
            .contains(FluxNewsState.androidFloatingActionPodcasts))
          GlassMenuItem(
            title: strings.audioDownloadsSettings,
            icon: const Icon(Icons.podcasts),
            height: 56,
            maxLines: 2,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => const DownloadsOverview(),
            )),
          ),
        if (!excludedActions
            .contains(FluxNewsState.androidFloatingActionSettings))
          GlassMenuItem(
            title: strings.settings,
            icon: const Icon(Icons.settings),
            height: 56,
            maxLines: 2,
            onTap: () =>
                Navigator.pushNamed(context, FluxNewsState.settingsRouteString),
          ),
      ],
    ];
    final items = <Widget>[];
    for (final group in groups.where((group) => group.isNotEmpty)) {
      if (items.isNotEmpty) items.add(const GlassMenuDivider());
      items.addAll(group);
    }
    return items;
  }

  List<Widget> _wideTabletActions(
    FluxNewsState appState, {
    required LiquidGlassSettings settings,
    required GlassQuality quality,
    required Color foreground,
    required double newsPaneWidth,
  }) {
    final strings = AppLocalizations.of(context)!;
    final menuSettings = iosLiquidGlassMenuSettings(
      context,
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final visibleActions = iosTabletVisibleToolbarActions(
      selectedActions: appState.iosToolbarActions,
      availableActions: _availableToolbarActions(appState),
      newsPaneWidth: newsPaneWidth,
    );
    final directActionSet = visibleActions.toSet();
    final menuItems = _menuItems(
      appState,
      excludedActions: directActionSet,
    );

    Widget buildButtonGroup(VoidCallback? toggleMenu) {
      return GlassButtonGroup.icons(
        useOwnLayer: true,
        quality: quality,
        settings: settings,
        itemPadding: const EdgeInsets.all(10),
        items: [
          GlassButtonGroupItem(
            label: appState.syncProcess ? strings.cancel : strings.syncNews,
            onTap: () => unawaited(_sync(appState)),
            icon: appState.syncProcess
                ? CupertinoActivityIndicator(radius: 9, color: foreground)
                : Icon(Icons.refresh, color: foreground),
          ),
          for (final action in visibleActions)
            _iosDirectAction(
              action,
              appState,
              foreground: foreground,
            ),
          if (toggleMenu != null)
            GlassButtonGroupItem(
              label: strings.moreActions,
              onTap: toggleMenu,
              icon: Icon(CupertinoIcons.ellipsis, color: foreground),
            ),
        ],
      );
    }

    final Widget toolbar = menuItems.isEmpty
        ? buildButtonGroup(null)
        : GlassMenu(
            quality: GlassQuality.standard,
            settings: menuSettings,
            items: menuItems,
            menuWidth: 320,
            autoAdjustToScreen: true,
            menuPadding: const EdgeInsets.all(12),
            triggerBuilder: (context, toggleMenu) =>
                buildButtonGroup(toggleMenu),
          );
    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: toolbar,
      ),
    ];
  }

  GlassButtonGroupItem _iosDirectAction(
    String action,
    FluxNewsState appState, {
    required Color foreground,
  }) {
    final strings = AppLocalizations.of(context)!;
    if (action == FluxNewsState.androidFloatingActionSearch) {
      return GlassButtonGroupItem(
        label: strings.search,
        onTap: () =>
            Navigator.pushNamed(context, FluxNewsState.searchRouteString),
        icon: Icon(Icons.search, color: foreground),
      );
    }
    if (action == FluxNewsState.androidFloatingActionNewsStatus) {
      return GlassButtonGroupItem(
        label: appState.newsStatus == FluxNewsState.unreadNewsStatus
            ? strings.showRead
            : strings.showUnread,
        onTap: () => unawaited(_toggleReadFilter(appState)),
        icon: Icon(
          appState.newsStatus == FluxNewsState.unreadNewsStatus
              ? Icons.checklist
              : Icons.fiber_new,
          color: foreground,
        ),
      );
    }
    if (action == FluxNewsState.androidFloatingActionSortOrder) {
      return GlassButtonGroupItem(
        label: appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
            ? strings.oldestFirst
            : strings.newestFirst,
        onTap: () => unawaited(_toggleSortOrder(appState)),
        icon: Icon(Icons.sort, color: foreground),
      );
    }
    if (action == FluxNewsState.androidFloatingActionMarkAsRead) {
      return GlassButtonGroupItem(
        label: _markScopeLabel(context, appState),
        onTap: () => showDeleteAllDialog(
          context,
          appState,
          context.read<FluxNewsCounterState>(),
        ),
        icon: Icon(Icons.check_circle_outline, color: foreground),
      );
    }
    if (action == FluxNewsState.floatingToolbarActionMarkAsReadAndNext) {
      return GlassButtonGroupItem(
        label: strings.markAsReadAndNext,
        onTap: () => unawaited(_markAsReadAndAdvance(appState)),
        icon: Icon(Icons.skip_next, color: foreground),
      );
    }
    if (action == FluxNewsState.androidFloatingActionPodcasts) {
      return GlassButtonGroupItem(
        label: strings.audioDownloadsSettings,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (context) => const DownloadsOverview(),
        )),
        icon: Icon(Icons.podcasts, color: foreground),
      );
    }
    return GlassButtonGroupItem(
      label: strings.settings,
      onTap: () =>
          Navigator.pushNamed(context, FluxNewsState.settingsRouteString),
      icon: Icon(Icons.settings, color: foreground),
    );
  }

  List<Widget> _compactTopActions(
    FluxNewsState appState, {
    required LiquidGlassSettings settings,
    required GlassQuality quality,
    required Color foreground,
  }) {
    final strings = AppLocalizations.of(context)!;
    final menuSettings = iosLiquidGlassMenuSettings(
      context,
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final visibleActions = iosPhoneVisibleToolbarActions(
      selectedActions: appState.iosToolbarActions,
      availableActions: _availableToolbarActions(appState),
    );
    final menuItems = _menuItems(
      appState,
      excludedActions: visibleActions.toSet(),
    );

    Widget buildButtonGroup(VoidCallback? toggleMenu) {
      return GlassButtonGroup.icons(
        useOwnLayer: true,
        quality: quality,
        settings: settings,
        itemPadding: const EdgeInsets.all(10),
        items: [
          GlassButtonGroupItem(
            label: appState.syncProcess ? strings.cancel : strings.syncNews,
            onTap: () => unawaited(_sync(appState)),
            icon: appState.syncProcess
                ? CupertinoActivityIndicator(radius: 9, color: foreground)
                : Icon(Icons.refresh, color: foreground),
          ),
          for (final action in visibleActions)
            _iosDirectAction(
              action,
              appState,
              foreground: foreground,
            ),
          if (toggleMenu != null)
            GlassButtonGroupItem(
              label: strings.moreActions,
              onTap: toggleMenu,
              icon: Icon(CupertinoIcons.ellipsis, color: foreground),
            ),
        ],
      );
    }

    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: menuItems.isEmpty
            ? buildButtonGroup(null)
            : GlassMenu(
                quality: GlassQuality.standard,
                settings: menuSettings,
                items: menuItems,
                menuWidth: (MediaQuery.sizeOf(context).width - 32)
                    .clamp(280.0, 340.0)
                    .toDouble(),
                autoAdjustToScreen: true,
                menuPadding: const EdgeInsets.all(12),
                triggerBuilder: (context, toggleMenu) =>
                    buildButtonGroup(toggleMenu),
              ),
      ),
    ];
  }

  Widget _wideTabletSidebar({required double width}) {
    final themeState = context.watch<FluxNewsThemeState>();
    final useTrueBlack = themeState.useBlackMode &&
        Theme.of(context).brightness == Brightness.dark;
    final settings = iosLiquidGlassSidebarSettings(
      context,
      useTrueBlack: useTrueBlack,
    );
    return SizedBox(
      width: width,
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 12),
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
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: 12),
                      child: CategoryList(iosSidebar: true),
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

  Widget _bottomChrome(
    FluxNewsState appState, {
    required bool usesWideSidebar,
    required double sidebarWidth,
  }) {
    if (usesWideSidebar) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(width: sidebarWidth),
          Expanded(child: _BottomBanners(appState: appState)),
        ],
      );
    }

    if (widget.isTablet) {
      return _BottomBanners(appState: appState);
    }

    final strings = AppLocalizations.of(context)!;
    final glassSettings = iosLiquidGlassSettings(
      context,
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassQuality = iosLiquidGlassQuality(
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassForeground = iosLiquidGlassForeground(context);
    final visibleActions = iosPhoneVisibleToolbarActions(
      selectedActions: appState.iosToolbarActions,
      availableActions: _availableToolbarActions(appState),
    );
    final menuItems = _menuItems(
      appState,
      excludedActions: visibleActions.toSet(),
    );

    Widget buildButtonGroup(VoidCallback toggleMenu) {
      return GlassButtonGroup.icons(
        useOwnLayer: true,
        quality: glassQuality,
        settings: glassSettings,
        itemPadding: const EdgeInsets.all(10),
        items: [
          GlassButtonGroupItem(
            label: appState.syncProcess ? strings.cancel : strings.syncNews,
            onTap: () => unawaited(_sync(appState)),
            icon: appState.syncProcess
                ? CupertinoActivityIndicator(
                    radius: 9,
                    color: glassForeground,
                  )
                : Icon(Icons.refresh, color: glassForeground),
          ),
          for (final action in visibleActions)
            _iosDirectAction(
              action,
              appState,
              foreground: glassForeground,
            ),
          GlassButtonGroupItem(
            label: strings.moreActions,
            onTap: toggleMenu,
            icon: Icon(CupertinoIcons.ellipsis, color: glassForeground),
          ),
        ],
      );
    }

    final contentChrome = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BottomBanners(
          appState: appState,
          respectBottomSafeArea: false,
        ),
        AdaptiveLiquidGlassLayer(
          quality: glassQuality,
          settings: glassSettings,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Center(
                child: GlassMenu(
                  quality: GlassQuality.standard,
                  settings: iosLiquidGlassMenuSettings(
                    context,
                    useClearEffect: appState.iosClearLiquidGlass,
                  ),
                  items: menuItems,
                  menuWidth: (MediaQuery.sizeOf(context).width - 32)
                      .clamp(280.0, 340.0)
                      .toDouble(),
                  autoAdjustToScreen: true,
                  menuPadding: const EdgeInsets.all(12),
                  triggerBuilder: (context, toggleMenu) =>
                      buildButtonGroup(toggleMenu),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return contentChrome;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<FluxNewsState>();
    final appCounterState = context.watch<FluxNewsCounterState>();
    final hasNewsConfiguration = appState.startUp ||
        (appState.minifluxURL != null &&
            appState.minifluxAPIKey != null &&
            !appState.errorOnMinifluxAuth);
    final titleController = hasNewsConfiguration ? _largeTitleController : null;
    final title = appState.appBarText.isEmpty
        ? AppLocalizations.of(context)!.fluxNews
        : appState.appBarText;
    final glassSettings = iosLiquidGlassSettings(
      context,
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassQuality = iosLiquidGlassQuality(
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassForeground = iosLiquidGlassForeground(context);
    final compactTitle = GlassContainer(
      useOwnLayer: true,
      quality: glassQuality,
      settings: glassSettings,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: glassForeground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (appState.multilineAppBarText) ...[
            const SizedBox(width: 6),
            Semantics(
              label:
                  '${AppLocalizations.of(context)!.itemCount}: ${appCounterState.appBarNewsCount}',
              child: Text(
                '${appCounterState.appBarNewsCount}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: glassForeground,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
    final topContentInset = MediaQuery.paddingOf(context).top + 44;
    return LayoutBuilder(
      builder: (context, constraints) {
        final usesWideSidebar = useIOSPermanentSidebar(
          isTablet: widget.isTablet,
          availableWidth: constraints.maxWidth,
        );
        final sidebarWidth = usesWideSidebar
            ? (constraints.maxWidth * 0.25).clamp(260.0, 340.0).toDouble()
            : 0.0;
        Widget list = IOSNewsScrollEdgeEffect(
          topChromeExtent: topContentInset,
          isTablet: widget.isTablet,
          child: FluxNewsBodyList(
            largeTitleController: titleController,
            topContentInset: topContentInset,
          ),
        );
        if (usesWideSidebar) {
          list = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _wideTabletSidebar(width: sidebarWidth),
              Expanded(child: list),
            ],
          );
        }

        final appBarTitle = usesWideSidebar
            ? Row(
                children: [
                  SizedBox(width: sidebarWidth),
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: compactTitle,
                    ),
                  ),
                ],
              )
            : compactTitle;

        return Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          drawerScrimColor: Colors.black.withValues(alpha: 0.28),
          appBar: GlassAppBar(
            centerTitle: false,
            largeTitleController: titleController,
            leading: usesWideSidebar
                ? null
                : Builder(builder: (context) {
                    return GlassIconButton(
                      quality: glassQuality,
                      useOwnLayer: true,
                      settings: glassSettings,
                      semanticLabel: MaterialLocalizations.of(context)
                          .openAppDrawerTooltip,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: FaIcon(
                        FontAwesomeIcons.bookOpen,
                        size: 18,
                        color: glassForeground,
                      ),
                    );
                  }),
            title: appBarTitle,
            actions: usesWideSidebar
                ? _wideTabletActions(
                    appState,
                    settings: glassSettings,
                    quality: glassQuality,
                    foreground: glassForeground,
                    newsPaneWidth: constraints.maxWidth - sidebarWidth,
                  )
                : widget.isTablet
                    ? _compactTopActions(
                        appState,
                        settings: glassSettings,
                        quality: glassQuality,
                        foreground: glassForeground,
                      )
                    : const <Widget>[],
          ),
          drawer: usesWideSidebar ? null : widget.drawer,
          body: list,
          bottomNavigationBar: _bottomChrome(
            appState,
            usesWideSidebar: usesWideSidebar,
            sidebarWidth: sidebarWidth,
          ),
        );
      },
    );
  }
}

class PersistentAudioMiniPlayer extends StatefulWidget {
  const PersistentAudioMiniPlayer({
    super.key,
    required this.appState,
    this.respectBottomSafeArea = true,
  });

  final FluxNewsState appState;
  final bool respectBottomSafeArea;

  @override
  State<PersistentAudioMiniPlayer> createState() =>
      _PersistentAudioMiniPlayerState();
}

class _PersistentAudioMiniPlayerState extends State<PersistentAudioMiniPlayer> {
  FluxNewsAudioHandler? _audioHandler;
  StreamSubscription<PlaybackState>? _completionSubscription;
  StreamSubscription<SleepTimerEvent>? _sleepTimerSubscription;

  @override
  void initState() {
    super.initState();
    _initAudioHandler();
  }

  @override
  void dispose() {
    _completionSubscription?.cancel();
    _sleepTimerSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initAudioHandler() async {
    final handler = await initFluxNewsAudioHandler();
    if (!mounted) return;
    setState(() {
      _audioHandler = handler;
    });
    _completionSubscription = handler.playbackState.listen((state) {
      if (state.processingState == AudioProcessingState.completed) {
        _handleCompletion(handler);
      }
    });
    _sleepTimerSubscription = handler.sleepTimerStream.listen((event) {
      if (!mounted || event != SleepTimerEvent.fired) return;
      final extras = handler.mediaItem.value?.extras;
      final attachmentID = extras?['attachmentID'];
      final newsID = extras?['newsID'];
      final position = handler.position;
      if (attachmentID is int && newsID is int && position > Duration.zero) {
        syncMediaProgression(
                widget.appState, newsID, attachmentID, position.inSeconds)
            .ignore();
      }
    });
  }

  Future<News?> _resolveCurrentPlaybackNews(
      FluxNewsAudioHandler handler) async {
    final media = handler.mediaItem.value;
    if (media == null) return null;

    final extras = media.extras;

    final newsIdFromExtras = extras?['newsID'];
    if (newsIdFromExtras is int) {
      final news = await queryNewsByNewsId(widget.appState, newsIdFromExtras);
      if (news != null) return news;
    }

    final attachmentIdFromExtras = extras?['attachmentID'];
    if (attachmentIdFromExtras is int) {
      final newsID = await queryNewsIdByAttachmentId(
          widget.appState, attachmentIdFromExtras);
      if (newsID != null) {
        return await queryNewsByNewsId(widget.appState, newsID);
      }
    }

    final newsID = await queryNewsIdByAttachmentUrl(widget.appState, media.id);
    if (newsID == null) return null;
    return await queryNewsByNewsId(widget.appState, newsID);
  }

  Future<void> _handleCompletion(FluxNewsAudioHandler handler) async {
    final activeNews = await _resolveCurrentPlaybackNews(handler);
    if (activeNews != null) {
      final attachments = activeNews.getAudioAttachments();

      // Prefer attachmentID from extras — the media item ID may be a file://
      // URI (CarPlay/downloaded playback) which won't match attachmentURL.
      final extras = handler.mediaItem.value?.extras;
      final attachmentIdFromExtras = extras?['attachmentID'];
      final completedAttachment = attachmentIdFromExtras is int
          ? attachments
              .where((a) => a.attachmentID == attachmentIdFromExtras)
              .fold<Attachment?>(null, (prev, e) => prev ?? e)
          : attachments
              .where((a) => a.attachmentURL == handler.mediaItem.value?.id)
              .fold<Attachment?>(null, (prev, e) => prev ?? e);

      // Stop first — handler.stop() internally re-saves progress, so we
      // write "0" afterwards to mark the episode as completed. Using "0" rather
      // than deleting lets _loadProgress / _resolveSavedPosition distinguish
      // "explicitly reset" from "never played" and ignore stale server values.
      await handler.stop();
      await AudioProgressStore.write(
          AudioProgressStore.keyForNews(activeNews.newsID), '0');

      if (completedAttachment != null) {
        syncMediaProgression(widget.appState, activeNews.newsID,
                completedAttachment.attachmentID, 0)
            .ignore();

        if (widget.appState.deleteAudioAfterPlayback) {
          await AudioDownloadService.deleteDownloadedAudio(
              completedAttachment.attachmentID);
        }
      }
    } else {
      await handler.stop();
    }
  }

  Future<void> _stopMiniPlayer() async {
    final handler = _audioHandler;
    if (handler == null) return;

    final position = handler.position;
    final extras = handler.mediaItem.value?.extras;
    final attachmentIdFromExtras = extras?['attachmentID'];
    final newsIdFromExtras = extras?['newsID'];

    await handler.stop();

    if (attachmentIdFromExtras is int &&
        newsIdFromExtras is int &&
        position > Duration.zero) {
      syncMediaProgression(widget.appState, newsIdFromExtras,
              attachmentIdFromExtras, position.inSeconds)
          .ignore();
    }
  }

  Future<void> _openFullPlayer() async {
    final handler = _audioHandler;
    if (handler == null) return;

    final activeNews = await _resolveCurrentPlaybackNews(handler);
    if (!mounted || activeNews == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewsAudioPlayerScreen(news: activeNews),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_audioHandler == null) return const SizedBox.shrink();

    return StreamBuilder<MediaItem?>(
      stream: _audioHandler!.mediaItem,
      initialData: _audioHandler!.mediaItem.value,
      builder: (context, mediaSnapshot) {
        final media = mediaSnapshot.data;
        if (media == null) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<PlaybackState>(
          stream: _audioHandler!.playbackState,
          initialData: _audioHandler!.playbackState.value,
          builder: (context, playbackSnapshot) {
            final playback = playbackSnapshot.data;
            if (playback == null) {
              return const SizedBox.shrink();
            }

            final colorScheme = Theme.of(context).colorScheme;
            final miniPlayerBackground = colorScheme.primaryContainer;
            final miniPlayerForeground = colorScheme.onPrimaryContainer;

            final isVisible = playback.playing ||
                playback.processingState != AudioProcessingState.idle;
            if (!isVisible) {
              return const SizedBox.shrink();
            }

            // Detect tablet layout
            final isTablet = useTwoPaneLayout(MediaQuery.sizeOf(context));
            final iconSize = isTablet ? 38.0 : 34.0;
            final buttonSize = isTablet ? 60.0 : 52.0;
            final textFontSize = isTablet ? 14.0 : 12.0;

            final totalMs = media.duration?.inMilliseconds ?? 0;
            final currentMs = totalMs <= 0
                ? 0
                : playback.updatePosition.inMilliseconds.clamp(0, totalMs);
            final progress = totalMs <= 0 ? null : currentMs / totalMs;

            if (Platform.isIOS) {
              final useClearEffect = widget.appState.iosClearLiquidGlass;
              final glassSettings = iosLiquidGlassSettings(
                context,
                useClearEffect: useClearEffect,
              );
              final glassQuality = iosLiquidGlassQuality(
                useClearEffect: useClearEffect,
              );
              final glassForeground = iosLiquidGlassForeground(context);
              final artist = media.artist?.trim() ?? '';

              return SafeArea(
                top: false,
                bottom: widget.respectBottomSafeArea,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 20 : 16,
                    4,
                    isTablet ? 20 : 16,
                    6,
                  ),
                  child: GlassContainer(
                    useOwnLayer: true,
                    quality: glassQuality,
                    settings: glassSettings,
                    shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openFullPlayer,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color:
                                      glassForeground.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  CupertinoIcons.headphones,
                                  size: 21,
                                  color: glassForeground,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      media.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: glassForeground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if (artist.isNotEmpty)
                                      Text(
                                        artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: glassForeground.withValues(
                                                alpha: 0.65,
                                              ),
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                color: glassForeground,
                                tooltip: '-30s',
                                onPressed: () => _audioHandler!.rewind(),
                                icon: const Icon(Icons.replay_30, size: 24),
                              ),
                              IconButton(
                                color: glassForeground,
                                tooltip: playback.playing
                                    ? AppLocalizations.of(context)!.pause
                                    : AppLocalizations.of(context)!.play,
                                onPressed: () => playback.playing
                                    ? _audioHandler!.pause()
                                    : _audioHandler!.play(),
                                icon: Icon(
                                  playback.playing
                                      ? CupertinoIcons.pause_fill
                                      : CupertinoIcons.play_fill,
                                ),
                              ),
                              IconButton(
                                color: glassForeground,
                                tooltip: '+30s',
                                onPressed: () => _audioHandler!.fastForward(),
                                icon: const Icon(Icons.forward_30, size: 24),
                              ),
                              IconButton(
                                color: glassForeground,
                                tooltip: AppLocalizations.of(context)!.stop,
                                onPressed: _stopMiniPlayer,
                                icon: const Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  size: 21,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor:
                                  glassForeground.withValues(alpha: 0.16),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                glassForeground.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              bottom: widget.respectBottomSafeArea,
              child: Material(
                elevation: 8,
                color: miniPlayerBackground,
                child: InkWell(
                  onTap: _openFullPlayer,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 12 : 8,
                      vertical: isTablet ? 8 : 6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconTheme(
                          data: IconThemeData(color: miniPlayerForeground),
                          child: Row(
                            children: [
                              IconButton(
                                color: miniPlayerForeground,
                                iconSize: iconSize,
                                constraints: BoxConstraints(
                                  minWidth: buttonSize,
                                  minHeight: buttonSize,
                                ),
                                tooltip: '-30s',
                                onPressed: () => _audioHandler!.rewind(),
                                icon: const Icon(Icons.replay_30),
                              ),
                              IconButton(
                                color: miniPlayerForeground,
                                iconSize: iconSize,
                                constraints: BoxConstraints(
                                  minWidth: buttonSize,
                                  minHeight: buttonSize,
                                ),
                                tooltip: playback.playing
                                    ? AppLocalizations.of(context)!.pause
                                    : AppLocalizations.of(context)!.play,
                                onPressed: () => playback.playing
                                    ? _audioHandler!.pause()
                                    : _audioHandler!.play(),
                                icon: Icon(playback.playing
                                    ? Icons.pause_circle
                                    : Icons.play_circle),
                              ),
                              IconButton(
                                color: miniPlayerForeground,
                                iconSize: iconSize,
                                constraints: BoxConstraints(
                                  minWidth: buttonSize,
                                  minHeight: buttonSize,
                                ),
                                tooltip: AppLocalizations.of(context)!.stop,
                                onPressed: _stopMiniPlayer,
                                icon: const Icon(Icons.stop_circle),
                              ),
                              IconButton(
                                color: miniPlayerForeground,
                                iconSize: iconSize,
                                constraints: BoxConstraints(
                                  minWidth: buttonSize,
                                  minHeight: buttonSize,
                                ),
                                tooltip: '+30s',
                                onPressed: () => _audioHandler!.fastForward(),
                                icon: const Icon(Icons.forward_30),
                              ),
                              SizedBox(width: isTablet ? 8 : 4),
                              Expanded(
                                child: Text(
                                  media.title,
                                  maxLines: isTablet ? 3 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: textFontSize,
                                        height: 1.15,
                                        fontWeight: FontWeight.w600,
                                        color: miniPlayerForeground,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isTablet ? 6 : 4),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: isTablet ? 4 : 3,
                          backgroundColor:
                              miniPlayerForeground.withValues(alpha: 0.25),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              miniPlayerForeground),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Bottom banners: download progress + mini player stacked ─────────────────

class _BottomBanners extends StatelessWidget {
  const _BottomBanners({
    required this.appState,
    this.respectBottomSafeArea = true,
  });
  final FluxNewsState appState;
  final bool respectBottomSafeArea;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PersistentDownloadBanner(
          appState: appState,
          respectBottomSafeArea: respectBottomSafeArea,
        ),
        PersistentAudioMiniPlayer(
          appState: appState,
          respectBottomSafeArea: respectBottomSafeArea,
        ),
      ],
    );
  }
}

class PersistentDownloadBanner extends StatelessWidget {
  const PersistentDownloadBanner({
    super.key,
    required this.appState,
    this.respectBottomSafeArea = true,
  });
  final FluxNewsState appState;
  final bool respectBottomSafeArea;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AudioDownloadProgress>>(
      initialData: AudioDownloadService.getActiveDownloadsSnapshot(),
      stream: AudioDownloadService.activeDownloadsStream,
      builder: (context, snapshot) {
        final downloads = snapshot.data ?? const [];
        if (downloads.isEmpty) return const SizedBox.shrink();

        final isTablet = useTwoPaneLayout(MediaQuery.sizeOf(context));

        if (Platform.isIOS) {
          final glassForeground = iosLiquidGlassForeground(context);
          return SafeArea(
            top: false,
            bottom: respectBottomSafeArea,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 20 : 16,
                4,
                isTablet ? 20 : 16,
                6,
              ),
              child: GlassContainer(
                useOwnLayer: true,
                quality: GlassQuality.standard,
                settings: iosLiquidGlassSettings(
                  context,
                  useClearEffect: appState.iosClearLiquidGlass,
                ),
                shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 12 : 10,
                  vertical: isTablet ? 8 : 7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: downloads
                      .map((download) => _DownloadRow(
                            progress: download,
                            foreground: glassForeground,
                            isTablet: isTablet,
                          ))
                      .toList(),
                ),
              ),
            ),
          );
        }

        final colorScheme = Theme.of(context).colorScheme;
        final bg = colorScheme.tertiaryContainer;
        final fg = colorScheme.onTertiaryContainer;

        return SafeArea(
          top: false,
          bottom: respectBottomSafeArea,
          child: Material(
            elevation: 8,
            color: bg,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 12 : 8,
                vertical: isTablet ? 8 : 6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: downloads
                    .map((d) => _DownloadRow(
                          progress: d,
                          foreground: fg,
                          isTablet: isTablet,
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.progress,
    required this.foreground,
    required this.isTablet,
  });

  final AudioDownloadProgress progress;
  final Color foreground;
  final bool isTablet;

  String _subtitle(BuildContext context) {
    if (progress.isQueued) return AppLocalizations.of(context)!.downloadQueued;
    if (progress.totalBytes > 0) {
      return '${AudioDownloadService.formatBytes(progress.receivedBytes)}'
          ' / ${AudioDownloadService.formatBytes(progress.totalBytes)}';
    }
    return AudioDownloadService.formatBytes(progress.receivedBytes);
  }

  @override
  Widget build(BuildContext context) {
    final title =
        AudioDownloadService.getDownloadTitle(progress.attachmentID) ??
            progress.fileName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: isTablet ? 13 : 11,
                              fontWeight: FontWeight.w600,
                              color: foreground,
                            ),
                      ),
                    ),
                    Text(
                      _subtitle(context),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: isTablet ? 11 : 10,
                            color: foreground.withAlpha(180),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progress.progress,
                  minHeight: isTablet ? 4 : 3,
                  backgroundColor: foreground.withAlpha(50),
                  valueColor: AlwaysStoppedAnimation<Color>(foreground),
                ),
              ],
            ),
          ),
          IconButton(
            icon:
                Icon(Icons.close, size: isTablet ? 20 : 18, color: foreground),
            tooltip: AppLocalizations.of(context)!.cancel,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(),
            onPressed: () =>
                AudioDownloadService.cancelDownload(progress.attachmentID),
          ),
        ],
      ),
    );
  }
}

class FluxNewsBodyList extends StatelessWidget {
  const FluxNewsBodyList({
    super.key,
    this.largeTitleController,
    this.topContentInset = 0,
  });

  final GlassLargeTitleController? largeTitleController;
  final double topContentInset;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // return the body of the main view
    // if errors had occurred, the error widget is returned
    // if the miniflux settings are incorrect a corresponding message is shown
    // otherwise the normal list view is returned
    if ((appState.minifluxURL == null ||
            appState.minifluxAPIKey == null ||
            appState.errorOnMinifluxAuth == true) &&
        !appState.startUp) {
      return Padding(
        padding: EdgeInsets.only(top: topContentInset),
        child: const NoSettings(),
      );
    } else if (appState.errorString.trim().isNotEmpty && appState.newError) {
      return ErrorWidget(
        largeTitleController: largeTitleController,
        topContentInset: topContentInset,
      );
    } else if (appState.longSync) {
      return LongSyncWidget(
        largeTitleController: largeTitleController,
        topContentInset: topContentInset,
      );
    } else if (appState.tooManyNews) {
      return TooManyNewsWidget(
        largeTitleController: largeTitleController,
        topContentInset: topContentInset,
      );
    } else {
      return BodyNewsList(
        largeTitleController: largeTitleController,
        topContentInset: topContentInset,
      );
    }
  }
}

// this widget replace the normal news list widget, if a error occurs
// it will pop up an error dialog and then show the normal news list in the background.
class ErrorWidget extends StatelessWidget {
  const ErrorWidget({
    super.key,
    this.largeTitleController,
    this.topContentInset = 0,
  });

  final GlassLargeTitleController? largeTitleController;
  final double topContentInset;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    if (!appState.errorDialogVisible && appState.newError) {
      final currentMessage = appState.errorString.trim();
      final message = currentMessage.isEmpty
          ? AppLocalizations.of(context)!.communicateionMinifluxError
          : currentMessage;

      // Consume this exact error before scheduling the dialog. A later error
      // can set newError again and will be displayed after the current dialog
      // closes instead of being cleared by its completion callback.
      appState.newError = false;
      appState.errorDialogVisible = true;
      Timer.run(() async {
        try {
          if (context.mounted) {
            await showErrorDialog(context, message);
          }
        } finally {
          appState.errorDialogVisible = false;
          if (!appState.newError && appState.errorString.trim() == message) {
            appState.errorString = '';
          }
          if (context.mounted) {
            appState.refreshView();
          }
        }
      });
    }
    return BodyNewsList(
      largeTitleController: largeTitleController,
      topContentInset: topContentInset,
    );
  }

  // this is the error dialog which is shown, if a error occurs.
  // to prevent the multi pop up (f.e. if the internet connection ist lost
  // not every function which require the connection should raise a pop up)
  // we check if the error which is shown is a new error.
  Future<void> showErrorDialog(BuildContext context, String message) async {
    FluxNewsState appState = context.read<FluxNewsState>();
    if (Platform.isIOS) {
      await showAdaptiveGlassDialog<void>(
        context: context,
        title: AppLocalizations.of(context)!.error,
        message: message,
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
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog.adaptive(
          title: Text(AppLocalizations.of(context)!.error),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, FluxNewsState.cancelContextString);
              },
              child: Text(AppLocalizations.of(context)!.ok),
            ),
          ],
        );
      },
    );
  }
}

// this widget replace the normal news list widget, if a long sync is detected
// it will pop up an long sync warning dialog and then show the normal news list in the background.
class LongSyncWidget extends StatelessWidget {
  const LongSyncWidget({
    super.key,
    this.largeTitleController,
    this.topContentInset = 0,
  });

  final GlassLargeTitleController? largeTitleController;
  final double topContentInset;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    Timer.run(() {
      showLongSyncDialog(context).then((value) {
        appState.longSync = false;
        appState.longSyncAlerted = true;
        appState.refreshView();
      });
    });
    return BodyNewsList(
      largeTitleController: largeTitleController,
      topContentInset: topContentInset,
    );
  }

  // this is the error dialog which is shown, if a error occurs.
  // to prevent the multi pop up (f.e. if the internet connection ist lost
  // not every function which require the connection should raise a pop up)
  // we check if the error which is shown is a new error.
  Future showLongSyncDialog(BuildContext context) async {
    FluxNewsState appState = context.read<FluxNewsState>();
    if (appState.longSync) {
      if (Platform.isIOS) {
        await showAdaptiveGlassDialog<void>(
          context: context,
          title: AppLocalizations.of(context)!.longSyncHeader,
          message: AppLocalizations.of(context)!.longSyncWarning,
          settings: iosLiquidGlassMenuSettings(
            context,
            useClearEffect: appState.iosClearLiquidGlass,
          ),
          quality: GlassQuality.standard,
          maxWidth: 360,
          actions: [
            GlassDialogAction(
              label: AppLocalizations.of(context)!.cancel,
              isDestructive: true,
              onPressed: () {
                appState.longSyncAborted = true;
                appState.refreshView();
                Navigator.pop(context, FluxNewsState.cancelContextString);
              },
            ),
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
              title: Text(AppLocalizations.of(context)!.longSyncHeader),
              content: Text(AppLocalizations.of(context)!.longSyncWarning),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    appState.longSyncAborted = true;
                    appState.refreshView();
                    Navigator.pop(context, FluxNewsState.cancelContextString);
                  },
                  child: Text(
                    AppLocalizations.of(context)!.cancel,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
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

// this widget replace the normal news list widget, if too many news are detected
// it will pop up an too many news warning dialog and then show the normal news list in the background.
class TooManyNewsWidget extends StatelessWidget {
  const TooManyNewsWidget({
    super.key,
    this.largeTitleController,
    this.topContentInset = 0,
  });

  final GlassLargeTitleController? largeTitleController;
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
    return BodyNewsList(
      largeTitleController: largeTitleController,
      topContentInset: topContentInset,
    );
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

// this widget replace the news list view, if the miniflux server settings
// are not set or not correct.
class NoSettings extends StatelessWidget {
  const NoSettings({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)!.settingsNotSet,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 20.0, right: 30),
            child: Text(
              AppLocalizations.of(context)!.provideMinifluxCredentials,
              style: const TextStyle(
                  color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: Platform.isIOS
                ? CupertinoButton.filled(
                    child: Text(AppLocalizations.of(context)!.login),
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
                    child: Text(AppLocalizations.of(context)!.login),
                  ),
          ),
        ],
      ),
    );
  }
}

class AppBarTitle extends StatelessWidget {
  const AppBarTitle({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsCounterState appCounterState =
        context.watch<FluxNewsCounterState>();
    FluxNewsState appState = context.watch<FluxNewsState>();

    // set the app bar title depending on the chosen category to show in list view

    if (appState.multilineAppBarText) {
      // this is the part where the news count is added as an extra line to the app bar title
      return Builder(builder: (BuildContext context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appState.appBarText,
              maxLines: 2,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${AppLocalizations.of(context)!.itemCount}: ${appCounterState.appBarNewsCount}',
              style: Theme.of(context).textTheme.labelMedium,
            )
          ],
        );
      });
    } else {
      // this is the part without the news count as an extra line
      return Text(
        appState.appBarText,
        maxLines: 2,
        textAlign: TextAlign.start,
        style: Theme.of(context).textTheme.titleLarge,
      );
    }
  }
}

class CategoryList extends StatelessWidget {
  const CategoryList({
    super.key,
    this.iosSidebar = false,
    this.closeDrawerOnSelection = false,
  });

  final bool iosSidebar;
  final bool closeDrawerOnSelection;

  @override
  Widget build(BuildContext context) {
    FluxNewsCounterState appCounterState =
        context.watch<FluxNewsCounterState>();
    FluxNewsState appState = context.watch<FluxNewsState>();
    var getData = FutureBuilder<Categories>(
        future: appState.categoryList,
        builder: (context, snapshot) {
          if (appCounterState.listUpdated) {
            appCounterState.listUpdated = false;
            snapshot.data?.renewNewsCount(appState, context);
            renewAllNewsCount(appState, context);
          }
          switch (snapshot.connectionState) {
            case ConnectionState.none:
            case ConnectionState.waiting:
              // we add a static category of "All News" to the list of categories
              // while waiting on the news list from the miniflux server
              return _buildNavigationTile(
                context: context,
                leading: const Icon(Icons.home),
                title: AppLocalizations.of(context)!.allNews,
                selected: false,
              );
            default:
              if (snapshot.hasError) {
                return const SizedBox.shrink();
              } else {
                appState.actualCategoryList = snapshot.data;
                return snapshot.data != null
                    ? snapshot.data!.categories.isEmpty
                        ? const SizedBox.shrink()
                        // if the category list from the miniflux server is not null
                        // and not empty, we show the category list
                        : Column(children: [
                            // we add a static category of "All News" to the list of categories
                            _buildNavigationTile(
                              context: context,
                              leading: const Icon(
                                Icons.home,
                              ),
                              title: AppLocalizations.of(context)!.allNews,
                              count: appCounterState.allNewsCount,
                              selected: appState.selectedCategoryElementType ==
                                  FluxNewsState.allNewsElementType,
                              onTap: () {
                                allNewsOnClick(appState, context);
                              },
                            ),
                            // we add a static category of "Bookmarked" to the list of categories
                            _buildNavigationTile(
                              context: context,
                              leading: const Icon(
                                Icons.star,
                              ),
                              title: AppLocalizations.of(context)!.bookmarked,
                              count: appCounterState.starredCount,
                              selected: appState.selectedCategoryElementType ==
                                  FluxNewsState.bookmarkedNewsElementType,
                              onTap: () {
                                bookmarkedOnClick(appState, context);
                              },
                            ),
                            // we iterate over the category list
                            for (Category category in snapshot.data!.categories)
                              appState.showOnlyFeedCategoriesWithNewNews
                                  ? category.newsCount > 0
                                      ? showCategory(
                                          category, snapshot.data!, context)
                                      : const SizedBox.shrink()
                                  : showCategory(
                                      category, snapshot.data!, context),
                          ])
                    : const SizedBox.shrink();
              }
          }
        });
    return getData;
  }

  Widget _buildNavigationTile({
    required BuildContext context,
    required Widget leading,
    required String title,
    required bool selected,
    int? count,
    VoidCallback? onTap,
  }) {
    final accent = _navigationSelectionAccent(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: iosSidebar,
          minTileHeight: iosSidebar ? 44 : null,
          contentPadding: iosSidebar
              ? const EdgeInsetsDirectional.only(start: 8, end: 16)
              : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          selected: selected,
          selectedColor: accent,
          leading: leading,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? accent : null,
                ),
          ),
          trailing: count == null
              ? null
              : _buildCountLabel(
                  context: context,
                  count: count,
                  selected: selected,
                ),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildCountLabel({
    required BuildContext context,
    required int count,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final accent = _navigationSelectionAccent(context);
    Widget label = Text(
      '$count',
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? accent : null,
          ),
    );
    if (iosSidebar) {
      label = SizedBox(
        width: 32,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: label,
        ),
      );
    }
    return onTap == null ? label : InkWell(onTap: onTap, child: label);
  }

  // here we style the category ExpansionTile
  // we use a ExpansionTile because we want to show the according feeds
  // of this category in the expanded state.
  Widget showCategory(
      Category category, Categories categories, BuildContext context) {
    FluxNewsState appState = context.read<FluxNewsState>();
    final selected = appState.selectedCategoryElementType ==
            FluxNewsState.categoryElementType &&
        appState.selectedID == category.categoryID;
    final selectedFeedId =
        appState.selectedCategoryElementType == FluxNewsState.feedElementType
            ? appState.selectedID
            : null;
    final containsSelectedFeed = selectedFeedId != null &&
        category.feeds.any((feed) => feed.feedID == selectedFeedId);
    final accent = _navigationSelectionAccent(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Stack(
        children: [
          if (selected)
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              height: iosSidebar ? 44 : 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          _AutoExpandingCategory(
            key: ValueKey<int>(category.categoryID),
            selectedFeedId: selectedFeedId,
            containsSelectedFeed: containsSelectedFeed,
            builder: (context, controller) => ExpansionTile(
              controller: controller,
              dense: iosSidebar,
              minTileHeight: iosSidebar ? 44 : null,
              tilePadding: iosSidebar
                  ? const EdgeInsetsDirectional.only(start: 8, end: 16)
                  : null,
              childrenPadding: iosSidebar
                  ? const EdgeInsetsDirectional.only(start: 12, bottom: 4)
                  : EdgeInsets.zero,
              iconColor: selected ? accent : null,
              collapsedIconColor: selected ? accent : null,
              shape: const Border(),
              collapsedShape: const Border(),
              // we want the expansion arrow at the beginning,
              // because we want to show the news count at the end of this row.
              controlAffinity: ListTileControlAffinity.leading,
              // make the title clickable to select this category as the news view
              title: InkWell(
                child: Text(
                  category.title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected ? accent : null,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  categoryOnClick(category, appState, categories, context);
                },
              ),
              // show the news count of this category
              trailing: _buildCountLabel(
                context: context,
                count: category.newsCount,
                selected: selected,
                onTap: () {
                  categoryOnClick(category, appState, categories, context);
                },
              ),
              // iterate over the according feeds of the category
              children: [
                for (Feed feed in category.feeds)
                  FeedTile(
                    feed: feed,
                    categories: categories,
                    iosSidebar: iosSidebar,
                    closeDrawerOnSelection: closeDrawerOnSelection,
                  )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // if the title of the category is clicked,
  // we want all the news of this category in the news view.
  Future<void> categoryOnClick(Category category, FluxNewsState appState,
      Categories categories, BuildContext context) async {
    // add the according feeds of this category as a filter
    appState.feedIDs = category.getFeedIDs();
    appState.selectedCategoryElementType = FluxNewsState.categoryElementType;
    // reload the news list with the new filter
    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
      _resetListAfterNavigationSelection(appState);
    });
    // set the category title as app bar title
    // and update the news count in the app bar, if the function is activated.
    appState.appBarText = category.title;
    appState.selectedID = category.categoryID;
    categories.renewNewsCount(appState, context);
    // update the view after changing the values
    appState.refreshView();

    _closeNavigationDrawerAfterSelection(
      context,
      appState,
      force: closeDrawerOnSelection,
    );
  }

  // if the "All News" ListTile is clicked,
  // we want all the news in the news view.
  Future<void> allNewsOnClick(
      FluxNewsState appState, BuildContext context) async {
    // empty the feedIds which are used as a filter if a specific category is selected
    appState.feedIDs = null;
    appState.selectedCategoryElementType = FluxNewsState.allNewsElementType;
    // reload the news list with the new filter (empty)
    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
      _resetListAfterNavigationSelection(appState);
    });
    // set the "All News" title as app bar title
    // and update the news count in the app bar, if the function is activated.
    appState.appBarText = AppLocalizations.of(context)!.allNews;
    appState.selectedID = null;
    if (context.mounted) {
      renewAllNewsCount(appState, context);
    }
    // update the view after changing the values
    appState.refreshView();

    _closeNavigationDrawerAfterSelection(
      context,
      appState,
      force: closeDrawerOnSelection,
    );
  }

  // if the "Bookmarked" ListTile is clicked,
  // we want all the bookmarked news in the news view.
  Future<void> bookmarkedOnClick(
      FluxNewsState appState, BuildContext context) async {
    // set the feedIDs filter to -1 to only load bookmarked news
    // -1 is a impossible feed id of a regular miniflux feed,
    // so we use it to decide between all news (feedIds = null)
    // and bookmarked news (feedIds = -1).
    appState.feedIDs = [-1];
    appState.selectedCategoryElementType =
        FluxNewsState.bookmarkedNewsElementType;
    // reload the news list with the new filter (-1 only bookmarked news)
    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
      _resetListAfterNavigationSelection(appState);
    });
    // set the "Bookmarked" title as app bar title
    // and update the news count in the app bar, if the function is activated.
    appState.appBarText = AppLocalizations.of(context)!.bookmarked;
    appState.selectedID = -1;
    if (context.mounted) {
      updateStarredCounter(appState, context);
    }
    // update the view after changing the values
    appState.refreshView();

    _closeNavigationDrawerAfterSelection(
      context,
      appState,
      force: closeDrawerOnSelection,
    );
  }

  // here we style the ListTile of the feeds which are subordinate to the categories
}

class _AutoExpandingCategory extends StatefulWidget {
  const _AutoExpandingCategory({
    super.key,
    required this.selectedFeedId,
    required this.containsSelectedFeed,
    required this.builder,
  });

  final int? selectedFeedId;
  final bool containsSelectedFeed;
  final Widget Function(BuildContext, ExpansibleController) builder;

  @override
  State<_AutoExpandingCategory> createState() => _AutoExpandingCategoryState();
}

class _AutoExpandingCategoryState extends State<_AutoExpandingCategory> {
  late final ExpansibleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ExpansibleController();
    if (widget.containsSelectedFeed) {
      _controller.expand();
    }
  }

  @override
  void didUpdateWidget(covariant _AutoExpandingCategory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.containsSelectedFeed &&
        widget.selectedFeedId != oldWidget.selectedFeedId &&
        !_controller.isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_controller.isExpanded) {
          _controller.expand();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

class FeedTile extends StatelessWidget {
  const FeedTile({
    super.key,
    required this.feed,
    required this.categories,
    this.iosSidebar = false,
    this.closeDrawerOnSelection = false,
  });

  final Feed feed;
  final Categories categories;
  final bool iosSidebar;
  final bool closeDrawerOnSelection;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    if (appState.showOnlyFeedCategoriesWithNewNews && feed.newsCount <= 0) {
      return const SizedBox.shrink();
    }

    final selected =
        appState.selectedCategoryElementType == FluxNewsState.feedElementType &&
            appState.selectedID == feed.feedID;
    final accent = _navigationSelectionAccent(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 1, 8, 1),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          dense: iosSidebar,
          minTileHeight: iosSidebar ? 40 : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          selected: selected,
          selectedColor: accent,
          title: Padding(
            padding: EdgeInsetsDirectional.only(start: iosSidebar ? 0 : 8),
            child: Row(children: [
              if (appState.showFeedIcons) feed.getFeedIcon(16.0, context),
              if (appState.showFeedIcons) const SizedBox(width: 10),
              Expanded(
                child: Text(
                  feed.title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected ? accent : null,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
          trailing: Text(
            '${feed.newsCount}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? accent : null,
                ),
          ),
          onTap: () {
            appState.feedIDs = [feed.feedID];
            appState.selectedCategoryElementType =
                FluxNewsState.feedElementType;
            appState.newsList = queryNewsFromDB(appState).whenComplete(() {
              _resetListAfterNavigationSelection(appState);
            });
            appState.appBarText = feed.title;
            appState.selectedID = feed.feedID;
            categories.renewNewsCount(appState, context);
            appState.refreshView();
            _closeNavigationDrawerAfterSelection(
              context,
              appState,
              force: closeDrawerOnSelection,
            );
          },
        ),
      ),
    );
  }
}

Color _navigationSelectionAccent(BuildContext context) {
  if (Platform.isIOS) {
    return CupertinoColors.activeBlue.resolveFrom(context);
  }
  return Theme.of(context).colorScheme.primary;
}

void _closeNavigationDrawerAfterSelection(
  BuildContext context,
  FluxNewsState appState, {
  bool force = false,
}) {
  if (force || !appState.isTablet) {
    Navigator.maybePop(context);
  }
}

void _resetListAfterNavigationSelection(FluxNewsState appState) {
  if (!Platform.isIOS) {
    appState.jumpToItem(0);
    return;
  }

  appState.resetListToStart(revealIOSLargeTitle: true);
}

class FluxNewsBodyStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Future<void> Function(Duration? inactiveDuration) onResume;
  final Widget child;
  const FluxNewsBodyStatefulWrapper(
      {super.key,
      required this.onInit,
      required this.onResume,
      required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsBodyStatefulWrapper>
    with
        AutomaticKeepAliveClientMixin<FluxNewsBodyStatefulWrapper>,
        WidgetsBindingObserver {
  Timer? _foregroundActiveTimer;
  DateTime? _foregroundInactiveAt;

  // init the state of FluxNewsBody to load the config and the data on startup
  @override
  void initState() {
    widget.onInit();
    WidgetsBinding.instance.addObserver(this);
    logThis(
        'FluxNewsBody',
        'Foreground heartbeat waits for lifecycle resume: '
            'initialLifecycleState=${WidgetsBinding.instance.lifecycleState}',
        LogLevel.INFO);
    super.initState();
  }

  @override
  void dispose() {
    _foregroundActiveTimer?.cancel();
    unawaited(markFluxNewsForegroundInactive());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundActiveHeartbeat();
      final inactiveDuration = _foregroundInactiveAt == null
          ? null
          : DateTime.now().difference(_foregroundInactiveAt!);
      _foregroundInactiveAt = null;
      unawaited(widget.onResume(inactiveDuration));
      FluxNewsWidgetService.handlePendingWidgetAction(
          context, context.read<FluxNewsState>());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _foregroundInactiveAt ??= DateTime.now();
      _foregroundActiveTimer?.cancel();
      _foregroundActiveTimer = null;
      unawaited(markFluxNewsForegroundInactive());
    }
  }

  void _startForegroundActiveHeartbeat() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      logThis(
          'FluxNewsBody',
          'Foreground heartbeat not started: '
              'lifecycleState=${WidgetsBinding.instance.lifecycleState}',
          LogLevel.INFO);
      return;
    }
    _foregroundActiveTimer?.cancel();
    unawaited(markFluxNewsForegroundActive());
    _foregroundActiveTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(markFluxNewsForegroundActive());
      } else {
        _foregroundActiveTimer?.cancel();
        _foregroundActiveTimer = null;
        unawaited(markFluxNewsForegroundInactive());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
