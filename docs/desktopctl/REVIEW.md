# desktopctl Review

Reviewed on 2026-04-08.

## Verdict

The binary has fully replaced the old repo-owned desktop helper scripts. The
remaining integration edge to document accurately is `dark_hint`'s split
ownership between the daemon's solar schedule and direct theme-surface writes.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators. | `desktopctl/src/daemon/night_light.rs:129-163` applies scheduled `dark_hint` changes in `auto`, but `desktopctl/src/theme/mod.rs:73-95` and `desktopctl/src/theme/mod.rs:318-388` still let `theme set dark_hint ...` and preset-supplied `dark_hint` values persist directly without daemon arbitration. Docs in this domain and in `docs/sun-schedule/` must treat that split as current behavior, not as resolved delegation. |
