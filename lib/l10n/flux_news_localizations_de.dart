// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'flux_news_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get fluxNews => 'Flux News';

  @override
  String get minifluxServer => 'Miniflux Server';

  @override
  String get allNews => 'Alle Nachrichten';

  @override
  String get noNewEntries => 'Keine neuen Nachrichten';

  @override
  String get deleteBookmark => 'Lesezeichen löschen';

  @override
  String get addBookmark => 'Lesezeichen hinzufügen';

  @override
  String get markAsRead => 'Als gelesen markieren';

  @override
  String get markAsUnread => 'Als ungelesen markieren';

  @override
  String get showUnread => 'Nur Ungelesene Nachrichten anzeigen';

  @override
  String get showRead => 'Alle Nachrichten anzeigen';

  @override
  String get settingsNotSet => 'Einstellungen nicht korrekt';

  @override
  String get provideMinifluxCredentials =>
      'Bitte geben Sie die Miniflux URL und den API-Schlüssel an';

  @override
  String get error => 'Fehler';

  @override
  String get ok => 'Ok';

  @override
  String get all => 'Alle';

  @override
  String get always => 'Immer';

  @override
  String get settings => 'Einstellungen';

  @override
  String get minifluxSettings => 'Miniflux Einstellungen';

  @override
  String get apiUrl => 'API Url';

  @override
  String get apiKey => 'API Schlüssel';

  @override
  String get minifluxVersion => 'Miniflux Version';

  @override
  String get brightnesMode => 'Helligkeitseinstellung';

  @override
  String get sortOrderOfNews => 'Sortierreihenfolge der Nachrichten';

  @override
  String get markAsReadOnScrollover =>
      'Beim überscrollen als gelesen markieren';

  @override
  String get amountSaved => 'Anzahl der Nachrichten die gespeichert werden';

  @override
  String get amountSavedStarred =>
      'Anzahl der Nachrichten mit Lesezeichen die gespeichert werden';

  @override
  String get titleURL => 'URL';

  @override
  String get enterURL => 'Gebe die URL ein:';

  @override
  String get enterValidURL =>
      'Bitte gebe eine korrekte Miniflux URL an, die am Ende einen Slash besitzt';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get enterAPIKey => 'Gebe den API Schlüssel ein:';

  @override
  String get titleAPIKey => 'API Schlüssel';

  @override
  String get save => 'Speichern';

  @override
  String get system => 'System';

  @override
  String get dark => 'Dunkel';

  @override
  String get light => 'Hell';

  @override
  String get newestFirst => 'Neueste zuerst';

  @override
  String get oldestFirst => 'Älteste zuerst';

  @override
  String get communicateionMinifluxError =>
      'Es ist ein Fehler während der Kommunikation mit dem miniflux Server aufgetreten';

  @override
  String get databaseError =>
      'Es ist ein Fehler bei der Verarbeitung der Daten aufgetreten';

  @override
  String get authError => 'Fehler bei der Anmeldung am miniflux';

  @override
  String get generalSettings => 'Allgemeine Einstellungen';

  @override
  String get syncOnStart => 'Synchronisiere Nachrichten beim Start';

  @override
  String get bookmarked => 'Lesezeichen';

  @override
  String get itemCount => 'Anzahl';

  @override
  String get multilineAppBarTextSetting =>
      'Zeige die Anzahl der Nachrichten in der Appbar';

  @override
  String get showFeedIconsTextSettings => 'Zeige die Icons der Feeds an';

  @override
  String get descriptionMinifluxApp =>
      'Dies ist ein simpler Newsreader, der mit dem miniflux Server zusammenarbeitet\nFür mehr Informationen über das miniflux Projekt besuchen Sie bitte die Projektseite:';

  @override
  String get descriptionMoreInformation =>
      'Für mehr Informationen über diese App besuchen Sie bitte die Projektseite:';

  @override
  String get search => 'Suchen';

  @override
  String get searchHint => 'Suchen...';

  @override
  String get emptySearch => 'Keine Nachrichten gefunden';

  @override
  String get exportLogs => 'Export debug Logs';

  @override
  String get debugModeTextSettings => 'Debug Modus aktivieren';

  @override
  String get deleteLocalCache => 'Lösche den lokalen Nachrichtenspeicher';

  @override
  String get deleteLocalCacheDialogTitle => 'Nachrichtenspeicher löschen';

  @override
  String get deleteLocalCacheDialogContent =>
      'Möchten Sie wirklich den lokalen Nachrichtenspeicher löschen?';

  @override
  String get contextSaveButton => 'Nachricht in Drittsystem speichern';

  @override
  String get insecureMinifluxURL =>
      'Es wird eine unsichere Verbindung zu miniflux benutzt!';

  @override
  String get longSyncWarning =>
      'Die Anzahl der Nachrichten führt zu einer langsamen Synchronisation!';

  @override
  String get longSyncHeader => 'Langsame Synchronisation';

  @override
  String get tooManyNews =>
      'Die Anzahl der Nachrichten überschreitet die Grenze von 10.000, daher ist eine Synchronisation nicht möglich.\nBitte reduzieren Sie die Anzahl der zu synchronisierenden Nachrichten.';

  @override
  String get markAllAsRead => 'Alle Nachrichten als gelesen markieren';

  @override
  String get markBookmarkedAsRead => 'Lesezeichen als gelesen markieren';

  @override
  String get markCategoryAsRead => 'Kategorie als gelesen markieren';

  @override
  String get markFeedAsRead => 'Feed als gelesen markieren';

  @override
  String get amountOfSyncedNews =>
      'Anzahl der Nachrichten die synchronisiert werden';

  @override
  String get amountOfSearchedNews =>
      'Anzahl der Nachrichten die durchsucht werden';

  @override
  String get debugSettings => 'Debug Einstellungen';

  @override
  String get truncateSettings => 'Truncate Einstellungen';

  @override
  String get activateTruncate => 'Nachrichtentext abschneiden';

  @override
  String get truncateMode => 'Truncate Modus';

  @override
  String get truncateModeAll =>
      'Nachrichtentext bei allen Nachrichten abschneiden';

  @override
  String get truncateModeScraper =>
      'Nachrichtentext bei Nachrichten von Feeds abschneiden, bei denen der Originalinhalt heruntergelanden wird';

  @override
  String get truncateModeManual =>
      'Nachrichtentext bei Nachrichten von Feeds abschneiden, die manuell in den Feed Einstellungen ausgewählt wurden';

  @override
  String get charactersToTruncate =>
      'Anzahl der Zeichen auf die der Text gekürzt wird';

  @override
  String get charactersToTruncateLimit =>
      'Anzahl der Zeichen ab denen der Text gekürzt wird';

  @override
  String get manualTruncate => 'Nachrichtentext abschneiden';

  @override
  String get successfullSaveToThirdParty =>
      'Die Nachricht wurde erfolgreich gespeichert!';

  @override
  String get addBookmarkShort => 'Lesezeichen hinzufügen';

  @override
  String get bookmarkShort => 'Lesezeichen';

  @override
  String get saveShort => 'Speichern';

  @override
  String get readShort => 'Gelesen';

  @override
  String get unreadShort => 'Ungelesen';

  @override
  String get leftSwipeSelectionOption =>
      'Wählen Sie die Aktion, die bei einem Wisch nach links ausgeführt werden soll';

  @override
  String get rightSwipeSelectionOption =>
      'Wählen Sie die Aktion, die bei einem Wisch nachrechts ausgeführt werden soll';

  @override
  String get secondLeftSwipeSelectionOption =>
      'Wählen Sie die zweite Aktion, die bei einem Wisch nach links ausgeführt werden soll';

  @override
  String get secondRightSwipeSelectionOption =>
      'Wählen Sie die zweite Aktion, die bei einem Wisch nachrechts ausgeführt werden soll';

  @override
  String get deleteBookmarkShort => 'Lesezeichen entfernen';

  @override
  String get activateSwiping => 'Aktiviere Wischgesten';

  @override
  String get feedSettings => 'Feed Einstellungen';

  @override
  String get emptyFeedList => 'Keine Feeds vorhanden';

  @override
  String get preferParagraph =>
      'Bevorzuge den ersten HTML Paragraphen mit Text als News Text';

  @override
  String get preferAttachmentImage => 'Bevorzuge das angehängte Bild';

  @override
  String get manualAdaptLightModeToIcon =>
      'Passe ein durchsichtiges Feed Icon manuell an den Light Mode an';

  @override
  String get manualAdaptDarkModeToIcon =>
      'Passe  ein durchsichtiges Feed Icon manuell an den Dark Mode an';

  @override
  String get openMinifluxEntry =>
      'Öffne die Nachricht im Miniflux Webinterface';

  @override
  String get openMinifluxShort => 'Öffnen in Miniflux';

  @override
  String get scrollHorizontal => 'Horizontal scrollen';

  @override
  String get open => 'Öffnen';

  @override
  String get floatingActionButton =>
      'Nutze einen extra Button um alle Nachrichten als gelesen zu markieren';

  @override
  String get useBlackMode =>
      'Aktiviere den Black Mode speziell für OLED Displays';

  @override
  String get expand => 'Erweitern';

  @override
  String get menu => 'Aktionsmenü';

  @override
  String get tabActionSettings =>
      'Wählen Sie die Aktion, die bei einem Tab auf die News ausgeführt werden soll';

  @override
  String get longPressActionSettings =>
      'Wählen Sie die Aktion, die bei einem Long Press auf die News ausgeführt werden soll';

  @override
  String get expandedWithFulltext =>
      'Zeige nur Text statt HTML bei der Erweiterung des News Inhalts';

  @override
  String get showHeadlineOnTop =>
      'Zeige die Überschrift der News über dem Bild';

  @override
  String get showOnlyFeedCategoriesWithNewNews =>
      'Zeige nur die Kategorien und Feeds an, die neue Nachrichten besitzen';

  @override
  String get none => 'Keine';
}
