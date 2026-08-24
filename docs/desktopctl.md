# desktopctl

## Intent

- One Rust binary owns the desktop glue: `daemon` (focus tracker, monitor
  watcher, solar scheduler, Unix-socket server, and the state controllers),
  the theming pipeline (`theme`), `brightness`, Hyprland helpers (`hypr`),
  the night-light client, and `launch-quickshell`.
- The daemon is the single writer of all mutable desktop state: theme state,
  the hypr override files, brightness dim/restore, and `hyprsunset`
  ([[sun-schedule]]). CLI write subcommands are thin socket clients that
  hard-fail when the daemon is unreachable — they must never become a second
  writer. Quickshell and keybinds are request surfaces.
- Deliberate exceptions to strict daemon routing: `theme sync` keeps a direct
  in-process path because Home Manager activation runs it with no session;
  the hyprctl-only helpers (`toggle-float`, `lid-switch`,
  `reclaim-workspaces`) stay direct because they persist nothing and must
  work with the session locked or the daemon dead; `list-*`, `sun status`,
  and `launch-quickshell` are reads or launchers. Status reads go through the
  daemon for a consistent snapshot but fall back to direct reads so a dead
  daemon can still be debugged.
- The socket pushes change events (`theme`, `night_light`, `brightness`,
  `hypr_input` topics) to subscribed connections, each preceded by a
  snapshot; events publish only after a successful commit. Quickshell
  subscribes instead of polling ([[quickshell]]). Write subcommands accept
  `--wait-daemon` for autostart call sites that race the daemon's own spawn.
- Versioned theming data — scheme catalog, presets, concat bases, the state
  seed — resolves from `DESKTOPCTL_DATA`, which the package wraps to its own
  store copy. A deployed session therefore never reads the working tree, and a
  `git checkout` cannot change what it renders. The fallback,
  `<DESKTOPCTL_REPO>/styling` (in turn defaulting to `~/repos/dotfiles`), is
  the authoring path: it is what makes a new scheme visible before a rebuild.
  `launch-quickshell` follows the same rule through the Home Manager-deployed
  config at `$XDG_CONFIG_HOME/quickshell`.
- `DESKTOPCTL_REPO` survives only for wallpapers, which are gitignored user
  assets rather than versioned data the closure can pin.
- The daemon runs as `systemd.user.services.desktopctl`, wanted by and part of
  `graphical-session.target` (started and stopped by `config/hypr/autostart.lua`,
  which exports the session environment to systemd first). It is supervised
  because everything else hard-fails without it; an autostart line gave no
  restart, no ordering and no journal.
- Auxiliary subsystems (focus tracker, monitor watcher, solar scheduler) have
  their own failure domain: they are reported and survived, never fatal. Only
  the socket server exiting ends the process, which is what `Restart=on-failure`
  then acts on.
- `desktopctl hypr` writes only its own generated override files
  (`input-runtime.lua`, `animations-override-data.lua`,
  `displays-runtime.lua`) — never the static or host-selected fragments they
  layer on top of.
- The daemon is the only thing that decides which output is primary. Hyprland
  has no such concept, so the choice is stored as a monitor selector (empty =
  automatic, meaning the largest external and the built-in panel only when it
  is alone) and published resolved, as a connector name. Quickshell reads that
  answer rather than deriving one, because the same choice also decides which
  output owns the numbered workspaces — two rules that agree today would
  disagree the first time either changed.
- Applying a layout and persisting it are separate on purpose. The display
  pane applies through `hyprctl` so its confirm countdown can take a layout
  straight back off; only the layout the user kept is written to
  `displays-runtime.lua`, and only that one survives a reload.
- What is stored per output is the *whole* spec — mode, position, scale, vrr,
  transform, disabled — never the subset that changed, because the generated
  file is re-read at config-parse time where an omitted field resets rather
  than persists ([[hyprland]]). The shell's runtime expression and this
  file must keep naming the same fields.
- Stored outputs are merged, never replaced. The entry for a display that is
  unplugged right now is exactly the one worth keeping for when it comes
  back, so keeping a layout while it is away must not forget it.
- State mutations persist only after the required target apply succeeds, write
  only the mutated keys (per-key upserts in one transaction), and replace
  files atomically. See [[theming]] for the full contract.
- Keep new logic in small pure helpers with unit tests; the subprocess
  choreography around `hyprctl`, `hyprsunset`, `brightnessctl`, and `ddcutil`
  is integration-bound and should not grow.

## Quirks

### `ddcutil --display` costs ~10x what `--bus` costs — never reintroduce it
`--display <n>` is not an address: ddcutil re-runs full display detection on
every invocation, probing every I2C bus including ones that fail DDC checks.
Measured on the BenQ at `/dev/i2c-15`: ~0.99s get / ~1.61s set via
`--display`, vs ~0.10s / ~0.15s via `--bus`. `brightness.rs` therefore keys
DDC devices on the I2C bus parsed from `ddcutil detect --brief`, re-read on
every status call because bus numbers can move across reboots and hotplug.

### `--skip-ddc-checks` everywhere except `detect`
Reads and writes pass `--skip-ddc-checks` (a write drops 0.148s → 0.082s);
`detect --brief` deliberately keeps the checks, because classifying which
buses are usable is exactly what they do — skipping them there could put a
phantom slider in the shell.

### `--noverify` is rejected, not forgotten
It saves ~15ms, below perception, and verification is the only mechanism that
reports a rejected or clamped write — Quickshell no longer reads brightness
back after a write, so a non-zero exit from failed verification is what
triggers its corrective refresh. Note `man ddcutil` claims `--noverify` is the
default; measurement shows it is not (matching `--help`).

### A brightness slider jumping backward is a racing read, not a slow monitor
The BenQ reports a written value back correctly ~100ms after the write. When a
slider snaps to an old value, look for a status read or pushed event describing
a pre-write world — `services/Brightness.qml` guards both: the epoch pair on
status reads, and dropping daemon events while its own writes are queued.

### External monitor brightness needs DDC/CI plus i2c access
If a monitor's slider is missing or dead: check the monitor OSD has DDC/CI
enabled, `ddcutil detect` sees the display, and the user is in the `i2c`
group after a rebuild *and fresh login*.

### Workspace *rules* alone never move a workspace that already exists
Pinning workspaces 1-10 to a new primary output places workspaces created
afterwards and does nothing to the ones on screen — which reads as the pin
silently failing. Reconciling has to re-issue the rule *and* dispatch
`hl.dsp.workspace.move` for each one, and the two go through different hyprctl
verbs ([[hyprland]]).

### `--wait-daemon` waits for desktopctl's daemon, not awww's
Applying a wallpaper at login races two unrelated daemons. `--wait-daemon`
covers the desktopctl socket only; awww-daemon binds its own socket at
`$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY-awww-daemon.sock` roughly 0.8s after it
spawns, and `awww img` exits immediately when that socket is missing instead
of retrying. Reading `--wait-daemon` as covering both is the natural wrong
conclusion, and it makes a wallpaper that silently fails to apply on login
look unrelated to the flag. The wallpaper target polls that socket itself in
`apply_wallpaper`; a `sleep` in the autostart line is not a substitute,
because it guesses a delay that measurement already contradicts.

Related: [[theming]], [[sun-schedule]], [[hyprland]], [[quickshell]], [[focus-time]]
