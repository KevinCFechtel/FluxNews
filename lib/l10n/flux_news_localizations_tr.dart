// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'flux_news_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get fluxNews => 'Flux News';

  @override
  String get minifluxServer => 'Miniflux Sunucusu';

  @override
  String get allNews => 'Tüm Haberler';

  @override
  String get noNewEntries => 'Yeni haber yok';

  @override
  String get deleteBookmark => 'Yer İşaretini Sil';

  @override
  String get addBookmark => 'Yer İşareti Ekle';

  @override
  String get markAsRead => 'Okundu olarak işaretle';

  @override
  String get markAsUnread => 'Okunmadı olarak işaretle';

  @override
  String get showUnread => 'Okunmamış haberleri göster';

  @override
  String get showRead => 'Tüm haberleri göster';

  @override
  String get settingsNotSet => 'Ayarlar ayarlanmamış';

  @override
  String get provideMinifluxCredentials =>
      'Lütfen miniflux URL\'si ve API Anahtarı sağlayın';

  @override
  String get error => 'Hata';

  @override
  String get ok => 'Tamam';

  @override
  String get all => 'Tümü';

  @override
  String get always => 'Her zaman';

  @override
  String get settings => 'Ayarlar';

  @override
  String get minifluxSettings => 'Miniflux Ayarları';

  @override
  String get apiUrl => 'API URL\'si';

  @override
  String get apiKey => 'API Anahtarı';

  @override
  String get minifluxVersion => 'Miniflux Sürümü';

  @override
  String get brightnesMode => 'Parlaklık modu';

  @override
  String get sortOrderOfNews => 'Haberlerin sıralama düzeni';

  @override
  String get markAsReadOnScrollover =>
      'Kaydırma sırasında okundu olarak işaretle';

  @override
  String get amountSaved => 'Kaydedilecek Haber Miktarı';

  @override
  String get amountSavedStarred => 'Kaydedilecek yıldızlı Haber Miktarı';

  @override
  String get titleURL => 'URL';

  @override
  String get enterURL => 'URL girin';

  @override
  String get enterValidURL =>
      'Kuyruklu eğik çizgi ile geçerli bir Miniflux URL\'si girin';

  @override
  String get cancel => 'İptal';

  @override
  String get enterAPIKey => 'API Anahtarını girin:';

  @override
  String get titleAPIKey => 'API Anahtarı';

  @override
  String get save => 'Kaydet';

  @override
  String get system => 'Sistem';

  @override
  String get dark => 'Koyu';

  @override
  String get light => 'Açık';

  @override
  String get newestFirst => 'Önce en yeni';

  @override
  String get oldestFirst => 'Önce en eski';

  @override
  String get communicateionMinifluxError =>
      'Miniflux sunucusuyla iletişim kurarken hata oluştu';

  @override
  String get databaseError => 'Veriler işlenirken hata oluştu';

  @override
  String get authError => 'Miniflux\'a karşı kimlik doğrulama hatası';

  @override
  String get generalSettings => 'Genel Ayarlar';

  @override
  String get syncOnStart => 'Başlangıçta Haberleri Senkronize Et';

  @override
  String get bookmarked => 'Yer işaretlerine eklendi';

  @override
  String get itemCount => 'Miktar';

  @override
  String get multilineAppBarTextSetting => 'Appbar\'da haber sayısını göster';

  @override
  String get showFeedIconsTextSettings => 'Besleme simgelerini göster';

  @override
  String get descriptionMinifluxApp =>
      'Bu, miniflux ile çalışmak için basit bir Haber okuyucusudur.\nMiniflux hakkında daha fazla bilgi için proje sayfasını ziyaret edin:';

  @override
  String get descriptionMoreInformation =>
      'Bu uygulama hakkında daha fazla bilgi için proje sayfasını ziyaret edin:';

  @override
  String get search => 'Arama';

  @override
  String get searchHint => 'Ara...';

  @override
  String get emptySearch => 'Haber bulunamadı';

  @override
  String get exportLogs => 'Hata ayıklama günlüklerini dışa aktar';

  @override
  String get debugModeTextSettings => 'Hata ayıklama modunu etkinleştir';

  @override
  String get deleteLocalCache => 'Yerel haber deposunu temizle';

  @override
  String get deleteLocalCacheDialogTitle => 'Yerel önbelleği sil';

  @override
  String get deleteLocalCacheDialogContent =>
      'Yerel haber deposunu silmek istediğinizden emin misiniz?';

  @override
  String get contextSaveButton => 'Haberleri üçüncü tarafa kaydet';

  @override
  String get insecureMinifluxURL =>
      'Miniflux\'a güvensiz bir bağlantı kullanılıyor!';

  @override
  String get longSyncWarning =>
      'Mesaj sayısı yavaş senkronizasyona neden oluyor!';

  @override
  String get longSyncHeader => 'Yavaş senkronizasyon';

  @override
  String get tooManyNews =>
      'Mesaj sayısı 10.000 sınırını aşıyor, bu nedenle senkronizasyon mümkün değil.\nLütfen senkronize edilen haber miktarını azaltın.';

  @override
  String get markAllAsRead => 'Tüm haberleri okundu olarak işaretle';

  @override
  String get markBookmarkedAsRead =>
      'Yer işaretli haberleri okundu olarak işaretle';

  @override
  String get markCategoryAsRead => 'Kategoriyi okundu olarak işaretle';

  @override
  String get markFeedAsRead => 'Beslemeyi okundu olarak işaretle';

  @override
  String get amountOfSyncedNews => 'Senkronize edilecek Haber Miktarı';

  @override
  String get amountOfSearchedNews => 'Aranacak Haber Miktarı';

  @override
  String get debugSettings => 'Hata Ayıklama Ayarları';

  @override
  String get truncateSettings => 'Kısaltma Ayarları';

  @override
  String get activateTruncate => 'Haber metnini kısalt';

  @override
  String get truncateMode => 'Kısaltma Modu';

  @override
  String get truncateModeAll => 'Tüm haberleri kısalt';

  @override
  String get truncateModeScraper =>
      'Orijinal içeriği alınan beslemelerden tüm haberleri kısalt';

  @override
  String get truncateModeManual =>
      'Manuel olarak seçilen beslemelerden tüm haberleri kısalt (belirli bir beslemede uzun basarak)';

  @override
  String get charactersToTruncate => 'Metnin kısaltılacağı karakter sayısı';

  @override
  String get charactersToTruncateLimit =>
      'Metnin kısaltılacağı karakter sınırı';

  @override
  String get manualTruncate => 'Haberleri kısalt';

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
      'Use an extra button for additional functions';

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
      'Show formatted text instead of full HTML when expanding the news content';

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

  @override
  String get startupCategorie => 'Choose Categorie for startup';

  @override
  String get startupCategorieAll => 'Show all news on startup';

  @override
  String get startupCategorieBookmarks =>
      'Show the bookmark categorie on startup';

  @override
  String get startupCategorieCategorie =>
      'Choose a categorie as default for startup';

  @override
  String get startupCategorieFeed => 'Choose a feed as default for startup';

  @override
  String get startupCategorieCategorieSelection =>
      'Select a categorie as default for startup';

  @override
  String get startupCategorieFeedSelection =>
      'Select a feed as default for startup';

  @override
  String get share => 'Share';

  @override
  String get openComments => 'Open Comments';

  @override
  String get splitted => 'Splitted';

  @override
  String get splittedDescription =>
      'Splitted means that clicking on the text expands the text, and clicking on the title or the image opens the link';

  @override
  String get amountOfCharactersToTruncateExpand =>
      'Amount of characters to which the expanded formatted text is truncated';

  @override
  String get syncSettings => 'Sync Settings';

  @override
  String get newsItemSettings => 'News Item Settings';

  @override
  String get removeNewsFromListWhenRead =>
      'Remove the news from the list when marked as read';

  @override
  String get syncReadNews => 'Also synchronize read news';

  @override
  String get syncReadNewsAfterDays =>
      'Synchronize read news from the last days: ';

  @override
  String get skipLongSync => 'Skip long sync dialog';

  @override
  String get headerSettings =>
      'Set additional custom headers for accessing Miniflux';

  @override
  String get headerKey => 'Header Name: ';

  @override
  String get headerValue => 'Header Value: ';

  @override
  String get delete => 'Delete';

  @override
  String get headers => 'Headers';

  @override
  String get scrolloverAppBar => 'The app bar is collapsible on scroll';

  @override
  String get syncNews => 'Sync News';

  @override
  String get floatingButtonAction => 'Select the action for the extra button';

  @override
  String get markNewsAsReadButton => 'Mark as read';

  @override
  String get glassAppBar => 'The app bar has a glass effect';

  @override
  String get normal => 'Normal';

  @override
  String get collapsible => 'Collapsible';

  @override
  String get glass => 'Glass Effect';

  @override
  String get appBarType => 'Select the App Bar Type';

  @override
  String get glassActionButton => 'Show the extra button with a glass effect';

  @override
  String get imageCacheDurationDays => 'Number of days to keep images in cache';

  @override
  String get login => 'Login';

  @override
  String get restoreSettings => 'Restore settings';

  @override
  String get backupSettings => 'Backup settings';

  @override
  String get backupSettingsDescription =>
      'Backup all settings including feed settings';

  @override
  String get backupError => 'Failed to create backup.';

  @override
  String get saveHeader => 'Save Header';

  @override
  String get confirmRestore => 'Confirm restore';

  @override
  String get confirmRestoreOverride =>
      'This will overwrite your current settings and feed configurations.';

  @override
  String get file => 'File';

  @override
  String get backupType => 'Backup-Type';

  @override
  String get createdAt => 'Created at';

  @override
  String get appVersion => 'App version';

  @override
  String get restore => 'Restore';

  @override
  String get backupCheckFailed => 'Backup check failed';

  @override
  String get invalidFile => 'The selected file is invalid.';

  @override
  String get fileSelectionFailed => 'The file selection failed';

  @override
  String get backupSuccessfullyRestored => 'Backup successfully restored';

  @override
  String get restoreFailed => 'Restore failed';

  @override
  String get selectZipBackupFile =>
      'Select a ZIP backup file to restore settings.';

  @override
  String get selectZipBackupFileButton => 'Select ZIP file and restore';

  @override
  String get minimumFeedSelection => 'Please select at least one feed.';

  @override
  String get feedCreationError => 'Creation failed.';

  @override
  String get feedSelection => 'Select feed';

  @override
  String get feedCreationDuration => 'Creating...';

  @override
  String get feedCreationDescription =>
      'Select multiple feeds. The selected feeds will be created in your Miniflux account.';

  @override
  String get feedSelectionSelectAll => 'Select all';

  @override
  String get feedSelectionDeleteSelection => 'Clear selection';

  @override
  String get downloadsManagerDeleteTitle => 'Delete Download?';

  @override
  String get downloadsManagerDeleteMessage =>
      'Are you sure you want to delete this download?';

  @override
  String get downloadsManagerDeletedSnackbar => 'Download deleted';

  @override
  String get downloadsManagerClearAllTitle => 'Delete all downloads?';

  @override
  String get downloadsManagerClearAllMessage =>
      'This will delete all downloaded audio files. This action cannot be undone.';

  @override
  String get downloadsManagerClearedSnackbar => 'All downloads deleted';

  @override
  String get downloadsManagerClearAll => 'Delete all downloads';

  @override
  String get audioDownloadsSettings => 'Podcasts';

  @override
  String get audioDownloadsSettingsDescription =>
      'View active downloads and downloaded data';

  @override
  String get deleteDownloadAfterFinishing =>
      'Automatically delete downloads after listening';

  @override
  String get downloadAudioWLAN => 'Download audio via Wi-Fi only';

  @override
  String get autoDownloadAudio => 'Auto-download audio after sync';

  @override
  String get audioDownloadRetentionDays =>
      'Number of days to keep audio downloads';

  @override
  String get chapterFrom => 'Chapter from';

  @override
  String get downloadWLANWarning =>
      'Downloads allowed via Wi-Fi only. Please enable Wi-Fi.';

  @override
  String get noAudioFileAvailable => 'No audio file available.';

  @override
  String get sleepTimerNotification =>
      'Sleep Timer: Playback stopped automatically.';

  @override
  String get sleepTimerOff => 'Sleep Timer: Off';

  @override
  String get sleepTimerEndingSoon => 'Sleep Timer: Ending soon';

  @override
  String get sleepTimerActive => 'Sleep Timer: active';

  @override
  String get sleepTimerRemaining => 'min remaining';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get downloadAudio => 'Download Audio';

  @override
  String get speed => 'Speed';

  @override
  String get chapters => 'Chapters';

  @override
  String get interval => 'Interval';

  @override
  String get minutes => 'min';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get resume => 'Resume';

  @override
  String get stop => 'Stop';

  @override
  String get runningDownloads => 'Running downloads';

  @override
  String get noActiveDownloads => 'No active downloads.';

  @override
  String get from => 'from';

  @override
  String get loaded => 'loaded';

  @override
  String get downloadedData => 'Downloaded audio files';

  @override
  String get totalStorage => 'Total storage';

  @override
  String get loadDownloadedDataError => 'Failed to load downloaded files.';

  @override
  String get noAudioDownloads => 'No audio files downloaded yet.';

  @override
  String get fileList => 'Episodes';

  @override
  String get useAudioPlayer => 'Open audio items with audio player';

  @override
  String get advancedSettings => 'Advanced Settings';

  @override
  String get loadingChapters => 'Loading chapters ...';

  @override
  String get noChaptersFound => 'No chapters found.';

  @override
  String get autoDeleteDownloadAfterFinish =>
      'Automatically delete audio downloads when finished';
}
