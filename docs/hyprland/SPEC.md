# Hyprland Specification

This spec defines the sourced-file ownership model for Hyprland configuration:
which files are static base config, which are generated, which are host-specific,
and how the boundaries between Hyprland config, Quickshell, and the theming
pipeline are drawn. It is the intent document; see `docs/hyprland/ARCHITECTURE.md`
for the current implementation map.

## Goals

- Keep Hyprland configuration modular through a sourced-file graph.
- Separate host-specific hardware concerns from shared behavior.
- Keep generated theme outputs isolated from hand-authored base config.
- Define clear ownership boundaries with Quickshell and the theming pipeline.

Non-goals:

- Generating the entire Hyprland config from Nix expressions
- Putting host-specific hardware config in shared files
- Letting the theming pipeline write to base config files

## Source Graph Contract

`hyprland.conf` sources a fixed, ordered set of files. The source order is part
of the contract — later files may depend on variables defined by earlier ones.

| Order | File | Classification |
| --- | --- | --- |
| 1 | `monitors.conf` | Host-specific |
| 2 | `env.conf` | Host-specific |
| 3 | `cursor.conf` | Generated |
| 4 | `input.conf` | Static base |
| 5 | `input-devices.conf` | Host-specific |
| 6 | `input-runtime.conf` | Generated runtime override |
| 7 | `colors.conf` | Generated |
| 8 | `appearance.conf` | Static base (sources generated `appearance-theme.conf`) |
| 9 | `animations-override.conf` | Generated runtime override |
| 10 | `plugins.conf` | Static base |
| 11 | `keybinds.conf` | Static base |
| 12 | `keybinds-override.conf` | Generated runtime override |
| 13 | `rules.conf` | Static base |
| 14 | `autostart.conf` | Static base (sources host-selected `autostart-host.conf`) |

Constraints:

- The source order is authoritative. Adding, removing, or reordering entries
  in `hyprland.conf` is a contract change.
- Generated theme files must appear before any static file that consumes their
  variables.
- Runtime override files must appear after the static or host fragments they
  are allowed to override.
- Host-specific files must not assume behavior from other host-specific files.

## File Classifications

### Static base config

Files committed to `config/hypr/` and deployed via `xdg.configFile` in
`home/xdg.nix`. These are the same across all hosts.

| File | Concern |
| --- | --- |
| `hyprland.conf` | Source graph definition |
| `appearance.conf` | Compositor defaults (sources generated `appearance-theme.conf`) |
| `input.conf` | Shared keyboard, pointer, and cursor defaults |
| `keybinds.conf` | Key bindings, dispatcher actions, Quickshell IPC triggers |
| `rules.conf` | Window rules, layer rules, and plugin rule glue |
| `plugins.conf` | Plugin loading and theme-facing plugin settings |
| `autostart.conf` | Session bootstrap services plus the host-autostart include |
| `hypridle.conf` | Idle, lock, DPMS, and suspend timers |
| `hyprlock.conf` | Lock screen presentation (sources generated `colors.conf`) |

Constraints:

- Static files may import generated fragments but must not become the home of
  generated content.
- Static files must not contain host-specific hardware assumptions unless
  guarded by a documented fallback.

### Generated theme outputs

Files written by the theming pipeline at runtime. Never committed to the repo.

| File | Theming target | Content |
| --- | --- | --- |
| `colors.conf` | `hyprland` | `$theme_*` color, font, and semantic variables |
| `appearance-theme.conf` | `hypr_appearance` | Runtime appearance values (gaps, borders, rounding, blur, animations) |
| `cursor.conf` | `cursor` | Cursor environment variables |

Constraints:

- Generated files must contain only theming data.
- These files are owned by the theming pipeline; see `docs/theming/SPEC.md` for
  the target contract.
- The compositor sources these files but does not define their content.

### Generated desktopctl runtime overrides

Files written by `desktopctl` at runtime. Never committed to the repo.

| File | Owner | Content |
| --- | --- | --- |
| `input-runtime.conf` | `desktopctl hypr input` | Shared pointer defaults (`sensitivity`, `accel_profile`, `scroll_factor`) layered after `input.conf` and `input-devices.conf` |
| `animations-override.conf` | `desktopctl hypr animations` | Bezier curves and per-animation overrides layered after `appearance.conf` |
| `keybinds-override.conf` | `desktopctl hypr keybinds` | Unbind + rebind pairs layered after `keybinds.conf` |

Constraints:

- Runtime override files must only contain the mutable state owned by their
  runtime helper.
- `desktopctl hypr input` may rewrite `input-runtime.conf`, but it must not
  edit `input.conf` or `input-devices.conf`.
- `desktopctl hypr animations` may rewrite `animations-override.conf`, but it
  must not edit `appearance.conf` or `appearance-theme.conf`.
- `desktopctl hypr keybinds` may rewrite `keybinds-override.conf`, but it must
  not edit `keybinds.conf`.
- A missing runtime override file must be safe; Hyprland should still boot from
  the static and host-selected base config alone.

### Host-specific overrides

Files selected per host by the `host.hyprland.*` facts consumed in `home/xdg.nix`.

| File | Laptop | Desktop | Fallback |
| --- | --- | --- | --- |
| `autostart-host.conf` | `hosts/laptop/autostart.conf` | `hosts/desktop/autostart.conf` | Empty |
| `monitors.conf` | `hosts/laptop/monitors.conf` | `hosts/desktop/monitors.conf` | Generic auto-detect rule |
| `env.conf` | `config/hypr/env.conf` | `hosts/desktop/env.conf` | Empty |
| `input-devices.conf` | `hosts/laptop/input-devices.conf` | `hosts/desktop/input-devices.conf` | Empty |

Constraints:

- Host-specific files own hardware concerns plus minimal host-only startup
  hooks: GPU environment, monitor layout, per-device input overrides, and
  per-host session bootstrap commands that cannot live in the shared base file.
- The fallback branch must provide safe minimal defaults so the compositor
  starts on any host.
- Adding a new host requires adding the relevant `host.hyprland.*` facts in
  `flake.nix` or relying on the fallback path.

## Host Selection Contract

`flake.nix` defines the set of known hosts. Each host passes a structured `host`
record through `specialArgs` to Home Manager. `home/xdg.nix` uses the explicit
`host.hyprland.*` facts to select fragments.

Invariants:

- The `else` branch must always produce a bootable, functional Hyprland session
  with no host-specific assumptions.
- Host-specific `system.nix` modules handle NixOS-level concerns (drivers,
  hardware, boot). Host-specific Hyprland fragments handle compositor-level
  concerns and host-only session hooks (monitors, GPU env, input devices, and
  autostart additions).
- The laptop's `env.conf` lives in `config/hypr/env.conf` because it carries
  shared environment defaults alongside its GPU-specific settings. The desktop's
  `env.conf` lives in `hosts/desktop/env.conf` because it replaces GPU settings
  entirely.

## Ownership Boundaries

| Concern | Owner | Contract |
| --- | --- | --- |
| Source graph and compositor behavior | Hyprland config (`config/hypr/`) | Static base files define the session's behavior, bindings, rules, and idle policy. |
| Theme-derived appearance | The theming pipeline | Generated `colors.conf`, `appearance-theme.conf`, and `cursor.conf` are the only theme write surfaces within the Hyprland config directory. |
| Shared Hyprland mouse defaults | `desktopctl hypr input` | Writes generated `input-runtime.conf` and applies the same values live through `hyprctl keyword`, without editing `input.conf` or `input-devices.conf`. |
| Animation overrides | `desktopctl hypr animations` | Writes generated `animations-override.conf` with bezier curves and per-animation overrides, sourced after `appearance.conf` so GUI changes layer on top of hand-edited base animations. |
| Keybind overrides | `desktopctl hypr keybinds` | Writes generated `keybinds-override.conf` with unbind + rebind pairs, sourced after `keybinds.conf` so GUI remaps layer on top of the static base bindings. |
| Transient idle/lid inhibition | Quickshell `IdleInhibitService.qml` | Holds or releases runtime `systemd-inhibit --what=idle` and `systemd-inhibit --what=handle-lid-switch --mode=block` inhibitors that pause hypridle timers or block logind lid handling, without editing `hypridle.conf`. |
| Wallpaper application | The theming pipeline | The `wallpaper` target owns `awww img` invocations. `autostart.conf` owns `awww-daemon` startup and may reapply persisted theme state by calling `desktopctl theme wallpaper` after the daemon is ready. |
| Night-light automation | `desktopctl daemon` solar subsystem + night-light controller | `hyprsunset` lifecycle belongs to the daemon. Keybinds may request `desktopctl night-light toggle` or `desktopctl night-light auto`, but they do not start or stop `hyprsunset` directly. |
| Shell UI and IPC | Quickshell | Keybinds trigger Quickshell via `qs ipc call`, with the repo path resolved through the same `DESKTOPCTL_REPO` / `~/repos/dotfiles` abstraction used elsewhere; Quickshell does not write Hyprland config files. |
| Plugin loading | `plugins.conf` | Plugins are loaded from `HYPR_PLUGIN_DIR` (set in NixOS `system/configuration.nix`). Plugin visual settings consume theme variables but are declared in the static config. |
| Package installation | Nix / Home Manager | Hyprland ecosystem tools are installed via `home/packages.nix` while the shared Hyprland config graph is deployed through `home/xdg.nix`. |

Invariants:

- Quickshell communicates with Hyprland through `hyprctl` and IPC, never by
  writing config files.
- The theming pipeline writes generated fragments; it does not modify static
  base config.
- `desktopctl hypr input` only writes `input-runtime.conf`; it does not mutate
  static or host-selected fragments.
- `desktopctl hypr animations` only writes `animations-override.conf`; it does
  not mutate `appearance.conf` or other static fragments.
- `desktopctl hypr keybinds` only writes `keybinds-override.conf`; it does not
  mutate `keybinds.conf` or other static fragments.
- Quickshell's idle and lid-inhibit controls use transient runtime inhibitors
  and do not rewrite `hypridle.conf`.
- `desktopctl daemon` owns all live `hyprsunset` lifecycle changes. Keybinds
  are request surfaces into the daemon, not a parallel scheduling system.
