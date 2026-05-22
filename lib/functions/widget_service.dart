import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/functions/sync_news.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:provider/provider.dart';

class FluxNewsWidgetService {
  static const MethodChannel _channel =
      MethodChannel('dev.kevincfechtel.fluxnews/widgets');
  static Map<String, dynamic>? _pendingWidgetAction;
  static bool _handlingWidgetAction = false;

  static Future<void> updateWidgetSnapshot(FluxNewsState appState) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final news =
        await queryWidgetNewsFromDB(appState, limit: Platform.isIOS ? 7 : null);
    final unreadCount = await queryUnreadNewsCountFromDB(appState);
    final payload = <String, Object?>{
      'unreadCount': unreadCount,
      'lastUpdated': DateTime.now().toIso8601String(),
      'items': news.map(_widgetItemFromNews).toList(),
    };

    await _channel
        .invokeMethod<void>('saveSnapshot', {'snapshot': jsonEncode(payload)});
    await _channel.invokeMethod<void>('reloadWidgets');
  }

  static Future<void> handlePendingWidgetAction(
      BuildContext context, FluxNewsState appState) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_handlingWidgetAction) return;

    final action = await takePendingWidgetAction();
    if (action == null || action.isEmpty) return;
    if (!context.mounted) return;

    _handlingWidgetAction = true;
    try {
      switch (action['action']) {
        case 'sync':
          await syncNews(appState, context);
          await updateWidgetSnapshot(appState);
          break;
        case 'openNews':
          final newsID = int.tryParse(action['newsID']?.toString() ?? '');
          if (newsID == null) break;
          final news = await queryNewsByIdFromDB(appState, newsID);
          if (news == null || !context.mounted) break;
          await openNewsAction(
              news, appState, context, appState.widgetOpenMiniflux);
          if (!context.mounted) break;
          appState.newsList = queryNewsFromDB(appState).whenComplete(() {
            appState.jumpToItem(appState.scrollPosition);
          });
          context.read<FluxNewsCounterState>().listUpdated = true;
          context.read<FluxNewsCounterState>().refreshView();
          appState.refreshView();
          await updateWidgetSnapshot(appState);
          break;
      }
    } finally {
      _pendingWidgetAction = null;
      _handlingWidgetAction = false;
    }
  }

  static Future<bool> shouldSkipStartupSyncForPendingOpenNews() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      final action = await peekPendingWidgetAction();
      return action?['action'] == 'openNews';
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> peekPendingWidgetAction() async {
    if (_pendingWidgetAction != null) return _pendingWidgetAction;

    return _channel
        .invokeMapMethod<String, dynamic>('peekPendingAction')
        .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
  }

  static Future<Map<String, dynamic>?> takePendingWidgetAction() async {
    if (_pendingWidgetAction != null) return _pendingWidgetAction;

    _pendingWidgetAction =
        await _channel.invokeMapMethod<String, dynamic>('takePendingAction');
    return _pendingWidgetAction;
  }

  static Map<String, Object?> _widgetItemFromNews(News news) {
    final iconMimeType = news.iconMimeType ?? '';
    final isNativeImage = iconMimeType != 'image/svg+xml';
    return {
      'id': news.newsID,
      'title': news.title,
      'feedTitle': news.feedTitle,
      'publishedAt': news.publishedAt,
      'status': news.status,
      'feedInitial':
          news.feedTitle.trim().isEmpty ? '' : news.feedTitle.trim()[0],
      'iconMimeType': iconMimeType,
      'iconData':
          isNativeImage && news.icon != null ? base64Encode(news.icon!) : '',
      'manualAdaptLightModeToIcon': news.manualAdaptLightModeToIcon ?? false,
      'manualAdaptDarkModeToIcon': news.manualAdaptDarkModeToIcon ?? false,
    };
  }
}
