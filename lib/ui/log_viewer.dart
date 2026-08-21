import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:flux_news/ui/settings/adaptive_settings_scaffold.dart';

/// Keeps normal touch scrolling while preventing focused text fields from
/// moving the collapsing navigation hierarchy through showOnScreen requests.
class _NoImplicitScrollingPhysics extends ScrollPhysics {
  const _NoImplicitScrollingPhysics({super.parent});

  @override
  _NoImplicitScrollingPhysics applyTo(ScrollPhysics? ancestor) {
    return _NoImplicitScrollingPhysics(parent: buildParent(ancestor));
  }

  @override
  bool get allowImplicitScrolling => false;
}

// ── Data ────────────────────────────────────────────────────────────────────

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.module,
    required this.message,
  });

  final String timestamp;
  final String level; // INFO | WARNING | ERROR | SEVERE
  final String module;
  final String message;

  /// Parses a single Flux News log line.
  ///
  /// iOS:     "TIMESTAMP: {tag} {module} {message} {LEVEL}"
  /// Android: "{tag}  {module}  {message}  {TIMESTAMP}  {LEVEL}"
  ///   (PLog's formatCurly puts timestamp 4th, not 1st)
  static LogEntry? parse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Level is always the last {TOKEN}.
    String? level;
    int levelStart = -1;
    for (final lvl in const ['INFO', 'WARNING', 'ERROR', 'SEVERE']) {
      if (trimmed.endsWith('{$lvl}')) {
        level = lvl;
        levelStart = trimmed.length - lvl.length - 2;
        break;
      }
    }
    if (level == null) return null;

    final withoutLevel = trimmed.substring(0, levelStart).trim();

    if (withoutLevel.startsWith('{')) {
      // Android: {tag}  {module}  {message}  {timestamp}
      final blocks = _blocks(withoutLevel);
      if (blocks.length < 4) return null;
      return LogEntry(
        timestamp: blocks[3],
        level: level,
        module: blocks[1],
        message: blocks[2],
      );
    } else {
      // iOS: TIMESTAMP: {tag} {module} {message}
      final sep = withoutLevel.indexOf(': {');
      if (sep < 0) return null;
      final blocks = _blocks(withoutLevel.substring(sep + 2));
      if (blocks.length < 3) return null;
      return LogEntry(
        timestamp: withoutLevel.substring(0, sep),
        level: level,
        module: blocks[1],
        message: blocks[2],
      );
    }
  }

  /// Extracts all `{...}` blocks from [s], ignoring nested braces.
  static List<String> _blocks(String s) {
    final result = <String>[];
    int i = 0;
    while (i < s.length) {
      final open = s.indexOf('{', i);
      if (open < 0) break;
      final close = s.indexOf('}', open);
      if (close < 0) break;
      result.add(s.substring(open + 1, close));
      i = close + 1;
    }
    return result;
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  static const int _maxEntries = 5000;

  final List<LogEntry> _entries = [];
  bool _loading = false;
  bool _capped = false; // true when older entries were dropped due to cap
  String _search = '';
  String _levelFilter = 'ALL';
  final TextEditingController _searchController = TextEditingController();

  // Cached filtered list — only rebuilt when inputs change.
  List<LogEntry>? _filteredCache;
  String _cacheSearch = '';
  String _cacheLevelFilter = 'ALL';
  int _cacheEntriesLength = -1;

  static const _levels = ['ALL', 'INFO', 'WARNING', 'ERROR', 'SEVERE'];

  static Color _levelColor(String level, BuildContext context) {
    switch (level) {
      case 'ERROR':
      case 'SEVERE':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  List<LogEntry> get _filtered {
    if (_filteredCache != null &&
        _cacheSearch == _search &&
        _cacheLevelFilter == _levelFilter &&
        _cacheEntriesLength == _entries.length) {
      return _filteredCache!;
    }
    _filteredCache = _entries.reversed.where((e) {
      if (_levelFilter != 'ALL' && e.level != _levelFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        return e.message.toLowerCase().contains(q) ||
            e.module.toLowerCase().contains(q);
      }
      return true;
    }).toList(growable: false);
    _cacheSearch = _search;
    _cacheLevelFilter = _levelFilter;
    _cacheEntriesLength = _entries.length;
    return _filteredCache!;
  }

  void _addEntries(List<LogEntry> newEntries) {
    _entries.addAll(newEntries);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
      _capped = true;
    }
    _filteredCache = null; // invalidate cache
  }

  Future<void> _load() async {
    setState(() {
      _entries.clear();
      _filteredCache = null;
      _capped = false;
      _loading = true;
    });
    final logText = await readFluxNewsLogs();
    final newEntries = logText
        .split('\n')
        .map(LogEntry.parse)
        .whereType<LogEntry>()
        .toList(growable: false);
    if (!mounted) return;
    setState(() {
      _addEntries(newEntries);
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final theme = Theme.of(context);
    final title = _loading
        ? 'Logs …'
        : _capped
            ? 'Logs (${filtered.length}) — ${AppLocalizations.of(context)!.last} $_maxEntries'
            : 'Logs (${filtered.length})';

    return AdaptiveSettingsScaffold(
      title: title,
      useLargeTitle: true,
      iosScrollPhysics: const _NoImplicitScrollingPhysics(),
      actions: [
        AdaptiveSettingsIconButton(
          icon: const Icon(Icons.refresh),
          tooltip: AppLocalizations.of(context)!.reload,
          loading: _loading,
          onPressed: _loading ? null : _load,
        ),
        AdaptiveSettingsIconButton(
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: AppLocalizations.of(context)!.clearList,
          onPressed: _entries.isEmpty
              ? null
              : () => setState(() {
                    _entries.clear();
                    _filteredCache = null;
                  }),
        ),
      ],
      body: _buildBody(context, filtered, theme),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<LogEntry> filtered,
    ThemeData theme,
  ) {
    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: AdaptiveSettingsTextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.search,
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                )
              : null,
        ),
        onChanged: (value) => setState(() => _search = value),
      ),
    );

    final levelFilter = Platform.isIOS
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AdaptiveSettingsDropdown<String>(
                value: _levelFilter,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _levelFilter = value);
                  }
                },
                items: _levels
                    .map(
                      (level) => DropdownMenuItem<String>(
                        value: level,
                        child: Text(level),
                      ),
                    )
                    .toList(),
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _levels.map((level) {
                  final selected = _levelFilter == level;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FilterChip(
                      label: Text(
                        level,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected && level != 'ALL'
                              ? _levelColor(level, context)
                              : null,
                          fontWeight: selected ? FontWeight.bold : null,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) => setState(() => _levelFilter = level),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          );

    final header = <Widget>[
      searchField,
      levelFilter,
      const Divider(height: 1),
    ];

    if (Platform.isIOS) {
      final hasEntries = filtered.isNotEmpty;
      return ListView.builder(
        padding: EdgeInsets.zero,
        physics: const _NoImplicitScrollingPhysics(),
        itemCount: header.length + (hasEntries ? filtered.length : 1),
        itemBuilder: (context, index) {
          if (index < header.length) return header[index];
          if (!hasEntries) {
            return Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Center(child: _buildEmptyMessage(context, theme)),
            );
          }
          return _buildLogEntry(
              context, filtered[index - header.length], theme);
        },
      );
    }

    return Column(
      children: [
        ...header,
        Expanded(
          child: filtered.isEmpty
              ? Center(child: _buildEmptyMessage(context, theme))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildLogEntry(context, filtered[index], theme),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyMessage(BuildContext context, ThemeData theme) {
    return Text(
      _loading
          ? AppLocalizations.of(context)!.loading
          : AppLocalizations.of(context)!.noEntries,
      style: theme.textTheme.bodyMedium,
    );
  }

  Widget _buildLogEntry(
    BuildContext context,
    LogEntry entry,
    ThemeData theme,
  ) {
    final levelColor = _levelColor(entry.level, context);
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(
          text:
              '${entry.timestamp}: [${entry.level}] ${entry.module}: ${entry.message}',
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.copyClipboard),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: levelColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.level,
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: levelColor),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    entry.module,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    softWrap: true,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  entry.timestamp,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (entry.message.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                entry.message,
                style: theme.textTheme.bodySmall,
                softWrap: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
