// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'flux_news_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get fluxNews => 'Flux News';

  @override
  String get minifluxServer => 'Servidor Miniflux';

  @override
  String get allNews => 'Todas las Noticias';

  @override
  String get noNewEntries => 'Ninguna noticia nueva';

  @override
  String get deleteBookmark => 'Eliminar Marcador';

  @override
  String get addBookmark => 'Añadir Marcador';

  @override
  String get markAsRead => 'Marcar como leído';

  @override
  String get iosMarkAsReadQuickAction =>
      'Mostrar \"Marcar como leído\" en el tablero inferior';

  @override
  String get iosClearLiquidGlass => 'Activa \"Clear Liquid Glass\"';

  @override
  String get androidFloatingToolbarActions =>
      'Configurar las acciones del tablero flotante';

  @override
  String get androidFloatingToolbarFixedActionsHint =>
      'La acciones fijadas se muestran siempre. Selecciona y distribuye las acciones adicionales.';

  @override
  String get iosToolbarActionsHint =>
      'La sincronización se mantiene fija. Las acciones seleccionadas se mostrarán directamente siempre que haya espacio; las acciones adicionales permanecen dentro de \"Más\".';

  @override
  String get androidFloatingActionToggleNewsStatus => 'Mostrar Todas/No leidas';

  @override
  String get androidFloatingActionToggleSortOrder => 'Cambiar ordenación';

  @override
  String get androidFloatingAccentTint =>
      'Usa el color destacado para elementos flotantes';

  @override
  String get markAsReadAndNext => 'Marcar como leída y abrir la siguiente';

  @override
  String get moreActions => 'Más acciones';

  @override
  String get markAsUnread => 'Marcar como no leído';

  @override
  String get showUnread => 'Mostrar noticias no leídas';

  @override
  String get showRead => 'Mostrar todas las noticias';

  @override
  String get settingsNotSet => 'Opción no configurada';

  @override
  String get provideMinifluxCredentials =>
      'Por favor, introduce la dirección al servidor Miniflux y la llave de la API';

  @override
  String get error => 'Error';

  @override
  String get ok => 'Ok';

  @override
  String get all => 'Todo';

  @override
  String get always => 'Siempre';

  @override
  String get settings => 'Ajustes';

  @override
  String get minifluxSettings => 'Ajustes de Miniflux';

  @override
  String get apiUrl => 'Dirección de la API';

  @override
  String get apiKey => 'LLave de la API';

  @override
  String get minifluxVersion => 'Versión de Miniflux';

  @override
  String get brightnesMode => 'Apariencia';

  @override
  String get sortOrderOfNews => 'Sort order of News';

  @override
  String get markAsReadOnScrollover => 'Marcar como leida al desplazarse';

  @override
  String get amountSaved => 'Cantidad de noticias a conservar';

  @override
  String get amountSavedStarred =>
      'Cantidad de noticias preferidas a conservar';

  @override
  String get titleURL => 'URL';

  @override
  String get enterURL => 'Introduce la dirección web';

  @override
  String get enterValidURL =>
      'Introduce la dirección web de Miniflux con la barra final';

  @override
  String get cancel => 'Cancelar';

  @override
  String get enterAPIKey => 'Introduce la llave API:';

  @override
  String get titleAPIKey => 'Llave API';

  @override
  String get save => 'Guardar';

  @override
  String get system => 'Sistema';

  @override
  String get dark => 'Oscuro';

  @override
  String get light => 'Claro';

  @override
  String get newestFirst => 'Ultimas primero';

  @override
  String get oldestFirst => 'Antiguas primero';

  @override
  String get communicateionMinifluxError =>
      'Error al comunicarse con el servidor Miniflux';

  @override
  String get databaseError => 'Error al procesar los datos';

  @override
  String get authError => 'Error al autenticar con el servidor Miniflux';

  @override
  String get generalSettings => 'Ajustes Generales';

  @override
  String get syncOnStart => 'Sincronizar Noticias al arrancar';

  @override
  String get bookmarked => 'Marcadas';

  @override
  String get itemCount => 'Recuento';

  @override
  String largeTitleNewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    return '$_temp0';
  }

  @override
  String get multilineAppBarTextSetting =>
      'Mostrar numero de noticias en la Appbar';

  @override
  String get showFeedIconsTextSettings => 'Mostrar icono del feed';

  @override
  String get automaticFeedIconContrast =>
      'Resaltar iconos de feed oscuros automaticamente';

  @override
  String get automaticFeedIconContrastDescription =>
      'Añade una superficial clara detrás de iconos transparentes en modo oscuro. Tienen preferencia los ajustes del feed.';

  @override
  String get ignoreAutomaticFeedIconContrast =>
      'Ignora el resaltar automáticamente el icono del feed.';

  @override
  String get descriptionMinifluxApp =>
      'Un simple lector de noticias para Miniflux.\nPara mas información sobre Miniflux, visita la pagina del proyecto:';

  @override
  String get descriptionMoreInformation =>
      'Para mas información sobre esta aplicación, visita la pagina del proyecto:';

  @override
  String get search => 'Buscar';

  @override
  String get searchHint => 'Buscar…';

  @override
  String get emptySearch => 'No se han encontrado noticias';

  @override
  String get exportLogs => 'Exportar los registros de depuración';

  @override
  String get debugModeTextSettings => 'Activar modo depuración';

  @override
  String get clearLogsOnStart => 'Elimina los registros al arrancar';

  @override
  String get clearLogsOnStartDescription =>
      'Eliminar todos los registros al arrancar la aplicación';

  @override
  String get deleteLocalCache => 'Borrar datos locales';

  @override
  String get deleteLocalCacheDialogTitle => 'Eliminar datos locales';

  @override
  String get deleteLocalCacheDialogContent =>
      'Elije entre eliminar solamente los icono o todos los datos, archivos de audio inclusive.';

  @override
  String get deleteFeedIconsOnly => 'Solo iconos del feed';

  @override
  String get deleteAllLocalData => 'Todo los datos';

  @override
  String get contextSaveButton => 'Guardar noticias en otro servicio';

  @override
  String get insecureMinifluxURL =>
      'Conectado al servidor miniflux con una conexión insegura!';

  @override
  String get longSyncWarning =>
      'La cantidad de mensajes afecta al tiempo de sincronizado!';

  @override
  String get longSyncHeader => 'Sincronización lenta';

  @override
  String get tooManyNews =>
      'El número de mensajes excede el limite de 10,000, por lo que no se puede realizar la sincronización.\nPor favor, reduce el número de noticias sincronizadas.';

  @override
  String get markAllAsRead => 'Marcar todas las noticias como leídas';

  @override
  String get markBookmarkedAsRead => 'Mark bookmarked news as read';

  @override
  String get markCategoryAsRead => 'Marcar categoría cómo leída';

  @override
  String get markFeedAsRead => 'Marcar feed como leído';

  @override
  String get amountOfSyncedNews =>
      'Cantidad de Noticias no leídas que sincronizar';

  @override
  String get amountOfSearchedNews =>
      'Cantidad de Notícias a incluir en la búsqueda';

  @override
  String get debugSettings => 'Ajustes de depuración';

  @override
  String get truncateSettings => 'Ajustes de truncado';

  @override
  String get activateTruncate => 'Truncar el texto de las noticias';

  @override
  String get truncateMode => 'Modo de truncado';

  @override
  String get truncateModeAll => 'Truncar todas las noticias';

  @override
  String get truncateModeScraper =>
      'Truncar todas las noticias de feeds con contenido original extraido';

  @override
  String get truncateModeManual =>
      'Truncar todas las noticias de feeds seleccionados manualmente en los ajustes del feed';

  @override
  String get charactersToTruncate => 'Cantidad de caracteres que truncar';

  @override
  String get charactersToTruncateLimit =>
      'Cantidad de caracteres a partir de la cual truncar';

  @override
  String get manualTruncate => 'Truncar noticias';

  @override
  String get successfullSaveToThirdParty =>
      'La noticia se ha guardado correctamente!';

  @override
  String get addBookmarkShort => 'Añadir Marcador';

  @override
  String get bookmarkShort => 'Marcador';

  @override
  String get saveShort => 'Guardar';

  @override
  String get readShort => 'Leer';

  @override
  String get unreadShort => 'No leidas';

  @override
  String get leftSwipeSelectionOption =>
      'Seleccionar accion para el deslizamiento hacia la izquierda';

  @override
  String get rightSwipeSelectionOption =>
      'Seleccionar accion para el deslizamiento hacia la derecha';

  @override
  String get secondLeftSwipeSelectionOption =>
      'Selecciona la segunda acción al deslizar hacía la izquierda';

  @override
  String get secondRightSwipeSelectionOption =>
      'Selecciona la segunda acción al deslizar hacía la derecha';

  @override
  String get deleteBookmarkShort => 'Eliminar Marcador';

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
  String get syncInProgress => 'Sync in progress…';

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
  String get syncReadStatusImmediately =>
      'Immediately sync read status to server';

  @override
  String get backgroundSyncInterval => 'Background sync for widgets';

  @override
  String get off => 'Off';

  @override
  String get headerSettings =>
      'Set additional custom headers for accessing Miniflux';

  @override
  String get headerKey => 'Header Name:';

  @override
  String get headerValue => 'Header Value:';

  @override
  String get delete => 'Delete';

  @override
  String get headers => 'Headers';

  @override
  String get optional => 'Optional';

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
  String get floating => 'Floating';

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
  String get backupPassword => 'Backup password';

  @override
  String get createUnencryptedBackup => 'Create backup without encryption';

  @override
  String get createUnencryptedBackupWarning =>
      'This is more convenient, but the API key is stored in the backup file without password protection.';

  @override
  String get backupPasswordRepeat => 'Repeat backup password';

  @override
  String get backupPasswordRequired => 'Please enter a backup password.';

  @override
  String get backupPasswordMismatch => 'The backup passwords do not match.';

  @override
  String get backupPasswordInvalid => 'The backup password is invalid.';

  @override
  String get includeSettingsInAndroidBackup =>
      'Include app settings in Android backup';

  @override
  String get includeSettingsInAndroidBackupDescription =>
      'Disabled by default. If enabled, Android may back up the generated settings backup file according to the system backup schedule.';

  @override
  String get androidAutoBackupSuccessful => 'Backup file created successfully';

  @override
  String get androidAutoBackupNotCreated => 'Backup file not created';

  @override
  String get androidAutoBackupFileMissing =>
      'No local Android backup file is available yet.';

  @override
  String get lastChange => 'Last change';

  @override
  String get androidAutoBackupFoundTitle => 'Backup found';

  @override
  String get androidAutoBackupFoundMessage =>
      'An Android backup was restored for Flux News. If the backup is encrypted, you will be asked for the password before restoring.';

  @override
  String get checkAndroidAutoBackup => 'Check Android backup';

  @override
  String get noAndroidAutoBackupFound => 'No Android backup was found.';

  @override
  String get minimumFeedSelection => 'Please select at least one feed.';

  @override
  String get feedCreationError => 'Creation failed.';

  @override
  String get feedSelection => 'Select feed';

  @override
  String get feedCreationDuration => 'Creating…';

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
  String get downloadQueued => 'Queued';

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
  String get resetPlayback => 'Reset';

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
  String get showPlayerDetails => 'Show player details';

  @override
  String get hidePlayerDetails => 'Hide player details';

  @override
  String get advancedSettings => 'Advanced Settings';

  @override
  String get loadingChapters => 'Loading chapters…';

  @override
  String get noChaptersFound => 'No chapters found.';

  @override
  String get autoDeleteDownloadAfterFinish =>
      'Automatically delete audio downloads when finished';

  @override
  String get downloadStarted => 'Download started';

  @override
  String get showLogs => 'Show Logs';

  @override
  String get reload => 'Reload';

  @override
  String get clearList => 'Clear list';

  @override
  String get loading => 'loading…';

  @override
  String get noEntries => 'No entries';

  @override
  String get copyClipboard => 'Copy to clipboard';

  @override
  String get last => 'last';

  @override
  String get cancelAll => 'Cancel all';

  @override
  String get items => 'Items';

  @override
  String get widgetSettings => 'Widget settings';

  @override
  String get openSource => 'Open source';

  @override
  String get widgetLastSync => 'Last sync';

  @override
  String get widgetNever => 'never';

  @override
  String get widgetSync => 'Sync';

  @override
  String get widgetFilterCategory => 'Show a category in widgets';

  @override
  String get widgetFilterFeed => 'Show a feed in widgets';

  @override
  String get widgetFilterCategorySelection => 'Select category for widgets';

  @override
  String get widgetFilterFeedSelection => 'Select feed for widgets';

  @override
  String get widgetBlurredBackground => 'Translucent widget background';
}
