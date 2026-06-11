# Quickshell Quirks

## Display layout dragging is staged until release

**Symptom:** Dragging monitors in the Display settings pane could leave the
session on a black or unreachable output arrangement, and the countdown did not
reliably restore the previous layout.

**Cause:** `config/quickshell/popups/settings/SettingsDisplayPane.qml` previously
called `hyprctl keyword monitor` on every pointer move while
`config/quickshell/components/MonitorLayout.qml` mutated the shared
`DisplayService.monitors` snapshot before Hyprland confirmed the new layout.

**Status:** Fixed.

**Resolution:** Monitor drag now starts only after actual movement, edits a
local cloned layout, normalizes the staged layout back to a `0x0` origin, and
applies one `DisplayService.applyMonitorBatch(...)` call on release. The confirm
countdown keeps the pre-change snapshot and re-applies it as a batch on timeout.

## The single bar is recreated after suspend or output loss
**Symptom:** The bar can disappear after suspend/resume, DPMS, hotplug, or other output loss even though the Quickshell process stays alive.
**Cause:** Hyprland tears down the layer-shell surface when outputs churn, while Qt keeps a placeholder `QScreen` alive; `Quickshell.screens` therefore does not become a reliable signal that all real outputs are gone.
**Status:** Fixed
**Resolution:** `config/quickshell/shell.qml` now drives bar lifetime from Hyprland's real monitor model instead of `Quickshell.screens`, filtering out `FALLBACK` monitors, preferring the real monitor positioned at `0x0`, and recreating the bar through a `Loader` with an explicit `screen` binding. `monitoradded` and `monitorremoved` events refresh the Hyprland monitor model plus `DisplayService` and `BrightnessService`, so the stale `PanelWindow` is unloaded and brightness sliders are re-filtered when real outputs change.

## Theme commands resolve `desktopctl` from the session `PATH`
**Symptom:** Theme reads or writes from Quickshell can fail even when the QML command arrays look correct.
**Cause:** Quickshell `Process` invocations (the settings host in `config/quickshell/popups/SettingsPopup.qml` and the services) invoke the bare `desktopctl` binary, which must resolve from the user session `PATH` installed via Home Manager.
**Status:** By design
**Resolution:** Keep `desktopctl` installed through Home Manager so every Quickshell `Process` can resolve it. The old shell-IPC `theme.apply` bridge (`tokenizeThemeArgs` / `themeApplyProc` in `config/quickshell/shell.qml`) no longer exists; the settings host passes structured argv arrays and surfaces failures through `ToastService`.
