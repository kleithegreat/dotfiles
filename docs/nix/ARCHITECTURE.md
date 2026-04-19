# Nix Architecture

## Scope

Current implementation map for the flake, shared NixOS modules, optional
distributed-build wiring, and embedded Home Manager layer as of 2026-04-19.

## Flake Topology

| Piece | Current implementation |
| --- | --- |
| Outputs | The `outputs` attrset in `flake.nix` exports `nixosConfigurations.vm`, `nixosConfigurations.laptop`, `nixosConfigurations.desktop`, plus `overlays.default`, `packages.x86_64-linux.desktopctl`, `packages.x86_64-linux.helium`, `packages.x86_64-linux.openchamber`, and `packages.x86_64-linux.openchamber-claude-bridge` |
| Host constructor | `mkHost` in `flake.nix` wraps `nixpkgs.lib.nixosSystem` |
| Feature flags | The top-level `enableNativeOptimizations` and `enableDistributedBuilds` bindings in `flake.nix` stay shared across all hosts, with the VM explicitly opting out of native rebuilds and distributed builds currently disabled by default |
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
| `system/configuration.nix` | Shared system baseline | Nix settings, the shared unfree allowlist used by both NixOS and embedded Home Manager, overlays, common users/groups, shared services, privileged desktop helper registrations, shared Tailscale operator configuration, root-only weekly `fstrim` scheduling, system packages, explicit PipeWire/WirePlumber native-package selection, Hyprland packaging, shared Qt plugin-path wiring, the repo-wide fontconfig baseline, and the physical-host runtime kernel tuning (`bbr`/`fq`, autogroup, and MGLRU `min_ttl_ms`) |
| `system/distributed-builds.nix` | Optional shared distributed-build layer | When enabled, configures remote builders, the post-build cache push hook, `nix.sshServe`, and LAN-only SSH firewall rules |
| `system/distributed-builds-data.nix` | Environment-specific builder/cache data | Authorized builder keys, host keys, current cache signing key, and the current cache URL override |
| `system/native-optimizations.nix` | Shared helper | Centralizes the userspace `-O3 -march=native` / `target-cpu=native` flag sets, the kernel-specific `KCFLAGS=-O2 -march=native` / `KRUSTFLAGS=-Ctarget-cpu=native` flags, the per-host `native-optimized-<host>` feature marker, and the `overrideAttrs` helpers reused by the overlay, Hyprland-family packages, and Home Manager flake-input packages |
| `system/native-kernel-packages.nix` | Shared helper | Derives the physical-host kernel package set from the stock nixpkgs `linux_6_18` source, rebuilds it with Clang + LLD ThinLTO, applies an explicit BORE patch stack plus a `tcp/bbr3` patch on top, bakes in the shared BORE/BBR3/HZ=1000/NO_HZ_IDLE/THP=madvise/MGLRU Kconfig overrides, layers host-local `KCFLAGS=-O2 -march=native` / `KRUSTFLAGS=-Ctarget-cpu=native`, and carries the same per-host native build feature tag used by the rest of the optimized package set |
| `hosts/vm/system.nix` | VM overlay | VM boot, guest profile, and virtual disk layout |
| `hosts/laptop/system.nix` | Laptop overlay | Laptop-specific kernel/compiler tuning, the laptop's voluntary-preempt plus Intel-only Kconfig trim, local build-scheduling policy, hybrid GPU policy, laptop-only services and overrides, fingerprint/PAM policy, laptop-scoped polkit rules, GRUB, laptop hardware policy, and the laptop `tailscaled` stop-timeout override |
| `hosts/laptop/fan-control.nix` | Laptop-only hardware submodule | Dell SMM kernel module wiring, BIOS fan-control handoff, the explicit four-state `i8kmon.conf` profile with aggressive ramp thresholds, and the `i8kmon` systemd service |
| `hosts/desktop/system.nix` | Desktop overlay | Dedicated NVIDIA policy, shared native kernel/compiler tuning opt-in, the desktop's PREEMPT_FULL plus VM writeback/cache-pressure sysctls, local build-scheduling policy, desktop-only imports, storage mounts, GRUB, desktop-only overlay imports, the desktop Windows VM toggle, the desktop `tailscaled` stop-timeout override, and the desktop's forced `power-profiles-daemon` performance profile |
| `hosts/desktop/windows-vm.nix` | Desktop Windows VM submodule | Defines `virtualisation.windowsVm`, seeds the desktop qcow2/OVMF/TPM state under `/var/lib/windows-vm/windows11` during activation, grants the desktop user `kvm` access, and installs the `windows-vm` QEMU launcher |
| `home/default.nix` | Shared user baseline | User packages that do not require system-scoped helper registration, small package-level overrides such as the local OpenCode stale-`node_modules` hash pin plus the post-configure build workarounds and the explicit native-package aliases, `xdg.configFile` mappings, host-specific Hyprland file selection, desktop entry overrides, and theme activation |
| `home/shell.nix` | Shell submodule | Zsh, shell tools, Git, aliases, shell helpers, and sourcing the generated `~/.config/zsh/theme-colors` fragment from `programs.zsh.initContent` |
| `home/gtk.nix` | GTK submodule | GTK packages and small dconf defaults |
| `pkgs/helium/default.nix` | Prebuilt browser package | Fetches the upstream Helium release tarball, auto-patches the bundled ELFs, wraps the upstream launcher, and installs desktop assets using the pin in `pkgs/helium/source.nix` |
| `pkgs/openchamber/default.nix` | Source-built OpenChamber package | Fetches the upstream OpenChamber source tarball, applies the local `patches/openchamber/claude-backend-selector.patch`, restores the repo-pinned root `package.json` plus `package-lock.json` from `pkgs/openchamber/`, builds the `packages/web` workspace with npm workspace support, wraps the CLI with the store path to `openchamber-claude-bridge` so the app can auto-manage the Claude backend, installs a small browser-launch wrapper alongside the CLI, and installs a desktop entry plus icon from `packages/web/public/` so Home Manager profile installs show up in launchers such as Vicinae while still opening the reported local URL visibly in the browser |
| `pkgs/openchamber-claude-bridge/default.nix` | Claude Code bridge package | Wraps the local `pkgs/openchamber-claude-bridge/index.mjs` compatibility server that exposes the OpenCode endpoint subset OpenChamber uses and forwards chat turns into the `claude` CLI |
| `overlays/local-packages.nix` | Local package overlay | Exposes the repo's `desktopctl`, `helium`, `openchamber`, and `openchamber-claude-bridge` derivations, carries the repo-local `sf-pro` font package, and applies small nixpkgs overrides such as the Lapce Vulkan-loader runtime fix and the LM Studio AppImage fixups |

## Overlay Usage

- `overlays/local-packages.nix` exposes `pkgs.desktopctl` from the local
  `desktopctl/` derivation, `pkgs.helium` from `pkgs/helium/`,
  `pkgs.openchamber` from `pkgs/openchamber/`,
  `pkgs.openchamber-claude-bridge` from `pkgs/openchamber-claude-bridge/`, defines a repo-local
  `pkgs.sf-pro` derivation that fetches Apple's stable-url
  `SF-Pro.dmg` with a repo-pinned hash and unpacks `Payload~` via `cpio` when
  present, overrides `pkgs.lapce` so `bin/.lapce-wrapped` gains the
  `pkgs.vulkan-loader` library directory in its runtime search path for
  `wgpu`, and carries the `pkgs.lmstudio` override that rewrites nixpkgs'
  stale AppImage icon path to the current upstream AppImage's real
  `resources/app/.webpack/Icon-512x512.png` asset and skips the bundled `lms`
  post-install fixup when the release only ships an empty placeholder file.
- The `overlays.default` and `packages.x86_64-linux` exports in `flake.nix`
  expose that overlay and also
  exposes `packages.x86_64-linux.desktopctl`,
  `packages.x86_64-linux.helium`, and
  `packages.x86_64-linux.openchamber`, and
  `packages.x86_64-linux.openchamber-claude-bridge`.
- `pkgs/openchamber/default.nix` now wraps the upstream CLI with
  `OPENCHAMBER_CLAUDE_BRIDGE_BINARY=${lib.getExe pkgs.openchamber-claude-bridge}`.
  The patched OpenChamber server reads the persisted backend selector from its
  own settings, and when `backend = "claude-code"` it auto-starts that bridge
  itself and proxies the normal `/api` OpenCode traffic into Claude Code.
- In `system/configuration.nix`, the local `let` block imports both the
  `desktopctl` overlay and the optional native-optimization overlay;
  `nixpkgs.overlays` applies only the shared repo overlays globally, while the
  native overlay is re-applied locally through `pkgs.appendOverlays` where the
  config wants explicit native-package aliases. The same module also installs
  the local `pkgs.sf-pro` derivation through `fonts.packages`, and
  `fonts.fontconfig` enables RGB subpixel rendering plus a local
  `SF Pro -> SF Pro Text` family-preference rule so the generic Apple family
  resolves to the small-text cut instead of the bundled catch-all variable
  face.
- `overlays/native-optimized.nix` rebuilds selected nixpkgs derivations such as
  `desktopctl`, `lapce`, `pipewire`, `quickshell`, `fd`, `ripgrep`, and the
  repo's TeX Live environment with `-O3 -march=native` / `target-cpu=native`,
  while deliberately leaving low-level rebuild multipliers such as `zstd` and
  `lz4` untouched.
- `system/configuration.nix` reuses `system/native-optimizations.nix` directly
  for the flake-provided `hyprqt6engine`, `hyprland`,
  `xdg-desktop-portal-hyprland`, `hyprbars`, and `hyprexpo` derivations, while
  `home/default.nix` uses that same helper for the locally overridden
  `opencode`, `snappy-switcher`, and Vicinae packages. The OpenCode override
  swaps in `packages.<system>.node_modules_updater.override { hash =
  "sha256-i9TxYwWkJAR+kW6pbvhgQbRW9UYPtdrPQAGic4zPoa4="; }` before the existing
  `postConfigure` fixes run, keeping the repo on upstream commit
  `a546e88f37d1816adadf1e833a5fb4f39b7d56df` even when that commit ships a stale
  `nix/hashes.json` entry for `x86_64-linux`.
- Native nixpkgs-package selection is now explicit instead of global:
  `system/configuration.nix` builds a local `optimizedPkgs` set via
  `pkgs.appendOverlays [ optimizedPackages.overlay ]` and uses it only for
  `services.pipewire.package` plus `services.pipewire.wireplumber.package`, and
  `home/default.nix` builds the same kind of local `optimizedPkgs` set for the
  top-level user packages that are intentionally host-native (`fd`, `ripgrep`,
  `desktopctl`, `p7zip`, `lapce`, the TeX Live environment, `lsp-plugins`,
  `quickshell`, and the PipeWire JACK shim used by the Ableton launchers).
  Other nixpkgs packages stay on the stock shared package set.
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
- `hosts/desktop/system.nix` now also enables
  `services.power-profiles-daemon` and appends a
  `systemd.services.power-profiles-daemon.postStart` hook that runs
  `powerprofilesctl set performance`, so the desktop host reasserts the
  performance profile each time the daemon starts.
- Both physical host modules set
  `systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s"`, bounding
  rare upstream stop hangs without changing the shared VM profile.
- The shared system baseline also sets
  `services.tailscale.extraSetFlags = [ "--operator=kevin" ]` so
  user-session Quickshell calls to `tailscale up` / `tailscale down` can manage
  the local daemon without `sudo`.
- The shared system baseline also enables NixOS `qt.enable`, exports
  `QT_QPA_PLATFORMTHEME=hyprqt6engine`, keeps the nonstandard `hyprqt6engine`
  `lib/qt-6` root on `QT_PLUGIN_PATH`, and installs `libsForQt5.qt5ct`,
  `qt6Packages.qt6ct`, plus the Qt5/Qt6 Kvantum style engines through
  `environment.systemPackages`, so user-launched Qt apps and
  D-Bus/systemd-activated helpers such as `xdg-desktop-portal-kde` resolve the
  same platform and style plugins.
- The shared system baseline no longer enables the stock NixOS
  `services.fstrim` helper. Instead, `system/configuration.nix` defines a
  custom `fstrim-root.service` plus `fstrim-root.timer` that run `fstrim` only
  on `/`, preserving weekly discard on the Linux root filesystem without also
  trimming a shared `/boot/efi` mount when that EFI system partition lives on a
  separate Windows NVMe.
- `hosts/laptop/system.nix` enables `services.fprintd`, keeps the laptop PAM
  `polkit-1.fprintAuth` path available for external apps that explicitly use
  polkit system authentication, and also adds a narrow polkit rule granting the
  active local user direct `net.reactivated.fprint.device.enroll` access so the
  Quickshell fingerprint-management flow can enroll/delete prints without a
  separate external auth-agent prompt.
- `hosts/laptop/system.nix` and `hosts/desktop/system.nix` both source
  `boot.kernelPackages` from `system/native-kernel-packages.nix`, so both
  physical hosts rebuild the stock nixpkgs `linux_6_18` kernel source with
  Clang + LLD ThinLTO, an explicit BORE patch stack plus `tcp/bbr3` on top,
  shared BORE/BBR3/HZ=1000/NO_HZ_IDLE / THP=madvise / MGLRU Kconfig
  overrides, `ignoreConfigErrors = true`, `KCFLAGS=-O2 -march=native`,
  `KRUSTFLAGS=-Ctarget-cpu=native`, and the same host-specific
  `native-optimized-<host>` feature tag used by the rest of the native
  package set.
- The shared system baseline gates a physical-host-only kernel runtime tuning
  block on `hostName` and uses `boot.kernel.sysctl` to keep
  `kernel.sched_autogroup_enabled = 1`, `net.core.default_qdisc = "fq"`, and
  `net.ipv4.tcp_congestion_control = "bbr"` on desktop and laptop only. The
  same module also defines `systemd.services.mglru-tuning`, which writes `y`
  to `/sys/kernel/mm/lru_gen/enabled` and `1000` to
  `/sys/kernel/mm/lru_gen/min_ttl_ms` during boot so the physical hosts use
  MGLRU's thrash-prevention path as the repo's LE9/LE10-style working-set /
  file-cache protection.
- Both physical host modules also set
  `boot.kernelParams = [ "mitigations=off" "transparent_hugepage=madvise" ]`,
  disabling the kernel's CPU side-channel mitigation set and forcing THP to
  the `madvise` runtime mode on the bare-metal laptop and desktop while
  leaving the VM profile unchanged.
- `hosts/laptop/system.nix` still uses `boot.kernelPatches = [{ patch = null;
  structuredExtraConfig = ...; }]`, but that patch block now also forces the
  laptop onto `PREEMPT_VOLUNTARY` before disabling AMD-only
  platform/virtualization options such as `KVM_AMD`, `AMD_IOMMU`,
  `AMD_MEM_ENCRYPT`, and `AMD_PMC`, while also dropping guest-only hypervisor
  support (`XEN`, `HYPERV`, `KVM_GUEST`) and `DRM_NOUVEAU`; the Intel VM-host
  path (`kvm-intel`) remains intact.
- `hosts/desktop/system.nix` now adds its own `boot.kernelPatches = [{ patch =
  null; structuredExtraConfig = ...; }]` entry to force the desktop onto full
  preemption, and it also sets desktop-only `boot.kernel.sysctl` values for
  `vm.swappiness = 10`, `vm.dirty_ratio = 10`,
  `vm.dirty_background_ratio = 5`, and `vm.vfs_cache_pressure = 50`.
- Both physical host modules set `nix.settings.max-jobs = 1`, so desktop and
  laptop each build one derivation at a time locally while leaving
  per-derivation core parallelism at Nix's default `cores = 0` behavior.

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
flow. When native optimizations are enabled, that wrapper also passes the
target `system-features` list to `nixos-rebuild` so the current daemon can
schedule host-tagged `requiredSystemFeatures` derivations before the new
`/etc/nix/nix.conf` is active.
