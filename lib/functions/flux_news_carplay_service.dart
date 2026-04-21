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

    // Headless launch: the connected event may fire before Dart is listening.
    // After a short delay, attempt setup unconditionally — forceUpdateRootTemplate
    // is a no-op when the CarPlay interface controller is not connected.
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected) {
        _setupCarPlayTemplates();
      }
    });

    _downloadsChangedSubscription = AudioDownloadService.downloadedAudiosChangedStream.listen((_) {
      refreshIfConnected();
    });
  }

  final FlutterCarplay _carplay = FlutterCarplay();
  final FluxNewsAudioHandler _audioHandler;
  bool _isConnected = false;
  StreamSubscription<void>? _downloadsChangedSubscription;

  String _localizedEpisodesTitle() {
    final locale = ui.PlatformDispatcher.instance.locale;
    return lookupAppLocalizations(Locale(locale.languageCode)).fileList;
  }

  void _onConnectionStatusChanged(ConnectionStatusTypes status) {
    _isConnected = status == ConnectionStatusTypes.connected;
    if (_isConnected) {
      _setupCarPlayTemplates();
    }
  }

  Future<void> _setupCarPlayTemplates() async {
    final template = await _buildEpisodesTemplate();
    await FlutterCarplay.setRootTemplate(rootTemplate: template, animated: false);
    await _carplay.forceUpdateRootTemplate();
  }

  Future<CPListTemplate> _buildEpisodesTemplate() async {
    final downloads = await AudioDownloadService.getDownloadedAudios();
    await AudioDownloadService.loadTitlesForDownloads(downloads);
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
      items.add(
        CPListItem(
          text: title,
          detailText: feedTitle,
          onPress: (completer, item) async {
            await _audioHandler.playFromMediaId(capturedUri);
            FlutterCarplay.showSharedNowPlaying(animated: true);
            completer();
          },
        ),
      );
    }

    final section = CPListSection(
      header: _localizedEpisodesTitle(),
      items: items,
      sectionIndexEnabled: false,
    );

    return CPListTemplate(
      sections: [section],
      title: FluxNewsState.applicationName,
      systemIcon: 'music.note.list',
    );
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
    _carplay.removeListenerOnConnectionChange();
  }
}
