# desktopctl Review

Reviewed on 2026-06-10.

## Verdict

The binary has fully replaced the old repo-owned desktop helper scripts. The
remaining integration edge is `dark_hint`'s split ownership between the
daemon's solar schedule and direct theme-surface writes.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators by design, pending an owner decision on a unified override model. | See `docs/sun-schedule/SPEC.md` (Ownership Boundaries) for the canonical contract and `docs/sun-schedule/REVIEW.md` for the open policy question. Per-key upsert persistence means the concurrent writers no longer clobber each other's unrelated state keys; the remaining issue is product policy, not data integrity. |
