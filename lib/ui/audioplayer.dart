import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:just_audio/just_audio.dart';
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final useTabletLayout = screenWidth >= 900 || shortestSide >= 600;

    Widget articleContent = Scrollbar(
      controller: _articleContentController,
      child: SingleChildScrollView(
        controller: _articleContentController,
        primary: false,
        child: widget.news.getFullRenderedWidget(appState, context),
      ),
    );

    Widget playerHeader = Column(
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

    Widget mobileLayout = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        playerHeader,
        const SizedBox(height: 16),
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
              playerHeader,
              const SizedBox(height: 16),
              Expanded(
                child: Scrollbar(
                  controller: _playerContentController,
                  child: SingleChildScrollView(
                    controller: _playerContentController,
                    primary: false,
                    child: NewsAudioPlayer(news: widget.news, appState: appState),
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(widget.news.title),
      ),
      body: audioAttachments.isEmpty
          ? Center(
              child: Text(AppLocalizations.of(context)!.noAudioFileAvailable),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: useTabletLayout ? tabletLayout : mobileLayout,
            ),
    );
  }
}

class NewsAudioPlayer extends StatefulWidget {
  const NewsAudioPlayer({super.key, required this.news, required this.appState});

  final News news;
  final FluxNewsState appState;

  @override
  State<NewsAudioPlayer> createState() => _NewsAudioPlayerState();
}

class _NewsAudioPlayerState extends State<NewsAudioPlayer> {
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
  final _storage = const sec_store.FlutterSecureStorage();
  Timer? _autoSaveTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<PlaybackState>? _playbackStateSubscription;
  final Map<int, String> _downloadedPaths = {};
  final Map<int, List<AudioChapter>> _chaptersByAttachmentID = {};
  final Map<int, ScrollController> _chapterScrollControllers = {};
  final Set<int> _loadingChapterAttachmentIDs = {};
  final Set<int> _downloadingAttachmentIDs = {};
  Uri? _defaultArtworkUri;
  double _playbackSpeed = 1.0;
  Timer? _sleepTimer;
  bool _sleepTimerEnabled = false;
  int _sleepTimerMinutes = 30;
  DateTime? _sleepTimerEndAt;

  String? _activeUrl;
  int? _activeAttachmentID;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _savedPosition; // loaded from storage, seek target on first play
  PlayerState _playerState = PlayerState(false, ProcessingState.idle);
  bool _isLoading = false;
  bool _isDisposed = false;

  String _progressKey() => '${FluxNewsState.audioProgressKeyPrefix}${widget.news.newsID}';

  ScrollController _chapterControllerFor(int attachmentID) {
    return _chapterScrollControllers.putIfAbsent(attachmentID, ScrollController.new);
  }

  @override
  void initState() {
    super.initState();
    _audioAttachments = widget.news.getAudioAttachments();
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
    final downloadedPaths = await AudioDownloadService.loadDownloadedPathsForAttachments(
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
      final downloadedUrl = downloadedPath != null ? Uri.file(downloadedPath).toString() : null;

      if (targetId != null && targetId.isNotEmpty && attachment.attachmentURL == targetId) {
        matchedAttachment = attachment;
        break;
      }
      if (currentUrl != null && currentUrl.isNotEmpty) {
        if (attachment.attachmentURL == currentUrl || downloadedUrl == currentUrl) {
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

  Future<void> _loadChaptersForAttachment(Attachment attachment, {String? filePath}) async {
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
        chapters = await AudioDownloadService.readChaptersFromUrl(attachment.attachmentURL, context);
      }
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

  Future<void> _downloadAudio(Attachment attachment) async {
    if (_downloadingAttachmentIDs.contains(attachment.attachmentID)) return;
    setState(() => _downloadingAttachmentIDs.add(attachment.attachmentID));
    try {
      final filePath = await AudioDownloadService.downloadAttachment(attachment,
          onlyOnWifi: widget.appState.downloadAudioOnlyOnWifi);
      if (filePath != null) {
        _downloadedPaths[attachment.attachmentID] = filePath;
        await _loadChaptersForAttachment(attachment, filePath: filePath);
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
    } finally {
      if (mounted) {
        setState(() => _downloadingAttachmentIDs.remove(attachment.attachmentID));
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
      final completed = state.processingState == ProcessingState.completed && _activeUrl != null;
      setState(() {
        _playerState = state;
        _isLoading =
            state.processingState == ProcessingState.loading || state.processingState == ProcessingState.buffering;
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

    if (!mounted || _isDisposed) return;
    setState(() {});
  }

  @override
  void dispose() {
    _isDisposed = true;
    _saveProgress();
    _autoSaveTimer?.cancel();
    _sleepTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    for (final controller in _chapterScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _setPlaybackSpeedFromAdjustment(double adjustment) async {
    if (_audioHandler == null) return;

    final roundedAdjustment = (adjustment * 10).round() / 10;
    final speed = (1.0 + roundedAdjustment).clamp(0.5, 4.0).toDouble();
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
    final shouldDeleteDownloadedAudio = widget.appState.deleteAudioAfterPlayback && completedAttachmentID != null;

    await _storage.delete(key: _progressKey());
    final completedAttachment = _activeAttachmentID == null
        ? null
        : _audioAttachments
            .where((a) => a.attachmentID == _activeAttachmentID)
            .fold<Attachment?>(null, (prev, e) => prev ?? e);
    if (completedAttachment != null) {
      syncMediaProgression(widget.appState, widget.news.newsID, completedAttachment.attachmentID, 0).ignore();
    }

    if (shouldDeleteDownloadedAudio) {
      final attachmentIDToDelete = completedAttachmentID;
      final downloadedPath = _downloadedPaths[attachmentIDToDelete];
      if (downloadedPath != null) {
        await AudioDownloadService.deleteDownloadedAudio(attachmentIDToDelete);
        _downloadedPaths.remove(attachmentIDToDelete);
        _chaptersByAttachmentID.remove(attachmentIDToDelete);
      }
    }

    _autoSaveTimer?.cancel();
    _sleepTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _position = Duration.zero;
      _savedPosition = null;
      _activeUrl = null;
      _activeAttachmentID = null;
      _isLoading = false;
      _sleepTimerEnabled = false;
      _sleepTimerEndAt = null;
    });
  }

  void _startSleepTimer() {
    _sleepTimer?.cancel();
    final duration = Duration(minutes: _sleepTimerMinutes);
    _sleepTimerEndAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () async {
      if (_playerState.playing) {
        await _stop();
      }
      if (!mounted || _isDisposed) return;
      setState(() {
        _sleepTimerEnabled = false;
        _sleepTimerEndAt = null;
      });
      if (!mounted || _isDisposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.sleepTimerNotification)),
      );
    });
  }

  Future<void> _toggleSleepTimer(bool enabled) async {
    if (!mounted) return;

    if (!enabled) {
      _sleepTimer?.cancel();
      setState(() {
        _sleepTimerEnabled = false;
        _sleepTimerEndAt = null;
      });
      return;
    }

    setState(() {
      _sleepTimerEnabled = true;
    });
    _startSleepTimer();
  }

  Future<void> _updateSleepTimerMinutes(int minutes) async {
    if (!mounted) return;
    setState(() {
      _sleepTimerMinutes = minutes;
    });

    if (_sleepTimerEnabled) {
      _startSleepTimer();
    }
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
    final saved = await _storage.read(key: _progressKey());
    if (!mounted || _isDisposed) return;
    final localMs = saved != null ? (int.tryParse(saved) ?? 0) : 0;

    // Prefer local storage; fall back to server-side media_progression if local is absent
    if (localMs > 0) {
      setState(() => _savedPosition = Duration(milliseconds: localMs));
    } else if (_audioAttachments.isNotEmpty && _audioAttachments.first.mediaProgression > 0) {
      setState(() => _savedPosition = Duration(seconds: _audioAttachments.first.mediaProgression));
    }
  }

  Future<void> _saveProgress() async {
    if (_activeUrl == null || _position == Duration.zero) return;
    await _storage.write(
      key: _progressKey(),
      value: _position.inMilliseconds.toString(),
    );
    // Sync with Miniflux server
    final activeAttachment = _activeAttachmentID == null
        ? null
        : _audioAttachments
            .where((a) => a.attachmentID == _activeAttachmentID)
            .fold<Attachment?>(null, (prev, e) => prev ?? e);
    if (activeAttachment != null) {
      syncMediaProgression(widget.appState, widget.news.newsID, activeAttachment.attachmentID, _position.inSeconds)
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
    final url = downloadedPath != null ? Uri.file(downloadedPath).toString() : attachment.attachmentURL;
    if (url.isEmpty) return;

    if (_activeUrl == url && _playerState.playing) {
      await _audioHandler!.pause();
      await _saveProgress();
      return;
    }
    if (_activeUrl == url && !_playerState.playing && _playerState.processingState != ProcessingState.completed) {
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
      initialPosition: seekTarget != null && seekTarget > Duration.zero ? seekTarget : null,
    );
    await _audioHandler!.play();
    if (seekTarget != null && seekTarget > Duration.zero && mounted && !_isDisposed) {
      setState(() => _savedPosition = null);
    }
  }

  Future<void> _stop() async {
    if (_audioHandler == null) return;
    await _saveProgress();
    await _audioHandler!.stop();
    _sleepTimer?.cancel();
    if (!mounted || _isDisposed) return;
    setState(() {
      _activeUrl = null;
      _activeAttachmentID = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isLoading = false;
      _sleepTimerEnabled = false;
      _sleepTimerEndAt = null;
    });
  }

  String _formatSleepTimerLabel() {
    if (!_sleepTimerEnabled || _sleepTimerEndAt == null) {
      return AppLocalizations.of(context)!.sleepTimerOff;
    }

    final remaining = _sleepTimerEndAt!.difference(DateTime.now());
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

  Future<void> _seekToChapter(Attachment attachment, AudioChapter chapter) async {
    if (_audioHandler == null) return;

    final downloadedPath = _downloadedPaths[attachment.attachmentID];
    final url = downloadedPath != null ? Uri.file(downloadedPath).toString() : attachment.attachmentURL;
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

  Future<MediaItem> _buildMediaItem(Attachment attachment) async {
    final parsedUri = Uri.tryParse(attachment.attachmentURL);
    final fallbackMediaName = parsedUri != null && parsedUri.pathSegments.isNotEmpty
        ? parsedUri.pathSegments.last
        : attachment.attachmentMimeType;
    final title = _audioAttachments.length == 1 ? widget.news.title : fallbackMediaName;
    Uri? artworkUri;

    // Try to extract album art from ID3 tags
    Uint8List? id3ImageBytes;
    final downloadedPath = _downloadedPaths[attachment.attachmentID];
    if (downloadedPath != null && downloadedPath.isNotEmpty) {
      // Try local file first
      id3ImageBytes = await AudioDownloadService.extractAlbumArtFromFile(downloadedPath);
    }
    id3ImageBytes ??= await AudioDownloadService.extractAlbumArtFromUrl(attachment.attachmentURL);

    // Use ID3 image if found, otherwise fall back to attachment image
    if (id3ImageBytes != null && id3ImageBytes.isNotEmpty) {
      // Create data URI from image bytes
      final base64Image = base64Encode(id3ImageBytes);
      artworkUri = Uri.dataFromString(
        'data:image/jpeg;base64,$base64Image',
        mimeType: 'image/jpeg',
      );
    } else {
      // Fall back to original image extraction logic
      final imageAttachment = widget.news.getFirstImageAttachment();
      artworkUri = imageAttachment.attachmentID != -1 ? Uri.tryParse(imageAttachment.attachmentURL) : null;
      artworkUri ??= _defaultArtworkUri ?? await AudioDownloadService.getDefaultArtworkUri();
      _defaultArtworkUri ??= artworkUri;
    }

    return MediaItem(
      id: attachment.attachmentURL,
      title: title,
      artist: widget.news.feedTitle,
      album: widget.news.feedTitle,
      artUri: artworkUri,
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

    return Column(
      children: _audioAttachments.map((attachment) {
        final isActive = _activeAttachmentID == attachment.attachmentID;
        final isPlaying = isActive && _playerState.playing;
        final isPaused = isActive && !_playerState.playing && _playerState.processingState != ProcessingState.idle;
        final isStopped = !isActive || _playerState.processingState == ProcessingState.idle;
        final isDownloaded = _downloadedPaths.containsKey(attachment.attachmentID);
        final isDownloading = _downloadingAttachmentIDs.contains(attachment.attachmentID);
        final isLoadingChapters = _loadingChapterAttachmentIDs.contains(attachment.attachmentID);
        final chapters = _chaptersByAttachmentID[attachment.attachmentID] ?? const <AudioChapter>[];

        final parsedUri = Uri.tryParse(attachment.attachmentURL);
        final fallbackMediaName = parsedUri != null && parsedUri.pathSegments.isNotEmpty
            ? parsedUri.pathSegments.last
            : attachment.attachmentMimeType;
        final mediaName = _audioAttachments.length == 1 ? widget.news.title : fallbackMediaName;
        final chapterListHeight = chapters.length > 4 ? 224.0 : chapters.length * 56.0;
        final chapterScrollController = _chapterControllerFor(attachment.attachmentID);

        final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
        final currentMs = isActive ? _position.inMilliseconds.toDouble().clamp(0.0, maxMs) : 0.0;
        // Show saved position in time label before playback starts
        final displayPosition = isActive ? _position : (_savedPosition ?? Duration.zero);

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
                    Icon(Icons.headphones, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mediaName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      color: Theme.of(context).colorScheme.primary,
                      tooltip: isDownloaded
                          ? AppLocalizations.of(context)!.downloaded
                          : AppLocalizations.of(context)!.downloadAudio,
                      onPressed: isDownloaded || isDownloading ? null : () => _downloadAudio(attachment),
                      icon: isDownloading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                              ),
                            )
                          : Icon(
                              isDownloaded ? Icons.download_done : Icons.download,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      iconSize: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Progress slider
                Slider(
                  value: currentMs,
                  max: maxMs,
                  onChanged: isActive
                      ? (value) async {
                          await _audioHandler!.seek(Duration(milliseconds: value.toInt()));
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
                        isActive && _duration > Duration.zero ? _formatDuration(_duration) : '--:--',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    AppLocalizations.of(context)!.chapters,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Text(AppLocalizations.of(context)!.loadingChapters),
                          ],
                        ),
                      )
                    else if (chapters.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context)!.noChaptersFound,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: chapterListHeight,
                        child: Scrollbar(
                          controller: chapterScrollController,
                          child: ListView.builder(
                            controller: chapterScrollController,
                            primary: false,
                            padding: EdgeInsets.zero,
                            itemCount: chapters.length,
                            itemBuilder: (context, index) {
                              final chapter = chapters[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  chapter.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(_formatChapterStart(chapter.start)),
                                onTap: () => _seekToChapter(attachment, chapter),
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
                  title: Text(
                    AppLocalizations.of(context)!.advancedSettings,
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
                            '${AppLocalizations.of(context)!.speed}: ${_playbackSpeed.toStringAsFixed(1)}x (${_formatSignedAdjustment(_playbackSpeed - 1.0)})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: (_playbackSpeed - 1.0).clamp(-0.5, 3.0),
                      min: -0.5,
                      max: 3.0,
                      divisions: 35,
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
                        Switch.adaptive(
                          value: _sleepTimerEnabled,
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
                            AppLocalizations.of(context)!.interval,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        DropdownButton<int>(
                          value: _sleepTimerMinutes,
                          onChanged: (value) {
                            if (value != null) {
                              _updateSleepTimerMinutes(value);
                            }
                          },
                          items: _sleepTimerMinuteOptions
                              .map((minutes) => DropdownMenuItem<int>(
                                    value: minutes,
                                    child: Text('$minutes ${AppLocalizations.of(context)!.minutes}'),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),

                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Rewind 30s
                    IconButton(
                      tooltip: '-30s',
                      onPressed: isActive ? () => _seek(const Duration(seconds: -30)) : null,
                      icon: const Icon(Icons.replay_30),
                      iconSize: 32,
                    ),

                    const SizedBox(width: 8),

                    // Play / Pause / Resume
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
                                ? AppLocalizations.of(context)!.pause
                                : isPaused
                                    ? AppLocalizations.of(context)!.resume
                                    : AppLocalizations.of(context)!.play,
                            onPressed: () => _play(attachment),
                            icon: Icon(
                              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            iconSize: 56,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Stop
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.stop,
                      onPressed: isActive && !isStopped ? _stop : null,
                      icon: const Icon(Icons.stop_circle_outlined),
                      iconSize: 32,
                    ),

                    const SizedBox(width: 8),

                    // Forward 30s
                    IconButton(
                      tooltip: '+30s',
                      onPressed: isActive ? () => _seek(const Duration(seconds: 30)) : null,
                      icon: const Icon(Icons.forward_30),
                      iconSize: 32,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
