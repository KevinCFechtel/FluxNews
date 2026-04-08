import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

class NewsAudioPlayerScreen extends StatelessWidget {
  const NewsAudioPlayerScreen({super.key, required this.news});

  final News news;

  @override
  Widget build(BuildContext context) {
    final audioAttachments = news.getAudioAttachments();
    final appState = Provider.of<FluxNewsState>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(news.title),
      ),
      body: SafeArea(
        child: audioAttachments.isEmpty
            ? const Center(
                child: Text('Keine Audio-Datei vorhanden.'),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      news.feedTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      news.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    NewsAudioPlayer(news: news, appState: appState),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: news.getFullRenderedWidget(appState, context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
  FluxNewsAudioHandler? _audioHandler;
  late final List<Attachment> _audioAttachments;
  final _storage = const sec_store.FlutterSecureStorage();
  Timer? _autoSaveTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  final Map<int, String> _downloadedPaths = {};
  final Map<int, List<AudioChapter>> _chaptersByAttachmentID = {};
  final Set<int> _downloadingAttachmentIDs = {};
  Uri? _defaultArtworkUri;

  String? _activeUrl;
  int? _activeAttachmentID;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _savedPosition; // loaded from storage, seek target on first play
  PlayerState _playerState = PlayerState(false, ProcessingState.idle);
  bool _isLoading = false;

  String _progressKey() => 'audio_progress_${widget.news.newsID}';

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
    if (!mounted) return;
    setState(() => _defaultArtworkUri = artworkUri);
  }

  Future<void> _initializeDownloadedAudioState() async {
    final downloadedPaths = await AudioDownloadService.loadDownloadedPathsForAttachments(
        _audioAttachments, widget.appState.imageCacheDurationDays);
    _downloadedPaths
      ..clear()
      ..addAll(downloadedPaths);
    for (final entry in downloadedPaths.entries) {
      await _loadChaptersForAttachment(entry.key, entry.value);
    }
    _syncActiveAttachment();
    if (mounted) {
      setState(() {});
    }
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

    setState(() {
      _activeAttachmentID = matchedAttachment?.attachmentID;
    });
  }

  Future<void> _loadChaptersForAttachment(int attachmentID, String filePath) async {
    final chapters = await AudioDownloadService.readChapters(filePath);
    _chaptersByAttachmentID[attachmentID] = chapters;
  }

  Future<void> _downloadAudio(Attachment attachment) async {
    if (_downloadingAttachmentIDs.contains(attachment.attachmentID)) return;
    setState(() => _downloadingAttachmentIDs.add(attachment.attachmentID));
    try {
      final filePath = await AudioDownloadService.downloadAttachment(attachment,
          onlyOnWifi: widget.appState.downloadAudioOnlyOnWifi);
      if (filePath != null) {
        _downloadedPaths[attachment.attachmentID] = filePath;
        await _loadChaptersForAttachment(attachment.attachmentID, filePath);
      } else if (widget.appState.downloadAudioOnlyOnWifi) {
        final isWifiConnected = await AudioDownloadService.isWifiConnected();
        if (!isWifiConnected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download nur ueber WLAN erlaubt. Bitte WLAN aktivieren.'),
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
    if (!mounted) return;

    _audioHandler = audioHandler;
    _activeUrl = audioHandler.currentUrl;
    _position = audioHandler.position;
    _duration = audioHandler.duration ?? Duration.zero;
    _playerState = audioHandler.playerState;
    _isLoading = _playerState.processingState == ProcessingState.loading ||
        _playerState.processingState == ProcessingState.buffering;
    _syncActiveAttachment(mediaItemId: audioHandler.mediaItem.value?.id);

    _positionSubscription = audioHandler.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });

    _durationSubscription = audioHandler.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration ?? Duration.zero);
    });

    _playerStateSubscription = audioHandler.playerStateStream.listen((state) {
      if (!mounted) return;
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
      if (!mounted) return;
      _syncActiveAttachment(mediaItemId: item?.id);
    });

    setState(() {});
  }

  @override
  void dispose() {
    _saveProgress();
    _autoSaveTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handlePlaybackCompleted() async {
    await _storage.delete(key: _progressKey());
    final completedAttachment = _activeAttachmentID == null
        ? null
        : _audioAttachments
            .where((a) => a.attachmentID == _activeAttachmentID)
            .fold<Attachment?>(null, (prev, e) => prev ?? e);
    if (completedAttachment != null) {
      syncMediaProgression(widget.appState, widget.news.newsID, completedAttachment.attachmentID, 0).ignore();
    }
    _autoSaveTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _position = Duration.zero;
      _savedPosition = null;
      _activeUrl = null;
      _activeAttachmentID = null;
      _isLoading = false;
    });
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
    if (seekTarget != null && seekTarget > Duration.zero) {
      setState(() => _savedPosition = null);
    }
  }

  Future<void> _stop() async {
    if (_audioHandler == null) return;
    await _saveProgress();
    await _audioHandler!.stop();
    setState(() {
      _activeUrl = null;
      _activeAttachmentID = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isLoading = false;
    });
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
    final imageAttachment = widget.news.getFirstImageAttachment();
    Uri? artworkUri;

    if (Platform.isIOS) {
      artworkUri = _defaultArtworkUri ?? await AudioDownloadService.getDefaultArtworkUri();
      _defaultArtworkUri ??= artworkUri;
    } else {
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
        final chapters = _chaptersByAttachmentID[attachment.attachmentID] ?? const <AudioChapter>[];

        final parsedUri = Uri.tryParse(attachment.attachmentURL);
        final fallbackMediaName = parsedUri != null && parsedUri.pathSegments.isNotEmpty
            ? parsedUri.pathSegments.last
            : attachment.attachmentMimeType;
        final mediaName = _audioAttachments.length == 1 ? widget.news.title : fallbackMediaName;

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
                      tooltip: isDownloaded ? 'Heruntergeladen' : 'Audio herunterladen',
                      onPressed: isDownloaded || isDownloading ? null : () => _downloadAudio(attachment),
                      icon: isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(isDownloaded ? Icons.download_done : Icons.download),
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

                if (chapters.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      'Kapitel',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    children: chapters
                        .map(
                          (chapter) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              chapter.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(_formatChapterStart(chapter.start)),
                            onTap: () => _seekToChapter(attachment, chapter),
                          ),
                        )
                        .toList(),
                  ),
                ],

                const SizedBox(height: 4),

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
                                ? 'Pause'
                                : isPaused
                                    ? 'Weiter'
                                    : 'Play',
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
                      tooltip: 'Stop',
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
