# Flux Architecture Decisions

> **Status: ACTIVE / AUTHORITATIVE TARGET ARCHITECTURE**
>
> This document records explicitly agreed decisions for the shared Flux
> architecture. It describes the target state, not necessarily the
> current implementation. Historical roadmaps and compatibility
> contracts do not override it.

## 1. Target

Flux uses one shared Rust core for business/background responsibilities
and native clients for macOS, iOS, and Android.

macOS remains a native reference client. The completed iOS/iPadOS feature
implementation uses Swift, with a SwiftUI app shell and a UIKit Article Timeline
as specified in section 4.1. Phase E defines the native Android client in
Kotlin/Jetpack Compose. All native clients consume the shared Rust Core through
UniFFI; platform presentation follows the decisions below.

The former Go core is retired. No new work should preserve Go
compatibility or build transitional Go/Rust parity unless explicitly
requested for historical investigation.

UniFFI is the selected binding technology for Swift and Kotlin/native
clients.

The shared Rust implementation is organized as a workspace under
`core/`, with platform-native clients alongside it. Apple clients live under
`apple/macos/` and `apple/ios/`; Phase E adds the native client under
`android/`. The workspace manifest and lockfile belong to that shared-core
workspace rather than the repository root.

### Phase status

**Phase A — Newsreader Completion is complete and architecture-frozen.**
The automated validation baseline at this freeze was 129 passing Rust workspace
tests, 66 passing macOS XCTest cases, and a passing signed macOS Debug build.
These counts record the freeze baseline; they are not permanent architectural
invariants.

Phase A is not an open Flutter-to-native parity checklist. New Newsreader work
extends the decisions in this document and current product requirements;
intentionally dropped Flutter behavior remains dropped unless a new product
decision explicitly reintroduces it. Flutter remains historical behavioral
reference evidence where useful, particularly for Podcast/Media work in later
phases.

## 2. Responsibility boundary

### Rust core

Owns domain models; SQLite/local persistence and durable data state; Miniflux
networking; sync/reconciliation; durable offline mutations; article/feed/category
data; account/server configuration semantics; core settings; article/Reader
content processing; feed-icon acquisition/cache; article-image discovery/cache;
search requests; notification candidate/domain data; widget projection/domain
data; queries; structured errors/events; and the completed shared media domain,
persistence, download policies, playback progress, and media-retention
integration.

### Native clients

Own UI/presentation state and OS integration: navigation, visible/stable list
snapshots, scroll position and geometry, gestures, dialogs, layout/theme,
platform-specific accessibility/presentation behavior, native browser/share
behavior, secure credential storage, native scheduling/background execution and
transfer, system-notification presentation/delivery, WidgetKit/App Intent
presentation and routing, playback engines, and OS media integrations.

Core APIs express domain intent, never UI mechanisms. A swipe, button,
context menu, pull-to-refresh, or scroll gesture is translated by the
native client into a domain operation.

## 3. Queries, snapshots, counts, and events

The UI can query core data at any time. Core changes also emit
structured events, including changes initiated by the UI itself.

Events inform; they do not force presentation refresh. Visible lists and
counts change only when the native UI chooses to query again.

Article queries support at least:

-   scope: all / category / feed
-   read filter
-   starred filter
-   sort: newest first / oldest first
-   pagination (`limit = 0` means all matching items)

Sorting uses publication time only.

Counts are separate point-in-time core queries and respect the same
scope/read/starred filter semantics as article queries, but do not
require sorting or pagination. They can be refreshed independently from
visible article snapshots, for example after Read-on-Scrollover, without
re-querying the visible list.

Navigation catalog metadata and its navigation counts are one shared Core
projection. Native clients choose the navigation count mode (unread or all)
and consume the resulting catalog, global unread/starred totals, and category/
feed counts; they do not derive or incrementally maintain those counts. The
currently selected Timeline/query count remains a separate bounded-query
concern. Scrollover may defer a navigation-projection refresh until the
Timeline is idle, but does not derive counts itself.

The local native iOS Timeline reads Core-owned keyset pages using the
`(published_at, article_id)` cursor. The first page includes the authoritative
full selection total; later pages omit that repeated aggregate and include only
their bounded rows and next cursor. iOS retains pages for its current query and
publishes append and removal deltas without rebuilding unaffected row content or
presentation state. Search retains its separate remote offset-pagination
contract. Hard Timeline windowing/eviction is deferred pending memory profiling.

### Apple synchronous Core execution boundary

The Rust Core and its UniFFI surface remain synchronous. Swift Concurrency owns
the async lifecycle of a request and native presentation coordination, while a
small bounded Apple worker policy owns execution of synchronous Core closures.
The closure itself must execute on dedicated system worker infrastructure, not
on a Swift cooperative-executor thread or `MainActor`.

The policy has separate bounded responsive/local and potentially blocking/remote
lanes. This prevents synchronous network work from head-of-line blocking local
SQLite reads and mutations; it does not attempt to create parallel SQLite access
where the Core Store already serializes it. Rust retains domain, storage,
network, synchronization, and error semantics. Native clients retain request
generation/session ownership and only publish current results.

Cancelling a Swift waiter may prevent queued work from starting, but does not
cancel a synchronous Core operation once it has begun, including in-flight Rust
network I/O. CPU-only detached work such as image decoding and article layout is
outside this boundary. Timeline bounded-query/pagination work remains a separate
concern.

Visible article snapshots remain stable according to the snapshot rules
below, but selected status surfaces may intentionally show live core
counts. In particular, the macOS menu-bar unread count reflects the
current global core unread count after each successful sync even when
the currently presented article/navigation snapshot has not yet adopted
new data. Snapshot-relative navigation counts may remain stable until
the UI intentionally refreshes them.

List queries should return compact article summaries; full content is
requested separately for article detail.

## 4. Stable visible list snapshots

A background core change must not unexpectedly rebuild a list the user
is currently using.

Desktop clients may expose an explicit Sync-on-Start preference. Where such a
preference exists:

1.  load and display local state immediately;
2.  run sync in parallel;
3.  if the user has not scrolled or otherwise meaningfully interacted
    with the list by sync completion, the native UI may automatically
    refresh the snapshot;
4.  after interaction, keep the snapshot stable and signal new data
    through an event/badge until the UI intentionally refreshes.

Mobile clients do **not** expose a separate Sync-on-Start preference. Their
single user-facing Background Sync preference governs scheduled background work
and automatic foreground/resume refresh. When Background Sync is disabled,
mobile app start/resume loads local state without automatic sync; Manual Sync
remains available. When enabled, foreground/resume may perform a stale-data
fallback sync while avoiding duplication with a recent or running background
sync.

Resume follows the same stable-snapshot rule. Data obtained by a background
sync while the app was suspended is signalled, not pushed into the visible
list.

Deep-link/widget/notification launches prioritize the explicit
target/action. Later resumes return to the normal snapshot rules.

A background-only OS launch builds no UI.

After process restoration, native clients should restore prior
presentation state where supported; core changes still do not force a
presentation rebuild.

On foreground → background, flush transient UI work that must become
durable, currently including pending scrollover batches and playback
checkpoints. This transition does not itself force a sync.

### 4.1 iOS/iPadOS UIKit Article Timeline

**Accepted on 2026-09-11; U1-U5 are complete and the UIKit Timeline architecture is frozen.**

The owned UIKit Timeline is the productive baseline. U3 passed real-device
acceptance, the legacy article-image renderer has been removed, and the
productive image path is ImageIO -> UIImageView/Core Animation. Fundamental
changes to the Timeline renderer, cell/layout structure, Scrollover integration,
image-presentation pipeline, preparation, or scheduling require a concrete
reproducible regression case. Later Phase-D feature work must preserve this
frozen architecture and its product semantics.

The unpublished native iOS/iPadOS client replaces the existing Flutter
FluxNews app. For its central Article Timeline, long-term scrolling performance,
predictable layout, and direct control of updates take priority over preserving
the current SwiftUI implementation or minimizing the replacement effort.

The selected target is an owned UIKit view controller containing a plain
`UITableView`, embedded in the SwiftUI shell. Article cells use native UIKit
views and reusable cell instances. Use stable article IDs, a diffable table data
source, deterministic prepared row heights, and native table swipe/context-menu
APIs. The earlier `UICollectionView` baseline was an implementation stage, not
a permanent product requirement; the current table-based Timeline is the accepted
productive architecture.
The production Timeline must not use SwiftUI `List`, `ScrollView`/`LazyVStack`,
or SwiftUI-hosted article cells through `UIHostingConfiguration` or per-cell
`UIHostingController`. SwiftUI remains appropriate for navigation, Settings,
Reader/Search presentation, sheets, and the rest of the app.

This architecture is selected. An exploratory comparison or proof that the
old `List` is the dominant bottleneck is not a prerequisite for implementation.
UIKit is not a measured performance guarantee: correctness tests and focused
real-device performance acceptance remain required for the new implementation.

The UIKit controller owns scroll observation, current resolved cell geometry,
and bounded tracking of currently/recently visible article IDs. Scrollover
work per scroll event depends on that bounded set, not on the complete article
snapshot or the history of visited rows. It must not depend on separately
ordered SwiftUI row/scroll callbacks or cell disappearance alone.

Use stable article IDs for structural snapshots. A status-only read/starred update
must not rebuild the snapshot, reconfigure the complete article cell, change
its height, or remeasure its text/image content. Update the relevant status,
accessibility, and interaction state by ID. Images use prepared, display-sized
data and bounded caching; image completion must be safe under cell reuse.
Explicit manual actions that remove an article under the existing product
rules perform a separate structural update; Scrollover never removes rows.

Accepted mutation work belongs to the account/Core session, independently of
the view and its presentation snapshot. Preserve origin presentation generation
and per-article mutation ordering when enqueuing work. View/scope changes must
not discard accepted writes; obsolete feedback must not modify a newer view or
overwrite a newer explicit Read/Unread/Undo action. Core calls remain off the
main thread. Rust owns durable state and delivery; do not add a Swift database
or another Miniflux client.

The detailed iOS behavior contract is in
[Phase D](PHASE_D_NATIVE_IOS_IPADOS.md#iosipados-article-timeline--uikit).
[UIKit Timeline implementation handoff](IOS_UIKIT_TIMELINE_IMPLEMENTATION.md)
records the rationale, work packages, and acceptance cases. This is a bounded
amendment to the iOS Timeline, not a reopening of frozen Core/macOS architecture
or the Flutter production-data migration contract.

## 5. Mutations and bulk semantics

A mutation is successful for normal offline-first use once it is safely
persisted locally.

Bulk UI actions pass the exact article IDs the user acted on. The core
does not expand a UI-selected set based on newer database contents. The
core deduplicates bulk IDs before processing.

Opening an article always marks it read. Opening an article's comments
URL does **not** mark the article read. Read/unread and starred are
explicit reversible domain states.

Scrollover Undo is native presentation state, not a dedicated core operation.
macOS retains its existing most-recent-batch behavior. iOS/iPadOS retains one
active rolling group of successful mutations, with qualification and expiry as
specified in Phase D. Both use the normal exact-ID bulk unread operation.
There is no multi-batch Undo history in the core. The UIKit Timeline amendment
preserves the existing iOS Undo product rules.

### Delivery policy

-   **Live:** persist locally, then immediately attempt Miniflux
    delivery.
-   **Deferred:** persist locally and deliver on the next normal sync
    opportunity.

If Live delivery fails transiently, the mutation remains safely pending,
delivery temporarily behaves as Deferred, and the UI receives an event.

## 6. Sync

All ordinary triggers use one operation:

`sync(reason)`

Reasons identify the trigger, e.g. Manual, AppStart, Resume, Background,
Periodic, Widget. Native platforms must not implement separate synchronization
algorithms for those reasons. The Core may map a trigger through an explicit,
documented `SyncPlan` policy (for example mobile Background to Delta, or a
repair-due Resume to Full) while retaining one mutation, reconciliation,
cancellation and event contract. Native platforms decide when timer/stale
refreshes occur; these use their proper reason rather than overloading another
trigger.

The normal sync order is:

1.  send pending mutations;
2.  acknowledge successful mutations;
3.  fetch remote data;
4.  reconcile;
5.  run retention cleanup;
6.  update sync state and emit events.

A failure that undermines the whole run (connectivity/timeout, transient
server failure, auth failure, local persistence/integrity failure) may
abort early. Isolated entity/data-processing failures should be
contained where safe.

Background sync is independently configurable from Live/Deferred
mutation delivery and can be disabled completely. Pending mutations remain part
of every real Sync opportunity and are delivered/acknowledged before the Core
chooses the remote reconciliation plan.

The Core has two reconciliation plans behind the existing `sync(reason)`
boundary:

- **Full Sync** is the authoritative structural reconciliation. It refreshes the
  Feed/Category catalog and the complete unread-plus-starred remote snapshot and
  retains the established absent-entry, feed-removal and category-removal
  semantics.
- **Delta Sync** is a lightweight changed-entry reconciliation over Miniflux
  `changed_after`. It updates only returned Entries belonging to already-known
  local Feeds. It does not infer anything from Entries absent from the Delta and
  does not mutate Feed/Category structure.

On mobile, regular `Background` Sync is Delta-only once a valid Delta baseline
exists. A `BGAppRefreshTask` must not escalate into a Full Sync. If no valid
Delta baseline exists, Background records that Full reconciliation is required
and completes without starting the expensive remote Full snapshot. A Delta Entry
whose Feed is unknown locally is skipped while known-Feed work is retained; the
Delta cursor still advances and durable `full_sync_required` state requests a
later Full Sync. This is safe because Full Sync is independent of the Delta
cursor.

A successful Full Sync establishes the next Delta baseline from a remote
changed-entry high-water mark captured before the Full snapshot fetch. Delta
pagination uses a small overlap and a bounded changed-at window so concurrent
remote changes are re-read by a later Delta rather than skipped.

On mobile, the same Background Sync preference also governs automatic
foreground/resume refresh. There is no second mobile Sync-on-Start setting.
Resume requests are evaluated inside the serialized Core Sync boundary: when
Background Sync is disabled they are no-ops; otherwise a fresh successful Sync
suppresses ordinary Resume work. A stale Resume normally uses Delta, but Full
Sync takes precedence when `full_sync_required` is set, no valid Delta
baseline exists, or the last Full Sync is at least 24 hours old. The initial
mobile freshness window is 30 minutes. Native scheduling therefore does not need
a second race-prone Swift freshness state machine.

Background OS execution and Manual Sync share the same app-owned account/Core
session but not the same presentation lifecycle. D4.5 Manual Sync remains
user-owned and user-cancellable. An OS background task may use the same
run-scoped cooperative Core cancellation primitive only to stop already-running
synchronous work when the operating system expires the task; that does not make
background sync user-cancellable.

Once native background Core execution exists, destructive account/Core
operations must quiesce the entire current Core session, not only a UI store:
block new work, request cancellation of cancellable runs where appropriate, and
wait for already-started synchronous Core work to finish before replacing or
destroying the session.

`last_successful_sync_at` remains the one global persisted/queryable
timestamp for the last fully successful Sync, independent of `SyncReason`,
and is the user-facing freshness signal. Delta execution additionally persists
its remote cursor, while `last_full_sync_at` and `full_sync_required` are
Core-owned reconciliation-planning state. They are not separate user-facing
"last sync" values. The reason belongs in events/logs rather than separate
per-reason success timestamps.

Sync completion events contain coarse domain metadata rather than
snapshots or counts. They may include the reason, numbers of new/updated
articles and delivered mutations, `data_changed`, and
`navigation_changed`. Native clients decide which
article/navigation/count queries to refresh.

Sync failure events include compact phase-oriented partial-progress
metadata where useful (for example mutation delivery completed, remote
fetch started/completed, and small processed-item counts). They do not
contain partial snapshots or a complex progress state.

### Rebuild

Local reset recovery is a separate operation:

`rebuild_local_state()`

It is not another `sync(reason)` mode. Rebuild and normal sync should
reuse low-level API/persistence primitives where sensible but keep
separate orchestration.

## 7. Retry and error model

Errors are classified by retry semantics rather than exposing raw HTTP
behavior as product logic.

Automatically retryable/backoff candidates include connectivity
failures, timeouts, DNS/connection failures, transient 5xx responses,
and 429 (respect `Retry-After` where available).

401/403, invalid configuration/requests, and local persistence/storage
failures are not automatic retry loops and must be surfaced structurally
to the UI.

404/stale entities and conflicts are reconciled according to domain
semantics.

Data-processing failures should be isolated where possible; one bad
image or metadata record should not unnecessarily fail an entire sync.

Runtime health distinguishes at least Healthy, ConnectivityDegraded, and
ServerDegraded and is publicly queryable through the core/UniFFI
boundary, including `next_retry_at` where relevant. It is observable
state, not a UI-controlled retry mechanism.

Backoff is runtime-only and may use failure count plus `next_retry_at`;
it need not survive process restart. Manual sync overrides backoff and
forces a new attempt.

## 8. Miniflux account and credentials

One Miniflux account per installation is sufficient.

The native secure store permanently owns the API key/secret. It is
injected once into core runtime state during initialization, never
persisted in the core database, and never logged.

Custom HTTP headers are account/transport configuration, not Core settings.
They are stored by the native secure credential layer, never in Core SQLite or
UserDefaults, and their values never appear in logs or diagnostics. They apply
to Miniflux/server requests but are never forwarded to arbitrary external
article-image hosts. `Authorization` is allowed for reverse-proxy
authentication; `X-Auth-Token` and protected transport/framing headers may not
be overridden.

Non-sensitive connection configuration such as the Miniflux base URL may
be persisted by the core.

The configured Miniflux URL represents the installation base, not an API
URL. A legacy final `/v1` path component is normalized away while an
installation subpath is preserved. The Rust Miniflux adapter owns API
version routing (`/v1`), and Core owns Miniflux Web UI route construction;
native shells must not construct Miniflux API or Web routes. Configuration
URLs reject query strings and fragments because they do not identify a
stable installation base. Candidate credentials are validated without
committing account configuration through an authenticated `GET /v1/version`.
Successful validation returns the canonical installation base and the server
version. That version is runtime metadata, not authoritative persisted
configuration. Credential persistence remains a platform concern; macOS
validates a candidate before committing credentials or configuration, and a
failed validation preserves the working account.

Changing the Miniflux base URL creates a new server context.
Server-bound synchronized data and feed/category preferences are not
carried into that new context. Changing only the API key while keeping
the same base URL retains the existing local server context and
feed/category preferences; the long-lived core is recreated with the new
runtime credential.

Miniflux is authoritative for the synchronized feed/category catalog.
When a feed is absent from a complete authoritative remote catalog, Flux
removes the local feed and its articles and feed-bound preferences. Feed
deletion is reconciled before category deletion. If the same feed ID
later reappears, its feed preferences start from their defaults.
Categories absent from the complete remote catalog are removed after
stale feeds; empty categories that still exist remotely remain.

## 9. Article data, previews, and Reader content

Persist a flexible Miniflux-aligned article model. The original Miniflux
HTML content is the durable local source of truth for full article
content.

List presentation uses separately persisted, regenerable derivatives:

-   cleaned text-only `preview_text`;
-   discovered preview `image_url`.

The preview has a fixed Core maximum of **600 characters**. This is a
technical processing limit, not a user setting. Native clients control
only the number of visible preview lines. The agreed choices are **2
(Compact), 3 (Standard), and 5 (Extended)** lines, with **3 lines as the
default**.

### Semantic Reader document

The full Reader does not persist a second Markdown/full-content shadow
representation. When a Reader document is requested, the Rust Core
parses the stored HTML and builds a semantic internal `ArticleDocument`.
That document is then projected according to Reader/feed settings into a
public `ReaderDocument` returned through UniFFI.

The initial semantic model supports at least:

-   Paragraph;
-   Heading;
-   Image, including optional alt text and an optional surrounding link;
-   List, including ordered/unordered and nested content;
-   Quote;
-   CodeBlock;
-   HorizontalRule;
-   ExternalContent fallback.

Textual blocks support inline semantics for plain text, bold, italic,
inline code, and links.

Semantics belong to the Core; typography, spacing, colors, and other
visual styling belong to the native client. Unknown container elements
are processed recursively so useful descendant content survives.
Non-content elements such as scripts, styles, empty wrappers, and
tracking content are discarded.

V1 intentionally does **not** attempt browser-equivalent HTML/CSS
rendering. Complex tables are flattened into readable semantic content
while preserving useful text and links rather than reproducing their
layout. Unsupported embeds may become `ExternalContent` links. Native
tables, embedded WebViews, native video/audio embeds, syntax
highlighting, complex CSS layout, and image lightboxes are not required
for V1.

If relevant content had to be simplified, `ReaderDocument` exposes this
fact (for example `has_simplified_content`). Native clients show only a
decent secondary note such as "Some content was simplified · Open
Original"; ordinary ignored wrappers/styles/tracking must not trigger
that notice.

### Rendered and Text Only

Reader mode is a per-feed Core preference:

-   **Rendered** --- default; preserves supported semantic formatting,
    links, and images for native rendering.
-   **Text Only** --- projects the same parsed document into a
    text-focused representation. Images are omitted; visible link text
    remains. Image alt text is not automatically inserted into the
    reading flow.

Both modes derive from the same semantic parsing pipeline rather than
separate HTML processors.

### Detail truncation

Detail truncation is non-destructive. Complete original HTML remains
stored.

A global Core setting stores the actual character limit. User-facing
choices are **5,000 / 10,000 / 20,000 characters**, with **10,000 as the
default**. The limit applies only to feeds whose per-feed **Truncate
Detail** preference is enabled; there is no separate Unlimited choice
and no free-form numeric input.

Truncation is applied after semantic parsing and the Rendered/Text Only
projection. The limit counts displayed text, not images. Natural block
boundaries are preferred; an unusually large individual block may be cut
at a sensible word/sentence boundary rather than allowing an unbounded
overshoot. Images before the resulting cut remain; content after it does
not.

`ReaderDocument` exposes whether truncation actually occurred (for
example `was_truncated`). Native clients show a subtle end-of-content
note with an Open Original action. If content was both truncated and
simplified, the UI combines those states into one unobtrusive notice
rather than stacking warnings.

### Reader persistence and caching

`ArticleDocument` and `ReaderDocument` are generated on demand from the
stored original HTML and are **not persisted in SQLite**. Parser
improvements therefore apply automatically the next time an existing
article is opened and do not require a Reader-document data migration.

A regenerable in-memory cache may be added later if measurement shows a
need, but persistent Reader-document caching is not part of the data
model.

## 10. Retention and local article set

Retention is time-based (intended user choices include 30/60/90/180/365
days) and applies only to **read** articles.

Unread articles are retained regardless of age.

Independent retention protections include:

-   starred;
-   active download (Phase B);
-   existing download (Phase B).

Removing one protection does not negate another.

Retention cleanup runs only during a normal sync. A very old unread
article may therefore remain locally until a later sync after it is
marked read.

Initial/rebuilt local state includes at least:

-   all unread articles;
-   read articles inside retention;
-   all starred articles;
-   articles required by active/existing downloads when Phase B media state
    exists.

## 11. Search

Search initially remains Miniflux online full-text search without
additional Flux filtering or local FTS.

Remote search results may be displayed without automatic persistence. A
remote result becomes durable local data when the user stars it or
starts a download.

## 12. Feeds, categories, navigation, and feed preferences

Navigation is category → feed. The core maintains/query-exposes the
complete category/feed catalog independently of whether entries
currently have matching articles. Categories need ID/name/count. Feeds
need ID/category/name/icon/count for normal navigation; URL/error state
need not be part of that navigation DTO.

FluxNews supports a presentation option for showing empty
feeds/categories. It defaults to enabled. When disabled, "empty" is
relative to the currently active article filters: a feed/category whose
relevant filtered count is `0` is hidden even if it would contain
articles under another filter. The underlying catalog entry and
preferences remain intact.

The core owns feed-icon acquisition, cache/processing, and suitable
light/dark variants for transparent low-contrast icons. Native UI
requests and renders the appropriate variant.

Adaptive feed icons: If a feed-provided SVG contains author-defined
light/dark appearance variants, Flux should prefer and render those
variants for the corresponding appearance. Automatic contrast correction
is only a fallback when the source icon does not provide a suitable
adaptive appearance. This behavior is automatic and has no user-facing
setting.

Article image discovery/download/disk cache belongs to the core; native
UI triggers lazy loading, decodes/renders images, and may maintain a
memory cache. Background sync does not preload article images.

Feed-domain preferences are represented as one typed per-feed preference
model rather than separate preference tables for every feature. The
current intended `FeedPreferences` include:

-   System Notifications enabled/disabled (default off);
-   Detail Rendering: Rendered / Text Only (default Rendered);
-   Truncate Detail enabled/disabled (default off);
-   Open in Miniflux enabled/disabled (default off).

The persistence model should use typed columns/constraints rather than a
generic feed key/value table. Notification delivery/candidate state
remains separate operational state and is not part of `FeedPreferences`.
Public mutation APIs may remain field-specific so updating one control
cannot accidentally overwrite another preference from a stale snapshot.

FeedPreferences are user configuration keyed solely by Miniflux feed ID,
not relationally owned by a locally cached `feeds` row. The
`feed_preferences.feed_id` storage key intentionally has no foreign key or
cascade to `feeds`, so temporary orphan preferences are valid. Normal remote
reconciliation explicitly removes preferences only for feeds confirmed absent
from Miniflux; Rebuild Local State will preserve them, while account/server
replacement and Full Reset will remove them. There is no feed URL or title
matching. This schema ownership correction is required by the agreed Rebuild
semantics.

Feed/category core preferences are device-local and are not
automatically synchronized across devices. Device backup and explicit
config export/import are separate mechanisms.

Flux may add user-defined feeds. The native UI gathers
URL/category/options; the core performs Miniflux communication. Feed
discovery is delegated entirely to Miniflux. General feed/category
edit/delete remains in the Miniflux web UI for now.

Curated/suggested feed onboarding from the legacy Flutter client is retired product behavior. Flux clients do not maintain or ship a repository-curated feed list; feed creation/discovery stays with the existing Miniflux/native feed-management flow.

Miniflux Save/third-party integration is a core-wrapped Miniflux API
operation, not a duplicated service implementation.

## 13. Storage and settings

The native platform supplies semantic storage roots to the core, at
least:

-   persistent data;
-   regenerable cache;
-   media.

The core does not guess OS sandbox paths and owns organization/lifecycle
inside the supplied roots.

Core-domain settings are persisted by the core. Pure presentation
preferences remain native. Secrets remain in native secure storage.
Technical ownership must not dictate the eventual Settings UI grouping;
native Settings screens should group options by user-facing concepts
rather than by Core/Native/Secure-Store implementation boundaries.

The shared Core settings foundation contains:

-   read-article retention with intended choices 30/60/90/180/365 days;
-   mutation delivery mode: Live / Deferred;
-   background sync enabled / disabled;
-   global Reader detail character limit: 5,000 / 10,000 / 20,000,
    default 10,000.

Additional domain settings are added only with the feature that needs
them rather than being modeled speculatively. Later examples include
notification configuration, media rules, and feed-specific domain
preferences.

Native presentation/OS preferences remain platform-local. Current
examples include Sync on Start, Mark as Read on Scrollover, global
shortcut, Launch at Login, Startup Scope, presentation filters, Hide Empty
Feeds/Categories, Remove Article from List When Marked Read, Preview Lines,
and Click on News. System Notifications remain a separate native settings area,
not part of normal Feed Settings.

On macOS, Preview Lines offers 2 (Compact), 3 (Standard), and 5
(Extended), default 3. `Click on News` offers **Open Link** (default) or
**Open Detail View**. Mobile may later define additional native
interaction modes without changing the Core contract.

On macOS, Feed Settings are reached from a context menu on an individual
feed. `Preview Lines` is presentation state only and does not affect
Reader content processing. Per-feed `Open in Miniflux` changes the normal
Open destination between the publisher URL and the Miniflux entry URL;
explicit Open Original and Open in Miniflux actions remain available.

Appearance follows the native platform without a Flux Light/Dark/System
setting; iOS Liquid Glass behavior is likewise platform-owned without a
Flux setting. The legacy OLED/True-Black toggle is also retired: Apple clients
use system semantic colors, materials and native Dark Mode so OLED-capable
hardware receives the platform-appropriate darkest presentation without a
Flux-specific option.

Feed icons are always shown where the product design calls for them.
Automatic icon contrast handling is implementation behavior, not a user
preference, and there is no per-feed icon-contrast override. Feed icons are
regenerable cache; there is no user-facing "delete feed icons only" control.

Article-image cache age is not a user preference. Native clients own bounded
decoded-image caching, normal platform HTTP caching, memory-pressure handling
and eviction/tuning. The legacy user-selectable image-cache duration is retired.

The following FluxNews legacy concepts are intentionally not carried
into the shared Flux settings model: fixed stored-article/starred
limits, configurable sync/search result-count limits, legacy read-sync
day windows superseded by retention, preview character-truncation
controls, legacy HTML/truncation workarounds, the per-feed
`preferParagraph` and `preferAttachmentImage` presentation preferences, the
legacy `showHeadlineOnTop` layout toggle, and Flutter/mobile-specific
AppBar/FAB/Glass interaction settings. Tap/long-press customization is not part
of the current shared settings target and may only be reconsidered later as
platform-native presentation behavior. iOS swipe customization remains a
platform-native setting over semantic actions.

Secrets and potentially secret-bearing configuration never enter
ordinary core settings persistence. The Miniflux API key and custom HTTP
headers are stored in the native secure store (Keychain/Keystore or
platform equivalent), injected into runtime behavior as needed, and
never logged.

Regenerable icons/images are cache. Downloaded media is separate and
should normally not be included in device backup; durable metadata
remains persistent.

## 14. Config export/import and local reset

Flux Config Backup is a versioned, platform-specific configuration backup,
not a cross-platform interchange format. Its format version is independent
of the SQLite schema, application version, and Miniflux version. A backup
contains complete configurable state for its originating platform, including
the canonical Miniflux installation base, credentials, CoreSettings,
FeedPreferences, and a versioned native-platform settings payload.

Backups are always password-encrypted; Flux neither stores nor recovers the
password. V1 derives an encryption key with Argon2id (64 MiB, three passes,
one lane) and uses AES-256-GCM authenticated encryption. Only the format,
platform, and crypto/KDF metadata remain cleartext; credentials and all
settings remain encrypted.

FeedPreferences use Miniflux feed ID only. There is no URL/title matching.
Imports intentionally accept orphan feed IDs without server lookup; normal
later reconciliation removes preferences for feeds absent from the
authoritative catalog. Synchronized articles, cache/media, pending mutations,
notification/runtime state, and presentation state are excluded.

Backup parsing validates and returns a restore model without mutating core or
native state. The Core parser is authoritative for import validity. macOS
decodes its explicit `MacOSBackupSettingsV1` payload only to safely apply native
settings; it does not reinterpret Core data. Import does not validate candidate
credentials, call `/v1/version`, or otherwise require Miniflux connectivity.
A valid backup replaces the account association, credentials, CoreSettings,
FeedPreferences, and native configuration; it clears synchronized state and
then attempts a normal sync. A failed follow-up sync does not roll back a
successful import. Native settings remain owned by their platform even while
carried in that platform's backup.

On macOS, the v1 native payload explicitly includes Mark Read on Scrollover,
Sync on Start, article list style, Preview Lines, Click on News, Global
Shortcut, and Launch at Login. It excludes navigation/Spotlight caches, Reader
window geometry, AppKit window restoration, and other transient presentation
state. Rebuild preserves configured account, credentials, CoreSettings,
FeedPreferences, and native settings while clearing synchronized state and
pending mutations. Full Reset is local-only: it resets Core state, removes the
Keychain credential, unregisters Launch at Login, resets explicit native
settings, and returns FluxNews to fresh-install semantics.

Manual Account save remains intentionally different from backup restore:
manual edits validate credentials with `GET /v1/version` before commit; backup
restore never performs that validation.

`rebuild_local_state()` clears reconstructable synchronized article state,
ordinary read/star pending mutations, notification bookkeeping, sync metadata,
and regenerable Core caches, then immediately performs a fresh Miniflux sync.
It preserves the canonical account association, CoreSettings, FeedPreferences,
native settings, platform credentials, and the minimal local Article -> Feed ->
Category graph required by Phase-B protecting media state. Protecting media
state is Phase-C `ListeningList` membership, Phase-B `SavedMedia`,
`MediaDownload = Requested`/`Downloaded`, `PlaybackState = InProgress`,
or a pending MediaProgressMutation. Pending
media progression remains part of that durable media state; discarded ordinary
read/star intent falls back to the last observed remote article state before
the rebuild sync. Failed/DeleteRequested downloads, Completed-only playback,
AutoDownloadSuppression, and otherwise reconstructable articles do not gain
rebuild protection. If the immediate sync fails, reconstructable discarded
state is not restored. Schema-v7 orphan preferences make FeedPreferences
preservation possible; normal authoritative reconciliation still removes
preferences and feed/article state for feeds absent from the complete remote
catalog. Cache cleanup is best-effort after the authoritative database clear:
a cleanup failure is diagnostic only and never restores discarded synchronized
state.

`reset_core_state()` restores Core-owned database state to fresh-install
semantics: synchronized data, CoreSettings customizations, FeedPreferences,
base-url association, sync metadata, and Core media rows are removed or reset.
It does not contact Miniflux and does not manipulate Keychain, UserDefaults,
native OS registrations, or perform account-removal filesystem orchestration.
Account removal uses the separate account-state path, which also clears the
Core media root.

Account/server replacement, Rebuild, and Full Reset intentionally have
different FeedPreferences policies: account replacement and Full Reset remove
them; Rebuild preserves them. Backup Import remains a separate future
transactional configuration-replace operation.

## 15. Phase B — Shared Podcast / Media Core

Phase B is the next development phase. It extends the shared Rust architecture
without reopening Phase A Newsreader scope. The dependency guide is:

```text
Enclosures
    |
Podcast / Episode Domain
    |
Download State
    |
Download Policies
    |
Playback Position / Checkpoints
    |
Miniflux Progress Sync
    |
Retention Integration
```

Phase B will give the Rust Core ownership of enclosure/media and
podcast/episode domains, durable download metadata/state, download policies,
playback progress/checkpoints, Miniflux progress synchronization, and
media-related retention integration. It will not move platform playback or
transfer mechanisms into the Core.

Native clients will continue to own audio playback engines, AVAudioSession or
platform equivalents, Now Playing/MediaSession, headset/media controls, native
background transfer execution, CarPlay, Android Auto, and other OS-specific
media presentation/integration. Native transfer reports results to the Core;
the Core owns durable state and any downloaded-file metadata analysis.

## 16. Notifications

Flux distinguishes **System Notifications** from **In-App New Data**.
They have different lifecycles and acknowledgement semantics and must
not clear each other implicitly.

### System Notifications

System Notifications are OS-facing notifications and are off by default.
They are configurable **per feed**, not per category, under the native
Settings area "System Notifications".

For each enabled feed, an eligible background/automatic sync produces at
most one aggregated System Notification for that feed when the sync has
discovered articles that have not previously been successfully handed
off as System Notifications. Flux does not create one OS notification
per article.

The core durably tracks which discovered articles have already been
system-notified so later sync runs do not notify them again. If a later
sync discovers additional not-yet-notified articles for the same feed, a
new aggregated notification may be produced for that new set.

The core produces typed System Notification candidates. The native
client performs the actual OS notification handoff and acknowledges the
candidate only after successful handoff. System-notification delivery
state is therefore independent from whether the corresponding articles
have been adopted into an in-app visible snapshot.

The design does not require Firebase/FCM or a custom push service.

### In-App New Data

In-App New Data represents articles discovered by background/automatic
sync while the current UI snapshot is intentionally kept stable. It is
not controlled by the System Notifications feed settings and does not
require OS notification permission.

The UI tracks pending newly discovered article counts per feed relative
to the currently adopted presentation snapshots. These counts accumulate
across multiple background syncs until the relevant new data is adopted.
For example, if one sync adds three articles to a feed and a later sync
adds two more before the UI refreshes that scope, the feed's pending
New-Data badge shows five.

On macOS, affected feeds use the platform-native navigation badge to
show the pending New-Data count. The badge should use native system
styling; Flux does not require a custom badge color.

The macOS menu-bar item exposes two distinct signals:

-   the existing numeric title shows the **current global unread count
    from the core** and is refreshed after every successful sync, even
    when the visible article snapshot remains unchanged;
-   a small notification dot on the FluxNews status-item icon indicates
    that at least one feed still has pending In-App New Data that has
    not yet been adopted into the relevant UI snapshot.

The dot is an aggregate signal only; the per-feed native badges provide
the detailed counts. The dot remains visible across multiple background
syncs and disappears only when no pending per-feed In-App New Data
remains.

In-App New Data is acknowledged by **snapshot adoption**, not merely by
opening the sidebar or selecting a navigation entry. When a newly
queried snapshot is intentionally or policy-permittedly adopted,
acknowledgement follows that snapshot's scope:

-   adopting **All News** clears all pending per-feed In-App New Data;
-   adopting a **Category** clears pending In-App New Data for feeds in
    that category;
-   adopting a **Feed** clears pending In-App New Data only for that
    feed.

The same rule applies when the existing New Data/Refresh action adopts a
new snapshot. A feed does not need to be individually opened if a
broader adopted snapshot already includes its new articles.

System Notification acknowledgement and In-App New Data acknowledgement
are separate. Successfully handing an OS notification to the system does
not clear an in-app badge or menu-bar dot, and adopting a UI snapshot
does not mark an article as system-notified.

## 17. Widgets

Each native widget instance owns its own presentation/configuration
state.

WidgetKit and equivalent platform extensions are native/platform-owned. They
never open the production Core SQLite database, initialize UniFFI/Core, call
Miniflux, access credentials, or use Keychain/application-internal storage.
The native app projects a versioned, credential-free App Group read model from
Core data; the extension reads only that model and App Group icon files.

The initial contract is `WidgetSnapshotV1`, stored as atomically replaced JSON
in the existing FluxNews App Group `group.dev.kevincfechtel.fluxNews`. Its
schema version is independent of backup, database, and UniFFI versions.
Missing, corrupt, or unsupported snapshots are safe explicit extension states,
as are no account, configured-but-never-successfully-synced, and valid-empty
states. Snapshot creation time is distinct from Core's optional global
`last_successful_sync_at`; only the latter is presented as a synchronization
time.

The snapshot contains the complete compact feed/category catalog (stable IDs,
titles, and feed category IDs) for per-widget AppIntent/AppEntity
configuration. Widget article data remains a bounded App Group projection rather
than a serialized copy of the local article store. The original D5
`WidgetSnapshotV1` uses up to 12 newest unread articles per feed plus up to 48
newest starred articles globally, deduplicated by article ID and ordered
newest-first.

D9 adds per-widget Unread/All and Newest/Oldest configuration. If V1 cannot
correctly satisfy those combinations for every supported widget capacity, the
native app must write a versioned backward-safe snapshot extension containing a
bounded candidate set sufficient for both read filters and both sort directions.
The extension still performs no Core, SQLite, Miniflux, credential or network
access. Feed icons remain normalized Core PNGs copied by the native app into
bounded App Group files; absent files use a native fallback.

Core supplies authoritative counts separately from that bounded cache: global
unread, global starred, per-feed unread, and per-category unread. Therefore a
widget can compare its locally available matching articles with the
authoritative count. Cache exhaustion with a larger authoritative count leads
to a future native "More News in FluxNews" action, not a large-unread warning.

Headlines instance scopes are All News, Category ID, Feed ID, and Bookmarks.
D9 adds a per-instance **Unread / All** read filter and **Newest First / Oldest
First** sort order. The read filter applies inside the configured scope; for
Bookmarks, All means all retained starred articles and Unread means unread
starred articles.

Article snapshots retain Article ID so a tap enters the normal FluxNews
article-open path, including the per-feed Open in Miniflux behavior; widgets do
not choose their own destination. There is no widget-specific Open in Miniflux
or translucent-background preference.

The native app invalidates the App Group snapshot and icon cache before account
replacement, configuration import, rebuild, and full reset so discarded
account data cannot remain visible. Snapshot write failures are diagnostic and
never roll back a successful Core sync or mutation.

macOS provides separate, read-only Headlines and Compact Status WidgetKit kinds.
Both use per-instance AppIntent configuration with All News as the default and
stable Feed/Category AppEntity IDs sourced only from the App Group catalog. A
missing configured feed or category remains visibly unavailable rather than
falling back to All News. Headlines render the bounded cache; Compact Status
renders the authoritative configured-scope count and optional
`last_successful_sync_at`.

Headlines is a bounded configured-order article view, not a pageable article
list. Its WidgetFamily layout determines the capacity: one article in
`systemSmall`, three in `systemMedium`, seven in `systemLarge`, and twelve
in `systemExtraLarge`. It renders matching articles up to that capacity using
the configured read filter and sort order, without an overflow row. Pagination
remains outside the initial contract; the bounded snapshot rather than the
extension owns the candidate-data limit.

Widget article links carry only an article ID and are handled by the main app
through the same normal article-open route as a list click. Compact Status opens
its configured scope, using stable IDs and retaining unavailable selections as
unavailable. Widget Sync activates the app, which performs the normal Core
`SyncReason::Widget` synchronization. The extension remains Core, database,
Miniflux, credential, and Keychain-free.

After a successful snapshot write or successful stale-snapshot invalidation,
the app reloads the two stable kinds, `FluxNewsHeadlinesWidget` and
`FluxNewsCompactStatusWidget`, with targeted `reloadTimelines(ofKind:)` calls.
There is no delayed reload workaround or `reloadAllTimelines()` call. Incoming
widget URLs are parsed once and retained until app/Core configuration is ready,
so cold and warm launches do not duplicate or drop actions.

Supported data scopes include All, Starred, Category, and Feed. Widget
queries support pagination; `limit = 0` allows the complete matching
list where the platform can display it.

Widgets call the same standardized core operations and may trigger
`sync(reason = Widget)`. If direct mutation/sync execution is unsuitable
on a platform, the widget may open the main app with the required intent
and let the normal app/core path execute it.

## 18. Opening, Reader navigation, and sharing articles

The normal **Open** action is distinct from the Flux Reader.

By default, Open targets the publisher/original article URL. A per-feed
**Open in Miniflux** preference replaces that normal Open destination
with the corresponding Miniflux web entry for that feed. It changes only
the Open action; it does not disable the Flux Reader. Native code
performs the actual URL/deep-link/browser opening.

Native clients may expose explicit **Open Original** and **Open in
Miniflux** actions independently of the configured normal Open
destination. Open in Miniflux may be placed less prominently, such as in
an overflow/submenu.

### macOS Detail Preview navigation

macOS has one reusable native Detail Preview Panel. It is an interactive,
resizable Quick Look-style NSPanel used for temporary article inspection,
not a persistent Reader document window. It moves to the active Space when
shown and is not tied to the lifetime of the menu-bar popover.

The native `Click on News` preference determines the normal row-click
behavior:

-   **Open Link** (default) → perform the feed's normal Open action;
-   **Open Detail View** → open the article in the Flux Detail Preview Panel.

macOS does not require the mobile split-click mode where image and text
perform different actions; that remains a possible mobile-specific
interaction decision.

Pressing **Space** for the selected article always opens that article in
the Flux Detail Preview Panel, independent of `Click on News` and
independent of the feed's Open in Miniflux preference. If the panel is
already showing that article, Space hides it; Space on another article
reuses the panel with replacement content. An explicit **Open Detail View**
article action shows or reuses the panel without toggling it.

Only one Detail Preview Panel exists. If it is already open, opening
another article replaces its current article and brings the existing panel
forward rather than creating another preview.

Opening an article in the Detail Preview marks it read. The preview uses the
feed's Rendered/Text Only and Truncate Detail preferences. It does not
provide an image lightbox/zoom feature; users can open the original site
when they need the publisher's full media experience.

The Reader and menu-bar UI use the same Core article state and mutation
operations; the Reader does not own a second read/star state. Background
sync must not replace the article currently shown in the Reader.

When opening a publisher link, native code first tries an appropriate
installed app/deep-link association. If unavailable and supported by the
platform, a native user preference chooses in-app browser or
external/default browser. Widgets follow the same opening policy.

App Intents, Spotlight, and equivalent OS integrations are native
responsibilities. The core exposes stable feed/category IDs, titles, and
relationships through the navigation catalog; native clients project
those domain records into platform-specific entities/indexes.

An optional `comments_url` is part of the public article data contract.
Native clients offer an Open Comments action only when it is present and
perform the actual browser/deep-link opening. Opening comments does not
mark the article read.

Sharing is entirely native; the core supplies article data such as
title/URL.

## 19. Localization

All user-facing localization is native and managed through Weblate
across platforms.

The macOS Phase-A baseline is English and German. Application-owned user-facing
Swift strings use localization-aware APIs such as `LocalizedStringResource`,
`String(localized:)`, or SwiftUI localization mechanisms as appropriate.
Runtime/user/server content is data, not a localization key.

The core emits stable structured error/event codes and English technical
diagnostic messages, not localized UI strings.

## 20. Logging and diagnostics

Normal structured logs have limited detail and bounded local retention. An
explicit Debug Logging mode may collect additional Debug/Trace detail; ordinary
Info/Warning/Error support records remain available without enabling it.

Core and native logs should be combined into one native support-log projection
for diagnostics/support export. On iOS/iPadOS, the existing
`IOSAppDiagnostics` / `IOSAppLogger` store is the authoritative native
support-log surface: it is bounded, persists across relaunches, receives Core
diagnostic records, mirrors retained records to Apple's unified logging, and is
support infrastructure rather than domain state.

Native iOS Settings exposes this support capability directly rather than through
a permanent developer-only screen:

- Debug Logging on/off;
- retained record count;
- structured Log Viewer;
- search and severity filtering;
- native export/share;
- confirmed Clear Logs.

The Log Viewer consumes the same retained structured entries; it must not create
another logging store. Export includes useful environment metadata such as app
version/build and OS/device class while remaining privacy-sanitized.

Secrets (API keys, authorization headers, tokens, passwords, credentials and
registered sensitive custom-header values) are never intentionally retained or
exported. Prefer preventing sensitive fields from reaching logging APIs and keep
the existing redaction/sanitization boundary as defense in depth.

Development-only sandbox paths, migration probes, image/cache metrics and
Timeline performance counters are not production Settings. Account connection
validation may expose bounded technical **Connection Details** when useful for
support, but should not be labeled as Developer Diagnostics.

## 21. Testing philosophy

Prefer deterministic Rust unit/integration tests using fake Miniflux transport,
temporary SQLite databases, fixtures, and synchronization primitives rather
than arbitrary sleeps. Native tests should favor pure presentation/state,
routing, and snapshot/state-mutation coverage.

Manual or system testing is reserved for real OS behavior: WidgetKit refresh or
display, notification delivery/activation, lifecycle/background scheduling,
real scroll geometry, and native media integrations. Broad UI automation is not
required when a smaller deterministic test protects the contract.

## 22. Decisions intentionally still open

These should be decided when they materially affect durable
implementation, not through broad speculative analysis:

-   concrete SQLite schema;
-   concrete Rust HTML parsing/sanitization libraries used to build the
    semantic Reader document;
-   exact backoff timings;
-   logging library;
-   final DTO/API names;
-   detailed media cleanup options;
-   exact System Notification wording/content;
-   exact action/deep-link destination when the user activates a System
  Notification;
-   concrete future feature requirements where historical FluxNews/FluxBar
    evidence is relevant.

## 23. Working principle

Prefer durable implementation over possibility analysis.

Before commissioning a PoC, compatibility study, or broad audit,
identify the concrete decision it will unblock. If no current
implementation decision depends on the answer, defer the analysis.

# Architecture Decisions — Phase C Media Addition

> **Target file:** `docs/ARCHITECTURE_DECISIONS.md`
>
> Add the following authoritative section to the repository architecture
> decisions. It records durable Phase-C decisions; detailed UX and implementation
> sequencing remain in `docs/PHASE_C_NATIVE_MACOS_AUDIO.md`.

## Phase C — macOS audio and Listening List

Phase B media ownership remains unchanged: Core owns durable media/domain state,
playback progress, download intent/state, policies, metadata, chapters,
persistence and Miniflux reconciliation. Native clients own playback engines,
runtime transfer execution/progress, filesystem operations, sleep-timer runtime,
Now Playing/media-key integration and presentation.

The macOS Phase-C media experience is audio-only. Generic shared-Core media
support may remain broader; native clients are not required to expose every
`MediaKind`.

### Listening List identity and ownership

The Listening List is **News/article-centered**. Saving to the Listening List
means saving the News, not an individual enclosure.

Playback and download state remain **enclosure-centered**. A News may contain
multiple audio enclosures while appearing exactly once in the Listening List.

The public Core/UniFFI read model must provide a News-centered Listening List
projection containing enough enclosure playback/download state for native
clients to render rows without N+1 state stitching.

The normal Reader contract remains separate. Article-to-media discovery is
exposed through a generic Core/UniFFI `article_enclosures(article_id)` relation
query rather than embedding media state into `ReaderDocument`.

Listening List membership is durable user state and protects its News/article
from normal read-article retention until the membership is explicitly removed
or a configured completion policy removes it.

### Listening List and download invariants

Starting a manual download implicitly adds the containing News to the Listening
List if it is not already present.

Per-feed automatic audio download also adds every qualifying News with audio to
the Listening List and requests all of its audio enclosures.

A global policy may automatically download all audio enclosures when a News is
added to the Listening List. This and feed auto-download are different triggers
for the same normal download machinery, not separate transfer systems.

Deleting an individual local download does not remove the News from the
Listening List.

Removing a News from the Listening List requests deletion of all local audio
downloads belonging to that News. Physical file deletion remains native
execution of Core-owned deletion intent.

The existing `delete_download_after_playback` behavior remains independent from
Listening List membership. A separate policy controls automatic removal of
completed News from the Listening List. Such removal also deletes associated
downloads according to the normal Listening List removal invariant. For News
with multiple audio enclosures, automatic removal occurs only after all relevant
audio enclosures are completed.

### Listening List presentation semantics

The macOS client exposes one **Listening List** destination rather than separate
Saved Media and Downloads destinations. Downloads are a property/action of a
Listening List News item, not a separate library dimension.

The initial list is flat, filterable by represented feed, and sortable by
Recently Added (default) or Publication Date.

A row represents one News and may show the playback progress of its most
recently played/relevant enclosure plus an aggregate downloaded-enclosure marker
such as `1/2`. Playback progress is shown as a bar with elapsed/total minutes,
not a percentage.

A separate Continue Listening section is not required because playback progress
is directly visible in the Listening List.

### macOS Player semantics

The macOS Player is a dedicated popover presentation mode, not a separate
window and not an in-app mini-player. Native macOS Now Playing/Control Center
provides remote playback presence while the popover is elsewhere.

The Player remains available while a medium is loaded, including paused or
stopped state.

The primary controls are:

**−30s · Play/Pause · Stop · +30s · Restart**

Pause preserves loaded media and position. Stop checkpoints progress and keeps
the medium loaded. Restart resets progress to `0:00` while keeping the medium
loaded; it does not mean Eject/Unload. There is no user-facing Eject control.

The Player also renders full Show Notes through the existing `ReaderDocument`
pipeline and exposes Core-owned chapters. Visible Player artwork is not
required; artwork is used for native Now Playing where available.

For complete Phase-C UX, contract, sequencing and acceptance criteria, see
`docs/PHASE_C_NATIVE_MACOS_AUDIO.md`.
