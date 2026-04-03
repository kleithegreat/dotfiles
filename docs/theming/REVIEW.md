# Theming Review

Reviewed on 2026-04-03.

## Verdict

The pipeline is coherent: one CLI, one schema, one registry, and a consistent
base/generated ownership model. The centralized scheme metadata resolved the
previous family/variant drift in `bat`, `snappy_switcher`, `vicinae`,
`vscode`, and `qt`. The main remaining gaps are dependency-map drift,
Neovim's intentional raw pass-through, and the wallpaper bootstrap path.

## Findings

| Severity | Finding | Impact |
| --- | --- | --- |
| Medium | Dependency selection is not fully aligned with real consumers. | `tmux` is still listed under `mono_font`, while Quickshell font-size changes do not route back to the `quickshell` target. |
| Low | `neovim` still consumes raw `family` and `variant` strings by design. | The centralized app-theme metadata does not currently drive the Neovim target, so any future scheme whose Neovim plugin identifiers diverge from repo `family` / `variant` values will still need Neovim-side handling. |
| Medium | Quickshell `system_font` binding drift. The `quickshell` target emits both `family` (mono) and `systemFamily` (system) in `GeneratedTheme.json`, but `Theme.qml` exposes them as `fontFamily` and `systemFamily`. QML binds `Theme.fontFamily` across ~350 call sites in 40 files; `Theme.systemFamily` is only referenced in 2 settings panes. | Changing `system_font` has no visible effect on the shell UI outside the settings editor. |
| Low | `config/hypr/autostart.conf` contains a hardcoded `awww img` path that sets the initial wallpaper independently of the theming pipeline's persisted wallpaper value. | The wallpaper visible at session boot may not match theme state until the first `desktopctl theme` run. The spec correctly claims runtime wallpaper ownership for the pipeline, but the autostart bootstrap is an uncoordinated write to the same resource. |

Known KDE/Kirigami and Kvantum limitations are tracked in
`docs/theming/QUIRKS.md`.
