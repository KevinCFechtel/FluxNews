# macOS C3 — Feature-Parity Completion Roadmap

> **Status (17 October 2026): C3.1–C3.7 IMPLEMENTED AND MERGED; C3.8 OWNER-ACCEPTED ON REAL MAC.**
>
> **Current code baseline:** `main` at `2edc6537aebac35260d35f4dcbcab8dcfc7a0ae9`. The original source
> inventory was prepared on `9783d7e790858e79f00cab95b6b1c7b6bff513df`
> (12 October 2026) and is retained below as the historical gap baseline.
> **Goal:** Validate the implemented native macOS feature parity with the accepted
> iOS/iPadOS and Android capabilities without copying mobile UI layouts.
> Source review and green CI do **not** substitute for real-Mac functional acceptance.
>
> **Authority:** ARCHITECTURE_DECISIONS.md, frozen Phase C/D/E contracts,
> MOBILE_PRODUCT_SEMANTICS.md and the current Rust Core. The release/signing
> contract remains RELEASE_DISTRIBUTION.md, and macOS Sandbox readiness remains
> B1 in POST_REPLACEMENT_FOLLOWUP_PLAN.md.

## 1. Product decision and boundaries

- **Functional parity is the default.** Bulk feed settings and both scope-level
  "Mark All as Read" actions are explicitly in scope; they are no longer deferred
  as optional desktop-only product decisions.
- Preserve a **native menu-bar/SwiftUI desktop experience**: commands, keyboard
  shortcuts, context menus, popovers and Settings windows may replace mobile
  gestures and the mobile bottom Action Bar. Feature access and semantics must
  still be equivalent.
- Keep Rust Core/UniFFI authoritative for catalog, query results, unread/read
  state, feed preferences, media downloads, retention and diagnostics; do not
  recreate Miniflux requests or domain persistence in Swift.
- Avoid reopening completed iOS/Android Flutter migration or Phase C audio work.
  The unreleased macOS app starts fresh under its Sandbox; **no old-data migration**.
- Keep functional feature PRs separate from B1 signed Sandbox acceptance and
  from R release/distribution scripting. **B1 is required before Mac App Store
  export, not before implementing C3 features.**
- A similar capability is not considered missing merely because its controls
  are placed differently on desktop. Verify parity in end-to-end user flows.
- Do not silently expand scope to unsupported OS integrations or speculative
  refactors. Track discoveries against this checklist.

## 2. Historical source-verified macOS parity inventory

The evidence column below describes the **pre-C3 implementation baseline**
(12 October), not missing functionality on current `main`. C3.1–C3.7 were
subsequently implemented in PRs #49–#52; their real-Mac behavior is still to
be checked in C3.8. Retain this inventory for the original acceptance contract.

Legend: **Missing UI** = Core/platform primitives available, user control absent;
**Partial** = present but incomplete/different; **Exists** = do not rebuild;
**Verify** = source inspection cannot prove runtime behavior.

| ID | Capability | Current macOS evidence | Target / acceptance |
| --- | --- | --- | --- |
| P01 | Scope-level "Mark All as Read" | BrowserStore already calls Core setReadStateBulk for scrollover; no scope action in the popover More menu | Mark **all unread article IDs in current scope**, not just loaded/visible rows; no navigation; success/failure feedback; refresh counts |
| P02 | "Mark All as Read & Next" | No matching macOS workflow | For Feed/Category only, mark successfully and then move to the next **visible sibling**; no wrap-around; disable at final sibling and in All/Starred/Search/Listening List |
| P03 | Starred/Bookmarks read filter | BrowserStore.query currently forces readFilter=.all for Starred | Both All and Unread filter within Starred (starred filter remains active); consistent counts and switching |
| P04 | Bulk feed settings | Core already exposes feedPreferencesBulk and patchFeedPreferencesBulk; Mac has per-feed FeedSettingsView only | Searchable multi-select list; select visible/all, clear; mixed values; change only explicitly edited fields for selected IDs |
| P05 | Feed/category creation and per-feed preferences | AddFeedView, AddCategoryView and per-feed Settings are already implemented | Regression-check navigation refresh, duplicate handling and single-feed settings; do not rebuild |
| P06 | Downloaded-data overview | macOS Settings lacks the iOS/Android overview | Show file count and storage size from Core; "Delete All Downloads" with confirmation; preserve Listening List and playback progress |
| P07 | Cancel an in-progress audio download | MediaTransferCoordinator.cancel(enclosureID:) exists; ListeningListViews lacks a cancel control | User-visible cancel for pending/active transfers, coherent Core/request state and UI progress; no unintended deletion or automatic restart |
| P08 | Download network policy and retention | Core has downloadNetworkPolicy / downloadRetention; macOS Settings exposes only auto-download / post-playback cleanup | Provide Any/Unmetered and retention choices supported by Core; persist/reconcile safely; test policy changes during transfers |
| P09 | Support diagnostics | CoreDiagnosticLogger currently forwards to OSLog; no macOS viewer/export UI | Bounded, redacted native+Core support records; searchable viewer, severity filter, debug toggle, export, clear confirmation |
| P10 | Privacy-sensitive log handling | NativeLog / CoreDiagnosticLogger use public OSLog interpolation for some diagnostics | No credentials, header values, sensitive paths or raw media URLs in public logs/exports; tests for redaction and clear |
| P11 | HTTP Miniflux account warning | macOS account Settings displays server fields/version but lacks mobile HTTP warning | Explain explicitly that plain HTTP account credentials and feed traffic are unencrypted; do not confuse with Apple's feed-media ATS policy |
| P12 | About and Open Source | Settings has no dedicated About section like iOS/Android | App/build version, repository, Miniflux independence, license/open-source disclosures; native links |
| P13 | Background sync after wake/network return | Periodic 15-minute timer and resume sync exist | Deterministic stale-sync recovery on wake/reachability return, with debouncing, single-flight and disabled-setting semantics |
| P14 | Player skip semantics | PlayerView uses -30 s / +30 s; mobile uses -15 s / +30 s | Align to 15 s back / 30 s forward, including labels, controls and system-media actions as applicable |
| P15 | Desktop action access | Article row has context actions; popover More currently primarily filters/sort/settings/quit | Ensure Mark All, search, Starred, saved/third-party, reader/open original, share and media actions are discoverable; no mandatory mobile action-bar clone |
| P16 | Localization and accessibility | macOS Localizable.xcstrings: 236 keys, 231 with German localization at baseline; mobile has six non-English target languages | Complete/review existing German; prepare Spanish, Galician, Dutch, Tamil and Turkish as Weblate translation targets **without translating them in C3.7**; check resource extraction, fallbacks, labels, plurals, keyboard and VoiceOver |
| P17 | Reader, search, Listening List, chapter UI and sleep timer | Existing macOS views and coordinators cover these | Preserve behavior; test key regressions against mobile semantics rather than reimplementing |
| P18 | Widgets, notifications, shortcuts and configuration backup | Native macOS widgets, notifications, App Intents, backup and restore exist | Smoke/regression acceptance; desktop behavior may differ from iOS |
| P19 | Sandbox and signed release | Host Sandbox work has its own B1 acceptance; Mac App Store export remains on R track | Signed fresh-container acceptance before distribution; **not** a blocker for code-only C3 feature PRs |

### Important semantic details

- **All-read is not "current screen"**: use an independent Core unread query
  for the active scope. The visible list may be sorted, filtered or limited
  differently. Bookmarks must retain the starred filter, even when switching
  its read filter.
- **"Next" refers to navigation order**, including the same visibility policy
  that hides empty feeds/categories where enabled. A failed bulk mutation must
  not change scope; changed account/scope during the operation must not trigger
  navigation to an unrelated item.
- **Bulk feed edits are patches**, not copies of one feed's entire preferences.
  Untouched fields remain unchanged, and mixed values must never be silently
  treated as false/off. Keep per-feed settings independently reachable.
- **Download deletion is not Listening List deletion**. Core persistence for
  entries and playback positions must survive bulk file removal. Cancellation
  must distinguish queued, active, deleting and already-completed transfers.
- **Localization applies to user-facing copy**, while raw diagnostics may stay
  English. Protect sensitive values at logging/export time rather than merely
  hiding them from a viewer.

## 3. Implemented work packages and remaining PR boundaries

C3.1–C3.7 have been delivered via focused, merged PRs. The table below retains
the agreed implementation sequence and acceptance coverage, **not** a list of
features awaiting implementation. C3.8 is the separate real-Mac test/sign-off
phase. B1 signed Sandbox runtime acceptance remains independent of C3.8.

| Order | Work package | Primary code surfaces | Deliverable / merge gate |
| --- | --- | --- | --- |
| C3.0 | Scope/roadmap documentation | This document; post-replacement plan | Approved feature list and shared test/acceptance contracts |
| C3.1 | Scope actions + Starred parity | BrowserStore, PopoverContentView, PopoverNavigationViews, presentation policies | P01–P03/P15: complete-scope bulk mark, optional next and correct Starred filter |
| C3.2 | Bulk feed management | New macOS bulk settings view, SettingsView, BrowserStore; Core bulk APIs | P04/P05: multi-selection, mixed-value editing, safe patching, navigation refresh |
| C3.3 | Downloads and media settings | SettingsView, BrowserStore, MediaTransferCoordinator, ListeningListViews | P06–P08: summaries, delete-all, cancel and network/retention controls |
| C3.4 | Diagnostics + privacy | New diagnostic store/view, NativeLog, CoreDiagnosticLogger, SettingsView | P09/P10: redacted persistent records, viewer/search/export/clear |
| C3.5 | Account/about/player polish | SettingsView, account presentation, PlayerView, remote-control code | P11/P12/P14: HTTP warning, About, 15/30-second skip parity |
| C3.6 | Background recovery | BrowserStore lifecycle, AppDelegate, network monitoring | P13: wake/network reconnect and no duplicate/background-disabled sync |
| C3.7 | Weblate-ready localization and accessibility | macOS string catalog, Weblate handoff and relevant views | P15/P16: German completion, extraction/validation and five untranslated Weblate-ready target locales; keyboard/VoiceOver and small-window checks |
| C3.8 | Functional parity acceptance | macOS tests, Apple CI, real Mac smoke checklist | P01–P18 accepted; documentation updated; B1 tracked separately |

C3.1 and C3.2 can be developed independently, but merge and verify one Apple
change at a time to keep failures attributable. C3.3 precedes signed end-to-end
download/Sandbox checks. C3.4 should precede final support-export review.
C3.5 and C3.6 are independent once baseline Apple CI is green. C3.7 follows
stabilized new UI copy, although keys can be added with each feature.

### Merge and CI evidence (16 October 2026)

| Implemented package | Merged PR | Merge commit | Verification |
| --- | --- | --- | --- |
| C3.1 + C3.2 | [#49](https://github.com/KevinCFechtel/Flux/pull/49) | `d2f80e5` | Feature PR merged |
| C3.3 + C3.5 | [#50](https://github.com/KevinCFechtel/Flux/pull/50) | `e04ef4e` | Feature PR merged |
| C3.4 | [#51](https://github.com/KevinCFechtel/Flux/pull/51) | `2037be2` | Feature PR merged |
| C3.6 + C3.7 | [#52](https://github.com/KevinCFechtel/Flux/pull/52) | `4ec3c1e` | Feature PR merged |
| B1 verifier/install follow-up (separate) | [#53](https://github.com/KevinCFechtel/Flux/pull/53) | `7b02ecd` | [Apple CI #164](https://github.com/KevinCFechtel/Flux/actions/runs/38924332033) green; signed Mac acceptance open |
| Visual Compact hover overlay | [#54](https://github.com/KevinCFechtel/Flux/pull/54) | `2edc653` | [Apple CI #165](https://github.com/KevinCFechtel/Flux/actions/runs/38925707293) green; visual acceptance open |

[Apple CI #167](https://github.com/KevinCFechtel/Flux/actions/runs/38934397341)
passed on the combined `main` commit `2edc6537` (macOS and iOS).
This is automated regression evidence, **not** a signed Mac runtime sign-off.

The following package-specific requirements are preserved as regression and
device-acceptance criteria; they are not instructions to reimplement merged code.

### C3.1 — Scope mutations and navigation

- Establish Core-query policy for each supported scope and a tested "next
  visible sibling" policy based on the current navigation projection.
- Keep mutations off the main actor using existing
  AppleCoreSessionExecutionCoordinator; protect against account/scope changes.
- Maintain undo only if the existing Core/UI semantics support a correct
  full-scope rollback; do not imply the scrollover undo contract applies.
- Tests: 0 unread, 1 unread, many (including offscreen), Starred unread/all,
  last sibling, hidden sibling, failed mutation, changed scope during operation,
  counters and list refresh.

### C3.2 — Multi-feed editing

- Reuse feedPreferencesBulk and patchFeedPreferencesBulk; implement tri-state
  display and a sparse field patch only after explicit user input.
- Search/filter selection should not inadvertently discard selected feeds.
- Tests: partial selection, mixed values, untouched properties, deleted feed,
  failure/retry, empty catalog, multiple change types and sync/reload.

### C3.3 — Download behavior

- Read Core downloadedMediaSummary and requestAllDownloadDeletions via a
  responsive/serialized execution path. Reconcile pending deletion work.
- Wire a user-facing cancel action to the correct Core cancellation semantics,
  not just an in-memory URLSession task cancellation.
- Expose network/retention preference setters through Core, persist them and
  safely update future transfers; a currently playing file must not be removed.
- Tests: queued/active/completed/delete-requested transfer, cancel and retry,
  network-policy switch, retained Listening List/progress, storage summary.

### C3.4 — Supportability

- Match the iOS/Android bounded-retention, severity and debug-toggle contract.
  Export app/OS metadata and native+Core records only after redaction.
- Test export contents and purge, sensitive account/header/path suppression,
  disabled-debug collection and high-volume truncation.

### C3.5/C3.6 — UX and lifecycle

- Expose a clear warning for plain-HTTP Miniflux accounts without restricting
  legitimate HTTP-only podcast/image source URLs through a misleading claim.
- Use 15 s backward / 30 s forward consistently in the player and applicable
  media remote commands, with short accessible labels.
- For wake/network recovery use an idempotent trigger, respect background-sync
  preferences and throttle repeat attempts; preserve manual Sync.
- Tests: policy classification, player seek bounds, repeated wake/online
  callbacks, offline/online while sync is active and disabled background sync.

### C3.6 — Background recovery implementation

- macOS uses an `NWPathMonitor` to observe network availability. The initial
  online callback does **not** trigger a duplicate startup sync; a real
  offline-to-online transition requests recovery.
- `NSWorkspace.didWakeNotification`, application resume, popover close and
  the periodic timer converge on the same `BackgroundRecoveryPolicy` gate.
  Only a configured account with Background Sync enabled and an available
  network may perform unattended sync; a running sync is never duplicated.
- Cooldown: no second automatic attempt within 60 seconds of any sync attempt.
  User-triggered/manual Sync and the separate Sync on Start preference remain
  available when Background Sync is disabled.
- Functional smoke: sleep/wake, offline/online (including launch while
  offline), duplicate callbacks, in-flight sync, disabled Background Sync,
  and manual Sync while background sync is off.

### C3.7 — Weblate preparation, not translation of new languages

**Explicit owner decision (15 October 2026):** Do **not** translate the five
additional languages as part of C3.7. Weblate will supply these translations
later; C3.7 must only prepare a clean, importable and maintainable source.

- Keep **English** as canonical development/source language. Complete and
  review the existing **German** localization, including new macOS UI copy.
- Prepare **Spanish (es), Galician (gl), Dutch (nl), Tamil (ta) and Turkish (tr)**
  as target locales for later translation in Weblate. Do not write manual,
  automatic, pseudo- or English-copied "translations" for these five languages.
  Untranslated entries must remain visibly untranslated to Weblate, with
  normal English fallback behavior in the app.
- Extract all user-visible macOS strings into the `Localizable.xcstrings`
  catalog (including the C3.1–C3.6 surfaces). Use stable source keys,
  translator context where needed, suitable plural/format placeholders,
  and a catalog format and locale configuration compatible with Weblate.
- Document the Weblate import/export/update workflow and CI validation for
  missing/nonlocalized user-visible strings and resource consistency. Make
  target locales discoverable to Weblate without marking unfinished locales as
  complete or selecting them as fully translated application languages.
- Review German text, narrow Settings/Popover layouts, dates/plurals, keyboard
  labels and VoiceOver. Accessibility should be correct before translation;
  long-copy/RTL checks for future Weblate output can follow as translations land.
- **C3.7 done means translation-ready, not translated into seven languages.**
  Completion/review of es/gl/nl/ta/tr is a separate later Weblate milestone and
  must not block the macOS functional-parity merge or C3.8 acceptance.

## 4. Validation and release gates

For every feature PR:

1. Record scope, baseline commit, affected Core contracts and changed UI paths.
2. Add model/presentation tests for behavior and failure/cancellation paths.
3. Run the **macOS** regression target in .github/workflows/apple.yml and keep
   the Rust gate for any Core/UniFFI change. Do not infer tests from static
   inspection; record actual CI URL and conclusion.
4. Confirm ordinary account/Reader/feed navigation, Listening List, media
   playback and widget behavior are not regressed.
5. Update this inventory's status and link the merged PR/acceptance evidence.

For **C3.8 macOS functional acceptance**, test on a Mac:

- Mark-All in All, Category, Feed and Starred, including unread-only and
  switching filter; Mark-All-&-Next at last/non-last visible sibling.
- Bulk updates on mixed feed settings with selection/search and restart.
- Download start/progress/cancel/retry/erase; totals before and after deletion;
  playback and Listening List remain intact.
- Diagnostics privacy, search/filter/export, clear confirmation and disabled
  Debug Logging behavior.
- Plain HTTP warning, About links, media 15/30 jumps, small popover layouts,
  keyboard focus/VoiceOver and German copy.
- Sleep/wake, Wi-Fi/offline/online transitions and no duplicate Sync.
- Widget updates, notifications, Reader, backup/export and app restart.
- Visual Compact hover overlay (Gelesen/Stern/Mehr): right-bottom anchoring on
  article preview, fallback without preview, long/short titles, clicking and
  focus/VoiceOver; verify unchanged row height and other display styles.

**C3.8 sign-off (17 October 2026):** The project owner confirmed successful macOS app testing and expressly approved closing C3.8. This is an owner-reported device acceptance, not an independently captured per-case test log. Final code/CI and merge of PR #61 remain separate gates.

The C3.8 smoke checks may use the same **Apple Development-signed, sandboxed**
installation as B1; record pass/fail evidence for **C3.8 and B1 separately**.

**Separate sign-off:** B1 must verify a signed Sandboxed **fresh install**,
App Group, Keychain, data/download persistence, widget sharing and file-panel
access; it is not satisfied merely by an unsigned dev run. R follows with
correct Mac App Store provisioning and Transporter export. No macOS migration
of unsandboxed local development data is required.

## 5. Completion rule and exclusions

C3 is complete only when the accepted work packages are merged, CI is green,
the real-Mac functional checklist has pass/fail evidence, and any deferred
items are recorded as explicit owner-approved decisions. Code presence or
green compilation alone is not proof of a working experience.

Out of scope by default: identical mobile gesture/toolbar layouts, iOS
CarPlay/Live Activities, Android Auto, a macOS migration from unreleased
development builds, automatic publication and speculative broad refactors.

**Review rule:** Before declaring that *no* features remain, reconcile the
runtime parity checklist against current iOS/Android UI and record newly
discovered gaps here. This document is a controlled baseline, not an
assertion that a source-only comparison proves exhaustive parity.
