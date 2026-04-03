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

## `theme.apply` IPC breaks on values with spaces
**Symptom:** Shell IPC cannot safely set fonts like `IBM Plex Sans` or wallpaper paths containing spaces.
**Cause:** `config/quickshell/shell.qml` still splits the payload with `args.split(" ")` before spawning `desktopctl theme`.
**Status:** Open
**Resolution:** The settings popup write path is safe today; the shell IPC path still needs argv-safe argument passing plus completion and error reporting.
