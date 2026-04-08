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
| Medium | `dark_hint` still has multiple live policy initiators and no daemon-owned override model. | `desktopctl/src/daemon/night_light.rs:129-163` writes scheduled `dark_hint` changes in `auto`, but `desktopctl/src/theme/mod.rs:252-320` still lets theme surfaces persist `dark_hint` directly. That means sun-schedule docs must describe `dark_hint` as split ownership, not as a daemon-only surface. |
