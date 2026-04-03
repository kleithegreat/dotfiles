# Quickshell Quirks

## The single bar is recreated when outputs churn
**Symptom:** The bar can disappear or stay attached to a dead output during monitor hotplug, output disable, or output cycling.
**Cause:** The shell binds one bar to the first `Quickshell.screens` entry, and that list can go empty before a new screen becomes valid again.
**Status:** Workaround in place
**Resolution:** `config/quickshell/shell.qml` unloads the bar when `barScreen` is `null`, recreates it through a `Loader` when a screen returns, and refreshes Hyprland monitors on `monitoradded` and `monitorremoved`.

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
