// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart' as logger;
import 'package:path_provider/path_provider.dart';

enum LogLevel {
  INFO,
  WARNING,
  ERROR,
  SEVERE,
}

final logger.Logger _consoleLogger = logger.Logger(
  printer: logger.SimplePrinter(colors: false, printTime: false),
);

final DateFormat _logDirFormat = DateFormat('ddMMyyyy');
final DateFormat _logFileHourFormat = DateFormat('ddMMyyyyHH');
final DateFormat _timestampFormat = DateFormat('dd MMM yyyy hh:mm:ss a');

Future<File>? _currentLogFileFuture;
Future<void> _writeQueue = Future<void>.value();

Future<void> initFluxNewsLogging() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  _currentLogFileFuture ??= _resolveCurrentLogFile();
  try {
    final file = await _currentLogFileFuture!;
    await file.parent.create(recursive: true);
  } catch (e) {
    debugPrint(
        '${FluxNewsState.logTag}: logging: Could not initialize logs: $e');
  }
}

void logThis(String module, String message, LogLevel logLevel) {
  if (!Platform.isAndroid && !Platform.isIOS) {
    debugPrint('${FluxNewsState.logTag}: $module: $message');
    return;
  }

  final line = _formatLogLine(module, message, logLevel);
  switch (logLevel) {
    case LogLevel.INFO:
      _consoleLogger.i(line);
      break;
    case LogLevel.WARNING:
      _consoleLogger.w(line);
      break;
    case LogLevel.ERROR:
    case LogLevel.SEVERE:
      _consoleLogger.e(line);
      break;
  }

  unawaited(_enqueueLogWrite('$line\n'));
}

Future<String> readFluxNewsLogs() async {
  if (!Platform.isAndroid && !Platform.isIOS) return '';
  final buffer = StringBuffer();
  final root = await _resolveLogRootDirectory();
  if (!await root.exists()) return '';

  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File && _isLogFile(entity)) files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    try {
      buffer.write(await file.readAsString());
      if (!buffer.toString().endsWith('\n')) buffer.writeln();
    } catch (_) {
      // Ignore unreadable log files.
    }
  }
  return buffer.toString();
}

Future<void> clearFluxNewsLogs() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    final root = await _resolveLogRootDirectory();
    if (await root.exists()) await root.delete(recursive: true);
    _currentLogFileFuture = _resolveCurrentLogFile();
    await initFluxNewsLogging();
  } catch (e) {
    debugPrint('${FluxNewsState.logTag}: logging: Could not clear logs: $e');
  }
}

String _formatLogLine(String module, String message, LogLevel logLevel) {
  final timestamp = _timestampFormat.format(DateTime.now());
  final escapedMessage = message.replaceAll('\n', r'\n');
  return '{${FluxNewsState.logTag}}  {$module}  {$escapedMessage}  '
      '{$timestamp}  {${logLevel.name}}';
}

Future<void> _enqueueLogWrite(String line) {
  _writeQueue = _writeQueue.then((_) => _writeLogLine(line)).catchError((e) {
    debugPrint('${FluxNewsState.logTag}: logging: Could not write log: $e');
  });
  return _writeQueue;
}

Future<void> _writeLogLine(String line) async {
  final file = await (_currentLogFileFuture ??= _resolveCurrentLogFile());
  await file.parent.create(recursive: true);
  await file.writeAsString(line, mode: FileMode.append, flush: false);
}

Future<File> _resolveCurrentLogFile() async {
  final now = DateTime.now();
  final Directory baseDir;
  if (Platform.isAndroid) {
    final extDir = await getExternalStorageDirectory();
    baseDir = extDir ?? await getApplicationSupportDirectory();
  } else {
    baseDir = await getApplicationSupportDirectory();
  }

  final datePart = _logDirFormat.format(now);
  final hourPart = _logFileHourFormat.format(now);
  return File(
    '${baseDir.path}/${FluxNewsState.logsWriteDirectoryName}/Logs/'
    '$datePart/$hourPart.log',
  );
}

Future<Directory> _resolveLogRootDirectory() async {
  final Directory baseDir;
  if (Platform.isAndroid) {
    final extDir = await getExternalStorageDirectory();
    baseDir = extDir ?? await getApplicationSupportDirectory();
  } else {
    baseDir = await getApplicationSupportDirectory();
  }

  return Directory('${baseDir.path}/${FluxNewsState.logsWriteDirectoryName}');
}

bool _isLogFile(File file) {
  final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
  return name.endsWith('.log') || name.endsWith('.txt');
}
