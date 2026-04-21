import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

FluxNewsCarPlayService? _fluxNewsCarPlayService;

FluxNewsCarPlayService initFluxNewsCarPlayService(FluxNewsAudioHandler audioHandler) {
  _fluxNewsCarPlayService ??= FluxNewsCarPlayService._(audioHandler);
  return _fluxNewsCarPlayService!;
}

class FluxNewsCarPlayService {
  FluxNewsCarPlayService._(this._audioHandler) {
    if (!Platform.isIOS) return;
    _carplay.addListenerOnConnectionChange(_onConnectionStatusChanged);

    if (FlutterCarplay.connectionStatus == ConnectionStatusTypes.connected.name) {
      _setupCarPlayTemplates();
    }

    // Headless launch: the connected event fires before Dart's listener is ready,
    // and the CarPlay interface controller may not be available immediately.
    // Retry at increasing intervals until setup succeeds or CarPlay disconnects.
    _scheduleHeadlessRetry(const [2, 5, 10, 20]);

    _downloadsChangedSubscription = AudioDownloadService.downloadedAudiosChangedStream.listen((_) {
      refreshIfConnected();
    });

    _mediaItemSubscription = _audioHandler.mediaItem.listen((_) {
      _updateNowPlayingIndicator();
    });
  }

  final FlutterCarplay _carplay = FlutterCarplay();
  final FluxNewsAudioHandler _audioHandler;
  bool _isConnected = false;
  bool _headlessSetupDone = false;
  CPListTemplate? _rootTemplate;
  // fileUri → CPListItem; stable IDs allow setIsPlaying() to find items on the native side
  final Map<String, CPListItem> _episodeItems = {};
  StreamSubscription<void>? _downloadsChangedSubscription;
  StreamSubscription<dynamic>? _mediaItemSubscription;

  void _scheduleHeadlessRetry(List<int> remainingDelays) {
    if (remainingDelays.isEmpty) return;
    Future.delayed(Duration(seconds: remainingDelays.first), () async {
      if (_headlessSetupDone) return;
      final isConnected = _isConnected || FlutterCarplay.connectionStatus == ConnectionStatusTypes.connected.name;
      if (isConnected) {
        _isConnected = true;
        _rootTemplate = null;
        await _setupCarPlayTemplates();
        _headlessSetupDone = true;
      } else {
        _scheduleHeadlessRetry(remainingDelays.sublist(1));
      }
    });
  }

  String _localizedEpisodesTitle() {
    final locale = ui.PlatformDispatcher.instance.locale;
    return lookupAppLocalizations(Locale(locale.languageCode)).fileList;
  }

  void _onConnectionStatusChanged(ConnectionStatusTypes status) {
    _isConnected = status == ConnectionStatusTypes.connected;
    if (_isConnected) {
      _headlessSetupDone = true;
      // Reset so _setupCarPlayTemplates always uses setRootTemplate +
      // forceUpdateRootTemplate with the new interfaceController on reconnect.
      _rootTemplate = null;
      _setupCarPlayTemplates();
    }
  }

  Future<void> _setupCarPlayTemplates() async {
    final sections = await _buildEpisodesSections();
    if (_rootTemplate == null) {
      final template = CPListTemplate(
        sections: sections,
        title: FluxNewsState.applicationName,
        systemIcon: 'music.note',
      );
      _rootTemplate = template;
      await FlutterCarplay.setRootTemplate(rootTemplate: template, animated: false);
      await _carplay.forceUpdateRootTemplate();
    } else {
      await _carplay.updateListTemplateSections(
        elementId: _rootTemplate!.uniqueId,
        sections: sections,
      );
    }
  }

  Future<List<CPListSection>> _buildEpisodesSections() async {
    final downloads = await AudioDownloadService.getDownloadedAudios();
    await AudioDownloadService.loadTitlesForDownloads(downloads);
    final currentPlayingId = _audioHandler.currentUrl;

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
      final item = CPListItem(
        id: fileUri,
        text: title,
        detailText: feedTitle,
        isPlaying: fileUri == currentPlayingId,
        playingIndicatorLocation: CPListItemPlayingIndicatorLocation.leading,
        onPress: (completer, item) async {
          try {
            await _audioHandler.playFromMediaId(capturedUri);
            // Give the playback state time to propagate to CarPlay before
            // navigating — without this delay CarPlay may not show NowPlaying.
            //await Future.delayed(const Duration(milliseconds: 500));
            FlutterCarplay.showSharedNowPlaying(animated: true);
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
    final currentUrl = _audioHandler.currentUrl;
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
