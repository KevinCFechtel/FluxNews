import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/logging.dart';
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

  void _aaLog(String message) {
    logThis('android_auto', message, LogLevel.INFO);
  }

  void _aaError(String message) {
    logThis('android_auto', message, LogLevel.ERROR);
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
    _aaLog('loadMediaItem start: id=${item.id}, title=${item.title}, initial=${initialPosition?.inSeconds ?? -1}');
    await _initFuture; // ensure AVAudioSession is configured before activating
    final shouldReload = _currentUrl != url;
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
      _aaLog('loadMediaItem source loaded: scheme=${uri.scheme}, shouldReload=true');
    } else {
      _aaLog('loadMediaItem source reused: shouldReload=false');
    }

    if (initialPosition != null) {
      await _player.seek(initialPosition);
    }

    final state = _buildPlaybackState();
    playbackState.add(state);
    _aaLog('loadMediaItem done: playing=${state.playing}, processing=${state.processingState.name}');
  }

  @override
  Future<void> play() async {
    _aaLog('play called');
    final session = await AudioSession.instance;
    await session.setActive(true);
    await _player.play();
    final state = _buildPlaybackState();
    playbackState.add(state);
    _aaLog('play done: playing=${state.playing}, processing=${state.processingState.name}');
  }

  @override
  Future<void> pause() async {
    _aaLog('pause called');
    await _player.pause();
    final state = _buildPlaybackState();
    playbackState.add(state);
    _aaLog('pause done: playing=${state.playing}, processing=${state.processingState.name}');
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    playbackState.add(_buildPlaybackState());
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    playbackState.add(_buildPlaybackState());
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    _aaLog('getChildren called: parent=$parentMediaId, options=${options?.keys.toList()}');
    if (parentMediaId == AudioService.recentRootId) {
      if (_currentMediaItem != null) {
        _aaLog('getChildren recentRoot -> currentMediaItem');
        return [_currentMediaItem!];
      }
      _aaLog('getChildren recentRoot -> queue count=${queue.value.length}');
      return queue.value;
    }

    if (_isRootId(parentMediaId)) {
      final items = <MediaItem>[];

      // Currently queued / playing items first
      if (queue.value.isNotEmpty) {
        items.addAll(queue.value);
      } else if (_currentMediaItem != null) {
        items.add(_currentMediaItem!);
      }

      _aaLog('getChildren root -> items=${items.length}');
      return items;
    }

    _aaLog('getChildren unknown parent -> empty list');
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    _aaLog('getMediaItem called: mediaId=$mediaId');
    if (_isRootId(mediaId)) {
      _aaLog('getMediaItem resolved as root');
      return const MediaItem(id: _rootMediaId, title: 'Flux News', playable: false);
    }

    if (_currentMediaItem?.id == mediaId) {
      _aaLog('getMediaItem matched currentMediaItem');
      return _currentMediaItem;
    }

    final matches = queue.value.where((item) => item.id == mediaId);
    if (matches.isNotEmpty) {
      _aaLog('getMediaItem matched queue');
      return matches.first;
    }

    _aaLog('getMediaItem not found');
    return null;
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    _aaLog('playFromMediaId called: mediaId=$mediaId, extras=${extras?.keys.toList()}');
    if (_isRootId(mediaId)) {
      if (_currentMediaItem != null) {
        await play();
        _aaLog('playFromMediaId root -> resumed current item');
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
        _aaLog('playFromMediaId fallback media item created for uri');
      }
    }

    if (target == null) {
      _aaError('playFromMediaId failed: target unresolved');
      return;
    }

    await loadMediaItem(
      url: target.id,
      item: target,
      initialPosition: Duration.zero,
    );
    await play();
    _aaLog('playFromMediaId done: target=${target.id}');
  }

  @override
  Future<void> prepareFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    _aaLog('prepareFromMediaId called: mediaId=$mediaId, extras=${extras?.keys.toList()}');
    if (_isRootId(mediaId)) {
      _aaLog('prepareFromMediaId root -> no-op');
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
      _aaError('prepareFromMediaId failed: target unresolved');
      return;
    }

    await loadMediaItem(
      url: target.id,
      item: target,
      initialPosition: Duration.zero,
    );
    _aaLog('prepareFromMediaId done: target=${target.id}');
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    _aaLog('playMediaItem called: id=${mediaItem.id}, title=${mediaItem.title}');
    await loadMediaItem(
      url: mediaItem.id,
      item: mediaItem,
      initialPosition: Duration.zero,
    );
    await play();
    _aaLog('playMediaItem done: id=${mediaItem.id}');
  }

  @override
  Future<void> stop() async {
    _aaLog('stop called');
    await _player.stop();
    _currentUrl = null; // force setAudioSource on next play of the same track
    playbackState.add(_buildPlaybackState().copyWith(processingState: AudioProcessingState.idle));
    _aaLog('stop done');
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
