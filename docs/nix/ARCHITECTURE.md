# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, host overlays,
and embedded Home Manager layer as of 2026-04-02.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | `nixosConfigurations.vm`, `nixosConfigurations.laptop`, `nixosConfigurations.desktop` |
| Host constructor | `mkHost` in `flake.nix` wraps `nixpkgs.lib.nixosSystem` |
| Shared system layer | `system/configuration.nix` |
| Host overlays | `hosts/*/system.nix` |
| Home Manager entry | `home/default.nix`, embedded through `home-manager.nixosModules.home-manager` |
| Platform | `mkHost` injects `nixpkgs.hostPlatform = "x86_64-linux"` via an inline module |

`mkHost` currently assembles this module stack:

| Order | Module |
| --- | --- |
| 1 | Inline host-platform module |
| 2 | `./system/configuration.nix` |
| 3 | Selected `./hosts/<name>/system.nix` |
| 4 | `home-manager.nixosModules.home-manager` |
| 5 | Inline Home Manager configuration block |

Because `flake.nix:48-57` sets `home-manager.useGlobalPkgs = true`, nixpkgs
policy from the shared system layer, including the unfree allowlist predicate in
`system/configuration.nix:83-156`, applies to both system packages and
`home.packages`.

## Inputs And Feature Flags

Direct flake inputs:

| Input | Used for |
| --- | --- |
| `nixpkgs` | Base package set and `lib.nixosSystem` |
| `home-manager` | Home Manager as a NixOS module |
| `hyprland` | Upstream compositor and portal packages |
| `hyprland-plugins` | Plugin builds aligned with the pinned Hyprland |
| `hyprqt6engine` | Qt platform theme engine for the Hyprland session |
| `vicinae` | Launcher package and Home Manager module |
| `snappy-switcher` | Alt-Tab switcher package and bundled themes |

Repo-level feature flags:

| Flag | Effect |
| --- | --- |
| `enableMarchOptimizations` | Enables the curated `-march` overlay and host feature wiring |
| `enableDistributedBuilds` | Enables LAN builder configuration and cache propagation |

Low-level `-march` and distributed-build caveats live in `docs/nix/QUIRKS.md`.

## Module Ownership

| Path | Role | Current responsibilities |
| --- | --- | --- |
| `system/configuration.nix` | Shared system baseline | Nix settings, the shared unfree package allowlist predicate (`system/configuration.nix:83-156`), common users/groups, shared services, system packages, Hyprland packaging, and the distributed-builds import |
| `hosts/vm/system.nix` | VM overlay | VM boot, guest profile, and virtual disk layout |
| `hosts/laptop/system.nix` | Laptop overlay | Hybrid GPU policy, laptop hardware/services, and laptop-only overrides |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, desktop-only packages/services, storage mounts, and a desktop-only NVIDIA workaround overlay import |
| `home/default.nix` | Shared user baseline | User packages including LM Studio (`home/default.nix:33-180`), most `xdg.configFile` mappings, `home.file` scripts, MIME defaults, host-specific Hyprland file selection, and theme activation |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, prompt/navigation tooling |
| `home/gtk.nix` | GTK submodule | GTK packages and small dconf defaults |
| `home/sun-schedule.nix` | User service submodule | Sunrise/sunset timer and service |

## Overlay Usage

- `system/configuration.nix` always adds `overlays/march-optimized.nix` as the
  shared nixpkgs overlay.
- `hosts/desktop/system.nix` additionally appends
  `overlays/nvidia-open-pr996.nix`, a temporary desktop-only workaround for
  NVIDIA open-gpu-kernel-modules PR #996.
- `overlays/nvidia-open-pr996.nix` rebuilds
  `linuxPackages.nvidiaPackages.{production,stable}` through `mkDriver` with
  `patches/nvidia/nvidia-open-pr996.patch`, because the open kernel module is
  exposed through `passthru.open` and only picks up patches from `patchesOpen`.

## Home Manager Deployment Model

| Pattern | Current use |
| --- | --- |
| Base files via `xdg.configFile` | Hyprland base files, Alacritty, tmux, Zathura, recursive `quickshell/`, recursive `nvim/`, Git ignore, packaged Snappy Switcher themes |
| Host-selected symlinks | `hypr/monitors.conf`, `hypr/input-devices.conf`, and `hypr/env.conf` vary by `hostName` |
| Generated theme outputs | Written by `themes/apply-theme`, not by store symlinks |
| Runtime/user scripts | Deployed through `home.file` into `~/.local/bin` |

This is the current base/generated split:

- Home Manager deploys version-controlled entry files and static trees.
- `themes/apply-theme` writes mutable outputs such as `theme.toml`,
  `colors.conf`, `appearance-theme.conf`, `GeneratedTheme.json`, and other
  generated theme files.

## Activation Flow

1. `nixos-rebuild switch --flake ~/repos/dotfiles#<host>` builds and activates
   the selected `nixosConfigurations.<host>`.
2. The embedded Home Manager module writes managed user files.
3. `home.activation.applyTheme` runs `themes/apply-theme sync`.
4. `sync` materializes only `SYNC_SAFE` targets and skips runtime reload hooks.

The `nrs` alias in `home/shell.nix` is the preferred wrapper for this flow.
