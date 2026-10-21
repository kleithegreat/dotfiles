# Quickshell

## Intent

- The design system is structural. `Theme` maps the scheme onto roles and
  hands them out unmodified — the theming pipeline already guarantees the
  ramp ([[theming]]); only interaction states are computed, as alpha over the
  foreground. `Metrics` holds space, radius and size scales, `Motion`
  durations and curves. A one-widget constant lives at that widget, or
  nowhere. Widgets never reach for palette slots.
- Panels are opaque. Only the bar and the modal scrim are translucent, and
  their alphas stay above `ignore_alpha` in `config/hypr/rules.lua` or they
  lose blur. Menus (the session menu) take no scrim.
- At most one managed surface is open: one name in `ShellState`. The overlay
  owns focus, outside-click dismissal and the scrim; its mask excludes the bar.
- Surfaces grow from the control that summoned them. Bar items publish their
  origin (`ShellState.setOrigin`), so a keybind-opened surface grows from its
  button too.
- The shell lives on exactly one output, chosen by the daemon
  ([[desktopctl]]), and every window names it; an unnamed window defaults to
  `screens[0]`.
- Services own state and expose values; presentation composes text. One
  capability, one write path. A control the host cannot support is absent,
  not disabled.
- QML never edits config files. Every mutation is a `desktopctl` call on one
  serialised queue, staged optimistically and rolled back on real completion;
  failures surface as toasts. All `hyprctl` goes through `Compositor`
  ([[hyprland]]: failures exit 0).
- State arrives over `Desktopctl`'s subscription, never by polling.
  Reconnecting is load-bearing: daemon and shell start concurrently and
  restart independently. A one-shot status read is the degraded path.
- IPC target and function names are a published interface:
  `config/hypr/keybinds.lua` calls them and only changes on rebuild.
- Pointer-first: no keyboard contract beyond Escape closing the surface.
- Monitor-button brightness changes are not watched; do not add a poll.

## Quirks

### A `Socket` whose connect failed is dead for good
Setting `connected` again is a no-op while the failed socket exists, so
`Desktopctl` recreates the Socket per attempt. A local socket connects
synchronously inside the assignment, before the handler is wired, so the
subscribe is written from `ready`.

### A `var` array model resets its Repeater and kills in-flight drags
A reassigned array can't be diffed; every delegate is recreated, taking the
pointer grab with it. Views over arrays rebuilt on write key the model on the
*count* and index into the array.

### Wheel scrolling bypasses Flickable's bounds
`Scroll` and `Choice` animate `contentY`/`contentX` from a `WheelHandler`; the
rubber band is `Metrics.resist`, released by a timer. Both must share the curve
and devices, or one looks broken.

### Draggable controls inside a `Scroll` need `claimsDrag`
Otherwise Flickable steals the grab and sliders become click-to-set. Buttons
must not claim it: dragging across one is a legitimate scroll.

### Risky display changes are staged and batch-applied, never live
One `hyprctl eval` chunk covering every output, then a countdown that reverts
unless kept. Per-control writes can strand the session on an unviewable
layout. Applying scrolls to the confirm card: a countdown nobody sees always
reverts, which reads as Keep being broken. The main-display toggle cannot
blind you, so it skips the flow.

### Bar lifetime follows Hyprland's monitor list, not `Quickshell.screens`
Qt keeps placeholder `QScreen`s through output churn.

### A window's visibility must be one property nothing else can drive false
`visible: open || linger.running` with the linger restarted from a handler
unmaps one pass before the handler runs, then remaps with animation — the
panel pops back after dismissal (`closelayer`/`openlayer` on the event socket).

### A geometry animation on a window that unmaps replays when it maps
A `Behavior` queued while hidden runs in full on map, so hints slid across the
screen. Geometry is placed while hidden and animated only while shown; those
`enabled:` guards are load-bearing, and the clamp uses the screen's width.

### A missing binary never emits `exited`
State a probe would set defaults to "absent", and probes never chain on
another's exit code — the chain stalls silently at the first missing binary.

### Battery sysfs reports a charge interval even when the cap is off
The thresholds show the stored interval in any mode; only
`smbios-battery-ctl --get-charging-cfg` says whether the cap is engaged.

### Singletons are constructed on first reference
`shell.qml` touches polling/subscribing services in `Component.onCompleted`;
that block is load-bearing.

### A missing tray icon loads *successfully* as a magenta checkerboard
`Image.status` is `Ready` for the placeholder; test names with
`Quickshell.iconPath(name, true)` first and fall back to a monogram.

### The exclusive zone excludes the surface's own margin
Layer-shell reserves `margin + exclusive_zone`; the zone is the bar height only.

### Mapping functions in bindings never re-evaluate
A binding on `mapToItem`/`mapToGlobal` captures zero; bar items expose
`anchorPoint()` for callers to ask at click time.

### Reload sees neither new files nor Loader-URL panes
A new file is not in the generated qmldir until a restart (`nrs` restarts the
shell when its files moved). Settings panes are reached through
`Loader.source`, so their edits also need a restart.

### A sibling type resolves only in a directory imported as a module
`ui/` files use siblings bare because `qs.ui` is imported elsewhere.
`surfaces/settings/` is never imported, so a component added there fails with
"X is not a type" even after a restart. Shared components go in `ui/`.

### A polkit prompt raised from a shell surface cannot be answered
The dialog opens under the layer surface and the action hangs. Every
privileged call needs a polkit rule in the host module in the same change —
`fprintd-delete` needs `setusername` as well as `enroll`.

### Tray menus are drawn here
`QsMenuAnchor.open()` needs `UseQApplication` and opens a qt6ct-styled widget
menu; `TrayMenu` renders the model through `QsMenuOpener` instead.

### `ping` reports its summary on SIGINT, not SIGKILL
The bufferbloat ping must be stopped with `kill -INT`.

### A layer surface's own buffer clips its shadow
Windows holding a floating `Surface` reserve `Surface.shadowPad` and pull their
margin back by it; `Metrics.shadowReach` derives from `elevation`. The bar
uses the fixed `Metrics.barShadowPad`. The padding needs a `mask` or it eats
desktop clicks.

### `layer.enabled` on a `Surface` clips its shadow
The layer renders at the item's size, so the shadow vanishes for the whole
entrance animation. `Surface.flatten` layers the content instead;
`layer.sourceRect` darkens the panel rather than fixing it.

### Popover content declares its own height
Deriving it from the holder is a binding loop QML resolves to zero height.
