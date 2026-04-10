# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, optional
distributed-build wiring, and embedded Home Manager layer as of 2026-04-10.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | `flake.nix:24-104` exports `nixosConfigurations.vm`, `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default`, `packages.x86_64-linux.desktopctl`, and `packages.x86_64-linux.helium` |
| Host constructor | `mkHost` in `flake.nix:34-61` wraps `nixpkgs.lib.nixosSystem` |
| Feature flags | `flake.nix:26-32` keeps both `enableMarchOptimizations` and `enableDistributedBuilds` in the shared host constructor, with distributed builds currently disabled by default |
| Shared system layer | `system/configuration.nix:1-446` |
| Home Manager entry | `home/default.nix:1-350`, embedded through `home-manager.nixosModules.home-manager` in `flake.nix:49-59` |
| Platform | `flake.nix:41-42` passes `system = "x86_64-linux"` directly to `nixosSystem` |

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
| `hosts/laptop/system.nix` | Laptop overlay | Hybrid GPU policy, laptop-only services and overrides, GRUB, laptop hardware policy, and the laptop `tailscaled` stop-timeout override |
| `hosts/laptop/fan-control.nix` | Laptop-only hardware submodule | Dell SMM kernel module wiring, BIOS fan-control handoff, `i8kmon.conf`, and the `i8kmon` systemd service |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, desktop-only packages/services, storage mounts, GRUB, desktop-only overlay imports, and the desktop `tailscaled` stop-timeout override |
| `home/default.nix` | Shared user baseline | User packages that do not require system-scoped helper registration, `xdg.configFile` mappings, host-specific Hyprland file selection, desktop entry overrides, and theme activation |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, and shell helpers |
| `home/gtk.nix` | GTK submodule | GTK packages and small dconf defaults |
| `pkgs/helium/default.nix` | Prebuilt browser package | Fetches the upstream Helium release tarball, auto-patches the bundled ELFs, wraps the upstream launcher, and installs desktop assets using the pin from `pkgs/helium/source.nix:1-6` |
| `overlays/local-packages.nix` | Local package overlay | Exposes the repo's `desktopctl` and `helium` derivations, carries the repo-local `sf-pro` font package, and applies small nixpkgs overrides such as the LM Studio AppImage fixups |

## Overlay Usage

- `overlays/local-packages.nix:1-73` exposes `pkgs.desktopctl` from the local
  `desktopctl/` derivation, `pkgs.helium` from `pkgs/helium/`, defines a
  repo-local `pkgs.sf-pro` derivation that fetches the current Apple
  `SF-Pro.dmg` and unpacks `Payload~` via `cpio` when present, and carries the
  `pkgs.lmstudio` override that rewrites nixpkgs' stale AppImage icon path to
  the current upstream AppImage's real
  `resources/app/.webpack/Icon-512x512.png` asset and skips the bundled `lms`
  post-install fixup when the release only ships an empty placeholder file.
- `flake.nix:63-74` exports that overlay as `self.overlays.default` and also
  exposes `packages.x86_64-linux.desktopctl` and
  `packages.x86_64-linux.helium`.
- `system/configuration.nix:5-9` imports both the `desktopctl` overlay and the
  optional march-optimization overlay; `system/configuration.nix:199-203`
  applies them globally, and `system/configuration.nix:232-256` installs the
  local `pkgs.sf-pro` derivation through the shared `fonts.packages` list.
- `overlays/march-optimized.nix:167-169` optionally rebuilds `desktopctl` and
  other selected derivations with march tuning.
- `system/configuration.nix:10-90` also defines a Hyprland-only helper that
  always appends `-O3 -march=native` to the flake-provided `hyprland`,
  `xdg-desktop-portal-hyprland`, `hyprbars`, and `hyprexpo` derivations,
  independent of the global `enableMarchOptimizations` flag.
- `hosts/desktop/system.nix:4-8` still appends
  `overlays/nvidia-open-pr996.nix` for the desktop-specific NVIDIA workaround.
- `hosts/laptop/system.nix:78-84` and `hosts/desktop/system.nix:74-77`
  cap `tailscaled` shutdown at 15 seconds on the physical hosts, bounding rare
  upstream stop hangs without changing the shared VM profile.

## Distributed Builds

The distributed-build subsystem is present in the shared module graph even
though the repo currently ships with it disabled.

| Surface | Current implementation |
| --- | --- |
| Flag state | `flake.nix:29-31` sets `enableDistributedBuilds = false`, so the distributed-build module evaluates but its host-specific `mkIf` payload stays inactive |
| Shared module import | `system/configuration.nix:164-166` always imports `./distributed-builds.nix` |
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

- `system/configuration.nix:375-377` enables `programs.partition-manager`,
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
