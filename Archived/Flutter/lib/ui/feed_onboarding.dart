import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

class FeedOnboarding extends StatefulWidget {
  const FeedOnboarding({super.key});

  @override
  State<FeedOnboarding> createState() => _FeedOnboardingState();
}

class _FeedOnboardingState extends State<FeedOnboarding> {
  final GlassLargeTitleController _largeTitleController =
      GlassLargeTitleController();
  final Set<String> _selectedFeedUrls = <String>{};
  bool _isSubmitting = false;

  @override
  void dispose() {
    _largeTitleController.dispose();
    super.dispose();
  }

  // scraperRules can be maintained per suggested feed directly in code.
  late final List<_SuggestedCategory> _categories = <_SuggestedCategory>[
    _SuggestedCategory(
      title: 'Technologie',
      icon: Icons.memory,
      feeds: <_SuggestedFeed>[
        /*
        _SuggestedFeed(
          title: '9to5Mac',
          siteUrl: 'https://9to5mac.com',
          feedUrl: 'https://9to5mac.com/feed/',
          iconAssetPath: 'assets/9to5mac.png',
          scraperRules: null,
        ),
        */
        _SuggestedFeed(
          title: 'The Verge',
          siteUrl: 'https://www.theverge.com',
          feedUrl: 'https://www.theverge.com/rss/index.xml',
          iconAssetPath: 'assets/verge.png',
        ),
        /*
        _SuggestedFeed(
          title: 'heise online',
          siteUrl: 'https://www.heise.de',
          feedUrl: 'https://www.heise.de/rss/heise-atom.xml',
          iconAssetPath: 'assets/heise.png',
          scraperRules: null,
        ),
        */
      ],
    ),
    _SuggestedCategory(
      title: 'News - International',
      icon: Icons.public,
      feeds: <_SuggestedFeed>[
        _SuggestedFeed(
          title: 'New York Times - World',
          siteUrl: 'https://www.nytimes.com',
          feedUrl: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
          iconAssetPath: 'assets/nyt.png',
        ),
        _SuggestedFeed(
          title: 'Aljazeera - News',
          siteUrl: 'https://www.aljazeera.com/news/',
          feedUrl: 'https://www.aljazeera.com/xml/rss/all.xml',
          iconAssetPath: 'assets/aljazeera.png',
          scraperRules: 'p.article__subhead, div.responsive-image',
        ),
        /*
        _SuggestedFeed(
          title: 'The Wall Street Journal',
          siteUrl: 'https://www.wsj.com',
          feedUrl: 'https://feeds.content.dowjones.io/public/rss/RSSWorldNews',
          iconAssetPath: 'assets/wsj.png',
        ),
        */
      ],
    ),
    /*
    _SuggestedCategory(
      title: 'News - National Germany',
      icon: Icons.public,
      feeds: <_SuggestedFeed>[
        _SuggestedFeed(
          title: 'Tagesschau',
          siteUrl: 'https://www.tagesschau.de',
          feedUrl: 'https://www.tagesschau.de/xml/rss2',
          iconAssetPath: 'assets/tagesschau.png',
        ),
        _SuggestedFeed(
          title: 'ZEIT ONLINE',
          siteUrl: 'https://www.zeit.de',
          feedUrl: 'https://newsfeed.zeit.de/',
          iconAssetPath: 'assets/zeit.png',
          scraperRules: 'div.summary, picture',
        ),
        _SuggestedFeed(
          title: 'F.A.Z.',
          siteUrl: 'https://www.faz.net',
          feedUrl: 'https://www.faz.net/rss/aktuell/',
          iconAssetPath: 'assets/faz.png',
        ),
        _SuggestedFeed(
          title: 'Süddeutsche Zeitung',
          siteUrl: 'https://www.sueddeutsche.de',
          feedUrl: 'https://rss.sueddeutsche.de/rss/Topthemen',
          iconAssetPath: 'assets/sueddeutsche.png',
        ),
      ],
    ),
    */
    _SuggestedCategory(
      title: 'Science',
      icon: Icons.science,
      feeds: <_SuggestedFeed>[
        _SuggestedFeed(
          title: 'NASA (Image of the Day)',
          siteUrl: 'https://www.nasa.gov',
          feedUrl: 'https://www.nasa.gov/rss/dyn/lg_image_of_the_day.rss',
          iconAssetPath: 'assets/nasa.png',
        ),
        _SuggestedFeed(
          title: 'Science News',
          siteUrl: 'https://www.sciencenews.org',
          feedUrl: 'https://www.sciencenews.org/feed',
          iconAssetPath: 'assets/sciencenews.jpeg',
        ),
        _SuggestedFeed(
          title: 'Spektrum',
          siteUrl: 'https://www.spektrum.de',
          feedUrl:
              'http://www.spektrum.de/alias/rss/spektrum-de-rss-feed/996406',
          iconAssetPath: 'assets/spektrum.png',
        ),
      ],
    ),
    _SuggestedCategory(
      title: 'Podcasts - International',
      icon: Icons.podcasts,
      feeds: <_SuggestedFeed>[
        _SuggestedFeed(
          title: 'New York Times - Daily',
          siteUrl: 'https://www.nytimes.com',
          feedUrl: 'https://feeds.simplecast.com/54nAGcIl',
          iconAssetPath: 'assets/nyt.png',
        ),
        _SuggestedFeed(
          title: 'Aljazeera - The Take',
          siteUrl: 'https://www.aljazeera.com/news/',
          feedUrl:
              'https://www.omnycontent.com/d/playlist/9c074afa-3313-47e8-b802-a9f900789975/09af2160-238f-48b2-b20b-ad4b00ebd8e7/b86dddc1-67a5-41c2-a13c-ad4b00ebd8f5/podcast.rss',
          iconAssetPath: 'assets/aljazeera.png',
        ),
        _SuggestedFeed(
          title: 'Monocle Radio - The Globalist',
          siteUrl: 'https://www.monocle.com/radio/shows/the-globalist/',
          feedUrl:
              'https://www.omnycontent.com/d/playlist/e6127ab7-b81e-456b-893c-a8d600215365/9c42dc1e-9f07-4f76-b8fb-ab8a0120014e/f2eddba2-287e-448b-a454-ab8a01200152/podcast.rss',
          iconAssetPath: 'assets/monocle.png',
        ),
      ],
    ),
    /*
    _SuggestedCategory(
      title: 'Podcasts - National Germany',
      icon: Icons.podcasts,
      feeds: <_SuggestedFeed>[
        _SuggestedFeed(
          title: 'Lage der Nation',
          siteUrl: 'https://www.lagedernation.org',
          feedUrl: 'https://feeds.lagedernation.org/feeds/ldn-mp3.xml',
          iconAssetPath: 'assets/ldn.png',
        ),
        _SuggestedFeed(
          title: 'F.A.Z. - Wissen',
          siteUrl: 'https://www.faz.net/podcasts/f-a-z-wissen-der-podcast/',
          feedUrl: 'https://fazwissen.podigee.io/feed/mp3',
          iconAssetPath: 'assets/faz.png',
        ),
        _SuggestedFeed(
          title: '11KM: der tagesschau-Podcast',
          siteUrl: 'https://www.tagesschau.de/multimedia/podcasts/11km/',
          feedUrl:
              'https://www.tagesschau.de/multimedia/podcasts/11km/index~podcast.xml',
          iconAssetPath: 'assets/tagesschau.png',
        ),
      ],
    ),
    */
  ];

  int get _selectedCount => _selectedFeedUrls.length;

  void _toggleFeed(_SuggestedFeed feed, bool selected) {
    setState(() {
      if (selected) {
        _selectedFeedUrls.add(feed.feedUrl);
      } else {
        _selectedFeedUrls.remove(feed.feedUrl);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedFeedUrls
        ..clear()
        ..addAll(_categories
            .expand((category) => category.feeds.map((feed) => feed.feedUrl)));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedFeedUrls.clear();
    });
  }

  Widget _buildFeedSuggestionIcon(String iconAssetPath) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        iconAssetPath,
        width: 20,
        height: 20,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.rss_feed),
      ),
    );
  }

  Future<void> _createFeeds() async {
    if (_isSubmitting) {
      return;
    }

    if (_selectedFeedUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.minimumFeedSelection)),
      );
      return;
    }

    final appState = context.read<FluxNewsState>();

    setState(() {
      _isSubmitting = true;
    });

    int createdCount = 0;
    final List<String> failedFeeds = <String>[];

    for (final category in _categories) {
      final selectedFeeds = category.feeds
          .where((feed) => _selectedFeedUrls.contains(feed.feedUrl))
          .toList();
      if (selectedFeeds.isEmpty) {
        continue;
      }

      try {
        final categoryID = await createOrGetCategory(appState, category.title);
        for (final feed in selectedFeeds) {
          try {
            await createFeedSubscription(
              appState,
              feed.feedUrl,
              categoryID,
              scraperRules: feed.scraperRules,
              suggestedTitle: feed.title,
            );
            createdCount++;
          } catch (_) {
            failedFeeds.add(feed.title);
          }
        }
      } catch (_) {
        failedFeeds.addAll(selectedFeeds.map((feed) => feed.title));
      }
    }

    if (!mounted) {
      return;
    }

    if (createdCount > 0) {
      /*
      try {
        await refreshAllFeeds(appState);
        await Future.delayed(const Duration(seconds: 10));
      } catch (_) {
        // Continue to app startup sync even if refresh-all endpoint fails.
      }
      */
      setState(() {
        _isSubmitting = false;
      });
      appState.syncNow = true;
      appState.refreshView();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, FluxNewsState.rootRouteString, (route) => false);
      }
      return;
    } else {
      setState(() {
        _isSubmitting = false;
      });
    }

    final String failedText = failedFeeds.isEmpty ? '' : failedFeeds.join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '${AppLocalizations.of(context)!.feedCreationError} $failedText')),
    );
  }

  Widget _buildSelectionList(
      BuildContext context, AppLocalizations localization) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          localization.feedCreationDescription,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: Platform.isIOS
              ? <Widget>[
                  AdaptiveSettingsButton(
                    onPressed: _selectAll,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.check_mark_circled, size: 18),
                        const SizedBox(width: 7),
                        Text(localization.feedSelectionSelectAll),
                      ],
                    ),
                  ),
                  AdaptiveSettingsButton(
                    onPressed: _clearSelection,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.clear_circled, size: 18),
                        const SizedBox(width: 7),
                        Text(localization.feedSelectionDeleteSelection),
                      ],
                    ),
                  ),
                ]
              : <Widget>[
                  OutlinedButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(Icons.done_all),
                    label: Text(localization.feedSelectionSelectAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.deselect),
                    label: Text(localization.feedSelectionDeleteSelection),
                  ),
                ],
        ),
        const SizedBox(height: 12),
        ..._categories.map(_buildCategoryCard),
      ],
    );
  }

  Widget _buildPhoneLayout(
      BuildContext context, AppLocalizations localization) {
    return _buildSelectionList(context, localization);
  }

  Widget _buildTabletLayout(
      BuildContext context, AppLocalizations localization) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.rss_feed,
                        size: 88,
                        color: theme.colorScheme.primary,
                      ),
                      if (!Platform.isIOS) ...[
                        const SizedBox(height: 20),
                        Text(
                          localization.feedSelection,
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontSize: 36),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        localization.feedCreationDescription,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Platform.isIOS
                    ? _buildSelectionList(context, localization)
                    : Card(
                        child: _buildSelectionList(context, localization),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context)!;
    FluxNewsState appState = context.watch<FluxNewsState>();

    if (Platform.isIOS) {
      final glassSettings = iosLiquidGlassSettings(
        context,
        useClearEffect: appState.iosClearLiquidGlass,
      );
      final glassQuality = iosLiquidGlassQuality(
        useClearEffect: appState.iosClearLiquidGlass,
      );
      final foreground = iosLiquidGlassForeground(context);
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          centerTitle: false,
          largeTitleController: _largeTitleController,
          buttonSettings: glassSettings,
          leading: Navigator.canPop(context)
              ? GlassIconButton(
                  useOwnLayer: true,
                  quality: glassQuality,
                  settings: glassSettings,
                  semanticLabel:
                      MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(CupertinoIcons.back, color: foreground),
                )
              : null,
          title: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: GlassContainer(
                useOwnLayer: true,
                quality: glassQuality,
                settings: glassSettings,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  localization.feedSelection,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AdaptiveSettingsButton(
            onPressed: _isSubmitting ? null : _createFeeds,
            child: _isSubmitting
                ? const CupertinoActivityIndicator()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(CupertinoIcons.cloud_upload, size: 19),
                      const SizedBox(width: 8),
                      Text('${localization.save} ($_selectedCount)'),
                    ],
                  ),
          ),
        ),
        body: NestedScrollView(
          controller: _largeTitleController.scrollController,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).top + 44,
              ),
            ),
            GlassLargeTitle(
              text: localization.feedSelection,
              controller: _largeTitleController,
            ),
          ],
          body: appState.isTablet
              ? _buildTabletLayout(context, localization)
              : _buildPhoneLayout(context, localization),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.feedSelection,
            style: Theme.of(context).textTheme.titleLarge),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _isSubmitting ? null : _createFeeds,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(_isSubmitting
              ? localization.feedCreationDuration
              : '${localization.save} ($_selectedCount)'),
        ),
      ),
      body: appState.isTablet
          ? _buildTabletLayout(context, localization)
          : _buildPhoneLayout(context, localization),
    );
  }

  Widget _buildCategoryCard(_SuggestedCategory category) {
    final isIOS = Platform.isIOS;
    final theme = Theme.of(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isIOS ? 0 : null,
      shadowColor: isIOS ? Colors.transparent : null,
      surfaceTintColor: isIOS ? Colors.transparent : null,
      color: isIOS
          ? CupertinoColors.secondarySystemGroupedBackground
              .resolveFrom(context)
          : null,
      clipBehavior: isIOS ? Clip.antiAlias : Clip.none,
      shape: isIOS
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))
          : null,
      child: Theme(
        data: isIOS
            ? theme.copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              )
            : theme,
        child: ExpansionTile(
          iconColor: isIOS ? secondaryLabel : null,
          collapsedIconColor: isIOS ? secondaryLabel : null,
          leading: Icon(
            category.icon,
            color: isIOS ? secondaryLabel : null,
          ),
          title: Text(category.title),
          subtitle: Text(
              '${category.feeds.where((feed) => _selectedFeedUrls.contains(feed.feedUrl)).length}/${category.feeds.length}'),
          children: category.feeds
              .map(
                (feed) => isIOS
                    ? _buildIOSFeedSelectionRow(feed)
                    : CheckboxListTile(
                        value: _selectedFeedUrls.contains(feed.feedUrl),
                        onChanged: (selected) =>
                            _toggleFeed(feed, selected ?? false),
                        title: Text(feed.title),
                        subtitle: Text(feed.siteUrl),
                        secondary: _buildFeedSuggestionIcon(feed.iconAssetPath),
                      ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildIOSFeedSelectionRow(_SuggestedFeed feed) {
    final selected = _selectedFeedUrls.contains(feed.feedUrl);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Semantics(
      checked: selected,
      child: CupertinoListTile(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 14, 8),
        leadingSize: 28,
        leadingToTitle: 12,
        leading: _buildFeedSuggestionIcon(feed.iconAssetPath),
        title: Text(feed.title),
        subtitle: Text(
          feed.siteUrl,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Icon(
            selected
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            key: ValueKey(selected),
            size: 24,
            color: selected
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : secondaryLabel,
          ),
        ),
        onTap: () => _toggleFeed(feed, !selected),
      ),
    );
  }
}

class _SuggestedCategory {
  _SuggestedCategory(
      {required this.title, required this.icon, required this.feeds});

  final String title;
  final IconData icon;
  final List<_SuggestedFeed> feeds;
}

class _SuggestedFeed {
  _SuggestedFeed({
    required this.title,
    required this.siteUrl,
    required this.feedUrl,
    required this.iconAssetPath,
    this.scraperRules,
  });

  final String title;
  final String siteUrl;
  final String feedUrl;
  final String iconAssetPath;
  final String? scraperRules;
}
