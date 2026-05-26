import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as sec_store;
import 'package:flux_news/functions/audio_progress_store.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/dynamic_island_service.dart';
import 'package:flux_news/functions/logging.dart';
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
      androidNotificationChannelName:
          FluxNewsState.androidNotificationChannelName,
      androidNotificationIcon: FluxNewsState.androidNotificationIcon,
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      fastForwardInterval: Duration(seconds: 30),
      rewindInterval: Duration(seconds: 30),
      androidBrowsableRootExtras: {
        'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 1,
        'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 1,
        'androidx.media.MediaBrowserServiceCompat.BrowserRoot.CONTENT_STYLE_BROWSABLE_HINT':
            1,
        'androidx.media.MediaBrowserServiceCompat.BrowserRoot.CONTENT_STYLE_PLAYABLE_HINT':
            1,
      },
      // iOS/CarPlay support
      preloadArtwork: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  ).then((handler) {
    _fluxNewsAudioHandler = handler;
    return handler;
  });

  return _fluxNewsAudioHandlerFuture!;
}

enum SleepTimerEvent { stateChanged, fired }

class FluxNewsAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  FluxNewsAudioHandler() {
    _initFuture = _init();
    _loadDebugMode();
  }

  static bool _debugMode = false;
  static final _debugStorage = sec_store.FlutterSecureStorage(
    iOptions: const sec_store.IOSOptions(
      accessibility: sec_store.KeychainAccessibility.first_unlock,
    ),
  );

  static void setDebugMode(bool value) => _debugMode = value;

  static void _debugLog(String message) {
    if (_debugMode) logThis('AudioHandler', message, LogLevel.INFO);
  }

  static Future<void> _loadDebugMode() async {
    try {
      final value = await _debugStorage.read(
          key: FluxNewsState.secureStorageDebugModeKey);
      _debugMode = value == FluxNewsState.secureStorageTrueString;
    } catch (_) {}
  }

  static const String _rootMediaId = 'flux_news_root';
  static const String _downloadsMediaId = 'flux_news_downloads';
  final _storage = sec_store.FlutterSecureStorage(
    iOptions: const sec_store.IOSOptions(
      accessibility: sec_store.KeychainAccessibility.first_unlock,
    ),
  );
  final FluxNewsState _downloadQueryState = FluxNewsState();
  final Map<String, MediaItem> _downloadMediaItems = <String, MediaItem>{};
  DateTime? _lastPeriodicPersistAt;
  final DynamicIslandService _dynamicIslandService = DynamicIslandService();
  Timer? _sleepTimer;
  bool _sleepTimerEnabled = false;
  DateTime? _sleepTimerEndAt;
  int _sleepTimerMinutes = 30;
  final StreamController<SleepTimerEvent> _sleepTimerController =
      StreamController<SleepTimerEvent>.broadcast();

  String _downloadsTitleLocalized() {
    final languageCode =
        ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return languageCode == 'de' ? 'Folgen' : 'Episodes';
  }

  MediaItem _forBrowseList(MediaItem item) {
    return MediaItem(
      id: item.id,
      album: item.album,
      title: item.title,
      artist: item.artist,
      genre: item.genre,
      duration: item.duration,
      playable: item.playable,
      displayTitle: item.displayTitle,
      displaySubtitle: item.displaySubtitle,
      displayDescription: item.displayDescription,
      rating: item.rating,
      extras: item.extras,
    );
  }

  List<MediaItem> _forBrowseListItems(List<MediaItem> items) {
    return items.map(_forBrowseList).toList(growable: false);
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
  ProcessingState _lastProcessingState = ProcessingState.idle;
  bool _isHandlingCompletion = false;
  double? _volumeBeforeDucking;

  Future<int?> _resolveCurrentAttachmentId() async {
    final item = _currentMediaItem;
    final extras = item?.extras;
    final attachmentID = extras?['attachmentID'];
    if (attachmentID is int) {
      return attachmentID;
    }

    final mediaId = item?.id ?? _currentUrl;
    final uri = mediaId == null ? null : Uri.tryParse(mediaId);
    if (uri == null || uri.scheme != 'file') {
      return null;
    }

    final filePath = uri.toFilePath();
    final downloads = await AudioDownloadService.getDownloadedAudios();
    final matched = downloads
        .where((download) => download.filePath == filePath)
        .fold<DownloadedAudioInfo?>(
          null,
          (previous, download) => previous ?? download,
        );

    return matched?.attachmentID;
  }

  Future<void> _handleCompletedPlayback() async {
    cancelSleepTimer();
    await _persistCurrentProgress(clear: true, syncToServer: true);

    String? deleteAfterPlaybackValue;
    try {
      deleteAfterPlaybackValue = await _storage.read(
          key: FluxNewsState.secureStorageDeleteAudioAfterPlaybackKey);
    } catch (_) {
      // Keychain inaccessible (screen locked, pre-migration WhenUnlocked item) — skip delete.
    }
    final shouldDeleteAfterPlayback =
        deleteAfterPlaybackValue == FluxNewsState.secureStorageTrueString;
    if (!shouldDeleteAfterPlayback) {
      return;
    }

    final attachmentID = await _resolveCurrentAttachmentId();
    if (attachmentID == null) {
      return;
    }

    await AudioDownloadService.deleteDownloadedAudio(attachmentID);
  }

  Future<List<MediaItem>> _buildDownloadedMediaItems() async {
    final downloads = await AudioDownloadService.getDownloadedAudios();
    final defaultArtworkUri = await AudioDownloadService.getDefaultArtworkUri();
    final defaultArtworkFilePath =
        await AudioDownloadService.getDefaultArtworkFilePath();
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
            await queryNewsTitleByAttachmentId(
                _downloadQueryState, attachmentID);
        feedTitle = AudioDownloadService.getDownloadFeedTitle(attachmentID) ??
            await queryFeedTitleByAttachmentId(
                _downloadQueryState, attachmentID);
        newsID =
            await queryNewsIdByAttachmentId(_downloadQueryState, attachmentID);
      }

      Uri? artUri;
      String? artCacheFile;
      if (attachmentID >= 0) {
        artUri = await AudioDownloadService.getCachedArtworkUriForAttachment(
            attachmentID);
        artCacheFile =
            await AudioDownloadService.getCachedArtworkFilePathForAttachment(
                attachmentID);
      }
      artUri ??= defaultArtworkUri;
      artCacheFile ??= defaultArtworkFilePath;

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
          if (artCacheFile != null) 'artCacheFile': artCacheFile,
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

  Future<Duration?> _resolveSavedPosition(MediaItem item,
      [Map<String, dynamic>? extras]) async {
    final mergedExtras = <String, dynamic>{
      if (item.extras != null) ...item.extras!,
      if (extras != null) ...extras,
    };

    // --- Local position from Keychain (milliseconds) ---
    int localMs = 0;
    bool wasReset = false;
    final newsID = mergedExtras['newsID'];
    if (newsID is int) {
      try {
        final saved = await AudioProgressStore.read(
            AudioProgressStore.keyForNews(newsID));
        localMs = saved != null ? int.tryParse(saved) ?? 0 : 0;
        // "0" written explicitly means the episode was completed or re-downloaded
        // and should start from the beginning. Distinguish from null (never played
        // locally) where the server position is the correct resume point.
        wasReset = saved != null && localMs == 0;
      } catch (_) {
        // Keychain may be inaccessible (e.g. -25308 for items written before
        // first_unlock migration while screen is locked) — start from beginning.
      }
    }

    if (wasReset) return null;

    // --- Server/cache position (seconds → milliseconds) ---
    // Check the in-memory cache first — populated by loadTitlesForDownloads
    // during CarPlay/Android Auto template setup. This avoids a DB query on
    // the CarPlay audio-grant hot path, which can delay play() long enough
    // for the session grant to expire (!int error).
    int serverMs = 0;
    final attachmentID = mergedExtras['attachmentID'];
    if (attachmentID is int && attachmentID >= 0) {
      final cached =
          AudioDownloadService.getDownloadMediaProgression(attachmentID);
      if (cached != null && cached > 0) {
        serverMs = cached * 1000;
      } else {
        // Cache miss (first access before template setup) — fall back to DB.
        final news =
            await queryNewsByAttachmentId(_downloadQueryState, attachmentID);
        final attachment = news?.attachments
            ?.where((candidate) => candidate.attachmentID == attachmentID)
            .fold<Attachment?>(
                null, (previous, candidate) => previous ?? candidate);
        final mediaProgression = attachment?.mediaProgression ?? 0;
        if (mediaProgression > 0) {
          serverMs = mediaProgression * 1000;
        }
      }
    }

    // Use whichever position is further ahead.
    if (serverMs > localMs) {
      // Server is ahead — write to Keychain so it persists across restarts.
      if (newsID is int) {
        try {
          await AudioProgressStore.write(
              AudioProgressStore.keyForNews(newsID), serverMs.toString());
        } catch (_) {}
      }
      return Duration(milliseconds: serverMs);
    }
    if (localMs > 0) {
      // Local Keychain is ahead (e.g. app was terminated before the last
      // _syncProgressionToServer could complete). Upload to server now so
      // other devices and future syncs see the correct position.
      if (attachmentID is int && attachmentID >= 0) {
        _syncProgressionToServer(attachmentID, localMs ~/ 1000).ignore();
      }
      return Duration(milliseconds: localMs);
    }
    return null;
  }

  Future<void> _persistCurrentProgress(
      {bool clear = false, bool syncToServer = false}) async {
    final item = _currentMediaItem;
    if (item == null) {
      return;
    }

    final extras = item.extras ?? const <String, dynamic>{};
    int? newsID = extras['newsID'] is int ? extras['newsID'] as int : null;
    final attachmentID =
        extras['attachmentID'] is int ? extras['attachmentID'] as int : null;

    if (newsID == null && attachmentID != null && attachmentID >= 0) {
      newsID =
          await queryNewsIdByAttachmentId(_downloadQueryState, attachmentID);
    }

    if (newsID == null) {
      return;
    }

    final progressKey = AudioProgressStore.keyForNews(newsID);
    if (clear) {
      // Write "0" instead of deleting so _loadProgress can distinguish between
      // "never played locally" (null) and "completed/reset" (0).
      await AudioProgressStore.write(progressKey, '0');
      if (syncToServer && attachmentID != null && attachmentID >= 0) {
        _syncProgressionToServer(attachmentID, 0).ignore();
      }
      return;
    }

    final positionMs = _player.position.inMilliseconds;
    if (positionMs <= 0) {
      return;
    }

    await AudioProgressStore.write(progressKey, positionMs.toString());
    _lastPeriodicPersistAt = DateTime.now();

    if (syncToServer && attachmentID != null && attachmentID >= 0) {
      _syncProgressionToServer(attachmentID, positionMs ~/ 1000).ignore();
    }
  }

  /// Sends the current playback position to the Miniflux server via
  /// PUT /v1/enclosures/{id}. Requires Miniflux >= 2.2.0.
  /// Errors are swallowed so a network failure never disrupts playback.
  Future<void> _syncProgressionToServer(
      int attachmentID, int positionSeconds) async {
    try {
      final url =
          await _storage.read(key: FluxNewsState.secureStorageMinifluxURLKey);
      final apiKey =
          await _storage.read(key: FluxNewsState.secureStorageMinifluxAPIKey);
      final version = await _storage.read(
          key: FluxNewsState.secureStorageMinifluxVersionKey);
      if (url == null || url.isEmpty || apiKey == null || apiKey.isEmpty) {
        return;
      }
      if (!_isAtLeastMiniflux220(version)) return;

      final Client client;
      if (Platform.isAndroid) {
        final engine = CronetEngine.build(
            cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
        client = CronetClient.fromCronetEngine(engine, closeEngine: true);
      } else {
        client = IOClient(HttpClient());
      }
      try {
        await client.put(
          Uri.parse('${url}enclosures/$attachmentID'),
          headers: {
            FluxNewsState.httpMinifluxAuthHeaderString: apiKey,
            FluxNewsState.httpMinifluxAcceptHeaderString:
                FluxNewsState.httpContentTypeString,
            FluxNewsState.httpMinifluxContentTypeHeaderString:
                FluxNewsState.httpContentTypeString,
          },
          body: jsonEncode({'media_progression': positionSeconds}),
        );
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  bool _isAtLeastMiniflux220(String? v) {
    if (v == null || v.trim().isEmpty) return false;
    final p = RegExp(r'\d+')
        .allMatches(v)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    if (p.isEmpty) return false;
    final major = p[0];
    final minor = p.length > 1 ? p[1] : 0;
    return major > 2 || (major == 2 && minor >= 2);
  }

  void _persistCurrentProgressPeriodically() {
    if (!_player.playing) {
      return;
    }

    final now = DateTime.now();
    if (_lastPeriodicPersistAt != null &&
        now.difference(_lastPeriodicPersistAt!) < const Duration(seconds: 30)) {
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

  bool get sleepTimerEnabled => _sleepTimerEnabled;
  DateTime? get sleepTimerEndAt => _sleepTimerEndAt;
  int get sleepTimerMinutes => _sleepTimerMinutes;
  Stream<SleepTimerEvent> get sleepTimerStream => _sleepTimerController.stream;

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimerMinutes = minutes;
    _sleepTimerEnabled = true;
    _sleepTimerEndAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimerController.add(SleepTimerEvent.stateChanged);
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      if (_player.playing) {
        await pause();
      }
      _sleepTimerEnabled = false;
      _sleepTimerEndAt = null;
      _sleepTimerController.add(SleepTimerEvent.fired);
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEnabled = false;
    _sleepTimerEndAt = null;
    _sleepTimerController.add(SleepTimerEvent.stateChanged);
  }

  void updateSleepTimerMinutes(int minutes) {
    _sleepTimerMinutes = minutes;
    if (_sleepTimerEnabled) {
      startSleepTimer(minutes);
    } else {
      _sleepTimerController.add(SleepTimerEvent.stateChanged);
    }
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    // longFormAudio is required for CarPlay audio routing (routes to car
    // speakers) and keeps the app as the "Now Playing" owner so Dynamic Island
    // and Lock Screen controls continue to work. mixWithOthers would fix the
    // !int error but silently breaks Dynamic Island by demoting the app from
    // primary audio owner.
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.longFormAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    // Do not request Android audio focus during handler initialization. Android
    // Auto can create/browse the service without immediate playback; claiming
    // focus here can leave the car route in a stale state. Playback activates
    // the session explicitly in play().
    if (Platform.isIOS) {
      // setActive may still fail with !int if a non-interruptible source is
      // active at startup. just_audio activates the session internally via
      // AVPlayer, so we ignore the error to keep _initFuture successful.
      try {
        await session.setActive(true);
      } catch (e) {
        _debugLog('AudioSession.setActive during init failed: $e');
      }
    }

    session.interruptionEventStream.listen((event) {
      _handleAudioInterruption(event).ignore();
    });

    session.becomingNoisyEventStream.listen((_) {
      _handleBecomingNoisy().ignore();
    });

    _player.playerStateStream.listen((state) {
      _debugLog(
          'PlayerState: playing=${state.playing} processing=${state.processingState}');
      final isCompleted = state.processingState == ProcessingState.completed;
      final enteredCompletedState =
          isCompleted && _lastProcessingState != ProcessingState.completed;

      if (enteredCompletedState && !_isHandlingCompletion) {
        _isHandlingCompletion = true;
        _handleCompletedPlayback().whenComplete(() {
          _isHandlingCompletion = false;
        }).ignore();
      }

      if (!isCompleted) {
        _isHandlingCompletion = false;
      }

      _lastProcessingState = state.processingState;
    });

    _player.playbackEventStream.listen((event) {
      playbackState.add(_buildPlaybackState());
      _updateDynamicIsland();
    });

    _player.positionStream.listen((pos) {
      // intentionally low-noise — uncomment if needed:
      playbackState.add(_buildPlaybackState());
      _persistCurrentProgressPeriodically();
      _updateDynamicIsland();
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
      _updateDynamicIsland();
    });
  }

  Future<void> _handleAudioInterruption(AudioInterruptionEvent event) async {
    _debugLog(
        'Audio interruption: begin=${event.begin} type=${event.type} playing=${_player.playing}');
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (_volumeBeforeDucking == null) {
            _volumeBeforeDucking = _player.volume;
            await _player.setVolume(0.25);
          }
          playbackState.add(_buildPlaybackState());
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (_player.playing) {
            await pause();
          }
          break;
      }
      return;
    }

    if (event.type == AudioInterruptionType.duck) {
      final volume = _volumeBeforeDucking;
      _volumeBeforeDucking = null;
      if (volume != null) {
        await _player.setVolume(volume);
        playbackState.add(_buildPlaybackState());
      }
    }
  }

  Future<void> _handleBecomingNoisy() async {
    _debugLog('Audio becoming noisy event: playing=${_player.playing}');
    if (_player.playing) {
      await pause();
    }
  }

  Future<void> loadMediaItem({
    required String url,
    required MediaItem item,
    Duration? initialPosition,
  }) async {
    await _initFuture; // ensure AVAudioSession is configured before activating
    final shouldReload = _currentUrl != url;
    _debugLog(
        'loadMediaItem start: title=${item.title} shouldReload=$shouldReload initialPosition=$initialPosition url=$url');

    if (shouldReload && _currentMediaItem != null) {
      await _persistCurrentProgress(syncToServer: true);
    }

    _currentUrl = url;

    // Resolve artwork. For downloaded media items, artUri and artCacheFile are
    // already set by _buildDownloadedMediaItems() — skip the expensive async
    // lookups in that case. Only fall back to the default when artUri is absent
    // (e.g. streaming items built without pre-resolved artwork).
    final artCacheFileAlreadySet =
        item.extras?.containsKey('artCacheFile') == true;
    final Uri? fallbackArtworkUri;
    if (item.artUri != null) {
      fallbackArtworkUri = item.artUri;
    } else {
      fallbackArtworkUri = await AudioDownloadService.getDefaultArtworkUri();
    }

    final String? defaultArtworkFilePath;
    if (artCacheFileAlreadySet) {
      defaultArtworkFilePath =
          null; // already in item.extras, no extra lookup needed
    } else {
      defaultArtworkFilePath =
          await AudioDownloadService.getDefaultArtworkFilePath();
    }

    final preparedExtras = <String, dynamic>{
      if (item.extras != null) ...item.extras!,
      if (defaultArtworkFilePath != null)
        'artCacheFile': defaultArtworkFilePath,
    };

    final preparedItem = item.copyWith(
      playable: true,
      artUri: fallbackArtworkUri,
      extras: preparedExtras,
    );
    _currentMediaItem = preparedItem;
    queue.add([preparedItem]);
    mediaItem.add(preparedItem);

    if (shouldReload) {
      final uri = Uri.parse(url);
      if (uri.scheme == 'file') {
        _debugLog('loadMediaItem setAudioSource file');
        await _player.setAudioSource(AudioSource.file(uri.toFilePath()));
      } else {
        _debugLog('loadMediaItem setAudioSource uri');
        await _player.setAudioSource(AudioSource.uri(uri));
      }
    } else if (_player.processingState == ProcessingState.completed) {
      // Same audio source but player already completed — seek to the beginning
      // so a subsequent play() starts from 0 instead of replaying from the end.
      await _player.seek(Duration.zero);
    }

    if (initialPosition != null) {
      await _player.seek(initialPosition);
    }

    final state = _buildPlaybackState();
    playbackState.add(state);
    _debugLog(
        'loadMediaItem done: processing=${_player.processingState} duration=${_player.duration}');
  }

  @override
  Future<void> play() async {
    await _initFuture;
    _debugLog(
        'play requested: item=${_currentMediaItem?.title} processing=${_player.processingState} playing=${_player.playing}');
    await _activateAudioSessionForPlayback();
    // just_audio's play() completes when playback STOPS, not when it starts.
    // Awaiting it would block the entire call chain until the episode ends.
    _player.play().ignore();
    if (Platform.isAndroid) {
      await _verifyAndroidPlaybackStarted();
    }
    final state = _buildPlaybackState();
    playbackState.add(state);
    _startDynamicIsland();
    _debugLog(
        'play dispatched: processing=${_player.processingState} playing=${_player.playing}');
  }

  Future<void> _activateAudioSessionForPlayback() async {
    final session = await AudioSession.instance;
    try {
      await session.setActive(true);
      return;
    } catch (e) {
      if (Platform.isAndroid) {
        logThis(
            'AudioHandler',
            'AudioSession.setActive during play failed, retrying: $e',
            LogLevel.WARNING);
        await Future.delayed(const Duration(milliseconds: 250));
        try {
          await session.setActive(true);
          return;
        } catch (retryError) {
          logThis(
              'AudioHandler',
              'AudioSession.setActive retry during play failed: $retryError',
              LogLevel.WARNING);
          return;
        }
      }
      _debugLog('AudioSession.setActive during play failed: $e');
    }
  }

  Future<void> _verifyAndroidPlaybackStarted() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (_player.playing && _player.processingState != ProcessingState.idle) {
      return;
    }

    logThis(
        'AudioHandler',
        'Android playback did not start after play dispatch: '
            'playing=${_player.playing} '
            'processing=${_player.processingState} '
            'item=${_currentMediaItem?.title}',
        LogLevel.WARNING);
    await _activateAudioSessionForPlayback();
    _player.play().ignore();
  }

  @override
  Future<void> pause() async {
    _debugLog(
        'pause requested: item=${_currentMediaItem?.title} processing=${_player.processingState} playing=${_player.playing}');
    await _player.pause();
    await _persistCurrentProgress(syncToServer: true);
    final state = _buildPlaybackState();
    playbackState.add(state);
    _updateDynamicIsland();
    _debugLog(
        'pause done: processing=${_player.processingState} playing=${_player.playing}');
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
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.recentRootId) {
      if (_currentMediaItem != null) {
        return [_forBrowseList(_currentMediaItem!)];
      }
      return _forBrowseListItems(queue.value);
    }

    if (parentMediaId == _downloadsMediaId) {
      final items = await _buildDownloadedMediaItems();
      return _forBrowseListItems(items);
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

      if (Platform.isIOS) {
        final downloadedItems = await _buildDownloadedMediaItems();
        items.addAll(_forBrowseListItems(downloadedItems));
      }

      // Currently queued / playing items first
      if (queue.value.isNotEmpty) {
        items.addAll(_forBrowseListItems(queue.value));
      } else if (_currentMediaItem != null) {
        items.add(_forBrowseList(_currentMediaItem!));
      }

      return items;
    }

    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (_isRootId(mediaId)) {
      return const MediaItem(
          id: _rootMediaId, title: 'Flux News', playable: false);
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
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    _debugLog('playFromMediaId start — mediaId=$mediaId extras=$extras');

    if (_isRootId(mediaId)) {
      if (_currentMediaItem != null) {
        _debugLog('playFromMediaId — root id, resuming current item');
        await play();
      }
      return;
    }

    MediaItem? target = mediaId == _currentMediaItem?.id
        ? _currentMediaItem
        : queue.value
            .where((item) => item.id == mediaId)
            .fold<MediaItem?>(null, (prev, e) => prev ?? e);

    if (target != null) {
      _debugLog(
          'playFromMediaId — target found in current/queue: ${target.title}');
    } else {
      _debugLog('playFromMediaId — target not in cache, calling getMediaItem');
      target = await getMediaItem(mediaId);
      _debugLog(
          'playFromMediaId — getMediaItem returned: ${target?.title ?? "null"}');
    }

    // Check if it's a download (file:// URI)
    if (target == null) {
      final uri = Uri.tryParse(mediaId);
      if (uri != null && uri.scheme == 'file') {
        final title = uri.pathSegments.isNotEmpty
            ? Uri.decodeComponent(uri.pathSegments.last)
            : mediaId;
        _debugLog(
            'playFromMediaId — building fallback MediaItem for file:// URI');
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
        final fallbackTitle =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.last : mediaId;
        _debugLog('playFromMediaId — building generic fallback MediaItem');
        target = MediaItem(
          id: mediaId,
          album: 'Flux News',
          title: fallbackTitle,
          playable: true,
        );
      }
    }

    if (target == null) {
      _debugLog('playFromMediaId — no target resolved, aborting');
      return;
    }

    _debugLog(
        'playFromMediaId — resolving saved position for: ${target.title}');
    final initialPosition = await _resolveSavedPosition(target, extras);
    _debugLog(
        'playFromMediaId — initialPosition=$initialPosition, calling loadMediaItem');

    await loadMediaItem(
      url: target.id,
      item: target,
      initialPosition: initialPosition,
    );
    _debugLog('playFromMediaId — loadMediaItem done, calling play()');
    await play();
    _debugLog('playFromMediaId — play() done');
  }

  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    if (_isRootId(mediaId)) {
      return;
    }

    MediaItem? target = await getMediaItem(mediaId);
    target ??= await getMediaItem(Uri.decodeFull(mediaId));

    if (target == null) {
      final uri = Uri.tryParse(mediaId);
      if (uri != null && uri.hasScheme) {
        final fallbackTitle =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.last : mediaId;
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
    cancelSleepTimer();
    await _persistCurrentProgress();
    await _player.stop();
    _currentUrl = null; // force setAudioSource on next play of the same track
    playbackState.add(_buildPlaybackState()
        .copyWith(processingState: AudioProcessingState.idle));
    await _endDynamicIsland();
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

  Future<void> _startDynamicIsland() async {
    if (!Platform.isIOS) return;

    final item = _currentMediaItem;
    if (item == null) return;

    final defaultArtworkUri = await AudioDownloadService.getDefaultArtworkUri();
    final artworkUri = item.artUri ?? defaultArtworkUri;

    await _dynamicIslandService.startActivity(
      itemTitle: item.title,
      feedTitle: item.artist ?? 'Flux News',
      isPlaying: _player.playing,
      currentPosition: _player.position.inSeconds,
      duration: _player.duration?.inSeconds ?? 0,
      artworkUrl: artworkUri?.toString(),
    );
  }

  Future<void> _updateDynamicIsland() async {
    if (!Platform.isIOS) return;

    final item = _currentMediaItem;
    if (item == null) return;

    final defaultArtworkUri = await AudioDownloadService.getDefaultArtworkUri();
    final artworkUri = item.artUri ?? defaultArtworkUri;

    await _dynamicIslandService.updateActivity(
      itemTitle: item.title,
      feedTitle: item.artist ?? 'Flux News',
      isPlaying: _player.playing,
      currentPosition: _player.position.inSeconds,
      duration: _player.duration?.inSeconds ?? 0,
      artworkUrl: artworkUri?.toString(),
    );
  }

  Future<void> _endDynamicIsland() async {
    if (!Platform.isIOS) return;
    await _dynamicIslandService.endActivity();
  }

  PlaybackState _buildPlaybackState() {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
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
      androidCompactActionIndices: const [0, 1, 2],
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
