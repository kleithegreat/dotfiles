# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, and embedded
Home Manager layer as of 2026-06-10.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | The `outputs` attrset in `flake.nix` exports `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default`, `devShells.x86_64-linux.default`, `packages.x86_64-linux.desktopctl`, `packages.x86_64-linux.helium`, `packages.x86_64-linux.openchamber`, `packages.x86_64-linux.openchamber-claude-bridge`, `packages.x86_64-linux.openchamber-backend-mux`, and `packages.x86_64-linux.snappy-switcher` |
| Input branch policy | `flake.nix` keeps the primary `nixpkgs` input on `nixos-unstable`, a narrow `nixpkgs-claude` input on `master` for `claude-code` freshness, and tracks Home Manager `master` while no matching `release-26.11` branch exists. Home Manager's `nixpkgs` input follows the primary `nixpkgs` input so its release check matches the evaluated Nixpkgs release. |
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
| `system/configuration.nix` | Shared system root module | Nix settings including the `cache.nixos.org` and Vicinae substituters, the shared unfree allowlist and narrow insecure-package exceptions used by both NixOS and embedded Home Manager, the local package overlay plus the narrow `claude-code` overlay sourced from `inputs.nixpkgs-claude`, Hyprland packaging, the repo-wide fontconfig baseline, shared non-Qt session env, base system packages, locale/docs, and imports of the concern-specific shared system modules |
| `system/physical-host.nix` | Shared physical-host module | Shared physical-host defaults for the stock nixpkgs kernel package set, `boot.kernelModules = [ "kvm-intel" ]` (NAT for podman/WinBoat loads on demand through the nftables backend), zram, Intel firmware/microcode, I2C device access for DDC/CI monitor brightness, `hardware.logitech.wireless` (Solaar) for the shared MX Master 2S, GRUB/EFI bootloader setup, the broad `mitigations=off` kernel parameter plus `transparent_hugepage=madvise`, limited local build concurrency (`max-jobs = 2`), DHCP fallback, tailscaled stop-timeout bounding, runtime kernel tuning (`bbr`/`fq`, autogroup, and MGLRU `min_ttl_ms`), and `kernel-oom-notifier.service` for desktop OOM kill notifications |
| `system/qt.nix` | Shared Qt module | The optimized `hyprqt6engine` derivation, NixOS `qt.enable`, Qt platform/plugin env, and the shared qtct/Kvantum/hyprqt6engine system packages |
| `system/users.nix` | Shared user/admin module | The shared `programs.zsh` baseline, the `kevin` user declaration with desktop hardware access groups including `i2c`, and shared OpenSSH policy |
| `system/services.nix` | Shared service module | PKI trust for `certs/homelab-ca.crt`, firewall defaults, XDG portals using the Hyprland and GTK backends with GTK as the FileChooser implementation, SDDM plus the custom `where_is_my_sddm_theme` package install and the root-owned `/tmp`-to-`/var/lib/desktopctl/where-is-my-sddm-theme/background` sync bridge that keeps the greeter background aligned with the staged `desktopctl` wallpaper, root-only weekly `fstrim`, PipeWire/WirePlumber, disabled-by-default Bluetooth/Blueman, printing/Avahi, and Samba declarations, Podman with Docker-compatible CLI shim, libvirt, GeoClue with `where-am-i` app authorization, automatic timezone updates through `automatic-timezoned`, Tailscale, Mullvad, gnome-keyring, GVFS, dconf, Partition Manager, and the system-level Bitwarden install required for polkit wiring (runbook: `docs/nix/bitwarden.md`) |
| `system/native-optimizations.nix` | Shared helper | Centralizes the userspace `-O3 -march=native` / `target-cpu=native` flag sets, the per-host `native-optimized-<host>` feature marker, and the `overrideAttrs` helpers reused by the overlay, Hyprland-family packages, and Home Manager flake-input packages |
| `hosts/laptop/system.nix` | Laptop overlay | The laptop's voluntary-preempt plus Intel-only Kconfig trim, including explicit unsets for inherited AMD SEV, Hyper-V DRM/framebuffer, and Nouveau SVM child symbols that become invalid when their parent subsystems are disabled, hybrid GPU policy including `hardware.graphics.extraPackages = [ intel-media-driver ]` for the iHD VA-API driver, laptop-only services and overrides, the `laptop-power-profile` helper that wraps `powerprofilesctl` with the laptop's E-core-biased CPU hotplug policy, fingerprint/PAM policy, laptop-scoped polkit rules, Steam enablement with Remote Play/local transfer firewall and Wayland controller extest support, and laptop hardware policy |
| `hosts/laptop/fan-control.nix` | Laptop-only hardware submodule | Dell SMM kernel module wiring, BIOS fan-control handoff, the explicit four-state `i8kmon.conf` profile with aggressive ramp thresholds, and the `i8kmon` systemd service |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, the desktop's host-generated initrd module list, the writeback sysctls `vm.dirty_ratio = 10` / `vm.dirty_background_ratio = 5` (swappiness and cache-pressure stay at kernel defaults to match the shared zram-only swap policy), storage mounts including `/mnt/shared` with `nofail` + `x-systemd.device-timeout=10s` so a dead secondary data disk degrades gracefully instead of dropping to emergency mode, Steam enablement with Remote Play/local transfer firewall and Wayland controller extest support, and the desktop's forced `power-profiles-daemon` performance profile |
| `docs/archive/vms/` | Archived VM setup | Inert historical copies of the old shared Windows VM module/runbook and desktop-only macOS VM module/runbook. These files are not imported by the live flake. |
| `home/default.nix` | Shared Home Manager root module | Shared optimized package derivations, the shared XDG user-dir policy, small activation/git glue, the `browserExtensions` list shared between `programs.chromium.extensions` and the generated `~/.config/net.imput.helium/External Extensions/<id>.json` files in `heliumExtensionFiles`, and imports of the concern-specific Home Manager modules |
| `home/packages.nix` | Shared package module | The shared `home.packages` selection for CLI tools, desktop apps, editors including Zed, and media tooling, including `brightnessctl` plus `ddcutil` for the unified brightness path, a Discord package override that patches and deploys the native Krisp module through `pkgs/discord-krisp/`, Vicinae as an installed launcher without the Home Manager service enabled, `mission-center` as the GTK system monitor, Nautilus plus the explicit GLib/GDK Pixbuf helpers used for `gsettings` and image thumbnail generation, `lmstudio` and `bambu-studio` through AppImage desktop-entry fixes described in `docs/nix/QUIRKS.md`, and KDE's `kimageformats` plugin package so Gwenview can decode HEIC/HEIF images |
| `home/xdg.nix` | Shared XDG module | Data-driven `xdg.configFile` source maps including the Home Manager-owned Ghostty/Vicinae base configs, host-specific Hyprland file selection through `host.hyprland.*`, a user-level portal config kept aligned with the NixOS Hyprland/GTK portal selection so stale user config cannot force KDE file pickers, user-level desktop-entry shadows for hidden duplicate launchers plus the canonical packaged Bambu Studio desktop file, the VS Code desktop-entry override, and MIME defaults including Gwenview for HEIC/HEIF images |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, shell helpers, the `nrs` rebuild wrapper that re-enables Hyprland autoreload and replaces the Hyprland-owned Vicinae server after a successful switch, and sourcing the generated `~/.config/zsh/theme-colors` fragment from `programs.zsh.initContent` |
| `home/gtk.nix` | GTK submodule | GTK packages, the repo-packaged upstream-shaped Neuwaita icon theme with normalized inheritance syntax plus a derived `Neuwaita-KDE` wrapper for Qt/KDE recoloring and Breeze fallback ordering, Neuwaita folder-name aliases for GTK/KDE lookup, and small dconf defaults including Nautilus thumbnail preferences |
| `desktopctl/default.nix` | Repo Rust package | Builds the `desktopctl` binary and wraps it with `coreutils` plus GeoClue's demo helper directory on `PATH` so solar location lookup can invoke `timeout where-am-i` without relying on ambient session paths |
| `pkgs/helium/default.nix` | Prebuilt browser package | Fetches the upstream Helium release tarball, auto-patches the bundled ELFs, wraps the upstream launcher with the Chromium-family GTK file-dialog runtime libraries/data plus media/GL library paths, and installs desktop assets using the pin in `pkgs/helium/source.nix` |
| `pkgs/openchamber/cli.nix`, `pkgs/openchamber-desktop/default.nix`, and `pkgs/openchamber/default.nix` | Source-built OpenChamber package set | `pkgs/openchamber/cli.nix` still fetches the upstream OpenChamber source tarball, applies the local OpenChamber patch set (`patches/openchamber/claude-backend-selector.patch`, `patches/openchamber/mixed-backend-mux.patch`, and the desktop popup-performance patch), restores the repo-pinned root `package.json` plus `package-lock.json` from `pkgs/openchamber/`, builds the `packages/web` workspace with npm workspace support, and wraps the CLI with store paths to both `openchamber-claude-bridge` and `openchamber-backend-mux`. The selector patch still exposes OpenCode-only and Claude-only runtime modes, `patches/openchamber/mixed-backend-mux.patch` adds a third `mixed` mode plus model/provider-aware session creation so the mux can pin each chat to OpenCode or Claude Code at creation time, and the local popup patch keeps the same UI behavior while trimming WebKitGTK popup-time bookkeeping by removing eager per-child resize observation from the shared overlay scrollbar helper and skipping mutation tracking for static select option lists. `pkgs/openchamber-desktop/default.nix` builds a small local Tauri shell from `pkgs/openchamber-desktop/` that launches that wrapped CLI in desktop mode, reuses the remembered desktop port from `~/.config/openchamber/settings.json`, skips ports already claimed by the CLI runtime, relies on a single-instance Tauri plugin so repeated launcher invocations refocus the existing app instead of starting more local servers, opens the web UI in an undecorated window to avoid GTK headerbar chrome, requests `openchamber stop` in the background during app exit so the shell does not block on CLI teardown, and disables WebKitGTK's dmabuf renderer in the wrapper so Wayland launches do not trip the current syncobj protocol bug. The installed desktop entry is `openchamber-desktop.desktop` (renamed from `openchamber.desktop`) with `StartupWMClass=openchamber-desktop`, so the desktop-file ID matches the Wayland app_id Hyprland reports for the `--inherit-argv0`-launched binary; the icon name remains `openchamber`. The shell is built with `wrapGAppsHook3` (GTK3/webkitgtk_4_1 app) and no longer sets `GIO_MODULE_DIR` — the wrap hook's `GIO_EXTRA_MODULES` already covers glib-networking. `pkgs/openchamber/default.nix` then publishes the user-facing `openchamber` package as a `symlinkJoin` of the CLI plus the desktop app, with the desktop entry pointing at `openchamber-desktop` while the `openchamber` CLI remains available. |
| `pkgs/openchamber-claude-bridge/default.nix` | Claude Code bridge package | Wraps the local `pkgs/openchamber-claude-bridge/index.mjs` compatibility server that exposes the OpenCode endpoint subset OpenChamber uses, pins `CLAUDE_CODE_BIN` to the packaged `claude-code` executable, and forwards chat turns into that CLI. The bridge debounces state-file writes (one coalesced save instead of per-streamed-token rewrites, with a synchronous flush at run end and on SIGINT/SIGTERM) and no longer persists `nextEventId` (event IDs are seeded from process start time). A persisted `claudeSessionStarted` flag — set when the CLI emits its system/init event, migrated for legacy state files with recorded turns, and self-cleared when Claude reports an unknown session ID — decides `--session-id` vs `--resume`, so a failed first run can retry instead of resuming a nonexistent Claude session. It completes tool parts for all tools (with OpenCode error-shaped states for failed tool results), derives session titles from the first prompt instead of leaving "New Claude Code session", records the requested model/agent/variant on assistant messages, stamps `time.completed` on each assistant message at `message_stop`, supports unarchiving sessions, and rejects the synchronous POST message endpoint with a 400 instead of persisting placeholder messages |
| `pkgs/openchamber-backend-mux/default.nix` | Mixed backend mux package | Wraps `pkgs/openchamber-backend-mux/index.mjs`, pins `OPENCHAMBER_BACKEND_MUX_OPENCODE_BINARY` to the packaged `opencode` executable and `OPENCHAMBER_CLAUDE_BRIDGE_BINARY` to the packaged `openchamber-claude-bridge`, runs the local Node test suite during the derivation check phase, and provides a lightweight HTTP multiplexer that starts both OpenCode and the Claude bridge, cleans up any already-started backend if startup fails, normalizes mixed provider catalogs (including OpenCode's plain-string provider IDs), merges provider/model/session listings plus the global `/experimental/session` pages the sidebar consumes, forwards selected `model` / `variant` / `agent` fields when creating new sessions, routes session-specific calls by session ID, and lets one OpenChamber runtime host chats pinned to different backends. If either child backend dies after startup, the mux SIGTERMs the sibling and exits 1 so the OpenChamber lifecycle restarts the whole pair; merged provider/model/agent/permission/question/session/status endpoints degrade gracefully when one backend is unreachable (the dead backend contributes empty data instead of a 500), the merged `/event` SSE stream stays alive while at least one backend stream is healthy, merged `GET /session` re-applies the requested limit after merging, session-binding updates discovered during listing persist to `session-bindings.json`, and shutdown kills child backends before closing the HTTP server (closing all connections) so held SSE requests cannot orphan the backends |
| `pkgs/discord-krisp/` | Discord Krisp package helpers | Contains the local Linux-only backport of the upstream nixpkgs Krisp patcher: `patch-linux.py` bypasses the native module signature check and guards repeated initialization, `patch-voice.py` points `discord_voice` at the user-deployed Krisp module, and `deploy.py` copies the patched module into Discord's writable per-user module directory when the `Discord` launcher starts |
| `pkgs/hyprland-plugins/hyprexpo/default.nix` | Local Hyprland plugin package | Extracts the removed Hyprexpo source from upstream `hyprwm/hyprland-plugins` revision `eaf18d55d51cef00818c5a4fdd4170f8cc2de4dc`, applies `patches/hyprland-plugins/hyprexpo-hyprland-0.55.patch`, and builds it through the same `hyprlandPlugins.mkHyprlandPlugin` helper that `system/configuration.nix` points at the patched Hyprland package |
| `overlays/local-packages.nix`, `flake.nix` `claudeCodeOverlay`, and `system/configuration.nix` `claudeCodeOverlay` | Local package overlay | See the Overlay Usage table below for the full description |

The OpenChamber aggregate package in `pkgs/openchamber/default.nix` is now a
versioned symlink join of the CLI and desktop launcher. The helper packages are
self-contained: the mux wrapper pins both `opencode` and the packaged
`openchamber-claude-bridge` (via `--set-default
OPENCHAMBER_CLAUDE_BRIDGE_BINARY`), and the Claude bridge wrapper pins
`claude-code`, so the exported `openchamber-backend-mux` package works for both
backends without ambient `PATH`. Env vars (such as those set by the CLI
wrapper) still take precedence over the `--set-default` values.
The trimmed OpenChamber npm manifest in `pkgs/openchamber/package.json` keeps
the web/UI workspaces only, omits upstream-only release tooling such as the
root changelog-card `sharp` dependency, and relies on `pkgs/openchamber/cli.nix`
providing `vips` so the remaining `@xenova/transformers` sharp dependency does
not try to download libvips during `npm rebuild`.

## Overlay Usage

| Surface | Current implementation |
| --- | --- |
| `overlays/local-packages.nix`, `flake.nix` `claudeCodeOverlay`, and `system/configuration.nix` `claudeCodeOverlay` | Exposes the repo's packaged apps (`desktopctl`, `helium`, `snappy-switcher`, `openchamber`, `openchamber-cli`, `openchamber-desktop`, `openchamber-claude-bridge`, `openchamber-backend-mux`), carries the repo-local `sf-pro` font derivation, replaces `claude-code` with the package from the narrow `nixpkgs-claude` input so Claude Code can track model-support releases faster than `nixos-unstable`, replaces `lmstudio` with the upstream `0.4.15-2` x64 AppImage, and temporarily replaces source-built `bambu-studio` with a wrapped upstream AppImage because the flake's pinned nixpkgs predates the cloud-login fix in NixOS/nixpkgs#522161 and a local source rebuild is too heavy for routine switches. The AppImage desktop files are rewritten to absolute `$out/bin/lm-studio-desktop` and `$out/bin/bambu-studio-desktop` shell-parent launchers, keeping Vicinae's detached launcher from orphaning AppImage/FHS wrapper paths while still avoiding ambient `PATH` lookup for the final binaries; Bambu Studio's desktop metadata is also normalized to `StartupWMClass=BambuStudio`, matching the class Hyprland reports for the real window. |
| Flake exports | `flake.nix` exposes `overlays.default` plus the packaged `desktopctl`, `helium`, `openchamber`, `openchamber-claude-bridge`, `openchamber-backend-mux`, and `snappy-switcher` outputs for `x86_64-linux`. The flake package import carries a narrow `claude-code` unfree allowlist because the exported Claude bridge is self-contained. |
| Shared native overlay | `overlays/native-optimized.nix` rebuilds selected nixpkgs packages (`desktopctl`, `pipewire`, `wireplumber`, `quickshell`, `fd`, `ripgrep`, `p7zip`, `lsp-plugins`, and the repo's TeX Live environment) with host-native flags while deliberately leaving low-level rebuild multipliers such as `zstd` and `lz4` stock. |
| Shared system consumers | `system/configuration.nix` applies the repo-local package overlay plus the narrow `claude-code` overlay globally, uses a local `optimizedPkgs` set for PipeWire/WirePlumber, reuses `system/native-optimizations.nix` directly for the patched Hyprland-family derivations, keeps `hyprbars` on the rolling `hyprland-plugins` flake package, and builds `hyprexpo` from `pkgs/hyprland-plugins/hyprexpo/default.nix` because upstream removed that package output. |
| Home Manager consumers | `home/default.nix` now takes Snappy Switcher from the repo-local `pkgs.snappy-switcher` package exported through `overlays/local-packages.nix`, which fetches the upstream source snapshot and applies `patches/snappy-switcher/workspace-scope-filter.patch` directly instead of routing through a separate flake input. Vicinae keeps the upstream flake input only for the optional `vicinae.homeManagerModules.default` option surface, while `home/packages.nix` installs the cached `pkgs.vicinae` package directly and leaves `services.vicinae` disabled because Hyprland owns `vicinae server` startup. OpenCode and Haruna now come straight from `pkgs.opencode` and `pkgs.haruna` in the pinned `nixpkgs` set instead of separate upstream-flake or stable-package source overrides; Haruna must stay on the same Qt/KDE package set as the session-wide `hyprqt6engine` platform theme plugin. `home/packages.nix` then installs the selected host-native user packages explicitly. |
| Desktop-only extras | `hosts/desktop/system.nix` keeps the desktop-only NVIDIA suspend settings (`NVreg_TemporaryFilePath=/var/tmp`, `hardware.nvidia.powerManagement.kernelSuspendNotifier = false`, and the systemd sleep freeze workaround) plus the desktop's forced performance profile. The old PR #996 overlay has been removed because the current upstream NVIDIA open-kernel source already carries that fix, but this removal is still untested on real desktop suspend/resume hardware. |

## Shared Runtime Highlights

| Surface | Current implementation |
| --- | --- |
| Physical-host gate | `system/physical-host.nix` owns the stock nixpkgs kernel package selection, the broad `mitigations=off` kernel parameter, `transparent_hugepage=madvise`, `kvm-intel`, zram, Intel firmware/microcode, I2C device access for DDC/CI monitor brightness, `hardware.logitech.wireless` (Solaar), limited local build concurrency (`max-jobs = 2`), DHCP fallback, GRUB/EFI, the tailscaled stop-timeout cap, the shared `bbr`/`fq`/autogroup/MGLRU runtime tuning, and `kernel-oom-notifier.service`, which tails the kernel journal as root and forwards OOM kill lines to Kevin's user notification bus with `notify-send --app-name=kernel-oom --urgency=critical`. |
| Qt runtime | `system/qt.nix` enables NixOS `qt.enable`, exports the `hyprqt6engine` platform/plugin env, and installs qtct/Kvantum packages system-wide so direct apps and D-Bus/systemd-activated helpers resolve the same theme plugins. |
| Filesystem trim | `system/services.nix` replaces the stock `services.fstrim` unit with `fstrim-root.service` plus `fstrim-root.timer` so weekly discard stays pinned to `/` and does not also trim a shared `/boot/efi` mount. |
| SDDM background bridge | `system/services.nix` seeds `/var/lib/desktopctl/where-is-my-sddm-theme/background` from `wallpapers/lmao.png`, points the `where_is_my_sddm_theme` package override at that persistent file with blur enabled, and uses `desktopctl-sddm-theme-sync.path` / `.service` to copy the user-staged `/tmp/desktopctl-where-is-my-sddm-theme/background` file into the root-owned SDDM-readable location. A `systemd.tmpfiles.rules` entry pre-creates that staging directory at boot as `0700 kevin kevin` (via the `sddmThemeStagingDir` binding), so no other local user can pre-create it or symlink-swap the staged file the root-run sync copies. |
| Locality services | `system/configuration.nix` leaves `time.timeZone` unset while keeping `i18n.defaultLocale = "en_US.UTF-8"` and `console.keyMap = "us"`; `system/services.nix` sets `location.provider = "geoclue2"`, enables `services.automatic-timezoned`, keeps the GeoClue demo agent enabled, and authorizes the `where-am-i` app entry that `desktopctl` uses for solar and weather coordinates. |
| Laptop-only runtime | `hosts/laptop/system.nix` keeps the fingerprint and fan-control stack, the laptop-specific kernel trim and hybrid-GPU policy, and the laptop-only `laptop-power-profile` helper that re-onlines hotpluggable CPUs for the standard `powerprofilesctl` modes and offlines the hotpluggable P-core threads for the shell's `e-core-only` mode. |
| Desktop-only runtime | `hosts/desktop/system.nix` keeps the NVIDIA policy, forced performance profile, host-generated initrd module list, and the desktop writeback sysctls (`vm.dirty_ratio` / `vm.dirty_background_ratio` only). |

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
   `pkgs.desktopctl` to `PATH`, bootstraps empty
   `~/.config/hypr/input-runtime.conf`,
   `~/.config/hypr/animations-override.conf`, and
   `~/.config/hypr/keybinds-override.conf`, and runs `desktopctl theme sync`.
4. `sync` materializes only `sync_safe` targets and skips runtime reload hooks.

The `nrs` alias in `home/shell.nix` remains the preferred wrapper for this
flow. It disables Hyprland config autoreload during the switch, restores it
afterward, and on successful activation asks Hyprland to run `vicinae server
--replace` so the app launcher refreshes its desktop-entry view of the new
profile. When native optimizations are enabled, that wrapper also passes the
target `system-features` list to `nixos-rebuild` so the current daemon can
schedule host-tagged `requiredSystemFeatures` derivations before the new
`/etc/nix/nix.conf` is active.
