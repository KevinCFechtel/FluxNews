import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';

FluxNewsCarPlayService? _fluxNewsCarPlayService;

FluxNewsCarPlayService initFluxNewsCarPlayService(FluxNewsAudioHandler audioHandler) {
  _fluxNewsCarPlayService ??= FluxNewsCarPlayService._(audioHandler);
  return _fluxNewsCarPlayService!;
}

class FluxNewsCarPlayService {
  FluxNewsCarPlayService._(this._audioHandler) {
    if (!Platform.isIOS) return;
    _carplay.addListenerOnConnectionChange(_onConnectionStatusChanged);

    // If CarPlay is already connected when the app starts (e.g. launched in
    // background by the system), build templates immediately.
    if (FlutterCarplay.connectionStatus == ConnectionStatusTypes.connected.name) {
      _setupCarPlayTemplates();
    }
  }

  final FlutterCarplay _carplay = FlutterCarplay();
  final FluxNewsAudioHandler _audioHandler;
  bool _isConnected = false;

  String _localizedEpisodesTitle() {
    final languageCode = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return languageCode == 'de' ? 'Folgen' : 'Episodes';
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
  }

  Future<CPListTemplate> _buildEpisodesTemplate() async {
    final downloads = await AudioDownloadService.getDownloadedAudios();
    final items = <CPListItem>[];

    for (final download in downloads) {
      final fileUri = Uri.file(download.filePath).toString();
      final attachmentID = download.attachmentID;

      String title = download.fileName;
      String feedTitle = 'Flux News';

      if (attachmentID >= 0) {
        title = AudioDownloadService.getDownloadTitle(attachmentID) ?? download.fileName;
        feedTitle = AudioDownloadService.getDownloadFeedTitle(attachmentID) ?? 'Flux News';
      }

      final capturedUri = fileUri;
      items.add(
        CPListItem(
          text: title,
          detailText: feedTitle,
          accessoryType: CPListItemAccessoryType.disclosureIndicator,
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
    );

    return CPListTemplate(
      sections: [section],
      title: 'Flux News',
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
    _carplay.removeListenerOnConnectionChange();
  }
}
