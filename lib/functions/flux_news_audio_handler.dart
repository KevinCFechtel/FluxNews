import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:just_audio/just_audio.dart';

FluxNewsAudioHandler? _fluxNewsAudioHandler;
Future<FluxNewsAudioHandler>? _fluxNewsAudioHandlerFuture;

Future<FluxNewsAudioHandler> initFluxNewsAudioHandler() {
  if (_fluxNewsAudioHandler != null) {
    return Future.value(_fluxNewsAudioHandler!);
  }
  if (_fluxNewsAudioHandlerFuture != null) {
    return _fluxNewsAudioHandlerFuture!;
  }

  _fluxNewsAudioHandlerFuture = AudioService.init(
    builder: () => FluxNewsAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: FluxNewsState.androidNotificationChannelId,
      androidNotificationChannelName: FluxNewsState.androidNotificationChannelName,
      androidNotificationIcon: FluxNewsState.androidNotificationIcon,
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      fastForwardInterval: Duration(seconds: 30),
      rewindInterval: Duration(seconds: 30),
      androidBrowsableRootExtras: {
        'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 1,
        'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 1,
        'androidx.media.MediaBrowserServiceCompat.BrowserRoot.CONTENT_STYLE_BROWSABLE_HINT': 1,
        'androidx.media.MediaBrowserServiceCompat.BrowserRoot.CONTENT_STYLE_PLAYABLE_HINT': 1,
      },
    ),
  ).then((handler) {
    _fluxNewsAudioHandler = handler;
    return handler;
  });

  return _fluxNewsAudioHandlerFuture!;
}

class FluxNewsAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  FluxNewsAudioHandler() {
    _initFuture = _init();
  }

  static const String _rootMediaId = 'flux_news_root';
  static const String _downloadsMediaId = 'flux_news_downloads';
  final _storage = const sec_store.FlutterSecureStorage();
  final FluxNewsState _downloadQueryState = FluxNewsState();
  final Map<String, MediaItem> _downloadMediaItems = <String, MediaItem>{};
  DateTime? _lastPeriodicPersistAt;

  String _downloadsTitleLocalized() {
    final languageCode = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return languageCode == 'de' ? 'Folgen' : 'Episodes';
  }

  Future<Uri?> _extractId3Cover(String filePath) async {
    try {
      final imageBytes = await AudioDownloadService.extractAlbumArtFromFile(filePath);
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final coverCacheDir = await AudioDownloadService.getCoverCacheDir();
        final fileName = '${filePath.hashCode}_cover.jpg';
        final cacheFile = File('$coverCacheDir/$fileName');

        if (!await cacheFile.exists()) {
          await cacheFile.create(recursive: true);
          await cacheFile.writeAsBytes(imageBytes);
        }

        return Uri.file(cacheFile.path);
      }
    } catch (e) {
      // Silently ignore errors - will fall back to default artwork
    }
    return null;
  }

  bool _isRootId(String id) {
    return id == _rootMediaId ||
        id == AudioService.browsableRootId ||
        id == AudioService.recentRootId ||
        id == '' ||
        id == 'root';
  }

  final AudioPlayer _player = AudioPlayer();
  late final Future<void> _initFuture;

  MediaItem? _currentMediaItem;
  String? _currentUrl;

  Future<List<MediaItem>> _buildDownloadedMediaItems() async {
    final downloads = await AudioDownloadService.getDownloadedAudios();
    final defaultArtworkUri = await AudioDownloadService.getDefaultArtworkUri();
    final items = <MediaItem>[];
    final nextCache = <String, MediaItem>{};

    for (final download in downloads) {
      final fileUri = Uri.file(download.filePath).toString();
      final attachmentID = download.attachmentID;
      int? newsID;
      String? title;
      String? feedTitle;

      if (attachmentID >= 0) {
        title = AudioDownloadService.getDownloadTitle(attachmentID) ??
            await queryNewsTitleByAttachmentId(_downloadQueryState, attachmentID);
        feedTitle = AudioDownloadService.getDownloadFeedTitle(attachmentID) ??
            await queryFeedTitleByAttachmentId(_downloadQueryState, attachmentID);
        newsID = await queryNewsIdByAttachmentId(_downloadQueryState, attachmentID);
      }

      // Try to extract cover from ID3 tags, fall back to default
      final id3CoverUri = await _extractId3Cover(download.filePath);
      final artUri = id3CoverUri ?? defaultArtworkUri;

      final mediaItem = MediaItem(
        id: fileUri,
        title: title ?? download.fileName,
        artist: feedTitle ?? 'Flux News',
        album: feedTitle ?? 'Flux News',
        artUri: artUri,
        playable: true,
        extras: <String, dynamic>{
          if (attachmentID >= 0) 'attachmentID': attachmentID,
          if (newsID != null) 'newsID': newsID,
          'downloaded': true,
        },
      );

      nextCache[fileUri] = mediaItem;
      items.add(mediaItem);
    }

    _downloadMediaItems
      ..clear()
      ..addAll(nextCache);
    return items;
  }

  Future<Duration?> _resolveSavedPosition(MediaItem item, [Map<String, dynamic>? extras]) async {
    final mergedExtras = <String, dynamic>{
      if (item.extras != null) ...item.extras!,
      if (extras != null) ...extras,
    };

    final newsID = mergedExtras['newsID'];
    if (newsID is int) {
      final saved = await _storage.read(key: '${FluxNewsState.audioProgressKeyPrefix}$newsID');
      final localMs = saved != null ? int.tryParse(saved) ?? 0 : 0;
      if (localMs > 0) {
        return Duration(milliseconds: localMs);
      }
    }

    final attachmentID = mergedExtras['attachmentID'];
    if (attachmentID is int && attachmentID >= 0) {
      final news = await queryNewsByAttachmentId(_downloadQueryState, attachmentID);
      final attachment = news?.attachments
          ?.where((candidate) => candidate.attachmentID == attachmentID)
          .fold<Attachment?>(null, (previous, candidate) => previous ?? candidate);
      final mediaProgression = attachment?.mediaProgression ?? 0;
      if (mediaProgression > 0) {
        return Duration(seconds: mediaProgression);
      }
    }

    return null;
  }

  Future<void> _persistCurrentProgress({bool clear = false}) async {
    final item = _currentMediaItem;
    if (item == null) {
      return;
    }

    final extras = item.extras ?? const <String, dynamic>{};
    int? newsID = extras['newsID'] is int ? extras['newsID'] as int : null;
    final attachmentID = extras['attachmentID'] is int ? extras['attachmentID'] as int : null;

    if (newsID == null && attachmentID != null && attachmentID >= 0) {
      newsID = await queryNewsIdByAttachmentId(_downloadQueryState, attachmentID);
    }

    if (newsID == null) {
      return;
    }

    final progressKey = '${FluxNewsState.audioProgressKeyPrefix}$newsID';
    if (clear) {
      await _storage.delete(key: progressKey);
      return;
    }

    final positionMs = _player.position.inMilliseconds;
    if (positionMs <= 0) {
      return;
    }

    await _storage.write(key: progressKey, value: positionMs.toString());
    _lastPeriodicPersistAt = DateTime.now();
  }

  void _persistCurrentProgressPeriodically() {
    if (!_player.playing) {
      return;
    }

    final now = DateTime.now();
    if (_lastPeriodicPersistAt != null && now.difference(_lastPeriodicPersistAt!) < const Duration(seconds: 30)) {
      return;
    }

    _persistCurrentProgress();
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  PlayerState get playerState => _player.playerState;
  String? get currentUrl => _currentUrl;
  double get speed => _player.speed;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    _player.playbackEventStream.listen((event) {
      playbackState.add(_buildPlaybackState());
    });

    _player.positionStream.listen((pos) {
      // intentionally low-noise — uncomment if needed:
      playbackState.add(_buildPlaybackState());
      _persistCurrentProgressPeriodically();
    });

    _player.bufferedPositionStream.listen((_) {
      playbackState.add(_buildPlaybackState());
    });

    _player.durationStream.listen((duration) {
      if (_currentMediaItem != null && duration != null) {
        _currentMediaItem = _currentMediaItem!.copyWith(duration: duration);
        mediaItem.add(_currentMediaItem!);
      }
      playbackState.add(_buildPlaybackState());
    });
  }

  Future<void> loadMediaItem({
    required String url,
    required MediaItem item,
    Duration? initialPosition,
  }) async {
    await _initFuture; // ensure AVAudioSession is configured before activating
    final shouldReload = _currentUrl != url;

    if (shouldReload && _currentMediaItem != null) {
      await _persistCurrentProgress();
    }

    _currentUrl = url;
    final preparedItem = item.copyWith(
      playable: true,
    );
    _currentMediaItem = preparedItem;
    queue.add([preparedItem]);
    mediaItem.add(preparedItem);

    if (shouldReload) {
      final uri = Uri.parse(url);
      if (uri.scheme == 'file') {
        await _player.setAudioSource(AudioSource.file(uri.toFilePath()));
      } else {
        await _player.setAudioSource(AudioSource.uri(uri));
      }
    }

    if (initialPosition != null) {
      await _player.seek(initialPosition);
    }

    final state = _buildPlaybackState();
    playbackState.add(state);
  }

  @override
  Future<void> play() async {
    final session = await AudioSession.instance;
    await session.setActive(true);
    await _player.play();
    final state = _buildPlaybackState();
    playbackState.add(state);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    await _persistCurrentProgress();
    final state = _buildPlaybackState();
    playbackState.add(state);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    await _persistCurrentProgress();
    playbackState.add(_buildPlaybackState());
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    playbackState.add(_buildPlaybackState());
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.recentRootId) {
      if (_currentMediaItem != null) {
        return [_currentMediaItem!];
      }
      return queue.value;
    }

    if (parentMediaId == _downloadsMediaId) {
      return await _buildDownloadedMediaItems();
    }

    if (_isRootId(parentMediaId)) {
      final downloadsTitle = _downloadsTitleLocalized();
      final items = <MediaItem>[
        MediaItem(
          id: _downloadsMediaId,
          title: downloadsTitle,
          album: 'Flux News',
          playable: false,
        ),
      ];

      // Currently queued / playing items first
      if (queue.value.isNotEmpty) {
        items.addAll(queue.value);
      } else if (_currentMediaItem != null) {
        items.add(_currentMediaItem!);
      }

      return items;
    }

    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (_isRootId(mediaId)) {
      return const MediaItem(id: _rootMediaId, title: 'Flux News', playable: false);
    }

    if (mediaId == _downloadsMediaId) {
      return MediaItem(
        id: _downloadsMediaId,
        title: _downloadsTitleLocalized(),
        album: 'Flux News',
        playable: false,
      );
    }

    if (_currentMediaItem?.id == mediaId) {
      return _currentMediaItem;
    }

    if (_downloadMediaItems.containsKey(mediaId)) {
      return _downloadMediaItems[mediaId];
    }

    if (Uri.tryParse(mediaId)?.scheme == 'file') {
      await _buildDownloadedMediaItems();
      final cachedItem = _downloadMediaItems[mediaId];
      if (cachedItem != null) {
        return cachedItem;
      }
    }

    final matches = queue.value.where((item) => item.id == mediaId);
    if (matches.isNotEmpty) {
      return matches.first;
    }

    return null;
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    if (_isRootId(mediaId)) {
      if (_currentMediaItem != null) {
        await play();
      }
      return;
    }

    MediaItem? target = mediaId == _currentMediaItem?.id
        ? _currentMediaItem
        : queue.value.where((item) => item.id == mediaId).fold<MediaItem?>(null, (prev, e) => prev ?? e);

    target ??= await getMediaItem(mediaId);

    // Check if it's a download (file:// URI)
    if (target == null) {
      final uri = Uri.tryParse(mediaId);
      if (uri != null && uri.scheme == 'file') {
        final title = uri.pathSegments.isNotEmpty ? Uri.decodeComponent(uri.pathSegments.last) : mediaId;
        target = MediaItem(
          id: mediaId,
          title: title,
          album: 'Flux News',
          playable: true,
          extras: extras,
        );
      }
    }

    if (target == null) {
      final uri = Uri.tryParse(mediaId);
      if (uri != null && uri.hasScheme) {
        final fallbackTitle = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : mediaId;
        target = MediaItem(
          id: mediaId,
          album: 'Flux News',
          title: fallbackTitle,
          playable: true,
        );
      }
    }

    if (target == null) {
      return;
    }

    final initialPosition = await _resolveSavedPosition(target, extras);

    await loadMediaItem(
      url: target.id,
      item: target,
      initialPosition: initialPosition,
    );
    await play();
  }

  @override
  Future<void> prepareFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    if (_isRootId(mediaId)) {
      return;
    }

    MediaItem? target = await getMediaItem(mediaId);
    target ??= await getMediaItem(Uri.decodeFull(mediaId));

    if (target == null) {
      final uri = Uri.tryParse(mediaId);
      if (uri != null && uri.hasScheme) {
        final fallbackTitle = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : mediaId;
        target = MediaItem(
          id: mediaId,
          album: 'Flux News',
          title: fallbackTitle,
          playable: true,
          extras: extras,
        );
      }
    }

    if (target == null) {
      return;
    }

    final initialPosition = await _resolveSavedPosition(target, extras);

    await loadMediaItem(
      url: target.id,
      item: target,
      initialPosition: initialPosition,
    );
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    await loadMediaItem(
      url: mediaItem.id,
      item: mediaItem,
      initialPosition: Duration.zero,
    );
    await play();
  }

  @override
  Future<void> stop() async {
    await _persistCurrentProgress();
    await _player.stop();
    _currentUrl = null; // force setAudioSource on next play of the same track
    playbackState.add(_buildPlaybackState().copyWith(processingState: AudioProcessingState.idle));
  }

  @override
  Future<void> fastForward() async {
    await seek(_player.position + const Duration(seconds: 30));
  }

  @override
  Future<void> skipToNext() async {
    await fastForward();
  }

  @override
  Future<void> rewind() async {
    final target = _player.position - const Duration(seconds: 30);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> skipToPrevious() async {
    await rewind();
  }

  PlaybackState _buildPlaybackState() {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: queue.value.isNotEmpty ? 0 : null,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
