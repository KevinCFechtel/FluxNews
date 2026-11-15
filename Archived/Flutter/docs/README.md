# Flux News Context Documentation

The former single `FluxNewsContext.txt` has been split by purpose so humans and coding agents can load only the context relevant to a task.

## Always-relevant

- `../AGENTS.md` — instructions for coding agents and project-wide working rules.
- `DEVELOPER_MAP.md` — compact human-readable model of the application.
- `ARCHITECTURE_DECISIONS.md` — durable invariants and rationale.

## Feature-specific

- `features/WIDGETS.md`
- `features/IOS_UI.md`
- `features/ANDROID_UI.md`
- `features/SYNC_AND_DATA.md`
- `features/MEDIA.md`
- `features/BACKUP.md`

## Other context

- `RELEASE_AND_DISTRIBUTION.md` — release, signing, reproducible builds, F-Droid.
- `PRODUCT_BACKLOG.md` — ideas and future feature plans.
- `PROJECT_HISTORY.md` — migration and historical validation breadcrumbs.

## Suggested agent workflow

1. Read `AGENTS.md`.
2. Read `DEVELOPER_MAP.md` only when architectural orientation is needed.
3. Read the relevant feature document(s) for the task.
4. Read `ARCHITECTURE_DECISIONS.md` before changing critical data/sync/platform boundaries.
5. Read release/backlog/history documents only when the task actually involves them.

The original context file can be retained temporarily during migration, but it should no longer be loaded as the default project context once these files are adopted.
