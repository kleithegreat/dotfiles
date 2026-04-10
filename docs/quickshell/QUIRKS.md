# Quickshell Quirks

## The single bar is recreated after suspend or output loss
**Symptom:** The bar can disappear after suspend/resume, DPMS, hotplug, or other output loss even though the Quickshell process stays alive.
**Cause:** Hyprland tears down the layer-shell surface when outputs churn, while Qt keeps a placeholder `QScreen` alive; `Quickshell.screens` therefore does not become a reliable signal that all real outputs are gone.
**Status:** Fixed
**Resolution:** `config/quickshell/shell.qml` now drives bar lifetime from Hyprland's real monitor model instead of `Quickshell.screens`, filtering out `FALLBACK` monitors and recreating the bar through a `Loader` with an explicit `screen` binding. `monitoradded` and `monitorremoved` events refresh the Hyprland monitor model so the stale `PanelWindow` is unloaded and a fresh one is created when a real output returns.

## Theme commands now depend on `desktopctl` being on `PATH`
**Symptom:** Theme reads or writes from Quickshell fail even though the QML command arrays look correct.
**Cause:** `config/quickshell/popups/SettingsPopup.qml` and `config/quickshell/shell.qml` now invoke the bare `desktopctl` binary instead of hardcoded repo paths.
**Status:** By design
**Resolution:** Keep `desktopctl` installed through Home Manager so every Quickshell `Process` can resolve it from the user session `PATH`.

## `theme.apply` string payloads use shell-style quoting
**Symptom:** Shell IPC string payloads still split on unquoted whitespace, so multi-word fonts or wallpaper paths need quoting.
**Cause:** The `tokenizeThemeArgs` helper in `config/quickshell/shell.qml` tokenizes string payloads into argv using shell-style quote and backslash rules before spawning `desktopctl theme`.
**Status:** By design
**Resolution:** Quote arguments such as `"IBM Plex Sans"` or pass an array payload when the caller already has structured argv pieces. Failures now surface through the `themeApplyProc` / `ToastService.showError(...)` path in `config/quickshell/shell.qml`.

## Custom shell chrome is intentionally pointer-first
**Symptom:** Bar modules, Quick Settings tiles, the power menu, shared toggles, and settings sidebar categories do not expose repo-local tab stops, Enter/Space activation, or explicit focus outlines.
**Cause:** The Quickshell UI is currently designed around pointer/touch hit targets and hover/pressed feedback rather than a second custom keyboard-navigation layer across shell surfaces.
**Status:** By design
**Resolution:** Preserve the pointer-first interaction model in `config/quickshell/components/ToggleSwitch.qml`, `config/quickshell/components/InlineDropdown.qml`, `config/quickshell/components/InlineSelect.qml`, `config/quickshell/popups/settings/SettingsSidebar.qml`, `config/quickshell/popups/QuickSettingsPopup.qml`, `config/quickshell/bar/`, and `config/quickshell/PowerMenu.qml` unless the shell interaction policy changes again.
