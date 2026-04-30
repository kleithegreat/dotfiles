# Sun Schedule Review

Reviewed on 2026-04-07.

## Verdict

The `hyprsunset` ownership conflict is resolved, but the broader
night-light-versus-theme ownership story is still split. The daemon owns one
live controller for `hyprsunset`, while `dark_hint` can still be changed both
by the daemon's solar `auto` path and by direct `desktopctl theme` writes.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators and no daemon-owned override model. | `update_solar_status()` / `reconcile_locked()` in `desktopctl/src/daemon/night_light.rs` issue the startup scheduled reconciliation plus 23:00 enable and 06:00 disable, but `desktopctl/src/theme/mod.rs` still lets theme surfaces persist `dark_hint` directly through `set_dark_hint()` and the theme command handlers. This is documented as split ownership; the remaining issue is the absence of a unified override policy. |
