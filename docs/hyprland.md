# Hyprland

## Intent

- Hyprland is configured in Lua; hyprlang was deprecated in 0.55 and Lua has
  no `source` escape hatch, so every file in the graph is Lua. `hypridle.conf`
  and `hyprlock.conf` belong to separate apps and stay hyprlang.
- The require order in `hyprland.lua` is contract: later files override
  earlier ones, and runtime override files come after what they override.
- Generated files are pure data tables (`return { ... }`). The module that
  requires one applies it and tolerates it absent or empty (Home Manager seeds
  empty = "no overrides").
- Not in the repo: theming writes `colors.lua`, `appearance-theme.lua`,
  `cursor-theme.lua` (and hyprlang `colors.conf` for hyprlock); `desktopctl
  hypr` writes `input-runtime.lua` and `displays-runtime.lua`; Home Manager
  picks `monitors.lua`, `env-host.lua`, `input-devices.lua` and
  `autostart-host.lua` from `hosts/<host>/` via `host.hyprland.*`, with
  fallbacks that boot on any host. Host files carry only GPU env and
  host-only settings.
- Ownership: theming and desktopctl never edit base config; Quickshell reaches
  Hyprland only through `hyprctl`/IPC; the daemon owns `hyprsunset`
  ([[sun-schedule]]); the wallpaper target owns `awww img`, autostart owns
  `awww-daemon`.
- Output placement and the primary output are runtime state: host
  `monitors.lua` carries modes only, `displays.lua` applies what desktopctl
  recorded, and desktopctl pins the numbered workspaces live.
- Hyprland is pinned to a release tag; hyprexpo comes from the maintained
  `sandwichfarm/hyprexpo` fork (`pkgs/hyprland-plugins/hyprexpo/`) because the
  official flake dropped it. Advance Hyprland only when the fork has a
  matching release, and re-pin `hyprland-plugins` with it.
- `hyprlock.conf` must read under every scheme, light or dark, and hyprlang
  cannot branch: every widget draws `$theme_fg` on a `$theme_bg` card, and
  colours without a contrast guarantee (`$theme_accent`, `$theme_yellow`) are
  outlines only, never text.

## Quirks

### hyprctl takes Lua now, and reports failure with exit code 0
`hyprctl dispatch X` runs `return hl.dispatch(X)`, so hyprlang-era strings
(`workspace 3`, `killactive`) fail; `hyprctl keyword` does nothing at all.
Both **exit 0** on failure with `error: ...` on stdout — callers must scan
stdout. Config (`hl.config`, `hl.monitor`, `hl.workspace_rule`) goes through
`eval`, dispatchers through `dispatch`; either one in the wrong verb answers
`ok` and does nothing.
- `hl.dsp.exec_raw(...)` returns `ok` and does nothing.
- No `hl.dsp.workspace(n)`: use `hl.dsp.focus({ workspace = n })`. Pointer
  warp is `hl.dsp.cursor.move({ x, y })`; `window.resize` takes pixels only.
- `window.fullscreen` ignores `window` and hits the active one;
  `fullscreen_state({ internal, client = -1, action, window })` honours it.
- A `window` key does not make a dispatcher quiet: floating, resizing or
  positioning a window on another workspace focuses that workspace. Only the
  silent workspace move leaves the view alone ([[session-restore]]).
- `hl.monitor` needs `disabled = false` spelled out to re-enable an output. A
  reload re-enables the lid-shut laptop panel, hence `lid-switch sync` in the
  laptop autostart.

### A partial `hl.monitor` merges via `eval` and *resets* in a config file
In a file it is a second rule and every unnamed field takes its default —
`scale = auto` silently rescaled the built-in panel on every reload. Generated
config must spell out every field.

### One monitor moving drags every `position = "auto"` output with it
`auto` re-resolves on every apply, so a layout write names a position for
every connected output.

### Plugin features live on `hl.plugin.*`, and closures never fire as binds
Titlebar buttons are `hl.plugin.hyprbars.add_button(...)`; a config key parses
and does nothing. Reload clears buttons but `hl.define_submap` appends. A bare
closure bound with `hl.bind` registers and **never fires**: bind
`hl.dsp.exec_cmd` running `hyprctl eval` instead. Nothing can trigger a bind
synthetically (`wtype`, `send_shortcut`, `send_key_state` all fail), and
`hyprctl binds` shows only `__lua`, so `keybinds.lua` is the only record and
bind changes are verified by hand.

### The config verifier lies about plugin keys
Only a nested Hyprland session is a trustworthy check.

### Workspace pins exclude their IDs even when the pinned monitor is absent
`findAvailableDefaultWS` skips IDs whose `monitor:` rule the output doesn't
match, so an undocked login lands on unreachable workspace 11. The daemon's
monitor watcher runs `reclaim_workspaces` on connect and on monitor changes;
reproduce with `hyprctl output create headless`.

### Session tokens and the activation environment
Exec children get `HL_INITIAL_WORKSPACE_TOKEN`; copied into the D-Bus/systemd
environment (with `XDG_ACTIVATION_TOKEN`/`DESKTOP_STARTUP_ID`) it sends portal
pickers and D-Bus-activated apps to workspace 1 forever. Portals started before
the env import come up broken. Hence autostart's first command: import, scrub,
then start the session target and portals.

### Files required before `plugins.lua` cannot name `hl.plugin.*` at parse time
The laptop overview gesture reaches hyprexpo from inside its callback.

### Host-selected fragments must be git-tracked before rebuilding
An untracked `hosts/*/` file becomes a dangling Home Manager link that
`hyprctl configerrors` reports as inaccessible.

### Per-device input blocks beat the shared runtime defaults
A mouse ignoring the Mouse settings page is hitting an `hl.device` block.

### A desktop-entry field code cannot survive `exec_cmd`
`%F` inside the quoted dispatch string is not expanded and reached `code`
literally, hence the `code-hypr` wrapper that quotes real argv.

### Window-rule matches drift
Polkit agent (title, no class), `Zoom Meeting`, Discord's updater: after
bumping these, check `hyprctl clients` with the window open.

### hyprlock
- Caps lock can only be a colour (`capslock_color`); unset, it falls back to
  `fail_color` and looks like a rejected password.
- Widgets sharing a `zindex` render in unspecified order; `background` is -1.
- `hyprlock --display no-such-display -c <path>` reports config errors and then
  dies before locking — the only check there is. Misspelled keys are skipped
  silently, and a nested session cannot preview it (screencopy wedges).
- Fingerprint auth is shared config; the desktop's fprintd D-Bus error at
  unlock is noise.

### Terminating the logind session used to strand SDDM on a blinking cursor
Vicinae's Log Out calls logind `TerminateSession`. The session scope sends
SIGHUP, which kills `sddm-helper` outright; Qt reports the signal number as the
exit code, and SIGHUP's 1 is `HELPER_AUTH_ERROR`, the one status after which
SDDM keeps the old greeter instead of starting a new one. The SDDM patch in
`overlays/local-packages.nix` maps any crash to `HELPER_OTHER_ERROR`. Without
it, only logouts where Hyprland exits on its own (`hl.dsp.exit`) bring the
greeter back.

### MX Master 2S smart-shift caps at 50
50 *is* always-ratcheted; higher values fail.

### `hyprland-guiutils` needs explicit Pango cflags on this input lock
Without the `guiutils` override in `overlays/hyprland.nix` the build fails on
`pango/pango-font.h`. Re-test a plain build after input bumps.
