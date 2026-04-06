import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:provider/provider.dart';

class FeedOnboarding extends StatefulWidget {
  const FeedOnboarding({super.key});

  @override
  State<FeedOnboarding> createState() => _FeedOnboardingState();
}

class _FeedOnboardingState extends State<FeedOnboarding> {
  final Set<String> _selectedFeedUrls = <String>{};
  bool _isSubmitting = false;

  // scraperRules can be maintained per suggested feed directly in code.
  late final List<_SuggestedCategory> _categories = <_SuggestedCategory>[
    _SuggestedCategory(
      title: 'Technologie',
      icon: Icons.memory,
      feeds: <_SuggestedFeed>[
        _SuggestedFeed(
          title: '9to5Mac',
          siteUrl: 'https://9to5mac.com',
          feedUrl: 'https://9to5mac.com/feed/',
          iconAssetPath: 'assets/9to5mac.png',
          scraperRules: null,
        ),
        _SuggestedFeed(
          title: 'The Verge',
          siteUrl: 'https://www.theverge.com',
          feedUrl: 'https://www.theverge.com/rss/index.xml',
          iconAssetPath: 'assets/verge.png',
        ),
        _SuggestedFeed(
          title: 'heise online',
          siteUrl: 'https://www.heise.de',
          feedUrl: 'https://www.heise.de/rss/heise-atom.xml',
          iconAssetPath: 'assets/heise.png',
          scraperRules: null,
        ),
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
        _SuggestedFeed(
          title: 'The Wall Street Journal',
          siteUrl: 'https://www.wsj.com',
          feedUrl: 'https://feeds.content.dowjones.io/public/rss/RSSWorldNews',
          iconAssetPath: 'assets/wsj.png',
        ),
      ],
    ),
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
    _SuggestedCategory(
      title: 'Wissenschaft',
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
          iconAssetPath: 'assets/sciencenews.png',
        ),
        _SuggestedFeed(
          title: 'Spektrum',
          siteUrl: 'https://www.spektrum.de',
          feedUrl: 'http://www.spektrum.de/alias/rss/spektrum-de-rss-feed/996406',
          iconAssetPath: 'assets/spektrum.png',
        ),
      ],
    ),
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
        ..addAll(_categories.expand((category) => category.feeds.map((feed) => feed.feedUrl)));
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
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.rss_feed),
      ),
    );
  }

  Future<void> _createFeeds() async {
    if (_isSubmitting) {
      return;
    }

    if (_selectedFeedUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.minimumFeedSelection)),
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
      final selectedFeeds = category.feeds.where((feed) => _selectedFeedUrls.contains(feed.feedUrl)).toList();
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
        Navigator.pushNamedAndRemoveUntil(context, FluxNewsState.rootRouteString, (route) => false);
      }
      return;
    } else {
      setState(() {
        _isSubmitting = false;
      });
    }

    final String failedText = failedFeeds.isEmpty ? '' : failedFeeds.join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${AppLocalizations.of(context)!.feedCreationError} $failedText')),
    );
  }

  Widget _buildSelectionList(BuildContext context, AppLocalizations localization) {
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
          children: <Widget>[
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

  Widget _buildPhoneLayout(BuildContext context, AppLocalizations localization) {
    return _buildSelectionList(context, localization);
  }

  Widget _buildTabletLayout(BuildContext context, AppLocalizations localization) {
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
                      const SizedBox(height: 20),
                      Text(
                        localization.feedSelection,
                        style: theme.textTheme.headlineMedium?.copyWith(fontSize: 36),
                      ),
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
                child: Card(
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
    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.feedSelection),
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
          label: Text(_isSubmitting ? localization.feedCreationDuration : '${localization.save} ($_selectedCount)'),
        ),
      ),
      body: isTablet ? _buildTabletLayout(context, localization) : _buildPhoneLayout(context, localization),
    );
  }

  Widget _buildCategoryCard(_SuggestedCategory category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(category.icon),
        title: Text(category.title),
        subtitle: Text(
            '${category.feeds.where((feed) => _selectedFeedUrls.contains(feed.feedUrl)).length}/${category.feeds.length}'),
        children: category.feeds
            .map(
              (feed) => CheckboxListTile(
                value: _selectedFeedUrls.contains(feed.feedUrl),
                onChanged: (selected) => _toggleFeed(feed, selected ?? false),
                title: Text(feed.title),
                subtitle: Text(feed.siteUrl),
                secondary: _buildFeedSuggestionIcon(feed.iconAssetPath),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SuggestedCategory {
  _SuggestedCategory({required this.title, required this.icon, required this.feeds});

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
