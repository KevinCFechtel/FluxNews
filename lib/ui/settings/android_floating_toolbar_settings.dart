import 'package:material_ui/material_ui.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:flux_news/ui/settings/adaptive_settings_scaffold.dart';
import 'package:provider/provider.dart';

class AndroidFloatingToolbarSettingsTile extends StatelessWidget {
  const AndroidFloatingToolbarSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return AdaptiveSettingsNavigationRow(
      icon: Icons.dashboard_customize_outlined,
      title: strings.androidFloatingToolbarActions,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const AndroidFloatingToolbarSettings(),
        ),
      ),
    );
  }
}

class IOSToolbarSettingsTile extends StatelessWidget {
  const IOSToolbarSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return AdaptiveSettingsNavigationRow(
      icon: Icons.dashboard_customize_outlined,
      title: strings.androidFloatingToolbarActions,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              const AndroidFloatingToolbarSettings(iosToolbar: true),
        ),
      ),
    );
  }
}

class AndroidFloatingToolbarSettings extends StatefulWidget {
  const AndroidFloatingToolbarSettings({
    super.key,
    this.iosToolbar = false,
  });

  final bool iosToolbar;

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
      widget.iosToolbar
          ? appState.iosToolbarActionOrder
          : appState.androidFloatingToolbarActionOrder,
    );
    _selectedActions = (widget.iosToolbar
            ? appState.iosToolbarActions
            : appState.androidFloatingToolbarActions)
        .toSet();
  }

  void _persistActions() {
    final appState = context.read<FluxNewsState>();
    final selectedActions = _orderedActions
        .where(_selectedActions.contains)
        .toList(growable: false);
    if (widget.iosToolbar) {
      appState.updateIOSToolbarActions(
        selectedActions,
        orderedActions: _orderedActions,
      );
    } else {
      appState.updateAndroidFloatingToolbarActions(
        selectedActions,
        orderedActions: _orderedActions,
      );
    }
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
                    widget.iosToolbar
                        ? strings.iosToolbarActionsHint
                        : strings.androidFloatingToolbarFixedActionsHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      MediaQuery.paddingOf(context).bottom + 16,
                    ),
                    child: AdaptiveSettingsGroupSurface(
                      child: ReorderableListView.builder(
                        padding: EdgeInsets.zero,
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
                          return Column(
                            key: ValueKey(action),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                contentPadding:
                                    const EdgeInsetsDirectional.only(
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
                                    Checkbox.adaptive(
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
                              if (index < _orderedActions.length - 1)
                                const Divider(),
                            ],
                          );
                        },
                      ),
                    ),
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
    if (action == FluxNewsState.floatingToolbarActionMarkAsReadAndNext) {
      return strings.markAsReadAndNext;
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
    if (action == FluxNewsState.floatingToolbarActionMarkAsReadAndNext) {
      return Icons.skip_next;
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
