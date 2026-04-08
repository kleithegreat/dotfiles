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
| `desktopctl brightness ...` | Short-lived helpers for perceptual brightness stepping, dimming, restoring, and Quickshell brightness OSD notification |
| `desktopctl hypr ...` | Small Hyprland helper surface; today this is only `toggle-float` |
| `desktopctl launch-quickshell` | Reads cursor env overrides from `~/.config/hypr/cursor.conf`, then launches Quickshell against the repo checkout |
| `desktopctl portal ...` | Short-lived portal helper surface; today this is only `pick-directory` |
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
| `$XDG_CACHE_HOME/sun-schedule/location.json` | `desktopctl sun` / daemon | Cached latitude/longitude for solar scheduling |
| `~/repos/dotfiles` | `desktopctl` helpers | Default repo-root fallback for Quickshell launch and repo-relative helper paths |

Additional path rules:

- `paths::repo_root()` first honors `DESKTOPCTL_REPO`, then the legacy
  lowercase `desktopctl_REPO`, then falls back to `~/repos/dotfiles`.
- `launch-quickshell` and brightness OSD notifications both depend on that
  repo-root resolution when they need the repo's `config/quickshell/` tree.

## Ownership Boundaries

| Concern | Current owner | Notes |
| --- | --- | --- |
| Live `hyprsunset` process lifecycle | `desktopctl daemon` night-light controller | Quickshell and Hyprland request mode changes through `desktopctl night-light ...`; they do not spawn `hyprsunset` directly |
| Persisted theme state | `desktopctl theme` | Stored in the `theme_state` table inside `desktopctl.db` |
| Scheduled `dark_hint` changes in `auto` mode | `desktopctl daemon` via `theme::set_dark_hint()` | The daemon computes solar status and persists the scheduled value through the theming module |
| Manual and preset `dark_hint` changes | `desktopctl theme set dark_hint ...` and `desktopctl theme preset ...` | These writes still persist and apply directly; they do not route through the daemon |
| Focus-time SQLite writes and JSON summaries | `desktopctl daemon` focus tracker | Quickshell is read-only for this data |
| Generated theme outputs and runtime side effects | `desktopctl theme` targets | Includes files under `~/.config`, dconf writes, cursor updates, wallpaper apply, and editor/shell state files |
| Quickshell shell IPC | Quickshell | Shell IPC is only a requester; it calls `desktopctl` and does not mutate theme state itself |

Important current behavior:

- `hyprsunset` has a single live arbiter in the daemon.
- `dark_hint` does not: the daemon writes it for solar `auto` mode, but manual
  theme surfaces can also write it directly.
- `desktopctl brightness seed` remains part of the public CLI, but it is
  currently a no-op compatibility shim.

## Command Surface

### `desktopctl daemon`

- Runs in the foreground.
- Starts three subsystems together:
  - focus tracker
  - solar scheduler
  - Unix-socket server
- Shuts down on `SIGTERM` or `SIGINT`.

### `desktopctl theme`

Apply scopes:

| Command | Current behavior |
| --- | --- |
| `theme all` | Applies every registered target in filename order |
| `theme sync` | Applies only `sync_safe` targets and skips runtime-only reload hooks |
| `theme colors` | Applies the color-dependent target set |
| `theme fonts` | Applies the font-dependent target set |
| `theme wallpaper` | Applies only the wallpaper target |
| `theme cursor` | Applies only the cursor target |
| `theme target <name>` | Applies one registered target by name |

State mutation:

| Command | Current behavior |
| --- | --- |
| `theme set <key> <value>` | Validates one state key, persists it, then applies only the affected targets |
| `theme preset <name>` | Loads one preset patch, merges it into current state, applies all targets, then applies any preset-supplied `dark_hint` directly |
| `theme save-preset <name> <json>` | Writes one preset JSON object with canonical key ordering |
| `theme delete-preset <name>` | Removes one preset file |

Inspection:

| Command | Current behavior |
| --- | --- |
| `theme status [--json]` | Prints the current canonical theme state |
| `theme list-schemes [--json]` | Lists color-scheme files |
| `theme list-presets [--json]` | Lists preset files |

Theming invariants:

- `theme status --json` is the authoritative machine-readable view of persisted
  theme state.
- Presets are partial patches, not full-state snapshots.
- `theme sync` is the activation-time safe subset; it is intentionally narrower
  than `theme all`.
- `dark_hint` persists through the theme pipeline even when the daemon is the
  caller.

### `desktopctl brightness`

| Command | Current behavior |
| --- | --- |
| `brightness up [--device <name>]` | Applies one perceptual +5% step through `brightnessctl`, then best-effort notifies Quickshell by calling `qs -p <repo>/config/quickshell ipc call brightness osd <percent>` |
| `brightness down [--device <name>]` | Same, but one perceptual -5% step |
| `brightness dim [--device <name>]` | Saves state with `brightnessctl -s`, dims toward 30% of the current raw brightness over 20 steps, and writes `/tmp/dim-screen.pid` while running |
| `brightness restore [--device <name>]` | Calls `brightnessctl -r` |
| `brightness seed [--device <name>]` | Returns success without writing any state or notifying Quickshell |

Brightness rules:

- Device auto-detection picks the first directory under `/sys/class/backlight`.
- If no backlight exists, the command fails.
- Only `up` and `down` emit the Quickshell OSD IPC call today.
- The old `/tmp/quickshell-brightness` file contract no longer exists.

### `desktopctl hypr`

| Command | Current behavior |
| --- | --- |
| `hypr toggle-float` | If the active window is tiled, toggles floating, resizes it to `75% 75%`, and centers it; if already floating, toggles floating off |

### `desktopctl launch-quickshell`

| Command | Current behavior |
| --- | --- |
| `launch-quickshell` | Reads cursor env overrides from `~/.config/hypr/cursor.conf`, resolves the repo-root Quickshell path, and `exec()`s `quickshell -p <repo>/config/quickshell` |
| `launch-quickshell --print-env` | Prints `XCURSOR_THEME|HYPRCURSOR_THEME|XCURSOR_SIZE` and exits |

### `desktopctl portal`

| Command | Current behavior |
| --- | --- |
| `portal pick-directory` | Opens the XDG file chooser through `busctl`, watches the portal response through `dbus-monitor`, and prints the selected directory path when one is returned |

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
- `auto` follows solar status for both `hyprsunset` and `dark_hint`.
- `on` and `off` only change `hyprsunset`; they leave `dark_hint` unchanged.

### `desktopctl sun`

| Command | Current behavior |
| --- | --- |
| `sun status` | Prints the resolved coordinates, sunrise/sunset, current `night` / `dark_hint` schedule state, and the next sunrise / sunset / dark-on events |

## Socket Contract

`desktopctl daemon` listens on `$XDG_RUNTIME_DIR/desktopctl.sock` and accepts
one JSON object per line.

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
| Home Manager | Installs `desktopctl` into `home.packages` and runs `desktopctl theme sync` in `home.activation.applyTheme` |
| Hyprland autostart | Starts `desktopctl daemon` and `desktopctl launch-quickshell`, then re-applies wallpaper with `desktopctl theme wallpaper` |
| Hyprland keybinds | Use `desktopctl brightness`, `desktopctl hypr toggle-float`, and `desktopctl night-light ...` |
| Hypridle | Uses `desktopctl brightness dim` and `desktopctl brightness restore` |
| Quickshell settings | Reads theme state, scheme lists, and presets through `desktopctl theme ... --json`, and sends theme writes back through `desktopctl theme ...` |
| Quickshell shell IPC | Routes `theme.apply` to `desktopctl theme ...` with argv-safe tokenization and error-only toast reporting |

## Packaging

`desktopctl` is packaged from `desktopctl/default.nix` as a Rust derivation,
exposed through `overlays/desktopctl.nix`, and published from the flake as
`packages.x86_64-linux.desktopctl`.
