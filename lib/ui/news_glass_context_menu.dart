import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// iOS-only replacement for the former [CupertinoContextMenu].
///
/// The most common actions stay in the morphing menu. Less common actions are
/// grouped in a glass action sheet so the menu remains compact and reachable.
class NewsGlassContextMenu extends StatefulWidget {
  const NewsGlassContextMenu({
    super.key,
    required this.news,
    required this.searchView,
    required this.itemIndex,
    required this.newsList,
    required this.child,
  });

  final News news;
  final bool searchView;
  final int itemIndex;
  final List<News>? newsList;
  final Widget child;

  @override
  State<NewsGlassContextMenu> createState() => _NewsGlassContextMenuState();
}

class _NewsGlassContextMenuState extends State<NewsGlassContextMenu> {
  final GlassMenuController _menuController = GlassMenuController();

  void _openMenu() {
    HapticFeedback.mediumImpact();
    _menuController.open();
  }

  void _removeReadItemIfNeeded(FluxNewsState appState) {
    if (!appState.removeNewsFromListWhenRead || widget.searchView) return;
    final index = widget.newsList
        ?.indexWhere((item) => item.newsID == widget.news.newsID);
    if (index != null && index >= 0) widget.newsList?.removeAt(index);
  }

  void _afterMenuCloses(FutureOr<void> Function() action) {
    _menuController.close();
    Future<void>.delayed(const Duration(milliseconds: 260), () async {
      if (!mounted) return;
      await action();
    });
  }

  bool _canSaveToThirdParty(FluxNewsState appState) {
    final version = appState.minifluxVersionString;
    if (version == null) return false;
    if (version.startsWith(RegExp(r'[01]|2\.0'))) {
      return appState.minifluxVersionInt >=
          FluxNewsState.minifluxSaveMinVersion;
    }
    return true;
  }

  void _toggleReadStatus(FluxNewsState appState) {
    final counter = context.read<FluxNewsCounterState>();
    if (widget.news.status == FluxNewsState.readNewsStatus) {
      markNewsAsUnreadAction(
          widget.news, appState, context, widget.searchView, counter);
    } else {
      markNewsAsReadAction(
          widget.news, appState, context, widget.searchView, counter);
      _removeReadItemIfNeeded(appState);
    }
  }

  void _openNews(FluxNewsState appState, {required bool inMiniflux}) {
    final wasUnread = widget.news.status == FluxNewsState.unreadNewsStatus;
    openNewsAction(widget.news, appState, context, inMiniflux);
    if (wasUnread) _removeReadItemIfNeeded(appState);
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      uri: Uri.parse(widget.news.url),
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  void _showMoreActions(FluxNewsState appState) {
    final strings = AppLocalizations.of(context)!;
    final actions = <GlassActionSheetAction>[
      GlassActionSheetAction(
        label: strings.openMinifluxShort,
        icon: const Icon(Icons.open_in_browser),
        onPressed: () {
          Navigator.of(context).pop();
          _openNews(appState, inMiniflux: true);
        },
      ),
      if (_canSaveToThirdParty(appState))
        GlassActionSheetAction(
          label: strings.contextSaveButton,
          icon: const Icon(Icons.save),
          onPressed: () {
            Navigator.of(context).pop();
            saveToThirdPartyAction(widget.news, appState, context);
          },
        ),
      if (widget.news.getAudioAttachments().isNotEmpty)
        GlassActionSheetAction(
          label: strings.downloadAudio,
          icon: const Icon(Icons.download),
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(downloadAudioAction(widget.news, appState, context));
          },
        ),
      if (widget.news.commentsUrl.isNotEmpty)
        GlassActionSheetAction(
          label: strings.openComments,
          icon: const Icon(Icons.comment),
          onPressed: () {
            Navigator.of(context).pop();
            openNewsCommentsAction(widget.news, context);
          },
        ),
    ];

    showGlassActionSheet<void>(
      context: context,
      title: strings.moreActions,
      cancelLabel: strings.cancel,
      quality: GlassQuality.standard,
      actions: actions,
    );
  }

  List<Widget> _items(FluxNewsState appState) {
    final strings = AppLocalizations.of(context)!;
    return <Widget>[
      GlassMenuItem(
        title:
            widget.news.starred ? strings.deleteBookmark : strings.addBookmark,
        icon: Icon(widget.news.starred ? Icons.star_outline : Icons.star),
        onTap: () => _afterMenuCloses(
          () =>
              bookmarkAction(widget.news, appState, context, widget.searchView),
        ),
      ),
      GlassMenuItem(
        title: widget.news.status == FluxNewsState.readNewsStatus
            ? strings.markAsUnread
            : strings.markAsRead,
        icon: Icon(widget.news.status == FluxNewsState.readNewsStatus
            ? Icons.fiber_new
            : Icons.check),
        onTap: () => _afterMenuCloses(() => _toggleReadStatus(appState)),
      ),
      GlassMenuItem(
        title: strings.open,
        icon: const Icon(Icons.open_in_new),
        onTap: () => _afterMenuCloses(
          () => _openNews(appState, inMiniflux: false),
        ),
      ),
      GlassMenuItem(
        title: strings.share,
        icon: const Icon(Icons.share),
        onTap: () => _afterMenuCloses(_share),
      ),
      const GlassMenuDivider(),
      GlassMenuItem(
        title: strings.moreActions,
        icon: const Icon(Icons.more_horiz),
        onTap: () => _afterMenuCloses(() => _showMoreActions(appState)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<FluxNewsState>();
    final menuLabel = AppLocalizations.of(context)!.menu;
    return Semantics(
      onLongPress: _openMenu,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: menuLabel): _openMenu,
      },
      child: GlassMenu(
        controller: _menuController,
        quality: GlassQuality.standard,
        autoAdjustToScreen: true,
        menuPadding: const EdgeInsets.all(12),
        menuWidth: 280,
        menuHeight: 330,
        morphFromZero: true,
        items: _items(appState),
        triggerBuilder: (context, toggleMenu) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: _openMenu,
          child: widget.child,
        ),
      ),
    );
  }
}
