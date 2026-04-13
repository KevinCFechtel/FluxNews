import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';

class DownloadStorageSettings extends StatefulWidget {
  const DownloadStorageSettings({super.key});

  @override
  State<DownloadStorageSettings> createState() => _DownloadStorageSettingsState();
}

class _DownloadStorageSettingsState extends State<DownloadStorageSettings> {
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
        title: Text(
          AppLocalizations.of(context)!.downloadedData,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            FutureBuilder<List<DownloadedAudioInfo>>(
              future: _downloadsFuture,
              builder: (context, snapshot) {
                final count = (snapshot.data ?? const <DownloadedAudioInfo>[]).length;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLocalizations.of(context)!.downloadedData,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('$count ${AppLocalizations.of(context)!.fileList}'),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            FutureBuilder<int>(
              future: _totalSizeFuture,
              builder: (context, snapshot) {
                final totalSize = snapshot.data ?? 0;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLocalizations.of(context)!.totalStorage,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          AudioDownloadService.formatBytes(totalSize),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            FutureBuilder<int>(
              future: _totalSizeFuture,
              builder: (context, snapshot) {
                final totalSize = snapshot.data ?? 0;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: totalSize == 0 ? null : _deleteAll,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: Text(AppLocalizations.of(context)!.downloadsManagerClearAll),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
