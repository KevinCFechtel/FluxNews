# iOS D5 Final Acceptance

Status: **COMPLETE / ARCHITECTURE-FROZEN — 24 September 2026**

This acceptance record closes **D5 — Background Sync, Local Notifications & Widgets** for the native iOS/iPadOS client. It supplements the authoritative Phase-D contract and records the final real-device evidence that was still pending for D5-G.

## Closure

D5-A through D5-F were already complete before this acceptance pass. D5-G (Native iOS WidgetKit, including Lock Screen widgets) is now also **COMPLETE / real-device accepted**. Therefore D5 as a whole is **COMPLETE / architecture-frozen**.

Future changes require a concrete product requirement or reproducible regression. The separately recorded D4 follow-ups in `IOS_D4_FOLLOWUP_FINDINGS.md` are explicitly outside this D5 freeze.

## Final real-device acceptance

The final physical-device pass confirmed the complete background-to-presentation chain without opening the app:

1. iOS launches the registered `BGAppRefreshTask` while FluxNews is not foregrounded.
2. The native app executes the existing Core `sync(.background)` path.
3. New eligible articles produce the expected local System Notifications.
4. Successful background completion writes an updated App Group widget snapshot before BGTask completion.
5. WidgetKit subsequently reads the updated snapshot and refreshes the installed widgets without requiring a foreground app launch.
6. The additional WidgetKit timeline fallback refreshed the widgets within the expected approximately 30-minute window on real hardware.

The accepted platform boundary remains unchanged: a user force-quit from the app switcher may suppress normal iOS background app execution until the app is launched again. This is not a Flux Sync failure and is not worked around with unsupported background modes.

## Widget refresh policy

The production widget refresh contract is now:

- after a successful widget snapshot write or successful stale-snapshot invalidation, Flux requests a WidgetKit timeline reload through the shared `WidgetTimelineReloader`;
- this reload request is best-effort and its actual execution time remains controlled by WidgetKit;
- every native iOS widget timeline additionally uses a **30-minute `.after(...)` refresh request** as a fallback so an already-written App Group snapshot is eventually re-read even when the immediate reload request is deferred by the system;
- the fallback does not perform Miniflux networking, initialize Core, access SQLite/Keychain, or create a second synchronization path;
- the 30-minute value is an accepted product/architecture baseline, not a guarantee that iOS will execute the extension at an exact 30-minute cadence.

This policy supersedes the older statement in `ARCHITECTURE_DECISIONS.md` section 17 that required only targeted `reloadTimelines(ofKind:)` calls and explicitly prohibited `reloadAllTimelines()` or a delayed/fallback refresh. The current shared implementation and this D5 acceptance record are authoritative for that narrow reload-policy point until section 17 is mechanically reconciled.

## Accepted widget surface

The native iOS widget extension remains a read-only consumer of the shared Apple widget snapshot contract. It does not initialize UniFFI/Core, open Core SQLite, access Miniflux credentials/Keychain, or perform Miniflux networking.

Accepted Home Screen families are `systemSmall`, `systemMedium`, `systemLarge`, and `systemExtraLarge` where supported. Accepted Lock Screen families are `accessoryInline`, `accessoryCircular`, and `accessoryRectangular`. Widget instances use the shared All News, Bookmarks, Category, and Feed scopes and the existing `WidgetAction` routing contract.

The accepted status presentation uses the FluxNews book mark rather than a generic news glyph. The small status widget uses its compact synchronization-date presentation. The rectangular Lock Screen status presentation is the accepted three-line layout: scope, book icon plus count, then the localized unread/bookmarked label. The removed small Headlines presentation is not part of the accepted product surface.

`last_successful_sync_at` remains the single user-facing synchronization timestamp regardless of Sync reason; widgets do not maintain separate Manual/Background timestamps.

## Snapshot consistency

Widget snapshots are refreshed after successful Sync fan-out and after local Read/Unread and Star/Unstar state changes that affect widget projections. Background Sync awaits its required widget snapshot fan-out before reporting BGTask completion. Snapshot write/reload failure remains diagnostic and does not roll back an otherwise successful Core Sync or durable mutation.

Cold-launch widget actions remain buffered until app/Core readiness and then enter the existing app/Core action paths. NativeDev remains isolated from upgrade-test/production App Group and URL-scheme state.

## Validation evidence

Final acceptance includes:

- successful canonical native iOS test execution after the final widget changes;
- successful signed device archive with separate host/widget provisioning and the NativeDev App Group;
- successful real-device local-notification delivery from background Sync;
- successful real-device widget refresh without opening FluxNews;
- successful real-device observation of the 30-minute WidgetKit fallback;
- accepted Home Screen and Lock Screen widget presentation.

No Rust-Core redesign or UIKit Article Timeline architecture change was required for D5 closure.

## Freeze boundary

The following are not open D5 work:

- selecting native iOS `DeliveryMode::Live` for immediate Read/Unread and Star/Unstar Miniflux mutation delivery;
- reviewing the number, side, and assignment of UIKit Timeline swipe actions.

Those items remain D4/U4 interaction/mutation follow-ups in `IOS_D4_FOLLOWUP_FINDINGS.md` and do not prevent D5 closure.