import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/flux_news_state.dart';

void logThis(String module, String message, LogLevel logLevel) {
  FlutterLogs.logThis(
      tag: FluxNewsState.logTag,
      subTag: module,
      logMessage: message,
      level: logLevel);
}
