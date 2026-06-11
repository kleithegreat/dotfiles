# desktopctl Specification

This spec describes the current contract of the `desktopctl` binary as it
exists today. It is intentionally descriptive: where the implementation still
has rough edges or split ownership, this file names them directly instead of
describing an intended future migration.

## Scope

| Surface | Current contract |
| --- | --- |
| `desktopctl daemon` | Long-lived foreground process that starts the focus tracker, solar scheduler, and Unix-socket server |
| `desktopctl theme ...` | Theming CLI that reads and writes the shared theme state, applies generated outputs, and manages presets |
| `desktopctl brightness ...` | Short-lived helpers for multi-device brightness status, perceptual stepping, dimming, restoring, and Quickshell brightness OSD notification |
| `desktopctl hypr ...` | Hyprland helper surface for `toggle-float`, laptop lid-switch output policy, managed shared input settings, and generated animation/keybind override files |
| `desktopctl launch-quickshell` | Reads cursor env overrides from `~/.config/hypr/cursor.conf`, then launches Quickshell against the repo checkout |
| `desktopctl night-light ...` | CLI client for daemon-owned `hyprsunset` override state and fallback status reporting |
| `desktopctl sun status` | Read-only solar-status inspection surface |

## Runtime Paths

| Path | Owner | Purpose |
| --- | --- | --- |
| `$XDG_DATA_HOME/desktopctl/desktopctl.db` | `desktopctl` | Shared SQLite store for theme state and focus-time data |
| `~/.local/share/desktopctl/desktopctl.db` | `desktopctl` | Database fallback when `XDG_DATA_HOME` is unset |
| `$XDG_RUNTIME_DIR/desktopctl.sock` | `desktopctl daemon` | Unix socket for newline-delimited JSON requests |
| `/run/user/$UID/desktopctl.sock` | `desktopctl daemon` | Socket fallback when `XDG_RUNTIME_DIR` is unset |
| `$XDG_RUNTIME_DIR/focustime_state.json` | `desktopctl daemon` | Focus-time summary consumed by Quickshell |
| `$XDG_RUNTIME_DIR/desktopctl/dim-screen-ddc-state` | `desktopctl brightness` | Per-user DDC/CI dim/restore state |
| `$XDG_CACHE_HOME/sun-schedule/location.json` | `desktopctl sun` / daemon | Cached latitude/longitude for solar scheduling |
| `$XDG_CACHE_HOME/desktopctl/wallpaper-previews/*.png` | `desktopctl theme list-wallpapers` | Cache-backed wallpaper preview images consumed by Quickshell |
| `~/.config/hypr/input-runtime.conf` | `desktopctl hypr input` | Persisted shared Hyprland mouse defaults layered after `input.conf` and `input-devices.conf` |
| `~/.config/hypr/animations-override.conf` | `desktopctl hypr animations` | Persisted animation overrides layered after `appearance.conf` |
| `~/.config/hypr/keybinds-override.conf` | `desktopctl hypr keybinds` | Persisted keybind overrides layered after `keybinds.conf` |
| `~/repos/dotfiles` | `desktopctl` helpers | Default repo-root fallback for Quickshell launch and repo-relative helper paths |

Additional path rules:

- `paths::repo_root()` first honors `DESKTOPCTL_REPO`, then the legacy
  lowercase `desktopctl_REPO`, then falls back to `~/repos/dotfiles`.
- `desktopctl hypr input status` layers `~/.config/hypr/input.conf` defaults
  with any managed overrides found in `~/.config/hypr/input-runtime.conf`.
- `desktopctl theme list-wallpapers --json` caches scaled preview images under
  `$XDG_CACHE_HOME/desktopctl/wallpaper-previews/`, keyed by wallpaper path,
  file metadata, and the fixed preview bounds used for Quickshell cards. Each
  listing best-effort evicts cached preview files the current listing does not
  reference; previews for other directories regenerate on the next browse.
- `launch-quickshell`, brightness OSD notifications, and repo-relative concat
  target base paths all depend on that repo-root resolution when they need the
  repo's `config/` tree.
- `sun-schedule/location.json` is a GeoClue cache. `desktopctl` uses it without
  refreshing only while the file mtime is no more than six hours old; after
  that it tries `where-am-i` and keeps the stale cache only as a fallback when
  live location lookup fails.

## Ownership Boundaries

| Concern | Current owner | Notes |
| --- | --- | --- |
| Live `hyprsunset` process lifecycle | `desktopctl daemon` night-light controller | Quickshell and Hyprland request mode changes through `desktopctl night-light ...`; they do not spawn `hyprsunset` directly |
| Persisted theme state | `desktopctl theme` | Stored in the `theme_state` table inside `desktopctl.db` |
| Scheduled `dark_hint` reconciliation plus edges at 23:00 and 06:00 local time | `desktopctl daemon` via `theme::set_dark_hint()` | See `docs/sun-schedule/SPEC.md` (Ownership Boundaries) for the canonical `dark_hint` schedule contract; manual `theme set dark_hint` / preset writes remain a separate supported path |
| Persisted Hyprland mouse defaults | `desktopctl hypr input` | Stored in `~/.config/hypr/input-runtime.conf`, applied live through `hyprctl keyword`, and rolled back if the live apply fails |
| Persisted Hyprland animation overrides | `desktopctl hypr animations` | Stored in `~/.config/hypr/animations-override.conf` and reloaded through `hyprctl reload` |
| Persisted Hyprland keybind overrides | `desktopctl hypr keybinds` | Stored in `~/.config/hypr/keybinds-override.conf` and reloaded through `hyprctl reload` |
| Focus-time SQLite writes and JSON summaries | `desktopctl daemon` focus tracker | Quickshell is read-only for this data |
| Generated theme outputs and runtime side effects | `desktopctl theme` targets | Includes files under `~/.config`, dconf writes, cursor updates, wallpaper apply, and editor/shell state files |
| Quickshell requests | Quickshell | Quickshell services and the settings host are only requesters; they call `desktopctl` and do not mutate theme state themselves |

Important current behavior:

- `hyprsunset` has a single live arbiter in the daemon.
- `dark_hint` does not; see `docs/sun-schedule/SPEC.md` for the split-ownership
  contract between the daemon's scheduled writes and direct theme writes.
- Persisted `theme_state` rows and legacy `themes/state.json` imports that are
  missing newly added required keys are backfilled from compiled defaults and
  then rewritten through the SQLite-backed theme-state path.
- `theme set color_scheme ...` and presets that change `color_scheme` preserve
  the current persisted `dark_hint` unless `dark_hint` is set explicitly in the
  same mutation.

## Command Surface

### `desktopctl daemon`

- Runs in the foreground.
- Starts three subsystems together:
  - focus tracker
  - solar scheduler
  - Unix-socket server
- Shuts down on `SIGTERM` or `SIGINT`, exiting with status 0 on clean
  signal-driven shutdown; it exits nonzero only when a task fails or exits
  unexpectedly while the daemon is not shutting down.
- Recomputes solar status early on `SIGUSR1`.

### `desktopctl theme`

Apply scopes:

| Command | Current behavior |
| --- | --- |
| `theme all` | Applies every registered target in the orchestrator's stable order, with command targets after file-writing targets |
| `theme sync` | Applies only `sync_safe` targets and skips runtime-only reload hooks |
| `theme colors` | Applies the color-dependent target set |
| `theme fonts` | Applies the font-dependent target set |
| `theme wallpaper` | Applies only the wallpaper target |
| `theme cursor` | Applies only the cursor target |
| `theme target <name>` | Applies one registered target by name |

State mutation:

| Command | Current behavior |
| --- | --- |
| `theme set <key> <value>` | Validates one state key, applies only the affected targets, and persists the new state only if that apply succeeds. Setting `color_scheme` preserves the current `dark_hint` unless `dark_hint` is part of a separate explicit write. |
| `theme preset <name>` | Loads one preset patch, merges it into current state, applies all targets, and persists the merged state only if that apply succeeds. If the preset omits `dark_hint`, the merged state preserves the current hint even when `color_scheme` changes; an explicit preset `dark_hint` still applies directly through the theming module afterward. |
| `theme save-preset <name> <json>` | Writes one preset JSON object with canonical key ordering via atomic replacement |
| `theme delete-preset <name>` | Removes one preset file |

Inspection:

| Command | Current behavior |
| --- | --- |
| `theme status [--json]` | Prints the current canonical theme state |
| `theme list-schemes [--json]` | Lists color-scheme files in filename order for both human and `--json` output; `--json` returns scheme preview objects with identity, appearance, named colors, and terminal palette entries for UI consumers |
| `theme list-wallpapers [--json] [--directory <path>]` | Lists supported wallpaper files from the current wallpaper directory or an explicit directory; `--json` returns filename-ordered entries with absolute source paths plus cached preview paths for UI consumers |
| `theme list-presets [--json]` | Lists preset files in filename order for both human and `--json` output |

Theming invariants:

- `theme status --json` is the authoritative machine-readable view of persisted
  theme state.
- Loading persisted theme state backfills any newly required keys from compiled
  defaults before validation and rewrites the upgraded row set to SQLite.
- `theme list-schemes --json` is the machine-readable scheme-preview inventory
  consumed by Quickshell theme selectors.
- `theme list-wallpapers --json` is the machine-readable wallpaper inventory
  consumed by the Quickshell wallpaper browser, and its preview paths point to
  cache-backed scaled images rather than the original wallpaper files.
- Presets are partial patches, not full-state snapshots.
- `theme sync` is the activation-time safe subset; it is intentionally narrower
  than `theme all`.
- State mutations that change `color_scheme` preserve the current `dark_hint`
  unless `dark_hint` is part of the same explicit mutation.
- `theme set`, `theme preset`, and `theme::set_dark_hint()` only persist state
  after the required target application succeeds; failed applies leave the
  stored state unchanged.
- Generated theme files and preset JSON are replaced atomically so consumers do
  not observe truncated writes.
- `dark_hint` persists through the theme pipeline even when the daemon is the
  caller.

### `desktopctl brightness`

| Command | Current behavior |
| --- | --- |
| `brightness status [--json]` | Auto-detects the primary brightness backend and prints the current value; JSON output includes the primary availability/kind/label/raw/fraction/percent fields plus a `devices` array for every readable backlight and DDC/CI brightness device Quickshell can render |
| `brightness set <percent> [--device <name>]` | Sets an absolute perceived brightness percent through the selected backend and best-effort notifies Quickshell by calling `qs -p <repo>/config/quickshell ipc call brightness osd <percent>` with the actual applied display percentage |
| `brightness up [--device <name>]` | Applies one perceptual +5% step through the selected backend, then best-effort notifies Quickshell with the actual applied display percentage |
| `brightness down [--device <name>]` | Same, but one perceptual -5% step |
| `brightness dim [--device <name>]` | Saves state for the selected backend, dims toward 30% of the current raw brightness over 20 steps, and writes `/tmp/dim-screen.pid` while running. DDC/CI restore state is kept under `$XDG_RUNTIME_DIR/desktopctl/` rather than a shared `/tmp` file |
| `brightness restore [--device <name>]` | Restores the saved brightness state through `brightnessctl -r` for backlights or the saved DDC/CI value for external monitors |

Brightness rules:

- Device auto-detection for step/dim/set without `--device` prefers the first backlight name in sorted `/sys/class/backlight` order, then falls back to DDC/CI VCP code `0x10` through `ddcutil`.
- JSON status lists all readable backlights plus DDC/CI displays discovered through `ddcutil detect --brief`; DDC entries include connector metadata when `ddcutil` reports a DRM connector.
- `--device <name>` still selects a backlight device; `--device ddc` selects the default DDC display, and `--device ddc:<display>` passes an explicit `ddcutil --display` value. `ddc-<display>` is accepted as a compatibility alias of `ddc:<display>`.
- If neither a backlight nor DDC/CI brightness is reachable, mutating commands and non-JSON `status` fail; JSON `status` reports `available: false` with an empty `devices` array.
- `set`, `up`, and `down` emit the Quickshell OSD IPC call today.
- The old `/tmp/quickshell-brightness` file contract no longer exists.

### `desktopctl hypr`

| Command | Current behavior |
| --- | --- |
| `hypr toggle-float` | If the active window is tiled, toggles floating, resizes it to `75% 75%`, and centers it; if already floating, toggles floating off |
| `hypr lid-switch <open/closed/sync> [--internal <monitor>] [--open-spec <spec>]` | Applies the laptop lid monitor policy. `closed` disables the internal monitor only when another output is active (`close` is accepted as a compatibility alias), `open` restores the internal monitor with the provided Hyprland monitor spec, and `sync` reads `/proc/acpi/button/lid/*/state` and applies only the closed-lid action when needed. |
| `hypr input status [--json]` | Prints the effective managed shared input state by layering `~/.config/hypr/input.conf` defaults with `~/.config/hypr/input-runtime.conf` overrides |
| `hypr input set <key> <value>` | Validates one managed shared input key (`sensitivity`, `accel_profile`, or `scroll_factor`), atomically rewrites `input-runtime.conf`, applies the same value live through `hyprctl keyword`, and restores the previous file if that live apply fails |
| `hypr animations save <json>` | Validates one JSON payload, rewrites `animations-override.conf`, and reloads Hyprland so the generated overrides apply on top of `appearance.conf` |
| `hypr animations clear` | Clears all managed animation overrides, rewrites `animations-override.conf` to an empty managed file, and reloads Hyprland |
| `hypr keybinds save <json>` | Validates one JSON payload (entries whose flags contain `d` must carry a non-empty description, since `bindd` renders the description as its own field), rewrites `keybinds-override.conf`, and reloads Hyprland so the generated remaps apply on top of `keybinds.conf` |
| `hypr keybinds clear` | Clears all managed keybind overrides, rewrites `keybinds-override.conf` to an empty managed file, and reloads Hyprland |

### `desktopctl launch-quickshell`

| Command | Current behavior |
| --- | --- |
| `launch-quickshell` | Reads cursor env overrides from `~/.config/hypr/cursor.conf`, resolves the repo-root Quickshell path, and `exec()`s `quickshell -p <repo>/config/quickshell` |
| `launch-quickshell --print-env` | Prints `XCURSOR_THEME` \| `HYPRCURSOR_THEME` \| `XCURSOR_SIZE` and exits. Manual debugging aid only — it has no automated consumers |

### `desktopctl night-light`

| Command | Current behavior |
| --- | --- |
| `night-light status [--json]` | Returns daemon-backed status when the socket is available, otherwise falls back to local process/solar inspection |
| `night-light on [--temp K]` | Requests daemon mode `on` with an optional manual temperature |
| `night-light off [--temp K]` | Requests daemon mode `off`; `--temp` only updates the stored manual target |
| `night-light auto [--temp K]` | Requests daemon mode `auto`; `--temp` updates the manual target used when switching back to `on` later |
| `night-light toggle` | Switches between `on` and `off` based on the live `hyprsunset` process state |

Night-light rules:

- Mode is in-memory only and resets to `auto` when the daemon restarts.
- `auto` follows solar status for `hyprsunset`.
- `on` and `off` only change `hyprsunset`; the scheduled `dark_hint` edges are
  a separate contract — see `docs/sun-schedule/SPEC.md` (Ownership Boundaries).

### `desktopctl sun`

| Command | Current behavior |
| --- | --- |
| `sun status` | Prints the resolved coordinates, sunrise/sunset, current `night` / late-night dark-on window state, and the next sunrise / sunset / dark-on / dark-off events |

## Socket Contract

`desktopctl daemon` listens on `$XDG_RUNTIME_DIR/desktopctl.sock` and accepts
one JSON object per line.

The CLI client applies finite socket read/write timeouts so an accepted but
unresponsive daemon does not block Quickshell or shell commands indefinitely.

Supported methods today:

| Method | Params | Result |
| --- | --- | --- |
| `ping` | none | `{"pong": true}` |
| `night_light.status` | none | Full `NightLightStatus` payload |
| `night_light.set` | `{ "mode": "...", "temperature": <int or null> }` | Updated `NightLightStatus` |
| `night_light.toggle` | none | Updated `NightLightStatus` |

Response shape:

- Success: `{"ok": true, "data": ...}`
- Error: `{"ok": false, "error": "..."}`

## Repo Integration

| Surface | Current contract |
| --- | --- |
| Home Manager | Installs `desktopctl` into `home.packages`, bootstraps `~/.config/hypr/input-runtime.conf`, `animations-override.conf`, and `keybinds-override.conf`, and runs `desktopctl theme sync` in `home.activation.applyTheme` |
| Hyprland autostart | Starts `desktopctl daemon` and `desktopctl launch-quickshell`, then re-applies wallpaper with `desktopctl theme wallpaper` |
| Hyprland keybinds | Use `desktopctl brightness`, `desktopctl hypr toggle-float`, laptop-host `desktopctl hypr lid-switch ...` switch binds, and `desktopctl night-light ...` |
| Hypridle | Uses `desktopctl brightness dim` and `desktopctl brightness restore` |
| Quickshell settings | Reads theme state, scheme lists, and presets through `desktopctl theme ... --json`, reads shared mouse defaults through `desktopctl hypr input status --json`, and sends writes back through `desktopctl theme ...` plus `desktopctl hypr input set ...` |

## Packaging

`desktopctl` is packaged from `desktopctl/default.nix` as a Rust derivation,
exposed through `overlays/local-packages.nix`, and published from the flake as
`packages.x86_64-linux.desktopctl`.
