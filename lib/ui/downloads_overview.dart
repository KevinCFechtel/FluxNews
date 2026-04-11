import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/audio_download_service.dart';
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
  late Future<int> _totalSizeFuture;
  StreamSubscription<void>? _downloadedAudiosChangedSubscription;
  final Map<int, Future<String?>> _titleFutureByAttachmentId = {};
  final Map<int, Future<String?>> _feedTitleFutureByAttachmentId = {};

  @override
  void initState() {
    super.initState();
    _reload();
    _downloadedAudiosChangedSubscription = AudioDownloadService.downloadedAudiosChangedStream.listen((_) {
      if (!mounted) return;
      setState(_reload);
    });
  }

  @override
  void dispose() {
    _downloadedAudiosChangedSubscription?.cancel();
    super.dispose();
  }

  void _reload() {
    _downloadsFuture = AudioDownloadService.getDownloadedAudios();
    _totalSizeFuture = AudioDownloadService.getDownloadedAudioSizeInBytes();
    _titleFutureByAttachmentId.clear();
    _feedTitleFutureByAttachmentId.clear();
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

  Future<String?> _getFeedTitleByAttachmentId(int attachmentID) async {
    if (attachmentID < 0) {
      return null;
    }

    final appState = context.read<FluxNewsState>();
    final feedTitle = await queryFeedTitleByAttachmentId(appState, attachmentID);
    if (feedTitle != null && feedTitle.isNotEmpty) {
      AudioDownloadService.cacheDownloadFeedTitle(attachmentID, feedTitle);
    }
    return feedTitle;
  }

  Future<String?> _feedTitleFutureForAttachmentId(int attachmentID) {
    return _feedTitleFutureByAttachmentId.putIfAbsent(
      attachmentID,
      () => _getFeedTitleByAttachmentId(attachmentID),
    );
  }

  Future<News?> _getNewsByAttachmentId(int attachmentID) async {
    if (attachmentID < 0) {
      return null;
    }

    final appState = context.read<FluxNewsState>();
    return queryNewsByAttachmentId(appState, attachmentID);
  }

  Future<void> _openDownloadedItem(DownloadedAudioInfo item) async {
    final news = await _getNewsByAttachmentId(item.attachmentID);
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
    await Future.wait([_downloadsFuture, _totalSizeFuture]);
  }

  Future<void> _deleteItem(DownloadedAudioInfo item) async {
    await AudioDownloadService.deleteDownloadedAudioByStorageId(item.storageID);
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.downloadsManagerDeletedSnackbar)),
    );
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.downloadsManagerClearAllTitle),
            content: Text(AppLocalizations.of(context)!.downloadsManagerClearAllMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(AppLocalizations.of(context)!.delete),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await AudioDownloadService.deleteAllDownloadedAudios();
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.downloadsManagerClearedSnackbar)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(AppLocalizations.of(context)!.audioDownloadsSettings),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildRunningDownloadsCard(),
            const SizedBox(height: 12),
            _buildStorageCard(),
            const SizedBox(height: 12),
            _buildDownloadedList(),
            const SizedBox(height: 12),
            _buildDeleteAllCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildRunningDownloadsCard() {
    return StreamBuilder<List<AudioDownloadProgress>>(
      initialData: AudioDownloadService.getActiveDownloadsSnapshot(),
      stream: AudioDownloadService.activeDownloadsStream,
      builder: (context, snapshot) {
        final activeDownloads = snapshot.data ?? const <AudioDownloadProgress>[];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.runningDownloads, style: Theme.of(context).textTheme.titleMedium),
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
    final progressValue = progress.progress;
    final subtitle = progress.totalBytes > 0
        ? '${AudioDownloadService.formatBytes(progress.receivedBytes)} ${AppLocalizations.of(context)!.from} ${AudioDownloadService.formatBytes(progress.totalBytes)}'
        : '${AudioDownloadService.formatBytes(progress.receivedBytes)} ${AppLocalizations.of(context)!.loaded}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
          LinearProgressIndicator(value: progressValue),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildStorageCard() {
    return FutureBuilder<int>(
      future: _totalSizeFuture,
      builder: (context, snapshot) {
        final totalSize = snapshot.data ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.downloadedData, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text('${AppLocalizations.of(context)!.totalStorage}: ${AudioDownloadService.formatBytes(totalSize)}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeleteAllCard() {
    return FutureBuilder<int>(
      future: _totalSizeFuture,
      builder: (context, snapshot) {
        final totalSize = snapshot.data ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: totalSize == 0 ? null : _deleteAll,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(AppLocalizations.of(context)!.downloadsManagerClearAll),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadedList() {
    return FutureBuilder<List<DownloadedAudioInfo>>(
      future: _downloadsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(AppLocalizations.of(context)!.loadDownloadedDataError),
            ),
          );
        }

        final downloads = snapshot.data ?? const <DownloadedAudioInfo>[];
        if (downloads.isEmpty) {
          return Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(AppLocalizations.of(context)!.noAudioDownloads),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(AppLocalizations.of(context)!.fileList, style: Theme.of(context).textTheme.titleMedium),
                ),
                ...downloads.map((item) => _buildDownloadedItem(item, context)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadedItem(DownloadedAudioInfo item, BuildContext context) {
    final formattedDate = context.read<FluxNewsState>().dateFormat.format(item.downloadedAt.toLocal());
    return Dismissible(
      key: ValueKey(item.storageID),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
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
        );
      },
      onDismissed: (_) {
        _deleteItem(item);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      child: ListTile(
        title: FutureBuilder<String?>(
          future: _titleFutureForAttachmentId(item.attachmentID),
          builder: (context, snapshot) {
            final title = snapshot.data;
            return Text(
              title != null && title.isNotEmpty ? title : item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        subtitle: FutureBuilder<String?>(
          future: _feedTitleFutureForAttachmentId(item.attachmentID),
          builder: (context, snapshot) {
            final feedTitle = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (feedTitle != null && feedTitle.isNotEmpty)
                  Text(
                    feedTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text('${AudioDownloadService.formatBytes(item.fileSize)} • $formattedDate'),
              ],
            );
          },
        ),
        onTap: () => _openDownloadedItem(item),
      ),
    );
  }
}
