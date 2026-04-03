# Quickshell Quirks

## The single bar is recreated after suspend or output loss
**Symptom:** The bar can disappear after suspend/resume, DPMS, hotplug, or other output loss even though the Quickshell process stays alive.
**Cause:** Hyprland tears down the layer-shell surface when outputs churn, while Qt keeps a placeholder `QScreen` alive; `Quickshell.screens` therefore does not become a reliable signal that all real outputs are gone.
**Status:** Fixed
**Resolution:** `config/quickshell/shell.qml` now drives bar lifetime from Hyprland's real monitor model instead of `Quickshell.screens`, filtering out `FALLBACK` monitors and recreating the bar through a `Loader` with an explicit `screen` binding. `monitoradded` and `monitorremoved` events refresh the Hyprland monitor model so the stale `PanelWindow` is unloaded and a fresh one is created when a real output returns.

## Theme commands cannot rely on `$DOTFILES`
**Symptom:** Theme reads or writes from Quickshell fail if they try to discover the repo root from `$DOTFILES`.
**Cause:** Quickshell `Process` commands do not inherit that variable in this setup.
**Status:** Workaround in place
**Resolution:** `config/quickshell/popups/SettingsPopup.qml` and `config/quickshell/shell.qml` use absolute `/home/kevin/repos/dotfiles/...` paths for theme state, lists, wallpapers, and `themes/apply-theme`.

## `theme.apply` IPC breaks on values with spaces
**Symptom:** Shell IPC cannot safely set fonts like `IBM Plex Sans` or wallpaper paths containing spaces.
**Cause:** `config/quickshell/shell.qml` splits the payload with `args.split(" ")` before spawning `apply-theme`.
**Status:** Open
**Resolution:** The settings popup write path is safe today; the shell IPC path still needs argv-safe argument passing plus completion and error reporting.
