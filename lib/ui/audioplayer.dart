import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
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
  late final AudioPlayer _player;
  late final List<Attachment> _audioAttachments;
  final _storage = const sec_store.FlutterSecureStorage();
  Timer? _autoSaveTimer;

  String? _activeUrl;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _savedPosition; // loaded from storage, seek target on first play
  PlayerState _playerState = PlayerState.stopped;
  bool _isLoading = false;

  String _progressKey() => 'audio_progress_${widget.news.newsID}';

  @override
  void initState() {
    super.initState();
    _audioAttachments = widget.news.getAudioAttachments();
    _player = AudioPlayer();

    _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });

    _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playerState = state;
        if (state == PlayerState.playing) _isLoading = false;
      });
    });

    _player.onPlayerComplete.listen((event) {
      if (!mounted) return;
      // Clear saved progress and reset server progression when fully played
      _storage.delete(key: _progressKey());
      final completedAttachment =
          _audioAttachments.where((a) => a.attachmentURL == _activeUrl).fold<Attachment?>(null, (prev, e) => prev ?? e);
      if (completedAttachment != null) {
        syncMediaProgression(widget.appState, widget.news.newsID, completedAttachment.attachmentID, 0).ignore();
      }
      _autoSaveTimer?.cancel();
      setState(() {
        _position = Duration.zero;
        _savedPosition = null;
        _activeUrl = null;
      });
    });

    _loadProgress();
    _startAutoSaveTimer();
  }

  @override
  void dispose() {
    _saveProgress();
    _autoSaveTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ---- Progress persistence ----

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_playerState == PlayerState.playing) {
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
    final activeAttachment =
        _audioAttachments.where((a) => a.attachmentURL == _activeUrl).fold<Attachment?>(null, (prev, e) => prev ?? e);
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
    final url = attachment.attachmentURL;
    if (url.isEmpty) return;

    if (_activeUrl == url && _playerState == PlayerState.playing) {
      await _player.pause();
      await _saveProgress();
      return;
    }
    if (_activeUrl == url && _playerState == PlayerState.paused) {
      await _player.resume();
      return;
    }

    final seekTarget = _savedPosition;
    setState(() {
      _isLoading = true;
      _activeUrl = url;
      _position = seekTarget ?? Duration.zero;
      _duration = Duration.zero;
    });
    await _player.play(UrlSource(url));
    // Seek to saved position after playback starts
    if (seekTarget != null && seekTarget > Duration.zero) {
      await _player.seek(seekTarget);
      setState(() => _savedPosition = null);
    }
    // Fallback: reset loading if listener hasn't fired
    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _stop() async {
    await _saveProgress();
    await _player.stop();
    setState(() {
      _activeUrl = null;
      _position = Duration.zero;
    });
  }

  Future<void> _seek(Duration offset) async {
    final newPosition = _position + offset;
    final clamped = newPosition < Duration.zero
        ? Duration.zero
        : newPosition > _duration && _duration > Duration.zero
            ? _duration
            : newPosition;
    await _player.seek(clamped);
  }

  @override
  Widget build(BuildContext context) {
    if (_audioAttachments.isEmpty) return const SizedBox.shrink();

    return Column(
      children: _audioAttachments.map((attachment) {
        final isActive = _activeUrl == attachment.attachmentURL;
        final isPlaying = isActive && _playerState == PlayerState.playing;
        final isPaused = isActive && _playerState == PlayerState.paused;
        final isStopped = !isActive || _playerState == PlayerState.stopped;

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
                  ],
                ),
                const SizedBox(height: 12),

                // Progress slider
                Slider(
                  value: currentMs,
                  max: maxMs,
                  onChanged: isActive
                      ? (value) async {
                          await _player.seek(Duration(milliseconds: value.toInt()));
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
