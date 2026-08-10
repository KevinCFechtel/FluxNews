import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:flux_news/ui/settings/adaptive_settings_scaffold.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

class DownloadStorageSettings extends StatefulWidget {
  const DownloadStorageSettings({super.key});

  @override
  State<DownloadStorageSettings> createState() =>
      _DownloadStorageSettingsState();
}

class _DownloadStorageSettingsState extends State<DownloadStorageSettings> {
  late Future<List<DownloadedAudioInfo>> _downloadsFuture;
  late Future<int> _totalSizeFuture;
  StreamSubscription<void>? _downloadedAudiosChangedSubscription;

  @override
  void initState() {
    super.initState();
    _reload();
    _downloadedAudiosChangedSubscription =
        AudioDownloadService.downloadedAudiosChangedStream.listen((_) {
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
    final confirmed = Platform.isIOS
        ? await showAdaptiveSettingsGlassDialog<bool>(
              context: context,
              title:
                  AppLocalizations.of(context)!.downloadsManagerClearAllTitle,
              message:
                  AppLocalizations.of(context)!.downloadsManagerClearAllMessage,
              settings: iosLiquidGlassMenuSettings(
                context,
                useClearEffect:
                    context.read<FluxNewsState>().iosClearLiquidGlass,
              ),
              quality: GlassQuality.standard,
              actions: [
                GlassDialogAction(
                  label: AppLocalizations.of(context)!.cancel,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                GlassDialogAction(
                  label: AppLocalizations.of(context)!.delete,
                  isDestructive: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ) ??
            false
        : await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(AppLocalizations.of(context)!
                    .downloadsManagerClearAllTitle),
                content: Text(AppLocalizations.of(context)!
                    .downloadsManagerClearAllMessage),
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
      SnackBar(
          content: Text(
              AppLocalizations.of(context)!.downloadsManagerClearedSnackbar)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsScaffold(
      title: AppLocalizations.of(context)!.downloadedData,
      useLargeTitle: true,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            AdaptiveSettingsGroup(
              children: [
                FutureBuilder<List<DownloadedAudioInfo>>(
                  future: _downloadsFuture,
                  builder: (context, snapshot) {
                    final count =
                        (snapshot.data ?? const <DownloadedAudioInfo>[]).length;
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.of(context)!.downloadedData,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                              '$count ${AppLocalizations.of(context)!.fileList}'),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(),
                FutureBuilder<int>(
                  future: _totalSizeFuture,
                  builder: (context, snapshot) {
                    final totalSize = snapshot.data ?? 0;
                    return Padding(
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
                    );
                  },
                ),
                const Divider(),
                FutureBuilder<int>(
                  future: _totalSizeFuture,
                  builder: (context, snapshot) {
                    final totalSize = snapshot.data ?? 0;
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Platform.isIOS
                            ? AdaptiveSettingsButton(
                                onPressed: totalSize == 0 ? null : _deleteAll,
                                isDestructive: true,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.delete_sweep_outlined),
                                    const SizedBox(width: 8),
                                    Text(AppLocalizations.of(context)!
                                        .downloadsManagerClearAll),
                                  ],
                                ),
                              )
                            : FilledButton.icon(
                                onPressed: totalSize == 0 ? null : _deleteAll,
                                icon: const Icon(Icons.delete_sweep_outlined),
                                label: Text(AppLocalizations.of(context)!
                                    .downloadsManagerClearAll),
                              ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
