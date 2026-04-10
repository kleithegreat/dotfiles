# desktopctl Review

Reviewed on 2026-04-08.

## Verdict

The binary has fully replaced the old repo-owned desktop helper scripts. The
remaining integration edge to document accurately is `dark_hint`'s split
ownership between the daemon's solar schedule and direct theme-surface writes.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators. | `desired_state()` / `apply_desired_state()` in `desktopctl/src/daemon/night_light.rs` apply scheduled `dark_hint` changes in `auto`, but `set_dark_hint()`, `cmd_set()`, and `cmd_preset()` in `desktopctl/src/theme/mod.rs` still let `theme set dark_hint ...` and preset-supplied `dark_hint` values persist directly without daemon arbitration. Docs in this domain and in `docs/sun-schedule/` must treat that split as current behavior, not as resolved delegation. |
