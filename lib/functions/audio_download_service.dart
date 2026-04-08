import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/models/news_model.dart';
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

class AudioDownloadService {
  static const _storage = sec_store.FlutterSecureStorage();
  static const String _downloadPathKeyPrefix = 'audio_download_path_';
  static const String _downloadTimestampKeyPrefix = 'audio_download_ts_';
  static const String _defaultArtworkAssetPath = 'assets/Flux_News_Starticon_Blue_IOS.png';
  static const String _defaultArtworkFileName = 'default_audio_artwork.png';

  static String _downloadPathKey(int attachmentID) => '$_downloadPathKeyPrefix$attachmentID';
  static String _downloadTimestampKey(int attachmentID) => '$_downloadTimestampKeyPrefix$attachmentID';

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

  static Future<List<AudioChapter>> readChapters(String filePath) async {
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
          final chapter = _parseChapFrame(tagData.sublist(offset + 10, offset + 10 + frameSize), version);
          if (chapter != null) {
            chapters.add(chapter);
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

  static AudioChapter? _parseChapFrame(Uint8List data, int version) {
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
      title: (title == null || title.trim().isEmpty) ? 'Kapitel ab ${_formatChapterTime(startMs)}' : title.trim(),
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
      final storedPath = await _storage.read(key: _downloadPathKey(attachment.attachmentID));
      if (storedPath == null || storedPath.isEmpty) continue;

      final file = File(storedPath);
      if (await file.exists()) {
        downloadedPaths[attachment.attachmentID] = storedPath;
      } else {
        await _storage.delete(key: _downloadPathKey(attachment.attachmentID));
        await _storage.delete(key: _downloadTimestampKey(attachment.attachmentID));
      }
    }

    return downloadedPaths;
  }

  static Future<void> cleanupExpiredDownloads(int retentionDays) async {
    if (retentionDays <= 0) return;

    final now = DateTime.now();
    final appSupport = await getApplicationSupportDirectory();
    final audioDirectory = Directory(p.join(appSupport.path, 'audio_cache'));

    final allValues = await _storage.readAll();
    final trackedPaths = <String>{};

    for (final entry in allValues.entries) {
      if (!entry.key.startsWith(_downloadPathKeyPrefix)) continue;

      final idString = entry.key.substring(_downloadPathKeyPrefix.length);
      final attachmentID = int.tryParse(idString);
      if (attachmentID == null) continue;

      final storedPath = entry.value;
      if (storedPath.isEmpty) continue;

      final file = File(storedPath);
      if (!await file.exists()) {
        await _storage.delete(key: _downloadPathKey(attachmentID));
        await _storage.delete(key: _downloadTimestampKey(attachmentID));
        continue;
      }

      bool isExpired = false;
      final storedTimestamp = allValues[_downloadTimestampKey(attachmentID)];
      if (storedTimestamp != null && storedTimestamp.isNotEmpty) {
        final parsedTimestamp = DateTime.tryParse(storedTimestamp);
        if (parsedTimestamp != null) {
          isExpired = now.difference(parsedTimestamp).inDays >= retentionDays;
        }
      }

      if (!isExpired && (storedTimestamp == null || DateTime.tryParse(storedTimestamp) == null)) {
        final stat = await file.stat();
        isExpired = now.difference(stat.modified).inDays >= retentionDays;
      }

      if (isExpired) {
        await file.delete();
        await _storage.delete(key: _downloadPathKey(attachmentID));
        await _storage.delete(key: _downloadTimestampKey(attachmentID));
      } else {
        trackedPaths.add(storedPath);
        if (storedTimestamp == null || DateTime.tryParse(storedTimestamp) == null) {
          await _storage.write(
            key: _downloadTimestampKey(attachmentID),
            value: now.toIso8601String(),
          );
        }
      }
    }

    if (!await audioDirectory.exists()) return;

    await for (final entity in audioDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (trackedPaths.contains(entity.path)) continue;

      final stat = await entity.stat();
      if (now.difference(stat.modified).inDays >= retentionDays) {
        await entity.delete();
      }
    }
  }

  static Future<String?> downloadAttachment(Attachment attachment, {bool onlyOnWifi = false}) async {
    if (attachment.attachmentURL.isEmpty) return null;

    final existingPath = await _storage.read(key: _downloadPathKey(attachment.attachmentID));
    if (existingPath != null && existingPath.isNotEmpty) {
      final existingFile = File(existingPath);
      if (await existingFile.exists()) {
        return existingPath;
      }
      await _storage.delete(key: _downloadPathKey(attachment.attachmentID));
      await _storage.delete(key: _downloadTimestampKey(attachment.attachmentID));
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
      final audioDirectory = Directory(p.join(appSupport.path, 'audio_cache'));
      if (!await audioDirectory.exists()) {
        await audioDirectory.create(recursive: true);
      }

      final uri = Uri.tryParse(attachment.attachmentURL);
      final extension = uri != null ? p.extension(uri.path) : '';
      final filePath = p.join(
        audioDirectory.path,
        'audio_${attachment.attachmentID}_${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      final file = File(filePath);
      await response.pipe(file.openWrite());

      await _storage.write(key: _downloadPathKey(attachment.attachmentID), value: filePath);
      await _storage.write(
        key: _downloadTimestampKey(attachment.attachmentID),
        value: DateTime.now().toIso8601String(),
      );

      return filePath;
    } finally {
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
