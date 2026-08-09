# Hyprland Specification

This spec defines the required-file ownership model for Hyprland configuration:
which files are static base config, which are generated, which are host-specific,
and how the boundaries between Hyprland config, Quickshell, and the theming
pipeline are drawn. It is the intent document; see `docs/hyprland/ARCHITECTURE.md`
for the current implementation map.

## Goals

- Keep Hyprland configuration modular through a Lua require graph.
- Separate host-specific hardware concerns from shared behavior.
- Keep generated theme outputs isolated from hand-authored base config.
- Define clear ownership boundaries with Quickshell and the theming pipeline.

Non-goals:

- Generating the entire Hyprland config from Nix expressions
- Putting host-specific hardware config in shared files
- Letting the theming pipeline write to base config files

## Require Graph Contract

Hyprland is configured in Lua. hyprlang `.conf` was deprecated upstream in
0.55 and the Lua API has no `source`/hyprlang escape hatch, so every file in
the graph — including generated and host-specific ones — is Lua.

`hyprland.lua` requires a fixed, ordered set of files. The order is part of the
contract — later files may override settings applied by earlier ones.

Generated files are *data tables* (`return { ... }`) with no side effects; the
hand-written module that requires one is responsible for applying it. This
keeps generator output trivially reviewable and keeps `hl.*` calls in
version-controlled code.

| Order | File | Classification |
| --- | --- | --- |
| 1 | `monitors.lua` | Host-specific monitor layout and workspace placement |
| 2 | `env.lua` | Host-specific |
| 3 | `cursor.lua` | Static base (applies generated `cursor-theme.lua`) |
| 4 | `input.lua` | Static base (applies `input-defaults.lua` + generated `input-runtime.lua`) |
| 5 | `input-devices.lua` | Host-specific |
| 6 | `appearance.lua` | Static base (applies generated `appearance-theme.lua`) |
| 7 | `animations-override.lua` | Static base (applies generated `animations-override-data.lua`) |
| 8 | `plugins.lua` | Static base (applies generated `colors.lua`) |
| 9 | `keybinds.lua` | Static base |
| 10 | `keybinds-override.lua` | Static base (applies generated `keybinds-override-data.lua`) |
| 11 | `rules.lua` | Static base |
| 12 | `autostart.lua` | Static base (requires host-selected `autostart-host.lua`) |

`hypridle.conf` and `hyprlock.conf` are **not** part of this graph. They
configure separate applications that still use hyprlang.

Constraints:

- The require order is authoritative. Adding, removing, or reordering entries
  in `hyprland.lua` is a contract change.
- Generated data tables must be required by the module that consumes them, and
  that module must tolerate the file being absent or empty — an empty file is
  the "no overrides" state that `desktopctl ... clear` writes.
- Runtime override files must appear after the static or host fragments they
  are allowed to override.
- Host-specific files must not assume behavior from other host-specific files.

## File Classifications

### Static base config

Files committed to `config/hypr/` and deployed via `xdg.configFile` in
`home/xdg.nix`. These are the same across all hosts.

| File | Concern |
| --- | --- |
| `hyprland.lua` | Require graph definition |
| `appearance.lua` | Compositor defaults (applies generated `appearance-theme.lua`) |
| `input-defaults.lua` | Shared keyboard, pointer, and cursor defaults |
| `keybinds.lua` | Key bindings, dispatcher actions, Quickshell IPC triggers |
| `rules.lua` | Window rules, layer rules, and plugin rule glue |
| `plugins.lua` | Plugin loading and theme-facing plugin settings |
| `autostart.lua` | Session bootstrap services plus the host-autostart require |
| `session.lua` | Shared autostart helpers (clean-env exec prefix) |
| `hypridle.conf` / `hyprlock.conf` | Separate hyprlang apps — not part of the Lua graph |

Constraints:

- Static files may import generated fragments but must not become the home of
  generated content.
- Static files must not contain host-specific hardware assumptions unless
  guarded by a documented fallback.

### Generated theme outputs

Files written by the theming pipeline at runtime. Never committed to the repo.

| File | Theming target | Content |
| --- | --- | --- |
| `colors.lua` | `hyprland` | Color, font, and semantic values as a data table |
| `appearance-theme.lua` | `hypr_appearance` | Runtime appearance values (gaps, borders, rounding, blur, animations) |
| `cursor-theme.lua` | `cursor` | Cursor environment variables as a data table |

Constraints:

- Generated files must contain only theming data.
- These files are owned by the theming pipeline; see `docs/theming/SPEC.md` for
  the target contract.
- The compositor requires these files but does not define their content.
- Generated files are data tables only; the hand-written module that requires
  one performs the `hl.*` calls.

### Generated desktopctl runtime overrides

Files written by `desktopctl` at runtime. Never committed to the repo.

| File | Owner | Content |
| --- | --- | --- |
| `input-runtime.lua` | `desktopctl hypr input` | Shared pointer defaults (`sensitivity`, `accel_profile`, `scroll_factor`) layered after `input-defaults.lua` and `input-devices.lua` |
| `animations-override-data.lua` | `desktopctl hypr animations` | Bezier curves and per-animation overrides layered after `appearance.lua` |
| `keybinds-override-data.lua` | `desktopctl hypr keybinds` | Unbind + rebind pairs layered after `keybinds.lua` |

Constraints:

- Runtime override files must only contain the mutable state owned by their
  runtime helper.
- `desktopctl hypr input` may rewrite `input-runtime.lua`, but it must not
  edit `input-defaults.lua` or `input-devices.lua`.
- `desktopctl hypr animations` may rewrite `animations-override-data.lua`, but it
  must not edit `appearance.lua` or `appearance-theme.lua`.
- `desktopctl hypr keybinds` may rewrite `keybinds-override-data.lua`, but it must
  not edit `keybinds.lua`.
- A missing runtime override file must be safe; Hyprland should still boot from
  the static and host-selected base config alone.

### Host-specific overrides

Files selected per host by the `host.hyprland.*` facts consumed in `home/xdg.nix`.

| File | Laptop | Desktop | Fallback |
| --- | --- | --- | --- |
| `autostart-host.lua` | `hosts/laptop/autostart.lua` | `hosts/desktop/autostart.lua` | Empty |
| `monitors.lua` | `hosts/laptop/monitors.lua` | `hosts/desktop/monitors.lua` | Generic auto-detect rule |
| `env.lua` | `config/hypr/env.lua` | `hosts/desktop/env.lua` | Empty |
| `input-devices.lua` | `hosts/laptop/input-devices.lua` | `hosts/desktop/input-devices.lua` | Empty |

Constraints:

- Host-specific files own hardware concerns plus minimal host-only startup
  hooks: GPU environment, monitor layout, monitor-scoped workspace placement,
  per-device input overrides, laptop lid-switch output policy, and per-host
  session bootstrap commands that cannot live in the shared base file.
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
  concerns and host-only session hooks (monitors, GPU env, input/lid devices,
  and autostart additions).
- The laptop's `env.lua` lives in `config/hypr/env.lua` because it carries
  shared environment defaults alongside its GPU-specific settings. The desktop's
  `env.lua` lives in `hosts/desktop/env.lua` because it replaces GPU settings
  entirely.

## Ownership Boundaries

| Concern | Owner | Contract |
| --- | --- | --- |
| Source graph and compositor behavior | Hyprland config (`config/hypr/`) | Static base files define the session's behavior, bindings, rules, and idle policy. |
| Theme-derived appearance | The theming pipeline | Generated `colors.lua`, `appearance-theme.lua`, and `cursor-theme.lua` are the only theme write surfaces within the Hyprland config directory. |
| Shared Hyprland mouse defaults | `desktopctl hypr input` | Writes generated `input-runtime.lua` and applies the same values live through `hyprctl keyword`, without editing `input-defaults.lua` or `input-devices.lua`. |
| Laptop lid-switch output policy | `hosts/laptop/input-devices.lua` + `desktopctl hypr lid-switch` | Laptop switch binds call the helper on lid close/open. Close disables the internal panel only when another output is active; open restores the internal panel from the configured Hyprland monitor spec. |
| Numbered-workspace reachability | `desktopctl daemon` monitor watcher + `desktopctl hypr reclaim-workspaces` | Monitor pins in `hosts/*/monitors.lua` stay static; the watcher only refocuses an output that Hyprland parked past those pins because the pinned monitor is absent. It never edits config and no-ops on hosts that pin nothing. |
| Animation overrides | `desktopctl hypr animations` | Writes generated `animations-override-data.lua` with bezier curves and per-animation overrides, sourced after `appearance.lua` so GUI changes layer on top of hand-edited base animations. |
| Keybind overrides | `desktopctl hypr keybinds` | Writes generated `keybinds-override-data.lua` with unbind + rebind pairs, sourced after `keybinds.lua` so GUI remaps layer on top of the static base bindings. |
| Transient idle/lid inhibition | Quickshell `IdleInhibitService.qml` | Holds or releases runtime `systemd-inhibit --what=idle` and `systemd-inhibit --what=handle-lid-switch --mode=block` inhibitors that pause hypridle timers or block logind lid handling, without editing `hypridle.conf`. |
| Wallpaper application | The theming pipeline | The `wallpaper` target owns `awww img` invocations. `autostart.lua` owns `awww-daemon` startup and may reapply persisted theme state by calling `desktopctl theme wallpaper` after the daemon is ready. |
| Night-light automation | `desktopctl daemon` solar subsystem + night-light controller | `hyprsunset` lifecycle belongs to the daemon. Keybinds may request `desktopctl night-light toggle` or `desktopctl night-light auto`, but they do not start or stop `hyprsunset` directly. |
| Shell UI and IPC | Quickshell | Keybinds trigger Quickshell via `qs ipc call`, with the repo path resolved through the same `DESKTOPCTL_REPO` / `~/repos/dotfiles` abstraction used elsewhere; Quickshell does not write Hyprland config files. |
| Plugin loading | `plugins.lua` | Plugins are loaded from `HYPR_PLUGIN_DIR` (set in NixOS `system/configuration.nix`). Plugin visual settings consume theme variables but are declared in the static config. |
| Package installation | Nix / Home Manager | Hyprland ecosystem tools are installed via `home/packages.nix` while the shared Hyprland config graph is deployed through `home/xdg.nix`. |

Invariants:

- Quickshell communicates with Hyprland through `hyprctl` and IPC, never by
  writing config files.
- The theming pipeline writes generated fragments; it does not modify static
  base config.
- `desktopctl hypr input` only writes `input-runtime.lua`; it does not mutate
  static or host-selected fragments.
- `desktopctl hypr animations` only writes `animations-override-data.lua`; it does
  not mutate `appearance.lua` or other static fragments.
- `desktopctl hypr keybinds` only writes `keybinds-override-data.lua`; it does not
  mutate `keybinds.lua` or other static fragments.
- Quickshell's idle and lid-inhibit controls use transient runtime inhibitors
  and do not rewrite `hypridle.conf`.
- `desktopctl daemon` owns all live `hyprsunset` lifecycle changes. Keybinds
  are request surfaces into the daemon, not a parallel scheduling system.
