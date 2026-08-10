import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

/// Keeps the existing Material settings shell on Android and supplies the
/// shared Liquid Glass navigation layer for iOS settings pages.
class AdaptiveSettingsScaffold extends StatefulWidget {
  const AdaptiveSettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.useLargeTitle = false,
    this.iosLargeTitleBody,
    this.actions,
    this.iosScrollPhysics,
  });

  final String title;
  final Widget body;
  final bool useLargeTitle;
  final List<Widget>? actions;
  final ScrollPhysics? iosScrollPhysics;

  /// Non-scrollable content placed below [GlassLargeTitle] on the iOS root
  /// settings page. Android always renders [body].
  final Widget? iosLargeTitleBody;

  @override
  State<AdaptiveSettingsScaffold> createState() =>
      _AdaptiveSettingsScaffoldState();
}

class _AdaptiveSettingsScaffoldState extends State<AdaptiveSettingsScaffold> {
  final GlassLargeTitleController _largeTitleController =
      GlassLargeTitleController();

  @override
  void dispose() {
    _largeTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          actions: widget.actions,
        ),
        body: SafeArea(
          top: false,
          left: false,
          right: false,
          child: widget.body,
        ),
      );
    }

    final appState = context.watch<FluxNewsState>();
    final glassSettings = iosLiquidGlassSettings(
      context,
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassQuality = iosLiquidGlassQuality(
      useClearEffect: appState.iosClearLiquidGlass,
    );
    final glassForeground = iosLiquidGlassForeground(context);
    final compactTitle = GlassContainer(
      useOwnLayer: true,
      quality: glassQuality,
      settings: glassSettings,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: glassForeground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
    final titleController = widget.useLargeTitle ? _largeTitleController : null;
    final appBar = GlassAppBar(
      centerTitle: false,
      largeTitleController: titleController,
      buttonSettings: glassSettings,
      leading: GlassIconButton(
        quality: glassQuality,
        useOwnLayer: true,
        settings: glassSettings,
        semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.maybePop(context),
        icon: Icon(CupertinoIcons.back, color: glassForeground),
      ),
      title: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: compactTitle,
        ),
      ),
      actions: widget.actions ?? const [],
    );

    if (widget.useLargeTitle) {
      final topContentInset = MediaQuery.paddingOf(context).top + 44;
      if (widget.iosLargeTitleBody == null) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: appBar,
          body: NestedScrollView(
            controller: _largeTitleController.scrollController,
            physics: widget.iosScrollPhysics,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(child: SizedBox(height: topContentInset)),
              GlassLargeTitle(
                text: widget.title,
                controller: _largeTitleController,
              ),
            ],
            body: _wideIOSBody(widget.body),
          ),
        );
      }
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: appBar,
        body: CustomScrollView(
          controller: _largeTitleController.scrollController,
          physics:
              widget.iosScrollPhysics ?? const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: topContentInset)),
            GlassLargeTitle(
              text: widget.title,
              controller: _largeTitleController,
            ),
            SliverToBoxAdapter(
              child: widget.iosLargeTitleBody,
            ),
          ],
        ),
      );
    }

    final topContentInset = MediaQuery.paddingOf(context).top + 52;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: Padding(
        padding: EdgeInsets.only(top: topContentInset),
        child: _wideIOSBody(widget.body),
      ),
    );
  }

  Widget _wideIOSBody(Widget body) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth
            .clamp(0.0, adaptiveSettingsMaximumContentWidth)
            .toDouble();
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: body,
          ),
        );
      },
    );
  }
}
