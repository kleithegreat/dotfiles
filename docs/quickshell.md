# Quickshell

## Intent

- The design system is *structural*, never authored per widget. `Theme` maps the
  generated scheme onto named roles and hands them out unmodified — the scheme's
  own `fg`/`fg2`/`fg3`/`fg4` ramp, its own accent, its own status hues; the
  theming pipeline already guarantees that ramp's ordering and contrast floor
  ([[theming]]) and the shell does not get a second opinion. Only interaction
  states are computed, as alpha over the foreground, because no scheme ships
  them. `Metrics` holds the space, radius and size scales; `Motion` holds four
  durations and three curves. A constant that exactly one widget uses belongs at
  that widget or, far more often, nowhere. Widgets never reach for palette slots
  directly.
- Chrome is glass over the compositor's blur; dense content sits on opaque cards
  inside it. Translucency stacked on translucency is mud, and translucency
  without blur is unreadable rather than atmospheric — so the glass alphas must
  stay above `ignore_alpha` in `config/hypr/rules.lua`, and the material falls
  back to opaque when the compositor reports blur off.
- At most one managed surface is open, expressed as one name in `ShellState`.
  Exclusivity is structural, not coordinated. The overlay owns focus, outside
  click dismissal and the scrim; its input mask excludes the bar strip so bar
  buttons keep working while a surface is open.
- Surfaces grow from the control that summoned them: bar items report their
  screen-centre x and the popover scales from that origin.
- The shell occupies exactly one output, and every window it owns names that
  same output. Which one it is comes from the daemon ([[desktopctl]]); the
  shell has no second rule for it. Left unnamed a surface defaults to
  `Quickshell.screens[0]`, and since popovers grow from bar-item coordinates a
  mismatch opens them at the right spot on the wrong display.
- Services own system state and expose values. They never compose display
  sentences and never render; presentation composes text from service state. One
  capability gets one write path.
- Capability decides visibility. A control this host cannot support is absent,
  not shown disabled.
- QML never edits theme or Hyprland config files. Every mutation is a
  `desktopctl` call on a single serialised queue — the Hyprland appearance
  values *are* theme-state keys, so there is one queue, not two that cross-gate
  — staged optimistically and rolled back on real completion. Backend failures
  surface as toasts, never console lines. All `hyprctl` traffic goes through the
  `Compositor` gateway, which exists because hyprctl reports failure on stdout
  while exiting 0 ([[hyprland]]).
- State flows the other way over the `Desktopctl` service's subscribed socket:
  the daemon pushes a snapshot per topic and change events after each commit,
  so external changes (hotkeys, terminal) reach the shell without polling.
  Reconnect-with-backoff in that service is load-bearing — the daemon and the
  shell start concurrently, and the shell restarts alone. Services keep a
  one-shot startup status read as the degraded path while the daemon is down.
- The IPC target and function names are a published interface, not internal
  naming: `config/hypr/keybinds.lua` calls them, and that file reaches the
  session through Home Manager, so a rename leaves the keybinds dead until the
  next rebuild. Bar items publish where they sit (`ShellState.setOrigin`) so a
  surface opened from a keybind still grows from the button it belongs to.
- The shell is pointer-first. No tab-order or keyboard-activation contract is
  imposed on chrome beyond Escape closing the open surface.

## Quirks

### A `var` array model resets its Repeater and kills in-flight drags
Reassigning a `var` array bound as a Repeater model cannot be diffed, so
`QQmlDelegateModel` destroys and recreates every delegate — taking the
`MouseArea` holding the pointer grab with it. This made brightness sliders
click-only: the service rebuilds its device array on every write, and the first
`moved` emission destroyed the delegate mid-gesture. Any view over a service
array rebuilt on write must key its model on the *count* and index into the
array; binding the array itself silently breaks drags and all per-delegate
state.

### One scroll gesture, two implementations, two speeds
`Scroll` and `Choice` both glide the wheel to a target by `Metrics.wheelStep`.
When `Scroll` accepted only `PointerDevice.Mouse`, touchpad scrolling fell
through to `Flickable`'s own wheel handling instead — a different curve, scaled
again by `input:touchpad:scroll_factor`, and damped by a `flickDeceleration`
well above Qt's default. The pane crawled while the option strip inside it
zipped along. Both handlers accept both devices now; a device one of them
handles and the other declines will read as one of them being broken.

### Draggable controls inside a `Scroll` need `claimsDrag`
`Flickable` filters child mouse events and steals the grab once a drag passes
the threshold, reducing any child slider to click-to-set. `Slider.claimsDrag`
sets `preventStealing`; every draggable control in a scroll view needs it — and
plain buttons must *not*, since dragging across a button is a legitimate scroll
gesture.

### Risky display changes are staged and batch-applied, never live
The display pane accumulates edits and applies them as one `hyprctl eval` chunk
covering *every* connected output (see [[hyprland]] on `position = "auto"`),
then runs a confirm countdown that re-applies the captured snapshot if it
expires. Do not reintroduce per-control or per-pointer-move writes — they can
strand the session on a layout the display cannot show. The main-display toggle
is deliberately outside that flow: it cannot leave you unable to see a screen,
so there is nothing for a countdown to rescue.

### Bar lifetime follows Hyprland's monitor model, not `Quickshell.screens`
Output churn (suspend, DPMS, hotplug) tears down the layer-shell surface while
Qt keeps a placeholder `QScreen` alive, so `Quickshell.screens` is not a
reliable "outputs gone" signal. `shell.qml` drives the bar through a Loader
keyed on Hyprland's real monitor list (filtering `FALLBACK`).

### A window whose `visible` is extended by a signal handler unmaps first
`visible: open || linger.running`, with the linger restarted from a
`currentChanged` handler, is a flicker, not a lifetime: the binding
re-evaluates in the pass that closes the surface — one pass before the handler
can extend it — so the layer surface unmaps and immediately remaps, and the
compositor animates that second map in. It looks exactly like the panel
popping back for a moment after you dismissed it, and it is visible on
Hyprland's event socket as `closelayer` / `openlayer` on the same namespace.
A window's visibility has to be one property that nothing else can drive
false.

### A missing binary fails to *start*, which never emits `exited`
Backend probes must run in parallel and resolve by priority, never chain on each
other's exit codes. `Power` probes `laptop-power-profile`, `powerprofilesctl`
and the cpufreq governor at once: a chained version stalls forever on the first
backend that is not installed, and every later one is silently never tried —
with no failing command to point at.

`laptop-power-profile` ships on every host (it is part of `desktopctl`), so
the `laptop-helper` backend is selected by the probe printing a profile, not
by the binary existing. On non-hybrid CPUs it exits non-zero with empty
stdout, leaving `_helperProfile` empty so the `ppctl` backend wins and the
"Efficiency Cores" tile stays hidden.

### Battery sysfs reports a charge interval even when the cap is off
`/sys/class/power_supply/BAT0/charge_control_{start,end}_threshold` exposes the
*stored* Dell custom interval whatever the active charging mode is: it reads
`75`/`80` while the firmware sits in `primarily_ac` and happily charges to 100%.
Whether the cap is actually engaged lives in the mode, which only
`smbios-battery-ctl --get-charging-cfg` reports. That is why `Power` shells out
for a value sysfs appears to hand over for free.

### Monitor-button brightness changes have no event source
The 30s DDC-enumerating brightness poll is gone; brightness state arrives as
daemon events, and nothing watches the monitor's own OSD buttons. A change made
on the monitor itself surfaces only at the next daemon-side brightness
operation. Accepted trade-off — do not reintroduce the poll for it.

### Singletons are constructed on first reference
A service that polls or holds a subscription does not exist until something
reads it, so it never starts if the only reader is a surface that has not been
opened yet. `shell.qml` touches those services in `Component.onCompleted`; that
block is load-bearing, not defensive.

### A tray icon the theme lacks loads *successfully* as a magenta checkerboard
`Image.status` reports `Ready` for the icon theme's missing-icon placeholder, so
status cannot detect the failure — the bar renders a magenta and black grid.
Themed names have to be tested with `Quickshell.iconPath(name, true)` before the
image is requested, and fall back to a monogram.

### The exclusive zone excludes the surface's own margin
Layer-shell reserves `margin + exclusive_zone`, so a bar that sets its exclusive
zone to height *plus* its top margin reserves that margin twice and leaves twice
as much air below the bar as above it. The zone is the bar's height and nothing
else; `hyprctl monitors -j` reports the total under `reserved`.

### A scrim below `ignore_alpha` turns the panel edge into a blur boundary
The modal backdrop has to be opaque enough for the compositor to blur it, or the
blurred panel meets a sharp desktop at its own outline and the material stops
reading as a material. Surfaces that are menus rather than modals — the session
menu — take no scrim at all, so nothing behind them changes.

### Mapping functions in bindings never re-evaluate
`mapToItem`/`mapToGlobal` are calls, not reactive expressions, so a property
bound to one captures the geometry the item had while it was still being built:
zero. Bar items therefore expose `anchorPoint()` and callers ask at click time.
Bound instead, every surface silently opens at the far left of the screen.

### A new QML file needs a restart, not a reload
Hot reload re-reads files it already knows about; a file added to a directory
module is not in the generated qmldir yet, so it reloads cleanly and then fails
with "X is not a type". Restart quickshell after adding a file.

### Platform menus need QApplication mode, so tray menus are drawn here
`QsMenuAnchor.open()` refuses to run unless the shell was started with
`//@ pragma UseQApplication`, and what it opens is a Qt widget menu wearing
whatever qt6ct hands it. `TrayMenu` renders the same DBus model through
`QsMenuOpener` with the shell's own rows instead, and drills into submenus in
place rather than cascading.

### A pane behind a Loader URL is outside the reload graph
Hot reload re-reads the files it can see through imports. A settings pane is
reached through `Loader.source`, so the engine keeps its cached component and
edits to it appear to do nothing — the config reloads, cleanly, and the old pane
comes back. Restart after editing a pane.

### `ping` reports its summary on SIGINT, not on SIGKILL
The bufferbloat measurement pings the gateway *during* a transfer and reads the
rtt line afterwards. A plain `kill` gets no summary at all, so the loaded
latency silently reads as unmeasured and the ratio never appears; the background
ping has to be stopped with `kill -INT`.

### Popover content declares its own height
`Popover.contentHeight` is set by each surface. Deriving it from the holder that
the surface fills makes the holder's height depend on the panel that depends on
the holder; QML resolves that by giving the panel a height of zero, which
renders as content spilling out of a panel with no visible background.

Related: [[theming]], [[hyprland]], [[desktopctl]], [[focus-time]]
