import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    this.isQueued = false,
  });

  final int attachmentID;
  final String fileName;
  final int receivedBytes;
  final int totalBytes;
  final DateTime startedAt;
  /// True while the item is waiting in the queue before the HTTP download starts.
  final bool isQueued;

  double? get progress {
    if (isQueued || totalBytes <= 0) return null;
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

class _ArtworkImageInfo {
  const _ArtworkImageInfo({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
}

class AudioDownloadService {
  // AfterFirstUnlock: readable in background after device has been unlocked
  // at least once since boot — required for CarPlay headless launch with
  // locked screen. WhenUnlocked (default) fails with errSecInteractionNotAllowed.
  static final _storage = sec_store.FlutterSecureStorage(
    iOptions: const sec_store.IOSOptions(
      accessibility: sec_store.KeychainAccessibility.first_unlock,
    ),
  );
  static const int _remoteId3HeaderLength = 10;
  static const int _maxArtworkBytes = 3 * 1024 * 1024;
  static const int _maxArtworkDownloadBytes = 12 * 1024 * 1024;
  static const int _maxArtworkDimension = 1024;
  static const String _downloadPathKeyPrefix = FluxNewsState.downloadPathKeyPrefix;
  static const String _downloadPathByUrlKeyPrefix = FluxNewsState.downloadPathByUrlKeyPrefix;
  static const String _downloadTimestampKeyPrefix = FluxNewsState.downloadTimestampKeyPrefix;
  static const String _defaultArtworkAssetPath = FluxNewsState.defaultArtworkAssetPath;
  static const String _defaultArtworkFileName = FluxNewsState.defaultArtworkFileName;
  static const String _defaultAndroidArtworkAssetPath = FluxNewsState.defaultAndroidArtworkAssetPath;
  static const String _defaultAndroidArtworkFileName = FluxNewsState.defaultAndroidArtworkFileName;
  static const String _androidDefaultArtworkProviderAuthority = FluxNewsState.androidDefaultArtworkProviderAuthority;
  static const String _artworkCacheDirectoryName = FluxNewsState.artworkCacheDirectoryName;
  static final _activeDownloads = <int, AudioDownloadProgress>{};
  static final _activeDownloadsController = StreamController<List<AudioDownloadProgress>>.broadcast();
  static final _downloadedAudiosChangedController = StreamController<void>.broadcast();
  // Tracks the HttpClient per storageAttachmentId so downloads can be cancelled.
  static final _activeClients = <int, HttpClient>{};
  // Sequential queue: each new download is chained onto the previous one.
  static var _downloadQueue = Future<void>.value();
  // IDs explicitly cancelled by the user — distinguishes cancellations from real errors.
  static final _cancelledByUser = <int>{};
  static const String _downloadSkippedKeyPrefix = FluxNewsState.downloadSkippedKeyPrefix;
  // In-memory cache of user-skipped IDs; backed by Keychain for persistence.
  static final _userSkippedDownloads = <int>{};

  static const String _downloadTitleKeyPrefix = FluxNewsState.downloadTitleKeyPrefix;
  static const String _downloadFeedTitleKeyPrefix = FluxNewsState.downloadFeedTitleKeyPrefix;

  // Cache for download metadata (attachmentID → value) used by CarPlay / Android Auto
  static final _downloadTitleCache = <int, String>{};
  static final _downloadFeedTitleCache = <int, String>{};
  // newsID and mediaProgression are memory-only — always derivable from the DB.
  // They are cached here so _resolveSavedPosition can avoid a DB query on the
  // CarPlay audio-grant hot path.
  static final _downloadNewsIdCache = <int, int>{};
  static final _downloadMediaProgressionCache = <int, int>{};

  static void cacheDownloadTitle(int attachmentID, String title) {
    _downloadTitleCache[attachmentID] = title;
    _storage.write(key: '$_downloadTitleKeyPrefix$attachmentID', value: title);
  }

  static void cacheDownloadFeedTitle(int attachmentID, String feedTitle) {
    _downloadFeedTitleCache[attachmentID] = feedTitle;
    _storage.write(key: '$_downloadFeedTitleKeyPrefix$attachmentID', value: feedTitle);
  }

  static void cacheDownloadNewsId(int attachmentID, int newsID) {
    _downloadNewsIdCache[attachmentID] = newsID;
  }

  static void cacheDownloadMediaProgression(int attachmentID, int mediaProgression) {
    _downloadMediaProgressionCache[attachmentID] = mediaProgression;
  }

  /// Refreshes the in-memory mediaProgression cache from a freshly synced news
  /// list. Called after insertNewsInDB so CarPlay / Android Auto resolve the
  /// saved position without an extra DB query.
  static void refreshMediaProgressionCacheFromSync(List<News> newsList) {
    for (final news in newsList) {
      for (final attachment in news.getAudioAttachments()) {
        if (attachment.attachmentID < 0) continue;
        if (attachment.mediaProgression > 0) {
          _downloadMediaProgressionCache[attachment.attachmentID] = attachment.mediaProgression;
        } else {
          // Server reset to 0 (e.g. episode restarted on another device) — clear stale entry.
          _downloadMediaProgressionCache.remove(attachment.attachmentID);
        }
      }
    }
  }

  static String? getDownloadTitle(int attachmentID) => _downloadTitleCache[attachmentID];
  static String? getDownloadFeedTitle(int attachmentID) => _downloadFeedTitleCache[attachmentID];
  static int? getDownloadNewsId(int attachmentID) => _downloadNewsIdCache[attachmentID];
  static int? getDownloadMediaProgression(int attachmentID) => _downloadMediaProgressionCache[attachmentID];

  /// Persists the user-skipped flag to Keychain so auto-downloads skip this
  /// attachment on future syncs even after the app is restarted.
  static Future<void> _persistUserSkipped(int storageAttachmentId) async {
    _userSkippedDownloads.add(storageAttachmentId);
    try {
      await _storage.write(
        key: '$_downloadSkippedKeyPrefix$storageAttachmentId',
        value: FluxNewsState.secureStorageTrueString,
      );
    } catch (_) {}
  }

  /// Returns true if the user has previously cancelled this attachment's
  /// auto-download. Checks the in-memory cache first, then Keychain.
  static Future<bool> isUserSkipped(int storageAttachmentId) async {
    if (_userSkippedDownloads.contains(storageAttachmentId)) return true;
    try {
      final value = await _storage.read(
        key: '$_downloadSkippedKeyPrefix$storageAttachmentId',
      );
      if (value == FluxNewsState.secureStorageTrueString) {
        _userSkippedDownloads.add(storageAttachmentId);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Marks an attachment as user-skipped without cancelling an active download.
  /// Use this when the user explicitly deletes a downloaded file so the next
  /// sync does not re-download it automatically.
  static Future<void> markUserSkipped(int storageAttachmentId) =>
      _persistUserSkipped(storageAttachmentId);

  /// Clears the user-skipped flag. Called when the user manually triggers a
  /// download or when a download completes successfully.
  static Future<void> clearUserSkipped(int storageAttachmentId) async {
    _userSkippedDownloads.remove(storageAttachmentId);
    try {
      await _storage.delete(key: '$_downloadSkippedKeyPrefix$storageAttachmentId');
    } catch (_) {}
  }

  /// Cancels a running download by closing its HTTP connection.
  /// The in-progress file is deleted and the active-downloads stream is updated.
  static void cancelDownload(int storageAttachmentId) {
    _cancelledByUser.add(storageAttachmentId);
    _persistUserSkipped(storageAttachmentId).ignore();
    _activeClients[storageAttachmentId]?.close(force: true);
  }

  /// Cancels all running downloads. For sequential batch downloads
  /// (e.g. auto-download), aborting the active one propagates an exception
  /// through the loop, which also cancels all queued downloads.
  static void cancelAllDownloads() {
    for (final id in List<int>.from(_activeClients.keys)) {
      cancelDownload(id);
    }
  }

  /// Adds [attachment] to the sequential download queue. Returns a Future that
  /// completes with the local file path when the download actually runs, or
  /// null if the file already exists / WiFi check failed. If [attachment] is
  /// already active or queued, returns null immediately.
  static Future<String?> queueDownload(
    Attachment attachment, {
    News? news,
    bool onlyOnWifi = false,
  }) {
    final storageId = _resolveStorageAttachmentId(attachment);

    // Already active or queued — don't enqueue twice.
    if (_activeDownloads.containsKey(storageId)) return Future.value(null);

    // Pre-cache title so the banner shows the episode name while waiting.
    if (news != null && storageId >= 0) {
      cacheDownloadTitle(storageId, news.title);
      cacheDownloadFeedTitle(storageId, news.feedTitle);
      cacheDownloadNewsId(storageId, news.newsID);
    }

    // Show a "queued" placeholder in the active-downloads stream immediately.
    _setActiveDownload(AudioDownloadProgress(
      attachmentID: storageId,
      fileName: (news != null && news.title.isNotEmpty)
          ? news.title
          : p.basename(attachment.attachmentURL),
      receivedBytes: 0,
      totalBytes: 0,
      startedAt: DateTime.now(),
      isQueued: true,
    ));

    final completer = Completer<String?>();

    _downloadQueue = _downloadQueue.then((_) async {
      String? result;
      Object? downloadError;
      try {
        result = await downloadAttachment(attachment, news: news, onlyOnWifi: onlyOnWifi);
      } catch (e) {
        downloadError = e;
      } finally {
        // Remove queued placeholder if downloadAttachment returned early
        // (file already exists, WiFi check failed) without replacing it.
        final current = _activeDownloads[storageId];
        if (current?.isQueued == true) {
          _removeActiveDownload(storageId);
        }
      }
      if (!completer.isCompleted) {
        if (downloadError != null) {
          completer.completeError(downloadError);
        } else {
          completer.complete(result);
        }
      }
      // Never rethrow — a single failure must not break the queue chain.
    });

    return completer.future;
  }

  /// Returns true if [storageAttachmentId] was explicitly cancelled by the user.
  /// Clears the flag on read so it is consumed exactly once.
  static bool consumeCancelledByUser(int storageAttachmentId) {
    return _cancelledByUser.remove(storageAttachmentId);
  }

  /// Loads titles into the memory cache for the given downloads.
  /// Checks memory cache → SecureStorage → SQLite DB (headless-safe).
  static Future<void> loadTitlesForDownloads(List<DownloadedAudioInfo> downloads) async {
    final needsLookup = <int>[];
    for (final d in downloads) {
      final id = d.attachmentID;
      if (id < 0) continue;
      if (_downloadTitleCache.containsKey(id)) continue;
      try {
        final title = await _storage.read(key: '$_downloadTitleKeyPrefix$id');
        final feedTitle = await _storage.read(key: '$_downloadFeedTitleKeyPrefix$id');
        if (title != null && title.isNotEmpty) _downloadTitleCache[id] = title;
        if (feedTitle != null && feedTitle.isNotEmpty) _downloadFeedTitleCache[id] = feedTitle;
      } catch (e) {
        logThis('AudioDownloadService', 'loadTitlesForDownloads: Keychain read failed for id=$id: $e', LogLevel.WARNING);
      }
      if (!_downloadTitleCache.containsKey(id)) needsLookup.add(id);
    }

    if (needsLookup.isEmpty) return;

    // Fall back to a direct read-only query of the SQLite database.
    Database? db;
    try {
      databaseFactory = databaseFactoryFfi;
      final dbPath = await _resolveDatabasePath();
      if (dbPath == null || !await File(dbPath).exists()) return;

      db = await databaseFactoryFfi.openDatabase(dbPath);
      for (final id in needsLookup) {
        final rows = await db.rawQuery(
          '''SELECT news.title, news.feedTitle, attachments.newsID,
                    attachments.mediaProgression
             FROM attachments
             INNER JOIN news ON attachments.newsID = news.newsID
             WHERE attachments.attachmentID = ?
             LIMIT 1''',
          [id],
        );
        if (rows.isEmpty) continue;
        final title = rows.first['title'] as String?;
        final feedTitle = rows.first['feedTitle'] as String?;
        final newsID = rows.first['newsID'] as int?;
        final mediaProgression = rows.first['mediaProgression'] as int?;
        if (title != null && title.isNotEmpty) cacheDownloadTitle(id, title);
        if (feedTitle != null && feedTitle.isNotEmpty) cacheDownloadFeedTitle(id, feedTitle);
        if (newsID != null) cacheDownloadNewsId(id, newsID);
        if (mediaProgression != null && mediaProgression > 0) {
          cacheDownloadMediaProgression(id, mediaProgression);
        }
      }
    } catch (_) {
      // DB unavailable — titles will fall back to filenames
    } finally {
      await db?.close();
    }
  }

  static Future<String?> _resolveDatabasePath() async {
    try {
      if (Platform.isIOS) {
        final libraryDir = await getLibraryDirectory();
        return p.join(libraryDir.path, FluxNewsState.databasePathString);
      } else {
        final appSupport = await getApplicationSupportDirectory();
        final parts = appSupport.path.split('/');
        var dir = '/';
        for (int i = 0; i < parts.length - 1; i++) {
          if (parts[i].isNotEmpty) dir = p.join(dir, parts[i]);
        }
        return p.join(dir, FluxNewsState.androidDatabaseDirectory, FluxNewsState.databasePathString);
      }
    } catch (_) {
      return null;
    }
  }

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

  static int resolveStorageAttachmentId(Attachment attachment) {
    return _resolveStorageAttachmentId(attachment);
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

  static Future<File> _ensureDefaultArtworkFile() async {
    final assetPath = Platform.isAndroid ? _defaultAndroidArtworkAssetPath : _defaultArtworkAssetPath;
    final fileName = Platform.isAndroid ? _defaultAndroidArtworkFileName : _defaultArtworkFileName;

    final appSupport = await getApplicationSupportDirectory();
    final file = File(p.join(appSupport.path, fileName));

    if (!await file.exists()) {
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    }

    return file;
  }

  static Uri _buildAndroidDefaultArtworkContentUri() {
    return Uri.parse(
      'content://$_androidDefaultArtworkProviderAuthority/${Uri.encodeComponent(_defaultAndroidArtworkFileName)}',
    );
  }

  static Future<String?> getDefaultArtworkFilePath() async {
    try {
      final file = await _ensureDefaultArtworkFile();
      return file.path;
    } catch (e, st) {
      logThis('artwork', 'getDefaultArtworkFilePath error: $e\n$st', LogLevel.ERROR);
      return null;
    }
  }

  static Future<Uri?> getDefaultArtworkUri() async {
    try {
      final file = await _ensureDefaultArtworkFile();

      if (Platform.isAndroid) {
        return _buildAndroidDefaultArtworkContentUri();
      }

      final uri = Uri.file(file.path);
      return uri;
    } catch (e, st) {
      logThis('artwork', 'getDefaultArtworkUri error: $e\n$st', LogLevel.ERROR);
      return null;
    }
  }

static Future<Uri?> cacheArtworkBytesForAttachment({
    required int attachmentID,
    required Uint8List imageBytes,
  }) async {
    if (imageBytes.isEmpty) {
      return null;
    }

    try {
      final normalizedBytes = await _normalizeArtworkBytes(imageBytes);
      if (normalizedBytes == null || normalizedBytes.isEmpty) {
        return null;
      }

      // On Android, add a mean-color border so the notification artwork is not
      // cropped/zoomed. The border makes the image square and adds ~15 % padding
      // on each side, filled with the average colour of the image.
      final finalBytes = Platform.isAndroid
          ? await _addAndroidArtworkPadding(normalizedBytes) ?? normalizedBytes
          : normalizedBytes;

      final appSupport = await getApplicationSupportDirectory();
      final artworkDirectory = Directory(p.join(appSupport.path, _artworkCacheDirectoryName));
      if (!await artworkDirectory.exists()) {
        await artworkDirectory.create(recursive: true);
      }

      // Padding always produces PNG; detect extension from the final bytes.
      final extension = _detectImageFileExtension(finalBytes);
      final fileName = '${FluxNewsState.artworkFilePrefix}$attachmentID.$extension';
      final file = File(p.join(artworkDirectory.path, fileName));
      await file.writeAsBytes(finalBytes, flush: true);
      return Uri.file(file.path);
    } catch (_) {
      return null;
    }
  }

  /// Adds a mean-colour border to make the artwork square with ~15 % padding on
  /// each side. Required on Android because the media notification crops artwork
  /// to a circle/square and the launcher zooms in to fill the frame.
  static Future<Uint8List?> _addAndroidArtworkPadding(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;

      // Compute average colour from raw RGBA pixel data.
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        image.dispose();
        codec.dispose();
        return null;
      }

      final pixels = byteData.buffer.asUint8List();
      final pixelCount = width * height;
      int sumR = 0, sumG = 0, sumB = 0;
      for (int i = 0; i < pixels.length; i += 4) {
        sumR += pixels[i];
        sumG += pixels[i + 1];
        sumB += pixels[i + 2];
      }
      final avgColor = ui.Color.fromARGB(
        255,
        sumR ~/ pixelCount,
        sumG ~/ pixelCount,
        sumB ~/ pixelCount,
      );

      // Compute output dimensions: square canvas with 15 % padding per side.
      final maxDim = width > height ? width : height;
      final padding = (maxDim * 0.15).round();
      final outputSize = maxDim + 2 * padding;

      // Offset to centre the original image on the square canvas.
      final offsetX = (padding + (maxDim - width) ~/ 2).toDouble();
      final offsetY = (padding + (maxDim - height) ~/ 2).toDouble();

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble()),
        ui.Paint()..color = avgColor,
      );
      canvas.drawImage(image, ui.Offset(offsetX, offsetY), ui.Paint());

      image.dispose();
      codec.dispose();

      final picture = recorder.endRecording();
      final output = await picture.toImage(outputSize, outputSize);
      picture.dispose();

      final resultData = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();

      return resultData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _normalizeArtworkBytes(Uint8List imageBytes) async {
    if (imageBytes.isEmpty || imageBytes.length > _maxArtworkDownloadBytes) {
      return null;
    }

    final imageInfo = await _tryReadImageInfo(imageBytes);
    if (imageInfo == null) {
      return imageBytes.length <= _maxArtworkBytes ? imageBytes : null;
    }

    final originalWidth = imageInfo.width;
    final originalHeight = imageInfo.height;
    if (imageBytes.length <= _maxArtworkBytes &&
        originalWidth <= _maxArtworkDimension &&
        originalHeight <= _maxArtworkDimension) {
      return imageBytes;
    }

    Uint8List? candidate;
    for (final targetLongSide in const [1024, 768, 512, 384, 256]) {
      final resized = await _resizeToLongSide(imageBytes, originalWidth, originalHeight, targetLongSide);
      if (resized == null) {
        continue;
      }

      candidate = resized;
      if (candidate.length <= _maxArtworkBytes) {
        return candidate;
      }
    }

    return null;
  }

  static Future<_ArtworkImageInfo?> _tryReadImageInfo(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return _ArtworkImageInfo(width: width, height: height);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _resizeToLongSide(
    Uint8List imageBytes,
    int width,
    int height,
    int targetLongSide,
  ) async {
    try {
      final maxSide = width > height ? width : height;
      if (maxSide <= 0) {
        return null;
      }

      final scale = targetLongSide / maxSide;
      final targetWidth = scale >= 1 ? width : (width * scale).round().clamp(1, width);
      final targetHeight = scale >= 1 ? height : (height * scale).round().clamp(1, height);

      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (byteData == null) {
        return null;
      }
      return byteData.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getCachedArtworkFilePathForAttachment(int attachmentID) async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final artworkDirectory = Directory(p.join(appSupport.path, _artworkCacheDirectoryName));
      if (!await artworkDirectory.exists()) return null;
      for (final extension in const ['png', 'jpg', 'gif']) {
        final file = File(p.join(artworkDirectory.path, '${FluxNewsState.artworkFilePrefix}$attachmentID.$extension'));
        if (await file.exists()) return file.path;
      }
    } catch (_) {}
    return null;
  }

  static Future<Uri?> getCachedArtworkUriForAttachment(int attachmentID) async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final artworkDirectory = Directory(p.join(appSupport.path, _artworkCacheDirectoryName));
      if (!await artworkDirectory.exists()) {
        return null;
      }

      for (final extension in const ['png', 'jpg', 'gif']) {
        final fileName = '${FluxNewsState.artworkFilePrefix}$attachmentID.$extension';
        final file = File(p.join(artworkDirectory.path, fileName));
        if (await file.exists()) {
          if (Platform.isAndroid) {
            return Uri.parse(
              'content://$_androidDefaultArtworkProviderAuthority/$_artworkCacheDirectoryName/${Uri.encodeComponent(fileName)}',
            );
          }
          return Uri.file(file.path);
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static Future<Uint8List?> _downloadImageBytes(Uri uri) async {
    if (!(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(uri);

      final apiKey = await _storage.read(key: FluxNewsState.secureStorageMinifluxAPIKey);
      final minifluxUrl = await _storage.read(key: FluxNewsState.secureStorageMinifluxURLKey);
      final minifluxHost = Uri.tryParse(minifluxUrl ?? '')?.host.toLowerCase();
      if (apiKey != null &&
          apiKey.isNotEmpty &&
          minifluxHost != null &&
          minifluxHost.isNotEmpty &&
          uri.host.toLowerCase() == minifluxHost) {
        request.headers.set(FluxNewsState.httpMinifluxAuthHeaderString, apiKey);
      }

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      if (response.contentLength > _maxArtworkDownloadBytes) {
        return null;
      }

      final bytesBuilder = BytesBuilder(copy: false);
      var receivedBytes = 0;
      await for (final chunk in response) {
        receivedBytes += chunk.length;
        if (receivedBytes > _maxArtworkDownloadBytes) {
          return null;
        }
        bytesBuilder.add(chunk);
      }

      final bytes = bytesBuilder.toBytes();
      if (bytes.isEmpty) {
        return null;
      }

      return bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _precacheArtworkForDownloadedAudio({
    required Attachment attachment,
    required String downloadedFilePath,
    News? news,
  }) async {
    Uint8List? artworkBytes;

    if (news != null) {
      final imageAttachment = news.getFirstImageAttachment();
      if (imageAttachment.attachmentURL.isNotEmpty &&
          imageAttachment.attachmentMimeType.trim().toLowerCase().startsWith('image/')) {
        final imageUri = Uri.tryParse(imageAttachment.attachmentURL);
        if (imageUri != null) {
          artworkBytes = await _downloadImageBytes(imageUri);
        }
      }
    }

    artworkBytes ??= await extractAlbumArtFromFile(downloadedFilePath);
    if (artworkBytes == null || artworkBytes.isEmpty) {
      return;
    }

    await cacheArtworkBytesForAttachment(
      attachmentID: attachment.attachmentID,
      imageBytes: artworkBytes,
    );
  }

  static String _detectImageFileExtension(Uint8List bytes) {
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 4 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'gif';
    }
    return 'jpg';
  }

  static Future<List<AudioChapter>> readChapters(String filePath, BuildContext context) async {
    final file = File(filePath);
    if (!await file.exists()) return const [];

    final raf = await file.open();
    try {
      final header = await raf.read(_remoteId3HeaderLength);
      if (!_hasId3Header(header)) {
        return const [];
      }

      final version = header[3];
      final flags = header[5];
      final tagSize = _readSynchsafeInt(header, 6);
      if (tagSize <= 0) return const [];

      final tagData = await raf.read(tagSize);
      if (context.mounted) {
        return _extractChaptersFromTagData(
          version: version,
          flags: flags,
          tagData: tagData,
          context: context,
        );
      } else {
        return const [];
      }
    } finally {
      await raf.close();
    }
  }

  static Future<List<AudioChapter>> readChaptersFromUrl(String url, BuildContext context) async {
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null) return const [];

    final client = HttpClient();
    try {
      final headerBytes = await _readRemoteBytes(
        client: client,
        uri: parsedUrl,
        start: 0,
        end: _remoteId3HeaderLength - 1,
        maxBytes: _remoteId3HeaderLength,
      );
      if (!_hasId3Header(headerBytes)) {
        return const [];
      }

      final version = headerBytes[3];
      final flags = headerBytes[5];
      final tagSize = _readSynchsafeInt(headerBytes, 6);
      if (tagSize <= 0) return const [];

      final tagData = await _readRemoteBytes(
        client: client,
        uri: parsedUrl,
        start: _remoteId3HeaderLength,
        end: _remoteId3HeaderLength + tagSize - 1,
        maxBytes: tagSize,
      );
      if (tagData.length < tagSize) {
        return const [];
      }

      if (context.mounted) {
        return _extractChaptersFromTagData(
          version: version,
          flags: flags,
          tagData: tagData,
          context: context,
        );
      } else {
        return const [];
      }
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// Extracts album art (APIC frame) from local audio file
  static Future<Uint8List?> extractAlbumArtFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final fileBytes = await file.readAsBytes();
      if (fileBytes.length < _remoteId3HeaderLength) return null;

      if (!_hasId3Header(fileBytes)) return null;

      final version = fileBytes[3];
      final tagSize = _readSynchsafeInt(fileBytes, 6);
      if (tagSize <= 0) return null;

      final endOffset = _remoteId3HeaderLength + tagSize;
      if (endOffset > fileBytes.length) return null;

      final tagBytes = fileBytes.sublist(_remoteId3HeaderLength, endOffset);
      return _extractPictureFromTagData(version: version, tagData: tagBytes);
    } catch (_) {
      return null;
    }
  }

  /// Extracts album art (APIC frame) from remote audio file
  static Future<Uint8List?> extractAlbumArtFromUrl(String url) async {
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null) return null;

    final client = HttpClient();
    try {
      final headerBytes = await _readRemoteBytes(
        client: client,
        uri: parsedUrl,
        start: 0,
        end: _remoteId3HeaderLength - 1,
        maxBytes: _remoteId3HeaderLength,
      );
      if (!_hasId3Header(headerBytes)) return null;

      final version = headerBytes[3];
      final tagSize = _readSynchsafeInt(headerBytes, 6);
      if (tagSize <= 0) return null;

      final tagData = await _readRemoteBytes(
        client: client,
        uri: parsedUrl,
        start: _remoteId3HeaderLength,
        end: _remoteId3HeaderLength + tagSize - 1,
        maxBytes: tagSize,
      );

      return _extractPictureFromTagData(version: version, tagData: tagData);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Extracts APIC (picture) frame from ID3v2 tag data
  static Uint8List? _extractPictureFromTagData({
    required int version,
    required Uint8List tagData,
  }) {
    if (version < 3 || version > 4) return null;

    int offset = 0;
    while (offset < tagData.length - 10) {
      final frameId = String.fromCharCodes(tagData.sublist(offset, offset + 4));
      if (frameId.startsWith('\u0000')) break; // padding

      if (frameId == 'APIC') {
        return _parseApicFrame(tagData, offset);
      }

      offset += 10; // frame header
      final frameSize = version == 3 ? _readInt32(tagData, offset - 4) : _readSynchsafeInt(tagData, offset - 4);
      offset += frameSize;
      if (offset > tagData.length) break;
    }
    return null;
  }

  /// Parses APIC (attached picture) frame and returns image bytes
  static Uint8List? _parseApicFrame(Uint8List tagData, int frameOffset) {
    try {
      int offset = frameOffset + 10; // skip frame header
      if (offset >= tagData.length) return null;

      offset++; // skip encoding byte
      if (offset >= tagData.length) return null;

      // Skip MIME type (null-terminated string)
      while (offset < tagData.length && tagData[offset] != 0) {
        offset++;
      }
      offset++; // skip null terminator

      if (offset >= tagData.length) return null;
      offset++; // skip picture type

      // Skip description (null-terminated string)
      while (offset < tagData.length && tagData[offset] != 0) {
        offset++;
      }
      offset++; // skip null terminator

      if (offset >= tagData.length) return null;

      // Remaining bytes are the image data
      return tagData.sublist(offset);
    } catch (_) {
      return null;
    }
  }

  static bool _hasId3Header(Uint8List header) {
    return header.length >= _remoteId3HeaderLength && ascii.decode(header.sublist(0, 3), allowInvalid: true) == 'ID3';
  }

  static Future<Uint8List> _readRemoteBytes({
    required HttpClient client,
    required Uri uri,
    required int start,
    required int end,
    required int maxBytes,
  }) async {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    if (response.statusCode != HttpStatus.partialContent && response.statusCode != HttpStatus.ok) {
      return Uint8List(0);
    }

    final builder = BytesBuilder(copy: false);
    var receivedBytes = 0;
    await for (final chunk in response) {
      if (receivedBytes >= maxBytes) {
        break;
      }

      final remaining = maxBytes - receivedBytes;
      if (chunk.length <= remaining) {
        builder.add(chunk);
        receivedBytes += chunk.length;
      } else {
        builder.add(chunk.sublist(0, remaining));
        receivedBytes += remaining;
        break;
      }
    }

    return builder.takeBytes();
  }

  static List<AudioChapter> _extractChaptersFromTagData({
    required int version,
    required int flags,
    required Uint8List tagData,
    required BuildContext context,
  }) {
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

      if (frameId == 'CHAP' && context.mounted) {
        final chapter = _parseChapFrame(tagData.sublist(offset + 10, offset + 10 + frameSize), version, context);
        if (chapter != null) {
          chapters.add(chapter);
        }
      }

      offset += 10 + frameSize;
    }

    chapters.sort((a, b) => a.start.compareTo(b.start));
    return chapters;
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
    if (attachmentID >= 0) {
      await _storage.delete(key: '$_downloadTitleKeyPrefix$attachmentID');
      await _storage.delete(key: '$_downloadFeedTitleKeyPrefix$attachmentID');
      _downloadTitleCache.remove(attachmentID);
      _downloadFeedTitleCache.remove(attachmentID);
      _downloadNewsIdCache.remove(attachmentID);
      _downloadMediaProgressionCache.remove(attachmentID);
    }
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
      await _storage.delete(key: '$_downloadTitleKeyPrefix$attachmentID');
      await _storage.delete(key: '$_downloadFeedTitleKeyPrefix$attachmentID');
      _downloadTitleCache.remove(attachmentID);
      _downloadFeedTitleCache.remove(attachmentID);
      _downloadNewsIdCache.remove(attachmentID);
      _downloadMediaProgressionCache.remove(attachmentID);
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
          await _storage.delete(key: '$_downloadTitleKeyPrefix$attachmentID');
          await _storage.delete(key: '$_downloadFeedTitleKeyPrefix$attachmentID');
          _downloadTitleCache.remove(attachmentID);
          _downloadFeedTitleCache.remove(attachmentID);
          _downloadNewsIdCache.remove(attachmentID);
          _downloadMediaProgressionCache.remove(attachmentID);
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

  static Future<String?> downloadAttachment(Attachment attachment, {bool onlyOnWifi = false, News? news}) async {
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
    _activeClients[storageAttachmentId] = client;
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
      // Cache title before emitting the first progress event so the download
      // banner shows the episode title immediately (not just the filename).
      if (news != null && storageAttachmentId >= 0) {
        cacheDownloadTitle(storageAttachmentId, news.title);
        cacheDownloadFeedTitle(storageAttachmentId, news.feedTitle);
        cacheDownloadNewsId(storageAttachmentId, news.newsID);
      }
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
        _emitDownloadedAudiosChanged();
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
      await _precacheArtworkForDownloadedAudio(
        attachment: attachment,
        downloadedFilePath: filePath,
        news: news,
      );
      if (news != null && storageAttachmentId >= 0) {
        cacheDownloadTitle(storageAttachmentId, news.title);
        cacheDownloadFeedTitle(storageAttachmentId, news.feedTitle);
        cacheDownloadNewsId(storageAttachmentId, news.newsID);
      }
      clearUserSkipped(storageAttachmentId).ignore();
      _emitDownloadedAudiosChanged();
      _removeActiveDownload(storageAttachmentId);

      return filePath;
    } finally {
      _activeClients.remove(storageAttachmentId);
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
        final storageId = _resolveStorageAttachmentId(attachment);
        if (await isUserSkipped(storageId)) continue;
        await queueDownload(attachment, onlyOnWifi: onlyOnWifi, news: news);
      }
    }
  }
}
