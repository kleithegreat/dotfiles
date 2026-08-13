# Quickshell

## Intent

- The bar is thin chrome. One overlay host (`PopupOverlayHost.qml`) owns all
  managed popups: at most one visible, host-owned focus/outside-click/scrim,
  popups request handoff rather than managing siblings. Transient surfaces
  (tooltip, OSD, toast, notification popups) are independent of that
  exclusivity.
- State ownership: shared/system state lives in singleton services; the
  Settings host owns snapshot-style theme data and preset/wallpaper
  orchestration; panes keep only local view state. One capability gets one
  write path — if a domain is service-owned, every surface talks to the
  service; if host-owned, panes emit intents and the host mutates. Quick
  Settings stays shallow: summary state, bounded toggles, jumps into Settings.
- The shell is intentionally pointer-first; no custom tab-order or
  Enter/Space activation contract is imposed on shell chrome.
- Reuse the shared interaction primitives in `components/` (WheelFlickable,
  HoverLayer, SliderTrack, the Anim family, ActionButton, ...) instead of
  reinventing hover/overscroll/slider behavior per view.
- QML never edits theme or Hyprland config files. Theme mutations go through
  the Settings host via `desktopctl theme`, serialized one backend write at a
  time (the theme and Hyprland write queues cross-gate); changes propagate on
  real command completion, not timers; backend failures surface as toasts, not
  console lines. Write-oriented services may stage optimistic values with
  rollback on real completion.

## Quirks

### A `var` array model resets its Repeater and kills in-flight drags
Reassigning a `var` array bound as a Repeater model cannot be diffed, so
`QQmlDelegateModel` destroys and recreates every delegate — taking the
`MouseArea` holding the pointer grab with it. This made brightness sliders
click-only: the service rebuilds `brightnessDevices` on every write, and the
first `moved` emission destroyed the delegate mid-gesture. Any view over a
service array rebuilt on write must key its model on the *count* and index
into the array; binding the array itself silently breaks drags and all
per-delegate state.

### Draggable controls inside a `WheelFlickable` need `preventStealing`
`Flickable` filters child mouse events and steals the grab once a drag passes
the threshold, reducing any child slider to click-to-set. `SliderTrack` sets
`preventStealing: true`; every future draggable control in a scroll view needs
the same flag — and plain buttons must *not* set it, since dragging across a
button is a legitimate scroll gesture.

### Risky display changes are staged and batch-applied, never live
Monitor drags edit a local cloned layout normalized to a `0x0` origin and apply
once on release as a single `hyprctl eval` chunk; resolution/transform/VRR/mirror
changes capture a snapshot and revert as one chunk if the confirm countdown
expires. Do not reintroduce per-pointer-move `hl.monitor` calls — they could
strand the session on an unreachable layout.

### Bar lifetime follows Hyprland's monitor model, not `Quickshell.screens`
Output churn (suspend, DPMS, hotplug) tears down the layer-shell surface while
Qt keeps a placeholder `QScreen` alive, so `Quickshell.screens` is not a
reliable "outputs gone" signal. `shell.qml` drives the bar through a Loader
keyed on Hyprland's real monitor list (filtering `FALLBACK`), refreshed on
`monitoradded`/`monitorremoved`.

### `desktopctl` resolves from the session PATH
Every `Process` invocation uses the bare `desktopctl` name; it must stay
installed via Home Manager or theme reads/writes fail with correct-looking
argv arrays.

Related: [[theming]], [[hyprland]], [[desktopctl]], [[focus-time]]
