# Quickshell Review

Reviewed on 2026-04-02.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. The remaining issues are mostly wiring mismatches at the shell/theme
edges.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| High | Quick Settings chevrons still emit expand signals that nothing consumes. | `QuickSettingsPopup.qml` exposes expand affordances for Wi-Fi, Bluetooth, VPN, DND, and power profile, but the overlay host only handles `settingsRequested`, so the UI shows dead controls. |
| Medium | `theme.apply` IPC still splits argv unsafely and does not report completion or failure. | Fonts and wallpaper paths containing spaces are not safe through this path; see `docs/quickshell/QUIRKS.md`. |
| Medium | Quickshell font-size controls do not update Quickshell chrome. | The `quickshell` target hardcodes shell font sizes, and the dependency map does not route `font_size` or `mono_font_size` changes back to the Quickshell target. |
| Medium | `system_font` has no visible effect on shell chrome. | `themes/lib/targets/quickshell.py` emits both `family` (from `mono_font`) and `systemFamily` (from `system_font`) in `GeneratedTheme.json`. `Theme.qml` exposes them as `fontFamily` and `systemFamily`. QML binds `Theme.fontFamily` across roughly 40 files; `Theme.systemFamily` is only referenced in `SettingsFontsPane.qml` and `SettingsPresetEditor.qml`. Changing `system_font` updates `GeneratedTheme.json` but has no visible effect on bar, popups, notifications, or other shell surfaces. |
| Medium | `neovide_mono_font_size_offset` exists in theming state but is missing from the editable settings list. | The backend and the settings UI no longer expose the same theme surface. |
