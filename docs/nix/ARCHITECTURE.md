# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, overlays, and
embedded Home Manager layer as of 2026-04-03.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | `flake.nix:23-101` exports `nixosConfigurations.vm`, `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default` and `packages.x86_64-linux.desktopctl`. |
| Host constructor | `mkHost` in `flake.nix:33-60` wraps `nixpkgs.lib.nixosSystem`. |
| Shared system layer | `system/configuration.nix:1-220` |
| Home Manager entry | `home/default.nix:1-328`, embedded through `home-manager.nixosModules.home-manager` in `flake.nix:44-58` |
| Platform | `flake.nix:45` injects `nixpkgs.hostPlatform = "x86_64-linux"` via an inline module |

`mkHost` currently assembles this module stack:

| Order | Module |
| --- | --- |
| 1 | Inline host-platform module |
| 2 | `./system/configuration.nix` |
| 3 | Selected `./hosts/<name>/system.nix` |
| 4 | `home-manager.nixosModules.home-manager` |
| 5 | Inline Home Manager configuration block |

## Module Ownership

| Path | Role | Current responsibilities |
| --- | --- | --- |
| `system/configuration.nix` | Shared system baseline | Nix settings, shared unfree allowlist, overlays, common users/groups, shared services, system packages, and Hyprland packaging |
| `hosts/vm/system.nix` | VM overlay | VM boot, guest profile, and virtual disk layout |
| `hosts/laptop/system.nix` | Laptop overlay | Hybrid GPU policy, laptop hardware/services, and laptop-only overrides |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, desktop-only packages/services, storage mounts, and desktop-only overlay imports |
| `home/default.nix` | Shared user baseline | User packages, `xdg.configFile` mappings, host-specific Hyprland file selection, desktop entry overrides, and theme activation |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, prompt/navigation tooling |
| `home/gtk.nix` | GTK submodule | GTK packages and small dconf defaults |

The repo no longer has a `home/sun-schedule.nix` module; solar scheduling now
lives inside `desktopctl daemon`.

## Overlay Usage

- `overlays/desktopctl.nix:1-3` exposes `pkgs.desktopctl` from the local
  `desktopctl/` derivation.
- `flake.nix:62-71` exports that overlay as `self.overlays.default` and also
  exposes `packages.x86_64-linux.desktopctl`.
- `system/configuration.nix:5-8` imports both the `desktopctl` overlay and the
  optional march-optimization overlay; `system/configuration.nix:159-162`
  applies them globally.
- `overlays/march-optimized.nix:167-170` optionally rebuilds `desktopctl` with
  the repository's selective march tuning.
- `hosts/desktop/system.nix` still appends
  `overlays/nvidia-open-pr996.nix` for the desktop-specific NVIDIA workaround.

## Home Manager Deployment Model

| Pattern | Current use |
| --- | --- |
| Base files via `xdg.configFile` | Hyprland base files, Alacritty, tmux, Zathura, recursive `quickshell/`, recursive `nvim/`, Git ignore, and packaged Snappy Switcher themes |
| Host-selected symlinks | `hypr/monitors.conf`, `hypr/input-devices.conf`, and `hypr/env.conf` vary by `hostName` |
| Generated theme outputs | Written at activation/runtime by `desktopctl theme`, not by store symlinks |
| Runtime executables | `desktopctl` is installed as a Nix package; the old `home.file`-managed session scripts are gone |

This is the current base/generated split:

- Home Manager deploys version-controlled entry files and static trees.
- `desktopctl theme` writes mutable outputs such as `theme.toml`,
  `colors.conf`, `appearance-theme.conf`, `GeneratedTheme.json`, and the other
  generated theme files.

## Activation Flow

1. `nixos-rebuild switch --flake ~/repos/dotfiles#<host>` builds and activates
   the selected `nixosConfigurations.<host>`.
2. The embedded Home Manager module writes managed user files.
3. `home.activation.applyTheme` prepends `pkgs.desktopctl` to `PATH` and runs
   `desktopctl theme sync` through `home/default.nix:310-312`.
4. `sync` materializes only `sync_safe` targets and skips runtime reload hooks.

The `nrs` alias in `home/shell.nix` remains the preferred wrapper for this
flow.
