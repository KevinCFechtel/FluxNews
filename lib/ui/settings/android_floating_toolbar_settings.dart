import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/settings/adaptive_settings_scaffold.dart';
import 'package:provider/provider.dart';

class AndroidFloatingToolbarSettingsTile extends StatelessWidget {
  const AndroidFloatingToolbarSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 5, end: 0),
      leading: const Icon(Icons.dashboard_customize_outlined),
      title: Text(
        strings.androidFloatingToolbarActions,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const AndroidFloatingToolbarSettings(),
        ),
      ),
    );
  }
}

class AndroidFloatingToolbarSettings extends StatefulWidget {
  const AndroidFloatingToolbarSettings({super.key});

  @override
  State<AndroidFloatingToolbarSettings> createState() =>
      _AndroidFloatingToolbarSettingsState();
}

class _AndroidFloatingToolbarSettingsState
    extends State<AndroidFloatingToolbarSettings> {
  late final List<String> _orderedActions;
  late final Set<String> _selectedActions;

  @override
  void initState() {
    super.initState();
    final appState = context.read<FluxNewsState>();
    _orderedActions = List<String>.of(
      appState.androidFloatingToolbarActionOrder,
    );
    _selectedActions = appState.androidFloatingToolbarActions.toSet();
  }

  void _persistActions() {
    context.read<FluxNewsState>().updateAndroidFloatingToolbarActions(
          _orderedActions
              .where(_selectedActions.contains)
              .toList(growable: false),
          orderedActions: _orderedActions,
        );
  }

  void _setSelected(String action, bool selected) {
    setState(() {
      if (selected) {
        _selectedActions.add(action);
      } else {
        _selectedActions.remove(action);
      }
    });
    _persistActions();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return AdaptiveSettingsScaffold(
      title: strings.androidFloatingToolbarActions,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text(
                    strings.androidFloatingToolbarFixedActionsHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: MediaQuery.paddingOf(context).bottom + 16,
                    ),
                    buildDefaultDragHandles: false,
                    itemCount: _orderedActions.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final action = _orderedActions.removeAt(oldIndex);
                        _orderedActions.insert(newIndex, action);
                      });
                      _persistActions();
                    },
                    itemBuilder: (context, index) {
                      final action = _orderedActions[index];
                      final selected = _selectedActions.contains(action);
                      return Card(
                        key: ValueKey(action),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsetsDirectional.only(
                            start: 16,
                            end: 4,
                          ),
                          minVerticalPadding: 12,
                          leading: Icon(_actionIcon(action)),
                          title: Text(
                            _actionLabel(strings, action),
                          ),
                          onTap: () => _setSelected(action, !selected),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: (value) =>
                                    _setSelected(action, value ?? false),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _actionLabel(
    AppLocalizations strings,
    String action,
  ) {
    if (action == FluxNewsState.androidFloatingActionNewsStatus) {
      return strings.androidFloatingActionToggleNewsStatus;
    }
    if (action == FluxNewsState.androidFloatingActionSortOrder) {
      return strings.androidFloatingActionToggleSortOrder;
    }
    if (action == FluxNewsState.androidFloatingActionMarkAsRead) {
      return strings.markAsRead;
    }
    if (action == FluxNewsState.androidFloatingActionPodcasts) {
      return strings.audioDownloadsSettings;
    }
    if (action == FluxNewsState.androidFloatingActionSearch) {
      return strings.search;
    }
    return strings.settings;
  }

  IconData _actionIcon(String action) {
    if (action == FluxNewsState.androidFloatingActionNewsStatus) {
      return Icons.filter_alt_outlined;
    }
    if (action == FluxNewsState.androidFloatingActionSortOrder) {
      return Icons.swap_vert;
    }
    if (action == FluxNewsState.androidFloatingActionMarkAsRead) {
      return Icons.check_circle_outline;
    }
    if (action == FluxNewsState.androidFloatingActionPodcasts) {
      return Icons.podcasts;
    }
    if (action == FluxNewsState.androidFloatingActionSearch) {
      return Icons.search;
    }
    return Icons.settings;
  }
}
