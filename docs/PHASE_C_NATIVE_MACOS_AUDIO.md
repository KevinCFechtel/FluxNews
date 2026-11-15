# Phase C — Native macOS Audio Experience

> **Status: COMPLETE / ARCHITECTURE-FROZEN / AUTHORITATIVE PHASE-C CONTRACT**
>
> Phase C is implemented in the native macOS client and is architecture-frozen.
> The completed experience covers the shared Listening List/media domain,
> native playback and transfer execution, chapters/show notes, playback speed,
> Sleep Timer, media settings, Now Playing/remote commands and the associated
> macOS presentation. Phase B remains frozen and playback execution remains
> native rather than moving into Rust.
>
> Historical requirement wording below is retained as the implemented contract,
> not as an open checklist.
>
> Post-completion structural cleanup was merged on 11 October 2026. The large
> `PopoverContentView.swift` and `BrowserStore.swift` implementation surfaces
> were decomposed into focused macOS presentation/support files while preserving
> the existing store, lifecycle, playback, transfer, notification, Settings and
> window behavior. PR #29 passed Apple CI before merge.
>
> Release/distribution scripting is tracked separately in
> [RELEASE_DISTRIBUTION.md](RELEASE_DISTRIBUTION.md). macOS distribution should
> ultimately use the same release interface as iOS, producing a validated
> App Store Connect artifact suitable for Transporter/manual upload while keeping
> App Store distribution as the primary channel.

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
- skip backward 30 seconds;
- skip forward 30 seconds;
- seek/change position.

Validate macOS media keys and Control Center. Native Now Playing intentionally
replaces an in-app mini-player.

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

## 7. Phase C definition of done

Phase C is complete when a macOS user can perform the full native audio workflow
without a parallel Swift media domain:

**Discover News → Add to Listening List → optionally auto/manual download →
open Player → play/seek/restart/change speed → persist and resume progress →
use chapters and linked Show Notes → control playback through macOS →
retain the completed News or automatically remove it according to policy.**

All durable media/domain decisions remain Core-owned. Native macOS code remains
responsible for OS execution and presentation only.