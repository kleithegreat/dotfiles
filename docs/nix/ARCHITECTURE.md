# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, and embedded
Home Manager layer as of 2026-04-19.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | The `outputs` attrset in `flake.nix` exports `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default`, `packages.x86_64-linux.desktopctl`, `packages.x86_64-linux.helium`, `packages.x86_64-linux.openchamber`, and `packages.x86_64-linux.openchamber-claude-bridge` |
| Host constructor | `mkHost` in `flake.nix` wraps `nixpkgs.lib.nixosSystem` and passes the shared `host` fact record into both the NixOS and Home Manager module graphs |
| Feature flags | The top-level `enableNativeOptimizations` binding in `flake.nix` stays shared across both hosts |
| Shared system layer | The top-level shared NixOS root module in `system/configuration.nix`, which imports the concern-specific shared modules under `system/` |
| Home Manager entry | `home/default.nix`, embedded through the inline Home Manager module inside `mkHost` in `flake.nix`, which imports the concern-specific shared modules under `home/` |
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
| `system/configuration.nix` | Shared system root module | Nix settings, the shared unfree allowlist used by both NixOS and embedded Home Manager, overlays, Hyprland packaging, the repo-wide fontconfig baseline, shared non-Qt session env, base system packages, locale/docs, and imports of the concern-specific shared system modules |
| `system/physical-host.nix` | Shared physical-host module | Shared physical-host defaults for the native kernel package set, `kvm-intel`, the shared Windows VM enablement, zram, Intel firmware/microcode, GRUB/EFI bootloader setup, `mitigations=off` plus `transparent_hugepage=madvise`, serialized local build scheduling, DHCP fallback, tailscaled stop-timeout bounding, and runtime kernel tuning (`bbr`/`fq`, autogroup, and MGLRU `min_ttl_ms`) |
| `system/qt.nix` | Shared Qt module | The optimized `hyprqt6engine` derivation, NixOS `qt.enable`, Qt platform/plugin env, and the shared qtct/Kvantum/hyprqt6engine system packages |
| `system/users.nix` | Shared user/admin module | The shared `programs.zsh` baseline, the `kevin` user declaration, and shared OpenSSH policy |
| `system/services.nix` | Shared service module | PKI trust, firewall defaults, XDG portals, SDDM plus the custom `where_is_my_sddm_theme` package install needed for `/run/current-system/sw/share/sddm/themes`, root-only weekly `fstrim`, PipeWire/WirePlumber, Bluetooth, printing, Samba, Docker/libvirt, GeoClue, Tailscale, Mullvad, gnome-keyring, GVFS, dconf, Partition Manager, and the system-level Bitwarden install required for polkit wiring |
| `system/native-optimizations.nix` | Shared helper | Centralizes the userspace `-O3 -march=native` / `target-cpu=native` flag sets, the kernel-specific `KCFLAGS=-O2 -march=native` / `KRUSTFLAGS=-Ctarget-cpu=native` flags, the per-host `native-optimized-<host>` feature marker, and the `overrideAttrs` helpers reused by the overlay, Hyprland-family packages, and Home Manager flake-input packages |
| `system/native-kernel-packages.nix` | Shared helper | Derives the physical-host kernel package set from the stock nixpkgs `linux_6_18` source, rebuilds it with Clang + LLD ThinLTO, applies an explicit BORE patch stack plus a `tcp/bbr3` patch on top, bakes in the shared BORE/BBR3/HZ=1000/NO_HZ_IDLE/THP=madvise/MGLRU Kconfig overrides, layers host-local `KCFLAGS=-O2 -march=native` / `KRUSTFLAGS=-Ctarget-cpu=native`, and carries the same per-host native build feature tag used by the rest of the optimized package set |
| `hosts/laptop/system.nix` | Laptop overlay | The laptop's voluntary-preempt plus Intel-only Kconfig trim, hybrid GPU policy, laptop-only services and overrides, fingerprint/PAM policy, laptop-scoped polkit rules, and laptop hardware policy |
| `hosts/laptop/fan-control.nix` | Laptop-only hardware submodule | Dell SMM kernel module wiring, BIOS fan-control handoff, the explicit four-state `i8kmon.conf` profile with aggressive ramp thresholds, and the `i8kmon` systemd service |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, the desktop's PREEMPT_FULL plus desktop-only dead-subsystem Kconfig culls and VM writeback/cache-pressure sysctls, storage mounts, desktop-only overlay imports, and the desktop's forced `power-profiles-daemon` performance profile |
| `system/windows-vm.nix` | Shared Windows VM submodule | Defines `virtualisation.windowsVm`, seeds the qcow2/OVMF/TPM state under `/var/lib/windows-vm/windows11` during activation, grants the configured user `kvm` access, and installs the `windows-vm` QEMU launcher on physical hosts |
| `home/default.nix` | Shared Home Manager root module | Shared optimized package derivations, the shared XDG user-dir policy, small activation/git/chromium glue, and imports of the concern-specific Home Manager modules |
| `home/packages.nix` | Shared package module | The shared `home.packages` selection for CLI tools, desktop apps, and media tooling plus the Home Manager-managed Vicinae service package wiring |
| `home/xdg.nix` | Shared XDG module | Data-driven `xdg.configFile` source maps including the Home Manager-owned Ghostty/Vicinae base configs, host-specific Hyprland file selection through `host.hyprland.*`, the VS Code desktop-entry override, and MIME defaults |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, shell helpers, and sourcing the generated `~/.config/zsh/theme-colors` fragment from `programs.zsh.initContent` |
| `home/gtk.nix` | GTK submodule | GTK packages and small dconf defaults |
| `pkgs/helium/default.nix` | Prebuilt browser package | Fetches the upstream Helium release tarball, auto-patches the bundled ELFs, wraps the upstream launcher, and installs desktop assets using the pin in `pkgs/helium/source.nix` |
| `pkgs/openchamber/cli.nix`, `pkgs/openchamber-desktop/default.nix`, and `pkgs/openchamber/default.nix` | Source-built OpenChamber package set | `pkgs/openchamber/cli.nix` still fetches the upstream OpenChamber source tarball, applies `patches/openchamber/claude-backend-selector.patch`, restores the repo-pinned root `package.json` plus `package-lock.json` from `pkgs/openchamber/`, builds the `packages/web` workspace with npm workspace support, and wraps the CLI with the store path to `openchamber-claude-bridge` so the app can auto-manage the Claude backend. `pkgs/openchamber-desktop/default.nix` builds a small local Tauri shell from `pkgs/openchamber-desktop/` that launches that wrapped CLI in desktop mode, reuses the remembered desktop port from `~/.config/openchamber/settings.json`, skips ports already claimed by the CLI runtime, relies on a single-instance Tauri plugin so repeated launcher invocations refocus the existing app instead of starting more local servers, opens the web UI in an undecorated window to avoid GTK headerbar chrome, requests `openchamber stop` in the background during app exit so the shell does not block on CLI teardown, and disables WebKitGTK's dmabuf renderer in the wrapper so Wayland launches do not trip the current syncobj protocol bug. `pkgs/openchamber/default.nix` then publishes the user-facing `openchamber` package as a `symlinkJoin` of the CLI plus the desktop app, with the desktop entry pointing at `openchamber-desktop` while the `openchamber` CLI remains available. |
| `pkgs/openchamber-claude-bridge/default.nix` | Claude Code bridge package | Wraps the local `pkgs/openchamber-claude-bridge/index.mjs` compatibility server that exposes the OpenCode endpoint subset OpenChamber uses and forwards chat turns into the `claude` CLI |
| `overlays/local-packages.nix` | Local package overlay | Exposes the repo's `desktopctl`, `helium`, `openchamber`, `openchamber-cli`, `openchamber-desktop`, and `openchamber-claude-bridge` derivations, carries the repo-local `sf-pro` font package, and applies small nixpkgs overrides such as the Lapce Vulkan-loader runtime fix and the LM Studio AppImage fixups |

## Overlay Usage

| Surface | Current implementation |
| --- | --- |
| `overlays/local-packages.nix` | Exposes the repo's packaged apps (`desktopctl`, `helium`, `openchamber`, `openchamber-cli`, `openchamber-desktop`, `openchamber-claude-bridge`), carries the repo-local `sf-pro` font derivation, and applies the small Lapce and LM Studio nixpkgs fixups. |
| Flake exports | `flake.nix` exposes `overlays.default` plus the packaged `desktopctl`, `helium`, `openchamber`, and `openchamber-claude-bridge` outputs for `x86_64-linux`. |
| Shared native overlay | `overlays/native-optimized.nix` rebuilds selected nixpkgs packages (`desktopctl`, `lapce`, `pipewire`, `quickshell`, `fd`, `ripgrep`, and the repo's TeX Live environment) with host-native flags while deliberately leaving low-level rebuild multipliers such as `zstd` and `lz4` stock. |
| Shared system consumers | `system/configuration.nix` applies only the repo overlays globally, uses a local `optimizedPkgs` set for PipeWire/WirePlumber, and reuses `system/native-optimizations.nix` directly for the patched Hyprland-family derivations. |
| Home Manager consumers | `home/default.nix` reuses the same native helper for the OpenCode, Snappy Switcher, and Vicinae overrides, including the pinned upstream OpenCode `node_modules` hash fix, while `home/packages.nix` installs the selected host-native user packages explicitly. |
| Desktop-only extras | `hosts/desktop/system.nix` appends `overlays/nvidia-open-pr996.nix`. |

## Shared Runtime Highlights

| Surface | Current implementation |
| --- | --- |
| Physical-host gate | `system/physical-host.nix` owns the native kernel package selection, `mitigations=off`, `transparent_hugepage=madvise`, `kvm-intel`, the shared Windows VM enablement, zram, Intel firmware/microcode, serialized local build scheduling, DHCP fallback, GRUB/EFI, the tailscaled stop-timeout cap, and the shared `bbr`/`fq`/autogroup/MGLRU runtime tuning. |
| Qt runtime | `system/qt.nix` enables NixOS `qt.enable`, exports the `hyprqt6engine` platform/plugin env, and installs qtct/Kvantum packages system-wide so direct apps and D-Bus/systemd-activated helpers resolve the same theme plugins. |
| Filesystem trim | `system/services.nix` replaces the stock `services.fstrim` unit with `fstrim-root.service` plus `fstrim-root.timer` so weekly discard stays pinned to `/` and does not also trim a shared `/boot/efi` mount. |
| Laptop-only runtime | `hosts/laptop/system.nix` keeps the fingerprint and fan-control stack plus the laptop-specific kernel trim and hybrid-GPU policy. |
| Shared physical-host VM runtime | `system/windows-vm.nix` installs the `windows-vm` launcher and keeps the Windows guest state rooted at `/var/lib/windows-vm/windows11` on both physical hosts. |
| Desktop-only runtime | `hosts/desktop/system.nix` keeps the NVIDIA policy, forced performance profile, desktop-specific kernel trim, and the extra desktop VM writeback/cache-pressure sysctls. |

## Home Manager Deployment Model

| Pattern | Current use |
| --- | --- |
| Base files via `xdg.configFile` | Hyprland base files, Alacritty, Ghostty, tmux, Vicinae, Zathura, recursive `quickshell/`, recursive `nvim/`, Git ignore, and packaged Snappy Switcher themes |
| Host-selected symlinks | `hypr/autostart-host.conf`, `hypr/monitors.conf`, `hypr/input-devices.conf`, and `hypr/env.conf` vary by the `host.hyprland.*` facts passed from `flake.nix` |
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
- The `home.packages` list in `home/packages.nix` no longer lists
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
flow. When native optimizations are enabled, that wrapper also passes the
target `system-features` list to `nixos-rebuild` so the current daemon can
schedule host-tagged `requiredSystemFeatures` derivations before the new
`/etc/nix/nix.conf` is active.
