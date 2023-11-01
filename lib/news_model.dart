import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flux_news/flux_news_counter_state.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import 'flux_news_state.dart';

// define the model
class News {
  News(
      {required this.newsID,
      required this.feedID,
      required this.title,
      required this.url,
      required this.content,
      required this.hash,
      required this.publishedAt,
      required this.createdAt,
      required this.status,
      required this.readingTime,
      required this.starred,
      required this.feedTitel,
      this.attachments,
      this.attachmentURL,
      this.attachmentMimeType});
  // define the properties
  int newsID = 0;
  int feedID = 0;
  String title = '';
  String url = '';
  String content = '';
  String hash = '';
  String publishedAt = '';
  String createdAt = '';
  String status = '';
  int readingTime = 0;
  bool starred = false;
  String feedTitel = '';
  String? syncStatus = FluxNewsState.notSyncedSyncStatus;
  Uint8List? icon;
  String? iconMimeType = '';
  List<Attachment>? attachments;
  String? attachmentURL = '';
  String? attachmentMimeType = '';

  // define the method to convert the json to the model
  factory News.fromJson(Map<String, dynamic> json) {
    News news = News(
      newsID: json['id'],
      feedID: json['feed_id'],
      title: json['title'],
      url: json['url'],
      content: json['content'],
      hash: json['hash'],
      publishedAt: json['published_at'],
      createdAt: json['created_at'],
      status: json['status'],
      readingTime: json['reading_time'],
      starred: json['starred'],
      feedTitel: json['feed']?['title'],
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
      'content': content,
      'hash': hash,
      'publishedAt': publishedAt,
      'createdAt': createdAt,
      'status': status,
      'readingTime': readingTime,
      'starred': starred ? 1 : 0,
      'feedTitle': feedTitel,
      'syncStatus': syncStatus,
    };
  }

  // define the method to convert the model from the database
  News.fromMap(Map<String, dynamic> res)
      : newsID = res['newsID'],
        feedID = res['feedID'],
        title = res['title'],
        url = res['url'],
        content = res['content'],
        hash = res['hash'],
        publishedAt = res['publishedAt'],
        createdAt = res['createdAt'],
        status = res['status'],
        readingTime = res['readingTime'],
        starred = res['starred'] == 1 ? true : false,
        feedTitel = res['feedTitle'],
        syncStatus = res['syncStatus'],
        icon = res['icon'],
        iconMimeType = res['iconMimeType'],
        attachmentURL = res['attachmentURL'],
        attachmentMimeType = res['attachmentMimeType'];

  // define the method to extract the text from the html content
  // the text is first searched in the raw text
  // the text is split at the first line break
  // if this result is less than 50 chars, the text is searched in the p tags
  // if no text is found the empty string is returned
  // if there is no raw text the text is searched in the p tags
  String getText() {
    final document = parse(content);
    String? text = '';
    text = parse(document.body?.text).documentElement?.text;
    if (text != null) {
      text = text.split('\n').first;
      if (text.length < 50) {
        List<dom.Element> elemente = document.getElementsByTagName('p');
        if (elemente.isNotEmpty) {
          text = elemente.first.text;
        }
      }
    } else {
      List<dom.Element> elemente = document.getElementsByTagName('p');
      if (elemente.isNotEmpty) {
        text = elemente.first.text;
      }
    }
    text ??= '';
    return text;
  }

  Attachment getFirstImmageAttachment() {
    Attachment imageAttachment = Attachment(
        attachmentID: -1,
        newsID: -1,
        attachmentURL: "",
        attachmentMimeType: "");

    if (attachments != null) {
      for (var attachment in attachments!) {
        if (attachment.attachmentMimeType.startsWith("image")) {
          imageAttachment = attachment;
        }
      }
    }
    return imageAttachment;
  }

  // define the method to extract the image url from the html content
  // the image url is searched in the img tags
  // the image url is searched in the src attribute
  // the image url must start with http
  // if no image url is found the noImageUrlString is returned
  String getImageURL() {
    String imageUrl = FluxNewsState.noImageUrlString;
    final document = parse(content);
    var images = document.getElementsByTagName('img');
    for (var image in images) {
      String? attrib = image.attributes['src'];
      if (attrib != null) {
        if (attrib.startsWith('http')) {
          imageUrl = attrib;
        }
      }
    }
    if (imageUrl == FluxNewsState.noImageUrlString) {
      if (attachmentURL != null) {
        imageUrl = attachmentURL!;
      }
    }
    return imageUrl;
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
  Widget getFeedIcon(
      double size, BuildContext context, FluxNewsState appState) {
    bool darkModeEnabled = false;
    if (appState.brightnessMode == FluxNewsState.brightnessModeDarkString) {
      darkModeEnabled = true;
    } else if (appState.brightnessMode ==
        FluxNewsState.brightnessModeSystemString) {
      darkModeEnabled =
          MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    if (icon != null) {
      if (iconMimeType == 'image/svg+xml') {
        if (darkModeEnabled) {
          return SvgPicture.string(
            String.fromCharCodes(icon!),
            width: size,
            height: size,
            colorFilter:
                const ColorFilter.mode(Colors.white70, BlendMode.srcIn),
          );
        } else {
          return SvgPicture.string(
            String.fromCharCodes(icon!),
            width: size,
            height: size,
          );
        }
      } else {
        return Image.memory(
          icon!,
          width: size,
          height: size,
        );
      }
    } else {
      return SizedBox.fromSize(size: Size(size, size));
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
      this.feedIconID});

  // define the properties
  int feedID = 0;
  String title = '';
  String siteUrl = '';
  int? feedIconID;
  int newsCount = 0;
  Uint8List? icon;
  String iconMimeType = '';

  // define the method to convert the model from json
  factory Feed.fromJson(Map<String, dynamic> json) {
    return Feed(
      feedID: json['id'],
      title: json['title'],
      siteUrl: json['site_url'],
      feedIconID: json['icon']?['icon_id'],
    );
  }

  // define the method to convert the model to database
  Map<String, dynamic> toMap() {
    return {
      'feedID': feedID,
      'title': title,
      'site_url': siteUrl,
      'icon': icon,
      'iconMimeType': iconMimeType,
      'newsCount': newsCount,
    };
  }

  // define the method to convert the model from database
  Feed.fromMap(Map<String, dynamic> res)
      : feedID = res['feedID'],
        title = res['title'],
        siteUrl = res['site_url'],
        icon = res['icon'],
        iconMimeType = res['iconMimeType'],
        newsCount = res['newsCount'];

  // define the method to get the feed icon as a widget
  // the icon could be a svg or a png image
  // if the icon is a svg image it is processed by the flutter_svg package
  // the icon is colored in white if the dark mode is enabled
  // the icon is colored in black if the dark mode is disabled
  // if the icon is a png image it is processed by the Image.memory widget
  Widget getFeedIcon(
      double size, BuildContext context, FluxNewsState appState) {
    bool darkModeEnabled = false;
    if (appState.brightnessMode == FluxNewsState.brightnessModeDarkString) {
      darkModeEnabled = true;
    } else if (appState.brightnessMode ==
        FluxNewsState.brightnessModeSystemString) {
      darkModeEnabled =
          MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    if (icon != null) {
      if (iconMimeType == 'image/svg+xml') {
        if (darkModeEnabled) {
          return SvgPicture.string(
            String.fromCharCodes(icon!),
            width: size,
            height: size,
            colorFilter:
                const ColorFilter.mode(Colors.white70, BlendMode.srcIn),
          );
        } else {
          return SvgPicture.string(
            String.fromCharCodes(icon!),
            width: size,
            height: size,
            colorFilter:
                const ColorFilter.mode(Colors.black54, BlendMode.srcIn),
          );
        }
      } else {
        return Image.memory(
          icon!,
          width: size,
          height: size,
        );
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

// define the model for a categorie
class Categorie {
  Categorie({required this.categorieID, required this.title, List<Feed>? feeds})
      : feeds = feeds ?? [];

  // define the properties
  int categorieID = 0;
  String title = '';
  List<Feed> feeds = [];
  int newsCount = 0;

  // define the method to convert the model from json
  factory Categorie.fromJson(Map<String, dynamic> json) {
    return Categorie(
      categorieID: json['id'],
      title: json['title'],
    );
  }

  // define the method to convert the model to database
  Map<String, dynamic> toMap() {
    return {
      'categorieID': categorieID,
      'title': title,
    };
  }

  // define the method to convert the model from database
  Categorie.fromMap(Map<String, dynamic> res)
      : categorieID = res['categorieID'],
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
  List<Categorie> categories = [];

  // define the method to renew the news count
  // the news count is the number of news for each feed
  // the news count is stored in the appBarNewsCount variable if the feed is currently displayed
  // the news count of a categorie is the sum of the news count of each feed
  // the news count is stored in the appBarNewsCount variable if the categorie is currently displayed
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
      for (Categorie categorie in categories) {
        int? categorieNewsCount = 0;
        for (Feed feed in categorie.feeds) {
          int? feedNewsCount;
          feedNewsCount = Sqflite.firstIntValue(await appState.db!.rawQuery(
              'SELECT COUNT(*) FROM news WHERE feedID = ? AND status LIKE ?',
              [feed.feedID, status]));
          feedNewsCount ??= 0;
          categorieNewsCount ??= 0;
          categorieNewsCount = categorieNewsCount + feedNewsCount;
          feed.newsCount = feedNewsCount;
          if (appState.appBarText == feed.title) {
            appCounterState.appBarNewsCount = feedNewsCount;
          }
        }
        categorieNewsCount ??= 0;
        categorie.newsCount = categorieNewsCount;
        if (appState.appBarText == categorie.title) {
          appCounterState.appBarNewsCount = categorieNewsCount;
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
      required this.attachmentMimeType});

  // define the properties
  int attachmentID = 0;
  int newsID = 0;
  String attachmentURL = '';
  String attachmentMimeType = '';

  // define the method to convert the model from json
  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      attachmentID: json['id'],
      newsID: json['entry_id'],
      attachmentURL: json['url'],
      attachmentMimeType: json['mime_type'],
    );
  }

  // define the method to convert the model to database
  Map<String, dynamic> toMap() {
    return {
      'attachmentID': attachmentID,
      'newsID': newsID,
      'attachmentURL': attachmentURL,
      'attachmentMimeType': attachmentMimeType,
    };
  }

  // define the method to convert the model from database
  Attachment.fromMap(Map<String, dynamic> res)
      : attachmentID = res['attachmentID'],
        newsID = res['newsID'],
        attachmentURL = res['attachmentURL'],
        attachmentMimeType = res['attachmentMimeType'];
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
