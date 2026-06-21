import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

bool _flutterLogsEnabled = true;

void setFlutterLogsEnabled(bool enabled) {
  _flutterLogsEnabled = enabled;
}

void logThis(String module, String message, LogLevel logLevel) {
  if (Platform.isAndroid && !_flutterLogsEnabled) {
    debugPrint('${FluxNewsState.logTag}: $module: $message');
    return;
  }
  FlutterLogs.logThis(
      tag: FluxNewsState.logTag,
      subTag: module,
      logMessage: message,
      level: logLevel);
}
