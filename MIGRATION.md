# FluxNews native repository migration

## Local preparation, not publication

Prepared on 15 November 2026 on `migration/native-root-2026-11-15`.
No changes were pushed or merged into `main`, no pull request was opened, and
no application release, GitHub Actions run, build or project test was started.
The original Flux and FluxNews checkouts were used only as read-only sources.

This record supplements the imported documentation. The native `AGENTS.md`
and complete `docs/` tree were imported unchanged; their historical references
to a future cutover, `legacy/`, Flux CI or Weblate configuration have not been
silently rewritten. The actual archive location is `Archived/Flutter/`.
`NATIVE_DEVELOPMENT.md` preserves the original Flux README unchanged as
development context; current scripts and native architecture contracts remain
authoritative.

## Source and commit provenance

| Item | Exact commit |
| --- | --- |
| Original FluxNews `main` | `dfe92486a709cfadea9b44f516261db3eed390be` |
| Original Flux `main` | `65bb8eba008ddb3a66711ecba3e624068883f8d1` |
| Flutter archive commit | `ce0faf10c490a961aaaba883d3f0728d82867edc` |
| Two-parent history merge | `0959dbe84c5b77ee86699b9e93861621a62c1472` |

The archive commit is the first parent of the history merge; the original Flux
`main` is its second parent. Neither original history was rewritten, rebased or
squashed. `main` remains at the original FluxNews commit in this local copy.
The integration commit follows the merge and is not a release candidate.

All 53 original FluxNews tags and `android/v3.0.0` retain their exact object IDs.
This includes the distinct historical `v.1.12.1` and `v1.12.1` tags.
Importing `android/v3.0.0` does not create a GitHub Release in FluxNews or move
the existing Flux release. Its original target remains
`75022c001b5ad0d0f3935c0846fb5c59f5faac87`.

In addition to the merged main histories, 38 local archive branches preserve
the original reference targets:

- `archive/fluxnews/heads/*` and `archive/fluxnews/remotes/origin/*`:
  8 references, including local-only Flutter development history;
- `archive/flux/heads/*`, `archive/flux/remotes/origin/*` and
  `archive/flux/other/opencode/pr78`: 30 references, including stale local
  remote-tracking history and the extra commit reference.

Archive references are provenance, not active development branches. Their
unmerged changes were not applied to the application. Symbolic `origin/HEAD`
aliases are represented by the preserved `origin/main` targets.

## File ownership

- `core/`, `android/`, `apple/`, `Build/`, `fdroid/` and native workflows are
  imported from Flux into the root.
- Root `AGENTS.md` and `docs/` are exactly the native source versions.
- The tracked Flutter implementation, editor configuration, helper scripts and
  both old workflows are under `Archived/Flutter/`.
- The 13 separately security-reviewed local Flutter text files are archived
  unchanged as `Archived/Flutter/AGENTS.md` and `Archived/Flutter/docs/`.
  No native/Flutter documentation contents were mixed.
- `metadata/` and `screenshots/` retain the complete original FluxNews Git trees,
  file contents and modes at their original root paths.
- Root `PRIVACY.md` and `.github/FUNDING.yml` are unchanged.
- Root `README.md` retains the original product material with explicit
  published-Flutter labels and native development links.
- Root `LICENSE` retains both original BSD-3-Clause copyright notices.
- No `.DS_Store` file was copied or added. The excluded original
  `docs/.DS_Store` was not deleted or modified.
- Three already tracked native Xcode `xcuserdata` files were removed from the
  final working tree, not from history. Shared projects and shared schemes are
  unchanged. Ignore rules prevent reintroducing local IDE state and credentials.

No local signing properties, keystores, environment files, generated native
bindings, caches, application packages or build outputs were copied.
Intentional versioned source inputs, such as the Gradle Wrapper and isolated
Android transport-test fixtures, remain part of the native source.

## Submodules and unchanged application identity

The only current Gitlink is `vendor/rustls-platform-verifier`, pinned to
`252e25161a91af476cbea620e29d277592d27ec7`, with its original upstream URL.
The source's Rust/Android version and commit checks are unchanged.

Flutter is no longer in the active `.gitmodules` or current Git tree. Its
original SDK revision is documented in [the Flutter archive](Archived/Flutter/README.md).
Historical commits and tags retain their original `vendor/flutter` Gitlinks.

No application IDs, bundle IDs, app groups, entitlements, signing identities,
certificate expectations, version files, native project build settings or
dependency lockfiles were changed.
`core/crates/flux-core/src/saved_media_sync.rs` and `init.xml` are byte-identical
to Flux, including the old Bootstrap URL. That URL remains a deliberate
compatibility exception; Saved Media replication will be revised separately.

## CI and F-Droid integration

All seven native workflows and the native Dependabot configuration are in the
root `.github/`. Flutter workflows and their Python helpers are archived only.
Cargo updates target `/core`; Gradle updates target `/android`; Actions updates
target the root. No Flutter update configuration was added.

The native verifier Gitlink now triggers Android and F-Droid PR validation.
Android's localization guard uses the exact imported native source as its
existing-debt baseline only when the event base predates the Flutter-to-native
cutover. All changes since that native source are still checked. Once the
event base contains the native import, the ordinary PR/push base is used.
This is not a bypass for future UI text changes.

The F-Droid CI clone and metadata `Repo`/`SourceCode` target FluxNews.
Only the new native recipe removes `Archived/Flutter` from its disposable
build workspace before scanning; the repository archive itself is retained.
No scanner-ignore exception was added. All 129 historical Flutter recipe
blocks, their 43 source references, signing fingerprints, update settings and
`CurrentVersion`/`CurrentVersionCode` were preserved.

Historical recipes continue to check out their original commit/tag and use
the original root layout. Do not rewrite their paths to the archive prefix.
The native `FLUX_NATIVE_COMMIT` placeholder remains a template: the existing
preparation script substitutes an explicitly selected later source SHA.

Native release orchestration now refuses execution outside
`KevinCFechtel/FluxNews`. It retains manual dispatch, default validation mode,
the existing main-only release rule, per-job permissions, signing environment,
reproducibility checks and immutable tag checks. No tag/release trigger was
introduced. Releasing Android `3.0.0` again is deliberately blocked by the
preserved existing `android/v3.0.0` tag.

## Outstanding, separately authorized operations

Before any remote cutover:

1. Review the local history, file mappings and integration diff. Any later PR
   must preserve the actual merge history; do not squash or rebase it.
2. Explicitly disable the old FluxNews Flutter workflow IDs before publishing
   native tags or allowing historical workflow reruns.
3. Configure FluxNews's `release-testing` environment with its main-branch
   restriction and appropriate approvals; verify existing signing credentials
   against the unchanged developer certificate without exposing their values.
4. Review branch protections and required native checks, Dependency Graph,
   Dependabot/security settings, and the Weblate push webhook/components.
   The old Flutter translation file mask must not write into the native tree.
5. Decide separately how to retire Flux's active schedules, Dependabot and
   open PRs. No setting, PR or release in Flux was changed by this migration.

Before any new application release:

- Run the appropriate Rust, Android, Apple, signing/upgrade and F-Droid gates
  against the final explicitly approved FluxNews source SHA.
- Resolve the already failing RustSec baseline reported on 14 November 2026:
  `ctutils`, `libsqlite3-sys`, `basic-toml` and `rustix`. No dependencies or
  security-check strictness were changed as part of this migration.
- Complete the native F-Droid acceptance gates in `docs/FDROID_OPEN_GATES.md`.
  Official fdroiddata still checks Flutter's root `pubspec.yaml` and ABI-offset
  versioning; agree a native update-check configuration with its maintainers.
- Official F-Droid submission and developer-signature publication require
  separate work: the imported native pipeline does not submit an fdroiddata MR.
- Select any future versions separately; this migration does not change them
  or authorize another release using an already published version/tag.
- Review the retained privacy policy and published-Flutter presentation
  against the eventually released native behavior.

GitHub releases, assets, workflow settings, secrets and Weblate configuration
are hosting-service data, not transferred by a Git merge. No remote mutation
was performed. The local migration copy additionally blocks accidental pushes
through an invalid `origin` push URL and a local pre-push hook.
