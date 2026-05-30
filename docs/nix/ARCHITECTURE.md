# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, and embedded
Home Manager layer as of 2026-05-24.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | The `outputs` attrset in `flake.nix` exports `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default`, `packages.x86_64-linux.desktopctl`, `packages.x86_64-linux.helium`, `packages.x86_64-linux.openchamber`, `packages.x86_64-linux.openchamber-claude-bridge`, `packages.x86_64-linux.openchamber-backend-mux`, and `packages.x86_64-linux.snappy-switcher` |
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
| `system/physical-host.nix` | Shared physical-host module | Shared physical-host defaults for the stock nixpkgs kernel package set, `kvm-intel`, zram, Intel firmware/microcode, I2C device access for DDC/CI monitor brightness, GRUB/EFI bootloader setup, the broad `mitigations=off` kernel parameter plus `transparent_hugepage=madvise`, limited local build concurrency (`max-jobs = 2`), DHCP fallback, tailscaled stop-timeout bounding, runtime kernel tuning (`bbr`/`fq`, autogroup, and MGLRU `min_ttl_ms`), and `kernel-oom-notifier.service` for desktop OOM kill notifications |
| `system/qt.nix` | Shared Qt module | The optimized `hyprqt6engine` derivation, NixOS `qt.enable`, Qt platform/plugin env, and the shared qtct/Kvantum/hyprqt6engine system packages |
| `system/users.nix` | Shared user/admin module | The shared `programs.zsh` baseline, the `kevin` user declaration with desktop hardware access groups including `i2c`, and shared OpenSSH policy |
| `system/services.nix` | Shared service module | PKI trust for `certs/homelab-ca.crt`, firewall defaults, XDG portals, SDDM plus the custom `where_is_my_sddm_theme` package install and the root-owned `/tmp`-to-`/var/lib/desktopctl/where-is-my-sddm-theme/background` sync bridge that keeps the greeter background aligned with the staged `desktopctl` wallpaper, root-only weekly `fstrim`, PipeWire/WirePlumber, disabled-by-default Bluetooth/Blueman, printing/Avahi, and Samba declarations, Podman with Docker-compatible CLI shim, libvirt, GeoClue with `where-am-i` app authorization, automatic timezone updates through `automatic-timezoned`, Tailscale, Mullvad, gnome-keyring, GVFS, dconf, Partition Manager, and the system-level Bitwarden install required for polkit wiring |
| `system/native-optimizations.nix` | Shared helper | Centralizes the userspace `-O3 -march=native` / `target-cpu=native` flag sets, the per-host `native-optimized-<host>` feature marker, and the `overrideAttrs` helpers reused by the overlay, Hyprland-family packages, and Home Manager flake-input packages |
| `hosts/laptop/system.nix` | Laptop overlay | The laptop's voluntary-preempt plus Intel-only Kconfig trim, hybrid GPU policy, Logitech wireless/Solaar enablement, laptop-only services and overrides, the `laptop-power-profile` helper that wraps `powerprofilesctl` with the laptop's E-core-biased CPU hotplug policy, fingerprint/PAM policy, laptop-scoped polkit rules, and laptop hardware policy |
| `hosts/laptop/fan-control.nix` | Laptop-only hardware submodule | Dell SMM kernel module wiring, BIOS fan-control handoff, the explicit four-state `i8kmon.conf` profile with aggressive ramp thresholds, and the `i8kmon` systemd service |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, the desktop's host-generated initrd module list, VM writeback/cache-pressure sysctls, storage mounts, desktop-only overlay imports, Steam enablement with Remote Play/local transfer firewall and Wayland controller extest support, and the desktop's forced `power-profiles-daemon` performance profile |
| `docs/archive/vms/` | Archived VM setup | Inert historical copies of the old shared Windows VM module/runbook and desktop-only macOS VM module/runbook. These files are not imported by the live flake. |
| `home/default.nix` | Shared Home Manager root module | Shared optimized package derivations, the shared XDG user-dir policy, small activation/git glue, the `browserExtensions` list shared between `programs.chromium.extensions` and the generated `~/.config/net.imput.helium/External Extensions/<id>.json` files in `heliumExtensionFiles`, and imports of the concern-specific Home Manager modules |
| `home/packages.nix` | Shared package module | The shared `home.packages` selection for CLI tools, desktop apps, editors including Zed, and media tooling, including `brightnessctl` plus `ddcutil` for the unified brightness path, plus Vicinae as an installed launcher without the Home Manager service enabled, `mission-center` as the GTK system monitor, `bambu-studio` through the temporary AppImage overlay workaround described in `docs/nix/QUIRKS.md`, and KDE's `kimageformats` plugin package so Gwenview can decode HEIC/HEIF images |
| `home/xdg.nix` | Shared XDG module | Data-driven `xdg.configFile` source maps including the Home Manager-owned Ghostty/Vicinae base configs, host-specific Hyprland file selection through `host.hyprland.*`, the VS Code desktop-entry override, and MIME defaults including Gwenview for HEIC/HEIF images |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, shell helpers, the `nrs` rebuild wrapper that re-enables Hyprland autoreload and replaces the Hyprland-owned Vicinae server after a successful switch, and sourcing the generated `~/.config/zsh/theme-colors` fragment from `programs.zsh.initContent` |
| `home/gtk.nix` | GTK submodule | GTK packages, the repo-packaged upstream-shaped Neuwaita icon theme with normalized inheritance syntax plus a derived `Neuwaita-KDE` wrapper for Qt/KDE recoloring and Breeze fallback ordering, Neuwaita folder-name aliases for GTK/KDE lookup, and small dconf defaults |
| `desktopctl/default.nix` | Repo Rust package | Builds the `desktopctl` binary and wraps it with `coreutils` plus GeoClue's demo helper directory on `PATH` so solar location lookup can invoke `timeout where-am-i` without relying on ambient session paths |
| `pkgs/helium/default.nix` | Prebuilt browser package | Fetches the upstream Helium release tarball, auto-patches the bundled ELFs, wraps the upstream launcher with the Chromium-family GTK file-dialog runtime libraries/data plus media/GL library paths, and installs desktop assets using the pin in `pkgs/helium/source.nix` |
| `pkgs/openchamber/cli.nix`, `pkgs/openchamber-desktop/default.nix`, and `pkgs/openchamber/default.nix` | Source-built OpenChamber package set | `pkgs/openchamber/cli.nix` still fetches the upstream OpenChamber source tarball, applies the local OpenChamber patch set (`patches/openchamber/claude-backend-selector.patch`, `patches/openchamber/mixed-backend-mux.patch`, and the desktop popup-performance patch), restores the repo-pinned root `package.json` plus `package-lock.json` from `pkgs/openchamber/`, builds the `packages/web` workspace with npm workspace support, and wraps the CLI with store paths to both `openchamber-claude-bridge` and `openchamber-backend-mux`. The selector patch still exposes OpenCode-only and Claude-only runtime modes, `patches/openchamber/mixed-backend-mux.patch` adds a third `mixed` mode plus model/provider-aware session creation so the mux can pin each chat to OpenCode or Claude Code at creation time, and the local popup patch keeps the same UI behavior while trimming WebKitGTK popup-time bookkeeping by removing eager per-child resize observation from the shared overlay scrollbar helper and skipping mutation tracking for static select option lists. `pkgs/openchamber-desktop/default.nix` builds a small local Tauri shell from `pkgs/openchamber-desktop/` that launches that wrapped CLI in desktop mode, reuses the remembered desktop port from `~/.config/openchamber/settings.json`, skips ports already claimed by the CLI runtime, relies on a single-instance Tauri plugin so repeated launcher invocations refocus the existing app instead of starting more local servers, opens the web UI in an undecorated window to avoid GTK headerbar chrome, requests `openchamber stop` in the background during app exit so the shell does not block on CLI teardown, and disables WebKitGTK's dmabuf renderer in the wrapper so Wayland launches do not trip the current syncobj protocol bug. `pkgs/openchamber/default.nix` then publishes the user-facing `openchamber` package as a `symlinkJoin` of the CLI plus the desktop app, with the desktop entry pointing at `openchamber-desktop` while the `openchamber` CLI remains available. |
| `pkgs/openchamber-claude-bridge/default.nix` | Claude Code bridge package | Wraps the local `pkgs/openchamber-claude-bridge/index.mjs` compatibility server that exposes the OpenCode endpoint subset OpenChamber uses, pins `CLAUDE_CODE_BIN` to the packaged `claude-code` executable, and forwards chat turns into that CLI |
| `pkgs/openchamber-backend-mux/default.nix` | Mixed backend mux package | Wraps `pkgs/openchamber-backend-mux/index.mjs`, pins `OPENCHAMBER_BACKEND_MUX_OPENCODE_BINARY` to the packaged `opencode` executable, runs the local Node test suite during the derivation check phase, and provides a lightweight HTTP multiplexer that starts both OpenCode and the Claude bridge, cleans up any already-started backend if startup fails, normalizes mixed provider catalogs (including OpenCode's plain-string provider IDs), merges provider/model/session listings plus the global `/experimental/session` pages the sidebar consumes, forwards selected `model` / `variant` / `agent` fields when creating new sessions, routes session-specific calls by session ID, and lets one OpenChamber runtime host chats pinned to different backends |
| `pkgs/hyprland-plugins/hyprexpo/default.nix` | Local Hyprland plugin package | Extracts the removed Hyprexpo source from upstream `hyprwm/hyprland-plugins` revision `eaf18d55d51cef00818c5a4fdd4170f8cc2de4dc`, applies `patches/hyprland-plugins/hyprexpo-hyprland-0.54.patch`, and builds it through the same `hyprlandPlugins.mkHyprlandPlugin` helper that `system/configuration.nix` points at the patched Hyprland package |
| `overlays/local-packages.nix` | Local package overlay | Exposes the repo's `desktopctl`, `helium`, `snappy-switcher`, `openchamber`, `openchamber-cli`, `openchamber-desktop`, `openchamber-claude-bridge`, and `openchamber-backend-mux` derivations, carries the repo-local `sf-pro` font package, and temporarily overrides `bambu-studio` with a wrapped upstream AppImage plus a shell-parent desktop launcher while the source-built nixpkgs package has broken cloud login on the locked input |

The OpenChamber aggregate package in `pkgs/openchamber/default.nix` is now a
versioned symlink join of the CLI and desktop launcher. The helper packages are
self-contained: the mux wrapper pins `opencode`, and the Claude bridge wrapper
pins `claude-code`, so mixed/Claude modes do not depend on ambient `PATH`.
The trimmed OpenChamber npm manifest in `pkgs/openchamber/package.json` keeps
the web/UI workspaces only, omits upstream-only release tooling such as the
root changelog-card `sharp` dependency, and relies on `pkgs/openchamber/cli.nix`
providing `vips` so the remaining `@xenova/transformers` sharp dependency does
not try to download libvips during `npm rebuild`.

## Overlay Usage

| Surface | Current implementation |
| --- | --- |
| `overlays/local-packages.nix` | Exposes the repo's packaged apps (`desktopctl`, `helium`, `snappy-switcher`, `openchamber`, `openchamber-cli`, `openchamber-desktop`, `openchamber-claude-bridge`, `openchamber-backend-mux`), carries the repo-local `sf-pro` font derivation, and temporarily replaces source-built `bambu-studio` with a wrapped upstream AppImage because the flake's pinned nixpkgs predates the cloud-login fix in NixOS/nixpkgs#522161 and a local source rebuild is too heavy for routine switches. The AppImage desktop file is rewritten to an absolute `$out/bin/bambu-studio-desktop` shell-parent launcher, keeping Vicinae's detached launcher from orphaning the AppImage/FHS wrapper path while still avoiding ambient `PATH` lookup for the final binary. |
| Flake exports | `flake.nix` exposes `overlays.default` plus the packaged `desktopctl`, `helium`, `openchamber`, `openchamber-claude-bridge`, `openchamber-backend-mux`, and `snappy-switcher` outputs for `x86_64-linux`. The flake package import carries a narrow `claude-code` unfree allowlist because the exported Claude bridge is self-contained. |
| Shared native overlay | `overlays/native-optimized.nix` rebuilds selected nixpkgs packages (`desktopctl`, `pipewire`, `wireplumber`, `quickshell`, `fd`, `ripgrep`, `p7zip`, `lsp-plugins`, and the repo's TeX Live environment) with host-native flags while deliberately leaving low-level rebuild multipliers such as `zstd` and `lz4` stock. |
| Shared system consumers | `system/configuration.nix` applies only the repo overlays globally, uses a local `optimizedPkgs` set for PipeWire/WirePlumber, reuses `system/native-optimizations.nix` directly for the patched Hyprland-family derivations, keeps `hyprbars` on the rolling `hyprland-plugins` flake package, and builds `hyprexpo` from `pkgs/hyprland-plugins/hyprexpo/default.nix` because upstream removed that package output. |
| Home Manager consumers | `home/default.nix` now takes Snappy Switcher from the repo-local `pkgs.snappy-switcher` package exported through `overlays/local-packages.nix`, which fetches the upstream source snapshot and applies `patches/snappy-switcher/workspace-scope-filter.patch` directly instead of routing through a separate flake input. Vicinae keeps the upstream flake input only for the optional `vicinae.homeManagerModules.default` option surface, while `home/packages.nix` installs the cached `pkgs.vicinae` package directly and leaves `services.vicinae` disabled because Hyprland owns `vicinae server` startup. OpenCode and Haruna now come straight from `pkgs.opencode` and `pkgs.haruna` in the pinned `nixpkgs` set instead of separate upstream-flake or stable-package source overrides; Haruna must stay on the same Qt/KDE package set as the session-wide `hyprqt6engine` platform theme plugin. `home/packages.nix` then installs the selected host-native user packages explicitly. |
| Desktop-only extras | `hosts/desktop/system.nix` keeps the desktop-only NVIDIA suspend settings (`NVreg_TemporaryFilePath=/var/tmp`, `hardware.nvidia.powerManagement.kernelSuspendNotifier = false`, and the systemd sleep freeze workaround) plus the desktop's forced performance profile. The old PR #996 overlay has been removed because the current upstream NVIDIA open-kernel source already carries that fix, but this removal is still untested on real desktop suspend/resume hardware. |

## Shared Runtime Highlights

| Surface | Current implementation |
| --- | --- |
| Physical-host gate | `system/physical-host.nix` owns the stock nixpkgs kernel package selection, the broad `mitigations=off` kernel parameter, `transparent_hugepage=madvise`, `kvm-intel`, zram, Intel firmware/microcode, I2C device access for DDC/CI monitor brightness, limited local build concurrency (`max-jobs = 2`), DHCP fallback, GRUB/EFI, the tailscaled stop-timeout cap, the shared `bbr`/`fq`/autogroup/MGLRU runtime tuning, and `kernel-oom-notifier.service`, which tails the kernel journal as root and forwards OOM kill lines to Kevin's user notification bus with `notify-send --app-name=kernel-oom --urgency=critical`. |
| Qt runtime | `system/qt.nix` enables NixOS `qt.enable`, exports the `hyprqt6engine` platform/plugin env, and installs qtct/Kvantum packages system-wide so direct apps and D-Bus/systemd-activated helpers resolve the same theme plugins. |
| Filesystem trim | `system/services.nix` replaces the stock `services.fstrim` unit with `fstrim-root.service` plus `fstrim-root.timer` so weekly discard stays pinned to `/` and does not also trim a shared `/boot/efi` mount. |
| SDDM background bridge | `system/services.nix` seeds `/var/lib/desktopctl/where-is-my-sddm-theme/background` from `wallpapers/lmao.png`, points the `where_is_my_sddm_theme` package override at that persistent file with blur enabled, and uses `desktopctl-sddm-theme-sync.path` / `.service` to copy the user-staged `/tmp/desktopctl-where-is-my-sddm-theme/background` file into the root-owned SDDM-readable location. |
| Locality services | `system/configuration.nix` leaves `time.timeZone` unset while keeping `i18n.defaultLocale = "en_US.UTF-8"` and `console.keyMap = "us"`; `system/services.nix` sets `location.provider = "geoclue2"`, enables `services.automatic-timezoned`, keeps the GeoClue demo agent enabled, and authorizes the `where-am-i` app entry that `desktopctl` uses for solar and weather coordinates. |
| Laptop-only runtime | `hosts/laptop/system.nix` keeps the fingerprint and fan-control stack, the laptop-specific kernel trim and hybrid-GPU policy, Logitech wireless/Solaar enablement, and the laptop-only `laptop-power-profile` helper that re-onlines hotpluggable CPUs for the standard `powerprofilesctl` modes and offlines the hotpluggable P-core threads for the shell's `e-core-only` mode. |
| Desktop-only runtime | `hosts/desktop/system.nix` keeps the NVIDIA policy, forced performance profile, host-generated initrd module list, and extra desktop VM writeback/cache-pressure sysctls. |

## Home Manager Deployment Model

| Pattern | Current use |
| --- | --- |
| Base files via `xdg.configFile` | Hyprland base files, Alacritty, Ghostty, tmux, Vicinae, Zathura, Zed, recursive `quickshell/`, recursive `nvim/`, Git ignore, and packaged Snappy Switcher themes |
| Host-selected symlinks | `hypr/autostart-host.conf`, `hypr/monitors.conf`, `hypr/input-devices.conf`, and `hypr/env.conf` vary by the `host.hyprland.*` facts passed from `flake.nix` |
| Generated theme outputs | Written at activation/runtime by `desktopctl theme`, not by store symlinks |
| Runtime executables | `desktopctl` is installed as a Nix package; the old `home.file`-managed session scripts are gone |

This is the current base/generated split:

- Home Manager deploys version-controlled entry files and static trees.
- `desktopctl theme` writes mutable outputs such as `theme.toml`,
  `colors.conf`, `appearance-theme.conf`, `theme-colors`, and the other
  generated theme files.
- The recursive Quickshell tree is the remaining special case: Home Manager
  deploys `config/quickshell/` recursively, while the Quickshell target
  implementation in `desktopctl/src/theme/targets/quickshell.rs` creates or
  replaces the live `~/.config/quickshell/GeneratedTheme.json` path during
  activation/runtime. The repo does not commit that generated snapshot; first
  shell startup before sync uses `config/quickshell/Theme.qml` fallbacks.

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
flow. It disables Hyprland config autoreload during the switch, restores it
afterward, and on successful activation asks Hyprland to run `vicinae server
--replace` so the app launcher refreshes its desktop-entry view of the new
profile. When native optimizations are enabled, that wrapper also passes the
target `system-features` list to `nixos-rebuild` so the current daemon can
schedule host-tagged `requiredSystemFeatures` derivations before the new
`/etc/nix/nix.conf` is active.
