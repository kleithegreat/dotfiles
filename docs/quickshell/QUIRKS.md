# Quickshell Quirks

## The single bar is recreated after suspend or output loss
**Symptom:** The bar can disappear after suspend/resume, DPMS, hotplug, or other output loss even though the Quickshell process stays alive.
**Cause:** Hyprland tears down the layer-shell surface when outputs churn, while Qt keeps a placeholder `QScreen` alive; `Quickshell.screens` therefore does not become a reliable signal that all real outputs are gone.
**Status:** Fixed
**Resolution:** `config/quickshell/shell.qml` now drives bar lifetime from Hyprland's real monitor model instead of `Quickshell.screens`, filtering out `FALLBACK` monitors, preferring the real monitor positioned at `0x0`, and recreating the bar through a `Loader` with an explicit `screen` binding. `monitoradded` and `monitorremoved` events refresh the Hyprland monitor model so the stale `PanelWindow` is unloaded and a fresh one is created when a real output returns.

## Theme commands use `desktopctl` from `PATH` and shell-style string quoting
**Symptom:** Theme reads or writes from Quickshell can fail even when the QML command arrays look correct, and string payloads still split on unquoted whitespace so multi-word fonts or wallpaper paths need quoting.
**Cause:** `config/quickshell/popups/SettingsPopup.qml` and `config/quickshell/shell.qml` invoke the bare `desktopctl` binary, while `tokenizeThemeArgs` in `config/quickshell/shell.qml` tokenizes string payloads into argv using shell-style quote and backslash rules before spawning `desktopctl theme`.
**Status:** By design
**Resolution:** Keep `desktopctl` installed through Home Manager so every Quickshell `Process` can resolve it from the user session `PATH`. Quote arguments such as `"IBM Plex Sans"` or pass an array payload when the caller already has structured argv pieces. Failures surface through the `themeApplyProc` / `ToastService.showError(...)` path in `config/quickshell/shell.qml`.
