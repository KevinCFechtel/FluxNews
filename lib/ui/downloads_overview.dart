import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/audioplayer.dart';
import 'package:provider/provider.dart';

class DownloadsOverview extends StatefulWidget {
  const DownloadsOverview({super.key});

  @override
  State<DownloadsOverview> createState() => _DownloadsOverviewState();
}

class _DownloadsOverviewState extends State<DownloadsOverview> {
  late Future<List<DownloadedAudioInfo>> _downloadsFuture;
  StreamSubscription<void>? _downloadedAudiosChangedSubscription;
  FluxNewsAudioHandler? _audioHandler;
  StreamSubscription<dynamic>? _mediaItemSubscription;
  final Map<int, Future<String?>> _titleFutureByAttachmentId = {};
  final Map<int, Future<News?>> _newsFutureByAttachmentId = {};
  final Set<String> _dismissedStorageIds = {};

  @override
  void initState() {
    super.initState();
    _reload();
    _downloadedAudiosChangedSubscription = AudioDownloadService.downloadedAudiosChangedStream.listen((_) {
      if (!mounted) return;
      setState(_reload);
    });
    initFluxNewsAudioHandler().then((handler) {
      if (!mounted) return;
      setState(() => _audioHandler = handler);
      _mediaItemSubscription = handler.mediaItem.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _downloadedAudiosChangedSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    super.dispose();
  }

  void _reload() {
    _downloadsFuture = AudioDownloadService.getDownloadedAudios();
    _titleFutureByAttachmentId.clear();
    _newsFutureByAttachmentId.clear();
    _dismissedStorageIds.clear();
  }

  Future<String?> _getNewsTitleByAttachmentId(int attachmentID) async {
    if (attachmentID < 0) {
      return null;
    }

    final appState = context.read<FluxNewsState>();
    final title = await queryNewsTitleByAttachmentId(appState, attachmentID);
    if (title != null && title.isNotEmpty) {
      AudioDownloadService.cacheDownloadTitle(attachmentID, title);
    }
    return title;
  }

  Future<String?> _titleFutureForAttachmentId(int attachmentID) {
    return _titleFutureByAttachmentId.putIfAbsent(
      attachmentID,
      () => _getNewsTitleByAttachmentId(attachmentID),
    );
  }

  Future<News?> _getNewsByAttachmentId(int attachmentID) async {
    if (attachmentID < 0) {
      return null;
    }

    final appState = context.read<FluxNewsState>();
    final news = await queryNewsByAttachmentId(appState, attachmentID);
    if (news?.feedTitle.isNotEmpty == true) {
      AudioDownloadService.cacheDownloadFeedTitle(attachmentID, news!.feedTitle);
    }
    return news;
  }

  Future<News?> _newsFutureForAttachmentId(int attachmentID) {
    return _newsFutureByAttachmentId.putIfAbsent(
      attachmentID,
      () => _getNewsByAttachmentId(attachmentID),
    );
  }

  Future<void> _openDownloadedItem(DownloadedAudioInfo item) async {
    final news = await _newsFutureForAttachmentId(item.attachmentID);
    if (!mounted) return;

    if (news == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.loadDownloadedDataError)),
      );
      return;
    }

    final appState = context.read<FluxNewsState>();
    appState.setActiveAudioNews(news);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewsAudioPlayerScreen(news: news),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _downloadsFuture;
  }

  Future<void> _deleteItem(DownloadedAudioInfo item) async {
    await AudioDownloadService.deleteDownloadedAudioByStorageId(item.storageID);
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.downloadsManagerDeletedSnackbar)),
    );
  }

  Future<void> _dismissAndDeleteItem(DownloadedAudioInfo item) async {
    setState(() {
      _dismissedStorageIds.add(item.storageID);
    });

    try {
      await _deleteItem(item);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dismissedStorageIds.remove(item.storageID);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.loadDownloadedDataError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    FluxNewsState appState = context.watch<FluxNewsState>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(AppLocalizations.of(context)!.audioDownloadsSettings, style: theme.textTheme.titleLarge),
      ),
      body: FutureBuilder<List<DownloadedAudioInfo>>(
        future: _downloadsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(AppLocalizations.of(context)!.loadDownloadedDataError),
              ),
            );
          }

          final downloads = snapshot.data ?? const <DownloadedAudioInfo>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = appState.isTablet ? 24.0 : 12.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: appState.isTablet ? 1100 : double.infinity),
                    child: ListView(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
                      children: [
                        _buildRunningDownloadsCard(),
                        const SizedBox(height: 16),
                        _buildDownloadedList(downloads, appState.isTablet),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirmDeleteItem(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.downloadsManagerDeleteTitle),
            content: Text(AppLocalizations.of(context)!.downloadsManagerDeleteMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(AppLocalizations.of(context)!.delete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildRunningDownloadsCard() {
    final theme = Theme.of(context);
    return StreamBuilder<List<AudioDownloadProgress>>(
      initialData: AudioDownloadService.getActiveDownloadsSnapshot(),
      stream: AudioDownloadService.activeDownloadsStream,
      builder: (context, snapshot) {
        final activeDownloads = snapshot.data ?? const <AudioDownloadProgress>[];

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.downloading_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.runningDownloads, style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                if (activeDownloads.isEmpty)
                  Text(AppLocalizations.of(context)!.noActiveDownloads)
                else
                  ...activeDownloads.map(_buildActiveDownloadTile),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveDownloadTile(AudioDownloadProgress progress) {
    final theme = Theme.of(context);
    final progressValue = progress.progress;
    final subtitle = progress.totalBytes > 0
        ? '${AudioDownloadService.formatBytes(progress.receivedBytes)} ${AppLocalizations.of(context)!.from} ${AudioDownloadService.formatBytes(progress.totalBytes)}'
        : '${AudioDownloadService.formatBytes(progress.receivedBytes)} ${AppLocalizations.of(context)!.loaded}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String?>(
              future: _titleFutureForAttachmentId(progress.attachmentID),
              builder: (context, snapshot) {
                final title = snapshot.data;
                return Text(
                  title != null && title.isNotEmpty ? title : progress.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progressValue, minHeight: 6),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadedList(List<DownloadedAudioInfo> downloads, bool isTablet) {
    final theme = Theme.of(context);
    final visibleDownloads = downloads.where((item) => !_dismissedStorageIds.contains(item.storageID)).toList();

    if (visibleDownloads.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(AppLocalizations.of(context)!.noAudioDownloads),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Row(
                children: [
                  Icon(Icons.library_music_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(AppLocalizations.of(context)!.fileList, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    visibleDownloads.length.toString(),
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            if (isTablet)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleDownloads.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.7,
                  mainAxisExtent: 120,
                ),
                itemBuilder: (context, index) => _buildDownloadedItemCard(visibleDownloads[index]),
              )
            else
              ...visibleDownloads.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildDownloadedItemCard(item),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadedItemCard(DownloadedAudioInfo item) {
    final theme = Theme.of(context);
    final appState = context.watch<FluxNewsState>();
    final formattedDate = context.read<FluxNewsState>().dateFormat.format(item.downloadedAt.toLocal());
    return Dismissible(
      key: ValueKey(item.storageID),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDeleteItem(context),
      onDismissed: (_) => _dismissAndDeleteItem(item),
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      child: Card(
        color: theme.colorScheme.surfaceContainerHighest,
        shadowColor: Colors.black,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openDownloadedItem(item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<String?>(
                        future: _titleFutureForAttachmentId(item.attachmentID),
                        builder: (context, snapshot) {
                          final title = snapshot.data;
                          return Text(
                            title != null && title.isNotEmpty ? title : item.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final currentUrl = _audioHandler?.currentUrl;
                        final fileUri = Uri.file(item.filePath).toString();
                        final isNowPlaying = currentUrl == fileUri;
                        if (!isNowPlaying) {
                          return const SizedBox.shrink();
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: 14,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.of(context)!.play,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FutureBuilder<News?>(
                  future: _newsFutureForAttachmentId(item.attachmentID),
                  builder: (context, snapshot) {
                    final news = snapshot.data;
                    final feedTitle = news?.feedTitle;
                    final meta = news != null && news.getFormattedPlaybackTime().isNotEmpty
                        ? '${news.getFormattedPlaybackTime()} • $formattedDate'
                        : formattedDate;
                    return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (appState.showFeedIcons && news != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(0, 0, 6, 0),
                                  child: news.getFeedIcon(16.0, context),
                                ),
                              Expanded(
                                child: Text(
                                  feedTitle != null && feedTitle.isNotEmpty ? feedTitle : meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          feedTitle != null && feedTitle.isNotEmpty
                              ? Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                )
                              : const SizedBox.shrink(),
                        ]);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
