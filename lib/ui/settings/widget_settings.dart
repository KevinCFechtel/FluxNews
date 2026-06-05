import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:provider/provider.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';

import '../../state_management/flux_news_state.dart';

class WidgetSettings extends StatefulWidget {
  const WidgetSettings({super.key});

  @override
  State<WidgetSettings> createState() => _WidgetSettingsState();
}

class _WidgetSettingsState extends State<WidgetSettings> {
  List<KeyValueRecordType> _categoryOptions = const [];
  List<KeyValueRecordType> _feedOptions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFilterOptions();
    });
  }

  Future<void> _loadFilterOptions() async {
    final appState = context.read<FluxNewsState>();
    final categories = await queryCategoriesFromDB(appState, context);
    if (!mounted) return;
    setState(() {
      _categoryOptions = _buildCategoryOptions(categories);
      _feedOptions = _buildFeedOptions(categories);
    });
  }

  List<KeyValueRecordType> _buildCategoryOptions(Categories categories) {
    return categories.categories
        .map((category) => KeyValueRecordType(
            key: category.categoryID.toString(), value: category.title))
        .toList();
  }

  List<KeyValueRecordType> _buildFeedOptions(Categories categories) {
    return [
      for (final category in categories.categories)
        for (final feed in category.feeds)
          KeyValueRecordType(key: feed.feedID.toString(), value: feed.title)
    ];
  }

  KeyValueRecordType? _selectedCategoryOption(FluxNewsState appState) {
    if (_categoryOptions.isEmpty) return null;
    return _categoryOptions.firstWhere(
      (item) => int.tryParse(item.key) == appState.widgetFilterId,
      orElse: () => _categoryOptions.first,
    );
  }

  KeyValueRecordType? _selectedFeedOption(FluxNewsState appState) {
    if (_feedOptions.isEmpty) return null;
    return _feedOptions.firstWhere(
      (item) => int.tryParse(item.key) == appState.widgetFilterId,
      orElse: () => _feedOptions.first,
    );
  }

  void _applyFilterType(FluxNewsState appState, String type) {
    appState.widgetFilterType = type;
    if (type == FluxNewsState.widgetFilterCategoryString) {
      final hasCurrentCategory = _categoryOptions
          .any((option) => int.tryParse(option.key) == appState.widgetFilterId);
      if (!hasCurrentCategory && _categoryOptions.isNotEmpty) {
        appState.widgetFilterId = int.tryParse(_categoryOptions.first.key);
      }
    } else if (type == FluxNewsState.widgetFilterFeedString) {
      final hasCurrentFeed = _feedOptions
          .any((option) => int.tryParse(option.key) == appState.widgetFilterId);
      if (!hasCurrentFeed && _feedOptions.isNotEmpty) {
        appState.widgetFilterId = int.tryParse(_feedOptions.first.key);
      }
    } else {
      appState.widgetFilterId = null;
    }
    _persistWidgetFilter(appState);
    _refreshWidgets(appState);
  }

  void _applyCategorySelection(
      FluxNewsState appState, KeyValueRecordType value) {
    appState.widgetFilterType = FluxNewsState.widgetFilterCategoryString;
    appState.widgetFilterId = int.tryParse(value.key);
    _persistWidgetFilter(appState);
    _refreshWidgets(appState);
  }

  void _applyFeedSelection(FluxNewsState appState, KeyValueRecordType value) {
    appState.widgetFilterType = FluxNewsState.widgetFilterFeedString;
    appState.widgetFilterId = int.tryParse(value.key);
    _persistWidgetFilter(appState);
    _refreshWidgets(appState);
  }

  void _persistWidgetFilter(FluxNewsState appState) {
    appState.storage.write(
        key: FluxNewsState.secureStorageWidgetFilterTypeKey,
        value: appState.widgetFilterType);
    if (appState.widgetFilterId == null) {
      appState.storage
          .delete(key: FluxNewsState.secureStorageWidgetFilterIdKey);
    } else {
      appState.storage.write(
          key: FluxNewsState.secureStorageWidgetFilterIdKey,
          value: appState.widgetFilterId.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<FluxNewsState>();
    final List<KeyValueRecordType> sortOptions = <KeyValueRecordType>[
      KeyValueRecordType(
          key: FluxNewsState.sortOrderNewestFirstString,
          value: AppLocalizations.of(context)!.newestFirst),
      KeyValueRecordType(
          key: FluxNewsState.sortOrderOldestFirstString,
          value: AppLocalizations.of(context)!.oldestFirst),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(AppLocalizations.of(context)!.widgetSettings),
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(12),
          alignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                        left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(Icons.mark_email_unread_outlined),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.unreadShort,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.widgetUnreadOnly,
                    onChanged: (value) {
                      appState.widgetUnreadOnly = value;
                      appState.widgetNewsStatus = value
                          ? FluxNewsState.widgetStatusUnreadString
                          : FluxNewsState.widgetStatusAllString;
                      appState.storage.write(
                          key: FluxNewsState.secureStorageWidgetUnreadOnlyKey,
                          value: value
                              ? FluxNewsState.secureStorageTrueString
                              : FluxNewsState.secureStorageFalseString);
                      appState.storage.write(
                          key: FluxNewsState.secureStorageWidgetNewsStatusKey,
                          value: appState.widgetNewsStatus);
                      _refreshWidgets(appState);
                    },
                  ),
                ],
              ),
              const Divider(),
              RadioGroup<String>(
                groupValue: appState.widgetFilterType,
                onChanged: (value) {
                  if (value == null) return;
                  _applyFilterType(appState, value);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: Text(AppLocalizations.of(context)!.allNews,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: FluxNewsState.widgetFilterAllString,
                    ),
                    RadioListTile<String>(
                      title: Text(AppLocalizations.of(context)!.bookmarkShort,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: FluxNewsState.widgetFilterBookmarkedString,
                    ),
                    RadioListTile<String>(
                      title: Text(
                          AppLocalizations.of(context)!
                              .startupCategorieCategorie,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: FluxNewsState.widgetFilterCategoryString,
                    ),
                    RadioListTile<String>(
                      title: Text(
                          AppLocalizations.of(context)!.startupCategorieFeed,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: FluxNewsState.widgetFilterFeedString,
                    ),
                  ],
                ),
              ),
              if (appState.widgetFilterType ==
                      FluxNewsState.widgetFilterCategoryString &&
                  _selectedCategoryOption(appState) != null) ...[
                const Divider(),
                _DropdownRow<KeyValueRecordType>(
                  icon: Icons.feed,
                  label: AppLocalizations.of(context)!
                      .startupCategorieCategorieSelection,
                  value: _selectedCategoryOption(appState)!,
                  items: _categoryOptions
                      .map((option) => DropdownMenuItem<KeyValueRecordType>(
                            value: option,
                            child: Text(option.value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    _applyCategorySelection(appState, value);
                  },
                ),
              ],
              if (appState.widgetFilterType ==
                      FluxNewsState.widgetFilterFeedString &&
                  _selectedFeedOption(appState) != null) ...[
                const Divider(),
                _DropdownRow<KeyValueRecordType>(
                  icon: Icons.feed,
                  label: AppLocalizations.of(context)!
                      .startupCategorieFeedSelection,
                  value: _selectedFeedOption(appState)!,
                  items: _feedOptions
                      .map((option) => DropdownMenuItem<KeyValueRecordType>(
                            value: option,
                            child: Text(option.value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    _applyFeedSelection(appState, value);
                  },
                ),
              ],
              const Divider(),
              _DropdownRow<KeyValueRecordType>(
                icon: Icons.sort,
                label: AppLocalizations.of(context)!.sortOrderOfNews,
                value: sortOptions.firstWhere(
                  (item) => item.key == appState.widgetSortOrder,
                  orElse: () => sortOptions.first,
                ),
                items: sortOptions
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
                      AppLocalizations.of(context)!.openMinifluxEntry,
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
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.42,
          ),
          child: DropdownButton<T>(
            value: value,
            elevation: 16,
            underline: Container(height: 2),
            alignment: AlignmentDirectional.centerEnd,
            isExpanded: true,
            selectedItemBuilder: (context) =>
                items.map((item) => _DropdownText(item.child)).toList(),
            onChanged: onChanged,
            items: items
                .map(
                  (item) => DropdownMenuItem<T>(
                    value: item.value,
                    enabled: item.enabled,
                    child: _DropdownText(item.child),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _DropdownText extends StatelessWidget {
  const _DropdownText(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: DefaultTextStyle.merge(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: child,
      ),
    );
  }
}
