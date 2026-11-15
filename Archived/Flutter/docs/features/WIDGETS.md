# Flux News Widgets

Detailed implementation context for Flutter-generated widget snapshots, Android AppWidgets, iOS WidgetKit, native bridges, and widget actions.

## Current Widget Feature

- Flutter owns sync, SQLite access, user settings, and snapshot generation.
- `lib/functions/widget_service.dart` creates a compact JSON snapshot:
  - localized `displayTitle` for the currently selected widget view (`All News`, `Bookmarks`, category title, or feed title)
  - `unreadCount` as the context count for the current widget filter (`unread` count when unread-only is enabled, `read` count when read items are included)
  - localized `countLabel` (`unread` or `read`)
  - localized `lastSyncLabel`, `neverLabel`, and `syncLabel`
  - `translucentBackground` for Android only, to render the colored background with reduced opacity when enabled in settings. iOS ignores this setting because WidgetKit controls Home Screen container transparency/tint/Liquid Glass behavior.
  - `lastUpdated`
  - `items[]` with `id`, `title`, `feedTitle`, `publishedAt`, `status`, `feedInitial`, `iconMimeType`, `iconData`
- iOS additionally writes a separate `statusSnapshot` without `items[]` for the small `FluxNewsCompactStatusWidget`.
- Native widgets render only this snapshot. They do not read Miniflux credentials or SQLite directly.
- Feed icons are embedded as base64 bitmap data when the local feed icon is not SVG. SVG icons fall back to the feed initial in native widgets.
- Android widget icons render in a fixed 28dp slot with 20dp image content. Feed `manualAdaptLightModeToIcon` / `manualAdaptDarkModeToIcon` flags are applied using the device widget night mode.
- iOS feed icons render with fixed 18pt image content inside a 20pt frame and apply the same manual light/dark adaptation flags using SwiftUI's widget `colorScheme`. Widget backgrounds use explicit light/dark container colors so they remain legible independently of WidgetKit tint/transparency behavior; the user-controlled translucent-background option is Android-only.
- Widget last-sync timestamps are stored as ISO strings and formatted natively with the device locale using medium date and medium time, including seconds.
- Widget settings use a separate unread-only switch plus the same selection shape as startup settings: radio options for all news, bookmarks, category, or feed; a dropdown is shown only for the selected category/feed mode. Legacy `widgetNewsStatus` values are migrated in memory to the new filter fields on first read if the new keys are absent.

## Widget Actions

- `fluxnews://widget/openNews?newsID=<id>` opens the app and then the selected article.
- `fluxnews://widget/sync` opens the app and starts the existing Flutter sync.
- On cold start, Flutter checks for a pending `openNews` widget action before running startup sync. If present, `syncOnStart` is skipped for that launch so the article opens quickly; explicit `syncNow` and widget `sync` actions still sync.
- This first version does not perform Miniflux sync inside a native widget extension/background worker.

## Native Bridges

- Widget snapshot persistence and widget reloads use the Flutter `home_widget` plugin so the same path works from the normal Flutter engine and the Workmanager headless engine. iOS update/reload requests must target both WidgetKit kinds `FluxNewsCompactStatusWidget` and `FluxNewsHeadlinesWidget`.
- The legacy app-owned MethodChannel `dev.kevincfechtel.fluxnews/widgets` is still used for pending widget actions (`peekPendingAction`, `takePendingAction`) while the app is opening.
- Methods:
  - `peekPendingAction`
  - `takePendingAction`
- Android widget data is stored in `HomeWidgetPreferences` under key `snapshot`.
- iOS widget data is stored in App Group `group.dev.kevincfechtel.fluxNews` under key `snapshot`.

## iOS

- Widget target: `FluxNewsWidgets`
- App Group: `group.dev.kevincfechtel.fluxNews`
- Widget kinds: `FluxNewsCompactStatusWidget` for `.systemSmall`; `FluxNewsHeadlinesWidget` for `.systemMedium`, `.systemLarge`, and `.systemExtraLarge`.
- iOS deployment target is raised to 17.0.
- Widget headers show the Flux News logo plus the selected widget view title from the snapshot. Widget content disables WidgetKit default margins and uses explicit top padding plus a compact header so the title/count/sync button are not clipped by rounded widget corners on newer iOS versions. Small shows selected view title, sync button, read/unread count, and last sync; medium shows 2 rows with 14pt top padding; large shows 7 rows on iPhone and 6 rows on iPad because iPad large widgets report enough geometric height for 7 rows even though the seventh row is visually clipped; extra large uses the wider iPad layout as two columns with 6 rows each.
- The iOS small widget is registered as a separate WidgetKit kind (`FluxNewsCompactStatusWidget`) with its own `FluxNewsStatusProvider`, `FluxNewsStatusEntry`, and `statusSnapshot` key to avoid stale/cross-family WidgetKit cache behavior with the headline widgets and to avoid decoding headline `items[]`. It intentionally avoids an embedded `Link` for the sync icon and uses a decorative sync icon plus `.widgetURL(fluxnews://widget/sync)` on the whole small widget.
- The iOS small status view uses the dedicated small widget logo asset copied from `assets/Flux_News_Logo_small.png` (64x64 RGBA). The previous larger PNG asset caused a blank white small widget on iPhone. With the smaller asset, the compact overlay layout and disabled WidgetKit content margins are used again.
- The iOS small status view applies `.unredacted()` because iPhone WidgetKit can otherwise show gray placeholder boxes for the small widget even when the status view has fallback text/logo content.
- If the app-group snapshot is missing or cannot be decoded, the iOS provider renders a visible fallback snapshot (`All News`, `0 unread`, `Last sync: never`) instead of an apparently empty widget. This mainly protects fresh installs/reinstalls before the first successful app-written snapshot and WidgetKit reload.
- Flutter performs a throttled foreground widget refresh on startup/resume: when the app is configured and no sync is currently active, it rewrites the widget snapshot and requests native WidgetKit/HomeWidget reloads. This is intended as a catch-up path for stale iOS WidgetKit timelines after reinstall, charging/low-power deferrals, or long background pauses.
- iOS large and extra-large widgets are both paginated, but use separate global page keys (`largePage` and `extraLargePage`) so the two sizes do not affect each other's current page. The offset is intentionally not per widget instance.
- The iOS widget layout gives the header and last-sync/page-control row higher layout priority. Headlines render in a clipped remaining-height area, so large Dynamic Type can reduce/cut off visible items without pushing the header out of the widget.
- The large iOS widget has seitenweise Up/Down navigation through the snapshot using one global App Group key `largePage`; it is not per widget instance and does not affect the medium widget. Snapshot updates reset the key to page 0.
- Flutter guards widget action handling against reentrant lifecycle calls. This prevents an iOS `openNews` action from being replayed when closing an in-app browser triggers `resumed`.

## Android Home Screen Widgets

- Widget provider: `de.circle_dev.flux_news.FluxNewsWidgetProvider`
- Scrollable list service: `de.circle_dev.flux_news.FluxNewsWidgetService`
- Snapshot storage: `SharedPreferences` named `HomeWidgetPreferences`
- Layouts: `android/app/src/main/res/layout/flux_news_widget.xml` for the headline list, `android/app/src/main/res/layout/flux_news_widget_small.xml` for the compact status size, `android/app/src/main/res/layout/flux_news_widget_tiny.xml` for the 2x1-style ultra-compact status size, `android/app/src/main/res/layout/flux_news_widget_short_medium.xml` for 3x1-style status, and `android/app/src/main/res/layout/flux_news_widget_short_wide.xml` for 4x1-style status.
- Android uses one AppWidget provider with a reduced 110dp minimum width and 40dp minimum height. `FluxNewsWidgetProvider` checks `AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH` and `OPTION_APPWIDGET_MIN_HEIGHT`; widgets shorter than 90dp render by width: 4x1-style (`minWidth >= 320dp`) uses two rows with logo/title/sync first and count/last-sync second, 3x1-style (`minWidth >= 180dp`) uses the same two-row structure with tighter spacing, and narrower widgets use the 2x1 ultra-compact two-row layout. Widgets taller than one row but narrower than 220dp render the compact status layout with logo, selected view title, read/unread count, last sync, and sync button. Wider/taller widgets render headlines in a `ListView` collection widget and receive all matching snapshot items; the list scrolls through the complete widget query result.
- iOS medium remains a static 2-item view. iOS large shows 6 or 7 items per page depending on available height and can move through the complete snapshot with Up/Down buttons.

## Foreground Lifecycle And Widget Actions

- Widget `openNews` actions mark the selected item read in SQLite before opening it, so the regular app list and widget converge on the same status.
- Widget launches intentionally skip only the automatic startup sync. Explicit widget sync actions and normal user-triggered sync remain enabled. Pending actions are peeked without consumption for the skip decision, then consumed exactly once for execution.
- Opening external/native-app links uses a browser fallback when no matching installed app handles the URL.
- Widget action handling is lifecycle/reentrancy guarded because closing the iOS in-app browser can emit another `resumed` event. Do not replay the pending action or reopen the same article on that event.
- A long resume can be treated as a deferred startup only when background sync is enabled. When background sync is disabled, resume behavior intentionally matches the app before background-sync integration: no extra resume sync or database reload is introduced. A future, separate timed sync-on-resume option is explicitly deferred.
