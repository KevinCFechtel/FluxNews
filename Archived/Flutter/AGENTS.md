# AGENTS.md

## Goal

Work efficiently and conservatively in Flux News.

Prefer small, focused changes that preserve the existing architecture. Do not introduce unnecessary abstractions, dependencies, migrations, or unrelated refactors.

The human developer remains responsible for architectural decisions. Make important design choices explicit instead of silently introducing them.

## Repository Context

Before non-trivial work, read the relevant project documentation rather than scanning every context file:

- `docs/DEVELOPER_MAP.md` — high-level architecture and important data flows.
- `docs/ARCHITECTURE_DECISIONS.md` — durable invariants and decisions that must not be accidentally violated.
- `docs/features/` — detailed feature-specific context; read only the files relevant to the current task.
- `docs/RELEASE_AND_DISTRIBUTION.md` — release, signing, reproducibility, F-Droid, and external distribution constraints.
- `docs/PRODUCT_BACKLOG.md` — ideas and planned features; these are not necessarily implemented.

Do not assume a backlog item is implemented. Verify the current repository state.

## Understand Before Changing

Before modifying code:

- Inspect the relevant implementation and its direct dependencies.
- Reuse existing patterns, abstractions, and utilities where appropriate.
- Identify the smallest reasonable scope for the requested change.
- Do not explore unrelated parts of the repository without a concrete reason.
- Distinguish current behavior from historical notes and proposed future behavior.

For non-trivial changes, briefly state the intended approach before implementation.

If a task requires a significant architectural decision not implied by the existing code, documentation, or task description, explain the alternatives before implementing it.

Do not ask for confirmation for routine details that clearly follow existing conventions.

## Project-Specific Rules

- Miniflux remains the source of truth for categories, feeds, and feed metadata.
- Never treat a failed or incomplete remote sync response as an authoritative empty snapshot.
- Preserve the shared foreground/background sync pipeline and cross-isolate sync locking unless a deliberate architectural change is requested.
- Preserve the distinction between failed Secure Storage reads and successfully read empty configuration.
- Production mobile SQLite must use normal `sqflite`; do not initialize `sqflite_common_ffi` in production.
- iOS uses Flutter Swift Package Manager integration. Do not reintroduce CocoaPods unless the migration decision is explicitly revisited.
- Keep iOS Liquid Glass implementation behind Flux News-owned boundaries and out of the Android rendering path.
- Native home-screen widgets consume Flutter-generated snapshots; they must not access Miniflux credentials or SQLite directly.
- Avoid reapplying previously reverted performance experiments documented as unsuccessful without first profiling the original problem.
- External policies, current dependency behavior, store rules, F-Droid behavior, and platform behavior must be revalidated against current primary/official sources when relevant.

See `docs/ARCHITECTURE_DECISIONS.md` for the full rationale and additional invariants.

## Analysis, Tests, and Commands

Always run `flutter analyze` with network access in this repository because Flutter may query `pub.dev` for package/advisory information.

Always scope analysis to explicit application/test paths. Do not run an unscoped project-wide analyze because the repository contains a vendored Flutter SDK and unrelated code.

Typical validation:

```bash
flutter analyze lib test
flutter test
```

Prefer targeted tests first, then the broader suite when justified by the scope.

Never claim a command or test succeeded unless it was actually executed successfully.

Do not repeatedly run expensive commands without a reason.

## Implementation

- Keep changes focused on the requested task.
- Prefer modifying existing abstractions over creating parallel implementations.
- Avoid unrelated cleanup or refactoring.
- Avoid new dependencies unless clearly justified.
- Preserve public interfaces unless changing them is part of the task.
- Follow existing platform separation and adaptive-layout conventions.
- Do not silently change behavior outside the requested scope.
- If an unrelated issue is discovered, report it instead of fixing it automatically.

## Risk-Based Review

Apply additional scrutiny when changes affect:

- persistence or database migrations
- synchronization and reconciliation
- configuration/credential loading
- concurrency or asynchronous state
- background execution
- authentication, authorization, security, or privacy
- data deletion or irreversible operations
- widget/native bridges
- application lifecycle
- audio focus / media sessions
- signing, releases, reproducible builds, or store/F-Droid distribution

For these areas, explicitly mention relevant risks in the final review.

## Human Review Summary

After a non-trivial implementation, provide a concise review for a human developer.

Group by logical change rather than by every modified file.

For each logical change include:

### `<short description>`

**What:** What behavior or implementation changed.

**Why:** Why the change was necessary.

**Code:** Relevant files and symbols to inspect.

**Risk:** Only when there is a meaningful risk, tradeoff, compatibility concern, or behavior that deserves human attention.

Then finish with:

### Validation

List only tests, analysis, builds, or checks actually performed and their results.

### Review Focus

List the parts that deserve particular human attention. If none do, say so briefly.

Do not explain obvious syntax or enumerate every changed line.

## Context Efficiency

Use repository context deliberately.

- Read only documentation relevant to the task.
- Avoid repeatedly reading unchanged files.
- Prefer durable documentation over reconstructing known architecture from scratch.
- Keep plans and summaries proportional to the task.
- Do not produce large reports unless explicitly requested.

The goal is to spend agent context on understanding, implementing, validating, and explaining the requested change.
