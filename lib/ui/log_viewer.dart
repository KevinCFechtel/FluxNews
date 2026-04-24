import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';

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

  /// Parses a single log line produced by flutter_logs.
  /// Format: "TIMESTAMP: {tag} {module} {message} {LEVEL}"
  static LogEntry? parse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Locate the timestamp/body boundary
    final colonBrace = trimmed.indexOf(': {');
    if (colonBrace < 0) return null;
    final timestamp = trimmed.substring(0, colonBrace);
    final rest = trimmed.substring(colonBrace + 2); // starts with "{"

    // Level is always the last {TOKEN}
    String? level;
    int levelStart = -1;
    for (final lvl in const ['INFO', 'WARNING', 'ERROR', 'SEVERE']) {
      if (rest.endsWith('{$lvl}')) {
        level = lvl;
        levelStart = rest.length - lvl.length - 2;
        break;
      }
    }
    if (level == null) return null;

    // Strip level from end → "{tag} {module} {message}"
    final middle = rest.substring(0, levelStart).trim();

    // Skip {tag}
    if (!middle.startsWith('{')) return null;
    final tagEnd = middle.indexOf('}');
    if (tagEnd < 0) return null;

    // Parse {module}
    final afterTag = middle.substring(tagEnd + 1).trim();
    if (!afterTag.startsWith('{')) return null;
    final moduleEnd = afterTag.indexOf('}');
    if (moduleEnd < 0) return null;
    final module = afterTag.substring(1, moduleEnd);

    // Everything remaining is {message}
    var message = afterTag.substring(moduleEnd + 1).trim();
    if (message.startsWith('{') && message.endsWith('}')) {
      message = message.substring(1, message.length - 1);
    }

    return LogEntry(
      timestamp: timestamp,
      level: level,
      module: module,
      message: message,
    );
  }
}

// ── Service (singleton fed from main.dart) ──────────────────────────────────

class LogPrintedService {
  LogPrintedService._();
  static final LogPrintedService instance = LogPrintedService._();

  final StreamController<String> _controller = StreamController<String>.broadcast();
  Stream<String> get stream => _controller.stream;

  void addChunk(String text) {
    if (!_controller.isClosed) _controller.add(text);
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
  StreamSubscription<String>? _sub;
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
    _sub?.cancel();
    _sub = LogPrintedService.instance.stream.listen((chunk) {
      final newEntries = chunk
          .split('\n')
          .map(LogEntry.parse)
          .whereType<LogEntry>()
          .toList(growable: false);
      if (newEntries.isNotEmpty && mounted) {
        setState(() => _addEntries(newEntries));
      }
    });
    await FlutterLogs.printLogs(exportType: ExportType.ALL);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _loading
              ? 'Logs …'
              : _capped
                  ? 'Logs (${filtered.length}) — letzte $_maxEntries'
                  : 'Logs (${filtered.length})',
          style: theme.textTheme.titleLarge,
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: AppLocalizations.of(context)!.reload,
              onPressed: _load,
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: AppLocalizations.of(context)!.clearList,
            onPressed: () => setState(() => _entries.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
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
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          // Level filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _levels.map((lvl) {
                  final selected = _levelFilter == lvl;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FilterChip(
                      label: Text(
                        lvl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected && lvl != 'ALL' ? _levelColor(lvl, context) : null,
                          fontWeight: selected ? FontWeight.bold : null,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) => setState(() => _levelFilter = lvl),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const Divider(height: 1),

          // Log list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _loading ? AppLocalizations.of(context)!.loading : AppLocalizations.of(context)!.noEntries,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final levelColor = _levelColor(entry.level, context);
                      return InkWell(
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(
                            text: '${entry.timestamp}: [${entry.level}] ${entry.module}: ${entry.message}',
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
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: levelColor.withAlpha(30),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      entry.level,
                                      style: theme.textTheme.labelSmall?.copyWith(color: levelColor),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    entry.module,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      entry.timestamp,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                entry.message,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
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
    );
  }
}
