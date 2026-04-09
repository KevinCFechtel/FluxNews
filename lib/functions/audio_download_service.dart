import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioChapter {
  const AudioChapter({
    required this.title,
    required this.start,
    this.end,
  });

  final String title;
  final Duration start;
  final Duration? end;
}

class AudioDownloadProgress {
  const AudioDownloadProgress({
    required this.attachmentID,
    required this.fileName,
    required this.receivedBytes,
    required this.totalBytes,
    required this.startedAt,
  });

  final int attachmentID;
  final String fileName;
  final int receivedBytes;
  final int totalBytes;
  final DateTime startedAt;

  double? get progress {
    if (totalBytes <= 0) return null;
    return receivedBytes / totalBytes;
  }
}

class DownloadedAudioInfo {
  const DownloadedAudioInfo({
    required this.storageID,
    required this.attachmentID,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.downloadedAt,
  });

  final String storageID;
  final int attachmentID;
  final String fileName;
  final String filePath;
  final int fileSize;
  final DateTime downloadedAt;
}

class AudioDownloadService {
  static const _storage = sec_store.FlutterSecureStorage();
  static const String _downloadPathKeyPrefix = FluxNewsState.downloadPathKeyPrefix;
  static const String _downloadPathByUrlKeyPrefix = FluxNewsState.downloadPathByUrlKeyPrefix;
  static const String _downloadTimestampKeyPrefix = FluxNewsState.downloadTimestampKeyPrefix;
  static const String _defaultArtworkAssetPath = FluxNewsState.defaultArtworkAssetPath;
  static const String _defaultArtworkFileName = FluxNewsState.defaultArtworkFileName;
  static final _activeDownloads = <int, AudioDownloadProgress>{};
  static final _activeDownloadsController = StreamController<List<AudioDownloadProgress>>.broadcast();
  static final _downloadedAudiosChangedController = StreamController<void>.broadcast();

  static String _downloadPathKey(int attachmentID) => '$_downloadPathKeyPrefix$attachmentID';
  static String _downloadPathByUrlKey(String attachmentURL) {
    final encoded = base64UrlEncode(utf8.encode(attachmentURL));
    return '$_downloadPathByUrlKeyPrefix$encoded';
  }

  static String _downloadTimestampKey(int attachmentID) => '$_downloadTimestampKeyPrefix$attachmentID';

  /// Extracts the numeric attachment ID encoded in the filename.
  /// File pattern: audio_[storageAttachmentId]_[epochMs].[ext]
  static int _attachmentIdFromFileName(String fileName) {
    try {
      final withoutPrefix = fileName.substring(FluxNewsState.audioFilePrefix.length);
      final underscore = withoutPrefix.indexOf('_');
      if (underscore < 0) return -1;
      return int.tryParse(withoutPrefix.substring(0, underscore)) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  static int _resolveStorageAttachmentId(Attachment attachment) {
    if (attachment.attachmentID >= 0) {
      return attachment.attachmentID;
    }
    if (attachment.newsID >= 0) {
      // Stable synthetic ID so fallback attachments do not collide at -1.
      return -(attachment.newsID + 1000000);
    }
    return attachment.attachmentID;
  }

  static Future<String?> _findCachedFileForStorageAttachmentId(int storageAttachmentId) async {
    final appSupport = await getApplicationSupportDirectory();
    final audioDirectory = Directory(p.join(appSupport.path, FluxNewsState.audioCachePath));
    if (!await audioDirectory.exists()) return null;

    final expectedPrefix = '${FluxNewsState.audioFilePrefix}${storageAttachmentId}_';
    File? newestMatch;
    DateTime? newestModified;

    await for (final entity in audioDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = p.basename(entity.path);
      if (!fileName.startsWith(expectedPrefix)) continue;

      final stat = await entity.stat();
      if (newestModified == null || stat.modified.isAfter(newestModified)) {
        newestMatch = entity;
        newestModified = stat.modified;
      }
    }

    return newestMatch?.path;
  }

  static Stream<List<AudioDownloadProgress>> get activeDownloadsStream => _activeDownloadsController.stream;
  static Stream<void> get downloadedAudiosChangedStream => _downloadedAudiosChangedController.stream;

  static List<AudioDownloadProgress> getActiveDownloadsSnapshot() {
    final downloads = _activeDownloads.values.toList();
    downloads.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return downloads;
  }

  static void _emitActiveDownloads() {
    if (_activeDownloadsController.isClosed) return;
    _activeDownloadsController.add(getActiveDownloadsSnapshot());
  }

  static void _emitDownloadedAudiosChanged() {
    if (_downloadedAudiosChangedController.isClosed) return;
    _downloadedAudiosChangedController.add(null);
  }

  static void _setActiveDownload(AudioDownloadProgress progress) {
    _activeDownloads[progress.attachmentID] = progress;
    _emitActiveDownloads();
  }

  static void _removeActiveDownload(int attachmentID) {
    _activeDownloads.remove(attachmentID);
    _emitActiveDownloads();
  }

  static Future<bool> _isWifiConnected() async {
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  static Future<bool> isWifiConnected() async {
    return _isWifiConnected();
  }

  static Future<Uri?> getDefaultArtworkUri() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final filePath = p.join(appSupport.path, _defaultArtworkFileName);
      final file = File(filePath);

      if (!await file.exists()) {
        final byteData = await rootBundle.load(_defaultArtworkAssetPath);
        await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      }

      return Uri.file(file.path);
    } catch (_) {
      return null;
    }
  }

  static Future<List<AudioChapter>> readChapters(String filePath, BuildContext context) async {
    final file = File(filePath);
    if (!await file.exists()) return const [];

    final raf = await file.open();
    try {
      final header = await raf.read(10);
      if (header.length < 10 || ascii.decode(header.sublist(0, 3), allowInvalid: true) != 'ID3') {
        return const [];
      }

      final version = header[3];
      final flags = header[5];
      final tagSize = _readSynchsafeInt(header, 6);
      if (tagSize <= 0) return const [];

      final tagData = await raf.read(tagSize);
      if (tagData.isEmpty) return const [];

      final chapters = <AudioChapter>[];
      var offset = 0;

      if ((flags & 0x40) != 0) {
        if (version == 3 && tagData.length >= 4) {
          offset = 4 + _readInt32(tagData, 0);
        } else if (version == 4 && tagData.length >= 4) {
          offset = _readSynchsafeInt(tagData, 0);
        }
      }

      while (offset + 10 <= tagData.length) {
        final frameId = ascii.decode(tagData.sublist(offset, offset + 4), allowInvalid: true);
        if (frameId.trim().isEmpty || frameId.codeUnits.every((unit) => unit == 0)) {
          break;
        }

        final frameSize = version == 4 ? _readSynchsafeInt(tagData, offset + 4) : _readInt32(tagData, offset + 4);
        if (frameSize <= 0 || offset + 10 + frameSize > tagData.length) {
          break;
        }

        if (frameId == 'CHAP') {
          if (context.mounted) {
            final chapter = _parseChapFrame(tagData.sublist(offset + 10, offset + 10 + frameSize), version, context);
            if (chapter != null) {
              chapters.add(chapter);
            }
          }
        }

        offset += 10 + frameSize;
      }

      chapters.sort((a, b) => a.start.compareTo(b.start));
      return chapters;
    } finally {
      await raf.close();
    }
  }

  static AudioChapter? _parseChapFrame(Uint8List data, int version, BuildContext context) {
    var offset = 0;
    while (offset < data.length && data[offset] != 0) {
      offset++;
    }
    if (offset + 17 > data.length) return null;

    offset += 1;
    final startMs = _readInt32(data, offset);
    final endMs = _readInt32(data, offset + 4);
    offset += 16;

    String? title;
    while (offset + 10 <= data.length) {
      final frameId = ascii.decode(data.sublist(offset, offset + 4), allowInvalid: true);
      if (frameId.trim().isEmpty || frameId.codeUnits.every((unit) => unit == 0)) {
        break;
      }

      final frameSize = version == 4 ? _readSynchsafeInt(data, offset + 4) : _readInt32(data, offset + 4);
      if (frameSize <= 0 || offset + 10 + frameSize > data.length) {
        break;
      }

      if (frameId == 'TIT2') {
        title = _decodeTextFrame(data.sublist(offset + 10, offset + 10 + frameSize));
        break;
      }

      offset += 10 + frameSize;
    }

    if (startMs < 0) return null;
    return AudioChapter(
      title: (title == null || title.trim().isEmpty)
          ? '${AppLocalizations.of(context)!.chapterFrom} ${_formatChapterTime(startMs)}'
          : title.trim(),
      start: Duration(milliseconds: startMs),
      end: endMs >= 0xffffffff ? null : Duration(milliseconds: endMs),
    );
  }

  static String _decodeTextFrame(Uint8List data) {
    if (data.isEmpty) return '';

    final encoding = data.first;
    final content = data.sublist(1);

    switch (encoding) {
      case 0:
        return latin1.decode(content).replaceAll('\u0000', '').trim();
      case 1:
        return _decodeUtf16(content).trim();
      case 2:
        return _decodeUtf16(content, withBom: false).trim();
      case 3:
        return utf8.decode(content, allowMalformed: true).replaceAll('\u0000', '').trim();
      default:
        return latin1.decode(content, allowInvalid: true).replaceAll('\u0000', '').trim();
    }
  }

  static String _decodeUtf16(Uint8List bytes, {bool withBom = true}) {
    if (bytes.isEmpty) return '';

    var littleEndian = false;
    var offset = 0;
    if (withBom && bytes.length >= 2) {
      if (bytes[0] == 0xff && bytes[1] == 0xfe) {
        littleEndian = true;
        offset = 2;
      } else if (bytes[0] == 0xfe && bytes[1] == 0xff) {
        littleEndian = false;
        offset = 2;
      }
    }

    final values = <int>[];
    for (var index = offset; index + 1 < bytes.length; index += 2) {
      final value = littleEndian ? bytes[index] | (bytes[index + 1] << 8) : (bytes[index] << 8) | bytes[index + 1];
      if (value == 0) break;
      values.add(value);
    }
    return String.fromCharCodes(values);
  }

  static int _readSynchsafeInt(Uint8List data, int offset) {
    if (offset + 4 > data.length) return 0;
    return ((data[offset] & 0x7f) << 21) |
        ((data[offset + 1] & 0x7f) << 14) |
        ((data[offset + 2] & 0x7f) << 7) |
        (data[offset + 3] & 0x7f);
  }

  static int _readInt32(Uint8List data, int offset) {
    if (offset + 4 > data.length) return 0;
    return ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
  }

  static String _formatChapterTime(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '${duration.inMinutes}:$seconds';
  }

  static Future<Map<int, String>> loadDownloadedPathsForAttachments(
      List<Attachment> attachments, int retentionDays) async {
    await cleanupExpiredDownloads(retentionDays);

    final downloadedPaths = <int, String>{};
    for (final attachment in attachments) {
      final storageAttachmentId = _resolveStorageAttachmentId(attachment);
      String? storedPath = await _storage.read(key: _downloadPathKey(attachment.attachmentID));
      if ((storedPath == null || storedPath.isEmpty) && storageAttachmentId != attachment.attachmentID) {
        storedPath = await _storage.read(key: _downloadPathKey(storageAttachmentId));
      }
      if ((storedPath == null || storedPath.isEmpty) && attachment.attachmentURL.isNotEmpty) {
        storedPath = await _storage.read(key: _downloadPathByUrlKey(attachment.attachmentURL));
        if (storedPath != null && storedPath.isNotEmpty) {
          await _storage.write(key: _downloadPathKey(storageAttachmentId), value: storedPath);
          if (attachment.attachmentID >= 0 && attachment.attachmentID != storageAttachmentId) {
            await _storage.write(key: _downloadPathKey(attachment.attachmentID), value: storedPath);
          }
        }
      }

      // Fallback after app restart: restore mapping from cached file name even
      // when secure storage keys are missing.
      if (storedPath == null || storedPath.isEmpty) {
        final cachedPath = await _findCachedFileForStorageAttachmentId(storageAttachmentId);
        if (cachedPath != null && cachedPath.isNotEmpty) {
          storedPath = cachedPath;
          await _storage.write(key: _downloadPathKey(storageAttachmentId), value: cachedPath);
          if (attachment.attachmentID >= 0 && attachment.attachmentID != storageAttachmentId) {
            await _storage.write(key: _downloadPathKey(attachment.attachmentID), value: cachedPath);
          }
          if (attachment.attachmentURL.isNotEmpty) {
            await _storage.write(key: _downloadPathByUrlKey(attachment.attachmentURL), value: cachedPath);
          }
        }
      }

      if (storedPath == null || storedPath.isEmpty) continue;

      await _storage.write(key: _downloadPathKey(storageAttachmentId), value: storedPath);

      // Backfill URL-based mapping for older ID-only entries.
      if (attachment.attachmentURL.isNotEmpty) {
        await _storage.write(
          key: _downloadPathByUrlKey(attachment.attachmentURL),
          value: storedPath,
        );
      }

      final file = File(storedPath);
      if (await file.exists()) {
        downloadedPaths[attachment.attachmentID] = storedPath;
      } else {
        await _storage.delete(key: _downloadPathKey(attachment.attachmentID));
        await _storage.delete(key: _downloadPathKey(storageAttachmentId));
        await _storage.delete(key: _downloadTimestampKey(attachment.attachmentID));
        await _storage.delete(key: _downloadTimestampKey(storageAttachmentId));
        if (attachment.attachmentURL.isNotEmpty) {
          await _storage.delete(key: _downloadPathByUrlKey(attachment.attachmentURL));
        }
      }
    }

    return downloadedPaths;
  }

  /// Lists all downloaded audio files by scanning the audio cache directory.
  /// This is resilient to app restarts because it reads directly from the
  /// filesystem rather than relying on persistent key–value storage.
  static Future<List<DownloadedAudioInfo>> getDownloadedAudios() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final audioDirectory = Directory(p.join(appSupport.path, FluxNewsState.audioCachePath));

      if (!await audioDirectory.exists()) {
        return const [];
      }

      final downloads = <DownloadedAudioInfo>[];
      final newestByAttachmentId = <int, DownloadedAudioInfo>{};
      await for (final entity in audioDirectory.list(followLinks: false)) {
        if (entity is! File) continue;
        final fileName = p.basename(entity.path);
        if (!fileName.startsWith(FluxNewsState.audioFilePrefix)) continue;

        final stat = await entity.stat();
        final info = DownloadedAudioInfo(
          storageID: entity.path,
          attachmentID: _attachmentIdFromFileName(fileName),
          fileName: fileName,
          filePath: entity.path,
          fileSize: stat.size,
          downloadedAt: stat.modified,
        );

        // Keep only one file per attachment ID (the newest), which avoids
        // duplicate entries after historic repeated sync downloads.
        if (info.attachmentID != -1) {
          final previous = newestByAttachmentId[info.attachmentID];
          if (previous == null || info.downloadedAt.isAfter(previous.downloadedAt)) {
            newestByAttachmentId[info.attachmentID] = info;
          }
        } else {
          downloads.add(info);
        }
      }

      downloads.addAll(newestByAttachmentId.values);

      downloads.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      return downloads;
    } catch (_) {
      return const [];
    }
  }

  static Future<int> getDownloadedAudioSizeInBytes() async {
    final downloads = await getDownloadedAudios();
    return downloads.fold<int>(0, (sum, item) => sum + item.fileSize);
  }

  static Future<void> deleteDownloadedAudio(int attachmentID) async {
    // Try the fast path via legacy storage key.
    final storedPath = await _storage.read(key: _downloadPathKey(attachmentID));
    if (storedPath != null && storedPath.isNotEmpty) {
      final file = File(storedPath);
      if (await file.exists()) await file.delete();
    } else {
      // Fall back to filesystem scan when the storage key is missing.
      final appSupport = await getApplicationSupportDirectory();
      final audioDirectory = Directory(p.join(appSupport.path, FluxNewsState.audioCachePath));
      if (await audioDirectory.exists()) {
        await for (final entity in audioDirectory.list(followLinks: false)) {
          if (entity is! File) continue;
          final fileName = p.basename(entity.path);
          if (!fileName.startsWith(FluxNewsState.audioFilePrefix)) continue;
          if (_attachmentIdFromFileName(fileName) == attachmentID) {
            await entity.delete();
            break;
          }
        }
      }
    }
    await _storage.delete(key: _downloadPathKey(attachmentID));
    await _storage.delete(key: _downloadTimestampKey(attachmentID));
    _emitDownloadedAudiosChanged();
  }

  /// Deletes a downloaded audio by its storageID, which is the file path.
  static Future<void> deleteDownloadedAudioByStorageId(String storageID) async {
    if (storageID.isEmpty) return;

    final file = File(storageID);
    if (await file.exists()) {
      await file.delete();
    }

    // Clean up legacy storage keys derived from the filename.
    final fileName = p.basename(storageID);
    final attachmentID = _attachmentIdFromFileName(fileName);
    if (attachmentID >= 0) {
      await _storage.delete(key: _downloadPathKey(attachmentID));
      await _storage.delete(key: _downloadTimestampKey(attachmentID));
    }

    _emitDownloadedAudiosChanged();
  }

  static Future<void> deleteAllDownloadedAudios() async {
    final downloads = await getDownloadedAudios();
    for (final download in downloads) {
      await deleteDownloadedAudioByStorageId(download.storageID);
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static Future<void> cleanupExpiredDownloads(int retentionDays) async {
    if (retentionDays <= 0) return;

    final now = DateTime.now();
    final appSupport = await getApplicationSupportDirectory();
    final audioDirectory = Directory(p.join(appSupport.path, FluxNewsState.audioCachePath));

    if (!await audioDirectory.exists()) return;

    // Delete expired audio files directly from the cache directory.
    await for (final entity in audioDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = p.basename(entity.path);
      if (!fileName.startsWith(FluxNewsState.audioFilePrefix)) continue;

      final stat = await entity.stat();
      if (now.difference(stat.modified).inDays >= retentionDays) {
        final attachmentID = _attachmentIdFromFileName(fileName);
        await entity.delete();
        if (attachmentID >= 0) {
          await _storage.delete(key: _downloadPathKey(attachmentID));
          await _storage.delete(key: _downloadTimestampKey(attachmentID));
        }
        _emitDownloadedAudiosChanged();
      }
    }

    // Clean up dangling legacy storage keys that no longer have a file.
    final allValues = await _storage.readAll();
    for (final entry in allValues.entries) {
      if (!entry.key.startsWith(_downloadPathKeyPrefix)) continue;
      if (entry.value.isEmpty) continue;
      if (!await File(entry.value).exists()) {
        final idString = entry.key.substring(_downloadPathKeyPrefix.length);
        final attachmentID = int.tryParse(idString);
        if (attachmentID != null) {
          await _storage.delete(key: _downloadPathKey(attachmentID));
          await _storage.delete(key: _downloadTimestampKey(attachmentID));
        }
      }
    }
  }

  static Future<String?> downloadAttachment(Attachment attachment, {bool onlyOnWifi = false}) async {
    if (attachment.attachmentURL.isEmpty) return null;

    final storageAttachmentId = _resolveStorageAttachmentId(attachment);

    String? existingPath = await _storage.read(key: _downloadPathKey(attachment.attachmentID));
    if ((existingPath == null || existingPath.isEmpty) && storageAttachmentId != attachment.attachmentID) {
      existingPath = await _storage.read(key: _downloadPathKey(storageAttachmentId));
    }
    existingPath ??= await _storage.read(key: _downloadPathByUrlKey(attachment.attachmentURL));

    if (existingPath != null && existingPath.isNotEmpty) {
      final existingFile = File(existingPath);
      if (await existingFile.exists()) {
        await _storage.write(
          key: _downloadPathKey(storageAttachmentId),
          value: existingPath,
        );
        await _storage.write(
          key: _downloadPathByUrlKey(attachment.attachmentURL),
          value: existingPath,
        );
        return existingPath;
      }
      await _storage.delete(key: _downloadPathKey(attachment.attachmentID));
      await _storage.delete(key: _downloadPathKey(storageAttachmentId));
      await _storage.delete(key: _downloadTimestampKey(attachment.attachmentID));
      await _storage.delete(key: _downloadTimestampKey(storageAttachmentId));
      await _storage.delete(key: _downloadPathByUrlKey(attachment.attachmentURL));
    }

    // Fallback: detect already cached file directly from filesystem so sync
    // does not re-download when secure storage entries are missing.
    final cachedPath = await _findCachedFileForStorageAttachmentId(storageAttachmentId);
    if (cachedPath != null && cachedPath.isNotEmpty) {
      await _storage.write(
        key: _downloadPathKey(storageAttachmentId),
        value: cachedPath,
      );
      if (attachment.attachmentID >= 0 && attachment.attachmentID != storageAttachmentId) {
        await _storage.write(
          key: _downloadPathKey(attachment.attachmentID),
          value: cachedPath,
        );
      }
      await _storage.write(
        key: _downloadPathByUrlKey(attachment.attachmentURL),
        value: cachedPath,
      );
      return cachedPath;
    }

    if (onlyOnWifi && !await _isWifiConnected()) {
      return null;
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(attachment.attachmentURL));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final appSupport = await getApplicationSupportDirectory();
      final audioDirectory = Directory(p.join(appSupport.path, FluxNewsState.audioCachePath));
      if (!await audioDirectory.exists()) {
        await audioDirectory.create(recursive: true);
      }

      final uri = Uri.tryParse(attachment.attachmentURL);
      final extension = uri != null ? p.extension(uri.path) : '';
      final filePath = p.join(
        audioDirectory.path,
        '${FluxNewsState.audioFilePrefix}${storageAttachmentId}_${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      final file = File(filePath);
      final sink = file.openWrite();
      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final startedAt = DateTime.now();
      _setActiveDownload(AudioDownloadProgress(
        attachmentID: storageAttachmentId,
        fileName: path.basename(filePath),
        receivedBytes: 0,
        totalBytes: totalBytes,
        startedAt: startedAt,
      ));

      try {
        await for (final chunk in response) {
          receivedBytes += chunk.length;
          sink.add(chunk);
          _setActiveDownload(AudioDownloadProgress(
            attachmentID: storageAttachmentId,
            fileName: path.basename(filePath),
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            startedAt: startedAt,
          ));
        }
      } catch (_) {
        await sink.close();
        _removeActiveDownload(storageAttachmentId);
        if (await file.exists()) {
          await file.delete();
        }
        rethrow;
      }

      await sink.close();

      await _storage.write(key: _downloadPathKey(storageAttachmentId), value: filePath);
      if (attachment.attachmentID >= 0 && attachment.attachmentID != storageAttachmentId) {
        await _storage.write(key: _downloadPathKey(attachment.attachmentID), value: filePath);
      }
      await _storage.write(key: _downloadPathByUrlKey(attachment.attachmentURL), value: filePath);
      await _storage.write(
        key: _downloadTimestampKey(storageAttachmentId),
        value: DateTime.now().toIso8601String(),
      );
      _emitDownloadedAudiosChanged();
      _removeActiveDownload(storageAttachmentId);

      return filePath;
    } finally {
      _removeActiveDownload(storageAttachmentId);
      client.close(force: true);
    }
  }

  static Future<void> downloadAudioForNewsList({
    required List<News> newsList,
    required int retentionDays,
    bool onlyOnWifi = false,
  }) async {
    await cleanupExpiredDownloads(retentionDays);

    if (onlyOnWifi && !await _isWifiConnected()) {
      return;
    }

    for (final news in newsList) {
      final attachments = news.getAudioAttachments();
      for (final attachment in attachments) {
        await downloadAttachment(attachment, onlyOnWifi: onlyOnWifi);
      }
    }
  }
}
