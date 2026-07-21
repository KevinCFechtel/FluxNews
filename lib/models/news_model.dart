import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flux_news/functions/android_url_launcher.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';
import 'package:html2md/html2md.dart' as html2md;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state_management/flux_news_state.dart';

// define the model
class News {
  News(
      {required this.newsID,
      required this.feedID,
      required this.title,
      required this.url,
      required this.commentsUrl,
      required this.shareCode,
      required this.content,
      this.previewText = '',
      this.imageUrl = '',
      this.contentLoaded = true,
      required this.hash,
      required this.publishedAt,
      required this.createdAt,
      required this.status,
      required this.readingTime,
      required this.starred,
      required this.feedTitle,
      this.feedIconID,
      this.attachments,
      this.attachmentURL,
      this.attachmentMimeType,
      this.crawler,
      this.manualTruncate,
      this.preferParagraph,
      this.preferAttachmentImage,
      this.manualAdaptLightModeToIcon,
      this.manualAdaptDarkModeToIcon,
      this.openMinifluxEntry,
      this.expandedWithFulltext});
  // define the properties
  int newsID = 0;
  int feedID = 0;
  String title = '';
  String url = '';
  String commentsUrl = '';
  String shareCode = '';
  String content = '';
  String previewText = '';
  String imageUrl = '';
  bool contentLoaded = true;
  String hash = '';
  String publishedAt = '';
  String createdAt = '';
  String status = '';
  int readingTime = 0;
  bool starred = false;
  String feedTitle = '';
  String? syncStatus = FluxNewsState.notSyncedSyncStatus;
  Uint8List? icon;
  String? iconMimeType = '';
  int? feedIconID;
  List<Attachment>? attachments;
  String? attachmentURL = '';
  String? attachmentMimeType = '';
  bool? crawler = false;
  bool? manualTruncate = false;
  bool? preferParagraph = false;
  bool? preferAttachmentImage = false;
  bool? manualAdaptLightModeToIcon = false;
  bool? manualAdaptDarkModeToIcon = false;
  bool? openMinifluxEntry = false;
  bool? expandedWithFulltext = false;
  int? expandedFulltextLimit = 0;
  bool expanded = false;

  int? _previewTextCacheKey;
  String? _previewTextCache;
  int? _imageUrlCacheKey;
  String? _imageUrlCache;

  // define the method to convert the json to the model
  factory News.fromJson(Map<String, dynamic> json) {
    News news = News(
      newsID: json['id'],
      feedID: json['feed_id'],
      title: json['title'],
      url: json['url'],
      commentsUrl: json['comments_url'],
      shareCode: json['share_code'],
      content: json['content'],
      hash: json['hash'],
      publishedAt: json['published_at'],
      createdAt: json['created_at'],
      status: json['status'],
      readingTime: json['reading_time'],
      starred: json['starred'],
      feedTitle: json['feed']?['title'],
      feedIconID: json['feed']?['icon']?['icon_id'],
    );

    if (json['enclosures'] != null) {
      news.attachments = List<Attachment>.from(
          json['enclosures'].map((i) => Attachment.fromJson(i)));
    }

    return news;
  }

  // define the method to convert the model to the database
  Map<String, dynamic> toMap() {
    return {
      'newsID': newsID,
      'feedID': feedID,
      'title': title,
      'url': url,
      'commentsUrl': commentsUrl,
      'shareCode': shareCode,
      'content': content,
      'previewText': previewText,
      'imageUrl': imageUrl,
      'hash': hash,
      'publishedAt': publishedAt,
      'createdAt': createdAt,
      'status': status,
      'readingTime': readingTime,
      'starred': starred ? 1 : 0,
      'feedTitle': feedTitle,
      'syncStatus': syncStatus,
    };
  }

  // define the method to convert the model from the database
  News.fromMap(Map<String, dynamic> res)
      : newsID = res['newsID'],
        feedID = res['feedID'],
        title = res['title'],
        url = res['url'],
        commentsUrl = res['commentsUrl'],
        shareCode = res['shareCode'],
        content = res['content'] as String? ?? '',
        previewText = res['previewText'] as String? ?? '',
        imageUrl = res['imageUrl'] as String? ?? '',
        contentLoaded = (res['contentLoaded'] as int? ?? 1) == 1,
        hash = res['hash'],
        publishedAt = res['publishedAt'],
        createdAt = res['createdAt'],
        status = res['status'],
        readingTime = res['readingTime'],
        starred = res['starred'] == 1 ? true : false,
        feedTitle = res['feedTitle'],
        syncStatus = res['syncStatus'],
        iconMimeType = res['iconMimeType'],
        feedIconID = res['iconID'],
        attachmentURL = res['attachmentURL'],
        attachmentMimeType = res['attachmentMimeType'],
        crawler = res['crawler'] == 1 ? true : false,
        manualTruncate = res['manualTruncate'] == 1 ? true : false,
        preferParagraph = res['preferParagraph'] == 1 ? true : false,
        preferAttachmentImage =
            res['preferAttachmentImage'] == 1 ? true : false,
        manualAdaptLightModeToIcon =
            res['manualAdaptLightModeToIcon'] == 1 ? true : false,
        manualAdaptDarkModeToIcon =
            res['manualAdaptDarkModeToIcon'] == 1 ? true : false,
        openMinifluxEntry = res['openMinifluxEntry'] == 1 ? true : false,
        expandedWithFulltext = res['expandedWithFulltext'] == 1 ? true : false,
        expandedFulltextLimit = res['expandedFulltextLimit'];

  // define the method to extract the text from the html content
  // the text is first searched in the raw text
  // the text is split at the first line break
  // if this result is less than 50 chars, the text is searched in the p tags
  // if no text is found the empty string is returned
  // if there is no raw text the text is searched in the p tags
  String getText(FluxNewsState appState) {
    final previewTextCacheKey = Object.hash(
      content,
      preferParagraph,
      appState.activateTruncate,
      appState.truncateMode,
      appState.charactersToTruncateLimit,
      appState.charactersToTruncate,
      crawler,
      manualTruncate,
    );
    if (_previewTextCacheKey == previewTextCacheKey &&
        _previewTextCache != null) {
      return _previewTextCache!;
    }

    String text = previewText.isNotEmpty
        ? previewText
        : createPreviewText(content, preferParagraph: preferParagraph == true);
    if (appState.activateTruncate) {
      switch (appState.truncateMode) {
        case 0:
          if (appState.charactersToTruncateLimit == 0 ||
              appState.charactersToTruncateLimit < text.length) {
            text = truncateText(text, appState.charactersToTruncate);
          }
          break;
        case 1:
          if (crawler != null) {
            if (crawler == true) {
              if (appState.charactersToTruncateLimit == 0 ||
                  appState.charactersToTruncateLimit < text.length) {
                text = truncateText(text, appState.charactersToTruncate);
              }
            }
          }
          break;
        case 2:
          if (manualTruncate != null) {
            if (manualTruncate == true) {
              if (appState.charactersToTruncateLimit == 0 ||
                  appState.charactersToTruncateLimit < text.length) {
                text = truncateText(text, appState.charactersToTruncate);
              }
            }
          }
          break;
      }
    }

    _previewTextCacheKey = previewTextCacheKey;
    _previewTextCache = text;
    return text;
  }

  static String createPreviewText(String html,
      {required bool preferParagraph}) {
    final document = parse(html);
    return _createPreviewTextFromDocument(
      document,
      preferParagraph: preferParagraph,
    );
  }

  static String _createPreviewTextFromDocument(
    dom.Document document, {
    required bool preferParagraph,
  }) {
    for (final element
        in document.querySelectorAll('script, style, noscript, svg')) {
      element.remove();
    }

    String normalize(String value) =>
        value.replaceAll(RegExp(r'\s+'), ' ').trim();

    String text = '';
    if (preferParagraph) {
      for (final paragraph in document.querySelectorAll('p')) {
        final candidate = normalize(paragraph.text);
        if (candidate.length >= 20) {
          text = candidate;
          break;
        }
      }
    }
    if (text.isEmpty) {
      text = normalize(document.body?.text ?? '');
    }
    return text.length > 2000 ? text.substring(0, 2000) : text;
  }

  void prepareListMetadata() {
    final document = parse(content);
    imageUrl = _resolveImageUrl(document: document);
    previewText = _createPreviewTextFromDocument(
      document,
      preferParagraph: preferParagraph == true,
    );
    _previewTextCacheKey = null;
    _previewTextCache = null;
    _imageUrlCacheKey = null;
    _imageUrlCache = null;
  }

  static String extractImageUrlFromHtml(String html) {
    final document = parse(html);
    return _extractImageUrlFromDocument(document);
  }

  static String _extractImageUrlFromDocument(dom.Document document) {
    String? normalize(String? rawUrl) {
      if (rawUrl == null) return null;
      final trimmed = rawUrl.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('//')) return 'https:$trimmed';
      final uri = Uri.tryParse(trimmed);
      if (uri == null || !uri.hasScheme) return null;
      final scheme = uri.scheme.toLowerCase();
      return scheme == 'http' || scheme == 'https' ? trimmed : null;
    }

    for (final image in document.getElementsByTagName('img')) {
      final directSrc = normalize(image.attributes['src']);
      if (directSrc != null) return directSrc;
      final lazySrc = normalize(image.attributes['data-src']);
      if (lazySrc != null) return lazySrc;
      final srcSet = image.attributes['srcset'];
      if (srcSet == null) continue;
      for (final candidate in srcSet.split(',')) {
        final urlPart = candidate.trim().split(RegExp(r'\s+')).first;
        final normalized = normalize(urlPart);
        if (normalized != null) return normalized;
      }
    }
    return FluxNewsState.noImageUrlString;
  }

  // define the method to extract the text from the html content
  // the text is first searched in the raw text
  // if no text is found the empty string is returned
  // if there is no raw text the text is searched in the p tags
  String getFullText(FluxNewsState appState) {
    final document = parse(content);
    String? text = parse(document.body?.text).documentElement?.text;
    text ??= '';
    if (expandedFulltextLimit != null && expandedFulltextLimit! > 0) {
      text = truncateText(text, expandedFulltextLimit!);
    }

    return text;
  }

  // define the method to extract the text from the html content
  // the text is first searched in the raw text
  // if no text is found the empty string is returned
  // if there is no raw text the text is searched in the p tags
  Widget getFullTextWidget(FluxNewsState appState) {
    var markdown = html2md.convert(content, ignore: ['img']);
    if (expandedFulltextLimit != null && expandedFulltextLimit! > 0) {
      markdown = truncateText(markdown, expandedFulltextLimit!);
    }
    return MarkdownBlock(
      data: markdown,
      selectable: false,
      config: MarkdownConfig(configs: [
        LinkConfig(
          style: TextStyle(), // empty style to use default
          onTap: (url) {
            //Do not open Links
          },
        ),
      ]),
    );
  }

  // define the method to extract the text from the html content
  // the text is first searched in the raw text
  // if no text is found the empty string is returned
  // if there is no raw text the text is searched in the p tags
  Widget getFullRenderedWidget(FluxNewsState appState, BuildContext context) {
    var markdown = html2md.convert(content);
    if (expandedFulltextLimit != null && expandedFulltextLimit! > 0) {
      markdown = truncateText(markdown, expandedFulltextLimit!);
    }
    return MarkdownBlock(
      data: markdown,
      selectable: false,
      config: MarkdownConfig(configs: [
        LinkConfig(
          onTap: (url) async {
            if (Platform.isAndroid) {
              AndroidUrlLauncher.launchUrl(context, url);
            } else if (Platform.isIOS) {
              // catch exception if no app is installed to handle the url
              final bool nativeAppLaunchSucceeded = await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalNonBrowserApplication,
              );
              //if exception is caught, open the app in web-view
              if (!nativeAppLaunchSucceeded) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.inAppWebView,
                );
              }
            }
          },
        ),
      ]),
    );
  }

  Attachment getFirstImageAttachment() {
    Attachment imageAttachment = Attachment(
        attachmentID: -1,
        newsID: -1,
        attachmentURL: "",
        attachmentMimeType: "");

    if (attachments != null) {
      for (final attachment in attachments!) {
        if (attachment.attachmentMimeType
            .trim()
            .toLowerCase()
            .startsWith('image/')) {
          imageAttachment = attachment;
          break;
        }
      }
    }

    if (imageAttachment.attachmentID == -1 &&
        attachmentURL != null &&
        attachmentURL!.isNotEmpty &&
        attachmentMimeType != null &&
        attachmentMimeType!.trim().toLowerCase().startsWith('image/')) {
      imageAttachment = Attachment(
        attachmentID: -1,
        newsID: newsID,
        attachmentURL: attachmentURL!,
        attachmentMimeType: attachmentMimeType!,
      );
    }

    return imageAttachment;
  }

  List<Attachment> getAudioAttachments() {
    final List<Attachment> audioAttachments = [];

    if (attachments != null) {
      for (final attachment in attachments!) {
        if (attachment.attachmentMimeType.toLowerCase().startsWith('audio/')) {
          audioAttachments.add(attachment);
        }
      }
    }

    if (audioAttachments.isEmpty &&
        attachmentURL != null &&
        attachmentURL!.isNotEmpty &&
        attachmentMimeType != null &&
        attachmentMimeType!.toLowerCase().startsWith('audio/')) {
      audioAttachments.add(
        Attachment(
          attachmentID: -1,
          newsID: newsID,
          attachmentURL: attachmentURL!,
          attachmentMimeType: attachmentMimeType!,
        ),
      );
    }

    return audioAttachments;
  }

  String getFormattedPlaybackTime() {
    if (readingTime == 0) return '';
    if (readingTime < 60) {
      return '${readingTime}min';
    }
    final int hours = readingTime ~/ 60;
    final int minutes = readingTime % 60;
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}min';
  }

  // define the method to extract the image url from the html content
  // the image url is searched in the img tags
  // the image url is searched in the src attribute
  // the image url must start with http
  // if no image url is found the noImageUrlString is returned
  String getImageURL() {
    if (imageUrl.isNotEmpty) return imageUrl;
    final attachmentSignature = Object.hashAll(
      attachments?.map((attachment) => Object.hash(
                attachment.attachmentURL,
                attachment.attachmentMimeType,
              )) ??
          const <Object>[],
    );
    final imageUrlCacheKey = Object.hash(
      content,
      preferAttachmentImage,
      attachmentURL,
      attachmentMimeType,
      attachmentSignature,
    );
    if (_imageUrlCacheKey == imageUrlCacheKey && _imageUrlCache != null) {
      return _imageUrlCache!;
    }

    final resolvedImageUrl = _resolveImageUrl();
    _imageUrlCacheKey = imageUrlCacheKey;
    _imageUrlCache = resolvedImageUrl;
    return resolvedImageUrl;
  }

  String _resolveImageUrl({dom.Document? document}) {
    String resolvedImageUrl = FluxNewsState.noImageUrlString;
    final parsedDocument = document ?? parse(content);

    String? normalizeImageUrl(String? rawUrl) {
      if (rawUrl == null) return null;
      final trimmed = rawUrl.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('//')) {
        return 'https:$trimmed';
      }
      final uri = Uri.tryParse(trimmed);
      if (uri == null || !uri.hasScheme) return null;
      final scheme = uri.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        return trimmed;
      }
      return null;
    }

    String? firstImageFromAttachments() {
      if (attachments != null) {
        for (final attachment in attachments!) {
          if (attachment.attachmentMimeType
              .trim()
              .toLowerCase()
              .startsWith('image/')) {
            final normalized = normalizeImageUrl(attachment.attachmentURL);
            if (normalized != null) {
              return normalized;
            }
          }
        }
      }

      if (attachmentURL != null &&
          attachmentURL!.isNotEmpty &&
          attachmentMimeType != null &&
          attachmentMimeType!.trim().toLowerCase().startsWith('image/')) {
        return normalizeImageUrl(attachmentURL);
      }

      return null;
    }

    String? firstImageFromHtml() {
      final images = parsedDocument.getElementsByTagName('img');
      for (final image in images) {
        final directSrc = normalizeImageUrl(image.attributes['src']);
        if (directSrc != null) {
          return directSrc;
        }

        final lazySrc = normalizeImageUrl(image.attributes['data-src']);
        if (lazySrc != null) {
          return lazySrc;
        }

        final srcSet = image.attributes['srcset'];
        if (srcSet != null) {
          for (final candidate in srcSet.split(',')) {
            final urlPart = candidate.trim().split(RegExp(r'\s+')).first;
            final normalized = normalizeImageUrl(urlPart);
            if (normalized != null) {
              return normalized;
            }
          }
        }
      }
      return null;
    }

    if (preferAttachmentImage != null && preferAttachmentImage!) {
      resolvedImageUrl = firstImageFromAttachments() ??
          firstImageFromHtml() ??
          FluxNewsState.noImageUrlString;
    } else {
      resolvedImageUrl = firstImageFromHtml() ??
          firstImageFromAttachments() ??
          FluxNewsState.noImageUrlString;
    }
    return resolvedImageUrl;
  }

  // define the method to get the publishing date in local date format
  DateTime getPublishingDate() {
    DateTime publishingDate = DateTime.parse(publishedAt).toLocal();
    return publishingDate;
  }

  // define the method to get the feed icon as a widget
  // the icon could be a svg or a png image
  // if the icon is a svg image it is processed by the flutter_svg package
  // the icon is colored in white if the dark mode is enabled
  // the icon is colored in black if the dark mode is disabled
  // if the icon is a png image it is processed by the Image.memory widget
  Widget getFeedIcon(double size, BuildContext context) {
    bool darkModeEnabled = false;
    if (context.read<FluxNewsThemeState>().brightnessMode ==
        FluxNewsState.brightnessModeDarkString) {
      darkModeEnabled = true;
    } else if (context.read<FluxNewsThemeState>().brightnessMode ==
        FluxNewsState.brightnessModeSystemString) {
      darkModeEnabled =
          MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    manualAdaptLightModeToIcon ??= false;
    manualAdaptDarkModeToIcon ??= false;
    if (icon != null) {
      if (iconMimeType == 'image/svg+xml') {
        if (manualAdaptLightModeToIcon! || manualAdaptDarkModeToIcon!) {
          if (manualAdaptDarkModeToIcon!) {
            if (darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: SvgPicture.string(
                    String.fromCharCodes(icon!),
                    width: size,
                    height: size,
                  ));
            } else {
              if (manualAdaptLightModeToIcon!) {
                return Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    child: SvgPicture.string(
                      String.fromCharCodes(icon!),
                      width: size,
                      height: size,
                    ));
              } else {
                return SvgPicture.string(
                  String.fromCharCodes(icon!),
                  width: size,
                  height: size,
                );
              }
            }
          } else {
            if (!darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: SvgPicture.string(
                    String.fromCharCodes(icon!),
                    width: size,
                    height: size,
                  ));
            } else {
              return SvgPicture.string(
                String.fromCharCodes(icon!),
                width: size,
                height: size,
              );
            }
          }
        } else {
          return SvgPicture.string(
            String.fromCharCodes(icon!),
            width: size,
            height: size,
          );
        }
      } else {
        if (manualAdaptLightModeToIcon! || manualAdaptDarkModeToIcon!) {
          if (manualAdaptDarkModeToIcon!) {
            if (darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: Image.memory(
                    icon!,
                    width: size,
                    height: size,
                    errorBuilder: (context, error, stackTrace) =>
                        SizedBox.fromSize(size: Size(size, size)),
                  ));
            } else {
              return Image.memory(
                icon!,
                width: size,
                height: size,
                errorBuilder: (context, error, stackTrace) =>
                    SizedBox.fromSize(size: Size(size, size)),
              );
            }
          } else {
            if (!darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: Image.memory(
                    icon!,
                    width: size,
                    height: size,
                    errorBuilder: (context, error, stackTrace) =>
                        SizedBox.fromSize(size: Size(size, size)),
                  ));
            } else {
              if (manualAdaptLightModeToIcon!) {
                return Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    child: Image.memory(
                      icon!,
                      width: size,
                      height: size,
                      errorBuilder: (context, error, stackTrace) =>
                          SizedBox.fromSize(size: Size(size, size)),
                    ));
              } else {
                return Image.memory(
                  icon!,
                  width: size,
                  height: size,
                  errorBuilder: (context, error, stackTrace) =>
                      SizedBox.fromSize(size: Size(size, size)),
                );
              }
            }
          }
        } else {
          return Image.memory(
            icon!,
            width: size,
            height: size,
            errorBuilder: (context, error, stackTrace) =>
                SizedBox.fromSize(size: Size(size, size)),
          );
        }
      }
    } else {
      return SizedBox.fromSize(size: Size(size, size));
    }
  }

  void saveFeedIcon(List<Feed> feeds) {
    for (Feed feed in feeds) {
      if (feed.feedID == feedID) {
        icon = feed.icon;
      }
    }
  }

  void getFeedInfo(List<Feed> feeds) {
    for (Feed feed in feeds) {
      if (feed.feedID == feedID) {
        icon = feed.icon;
        iconMimeType = feed.iconMimeType;
        crawler = feed.crawler;
        manualTruncate = feed.manualTruncate;
        preferParagraph = feed.preferParagraph;
        preferAttachmentImage = feed.preferAttachmentImage;
        manualAdaptLightModeToIcon = feed.manualAdaptLightModeToIcon;
        manualAdaptDarkModeToIcon = feed.manualAdaptDarkModeToIcon;
        openMinifluxEntry = feed.openMinifluxEntry;
        expandedWithFulltext = feed.expandedWithFulltext;
        expandedFulltextLimit = feed.expandedFulltextLimit;
      }
    }
  }
}

// define the model for the news list
class NewsList {
  NewsList({
    required this.news,
    required this.newsCount,
  });
  // define the properties
  List<News> news = [];
  int newsCount = 0;

  // define the method to convert the model from json
  factory NewsList.fromJson(Map<String, dynamic> json) {
    final List list = json['entries'] as List;
    final int newsCount = json['total'];
    final List<News> tempNewsList = list.map((i) => News.fromJson(i)).toList();
    return NewsList(news: tempNewsList, newsCount: newsCount);
  }
}

// define the model for a feed
class Feed {
  Feed(
      {required this.feedID,
      required this.title,
      required this.siteUrl,
      this.feedIconID,
      this.crawler,
      this.manualTruncate,
      this.preferParagraph,
      this.preferAttachmentImage,
      this.manualAdaptLightModeToIcon,
      this.manualAdaptDarkModeToIcon,
      this.openMinifluxEntry,
      this.expandedWithFulltext});

  // define the properties
  int feedID = 0;
  String title = '';
  String siteUrl = '';
  int? feedIconID;
  int newsCount = 0;
  Uint8List? icon;
  String iconMimeType = '';
  bool? crawler = false;
  bool? manualTruncate = false;
  bool? preferParagraph = false;
  bool? preferAttachmentImage = false;
  bool? manualAdaptLightModeToIcon = false;
  bool? manualAdaptDarkModeToIcon = false;
  bool? openMinifluxEntry = false;
  bool? expandedWithFulltext = false;
  int? expandedFulltextLimit = 0;
  int? categoryID;

  List<KeyValueRecordType> getAmountOfCharactersToTruncateExpandRecordTypes(
      BuildContext context) {
    if (AppLocalizations.of(context) != null) {
      List<KeyValueRecordType> recordTypesAmountOfCharactersToTruncateExpand =
          <KeyValueRecordType>[
        KeyValueRecordType(key: "0", value: AppLocalizations.of(context)!.all),
        const KeyValueRecordType(key: "500", value: "500"),
        const KeyValueRecordType(key: "600", value: "600"),
        const KeyValueRecordType(key: "700", value: "700"),
        const KeyValueRecordType(key: "800", value: "800"),
        const KeyValueRecordType(key: "900", value: "900"),
        const KeyValueRecordType(key: "1000", value: "1000"),
        const KeyValueRecordType(key: "1500", value: "1500"),
        const KeyValueRecordType(key: "2000", value: "2000"),
      ];

      return recordTypesAmountOfCharactersToTruncateExpand;
    } else {
      return <KeyValueRecordType>[];
    }
  }

  KeyValueRecordType getAmountOfCharactersToTruncateExpandSelection(
      BuildContext context) {
    List<KeyValueRecordType> recordTypesAmountOfCharactersToTruncateExpand =
        getAmountOfCharactersToTruncateExpandRecordTypes(context);
    KeyValueRecordType amountOfCharactersToTruncateExpandSelection =
        recordTypesAmountOfCharactersToTruncateExpand[0];
    // init the amount of characters to truncate expand selection with the first value of the above generated maps
    if (recordTypesAmountOfCharactersToTruncateExpand.isNotEmpty) {
      if (expandedFulltextLimit != null) {
        for (KeyValueRecordType recordSet
            in recordTypesAmountOfCharactersToTruncateExpand) {
          if (expandedFulltextLimit == int.parse(recordSet.key)) {
            amountOfCharactersToTruncateExpandSelection = recordSet;
          }
        }
      }
    }
    return amountOfCharactersToTruncateExpandSelection;
  }

  // define the method to convert the model from json
  factory Feed.fromJson(Map<String, dynamic> json) {
    return Feed(
      feedID: json['id'],
      title: json['title'],
      siteUrl: json['site_url'],
      feedIconID: json['icon']?['icon_id'],
      crawler: json['crawler'],
    );
  }

  // define the method to convert the model to database
  Map<String, dynamic> toMap() {
    return {
      'feedID': feedID,
      'title': title,
      'site_url': siteUrl,
      'iconMimeType': iconMimeType,
      'iconID': feedIconID,
      'newsCount': newsCount,
      'crawler': crawler,
      'manualTruncate': manualTruncate,
      'preferParagraph': preferParagraph,
      'preferAttachmentImage': preferAttachmentImage,
      'manualAdaptLightModeToIcon': manualAdaptLightModeToIcon,
      'manualAdaptDarkModeToIcon': manualAdaptDarkModeToIcon,
      'openMinifluxEntry': openMinifluxEntry,
      'expandedWithFulltext': expandedWithFulltext,
      'expandedFulltextLimit': expandedFulltextLimit
    };
  }

  // define the method to convert the model from database
  Feed.fromMap(Map<String, dynamic> res)
      : feedID = res['feedID'],
        title = res['title'],
        siteUrl = res['site_url'],
        iconMimeType = res['iconMimeType'],
        feedIconID = res['iconID'],
        newsCount = res['newsCount'],
        crawler = res['crawler'] == 1 ? true : false,
        manualTruncate = res['manualTruncate'] == 1 ? true : false,
        preferParagraph = res['preferParagraph'] == 1 ? true : false,
        preferAttachmentImage =
            res['preferAttachmentImage'] == 1 ? true : false,
        manualAdaptLightModeToIcon =
            res['manualAdaptLightModeToIcon'] == 1 ? true : false,
        manualAdaptDarkModeToIcon =
            res['manualAdaptDarkModeToIcon'] == 1 ? true : false,
        openMinifluxEntry = res['openMinifluxEntry'] == 1 ? true : false,
        expandedWithFulltext = res['expandedWithFulltext'] == 1 ? true : false,
        expandedFulltextLimit = res['expandedFulltextLimit'],
        categoryID = res['categoryID'];

  // define the method to get the feed icon as a widget
  // the icon could be a svg or a png image
  // if the icon is a svg image it is processed by the flutter_svg package
  // the icon is colored in white if the dark mode is enabled
  // the icon is colored in black if the dark mode is disabled
  // if the icon is a png image it is processed by the Image.memory widget
  Widget getFeedIcon(double size, BuildContext context) {
    bool darkModeEnabled = false;
    if (context.read<FluxNewsThemeState>().brightnessMode ==
        FluxNewsState.brightnessModeDarkString) {
      darkModeEnabled = true;
    } else if (context.read<FluxNewsThemeState>().brightnessMode ==
        FluxNewsState.brightnessModeSystemString) {
      darkModeEnabled =
          MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    manualAdaptLightModeToIcon ??= false;
    manualAdaptDarkModeToIcon ??= false;
    if (icon != null) {
      if (iconMimeType == 'image/svg+xml') {
        if (manualAdaptLightModeToIcon! || manualAdaptDarkModeToIcon!) {
          if (manualAdaptDarkModeToIcon!) {
            if (darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: SvgPicture.string(
                    String.fromCharCodes(icon!),
                    width: size,
                    height: size,
                  ));
            } else {
              if (manualAdaptLightModeToIcon!) {
                return Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    child: SvgPicture.string(
                      String.fromCharCodes(icon!),
                      width: size,
                      height: size,
                    ));
              } else {
                return SvgPicture.string(
                  String.fromCharCodes(icon!),
                  width: size,
                  height: size,
                );
              }
            }
          } else {
            if (!darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: SvgPicture.string(
                    String.fromCharCodes(icon!),
                    width: size,
                    height: size,
                  ));
            } else {
              return SvgPicture.string(
                String.fromCharCodes(icon!),
                width: size,
                height: size,
              );
            }
          }
        } else {
          return SvgPicture.string(
            String.fromCharCodes(icon!),
            width: size,
            height: size,
          );
        }
      } else {
        if (manualAdaptLightModeToIcon! || manualAdaptDarkModeToIcon!) {
          if (manualAdaptDarkModeToIcon!) {
            if (darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: Image.memory(
                    icon!,
                    width: size,
                    height: size,
                    errorBuilder: (context, error, stackTrace) =>
                        SizedBox.fromSize(size: Size(size, size)),
                  ));
            } else {
              if (manualAdaptLightModeToIcon!) {
                return Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    child: Image.memory(
                      icon!,
                      width: size,
                      height: size,
                      errorBuilder: (context, error, stackTrace) =>
                          SizedBox.fromSize(size: Size(size, size)),
                    ));
              } else {
                return Image.memory(
                  icon!,
                  width: size,
                  height: size,
                  errorBuilder: (context, error, stackTrace) =>
                      SizedBox.fromSize(size: Size(size, size)),
                );
              }
            }
          } else {
            if (!darkModeEnabled) {
              return Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  child: Image.memory(
                    icon!,
                    width: size,
                    height: size,
                    errorBuilder: (context, error, stackTrace) =>
                        SizedBox.fromSize(size: Size(size, size)),
                  ));
            } else {
              return Image.memory(
                icon!,
                width: size,
                height: size,
                errorBuilder: (context, error, stackTrace) =>
                    SizedBox.fromSize(size: Size(size, size)),
              );
            }
          }
        } else {
          return Image.memory(
            icon!,
            width: size,
            height: size,
            errorBuilder: (context, error, stackTrace) =>
                SizedBox.fromSize(size: Size(size, size)),
          );
        }
      }
    } else {
      return SizedBox.fromSize(size: Size(size, size));
    }
  }
}

// define the model for a feed icon
class FeedIcon {
  FeedIcon({required this.iconBase64, required this.iconMimeType});

  // define the properties
  String iconBase64 = '';
  String iconMimeType = '';

  // define the method to convert the model from json
  factory FeedIcon.fromJson(Map<String, dynamic> json) {
    return FeedIcon(
      iconBase64: json['data'],
      iconMimeType: json['mime_type'],
    );
  }

  // define the method to get the icon as a Uint8List
  Uint8List getIcon() {
    return base64Decode(iconBase64.split(',').last);
  }
}

// define the model for a category
class Category {
  Category({required this.categoryID, required this.title, List<Feed>? feeds})
      : feeds = feeds ?? [];

  // define the properties
  int categoryID = 0;
  String title = '';
  List<Feed> feeds = [];
  int newsCount = 0;

  // define the method to convert the model from json
  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      categoryID: json['id'],
      title: json['title'],
    );
  }

  // define the method to convert the model to database
  Map<String, dynamic> toMap() {
    return {
      'categoryID': categoryID,
      'title': title,
    };
  }

  // define the method to convert the model from database
  Category.fromMap(Map<String, dynamic> res)
      : categoryID = res['categoryID'],
        title = res['title'];

  // define the method to get the feed ids
  List<int> getFeedIDs() {
    List<int> newFeedIDList = [];
    for (Feed feed in feeds) {
      newFeedIDList.add(feed.feedID);
    }
    return newFeedIDList;
  }
}

// define the model for a categories list
class Categories {
  Categories({required this.categories});

  // define the properties
  List<Category> categories = [];

  // define the method to renew the news count
  // the news count is the number of news for each feed
  // the news count is stored in the appBarNewsCount variable if the feed is currently displayed
  // the news count of a category is the sum of the news count of each feed
  // the news count is stored in the appBarNewsCount variable if the category is currently displayed
  // the appState listener are notified to update the news count in the app bar
  Future<void> renewNewsCount(
      FluxNewsState appState, BuildContext context) async {
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      String status = '';
      if (appState.newsStatus == FluxNewsState.allNewsString) {
        status = FluxNewsState.databaseAllString;
      } else {
        status = appState.newsStatus;
      }
      for (Category category in categories) {
        int? categoryNewsCount = 0;
        for (Feed feed in category.feeds) {
          int? feedNewsCount;
          List<Map<String, Object?>> result = await appState.db!.rawQuery(
              'SELECT COUNT(*) FROM news WHERE feedID = ? AND status LIKE ?',
              [feed.feedID, status]);
          feedNewsCount =
              result.isNotEmpty ? result.first.values.first as int? : 0;
          feedNewsCount ??= 0;
          categoryNewsCount ??= 0;
          categoryNewsCount = categoryNewsCount + feedNewsCount;
          feed.newsCount = feedNewsCount;
          if (appState.appBarText == feed.title) {
            appCounterState.appBarNewsCount = feedNewsCount;
          }
        }
        categoryNewsCount ??= 0;
        category.newsCount = categoryNewsCount;
        if (appState.appBarText == category.title) {
          appCounterState.appBarNewsCount = categoryNewsCount;
        }
      }
      appCounterState.refreshView();
    }
  }
}

// define the model for a Attachment
class Attachment {
  Attachment(
      {required this.attachmentID,
      required this.newsID,
      required this.attachmentURL,
      required this.attachmentMimeType,
      this.mediaProgression = 0});

  // define the properties
  int attachmentID = 0;
  int newsID = 0;
  String attachmentURL = '';
  String attachmentMimeType = '';
  int mediaProgression = 0;

  // define the method to convert the model from json
  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      attachmentID: json['id'],
      newsID: json['entry_id'],
      attachmentURL: json['url'],
      attachmentMimeType: json['mime_type'],
      mediaProgression: json['media_progression'] ?? 0,
    );
  }

  // define the method to convert the model to database
  Map<String, dynamic> toMap() {
    return {
      'attachmentID': attachmentID,
      'newsID': newsID,
      'attachmentURL': attachmentURL,
      'attachmentMimeType': attachmentMimeType,
      'mediaProgression': mediaProgression,
    };
  }

  // define the method to convert the model from database
  Attachment.fromMap(Map<String, dynamic> res)
      : attachmentID = res['attachmentID'],
        newsID = res['newsID'],
        attachmentURL = res['attachmentURL'],
        attachmentMimeType = res['attachmentMimeType'],
        mediaProgression = res['mediaProgression'] ?? 0;
}

// define the model for Version response
class Version {
  Version(
      {required this.version,
      required this.commit,
      required this.buildDate,
      required this.goVersion,
      required this.compiler,
      required this.arch,
      required this.os});

  // define the properties
  String version = '';
  String commit = '';
  String buildDate = '';
  String goVersion = '';
  String compiler = '';
  String arch = '';
  String os = '';

  // define the method to convert the model from json
  factory Version.fromJson(Map<String, dynamic> json) {
    return Version(
      version: json['version'],
      commit: json['commit'],
      buildDate: json['build_date'],
      goVersion: json['go_version'],
      compiler: json['compiler'],
      arch: json['arch'],
      os: json['os'],
    );
  }
}

// this is a helper function to get the actual tab position
// this position is used to open the context menu of the news card here
String truncateText(String text, int characterLimit) {
  String truncatedText = '';
  int characterCount = 0;
  final words = text.split(' ');
  for (String word in words) {
    characterCount = characterCount + word.length;
    truncatedText = truncatedText + word;
    if (characterCount < characterLimit) {
      truncatedText = '$truncatedText ';
    } else {
      truncatedText = '$truncatedText...';
      break;
    }
  }
  return truncatedText;
}
