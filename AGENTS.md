# AGENTS.md

## Goal

Build Flux toward one shared Rust core consumed by native macOS, iOS, and Android clients.
Prioritize durable product value. Avoid temporary architectures, compatibility layers, PoCs, migrations, or refactors that are expected to be replaced shortly afterward.

The human developer owns product and architecture decisions. Do not silently introduce or reopen major design choices.

## Architecture Authority

For non-trivial work, use this order of authority:

1. `docs/ARCHITECTURE_DECISIONS.md` — authoritative target architecture and explicitly agreed product/core boundaries.
2. The active platform/phase contract for the requested work, including `docs/MOBILE_PRODUCT_SEMANTICS.md` for shared native-mobile behavior and `docs/PHASE_E_NATIVE_ANDROID.md` for Phase E Android sequencing/mechanics.
3. Current Rust/native implementation and tests — evidence of what is implemented today, not permission to override the target architecture.
4. `docs/reference/` — historical product and feature evidence used to avoid losing valuable behavior.

If reference material conflicts with `ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

The former Go core is retired and out of scope. Do not preserve Go compatibility, Go ABI behavior, Go database interoperability, or Go migration phases unless a task explicitly asks for historical analysis.

## Binding Decision

UniFFI is the selected binding technology for the shared Rust core.
Do not reopen the binding choice or introduce a temporary C/JSON/JNI/Swift bridge as an intermediate architecture unless explicitly requested.

Design the public Rust boundary to be UniFFI-friendly: coarse-grained domain operations, owned DTOs/records/enums, explicit errors, batch operations where appropriate, and no UI-specific concepts.

## Core / Native Boundary

The Rust core owns background/domain responsibilities such as persistence, Miniflux communication, sync/reconciliation, durable mutations, article/feed/category data, content processing, cache/media metadata, core settings, queries, and structured core events.

Native clients own presentation and OS integration: navigation, visible list snapshots, scroll position, gestures, dialogs, theme/layout, browser/share surfaces, secure credential storage, native background scheduling/transfer facilities, playback engines, widgets, and OS notifications.

A UI interaction may call a core domain operation, but the core API must not be named or shaped around a swipe, button, context menu, pull-to-refresh, or other UI mechanism.

## Repository and Build Layout

The shared Rust workspace lives under `core/`. `core/Cargo.toml` is the authoritative workspace manifest and `core/Cargo.lock` is the single tracked lockfile for that workspace. Platform clients live alongside the shared core under `apple/macos/`, `apple/ios/`, and the Phase-E `android/` client when implementation creates it. Do not move the Rust workspace back to the repository root or introduce duplicate workspace/lockfile layouts without a concrete requirement.

For Apple platforms, the canonical UniFFI packaging path is `apple/Build/build-uniffi.sh`; it produces the macOS and iOS XCFramework slices plus the generated Swift binding source. For macOS, `apple/macos/Build/build-uniffi.sh` consumes that package for the established `build-app.sh` and `release.sh` build/release path. Preserve this validated path unless a concrete implementation requirement makes a change necessary; do not replace it with parallel or temporary build/release mechanisms.

## Implementation Rules

- Prefer the smallest durable implementation that advances the target architecture.
- Do not create parallel implementations when an existing target abstraction can be extended cleanly.
- Do not perform broad compatibility audits or exploratory PoCs unless a concrete unresolved blocker requires them.
- Reuse old documentation only as evidence of required behavior or feature coverage.
- Keep visible UI snapshots independent from background core state changes as defined in the architecture decisions.
- Keep secrets out of core persistence and logs.
- Keep changes focused; report unrelated issues instead of fixing them automatically.
- New dependencies require a concrete justification.

If a requested change requires a product/architecture decision not already covered by `ARCHITECTURE_DECISIONS.md`, stop and surface that decision instead of guessing.

## Phase B — Shared Podcast / Media Core

For all Phase B media, podcast, enclosure, playback, download, SavedMedia, media metadata, automotive media, and related synchronization work, `docs/PHASE_B_MEDIA_CORE.md` is the authoritative implementation contract.

Agents must:

* follow `docs/PHASE_B_MEDIA_CORE.md` as frozen architecture;
* implement only the requested Phase B step or sub-step;
* reuse existing Flux architecture, storage, sync, mutation, retention, and UniFFI patterns where applicable;
* not redesign or re-open frozen Phase B decisions during implementation;
* not copy the legacy Flutter FluxNews media architecture as a technical template; it may only be used as a behavioral reference;
* preserve local-first behavior: playback, downloads, and SavedMedia must remain functional without optional Saved Media Sync;
* treat the optional Miniflux Saved Media Sync as a replication adapter above the local `SavedMedia` domain, never as its definition.

If the current implementation appears to contradict the Phase B contract, do not silently invent a new architecture. Identify the concrete conflict with:

1. the relevant contract requirement;
2. the current implementation behavior or constraint;
3. why both cannot be satisfied as written.

Only escalate genuine contract contradictions. Normal implementation details explicitly left open by the contract should be resolved consistently with the existing Flux codebase.


## Phase E — Native Android

For native Android work, `docs/PHASE_E_NATIVE_ANDROID.md` is the authoritative Phase-E implementation/sequencing contract and `docs/MOBILE_PRODUCT_SEMANTICS.md` is the shared mobile product contract.

Agents must:

* keep Rust Core/UniFFI as the durable domain boundary; do not create a Kotlin Miniflux/domain/persistence duplicate;
* begin Phase E with the E1 foundation/migration gates before productive feature UI;
* treat Flutter FluxNews only as behavioral and production-migration evidence;
* use Kotlin/Jetpack Compose as the initial native UI baseline and make Android renderer/performance changes from measurements rather than Apple implementation history;
* keep Android lifecycle, credentials, background work, notifications, widgets, media execution and Android Auto platform-native while preserving Core ownership;
* preserve the production application identity and copy/import-only migration contract for production-upgrade work;
* not reopen UniFFI, frozen Phase A-D ownership, or shared product semantics without a concrete technical contradiction.


## Validation

Run validation appropriate to the changed Rust/native target. Never claim a build, test, migration, or command succeeded unless it was actually executed successfully.

Give extra scrutiny to persistence/schema changes, Miniflux sync/reconciliation, concurrency/background execution, credentials/security/privacy, automatic read-state mutation, notifications, media/download state, UniFFI boundaries, and destructive reset/cleanup behavior.

## Human Review Summary

After non-trivial implementation, report briefly:

- **What** changed.
- **Why** it was needed.
- **Code** files/symbols worth reviewing.
- **Risk** only where meaningful.
- **Validation** actually executed.
- **Open decision** only if human input is genuinely required before proceeding.

Do not generate a new roadmap unless explicitly asked.
