# Focus Time Review

Reviewed on 2026-04-03.

## Verdict

The subsystem is small and understandable, and the 2026-04-03 reliability audit
items around liveness, aggregate alignment, reconnect re-seeding, empty-state
messaging, and minute-table retention are now addressed. One startup edge case
still remains when every `hyprctl activewindow -j` seed attempt returns empty
before the first focus-change event arrives.

## Findings

| Severity | Finding | Why it matters | Evidence |
| --- | --- | --- | --- |
| Medium | Startup recording still depends on at least one successful `hyprctl activewindow -j` seed or a later focus-change event. | The daemon now seeds at startup and again after each successful socket reconnect, but if both seed attempts return empty and the focused window never changes, unlocked time is still skipped while JSON rewrites continue. | `desktopctl/src/hypr.rs:21-25`, `desktopctl/src/daemon/focus.rs:20-24`, `desktopctl/src/daemon/focus.rs:51-63`, `desktopctl/src/daemon/focus.rs:523-530` |

## Open Questions

- The current code writes only whole-second aggregates and never reads the
  SQLite store outside the daemon. If another consumer needs richer history, the
  repo does not yet define whether that contract should stay JSON-only or expose
  a shared service instead.
