import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
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

    // Read persisted debug mode from Keychain so logging works correctly even
    // during headless CarPlay launch before FluxNewsState.readConfig() runs.
    _loadDebugMode();

    _debugLog('CarPlayService', 'Service init');

    // Wire up audio-handler-dependent listeners once the handler is ready.
    // We don't await here so CarPlay setup starts immediately without blocking
    // on AudioService.init().
    audioHandlerFuture.then((handler) {
      _debugLog('CarPlayService', 'AudioHandler ready — wiring up mediaItem listener');
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
      _debugLog('CarPlayService', 'Downloads changed — triggering refresh');
      refreshIfConnected();
    });

    _audioHandlerFuture = audioHandlerFuture;
  }

  static bool _debugMode = false;
  static final _secureStorage = sec_store.FlutterSecureStorage(
    iOptions: const sec_store.IOSOptions(
      accessibility: sec_store.KeychainAccessibility.first_unlock,
    ),
  );

  static void setDebugMode(bool value) {
    _debugMode = value;
  }

  static void _debugLog(String module, String message) {
    if (_debugMode) {
      logThis(module, message, LogLevel.INFO);
    }
  }

  static Future<void> _loadDebugMode() async {
    try {
      final value = await _secureStorage.read(key: FluxNewsState.secureStorageDebugModeKey);
      _debugMode = value == FluxNewsState.secureStorageTrueString;
    } catch (_) {
      // Keychain inaccessible during headless launch — default stays false
    }
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
    _debugLog('CarPlayService', 'Connection status changed → $status (_isConnected=$_isConnected)');
    if (status == ConnectionStatusTypes.background) {
      // Pre-build the template while the app is still in the background so it
      // is ready the moment the user focuses our app (connected event fires).
      // Do NOT reset _rootTemplate here — keep any existing template so that
      // the connected handler can force a clean rebuild with the new controller.
      _debugLog('CarPlayService', 'Background event — preloading template');
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
      _debugLog('CarPlayService', '_setupCarPlayTemplates skipped — setup already in progress, pendingRefresh set');
      _pendingRefresh = true;
      return;
    }
    _setupInProgress = true;
    _pendingRefresh = false;
    _debugLog('CarPlayService', '_setupCarPlayTemplates start — rootTemplate=${_rootTemplate == null ? "null (will setRoot)" : "exists (will update)"}');
    try {
      final sections = await _buildEpisodesSections();
      if (_rootTemplate == null) {
        final template = CPListTemplate(
          sections: sections,
          title: FluxNewsState.applicationName,
          systemIcon: 'music.note',
        );
        _rootTemplate = template;
        _debugLog('CarPlayService', 'Calling setRootTemplate');
        await FlutterCarplay.setRootTemplate(rootTemplate: template, animated: false);
        _debugLog('CarPlayService', 'setRootTemplate done — calling forceUpdateRootTemplate');
        await _carplay.forceUpdateRootTemplate();
        _debugLog('CarPlayService', 'forceUpdateRootTemplate done');
        // Explicitly push sections after setRootTemplate — flutter_carplay does
        // not always render sections from the constructor until this is called.
        _debugLog('CarPlayService', 'Calling updateListTemplateSections after setRoot');
        await _carplay.updateListTemplateSections(
          elementId: _rootTemplate!.uniqueId,
          sections: sections,
        );
        _debugLog('CarPlayService', 'updateListTemplateSections after setRoot done');
        // Second forceUpdate after a short delay — interfaceController may not
        // be fully ready on headless launch when the first call fires.
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isConnected) {
            _debugLog('CarPlayService', 'Delayed forceUpdateRootTemplate (500ms)');
            _carplay.forceUpdateRootTemplate().ignore();
          }
        });
      } else {
        _debugLog('CarPlayService', 'Calling updateListTemplateSections');
        await _carplay.updateListTemplateSections(
          elementId: _rootTemplate!.uniqueId,
          sections: sections,
        );
        _debugLog('CarPlayService', 'updateListTemplateSections done');
      }
    } catch (e) {
      logThis('CarPlayService', '_setupCarPlayTemplates error: $e', LogLevel.ERROR);
      // Reset so the next attempt re-tries setRootTemplate instead of
      // updateListTemplateSections on a template that was never accepted.
      _rootTemplate = null;
    } finally {
      _setupInProgress = false;
      if (_pendingRefresh) {
        _debugLog('CarPlayService', 'pendingRefresh — re-running setup');
        _pendingRefresh = false;
        _setupCarPlayTemplates();
      }
    }
  }

  Future<List<CPListSection>> _buildEpisodesSections() async {
    final downloads = await AudioDownloadService.getDownloadedAudios();
    _debugLog('CarPlayService', '_buildEpisodesSections: ${downloads.length} downloads — loading titles');
    await AudioDownloadService.loadTitlesForDownloads(downloads);
    final currentPlayingId = _audioHandler?.currentUrl;
    _debugLog('CarPlayService', '_buildEpisodesSections: titles loaded, currentPlayingId=$currentPlayingId');

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
          _debugLog('CarPlayService', 'Item pressed: $capturedUri');
          try {
            _debugLog('CarPlayService', 'Awaiting AudioHandler (timeout 15s)');
            final handler = await _audioHandlerFuture!
                .timeout(const Duration(seconds: 15));
            _debugLog('CarPlayService', 'AudioHandler ready — calling playFromMediaId');
            final newsID = capturedAttachmentID >= 0
                ? AudioDownloadService.getDownloadNewsId(capturedAttachmentID)
                : null;
            final extras = capturedAttachmentID >= 0
                ? <String, dynamic>{
                    'attachmentID': capturedAttachmentID,
                    if (newsID != null) 'newsID': newsID,
                    'downloaded': true,
                  }
                : null;
            await handler.playFromMediaId(capturedUri, extras)
                .timeout(const Duration(seconds: 15));
            _debugLog('CarPlayService', 'playFromMediaId done — showing NowPlaying');
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
