import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:provider/provider.dart';

import '../../state_management/flux_news_state.dart';

class WidgetSettings extends StatelessWidget {
  const WidgetSettings({super.key});

  static const List<KeyValueRecordType> _statusOptions = <KeyValueRecordType>[
    KeyValueRecordType(
        key: FluxNewsState.widgetStatusUnreadString, value: 'Unread'),
    KeyValueRecordType(key: FluxNewsState.widgetStatusAllString, value: 'All'),
    KeyValueRecordType(
        key: FluxNewsState.widgetStatusBookmarkedString, value: 'Bookmarked'),
  ];
  static const List<KeyValueRecordType> _sortOptions = <KeyValueRecordType>[
    KeyValueRecordType(
        key: FluxNewsState.sortOrderNewestFirstString, value: 'Newest first'),
    KeyValueRecordType(
        key: FluxNewsState.sortOrderOldestFirstString, value: 'Oldest first'),
  ];

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<FluxNewsState>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Widget settings'),
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(12),
          alignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              _DropdownRow<KeyValueRecordType>(
                icon: Icons.article_outlined,
                label: 'Items',
                value: _statusOptions.firstWhere(
                  (item) => item.key == appState.widgetNewsStatus,
                  orElse: () => _statusOptions.first,
                ),
                items: _statusOptions
                    .map((option) => DropdownMenuItem<KeyValueRecordType>(
                          value: option,
                          child: Text(option.value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  appState.widgetNewsStatus = value.key;
                  appState.storage.write(
                      key: FluxNewsState.secureStorageWidgetNewsStatusKey,
                      value: value.key);
                  _refreshWidgets(appState);
                },
              ),
              const Divider(),
              _DropdownRow<KeyValueRecordType>(
                icon: Icons.sort,
                label: 'Sort order',
                value: _sortOptions.firstWhere(
                  (item) => item.key == appState.widgetSortOrder,
                  orElse: () => _sortOptions.first,
                ),
                items: _sortOptions
                    .map((option) => DropdownMenuItem<KeyValueRecordType>(
                          value: option,
                          child: Text(option.value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  appState.widgetSortOrder = value.key;
                  appState.storage.write(
                      key: FluxNewsState.secureStorageWidgetSortOrderKey,
                      value: value.key);
                  _refreshWidgets(appState);
                },
              ),
              const Divider(),
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                        left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(Icons.open_in_browser),
                  ),
                  Expanded(
                    child: Text(
                      'Open Miniflux entry',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.widgetOpenMiniflux,
                    onChanged: (value) {
                      appState.widgetOpenMiniflux = value;
                      appState.storage.write(
                        key: FluxNewsState.secureStorageWidgetOpenMinifluxKey,
                        value: value
                            ? FluxNewsState.secureStorageTrueString
                            : FluxNewsState.secureStorageFalseString,
                      );
                      _refreshWidgets(appState);
                    },
                  ),
                ],
              ),
              const Divider(),
            ],
          ),
        ),
      ),
    );
  }

  void _refreshWidgets(FluxNewsState appState) {
    appState.refreshView();
    unawaited(FluxNewsWidgetService.updateWidgetSnapshot(appState));
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding:
              EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
          child: Icon(icon),
        ),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.visible,
          ),
        ),
        DropdownButton<T>(
          value: value,
          elevation: 16,
          underline: Container(height: 2),
          alignment: AlignmentDirectional.centerEnd,
          onChanged: onChanged,
          items: items,
        ),
      ],
    );
  }
}
