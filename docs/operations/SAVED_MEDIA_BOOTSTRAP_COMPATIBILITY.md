# Saved Media bootstrap compatibility

> **Status: ACTIVE COMPATIBILITY ITEM**
>
> This document owns the remaining compatibility decision for the historical
> Saved Media bootstrap endpoint. It is intentionally separate from repository
> migration and release orchestration.

During the Flux → FluxNews repository cutover,
`core/crates/flux-core/src/saved_media_sync.rs` and `init.xml` intentionally
retained the old Flux bootstrap URL. That preservation was a compatibility
decision, not evidence that the repository migration remains incomplete.

## Ownership

- Shared Saved Media domain and replication semantics remain governed by
  [`../current/MEDIA_CORE.md`](../current/MEDIA_CORE.md).
- This document owns only the compatibility question of whether/when the
  historical bootstrap URL should change.
- A URL change must not be bundled casually with documentation cleanup,
  dependency maintenance, F-Droid work or a release tag.

## Acceptance before changing the URL

Before replacing the historical endpoint, confirm:

1. the new endpoint is durable and controlled for the intended lifetime;
2. existing installations and stored configuration do not lose replication
   behavior or require an undocumented migration;
3. bootstrap behavior remains compatible with the local-first Saved Media
   contract;
4. tests/validation cover the exact old→new compatibility path as appropriate.

Until such a change is explicitly approved and validated, retaining the current
URL is intentional behavior rather than an open repository-migration defect.
