import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/audio_progress_store.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:flux_news/ui/adaptive_layout.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

class NewsAudioPlayerScreen extends StatefulWidget {
  const NewsAudioPlayerScreen({super.key, required this.news});

  final News news;

  @override
  State<NewsAudioPlayerScreen> createState() => _NewsAudioPlayerScreenState();
}

class _NewsAudioPlayerScreenState extends State<NewsAudioPlayerScreen> {
  late final ScrollController _articleContentController;
  late final ScrollController _playerContentController;

  @override
  void initState() {
    super.initState();
    _articleContentController = ScrollController();
    _playerContentController = ScrollController();
  }

  @override
  void dispose() {
    _articleContentController.dispose();
    _playerContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioAttachments = widget.news.getAudioAttachments();
    final appState = Provider.of<FluxNewsState>(context, listen: false);
    final useTabletLayout = useTwoPaneLayout(MediaQuery.sizeOf(context));
    final useClearEffect = appState.iosClearLiquidGlass;
    final glassSettings = iosLiquidGlassSettings(
      context,
      useClearEffect: useClearEffect,
    );
    final glassQuality = iosLiquidGlassQuality(
      useClearEffect: useClearEffect,
    );
    final glassForeground = iosLiquidGlassForeground(context);

    Widget newsHeader = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.news.feedTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          widget.news.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );

    Widget articleContent = Scrollbar(
      controller: _articleContentController,
      child: SingleChildScrollView(
        controller: _articleContentController,
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            newsHeader,
            widget.news.getFullRenderedWidget(appState, context)
          ],
        ),
      ),
    );

    Widget mobileLayout = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NewsAudioPlayer(news: widget.news, appState: appState),
        const SizedBox(height: 20),
        Expanded(child: articleContent),
      ],
    );

    Widget tabletLayout = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _playerContentController,
                  child: SingleChildScrollView(
                    controller: _playerContentController,
                    primary: false,
                    child:
                        NewsAudioPlayer(news: widget.news, appState: appState),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 6,
          child: articleContent,
        ),
      ],
    );

    final PreferredSizeWidget appBar = Platform.isIOS
        ? GlassAppBar(
            centerTitle: false,
            buttonSettings: glassSettings,
            leading: GlassIconButton(
              useOwnLayer: true,
              quality: glassQuality,
              settings: glassSettings,
              semanticLabel:
                  MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.maybePop(context),
              icon: Icon(CupertinoIcons.back, color: glassForeground),
            ),
            title: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: GlassContainer(
                  useOwnLayer: true,
                  quality: glassQuality,
                  settings: glassSettings,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    widget.news.feedTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: glassForeground,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          )
        : AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              widget.news.feedTitle,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );

    return Scaffold(
      extendBodyBehindAppBar: Platform.isIOS,
      appBar: appBar,
      body: audioAttachments.isEmpty
          ? Center(
              child: Text(AppLocalizations.of(context)!.noAudioFileAvailable),
            )
          : Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                Platform.isIOS ? MediaQuery.paddingOf(context).top + 52 : 0,
                16,
                16,
              ),
              child: useTabletLayout ? tabletLayout : mobileLayout,
            ),
    );
  }
}

class NewsAudioPlayer extends StatefulWidget {
  const NewsAudioPlayer(
      {super.key, required this.news, required this.appState});

  final News news;
  final FluxNewsState appState;

  @override
  State<NewsAudioPlayer> createState() => _NewsAudioPlayerState();
}

class _NewsAudioPlayerState extends State<NewsAudioPlayer> {
  static const double _chapterTileExtent = 56;

  static final List<RegExp> _chapterTimestampPatterns = [
    RegExp(r'\((?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)\)'),
    RegExp(r'\[(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)\]'),
    RegExp(r'\((?:(\d{1,2})\.)?([0-5]?\d)\.([0-5]\d)\)'),
    RegExp(r'\[(?:(\d{1,2})\.)?([0-5]?\d)\.([0-5]\d)\]'),
    RegExp(r'(?<!\d)(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)(?!\d)'),
    RegExp(r'(?<!\d)(?:(\d{1,2})\.)?([0-5]?\d)\.([0-5]\d)(?!\d)'),
  ];

  static const List<int> _sleepTimerMinuteOptions = [
    30,
    45,
    60,
    75,
    90,
    105,
    120,
    135,
    150,
    165,
    180,
  ];

  FluxNewsAudioHandler? _audioHandler;
  late final List<Attachment> _audioAttachments;
  Timer? _autoSaveTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<PlaybackState>? _playbackStateSubscription;
  StreamSubscription<List<AudioDownloadProgress>>? _activeDownloadsSubscription;
  StreamSubscription<SleepTimerEvent>? _sleepTimerSubscription;
  final Map<int, String> _downloadedPaths = {};
  final Map<int, AudioDownloadProgress> _activeDownloadsByStorageAttachmentID =
      {};
  final Map<int, List<AudioChapter>> _chaptersByAttachmentID = {};
  final Map<int, ScrollController> _chapterScrollControllers = {};
  final Map<int, int> _lastAutoScrolledChapterIndexByAttachmentID = {};
  final Set<int> _loadingChapterAttachmentIDs = {};
  final Set<int> _downloadingAttachmentIDs = {};
  Uri? _defaultArtworkUri;
  double _playbackSpeed = 1.0;
  bool _showPlayerDetails = false;

  String? _activeUrl;
  int? _activeAttachmentID;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _savedPosition; // loaded from storage, seek target on first play
  PlayerState _playerState = PlayerState(false, ProcessingState.idle);
  bool _isLoading = false;
  bool _isDisposed = false;

  String _progressKey() => AudioProgressStore.keyForNews(widget.news.newsID);

  ScrollController _chapterControllerFor(int attachmentID) {
    return _chapterScrollControllers.putIfAbsent(
        attachmentID, ScrollController.new);
  }

  int _storageAttachmentIDFor(Attachment attachment) {
    if (attachment.attachmentID >= 0) {
      return attachment.attachmentID;
    }
    if (attachment.newsID >= 0) {
      return -(attachment.newsID + 1000000);
    }
    return attachment.attachmentID;
  }

  @override
  void initState() {
    super.initState();
    _audioAttachments = widget.news.getAudioAttachments();
    _activeDownloadsByStorageAttachmentID
      ..clear()
      ..addEntries(
        AudioDownloadService.getActiveDownloadsSnapshot()
            .map((progress) => MapEntry(progress.attachmentID, progress)),
      );
    _activeDownloadsSubscription =
        AudioDownloadService.activeDownloadsStream.listen((downloads) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _activeDownloadsByStorageAttachmentID
          ..clear()
          ..addEntries(downloads
              .map((progress) => MapEntry(progress.attachmentID, progress)));
      });
    });
    _initializeDefaultArtwork();
    _initializeAudioHandler();
    _initializeDownloadedAudioState();
    _loadProgress();
    _startAutoSaveTimer();
  }

  Future<void> _initializeDefaultArtwork() async {
    final artworkUri = await AudioDownloadService.getDefaultArtworkUri();
    if (!mounted || _isDisposed) return;
    setState(() => _defaultArtworkUri = artworkUri);
  }

  Future<void> _initializeDownloadedAudioState() async {
    final downloadedPaths =
        await AudioDownloadService.loadDownloadedPathsForAttachments(
            _audioAttachments, widget.appState.audioDownloadRetentionDays);
    _downloadedPaths
      ..clear()
      ..addAll(downloadedPaths);
    for (final attachment in _audioAttachments) {
      await _loadChaptersForAttachment(
        attachment,
        filePath: downloadedPaths[attachment.attachmentID],
      );
    }
    _syncActiveAttachment();
    if (!mounted || _isDisposed) return;
    setState(() {});
  }

  void _syncActiveAttachment({String? mediaItemId}) {
    final currentUrl = _activeUrl;
    final targetId = mediaItemId ?? _audioHandler?.mediaItem.value?.id;

    Attachment? matchedAttachment;
    for (final attachment in _audioAttachments) {
      final downloadedPath = _downloadedPaths[attachment.attachmentID];
      final downloadedUrl =
          downloadedPath != null ? Uri.file(downloadedPath).toString() : null;

      if (targetId != null &&
          targetId.isNotEmpty &&
          attachment.attachmentURL == targetId) {
        matchedAttachment = attachment;
        break;
      }
      if (currentUrl != null && currentUrl.isNotEmpty) {
        if (attachment.attachmentURL == currentUrl ||
            downloadedUrl == currentUrl) {
          matchedAttachment = attachment;
          break;
        }
      }
    }

    if (!mounted) {
      _activeAttachmentID = matchedAttachment?.attachmentID;
      return;
    }

    if (_isDisposed) return;
    setState(() {
      _activeAttachmentID = matchedAttachment?.attachmentID;
    });
  }

  Future<void> _loadChaptersForAttachment(Attachment attachment,
      {String? filePath}) async {
    if (mounted && !_isDisposed) {
      setState(() {
        _loadingChapterAttachmentIDs.add(attachment.attachmentID);
      });
    } else {
      _loadingChapterAttachmentIDs.add(attachment.attachmentID);
    }

    List<AudioChapter> chapters = [];
    if (filePath != null && filePath.isNotEmpty) {
      if (mounted) {
        chapters = await AudioDownloadService.readChapters(filePath, context);
      }
    } else {
      if (mounted) {
        chapters = await AudioDownloadService.readChaptersFromUrl(
            attachment.attachmentURL, context);
      }
    }

    if (chapters.isEmpty) {
      chapters = _extractChaptersFromArticleContent();
    }

    _chaptersByAttachmentID[attachment.attachmentID] = chapters;
    if (!mounted || _isDisposed) {
      _loadingChapterAttachmentIDs.remove(attachment.attachmentID);
      return;
    }

    setState(() {
      _loadingChapterAttachmentIDs.remove(attachment.attachmentID);
    });
  }

  String _htmlToPlainTextWithLineBreaks(String html) {
    final processed = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
            RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n');
    return html_parser.parse(processed).body?.text ?? '';
  }

  List<AudioChapter> _extractChaptersFromArticleContent() {
    final plainText = _htmlToPlainTextWithLineBreaks(widget.news.content);
    if (plainText.trim().isEmpty) {
      return const [];
    }

    final extracted = <AudioChapter>[];
    final seenStartInSeconds = <int>{};

    for (final rawLine in plainText.split('\n')) {
      final line = rawLine.replaceAll('\u00A0', ' ').trim();
      if (line.isEmpty) continue;

      RegExpMatch? match;
      for (final pattern in _chapterTimestampPatterns) {
        match = pattern.firstMatch(line);
        if (match != null) break;
      }
      if (match == null) continue;

      final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
      final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
      final start = Duration(hours: hours, minutes: minutes, seconds: seconds);

      if (seenStartInSeconds.contains(start.inSeconds)) continue;

      final suffix = line.substring(match.end).trim();
      final prefix = line.substring(0, match.start).trim();
      var title = suffix.isNotEmpty ? suffix : prefix;
      title = title.replaceFirst(RegExp(r'^[\-:\.|\)\]\s]+'), '').trim();
      title = title.replaceFirst(RegExp(r'^[\[(]+'), '').trim();

      extracted.add(AudioChapter(
        title: title.isNotEmpty ? title : 'Chapter ${extracted.length + 1}',
        start: start,
      ));
      seenStartInSeconds.add(start.inSeconds);
    }

    if (extracted.length < 2) {
      return const [];
    }

    extracted.sort((a, b) => a.start.compareTo(b.start));

    final normalized = <AudioChapter>[];
    for (int i = 0; i < extracted.length; i++) {
      final current = extracted[i];
      final next = i + 1 < extracted.length ? extracted[i + 1] : null;
      normalized.add(AudioChapter(
        title: current.title,
        start: current.start,
        end: next?.start,
      ));
    }

    return normalized;
  }

  Future<void> _downloadAudio(Attachment attachment, News news) async {
    if (_downloadingAttachmentIDs.contains(attachment.attachmentID)) return;
    setState(() => _downloadingAttachmentIDs.add(attachment.attachmentID));
    // Manual download — clear any previous user-skipped flag.
    final storageId =
        AudioDownloadService.resolveStorageAttachmentId(attachment);
    await AudioDownloadService.clearUserSkipped(storageId);
    try {
      final filePath = await AudioDownloadService.queueDownload(
        attachment,
        onlyOnWifi: widget.appState.downloadAudioOnlyOnWifi,
        news: widget.news,
      );
      if (filePath != null) {
        _downloadedPaths[attachment.attachmentID] = filePath;
        await _loadChaptersForAttachment(attachment, filePath: filePath);
        // Re-download: reset position so the episode starts from the beginning.
        // Write "0" so _loadProgress treats this as an explicit reset.
        await AudioProgressStore.write(_progressKey(), '0');
        syncMediaProgression(
                widget.appState, widget.news.newsID, attachment.attachmentID, 0)
            .ignore();
        if (mounted && !_isDisposed) {
          setState(() => _savedPosition = null);
        }
      } else if (widget.appState.downloadAudioOnlyOnWifi) {
        final isWifiConnected = await AudioDownloadService.isWifiConnected();
        if (!isWifiConnected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.downloadWLANWarning),
            ),
          );
        }
      }
      NewsList newsList = NewsList(news: [news], newsCount: 1);
      await insertNewsInDB(newsList, widget.appState);
      AudioDownloadService.refreshMediaProgressionCacheFromSync([news]);
    } finally {
      if (mounted) {
        setState(
            () => _downloadingAttachmentIDs.remove(attachment.attachmentID));
      }
    }
  }

  Future<void> _initializeAudioHandler() async {
    final audioHandler = await initFluxNewsAudioHandler();
    if (!mounted || _isDisposed) return;

    _audioHandler = audioHandler;
    _activeUrl = audioHandler.currentUrl;
    _position = audioHandler.position;
    _duration = audioHandler.duration ?? Duration.zero;
    _playerState = audioHandler.playerState;
    _isLoading = _playerState.processingState == ProcessingState.loading ||
        _playerState.processingState == ProcessingState.buffering;
    _syncActiveAttachment(mediaItemId: audioHandler.mediaItem.value?.id);

    _positionSubscription = audioHandler.positionStream.listen((position) {
      if (!mounted || _isDisposed) return;
      setState(() => _position = position);
    });

    _durationSubscription = audioHandler.durationStream.listen((duration) {
      if (!mounted || _isDisposed) return;
      setState(() => _duration = duration ?? Duration.zero);
    });

    _playerStateSubscription = audioHandler.playerStateStream.listen((state) {
      if (!mounted || _isDisposed) return;
      final completed = state.processingState == ProcessingState.completed &&
          _activeUrl != null;
      setState(() {
        _playerState = state;
        _isLoading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
      });
      if (completed) {
        _handlePlaybackCompleted();
      }
    });

    _mediaItemSubscription = audioHandler.mediaItem.listen((item) {
      if (!mounted || _isDisposed) return;
      _syncActiveAttachment(mediaItemId: item?.id);
    });

    _playbackStateSubscription = audioHandler.playbackState.listen((state) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _playbackSpeed = state.speed;
      });
    });

    _sleepTimerSubscription = audioHandler.sleepTimerStream.listen((event) {
      if (!mounted || _isDisposed) return;
      setState(() {});
      if (event == SleepTimerEvent.fired) {
        _saveProgress();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.sleepTimerNotification)),
        );
      }
    });

    if (!mounted || _isDisposed) return;
    setState(() {});
  }

  @override
  void dispose() {
    _isDisposed = true;
    _saveProgress();
    _autoSaveTimer?.cancel();
    _sleepTimerSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _activeDownloadsSubscription?.cancel();
    for (final controller in _chapterScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _setPlaybackSpeedFromAdjustment(double adjustment) async {
    if (_audioHandler == null) return;

    final roundedAdjustment = (adjustment * 10).round() / 10;
    final speed = (1.0 + roundedAdjustment).clamp(0.5, 3.0).toDouble();
    await _audioHandler!.setSpeed(speed);
    if (!mounted || _isDisposed) return;
    setState(() {
      _playbackSpeed = speed;
    });
  }

  String _formatSignedAdjustment(double adjustment) {
    final rounded = (adjustment * 10).round() / 10;
    if (rounded >= 0) {
      return '+${rounded.toStringAsFixed(1)}';
    }
    return rounded.toStringAsFixed(1);
  }

  Future<void> _handlePlaybackCompleted() async {
    final completedAttachmentID = _activeAttachmentID;
    final completedAttachment = completedAttachmentID == null
        ? null
        : _audioAttachments
            .where((a) => a.attachmentID == completedAttachmentID)
            .fold<Attachment?>(null, (prev, e) => prev ?? e);

    // Stop without saving progress — episode is done, position should be 0.
    // Write "0" (not delete) so _loadProgress can distinguish between
    // "never played" (null → server wins) and "explicitly reset" (0 → start
    // from beginning regardless of stale server/cache value).
    await _stop(saveProgress: false);
    await AudioProgressStore.write(_progressKey(), '0');
    if (mounted && !_isDisposed) {
      setState(() => _savedPosition = null);
    }

    if (completedAttachment != null) {
      syncMediaProgression(widget.appState, widget.news.newsID,
              completedAttachment.attachmentID, 0)
          .ignore();
    }

    if (widget.appState.deleteAudioAfterPlayback &&
        completedAttachmentID != null) {
      final downloadedPath = _downloadedPaths[completedAttachmentID];
      if (downloadedPath != null) {
        await AudioDownloadService.deleteDownloadedAudio(completedAttachmentID);
        if (mounted && !_isDisposed) {
          setState(() {
            _downloadedPaths.remove(completedAttachmentID);
            _chaptersByAttachmentID.remove(completedAttachmentID);
          });
        }
      }
    }
  }

  void _toggleSleepTimer(bool enabled) {
    if (!mounted || _audioHandler == null) return;
    if (!enabled) {
      _audioHandler!.cancelSleepTimer();
    } else {
      _audioHandler!.startSleepTimer(_audioHandler!.sleepTimerMinutes);
    }
  }

  void _updateSleepTimerMinutes(int minutes) {
    if (!mounted || _audioHandler == null) return;
    _audioHandler!.updateSleepTimerMinutes(minutes);
  }

  // ---- Progress persistence ----

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_playerState.playing) {
        _saveProgress();
      }
    });
  }

  Future<void> _loadProgress() async {
    final saved = await AudioProgressStore.read(_progressKey());
    if (!mounted || _isDisposed) return;
    final localMs = saved != null ? (int.tryParse(saved) ?? 0) : 0;
    // "0" written explicitly signals a completed or re-downloaded episode.
    // Skip server/cache entirely so a stale in-memory value cannot override
    // the intended fresh start.
    final wasReset = saved != null && localMs == 0;

    // Server value: prefer the in-memory cache (updated by refreshMediaProgressionCacheFromSync
    // AFTER queryNewsFromDB, so it reflects the latest sync result). Fall back to the
    // mediaProgression on the News object (may be stale if sync hasn't completed yet).
    int serverMs = 0;
    if (!wasReset && _audioAttachments.isNotEmpty) {
      final attachmentID = _audioAttachments.first.attachmentID;
      final cached =
          AudioDownloadService.getDownloadMediaProgression(attachmentID);
      if (cached != null && cached > 0) {
        serverMs = cached * 1000;
      } else if (_audioAttachments.first.mediaProgression > 0) {
        serverMs = _audioAttachments.first.mediaProgression * 1000;
      }
    }

    if (widget.appState.debugMode) {
      logThis(
        'AudioPlayer._loadProgress',
        'newsID=${widget.news.newsID} '
            'localMs=$localMs '
            'serverMs=$serverMs '
            'attachmentProgression=${_audioAttachments.isNotEmpty ? _audioAttachments.first.mediaProgression : -1}s '
            'cacheProgression=${_audioAttachments.isNotEmpty ? AudioDownloadService.getDownloadMediaProgression(_audioAttachments.first.attachmentID) : -1}s',
        LogLevel.INFO,
      );
    }

    // Use whichever position is further ahead. If the server is ahead, also
    // update the Keychain so the advanced position persists across app restarts.
    if (serverMs > localMs) {
      try {
        await AudioProgressStore.write(_progressKey(), serverMs.toString());
      } catch (_) {}
      if (widget.appState.debugMode) {
        logThis('AudioPlayer._loadProgress',
            'Server wins → ${serverMs ~/ 1000}s', LogLevel.INFO);
      }
      setState(() => _savedPosition = Duration(milliseconds: serverMs));
    } else if (localMs > 0) {
      if (widget.appState.debugMode) {
        logThis('AudioPlayer._loadProgress', 'Local wins → ${localMs ~/ 1000}s',
            LogLevel.INFO);
      }
      setState(() => _savedPosition = Duration(milliseconds: localMs));
    } else {
      if (widget.appState.debugMode) {
        logThis('AudioPlayer._loadProgress', 'No saved position → start from 0',
            LogLevel.INFO);
      }
    }
  }

  Future<void> _saveProgress() async {
    if (_activeUrl == null || _position == Duration.zero) return;
    await AudioProgressStore.write(
        _progressKey(), _position.inMilliseconds.toString());
    // Sync with Miniflux server
    final activeAttachment = _activeAttachmentID == null
        ? null
        : _audioAttachments
            .where((a) => a.attachmentID == _activeAttachmentID)
            .fold<Attachment?>(null, (prev, e) => prev ?? e);
    if (activeAttachment != null) {
      syncMediaProgression(widget.appState, widget.news.newsID,
              activeAttachment.attachmentID, _position.inSeconds)
          .ignore();
    }
  }

  // ---- Playback controls ----

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Future<void> _play(Attachment attachment) async {
    if (_audioHandler == null) return;
    final downloadedPath = _downloadedPaths[attachment.attachmentID];
    final url = downloadedPath != null
        ? Uri.file(downloadedPath).toString()
        : attachment.attachmentURL;
    if (url.isEmpty) return;

    // Use the handler's actual current URL as source of truth. _activeUrl can
    // diverge from url when _downloadedPaths is populated asynchronously after
    // initState: the first Play press may compute url=https:// while the handler
    // already has file://, or vice versa on the subsequent Pause press. Both the
    // file URI and the HTTP URL identify the same attachment content.
    final handlerUrl = _audioHandler!.currentUrl;
    final isCurrentAttachment = url == handlerUrl ||
        url == _activeUrl ||
        attachment.attachmentURL == handlerUrl ||
        (downloadedPath != null &&
            Uri.file(downloadedPath).toString() == handlerUrl);

    if (isCurrentAttachment && _playerState.playing) {
      await _audioHandler!.pause();
      await _saveProgress();
      return;
    }
    if (isCurrentAttachment &&
        !_playerState.playing &&
        _playerState.processingState != ProcessingState.completed) {
      // Clear stale saved position so a subsequent URL mismatch (async
      // _downloadedPaths race) cannot trigger an unintended seek back to the
      // CarPlay pause position via the full-load path.
      setState(() => _savedPosition = null);
      await _audioHandler!.play();
      return;
    }

    final seekTarget = _savedPosition;
    final mediaItem = await _buildMediaItem(attachment);
    setState(() {
      _isLoading = true;
      _activeUrl = url;
      _activeAttachmentID = attachment.attachmentID;
      _position = seekTarget ?? Duration.zero;
      _duration = Duration.zero;
    });
    await _audioHandler!.loadMediaItem(
      url: url,
      item: mediaItem,
      initialPosition:
          seekTarget != null && seekTarget > Duration.zero ? seekTarget : null,
    );
    await _audioHandler!.play();
    if (seekTarget != null &&
        seekTarget > Duration.zero &&
        mounted &&
        !_isDisposed) {
      setState(() => _savedPosition = null);
    }
  }

  Future<void> _stop({bool saveProgress = true}) async {
    if (_audioHandler == null) return;
    if (saveProgress) await _saveProgress();
    await _audioHandler!.stop();
    if (!mounted || _isDisposed) return;
    setState(() {
      _savedPosition = _position > Duration.zero ? _position : _savedPosition;
      _activeUrl = null;
      _activeAttachmentID = null;
      _isLoading = false;
    });
  }

  Future<void> _reset({bool saveProgress = false}) async {
    if (_audioHandler == null) return;
    if (saveProgress) await _saveProgress();
    await _audioHandler!.stop();
    await AudioProgressStore.delete(_progressKey());
    final activeAttachment = _activeAttachmentID == null
        ? null
        : _audioAttachments
            .where((a) => a.attachmentID == _activeAttachmentID)
            .fold<Attachment?>(null, (prev, e) => prev ?? e);
    if (activeAttachment != null) {
      syncMediaProgression(widget.appState, widget.news.newsID,
              activeAttachment.attachmentID, 0)
          .ignore();
    }
    if (!mounted || _isDisposed) return;
    setState(() {
      _activeUrl = null;
      _activeAttachmentID = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _savedPosition = null;
      _isLoading = false;
    });
  }

  String _formatSleepTimerLabel() {
    final handler = _audioHandler;
    if (handler == null ||
        !handler.sleepTimerEnabled ||
        handler.sleepTimerEndAt == null) {
      return AppLocalizations.of(context)!.sleepTimerOff;
    }

    final remaining = handler.sleepTimerEndAt!.difference(DateTime.now());
    if (remaining.inSeconds <= 0) {
      return AppLocalizations.of(context)!.sleepTimerEndingSoon;
    }

    final remainingMinutes = (remaining.inSeconds / 60).ceil();
    return '${AppLocalizations.of(context)!.sleepTimerActive} ($remainingMinutes ${AppLocalizations.of(context)!.sleepTimerRemaining})';
  }

  Future<void> _seek(Duration offset) async {
    if (_audioHandler == null) return;
    final newPosition = _position + offset;
    final clamped = newPosition < Duration.zero
        ? Duration.zero
        : newPosition > _duration && _duration > Duration.zero
            ? _duration
            : newPosition;
    await _audioHandler!.seek(clamped);
  }

  Future<void> _seekToChapter(
      Attachment attachment, AudioChapter chapter) async {
    if (_audioHandler == null) return;

    final downloadedPath = _downloadedPaths[attachment.attachmentID];
    final url = downloadedPath != null
        ? Uri.file(downloadedPath).toString()
        : attachment.attachmentURL;
    if (url.isEmpty) return;

    if (_activeUrl == url) {
      await _audioHandler!.seek(chapter.start);
      if (!_playerState.playing) {
        await _audioHandler!.play();
      }
      if (!mounted) return;
      setState(() {
        _activeAttachmentID = attachment.attachmentID;
        _position = chapter.start;
        _savedPosition = null;
      });
      return;
    }

    final mediaItem = await _buildMediaItem(attachment);
    setState(() {
      _isLoading = true;
      _activeUrl = url;
      _activeAttachmentID = attachment.attachmentID;
      _position = chapter.start;
      _duration = Duration.zero;
      _savedPosition = null;
    });
    await _audioHandler!.loadMediaItem(
      url: url,
      item: mediaItem,
      initialPosition: chapter.start,
    );
    await _audioHandler!.play();
  }

  String _formatChapterStart(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '${duration.inMinutes}:$seconds';
  }

  /// Gibt den Index des aktuell laufenden Kapitels zurück (-1 wenn kein Match).
  int _activeChapterIndex(List<AudioChapter> chapters, Duration position) {
    if (chapters.isEmpty) return -1;
    int active = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (position >= chapters[i].start) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  /// Scrollt die Kapitel-Liste so, dass das aktive Kapitel sichtbar ist.
  void _scrollToActiveChapter(
    ScrollController controller,
    int activeIndex,
  ) {
    if (!controller.hasClients) return;
    final targetOffset = (activeIndex * _chapterTileExtent).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  bool _isSupportedArtworkUri(Uri? uri) {
    if (uri == null) {
      return false;
    }

    return uri.scheme == 'file' ||
        uri.scheme == 'content' ||
        uri.scheme == 'http' ||
        uri.scheme == 'https';
  }

  Future<Uri?> _resolveFallbackArtworkUri() async {
    _defaultArtworkUri ??= await AudioDownloadService.getDefaultArtworkUri();
    return _isSupportedArtworkUri(_defaultArtworkUri)
        ? _defaultArtworkUri
        : null;
  }

  Future<MediaItem> _buildMediaItem(Attachment attachment) async {
    final parsedUri = Uri.tryParse(attachment.attachmentURL);
    final fallbackMediaName =
        parsedUri != null && parsedUri.pathSegments.isNotEmpty
            ? parsedUri.pathSegments.last
            : attachment.attachmentMimeType;
    final title =
        _audioAttachments.length == 1 ? widget.news.title : fallbackMediaName;

    Uri? artworkUri;
    String? artCacheFile;
    if (attachment.attachmentID >= 0) {
      artworkUri = await AudioDownloadService.getCachedArtworkUriForAttachment(
          attachment.attachmentID);
      artCacheFile =
          await AudioDownloadService.getCachedArtworkFilePathForAttachment(
              attachment.attachmentID);
    }
    artworkUri ??= await _resolveFallbackArtworkUri();
    artCacheFile ??= await AudioDownloadService.getDefaultArtworkFilePath();

    return MediaItem(
      id: attachment.attachmentURL,
      title: title,
      artist: widget.news.feedTitle,
      album: widget.news.feedTitle,
      artUri: artworkUri,
      extras: <String, dynamic>{
        'newsID': widget.news.newsID,
        'attachmentID': attachment.attachmentID,
        if (artCacheFile != null) 'artCacheFile': artCacheFile,
      },
    );
  }

  Widget _buildAdaptiveSlider({
    required double value,
    required double max,
    required ValueChanged<double>? onChanged,
    double min = 0,
    int? divisions,
    String? label,
  }) {
    if (!Platform.isIOS) {
      return Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      );
    }

    final useClearEffect = widget.appState.iosClearLiquidGlass;
    final foreground = iosLiquidGlassForeground(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: GlassSlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        useOwnLayer: true,
        quality: iosLiquidGlassQuality(useClearEffect: useClearEffect),
        settings: iosLiquidGlassSettings(
          context,
          useClearEffect: useClearEffect,
        ),
        activeColor: CupertinoColors.activeBlue.resolveFrom(context),
        inactiveColor: foreground.withValues(alpha: 0.18),
        thumbColor: CupertinoColors.white,
      ),
    );
  }

  Widget _buildPlaybackControls({
    required Attachment attachment,
    required bool isActive,
    required bool isPlaying,
    required bool isPaused,
    required bool isStopped,
    required AppLocalizations localizations,
  }) {
    if (!Platform.isIOS) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '-30s',
            onPressed:
                isActive ? () => _seek(const Duration(seconds: -30)) : null,
            icon: const Icon(Icons.replay_30),
            iconSize: 32,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isLoading && isActive)
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                IconButton(
                  tooltip: isPlaying
                      ? localizations.pause
                      : isPaused
                          ? localizations.resume
                          : localizations.play,
                  onPressed: () => _play(attachment),
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  iconSize: 56,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: localizations.stop,
            onPressed: isActive && !isStopped ? () => _stop() : null,
            icon: const Icon(Icons.stop_circle_outlined),
            iconSize: 32,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '+30s',
            onPressed:
                isActive ? () => _seek(const Duration(seconds: 30)) : null,
            icon: const Icon(Icons.forward_30),
            iconSize: 32,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: localizations.resetPlayback,
            onPressed: isActive || isPaused ? () => _reset() : null,
            icon: const Icon(Icons.eject),
            iconSize: 32,
          ),
        ],
      );
    }

    final useClearEffect = widget.appState.iosClearLiquidGlass;
    final settings = iosLiquidGlassSettings(
      context,
      useClearEffect: useClearEffect,
    );
    final quality = iosLiquidGlassQuality(useClearEffect: useClearEffect);
    final foreground = iosLiquidGlassForeground(context);

    return Center(
      child: GlassButtonGroup.icons(
        useOwnLayer: true,
        quality: quality,
        settings: settings,
        iconSize: 26,
        itemPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        items: [
          GlassButtonGroupItem(
            label: '-30s',
            enabled: isActive,
            onTap: () => unawaited(_seek(const Duration(seconds: -30))),
            icon: const Icon(Icons.replay_30),
          ),
          GlassButtonGroupItem(
            label: isPlaying
                ? localizations.pause
                : isPaused
                    ? localizations.resume
                    : localizations.play,
            onTap: () => unawaited(_play(attachment)),
            icon: _isLoading && isActive
                ? CupertinoActivityIndicator(color: foreground)
                : Icon(
                    isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                  ),
          ),
          GlassButtonGroupItem(
            label: localizations.stop,
            enabled: isActive && !isStopped,
            onTap: () => unawaited(_stop()),
            icon: const Icon(CupertinoIcons.stop_fill),
          ),
          GlassButtonGroupItem(
            label: '+30s',
            enabled: isActive,
            onTap: () => unawaited(_seek(const Duration(seconds: 30))),
            icon: const Icon(Icons.forward_30),
          ),
          GlassButtonGroupItem(
            label: localizations.resetPlayback,
            enabled: isActive || isPaused,
            onTap: () => unawaited(_reset()),
            icon: const Icon(CupertinoIcons.eject_fill),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_audioAttachments.isEmpty) return const SizedBox.shrink();
    if (_audioHandler == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final localizations = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Platform.isIOS
              ? AdaptiveSettingsButton(
                  onPressed: () {
                    setState(() {
                      _showPlayerDetails = !_showPlayerDetails;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showPlayerDetails
                            ? Icons.unfold_less
                            : Icons.unfold_more,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showPlayerDetails
                            ? localizations.hidePlayerDetails
                            : localizations.showPlayerDetails,
                      ),
                    ],
                  ),
                )
              : TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showPlayerDetails = !_showPlayerDetails;
                    });
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 32),
                  ),
                  icon: Icon(
                    _showPlayerDetails ? Icons.unfold_less : Icons.unfold_more,
                    size: 18,
                  ),
                  label: Text(
                    _showPlayerDetails
                        ? localizations.hidePlayerDetails
                        : localizations.showPlayerDetails,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
        ),
        ..._audioAttachments.map((attachment) {
          final isActive = _activeAttachmentID == attachment.attachmentID;
          final isPlaying = isActive && _playerState.playing;
          final isPaused = isActive &&
              !_playerState.playing &&
              _playerState.processingState != ProcessingState.idle;
          final isStopped =
              !isActive || _playerState.processingState == ProcessingState.idle;
          final isDownloaded =
              _downloadedPaths.containsKey(attachment.attachmentID);
          final isDownloading =
              _downloadingAttachmentIDs.contains(attachment.attachmentID);
          final storageAttachmentID = _storageAttachmentIDFor(attachment);
          final downloadProgress =
              _activeDownloadsByStorageAttachmentID[storageAttachmentID];
          final downloadProgressValue = downloadProgress?.progress;
          final isLoadingChapters =
              _loadingChapterAttachmentIDs.contains(attachment.attachmentID);
          final chapters = _chaptersByAttachmentID[attachment.attachmentID] ??
              const <AudioChapter>[];

          final parsedUri = Uri.tryParse(attachment.attachmentURL);
          final fallbackMediaName =
              parsedUri != null && parsedUri.pathSegments.isNotEmpty
                  ? parsedUri.pathSegments.last
                  : attachment.attachmentMimeType;
          final mediaName = _audioAttachments.length == 1
              ? widget.news.title
              : fallbackMediaName;
          final chapterListHeight = chapters.length > 4
              ? 4 * _chapterTileExtent
              : chapters.length * _chapterTileExtent;
          final chapterScrollController =
              _chapterControllerFor(attachment.attachmentID);

          final maxMs = _duration.inMilliseconds > 0
              ? _duration.inMilliseconds.toDouble()
              : 1.0;
          final currentMs = isActive
              ? _position.inMilliseconds.toDouble().clamp(0.0, maxMs)
              : 0.0;
          // Show saved position in time label before playback starts
          final displayPosition =
              isActive ? _position : (_savedPosition ?? Duration.zero);
          final downloadTooltip = isDownloading
              ? localizations.cancel
              : isDownloaded
                  ? localizations.downloaded
                  : localizations.downloadAudio;
          final VoidCallback? downloadAction = isDownloaded
              ? null
              : isDownloading
                  ? () => AudioDownloadService.cancelDownload(
                        storageAttachmentID,
                      )
                  : () => _downloadAudio(attachment, widget.news);
          final downloadIcon = isDownloading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: downloadProgressValue,
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.close,
                        size: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                )
              : Icon(
                  isDownloaded ? Icons.download_done : Icons.download,
                  color: Theme.of(context).colorScheme.primary,
                );

          return Card(
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Media name
                  Row(
                    children: [
                      Icon(Icons.headphones,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mediaName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Platform.isIOS
                          ? GlassIconButton(
                              useOwnLayer: true,
                              quality: iosLiquidGlassQuality(
                                useClearEffect:
                                    widget.appState.iosClearLiquidGlass,
                              ),
                              settings: iosLiquidGlassSettings(
                                context,
                                useClearEffect:
                                    widget.appState.iosClearLiquidGlass,
                              ),
                              semanticLabel: downloadTooltip,
                              onPressed: downloadAction,
                              icon: downloadIcon,
                            )
                          : IconButton(
                              color: Theme.of(context).colorScheme.primary,
                              tooltip: downloadTooltip,
                              onPressed: downloadAction,
                              icon: downloadIcon,
                              iconSize: 20,
                            ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Progress slider
                  _buildAdaptiveSlider(
                    value: currentMs,
                    max: maxMs,
                    onChanged: isActive
                        ? (value) async {
                            await _audioHandler!
                                .seek(Duration(milliseconds: value.toInt()));
                          }
                        : null,
                  ),

                  // Time display
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(displayPosition),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          isActive && _duration > Duration.zero
                              ? _formatDuration(_duration)
                              : '--:--',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                  if (_showPlayerDetails) ...[
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      shape: Border(
                          bottom: BorderSide(
                              color: Theme.of(context).dividerColor)),
                      collapsedShape: LinearBorder.none,
                      title: Text(
                        localizations.chapters,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      onExpansionChanged: (expanded) {
                        if (!expanded) {
                          // Clear stored index so re-opening always scrolls to
                          // the current chapter, even if it hasn't changed.
                          _lastAutoScrolledChapterIndexByAttachmentID
                              .remove(attachment.attachmentID);
                        }
                      },
                      children: [
                        if (isLoadingChapters)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 12),
                                Text(localizations.loadingChapters),
                              ],
                            ),
                          )
                        else if (chapters.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                localizations.noChaptersFound,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: chapterListHeight,
                            child: Scrollbar(
                              controller: chapterScrollController,
                              child: Builder(
                                builder: (context) {
                                  final activeChapterIdx = isActive
                                      ? _activeChapterIndex(chapters, _position)
                                      : -1;

                                  if (isActive && activeChapterIdx >= 0) {
                                    final previousAutoScrolledIdx =
                                        _lastAutoScrolledChapterIndexByAttachmentID[
                                            attachment.attachmentID];
                                    if (previousAutoScrolledIdx !=
                                        activeChapterIdx) {
                                      _lastAutoScrolledChapterIndexByAttachmentID[
                                              attachment.attachmentID] =
                                          activeChapterIdx;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        _scrollToActiveChapter(
                                          chapterScrollController,
                                          activeChapterIdx,
                                        );
                                      });
                                    }
                                  }

                                  return ListView.builder(
                                    controller: chapterScrollController,
                                    primary: false,
                                    padding: EdgeInsets.zero,
                                    clipBehavior: Clip.hardEdge,
                                    itemExtent: _chapterTileExtent,
                                    itemCount: chapters.length,
                                    itemBuilder: (context, index) {
                                      final chapter = chapters[index];
                                      final isActiveChapter =
                                          index == activeChapterIdx;
                                      final tileColor = isActiveChapter
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withAlpha(128)
                                          : Colors.transparent;
                                      // Keep the highlight on the same clipped
                                      // render layer as its row. ListTile's
                                      // tileColor otherwise paints on the
                                      // surrounding player Card and remains
                                      // visible below the ExpansionTile header.
                                      return Material(
                                        color: tileColor,
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: Row(children: [
                                            isActiveChapter
                                                ? Icon(
                                                    Icons.play_arrow,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  )
                                                : const SizedBox(width: 16),
                                            Expanded(
                                                child: Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 4.0),
                                              child: Text(
                                                chapter.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: isActiveChapter
                                                    ? Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onPrimaryContainer,
                                                        )
                                                    : Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium,
                                              ),
                                            )),
                                          ]),
                                          trailing: Text(
                                            _formatChapterStart(chapter.start),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          onTap: () {
                                            // The tapped row is already in the
                                            // viewport. Treat it as positioned
                                            // so the subsequent playback-state
                                            // update does not scroll it away.
                                            _lastAutoScrolledChapterIndexByAttachmentID[
                                                    attachment.attachmentID] =
                                                index;
                                            unawaited(_seekToChapter(
                                              attachment,
                                              chapter,
                                            ));
                                          },
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      shape: LinearBorder.none,
                      collapsedShape: LinearBorder.none,
                      title: Text(
                        localizations.advancedSettings,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.speed, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${localizations.speed}: ${_playbackSpeed.toStringAsFixed(1)}x (${_formatSignedAdjustment(_playbackSpeed - 1.0)})',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        _buildAdaptiveSlider(
                          value: (_playbackSpeed - 1.0).clamp(-0.5, 2.0),
                          min: -0.5,
                          max: 2.0,
                          divisions: 25,
                          label: _formatSignedAdjustment(_playbackSpeed - 1.0),
                          onChanged: (value) async {
                            await _setPlaybackSpeedFromAdjustment(value);
                          },
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.bedtime_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatSleepTimerLabel(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            AdaptiveSettingsSwitch(
                              value: _audioHandler?.sleepTimerEnabled ?? false,
                              onChanged: (value) {
                                _toggleSleepTimer(value);
                              },
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const SizedBox(width: 26),
                            Expanded(
                              child: Text(
                                localizations.interval,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            AdaptiveSettingsDropdown<int>(
                              value: _audioHandler?.sleepTimerMinutes ?? 30,
                              onChanged: (value) {
                                if (value != null) {
                                  _updateSleepTimerMinutes(value);
                                }
                              },
                              items: _sleepTimerMinuteOptions
                                  .map((minutes) => DropdownMenuItem<int>(
                                        value: minutes,
                                        child: Text(
                                            '$minutes ${localizations.minutes}'),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ],

                  _buildPlaybackControls(
                    attachment: attachment,
                    isActive: isActive,
                    isPlaying: isPlaying,
                    isPaused: isPaused,
                    isStopped: isStopped,
                    localizations: localizations,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
