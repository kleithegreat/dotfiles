# desktopctl Review

Reviewed on 2026-04-07.

## Verdict

The binary has fully replaced the old repo-owned desktop helper scripts, but
two integration edges are still important to document accurately: `dark_hint`
still has split ownership, and one advertised brightness subcommand is now only
kept for compatibility.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators. | `desktopctl/src/daemon/night_light.rs:129-163` applies scheduled `dark_hint` changes in `auto`, but `desktopctl/src/theme/mod.rs:252-320` still lets `theme set dark_hint ...` and preset-supplied `dark_hint` values persist directly without daemon arbitration. Docs in this domain and in `docs/sun-schedule/` must treat that split as current behavior, not as resolved delegation. |
| Low | `desktopctl brightness seed` is still part of the public CLI even though it no longer does any work. | `desktopctl/src/main.rs:131-143` advertises the subcommand, but `desktopctl/src/brightness.rs:91-93` returns `Ok(())` immediately. That is fine as a compatibility shim, but callers must not assume it warms any Quickshell cache or OSD path. |
