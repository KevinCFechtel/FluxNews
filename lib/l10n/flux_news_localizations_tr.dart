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
