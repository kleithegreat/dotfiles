# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, optional
distributed-build wiring, and embedded Home Manager layer as of 2026-04-08.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | `flake.nix:23-101` exports `nixosConfigurations.vm`, `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default` and `packages.x86_64-linux.desktopctl` |
| Host constructor | `mkHost` in `flake.nix:33-60` wraps `nixpkgs.lib.nixosSystem` |
| Feature flags | `flake.nix:25-31` keeps both `enableMarchOptimizations` and `enableDistributedBuilds` in the shared host constructor, with distributed builds currently disabled by default |
| Shared system layer | `system/configuration.nix:1-405` |
| Home Manager entry | `home/default.nix:1-350`, embedded through `home-manager.nixosModules.home-manager` in `flake.nix:49-58` |
| Platform | `flake.nix:39-40` passes `system = "x86_64-linux"` directly to `nixosSystem` |

`mkHost` currently assembles this module stack:

| Order | Module |
| --- | --- |
| 1 | `./system/configuration.nix` |
| 2 | Selected `./hosts/<name>/system.nix` |
| 3 | `home-manager.nixosModules.home-manager` |
| 4 | Inline Home Manager configuration block |

## Module Ownership

| Path | Role | Current responsibilities |
| --- | --- | --- |
| `system/configuration.nix` | Shared system baseline | Nix settings, shared unfree allowlist, overlays, common users/groups, shared services, privileged desktop helper registrations, system packages, and Hyprland packaging |
| `system/distributed-builds.nix` | Optional shared distributed-build layer | When enabled, configures remote builders, the post-build cache push hook, `nix.sshServe`, and LAN-only SSH firewall rules |
| `system/distributed-builds-data.nix` | Environment-specific builder/cache data | Authorized builder keys, host keys, current cache signing key, and the current cache URL override |
| `hosts/vm/system.nix` | VM overlay | VM boot, guest profile, and virtual disk layout |
| `hosts/laptop/system.nix` | Laptop overlay | Hybrid GPU policy, laptop-only services and overrides, GRUB, and laptop hardware policy |
| `hosts/laptop/fan-control.nix` | Laptop-only hardware submodule | Dell SMM kernel module wiring, BIOS fan-control handoff, `i8kmon.conf`, and the `i8kmon` systemd service |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, desktop-only packages/services, storage mounts, GRUB, and desktop-only overlay imports |
| `home/default.nix` | Shared user baseline | User packages that do not require system-scoped helper registration, `xdg.configFile` mappings, host-specific Hyprland file selection, desktop entry overrides, and theme activation |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, and shell helpers |
| `home/gtk.nix` | GTK submodule | GTK packages and small dconf defaults |

## Overlay Usage

- `overlays/desktopctl.nix:1-3` exposes `pkgs.desktopctl` from the local
  `desktopctl/` derivation.
- `flake.nix:62-71` exports that overlay as `self.overlays.default` and also
  exposes `packages.x86_64-linux.desktopctl`.
- `system/configuration.nix:5-8` imports both the `desktopctl` overlay and the
  optional march-optimization overlay; `system/configuration.nix:160-164`
  applies them globally.
- `overlays/march-optimized.nix:167-170` optionally rebuilds `desktopctl` and
  other selected derivations with march tuning.
- `hosts/desktop/system.nix:4-8` still appends
  `overlays/nvidia-open-pr996.nix` for the desktop-specific NVIDIA workaround.

## Distributed Builds

The distributed-build subsystem is present in the shared module graph even
though the repo currently ships with it disabled.

| Surface | Current implementation |
| --- | --- |
| Flag state | `flake.nix:29-31` sets `enableDistributedBuilds = false`, so the distributed-build module evaluates but its host-specific `mkIf` payload stays inactive |
| Shared module import | `system/configuration.nix:125-127` always imports `./distributed-builds.nix` |
| Host gating | `system/distributed-builds.nix:77-99` only activates the subsystem when the flag is true and `hostName` is `desktop` or `laptop` |
| Cache URL | `system/distributed-builds.nix:25-27` falls back to `http://<homelab>:5000`, but `system/distributed-builds-data.nix:30-31` currently overrides that to `http://192.168.8.153:5050` |
| Reference docs | `docs/nix/distributed-builds.md` documents the repo-side contract, and `docs/nix/homelab-builder-setup.md` documents the Ubuntu homelab setup that matches the current `5050` override |

## Home Manager Deployment Model

| Pattern | Current use |
| --- | --- |
| Base files via `xdg.configFile` | Hyprland base files, Alacritty, tmux, Zathura, recursive `quickshell/`, recursive `nvim/`, Git ignore, and packaged Snappy Switcher themes |
| Host-selected symlinks | `hypr/autostart-host.conf`, `hypr/monitors.conf`, `hypr/input-devices.conf`, and `hypr/env.conf` vary by `hostName` |
| Generated theme outputs | Written at activation/runtime by `desktopctl theme`, not by store symlinks |
| Runtime executables | `desktopctl` is installed as a Nix package; the old `home.file`-managed session scripts are gone |

This is the current base/generated split:

- Home Manager deploys version-controlled entry files and static trees.
- `desktopctl theme` writes mutable outputs such as `theme.toml`,
  `colors.conf`, `appearance-theme.conf`, and the other generated theme files.
- The recursive Quickshell tree is the deliberate exception: Home Manager
  deploys `config/quickshell/` recursively, which includes the committed
  `config/quickshell/GeneratedTheme.json` bootstrap snapshot, and
  `desktopctl/src/theme/targets/quickshell.rs:8-17` then overwrites the live
  `~/.config/quickshell/GeneratedTheme.json` path during activation/runtime.

Privileged desktop helper wiring currently bypasses Home Manager for one shared
GUI package:

- `system/configuration.nix:334-336` enables `programs.partition-manager`,
  which installs `kdePackages.partitionmanager` and `kdePackages.kpmcore`
  through the NixOS module so `kpmcore` lands in both
  `services.dbus.packages` and `environment.systemPackages`.
- `home/default.nix:102-132` no longer lists `kdePackages.partitionmanager`
  directly; the nearby comment documents that the move is required because the
  helper depends on system-wide D-Bus and polkit registration.

## Activation Flow

1. `nixos-rebuild switch --flake ~/repos/dotfiles#<host>` builds and activates
   the selected `nixosConfigurations.<host>`.
2. The embedded Home Manager module writes managed user files.
3. `home.activation.applyTheme` prepends `pkgs.desktopctl` to `PATH` and runs
   `desktopctl theme sync` through `home/default.nix:332-335`.
4. `sync` materializes only `sync_safe` targets and skips runtime reload hooks.

The `nrs` alias in `home/shell.nix` remains the preferred wrapper for this
flow.
