# Sun Schedule Review

Reviewed on 2026-04-02.

## Verdict

The scheduling path itself is coherent: one script computes solar events, one
Home Manager module keeps it running, and one theming write path persists
`dark_hint`. The main problems are ownership conflicts around `hyprsunset` and
uncoordinated policy writers for the scheduled `dark_hint` value.

## Findings

| Severity | Finding | Impact | Evidence |
| --- | --- | --- | --- |
| High | `hyprsunset` has three direct writers. The scheduler starts or stops it in `scripts/sun-schedule`, Quickshell `DisplayService.qml` starts, stops, and restarts it directly, and Hyprland keybinds can also kill or start it. | There is no arbiter for automation vs manual control. The next 2-hour scheduler repair pass, the next transient timer, a shell temperature change, or an F8/F9 keypress can all overwrite each other. This makes ownership of the `hyprsunset` process genuinely ambiguous. | `scripts/sun-schedule:126-140`, `scripts/sun-schedule:193-236`, `config/quickshell/DisplayService.qml:85-137`, `config/quickshell/DisplayService.qml:217-285`, `config/hypr/keybinds.conf:73-75`, `home/sun-schedule.nix:12-18` |
| High | `dark_hint` has multiple policy initiators and no override model. The scheduler calls `apply-theme set dark_hint ...`; Quickshell settings can do the same; presets can include `dark_hint`; and shell IPC can invoke arbitrary `apply-theme` commands. | The file write path is centralized, but the desired value is not. A user can set `dark_hint` interactively and have it silently reversed by the next scheduler repair pass or transient event, while presets can also replace the same key without any coordination with solar automation. | `scripts/sun-schedule:143-149`, `scripts/sun-schedule:175-236`, `themes/apply-theme:228-256`, `themes/apply-theme:259-297`, `config/quickshell/popups/SettingsPopup.qml:647-654`, `config/quickshell/popups/SettingsPopup.qml:866-870`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:396-485`, `config/quickshell/shell.qml:299-306` |

## Open Questions

- If manual night-light control is meant to coexist with solar scheduling, what
  component is supposed to arbitrate overrides and hand control back?
- If user-selected `dark_hint` changes are supposed to survive automation, what
  lockout, snooze, or override model should the scheduler honor?
