# Sun Schedule Review

Reviewed on 2026-04-03.

## Verdict

The scheduler itself is now simpler than the old script-plus-timer stack: one
daemon task computes solar events and one theming write path persists
`dark_hint`. The remaining problems are ownership conflicts around
`hyprsunset` and uncoordinated policy writers for the scheduled `dark_hint`
value.

## Findings

| Severity | Finding | Impact | Evidence |
| --- | --- | --- | --- |
| High | `hyprsunset` has three direct writers. The scheduler starts or stops it in `desktopctl daemon`, Quickshell `DisplayService.qml` starts, stops, and restarts it directly, and Hyprland keybinds can also kill or start it. | There is no arbiter for automation vs manual control. The next 2-hour scheduler repair pass, the next solar event, a shell temperature change, or an F8/F9 keypress can all overwrite each other. This makes ownership of the `hyprsunset` process genuinely ambiguous. | `desktopctl/src/daemon/solar.rs:45-85`, `config/quickshell/DisplayService.qml:85-137`, `config/quickshell/DisplayService.qml:217-285`, `config/hypr/keybinds.conf:73-75` |
| High | `dark_hint` has multiple policy initiators and no override model. The scheduler calls into `desktopctl theme`, Quickshell settings can do the same, presets can include `dark_hint`, and shell IPC can invoke arbitrary `desktopctl theme` commands. | The file write path is centralized, but the desired value is not. A user can set `dark_hint` interactively and have it silently reversed by the next scheduler repair pass or solar event, while presets can also replace the same key without any coordination with solar automation. | `desktopctl/src/daemon/solar.rs:45-89`, `desktopctl/src/theme/mod.rs:69-90`, `config/quickshell/popups/SettingsPopup.qml:617-672`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:396-485`, `config/quickshell/shell.qml:299-306` |

## Open Questions

- If manual night-light control is meant to coexist with solar scheduling, what
  component is supposed to arbitrate overrides and hand control back?
- If user-selected `dark_hint` changes are supposed to survive automation, what
  lockout, snooze, or override model should the scheduler honor?
