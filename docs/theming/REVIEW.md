# Theming Review

Reviewed on 2026-04-02.

## Verdict

The pipeline is coherent: one CLI, one schema, one registry, and a consistent
base/generated ownership model. The main gaps are normalization drift,
dependency-map drift, stale repo snapshots that still look authoritative,
and cross-domain ownership conflicts around `dark_hint`, `hyprsunset`, and
the wallpaper bootstrap path.

## Findings

| Severity | Finding | Impact |
| --- | --- | --- |
| High | Variant and family normalization is not centralized. | Non-binary variants and family spellings still leak into targets that expect dark/light polarity or explicit family maps, especially `neovim.py`, `qt.py`, `vicinae.py`, and `vscode.py`. |
| Medium | Dependency selection is not fully aligned with real consumers. | `tmux` is still listed under `mono_font`, while Quickshell font-size changes do not route back to the `quickshell` target. |
| Medium | The repo still carries stale generated snapshots. | `config/ghostty/config`, `config/starship/starship.toml`, `config/vicinae/settings.json`, and `config/vicinae/vicinae.json` look like live sources even though the targets read `base` files and generate outputs elsewhere. |
| Medium | `dark_hint` has multiple policy initiators and no override model. The scheduler, Quickshell settings, presets, and shell IPC can all invoke `desktopctl theme set dark_hint`, but the pipeline has no lockout or coordination mechanism. | A user-selected `dark_hint` change can be silently reversed by the next scheduler repair pass or solar event. See `docs/sun-schedule/REVIEW.md`. |
| Medium | `hyprsunset` has three direct writers with no arbiter. The sun scheduler, Quickshell `DisplayService.qml`, and Hyprland keybinds all start or stop `hyprsunset` independently. | Any automated or manual color-temperature change can be overwritten by another writer at any time. See `docs/sun-schedule/REVIEW.md`. |
| Medium | Quickshell `system_font` binding drift. The `quickshell` target emits both `family` (mono) and `systemFamily` (system) in `GeneratedTheme.json`, but `Theme.qml` exposes them as `fontFamily` and `systemFamily`. QML binds `Theme.fontFamily` across ~350 call sites in 40 files; `Theme.systemFamily` is only referenced in 2 settings panes. | Changing `system_font` has no visible effect on the shell UI outside the settings editor. |
| Low | `config/hypr/autostart.conf` contains a hardcoded `awww img` path that sets the initial wallpaper independently of the theming pipeline's `state.json` wallpaper value. | The wallpaper visible at session boot may not match theme state until the first `desktopctl theme` run. The spec correctly claims runtime wallpaper ownership for the pipeline, but the autostart bootstrap is an uncoordinated write to the same resource. |

Known KDE/Kirigami and Kvantum limitations are tracked in
`docs/theming/QUIRKS.md`.
