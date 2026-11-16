# FluxNews macOS Contract

> **Status: ACTIVE / AUTHORITATIVE**
>
> This document carries forward the durable macOS product/platform contract from
> the completed Phase C and C3 parity work. Historical implementation sequencing
> and acceptance evidence are preserved separately.
>
> Transfer mapping:
> - `PHASE_C_NATIVE_MACOS_AUDIO.md` sections 1–6 → current macOS media,
>   Listening List, playback, downloads, lifecycle and Now Playing rules below.
> - `MACOS_C3_FEATURE_PARITY_ROADMAP.md` product decisions, semantic details and
>   accepted parity rules → current macOS product contract below.
> - `MACOS_SANDBOX_ACCEPTANCE.md` implemented sandbox/App Group boundary and
>   accepted development-build scope → current sandbox boundary below.
> - `PHASE_B8_NATIVE_MEDIA_EXECUTION.md` durable native playback/transfer
>   execution rules → native media execution boundary below.
>
> This transfer does not reopen Phase C, C3.1–C3.8 or B1 acceptance. Mac App
> Store provisioning/archive/export/Transporter validation remains release work,
> not a platform-contract gap.
>
> Shared media/Core semantics remain authoritative in
> [`../../current/MEDIA_CORE.md`](../../current/MEDIA_CORE.md).

## 1. Goal and boundaries

Phase C delivers the complete native macOS audio workflow:

**Discover News → add to Listening List → optionally download → play → resume →
use chapters/show notes → control through macOS → retain or automatically remove
the completed item.**

The Rust Core remains authoritative for durable media/domain state, policies,
playback progress, download intent/state, metadata, chapters, persistence and
Miniflux synchronization.

The native macOS client owns AVPlayer execution, runtime playback state,
runtime transfer progress, sleep timer execution, filesystem transfer work,
SwiftUI presentation, Now Playing and media-key integration.

There is no second durable media-state implementation in Swift, no direct
SQLite/Miniflux media access from Swift, and no playback engine in Rust.

The macOS Phase-C experience is audio-only. Generic Core media support may
remain broader, but video is not surfaced in the menu-bar audio experience.

## 2. C1 — Phase-C contract completion

### 2.1 Article → Enclosures

Expose a small public Core + UniFFI relation query:

`article_enclosures(article_id) -> Vec<Enclosure>`

The article/enclosure relationship already exists in storage. This is a public
contract completion and requires no new media ownership boundary. `ReaderDocument`
remains the article-rendering contract and is not extended with media state.

### 2.2 Listening List domain

The user saves a **News/article**, not an individual enclosure.

Playback and downloads remain enclosure-specific.

The Listening List is therefore News-centered. A conceptual read model is:

```text
ListeningListItem
    article_id
    feed_id
    title
    feed_title
    published_at
    added_at
    remote_present
    audio_enclosures: Vec<ListeningListEnclosure>
    active_enclosure_id?
```

with:

```text
ListeningListEnclosure
    enclosure
    playback_state
    download
    duration_ms?
```

`active_enclosure_id` identifies the last/relevant played enclosure for the
News and lets the client render the News-level progress without per-row
follow-up queries.

The concrete implementation may reuse existing public records where sensible;
it must not duplicate durable playback/download state merely for presentation.

### 2.3 Listening List queries

Expose:

```text
listening_list(feed_id?, sort) -> Vec<ListeningListItem>
listening_list_feeds() -> Vec<ListeningListFeed>
is_in_listening_list(article_id) -> bool
```

Initial sorting:

- `RecentlyAdded` — default.
- `PublicationDate`.

The feed filter exposes only feeds that actually have Listening List items.

The old enclosure-centered Saved Media API may remain temporarily for migration,
but new Phase-C UI uses the News-centered Listening List contract. Old APIs are
deprecated only after callers have migrated.

Listening List membership is durable user state. While a News remains in the
Listening List, normal read-article retention must not delete the News or
cascade away that membership. Explicit Listening List removal and the
remove-completed policy remain the mechanisms that intentionally remove it.

### 2.4 Listening List mutations

Expose News-centered operations:

```text
add_to_listening_list(article_id)
remove_from_listening_list(article_id)
```

Required invariants:

- Starting a manual download implicitly adds the containing News to the
  Listening List if necessary.
- Feed auto-download implicitly adds every qualifying News with audio to the
  Listening List before requesting downloads.
- Removing a News from the Listening List requests deletion of all local audio
  enclosures belonging to that News.
- Physical file deletion remains native execution of Core-owned deletion intent.

Deleting an individual download does **not** remove the News from the Listening
List.

### 2.5 Auto-download policies

There are two triggers for the same normal download path:

1. Per-feed automatic audio download.
2. Global automatic download when a News is added to the Listening List.

Both first establish Listening List membership and then use the existing
enclosure download machinery.

For automatic download, all audio enclosures of a qualifying News are requested.
Interactive/manual download remains enclosure-specific and may ask the user to
select an enclosure when several exist.

### 2.6 Completion policies

Keep two independent user policies:

- **Delete download after playback**
- **Remove completed items from Listening List**

Deleting the download after playback frees local storage while preserving the
News in the Listening List.

Removing a completed News from the Listening List also causes all of its local
audio downloads to be deleted according to the normal Unsave invariant.

For a News with multiple audio enclosures, automatic removal occurs only after
all relevant audio enclosures are completed.

### C1 acceptance

C1 is complete when the native client can render and mutate the Listening List
without direct SQLite access or N+1 media-state stitching, and the invariants
above are covered by Core tests.

## 3. C2 — Native playback experience

### 3.1 Playback presentation state

Build the observable native presentation state on the existing
`MediaPlaybackCoordinator` / AVPlayer execution:

- loaded media;
- playing / paused / stopped;
- current position;
- duration;
- loading/buffering;
- playback rate;
- chapters;
- user-visible error state.

Add native playback-rate support without changing Core playback ownership.

### 3.2 Player navigation

The Player is a dedicated presentation mode inside the existing menu-bar
popover. There is no separate player window and no in-app mini-player.

Reserve a fixed toolbar slot beside Sync:

- List + loaded medium: `waveform`, opens Player.
- Player: `list.bullet`, returns to List.
- No loaded medium: `waveform` remains visible but disabled.

A paused or stopped medium remains loaded, so the Player remains accessible.
Normal navigation to feeds/categories/articles returns to the normal List/content
mode.

### 3.3 Player layout

Fixed upper playback area:

1. Feed.
2. News/episode title.
3. Timeline.
4. Elapsed/total time.
5. Playback controls.
6. Compact media/download actions.

One main scrollable lower area:

7. Chapters.
8. Full Show Notes / article details.
9. Advanced Settings.

No artwork is visibly rendered in the Player. Artwork remains available for
native macOS Now Playing/media-session presentation.

### 3.4 Timeline

Use a native slider with elapsed and total duration. Do not show percentages.

Example:

```text
────────────●─────────────────
28:14                         42:03
```

Unknown duration is shown as `--:--`.

### 3.5 Playback controls

Final control set:

**−30s · Play/Pause · Stop · +30s · Restart**

Semantics:

- **Pause:** pause; medium stays loaded; position is preserved.
- **Stop:** stop playback and checkpoint progress; medium stays loaded.
- **Restart:** reset progress to `0:00`; medium stays loaded.
- If Restart is used while playing, playback continues from `0:00`.
- If Restart is used while paused/stopped, that state is retained.
- Restart requires no confirmation dialog.
- There is no Eject/Unload control.

Selecting another title checkpoints the previous title before loading the new
one.

### 3.6 Chapters

Preserve the established FluxNews behavior using native macOS UI and Core-owned
chapter data:

- approximately four visible chapter rows;
- internal chapter scrolling when needed;
- active chapter highlight;
- active chapter auto-scroll;
- chapter start time;
- selecting a chapter seeks to it;
- selecting while paused starts playback.

Do not duplicate chapter/timestamp parsing in Swift.

### 3.7 Show Notes

The Player is also the detail view for a Listening List News item.

Render the full Show Notes/article using the existing `ReaderDocument` pipeline
so links, headings, lists, images and supported formatting behave consistently
with the normal Reader.

### 3.8 Advanced Settings

One collapsible section after Show Notes:

**Playback speed**

- `0.5×–3.0×`
- `0.1×` steps.

**Sleep timer**

- enabled/disabled;
- interval selection;
- `30–180` minutes in 15-minute steps;
- useful remaining/status presentation.

Sleep timer execution is native runtime state. End-of-chapter/end-of-episode
timer modes are not part of Phase C.

## 4. C3 — News integration and Listening List UX

### 4.1 News actions

For News with audio enclosures, expose the important audio actions visibly:

- Play.
- Add to Listening List.
- Download.

**Add to Listening List must not be hidden in the overflow menu.**

It is distinct from the existing Save/Star article action. News without audio
do not show Listening List/audio actions.

### 4.2 Multiple audio enclosures

Exactly one audio enclosure: perform the requested action directly.

Multiple audio enclosures: show a small native menu anchored to the action.

Use existing data for labels:

- meaningful filename derived from URL when available;
- otherwise `Audio 1`, `Audio 2`, …;
- MIME/format;
- size when known;
- download state where relevant.

Do not add per-enclosure duration calls merely to enrich this selection menu.

Automatic download selects all audio enclosures without presenting a menu.

### 4.3 Switching loaded media

When another title is selected while playback is actively running, ask for
confirmation.

On confirmation:

1. checkpoint current progress;
2. load the selected enclosure;
3. open Player.

On cancellation, preserve the current state.

A merely paused/stopped loaded title does not require this confirmation.

### 4.4 Listening List navigation

Add one sidebar destination:

**Listening List**

There is no separate Downloads destination and no Playlist/queue semantics.

The list is flat rather than permanently grouped by feed.

Controls:

- Feed filter, containing only feeds represented in the list.
- `Recently Added` sorting as default.
- `Publication Date` as the second initial sort.

### 4.5 Listening List rows

One row represents one News regardless of enclosure count.

Show at least:

- Feed.
- News/episode title.
- playback progress bar when meaningful;
- elapsed/total minutes, e.g. `28 / 42 min`;
- compact aggregate download marker.

Do not show a playback percentage.

For News with multiple audio enclosures, progress is based on the most recently
played/relevant enclosure.

The download marker is derived from downloaded audio enclosure count, e.g.
`0/2`, `1/2`, `2/2`; no redundant durable aggregate needs to be stored.

A click on the News loads the relevant audio and opens the Player. The Player
also provides its Show Notes/detail view.

Keep Play and download status/action readily available. Removing from the
Listening List may live in the context menu.

A separate Continue Listening section is not required: progress is directly
visible in the Listening List.

## 5. C4 — Downloads, settings and macOS integration

### 5.1 Native transfer presentation

Extend `MediaTransferCoordinator` presentation/runtime state only as needed to
show active transfers:

- running state;
- received/total bytes when available;
- progress;
- cancel;
- failure/retry.

Runtime byte/progress information remains native and must not be persisted as
Core domain state.

### 5.2 Settings

Expose the relevant media settings, including:

- Automatically download items added to Listening List.
- Remove completed items from Listening List.
- Delete download after playback.
- Download network policy.
- Download retention.
- Per-feed automatic audio download.

The UI must make clear that removing an item from the Listening List also
removes its local downloads.

### 5.3 Feed auto-download

For every qualifying News in a feed with automatic audio download enabled:

1. add News to Listening List;
2. request download of all audio enclosures.

There must be no hidden auto-downloaded News outside the Listening List.

### 5.4 macOS Now Playing

Complete the existing native media-session integration with at least:

- episode title;
- feed;
- duration;
- elapsed position;
- playback state;
- artwork when available.

Complete appropriate `MPRemoteCommandCenter` handling for:

- play;
- pause;
- toggle;
- skip backward 15 seconds;
- skip forward 30 seconds;
- seek/change position.

Validate macOS media keys and Control Center. System Now Playing remains the
OS-level playback surface. The later accepted macOS parity work also adds a
compact in-popover player for direct title/artwork/play-pause access; this does
not create a second playback engine or duplicate media state.

## 6. C5 — Lifecycle, edge cases and acceptance

### 6.1 Lifecycle

Validate:

- popover close/open;
- app inactive/active;
- sleep/wake;
- termination;
- relaunch;
- playback while UI is not visible;
- loaded but paused/stopped media;
- downloads while UI is not visible.

Application deactivation checkpoints playback but must not pause it.

### 6.2 State interactions

Cover at least:

- Add to Listening List without download.
- Manual download ⇒ automatic Listening List membership.
- Feed auto-download ⇒ Listening List + all audio downloads.
- Listening List auto-download.
- Delete download while News remains saved.
- Remove from Listening List ⇒ delete all local audio downloads.
- Completion + delete-download policy.
- Completion + remove-from-Listening-List policy.
- Multiple enclosures.
- Partially downloaded News.
- Partially played News.
- All enclosures completed.
- Restart semantics.
- Switching titles during active playback.
- Transfer failure/retry.
- Missing local file.
- Relaunch/resume of durable playback/download intent.

### 6.3 UX/platform acceptance

Validate:

- accessibility and VoiceOver;
- keyboard navigation;
- localization;
- compact popover sizes;
- long feed/episode titles;
- large Listening Lists;
- many chapters;
- very long Show Notes.


---

## Accepted C3 parity and desktop semantics

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


---

## App Sandbox and App Group boundary

## Implemented in `main` (PR #38 and PR #53)

- Host entitlements: `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-write`, and the existing `group.dev.kevincfechtel.fluxNews` App Group.
- Widget entitlements remain separate and keep their existing sandbox and App Group.
- Internal podcast downloads are now under sandbox-local `Application Support/FluxNews/Media` instead of `~/Movies/FluxNews`. The existing `BrowserStore` persistent/core cache locations resolve under the app container when sandboxed.
- `apple/macos/Build/build-app.sh` now verifies that the signed host has the new entitlements rather than asserting that the host is unsandboxed.
- XCTest checks verify source entitlements and that the derived media path uses Application Support.
- PR [#53](https://github.com/KevinCFechtel/Flux/pull/53) added
  `apple/macos/Build/verify-sandbox.sh`, enforcing signed host/widget versions,
  bundle IDs, App Group/provisioning, Apple Development team and effective signed
  Sandbox/file/network entitlements.
- `build-app.sh` uses Apple Development signing for the real verification path;
  `install-local.sh` validates both source and staged application before
  replacing the local app, without deleting persistent data.
- [Apple CI #164](https://github.com/KevinCFechtel/Flux/actions/runs/38924332033)
  passed for PR #53; combined `main`
  [Apple CI #167](https://github.com/KevinCFechtel/Flux/actions/runs/38934397341)
  also passed. Neither constitutes an on-Mac acceptance run.

## Not implemented

No old data, Keychain, download or account migration. The existing Developer ID/notarization script remains separate from the future Mac App Store export script. No claim of successful App Store provisioning or review is made.


## B1 signed macOS development build acceptance

On a Mac with Apple Development signing and App Groups provisioned for both targets:

```bash
CONFIGURATION=Debug DEVELOPMENT_SIGNING=1 ./apple/macos/Build/build-app.sh
./apple/macos/Build/verify-sandbox.sh ./dist/FluxNews.app development
./apple/macos/Build/install-local.sh
```

The verifier checks actual signatures, host/widget IDs and versions, Sandbox and App Group entitlements, signing team and embedded development provisioning. The installer validates both source and staged copy **before** replacing the application; no app container or Keychain data is deleted. A truly fresh-container test requires a clean macOS user or separately approved manual cleanup. The project owner has explicitly accepted B1 as complete following device testing; the individual fresh-container checks above were not separately documented here. Unsigned CI checks alone do not establish signed Sandbox acceptance. Developer ID and Mac App Store distribution remain separate.


---

## Native media execution boundary

## Playback

`MediaPlaybackCoordinator` uses `AVPlayer` and accepts only Core-owned
`PlaybackPreparation` data. It prefers a validated local media file, falls
back to the Core-resolved remote URL, restores the Core position for in-progress
items, and does not implicitly restart completed items. The AVPlayer runtime
position is updated by a native periodic time observer while playback is
running. Position checkpoints are written on pause, seek, lifecycle
transitions, and a periodic 20-second cadence; the observer does not checkpoint
Core on every callback. Natural completion calls `playback_completed` once and
records the observed duration through Core.

AVPlayer duration can be unavailable during initial preparation. The native
engine observes the current item and reports each newly discovered valid
duration through the existing Core `observe_media_duration` operation. Invalid,
indefinite, zero, and non-finite durations are ignored. Replacing an item
removes its observers and guards queued callbacks against the active item.

Application deactivation checkpoints the active item but does not pause
playback. Explicit pause and real playback/session interruptions remain
playback controls; lifecycle checkpointing is separate from playback control.

The coordinator also publishes duration, chapters, artwork, and Now Playing
metadata to the macOS media session. It does not mark articles read or mutate
playback state outside the Core API.

## Transfers

`MediaTransferCoordinator` consumes Core transfer and deletion work. It uses
`URLSession` for downloads, applies Core's network policy, writes only beneath
the configured media root, and reports finished or failed work back to Core.
Temporary files are moved into deterministic Core-provided destinations only
after a successful transfer. Deletion work is completed only after the local
file is absent. Duplicate active tasks are suppressed and cancellation is
best-effort through URLSession. When Core no longer returns requested work,
the coordinator cancels the matching native task where possible. A late native
completion or failure is still sent through the existing Core callback path;
Core's stale-callback rules decide whether it changes durable state. Native
cancellation is not reported as a transfer failure.

`DeleteRequested` work is reconstructed and processed on reconciliation. A
missing local file is idempotently treated as deleted. Physical deletion is
deferred while the playback coordinator is actively using the enclosure; the
Core deletion intent remains unchanged and is retried on the next
reconciliation after playback stops.

`AnyNetwork` permits expensive and constrained URLSession access. `UnmeteredOnly`
sets `allowsExpensiveNetworkAccess` and `allowsConstrainedNetworkAccess` to
false. This is macOS's closest available approximation; it does not promise a
perfect carrier-metering distinction. Downloads waiting for that constraint
remain Core `Requested` rather than becoming `Failed`.

Successful completion is reported to Core only after the temporary URL has
been safely finalized beneath the media root and its size has been read.
Transport errors map to `Network`; finalization and filesystem errors map to
`Storage`. A rejected Core completion callback is logged as a stale/domain
callback result and is not converted into a second failure callback.

Core durable `Requested` and `DeleteRequested` intent survives process death.
On startup/resume, a fresh coordinator reconstructs execution by querying Core
and restarting valid requested transfers or processing pending deletions. The
current implementation uses foreground URLSession downloads, so an in-flight
foreground task itself is not guaranteed to survive process termination. True
OS-persistent background URLSession execution remains deferred.

Optional Saved Media Sync remains outside this coordinator. Local playback and
transfers do not depend on it.

## Integration And Tests

Both coordinators are application-scoped and configured from the existing
`BrowserStore` Core instance. `MediaCoordinatorTests` covers Core-authoritative
resume, explicit restart, natural completion idempotence, checkpoint behavior,
media-root path containment, duplicate suppression, cancellation and stale
callbacks, relaunch reconstruction, finalization ordering, failure mapping,
deletion idempotence/playback protection, and network policy mapping.

Generated UniFFI bindings remain build artifacts. The macOS test target hosts
the app so it can test app-internal coordinator types.


## Retained C3 Visual Compact hover behavior (completed)

The accepted C3 Visual Compact hover treatment from
[`MACOS_C3_FEATURE_PARITY_ROADMAP.md`](../../archive/phases/macos/MACOS_C3_FEATURE_PARITY_ROADMAP.md)
is a current macOS presentation rule, **not** a new C3.8 acceptance gate:

- Read/Star/More actions appear as a hover overlay anchored to the **lower-right
  of the article preview** rather than changing the row's stable layout.
- Articles without a preview retain a usable action fallback; long or short
  titles must not obscure access to controls.
- **Row height remains unchanged** when hovering or revealing actions, and
  other display styles remain unaffected.
- Clicking, keyboard focus and VoiceOver keep the actions reachable and
  semantically labelled.

C3.8 and B1 remain accepted. This retained UI rule does not reopen a
physical-Mac acceptance checklist.
