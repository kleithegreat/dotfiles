# Sun Schedule Review

Reviewed on 2026-04-03.

## Verdict

The ownership conflicts called out in the previous review are resolved. The
daemon now owns one live night-light controller that arbitrates `auto` /
`on` / `off`, Quickshell and Hyprland keybinds request changes through
`desktopctl night-light`, and theme-surface `dark_hint` requests are delegated
back through the daemon instead of bypassing it.

## Findings

No open ownership findings remain in this domain as of 2026-04-03.

## Open Questions

None at review time.
