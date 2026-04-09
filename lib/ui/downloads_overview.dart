import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
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
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait([_downloadsFuture, _totalSizeFuture]);
  }

  Future<void> _deleteItem(DownloadedAudioInfo item) async {
    await AudioDownloadService.deleteDownloadedAudio(item.attachmentID);
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
        title: Text(AppLocalizations.of(context)!.settingAudioDownloadsTitle),
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
          Text(progress.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: totalSize == 0 ? null : _deleteAll,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(AppLocalizations.of(context)!.downloadsManagerClearAll),
                  ),
                ),
              ],
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
    return ListTile(
      leading: const Icon(Icons.audio_file_outlined),
      title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${AudioDownloadService.formatBytes(item.fileSize)} • $formattedDate'),
      trailing: IconButton(
        onPressed: () => _deleteItem(item),
        icon: const Icon(Icons.delete_outline),
        tooltip: AppLocalizations.of(context)!.downloadsManagerDeleteTitle,
      ),
    );
  }
}
