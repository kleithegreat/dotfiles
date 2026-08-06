# Quickshell Quirks

## A `var` array model resets its Repeater and kills in-flight drags

**Symptom:** The brightness sliders could be clicked to set a value but not
dragged — the knob jumped to the press point and then ignored the rest of the
gesture. The volume slider in the same popup dragged fine, which is the tell:
it binds straight to `AudioService.volume` and is not a Repeater delegate.

**Cause:** `BrightnessService.updateDeviceFraction` rebuilds `brightnessDevices`
into a fresh array of fresh objects on every write, which is what makes the
optimistic value update visible. A `var` array model cannot be diffed, so
reassigning it resets `QQmlDelegateModel` and **destroys and recreates every
delegate**. The first `moved` emission of a drag therefore destroyed the
`BrightnessSlider` delegate — and with it the `MouseArea` holding the pointer
grab — so no further `positionChanged` could arrive. Confirmed by running a
minimal `Instantiator` over a reassigned array under `quickshell -p`: each
reassignment logs `DELEGATE DESTROYED` / `DELEGATE CREATED` for every element.

**Status:** Fixed.

**Resolution:** Both brightness Repeaters (`popups/QuickSettingsPopup.qml` and
`popups/settings/SettingsDisplayPane.qml`) key on `brightnessDevices.length` —
an int model, which only changes when the *set* of devices changes — and look
the device up by `index`. Value writes then rebind in place instead of
rebuilding the delegate. Any future view over a service array that is rebuilt
on write needs the same treatment; keying on the array itself will silently
break drags and destroy any per-delegate state.

## Draggable controls inside a `WheelFlickable` need `preventStealing`

**Symptom:** Latent rather than observed: a slider drag that survives long
enough to leave the track would hand the pointer grab to the enclosing scroll
view and stop tracking mid-gesture.

**Cause:** `Flickable` sets `filtersChildMouseEvents` and watches its children's
press-and-move. Once a drag passes the platform drag threshold it takes the
mouse grab to scroll the content, and the child `MouseArea` stops receiving
`positionChanged`. Every `SliderTrack` use site sits inside a
`components/WheelFlickable.qml`. This was masked for the brightness sliders by
the Repeater-reset bug above, which killed the drag earlier and more
completely; fixing that reset is what makes this reachable.

**Status:** Fixed.

**Resolution:** The `HoverLayer` in `config/quickshell/components/SliderTrack.qml`
sets `preventStealing: true`, which keeps the grab with the slider for the whole
gesture. A drag that begins on a slider is always meant for the slider, so the
lost scroll gesture is not a real trade. Any future draggable control placed
inside a `WheelFlickable` needs the same flag; plain buttons should *not* set it,
since dragging across a button is a legitimate way to scroll the pane.

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
