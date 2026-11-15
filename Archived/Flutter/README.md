# Archived Flutter implementation

This directory preserves the Flutter implementation from FluxNews commit
`dfe92486a709cfadea9b44f516261db3eed390be`. It is historical reference material,
not the active application or release pipeline.

The separately reviewed local `AGENTS.md` and `docs/` are archived unchanged.
They describe the Flutter implementation only and are not native development
instructions. Finder metadata, caches, local credentials and signing
configuration were not copied.

## Flutter SDK provenance

The original project used the `vendor/flutter` Git submodule:

- upstream: `https://github.com/flutter/flutter`
- recorded branch: `stable`
- exact revision: `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`
- locally recorded release: `3.47.5`

The Flutter Gitlink and its active `.gitmodules` entry have been removed from
the current repository tree. No Flutter SDK checkout is embedded in this
archive. The original Gitlink, configuration and source layout remain available
at the original commits and tags; no historical commit or tag was rewritten.

## Historical builds and releases

Use the original release tag or exact commit in a separate checkout to inspect
or reproduce a historical Flutter release. Historical F-Droid recipes must
continue to use their original root-relative paths, not this archive prefix.
The archived snapshot is not a newly validated reproducible-build location.

The workflows in `.github/workflows/` and their Python helpers are preserved
as inactive archival files. Do not invoke the archived release/tag or SDK-update
scripts as part of native development.

Project-wide `README.md`, `LICENSE`, `PRIVACY.md`, `metadata/`, `screenshots/`
and `.github/FUNDING.yml` remain in the repository root. The license for this
archived implementation is the root [BSD 3-Clause License](../../LICENSE).
