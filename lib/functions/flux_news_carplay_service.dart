import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

FluxNewsCarPlayService? _fluxNewsCarPlayService;

FluxNewsCarPlayService initFluxNewsCarPlayService(Future<FluxNewsAudioHandler> audioHandlerFuture) {
  _fluxNewsCarPlayService ??= FluxNewsCarPlayService._(audioHandlerFuture);
  return _fluxNewsCarPlayService!;
}

class FluxNewsCarPlayService {
  FluxNewsCarPlayService._(Future<FluxNewsAudioHandler> audioHandlerFuture) {
    if (!Platform.isIOS) return;

    logThis('CarPlayService', 'Service init', LogLevel.INFO);

    // Wire up audio-handler-dependent listeners once the handler is ready.
    // We don't await here so CarPlay setup starts immediately without blocking
    // on AudioService.init().
    audioHandlerFuture.then((handler) {
      logThis('CarPlayService', 'AudioHandler ready — wiring up mediaItem listener', LogLevel.INFO);
      _audioHandler = handler;
      _mediaItemSubscription = handler.mediaItem.listen((_) {
        _updateNowPlayingIndicator();
      });
    }).onError((e, _) {
      logThis('CarPlayService', 'AudioHandler future failed: $e', LogLevel.ERROR);
    });

    _carplay.addListenerOnConnectionChange(_onConnectionStatusChanged);

    // Always attempt setup at init. In headless launch, templateApplicationScene
    // (_:didConnect:) fires before Dart's listener is registered, so the
    // "connected" event is lost — but interfaceController IS already set by iOS
    // at this point. forceUpdateRootTemplate() uses optional chaining
    // (interfaceController?.setRootTemplate), so it is a safe nil no-op when
    // CarPlay is not connected at all.
    _setupCarPlayTemplates();

    _downloadsChangedSubscription = AudioDownloadService.downloadedAudiosChangedStream.listen((_) {
      logThis('CarPlayService', 'Downloads changed — triggering refresh', LogLevel.INFO);
      refreshIfConnected();
    });

    _audioHandlerFuture = audioHandlerFuture;
  }

  final FlutterCarplay _carplay = FlutterCarplay();
  Future<FluxNewsAudioHandler>? _audioHandlerFuture;
  FluxNewsAudioHandler? _audioHandler;
  bool _isConnected = false;
  bool _setupInProgress = false;
  bool _pendingRefresh = false;
  CPListTemplate? _rootTemplate;
  // fileUri → CPListItem; stable IDs allow setIsPlaying() to find items on the native side
  final Map<String, CPListItem> _episodeItems = {};
  StreamSubscription<void>? _downloadsChangedSubscription;
  StreamSubscription<dynamic>? _mediaItemSubscription;

  String _localizedEpisodesTitle() {
    final locale = ui.PlatformDispatcher.instance.locale;
    return lookupAppLocalizations(Locale(locale.languageCode)).fileList;
  }

  void _onConnectionStatusChanged(ConnectionStatusTypes status) {
    _isConnected = status == ConnectionStatusTypes.connected;
    logThis('CarPlayService', 'Connection status changed → $status (_isConnected=$_isConnected)', LogLevel.INFO);
    if (status == ConnectionStatusTypes.background) {
      // Pre-build the template while the app is still in the background so it
      // is ready the moment the user focuses our app (connected event fires).
      // Do NOT reset _rootTemplate here — keep any existing template so that
      // the connected handler can force a clean rebuild with the new controller.
      logThis('CarPlayService', 'Background event — preloading template', LogLevel.INFO);
      _setupCarPlayTemplates();
    } else if (_isConnected) {
      // Reset so _setupCarPlayTemplates always uses setRootTemplate +
      // forceUpdateRootTemplate with the new interfaceController on reconnect.
      _rootTemplate = null;
      // Re-activate audio session — iOS may have suspended it during inactivity.
      AudioSession.instance.then((session) => session.setActive(true)).ignore();
      _setupCarPlayTemplates();
    }
  }

  Future<void> _setupCarPlayTemplates() async {
    if (_setupInProgress) {
      logThis('CarPlayService', '_setupCarPlayTemplates skipped — setup already in progress, pendingRefresh set', LogLevel.INFO);
      _pendingRefresh = true;
      return;
    }
    _setupInProgress = true;
    _pendingRefresh = false;
    logThis('CarPlayService', '_setupCarPlayTemplates start — rootTemplate=${_rootTemplate == null ? "null (will setRoot)" : "exists (will update)"}', LogLevel.INFO);
    try {
      final sections = await _buildEpisodesSections();
      if (_rootTemplate == null) {
        final template = CPListTemplate(
          sections: sections,
          title: FluxNewsState.applicationName,
          systemIcon: 'music.note',
        );
        _rootTemplate = template;
        logThis('CarPlayService', 'Calling setRootTemplate', LogLevel.INFO);
        await FlutterCarplay.setRootTemplate(rootTemplate: template, animated: false);
        logThis('CarPlayService', 'setRootTemplate done — calling forceUpdateRootTemplate', LogLevel.INFO);
        await _carplay.forceUpdateRootTemplate();
        logThis('CarPlayService', 'forceUpdateRootTemplate done', LogLevel.INFO);
        // Explicitly push sections after setRootTemplate — flutter_carplay does
        // not always render sections from the constructor until this is called.
        logThis('CarPlayService', 'Calling updateListTemplateSections after setRoot', LogLevel.INFO);
        await _carplay.updateListTemplateSections(
          elementId: _rootTemplate!.uniqueId,
          sections: sections,
        );
        logThis('CarPlayService', 'updateListTemplateSections after setRoot done', LogLevel.INFO);
        // Second forceUpdate after a short delay — interfaceController may not
        // be fully ready on headless launch when the first call fires.
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isConnected) {
            logThis('CarPlayService', 'Delayed forceUpdateRootTemplate (500ms)', LogLevel.INFO);
            _carplay.forceUpdateRootTemplate().ignore();
          }
        });
      } else {
        logThis('CarPlayService', 'Calling updateListTemplateSections', LogLevel.INFO);
        await _carplay.updateListTemplateSections(
          elementId: _rootTemplate!.uniqueId,
          sections: sections,
        );
        logThis('CarPlayService', 'updateListTemplateSections done', LogLevel.INFO);
      }
    } catch (e) {
      logThis('CarPlayService', '_setupCarPlayTemplates error: $e', LogLevel.ERROR);
      // Reset so the next attempt re-tries setRootTemplate instead of
      // updateListTemplateSections on a template that was never accepted.
      _rootTemplate = null;
    } finally {
      _setupInProgress = false;
      if (_pendingRefresh) {
        logThis('CarPlayService', 'pendingRefresh — re-running setup', LogLevel.INFO);
        _pendingRefresh = false;
        _setupCarPlayTemplates();
      }
    }
  }

  Future<List<CPListSection>> _buildEpisodesSections() async {
    final downloads = await AudioDownloadService.getDownloadedAudios();
    logThis('CarPlayService', '_buildEpisodesSections: ${downloads.length} downloads — loading titles', LogLevel.INFO);
    await AudioDownloadService.loadTitlesForDownloads(downloads);
    final currentPlayingId = _audioHandler?.currentUrl;
    logThis('CarPlayService', '_buildEpisodesSections: titles loaded, currentPlayingId=$currentPlayingId', LogLevel.INFO);

    // Rebuild item map with stable IDs derived from fileUri so that
    // setIsPlaying() can find the correct native CPListItem by elementId.
    _episodeItems.clear();
    final items = <CPListItem>[];

    for (final download in downloads) {
      final fileUri = Uri.file(download.filePath).toString();
      final attachmentID = download.attachmentID;

      String title = download.fileName;
      String feedTitle = FluxNewsState.applicationName;

      if (attachmentID >= 0) {
        title = AudioDownloadService.getDownloadTitle(attachmentID) ?? download.fileName;
        feedTitle = AudioDownloadService.getDownloadFeedTitle(attachmentID) ?? FluxNewsState.applicationName;
      }

      final capturedUri = fileUri;
      final capturedAttachmentID = attachmentID;
      final item = CPListItem(
        id: fileUri,
        text: title,
        detailText: feedTitle,
        isPlaying: fileUri == currentPlayingId,
        playingIndicatorLocation: CPListItemPlayingIndicatorLocation.leading,
        onPress: (completer, item) async {
          logThis('CarPlayService', 'Item pressed: $capturedUri', LogLevel.INFO);
          try {
            logThis('CarPlayService', 'Awaiting AudioHandler (timeout 15s)', LogLevel.INFO);
            final handler = await _audioHandlerFuture!
                .timeout(const Duration(seconds: 15));
            logThis('CarPlayService', 'AudioHandler ready — calling playFromMediaId', LogLevel.INFO);
            final extras = capturedAttachmentID >= 0
                ? <String, dynamic>{'attachmentID': capturedAttachmentID}
                : null;
            await handler.playFromMediaId(capturedUri, extras)
                .timeout(const Duration(seconds: 15));
            logThis('CarPlayService', 'playFromMediaId done — showing NowPlaying', LogLevel.INFO);
            FlutterCarplay.showSharedNowPlaying(animated: true);
          } catch (e) {
            logThis('CarPlayService', 'onPress error (timeout or playback failure): $e', LogLevel.ERROR);
          } finally {
            completer();
          }
        },
      );
      _episodeItems[fileUri] = item;
      items.add(item);
    }

    final section = CPListSection(
      header: _localizedEpisodesTitle(),
      items: items,
      sectionIndexEnabled: false,
    );

    return [section];
  }

  /// Updates only the isPlaying indicator on existing items without rebuilding
  /// the whole template. Requires stable item IDs (set via id: fileUri).
  void _updateNowPlayingIndicator() {
    if (!_isConnected || _episodeItems.isEmpty) return;
    final currentUrl = _audioHandler?.currentUrl;
    for (final entry in _episodeItems.entries) {
      entry.value.setIsPlaying(entry.key == currentUrl);
    }
  }

  /// Call this after a download completes or is deleted to refresh the CarPlay list.
  Future<void> refreshIfConnected() async {
    if (!Platform.isIOS) return;
    if (!_isConnected) return;
    await _setupCarPlayTemplates();
  }

  void dispose() {
    if (!Platform.isIOS) return;
    _downloadsChangedSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    _carplay.removeListenerOnConnectionChange();
  }
}
