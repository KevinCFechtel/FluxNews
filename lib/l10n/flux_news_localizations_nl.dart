// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'flux_news_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get fluxNews => 'Flux News';

  @override
  String get minifluxServer => 'Miniflux Server';

  @override
  String get allNews => 'Alle nieuws';

  @override
  String get noNewEntries => 'Geen nieuw nieuws';

  @override
  String get deleteBookmark => 'Bladwijzer verwijderen';

  @override
  String get addBookmark => 'Bladwijzer toevoegen';

  @override
  String get markAsRead => 'Markeer als gelezen';

  @override
  String get markAsUnread => 'Markeer als ongelezen';

  @override
  String get showUnread => 'Alleen ongelezen berichten';

  @override
  String get showRead => 'Alle nieuws';

  @override
  String get settingsNotSet => 'Instellingen niet correct';

  @override
  String get provideMinifluxCredentials =>
      'Voer de Miniflux-URL en de API-sleutel in';

  @override
  String get error => 'Fout';

  @override
  String get ok => 'Ok';

  @override
  String get all => 'Alle';

  @override
  String get always => 'Always';

  @override
  String get settings => 'Instellingen';

  @override
  String get minifluxSettings => 'Miniflux instellingen';

  @override
  String get apiUrl => 'API Url';

  @override
  String get apiKey => 'API sleutel';

  @override
  String get minifluxVersion => 'Miniflux versie';

  @override
  String get brightnesMode => 'Helderheidsmodus';

  @override
  String get sortOrderOfNews => 'Sorteervolgorde van de berichten';

  @override
  String get markAsReadOnScrollover => 'Markeer als gelezen bij scrollen over';

  @override
  String get amountSaved => 'Aantal berichten die zijn opgeslagen';

  @override
  String get amountSavedStarred =>
      'Aantal berichten met bladwijzers die zijn opgeslagen';

  @override
  String get titleURL => 'URL';

  @override
  String get enterURL => 'Voer de URL in:';

  @override
  String get enterValidURL =>
      'Voer een correcte Miniflux URL in met een schuine streep aan het einde';

  @override
  String get cancel => 'Annuleren';

  @override
  String get enterAPIKey => 'Voer de API-sleutel in:';

  @override
  String get titleAPIKey => 'API-sleutel';

  @override
  String get save => 'Opslaan';

  @override
  String get system => 'Systeem';

  @override
  String get dark => 'Donker';

  @override
  String get light => 'Licht';

  @override
  String get newestFirst => 'Nieuwste eerst';

  @override
  String get oldestFirst => 'Oudste eerst';

  @override
  String get communicateionMinifluxError =>
      'Er is een fout opgetreden tijdens de communicatie met de miniflux-server';

  @override
  String get databaseError =>
      'Er is een fout opgetreden tijdens het verwerken van de gegevens';

  @override
  String get authError => 'Fout bij het inloggen op Miniflux';

  @override
  String get generalSettings => 'Algemene instellingen';

  @override
  String get syncOnStart => 'Synchroniseer nieuws bij het opstarten';

  @override
  String get bookmarked => 'Bladwijzers';

  @override
  String get itemCount => 'Aantal';

  @override
  String get multilineAppBarTextSetting =>
      'Toon het aantal nieuw in de appbalk';

  @override
  String get showFeedIconsTextSettings => 'Toon de icons van de feeds';

  @override
  String get descriptionMinifluxApp =>
      'Dit is een eenvoudige nieuwslezer die werkt met de miniflux server.\nGa voor meer informatie over het miniflux-project naar de projectpagina:';

  @override
  String get descriptionMoreInformation =>
      'Ga voor meer informatie over deze app naar de projectpagina:';

  @override
  String get search => 'Zoeken';

  @override
  String get searchHint => 'Zoeken...';

  @override
  String get emptySearch => 'Geen nieuws gevonden';

  @override
  String get exportLogs => 'Exporteer debug logs';

  @override
  String get debugModeTextSettings => 'Debugmodus activeren';

  @override
  String get deleteLocalCache => 'Wis het lokale nieuwsgeheugen';

  @override
  String get deleteLocalCacheDialogTitle => 'Wis het nieuwscache';

  @override
  String get deleteLocalCacheDialogContent =>
      'Wil je echt het lokale berichtgeheugen wissen?';

  @override
  String get contextSaveButton => 'Nieuws opslaan in systeem van derden';

  @override
  String get insecureMinifluxURL =>
      'Er wordt een onveilige verbinding met miniflux gebruikt!';

  @override
  String get longSyncWarning =>
      'Het aantal nieuws leidt tot trage synchronisatie!';

  @override
  String get longSyncHeader => 'Trage synchronisatie';

  @override
  String get tooManyNews =>
      'Het aantal berichten overschrijdt de limiet van 10.000, daarom is synchronisatie niet mogelijk.\nVerminder het aantal te synchroniseren berichten.';

  @override
  String get markAllAsRead => 'Markeer alle nieuws als gelezen';

  @override
  String get markBookmarkedAsRead => 'Bladwijzers markeren als gelezen';

  @override
  String get markCategoryAsRead => 'Categorie als gelezen markeren';

  @override
  String get markFeedAsRead => 'Feed als gelezen markeren';

  @override
  String get amountOfSyncedNews => 'Aantal nieuws dat is gesynchroniseerd';

  @override
  String get amountOfSearchedNews => 'Aantal nieuws dat wordt doorzocht';

  @override
  String get debugSettings => 'Debug Settings';

  @override
  String get truncateSettings => 'Truncate Settings';

  @override
  String get activateTruncate => 'Truncate news text';

  @override
  String get truncateMode => 'Truncate Mode';

  @override
  String get truncateModeAll => 'Truncate all news';

  @override
  String get truncateModeScraper =>
      'Truncate all news from feeds with original content fetched';

  @override
  String get truncateModeManual =>
      'Truncate all news from feeds which has been selected manually in the feed settings';

  @override
  String get charactersToTruncate =>
      'Amount of characters to which the text is truncated';

  @override
  String get charactersToTruncateLimit =>
      'Amount of characters from which the text is truncated';

  @override
  String get manualTruncate => 'Truncate news';

  @override
  String get successfullSaveToThirdParty => 'The news was successfully saved!';

  @override
  String get addBookmarkShort => 'Add Bookmark';

  @override
  String get bookmarkShort => 'Bookmark';

  @override
  String get saveShort => 'Save';

  @override
  String get readShort => 'Read';

  @override
  String get unreadShort => 'Unread';

  @override
  String get leftSwipeSelectionOption =>
      'Select action for swiping to the left';

  @override
  String get rightSwipeSelectionOption =>
      'Select action for swiping to the right';

  @override
  String get secondLeftSwipeSelectionOption =>
      'Select second action for swiping to the left';

  @override
  String get secondRightSwipeSelectionOption =>
      'Select second action for swiping to the right';

  @override
  String get deleteBookmarkShort => 'Delete bookmark';

  @override
  String get activateSwiping => 'Activate swipe gestures';

  @override
  String get feedSettings => 'Feed settings';

  @override
  String get emptyFeedList => 'No Feeds fetched';

  @override
  String get preferParagraph => 'Prefer first HTML paragraph as news text';

  @override
  String get preferAttachmentImage => 'Prefer attachment image as news picture';

  @override
  String get manualAdaptLightModeToIcon =>
      'Manual adapt the light mode to a transparent feed icon';

  @override
  String get manualAdaptDarkModeToIcon =>
      'Manual adapt the dark mode to a transparent feed icon';

  @override
  String get openMinifluxEntry => 'Open news in miniflux webinterface';

  @override
  String get openMinifluxShort => 'Open in miniflux';

  @override
  String get scrollHorizontal => 'Scroll horizontal';

  @override
  String get open => 'Open';

  @override
  String get floatingActionButton =>
      'Use an extra button to mark all messages as read';

  @override
  String get useBlackMode => 'Enable black mode specifically for OLED displays';

  @override
  String get expand => 'Expand';

  @override
  String get menu => 'Action Menu';

  @override
  String get tabActionSettings => 'Select action for tapping on a news item';

  @override
  String get longPressActionSettings =>
      'Select action for long press on a news item';

  @override
  String get expandedWithFulltext =>
      'Show only text instead of HTML when expanding the news content';

  @override
  String get showHeadlineOnTop =>
      'Show the headline of the news above the image';

  @override
  String get showOnlyFeedCategoriesWithNewNews =>
      'Only show the categories and feeds that have new messages';

  @override
  String get none => 'None';

  @override
  String get syncInProgress => 'Sync in progress...';
}
