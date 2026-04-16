# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, optional
distributed-build wiring, and embedded Home Manager layer as of 2026-04-13.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | The `outputs` attrset in `flake.nix` exports `nixosConfigurations.vm`, `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default`, `packages.x86_64-linux.desktopctl`, and `packages.x86_64-linux.helium` |
| Host constructor | `mkHost` in `flake.nix` wraps `nixpkgs.lib.nixosSystem` |
| Feature flags | The top-level `enableMarchOptimizations` and `enableDistributedBuilds` bindings in `flake.nix` stay shared across all hosts, with distributed builds currently disabled by default |
| Shared system layer | The top-level shared NixOS module in `system/configuration.nix` |
| Home Manager entry | `home/default.nix`, embedded through the inline Home Manager module inside `mkHost` in `flake.nix` |
| Platform | `mkHost` in `flake.nix` passes `system = "x86_64-linux"` directly to `nixosSystem` |

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
| `system/configuration.nix` | Shared system baseline | Nix settings, the shared unfree allowlist used by both NixOS and embedded Home Manager, overlays, common users/groups, shared services, privileged desktop helper registrations, shared Tailscale operator configuration, system packages, and Hyprland packaging |
| `system/distributed-builds.nix` | Optional shared distributed-build layer | When enabled, configures remote builders, the post-build cache push hook, `nix.sshServe`, and LAN-only SSH firewall rules |
| `system/distributed-builds-data.nix` | Environment-specific builder/cache data | Authorized builder keys, host keys, current cache signing key, and the current cache URL override |
| `hosts/vm/system.nix` | VM overlay | VM boot, guest profile, and virtual disk layout |
| `hosts/laptop/system.nix` | Laptop overlay | Hybrid GPU policy, laptop-only services and overrides, fingerprint/PAM policy, laptop-scoped polkit rules, GRUB, laptop hardware policy, and the laptop `tailscaled` stop-timeout override |
| `hosts/laptop/fan-control.nix` | Laptop-only hardware submodule | Dell SMM kernel module wiring, BIOS fan-control handoff, the explicit four-state `i8kmon.conf` profile with aggressive ramp thresholds, and the `i8kmon` systemd service |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, desktop-only imports, storage mounts, GRUB, desktop-only overlay imports, the desktop Windows VM toggle, and the desktop `tailscaled` stop-timeout override |
| `hosts/desktop/wine-ableton.nix` | Desktop Wine/audio submodule | Loads the `ntsync` kernel module at boot, enables `services.pipewire.jack.enable`, and installs the desktop's Ableton-facing Wine toolchain (`wineWow64Packages.stableFull`, `wineasio`, and `winetricks`) |
| `hosts/desktop/windows-vm.nix` | Desktop Windows VM submodule | Defines `virtualisation.windowsVm`, seeds the desktop qcow2/OVMF/TPM state under `/var/lib/windows-vm/windows11` during activation, grants the desktop user `kvm` access, and installs the `windows-vm` QEMU launcher |
| `home/default.nix` | Shared user baseline | User packages that do not require system-scoped helper registration, small package-level overrides such as the local OpenCode Nix build workaround, host-specific user-package wrappers, `xdg.configFile` mappings, host-specific Hyprland file selection, desktop entry overrides including the desktop Ableton Wine launcher variants, and theme activation |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, shell helpers, and sourcing the generated `~/.config/zsh/theme-colors` fragment from `programs.zsh.initContent` |
| `home/gtk.nix` | GTK submodule | GTK packages and small dconf defaults |
| `pkgs/helium/default.nix` | Prebuilt browser package | Fetches the upstream Helium release tarball, auto-patches the bundled ELFs, wraps the upstream launcher, and installs desktop assets using the pin in `pkgs/helium/source.nix` |
| `overlays/local-packages.nix` | Local package overlay | Exposes the repo's `desktopctl` and `helium` derivations, carries the repo-local `sf-pro` font package, and applies small nixpkgs overrides such as the Lapce Vulkan-loader runtime fix and the LM Studio AppImage fixups |

## Overlay Usage

- `overlays/local-packages.nix` exposes `pkgs.desktopctl` from the local
  `desktopctl/` derivation, `pkgs.helium` from `pkgs/helium/`, defines a
  repo-local `pkgs.sf-pro` derivation that fetches Apple's stable-url
  `SF-Pro.dmg` with a repo-pinned hash and unpacks `Payload~` via `cpio` when
  present, overrides `pkgs.lapce` so `bin/.lapce-wrapped` gains the
  `pkgs.vulkan-loader` library directory in its runtime search path for
  `wgpu`, and carries the `pkgs.lmstudio` override that rewrites nixpkgs'
  stale AppImage icon path to the current upstream AppImage's real
  `resources/app/.webpack/Icon-512x512.png` asset and skips the bundled `lms`
  post-install fixup when the release only ships an empty placeholder file.
- The `overlays.default` and `packages.x86_64-linux` exports in `flake.nix`
  expose that overlay and also
  exposes `packages.x86_64-linux.desktopctl` and
  `packages.x86_64-linux.helium`.
- In `system/configuration.nix`, the local `let` block imports both the
  `desktopctl` overlay and the optional march-optimization overlay;
  `nixpkgs.overlays` applies them globally, and `fonts.packages` installs the
  local `pkgs.sf-pro` derivation.
- `overlays/march-optimized.nix` optionally rebuilds `desktopctl` and
  other selected derivations with march tuning.
- `system/configuration.nix` also defines the `optimizeHyprlandNativePackage`
  helper that
  always appends `-O3 -march=native` to the flake-provided `hyprland`,
  `xdg-desktop-portal-hyprland`, `hyprbars`, and `hyprexpo` derivations,
  independent of the global `enableMarchOptimizations` flag.
- Those Hyprland-family derivations also carry the repo-local patch stack from
  `system/configuration.nix`: the compositor patch extends per-corner rounding
  control to both texture and rect paths, and the `hyprbars` compatibility
  patch now consumes that renderer support instead of the older oversized
  rounded titlebar fill workaround. The same module also re-calls nixpkgs'
  `pkgs/applications/window-managers/hyprwm/hyprland-plugins/default.nix`
  with `hyprland = patchedHyprland` and passes that helper set back through the
  upstream plugin overrides so `mkHyprlandPlugin` resolves the patched
  Hyprland headers, not the unpatched package-set default.
- The desktop host module's `nixpkgs.overlays` list in `hosts/desktop/system.nix`
  still appends
  `overlays/nvidia-open-pr996.nix` for the desktop-specific NVIDIA workaround.
- The desktop host also imports `hosts/desktop/windows-vm.nix` and enables
  `virtualisation.windowsVm`, which currently wraps a local QEMU + `swtpm`
  Windows guest with Microsoft-keyed OVMF firmware from `pkgs.OVMFFull.fd`.
  Activation seeds the writable `OVMF_VARS.ms.fd` copy and sparse
  `system.qcow2` under `/var/lib/windows-vm/windows11`, while the generated
  `windows-vm` launcher runs the guest as the desktop user instead of a root
  systemd service. `docs/nix/windows-vm.md` documents the operational steps.
- Both physical host modules set
  `systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s"`, bounding
  rare upstream stop hangs without changing the shared VM profile.
- The shared system baseline also sets
  `services.tailscale.extraSetFlags = [ "--operator=kevin" ]` so
  user-session Quickshell calls to `tailscale up` / `tailscale down` can manage
  the local daemon without `sudo`.
- `hosts/laptop/system.nix` enables `services.fprintd`, keeps the laptop PAM
  `polkit-1.fprintAuth` path available for external apps that explicitly use
  polkit system authentication, and also adds a narrow polkit rule granting the
  active local user direct `net.reactivated.fprint.device.enroll` access so the
  Quickshell fingerprint-management flow can enroll/delete prints without a
  separate external auth-agent prompt.

## Distributed Builds

The distributed-build subsystem is present in the shared module graph even
though the repo currently ships with it disabled.

| Surface | Current implementation |
| --- | --- |
| Flag state | The `enableDistributedBuilds = false` binding in `flake.nix` leaves the distributed-build module evaluated but inactive |
| Shared module import | `system/configuration.nix` always imports `./distributed-builds.nix` |
| Host gating | `system/distributed-builds.nix` only activates the subsystem inside the `enableDistributedBuilds'` host gate for `desktop` or `laptop` |
| Cache URL | The `cacheUrl` fallback in `system/distributed-builds.nix` points at `http://<homelab>:5000`, but `system/distributed-builds-data.nix` currently overrides it to `http://192.168.8.153:5050` |
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
  `colors.conf`, `appearance-theme.conf`, `theme-colors`, and the other
  generated theme files.
- The recursive Quickshell tree is the deliberate exception: Home Manager
  deploys `config/quickshell/` recursively, which includes the committed
  `config/quickshell/GeneratedTheme.json` bootstrap snapshot, and the
  Quickshell target implementation in `desktopctl/src/theme/targets/quickshell.rs`
  then overwrites the live
  `~/.config/quickshell/GeneratedTheme.json` path during activation/runtime.

Privileged desktop helper wiring currently bypasses Home Manager for one shared
GUI package:

- `system/configuration.nix` enables `programs.partition-manager`,
  which installs `kdePackages.partitionmanager` and `kdePackages.kpmcore`
  through the NixOS module so `kpmcore` lands in both
  `services.dbus.packages` and `environment.systemPackages`.
- The `home.packages` list in `home/default.nix` no longer lists
  `kdePackages.partitionmanager`
  directly; the nearby comment documents that the move is required because the
  helper depends on system-wide D-Bus and polkit registration.

## Activation Flow

1. `nixos-rebuild switch --flake ~/repos/dotfiles#<host>` builds and activates
   the selected `nixosConfigurations.<host>`.
2. The embedded Home Manager module writes managed user files.
3. The `home.activation.applyTheme` hook in `home/default.nix` prepends
   `pkgs.desktopctl` to `PATH`, bootstraps `~/.config/hypr/input-runtime.conf`,
   and runs `desktopctl theme sync`.
4. `sync` materializes only `sync_safe` targets and skips runtime reload hooks.

The `nrs` alias in `home/shell.nix` remains the preferred wrapper for this
flow.
