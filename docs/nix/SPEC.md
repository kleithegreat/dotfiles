# Nix Specification

This document defines the intended repository structure for the flake, the shared
and host-specific NixOS layers, the embedded Home Manager layer, and the boundary
between Nix-managed packages and repo-managed config. The current implementation
map lives in `docs/nix/ARCHITECTURE.md`, with the flake entry points in
`flake.nix:23-76` and the shared Home Manager entry point in
`home/default.nix:1-345`.

## Multi-Host Flake Contract

The repository is intended to be one flake with one explicit
`nixosConfigurations.<host>` output per machine (`flake.nix:61-76`). Host
inventory stays explicit at the flake output layer; adding a host means adding a
host module and another `mkHost` call, not creating a second flake or a second
repository root.

`mkHost` exists to abstract repeated flake plumbing, not host behavior
(`flake.nix:33-60`). Its intended responsibilities are:

- the shared `nixosSystem` call
- the shared module stack
- the host-module slot
- the shared `specialArgs` and `extraSpecialArgs` wiring
- the embedded Home Manager integration
- repo-level feature toggles that apply uniformly to every host

`mkHost` is not intended to hide host policy, package choices, hardware rules, or
user configuration. Those belong in modules, not in the helper.

## Layer Boundaries

The repo is intended to stay split into three configuration layers.

### Shared System Configuration

`system/configuration.nix` is the shared system baseline for every host, matching
the current shape described in `docs/nix/ARCHITECTURE.md:113-156`. A setting
belongs in the shared system layer when it is all of:

- required for every host or every host that participates in the common desktop
  platform
- privileged, root-owned, or evaluated before the user session exists
- part of system boot, PAM, networking, firewalling, display manager, system
  services, users/groups, compositor packaging, or the shared system package
  baseline

The shared system layer is the right home for package overrides, patched desktop
components, shared session variables, and service enablement that should not be
repeated in every host module (`system/configuration.nix:9-19`,
`system/configuration.nix:84-353`).

### Host-Specific System Configuration

Each `hosts/<name>/system.nix` file is intended to own only machine-specific
system policy, matching the current host split in `flake.nix:61-76` and
`docs/nix/ARCHITECTURE.md:137-156`. A setting belongs in a host module when it is
driven by:

- hardware, bootloader, filesystem, swap, or kernel differences
- GPU layout, firmware, or host-only driver policy
- host-only packages or services
- per-host overrides to the shared system defaults

If a rule is about one machine or one hardware class, it belongs in a host
module even when it is privileged. If it is shared policy, it does not.

### Home Manager Configuration

`home/default.nix` is the intended shared user-environment root
(`flake.nix:48-58`, `home/default.nix:1-345`). A setting belongs in Home Manager
when it is primarily user-facing and its output lives under the user's home
directory:

- user packages
- XDG config deployment
- `home.file` scripts
- desktop entry overrides
- MIME defaults
- app launcher / shell / editor / terminal configuration
- user-session activation hooks

Host-specific branching inside Home Manager is allowed, but only for user-space
files whose contents genuinely vary by machine, such as monitors, input-device
overrides, or session env fragments (`home/default.nix:181-214`). The intended
default is shared user config with narrow host-specific escapes, not one complete
Home Manager tree per host.

## Placement Rules

When deciding where a new change belongs, the intended rules are:

- Put it in `system/configuration.nix` if it affects system boot, privileged
  services, PAM, firewalling, system-wide packages, shared compositor packaging,
  or any `/etc`-style policy.
- Put it in `hosts/<name>/system.nix` if it is privileged and host-specific.
- Put it in `home/default.nix` or a `home/*.nix` module if it produces user-home
  state and can be managed as part of the user environment.
- Put it under `config/` if it is a version-controlled tool config file that Home
  Manager should deploy into `$XDG_CONFIG_HOME`.
- Put host-specific user config files under `hosts/<name>/` when the file itself,
  not just a small option, differs by host and is still fundamentally user-space
  config (`home/default.nix:187-214`).

The intended split is by authority and lifecycle, not by language. A Nix file is
not automatically a system concern, and a repo config file is not automatically a
Home Manager concern until Home Manager actually deploys it.

## `xdg.configFile` Policy

`xdg.configFile` is intended to own version-controlled base config and static
assets, not mutable generated outputs. The default rule from the theming domain is
the one described in `docs/theming/SPEC.md:70-82`: if a file is generated at
activation time or at runtime, it must stay writable and must not be sourced from
the Nix store.

The intended `xdg.configFile` patterns are:

- base files that import or source generated fragments, such as
  `config/alacritty/alacritty.toml:1-9`, `config/tmux/tmux.conf:1-41`,
  `config/zathura/zathurarc:1-2`, `config/hypr/hyprland.conf:1-14`, and
  `config/hypr/appearance.conf:1-3`
- static, version-controlled config trees such as `quickshell/` and `nvim/`
  deployed recursively from `home/default.nix:225-233`
- static assets that come from packages rather than the repo, such as
  `snappy-switcher/themes` in `home/default.nix:239-241`

The intended non-patterns are:

- final generated theme outputs such as `~/.config/ghostty/config`,
  `~/.config/starship.toml`, `~/.config/vicinae/settings.json`,
  `~/.config/hypr/colors.conf`, or `~/.config/hypr/appearance-theme.conf`
- generated runtime state files such as `~/.config/quickshell/GeneratedTheme.json`,
  `~/.config/nvim/lua/theme-state.json`, and
  `~/.config/nvim/lua/neovide-theme.lua`

The approved carve-out is recursive Home Manager trees that coexist with
runtime-generated sibling files. That is the intended deployment model for:

- `quickshell/`, where Home Manager deploys the QML tree and the theming pipeline
  writes `GeneratedTheme.json` beside it (`home/default.nix:225-228`,
  `config/quickshell/Theme.qml:5-25`, `themes/lib/targets/quickshell.py:7-49`)
- `nvim/`, where Home Manager deploys the repo tree and the theming pipeline
  writes `lua/theme-state.json` and `lua/neovide-theme.lua` inside that tree
  (`home/default.nix:230-233`, `config/nvim/lua/plugins/colors.lua:1-14`,
  `config/nvim/lua/config/options.lua:29-29`,
  `themes/lib/targets/neovim.py:7-17`, `themes/lib/targets/neovide.py:5-15`)

The activation hook at `home/default.nix:327-329` is the intended rebuild-time
sync path. It runs `themes/apply-theme sync`, which writes only the targets that
are safe to materialize during Home Manager activation.

## Packages Versus Repo Config

Nix-managed packages and repo-managed configs have different intended roles.

Nix is responsible for availability, version pinning, patched builds, and module
integration. That includes the system package baseline and desktop packaging in
`system/configuration.nix`, the user package baseline in
`home/default.nix:33-179`, and flake-pinned inputs wired through
`flake.nix:4-58`.

Repo config under `config/` is responsible for application behavior. That
includes:

- keybinds, prompt formats, editor options, and shell settings
- import/source statements that attach generated theme fragments
- compositor session config that belongs to the user's Hyprland config tree

The intended relationship is:

- Nix installs the tool and, when needed, the supporting packages that make a
  config viable.
- Home Manager deploys the base config from the repo.
- The theming pipeline owns the mutable generated fragment or final generated
  config.

If a concern is about package selection, patching, service enablement, or module
arguments, it belongs in Nix. If it is about how an installed tool behaves at
runtime, it belongs under `config/`.

The Qt theming chain is the intended example of that split. The packages needed
for Kvantum and the Qt style stack are installed through Nix
(`home/default.nix:168-171`), while the user-session environment that selects the
platform theme is expressed in the Hyprland config deployed by Home Manager
(`config/hypr/env.conf:4-5`, `home/default.nix:208-214`). The package contract
and the config contract are distinct, but they are expected to line up.
