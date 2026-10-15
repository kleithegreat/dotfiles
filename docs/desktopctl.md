# desktopctl

## Intent

- One Rust binary owns the desktop glue; its daemon is the single writer of
  all mutable desktop state (theme, hypr override files, brightness, night
  light, the window session). CLI write subcommands are socket clients that
  hard-fail when the daemon is unreachable — never a second writer.
- Exceptions: `theme sync` runs in-process because Home Manager activation has
  no session; `toggle-float`, `lid-switch` and `reclaim-workspaces` persist
  nothing and must work with the session locked or the daemon dead. Status
  reads prefer the daemon but fall back to direct reads.
- Subscribers get a snapshot per topic, then change events after each commit.
  A snapshot may span events (brightness sends DDC devices after enumeration,
  so the slider never waits a second to exist), so subscribers merge by device.
- Versioned theming data resolves from `DESKTOPCTL_DATA`, the package's own
  store copy, so a `git checkout` cannot change what a session renders. The
  fallback `<DESKTOPCTL_REPO>/styling` is the authoring path. `DESKTOPCTL_REPO`
  otherwise survives only for the gitignored wallpapers.
- The daemon is a `graphical-session.target` user service: supervised, ordered
  and journaled. Auxiliary subsystems fail alone; only the socket server
  exiting ends the process.
- The daemon alone decides the primary output, stored as a selector (empty =
  largest external, else the built-in) and published resolved. Quickshell reads
  it rather than deriving it, because it also decides workspace ownership.
- Applying a layout and persisting it are separate: the display pane applies
  through `hyprctl` so its countdown can revert; only a kept layout is written.
  Each output stores its *whole* spec (a file omission resets, see
  [[hyprland]]), and stored outputs merge, so an unplugged display keeps its
  entry.
- Keep new logic in small pure helpers with tests; the subprocess choreography
  around `hyprctl`, `hyprsunset`, `brightnessctl` and `ddcutil` should not grow.

## Quirks

### ddcutil: `--bus`, never `--display`; checks only on `detect`
`--display` re-runs full detection per call (~1s vs ~0.1s), so DDC devices are
keyed on the bus from `detect --brief`, re-read every status because buses
move. An empty detect is final; only a failed one falls back to bus-less
probing. Reads and writes pass `--skip-ddc-checks`; `detect` keeps them because
classifying buses is their job. `--noverify` stays off despite `man ddcutil`:
verification failure is what triggers Quickshell's corrective refresh.

### A brightness slider jumping backward is a racing read
Look for a status read or event describing a pre-write world;
`services/Brightness.qml` guards both.

### A busy daemon is not an unreachable one
The fallback covers a *dead* daemon. A `brightness status` colliding with a
subscriber's ~1s DDC snapshot times out with exit 1 and **empty stdout**;
treating that as "no devices" makes a transient permanent, so `Brightness.qml`
keeps its last list on a failed read.

### External monitor brightness needs DDC/CI plus i2c access
DDC/CI on in the monitor OSD, `ddcutil detect` sees it, and the user is in
`i2c` after a rebuild *and fresh login*.

### Workspace rules never move a workspace that already exists
Re-pinning must re-issue the rule *and* `hl.dsp.workspace.move` each one,
through different hyprctl verbs.

### `--wait-daemon` waits for desktopctl's daemon, not awww's
`awww img` exits at once if awww's socket is missing, and even a bound socket
may have no output yet ("none of the requested outputs are valid"). The
wallpaper target waits until `awww query` lists an output; a `sleep` in
autostart is not a substitute.
