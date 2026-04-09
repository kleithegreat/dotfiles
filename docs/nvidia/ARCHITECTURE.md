# NVIDIA Architecture

## Scope

Current implementation map for the NVIDIA stack across NixOS modules, overlays,
patches, and Hyprland session environment as of 2026-04-09.

## Composition

The host build is assembled in three layers:

1. `flake.nix:34-88` uses `mkHost` to combine the shared
   `system/configuration.nix`, one host module, and the Home Manager module.
2. `system/configuration.nix:123-160`, `system/configuration.nix:167`, and
   `system/configuration.nix:255-260` provide the shared
   graphics-adjacent baseline: tmpfs-backed `/tmp`, the shared unfree predicate
   that includes CUDA and NVIDIA userspace packages, and the common plugin/Qt
   session variables.
3. The selected host module plus the host-selected Hyprland env fragment apply
   the actual GPU policy for that machine, including any
   `__EGL_VENDOR_LIBRARY_FILENAMES` override.

## Ownership Map

| File | Owns | Notes |
| --- | --- | --- |
| `flake.nix:34-88` | Host composition | Selects `system/configuration.nix`, then `hosts/<host>/system.nix`, then Home Manager |
| `system/configuration.nix:123-160`, `system/configuration.nix:196-197` | Shared NVIDIA/CUDA package allowlist | `nixpkgs.config.allowUnfreePredicate` is fed from `allowedUnfreePackageNames`, which includes CUDA userspace packages plus `nvidia-settings` and `nvidia-x11` |
| `system/configuration.nix:167`, `system/configuration.nix:255-260` | Shared graphics baseline | `boot.tmp.useTmpfs = true` makes `/tmp` tmpfs-backed, which matters for preserved VRAM on the desktop. The shared baseline does not set `__EGL_VENDOR_LIBRARY_FILENAMES` |
| `hosts/laptop/system.nix:51-69` | Hybrid laptop kernel and X stack | Sets `hardware.graphics.enable`, enables the open NVIDIA driver with `modesetting`, enables NVIDIA power management plus `powerManagement.finegrained`, configures PRIME offload, uses `services.xserver.videoDrivers = [ "modesetting" "nvidia" ]`, and sets a laptop-only Mesa EGL vendor list |
| `hosts/desktop/system.nix:4-16`, `hosts/desktop/system.nix:57-72`, `hosts/desktop/system.nix:90-92` | Dedicated desktop kernel and X stack | Imports the PR #996 overlay, sets `NVreg_TemporaryFilePath=/var/tmp`, enables the open NVIDIA driver with `modesetting`, disables `hardware.nvidia.powerManagement.kernelSuspendNotifier`, sets a dual-vendor EGL list directly, disables systemd user-session freezing for suspend, and installs `nvidia-vaapi-driver` |
| `overlays/nvidia-open-pr996.nix:1-43` | Desktop-only driver patch injection | Rebuilds `linuxPackages.nvidiaPackages.production` through `mkDriver` with `patchesOpen = [ pr996Patch ]`, then points `stable` and the `nvidia_x11*` aliases at the patched driver set |
| `patches/nvidia/nvidia-open-pr996.patch:1-10` | Actual kernel patch | Adds `drm_mode_config_reset(dev);` in the open NVIDIA DRM resume path |
| `home/default.nix:229-235` | Host-selected Hyprland GPU env file | Publishes `~/.config/hypr/env.conf` from `config/hypr/env.conf` on the laptop and from `hosts/desktop/env.conf` on the desktop |
| `config/hypr/hyprland.conf:4-14` | Hyprland include order | Loads `~/.config/hypr/env.conf` early, before input, rules, and autostart, so these host-specific GPU environment variables apply for the whole session |
| `config/hypr/env.conf:13-16` | Laptop user-session GPU routing | Keeps Intel as the primary user-session graphics path with `LIBVA_DRIVER_NAME=iHD` and a stable `AQ_DRM_DEVICES` ordering via `/dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/by-path/pci-0000:01:00.0-card`, which matches the laptop PRIME bus IDs |
| `hosts/desktop/env.conf:13-17` | Desktop user-session NVIDIA env | Sets `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, and `NVD_BACKEND=direct` for the dedicated NVIDIA desktop session |

## Host Behavior Matrix

| Concern | Laptop hybrid path | Desktop dedicated path |
| --- | --- | --- |
| Base NixOS options | `hosts/laptop/system.nix:52-67` enables `hardware.graphics.enable`, `hardware.nvidia.open`, `hardware.nvidia.modesetting.enable`, and the PRIME block | `hosts/desktop/system.nix:57-64` enables the same base NVIDIA options, but uses `services.xserver.videoDrivers = [ "nvidia" ]` without PRIME |
| Render topology | `hardware.nvidia.prime.offload.enable = true` and `enableOffloadCmd = true` keep Intel as the primary GPU and expose NVIDIA as an offload target (`hosts/laptop/system.nix:58-65`) | No PRIME block is set. The desktop is a dedicated NVIDIA path with no secondary iGPU routing in the host module (`hosts/desktop/system.nix:57-64`) |
| Video driver selection | Xorg advertises both `modesetting` and `nvidia` (`hosts/laptop/system.nix:67`) | Xorg advertises only `nvidia` (`hosts/desktop/system.nix:64`) |
| Power management | The laptop enables `hardware.nvidia.powerManagement.finegrained = true` for hybrid runtime power behavior (`hosts/laptop/system.nix:56-57`) | The desktop instead sets `hardware.nvidia.powerManagement.kernelSuspendNotifier = false` and relies on the legacy resume-unit path (`hosts/desktop/system.nix:61-63`) |
| Suspend/resume persistence | No host-specific NVIDIA suspend workaround is present in the laptop module | `boot.extraModprobeConfig` redirects preserved VRAM files to `/var/tmp`, the overlay patches the open kernel module, and `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` is set on `systemd-suspend` (`hosts/desktop/system.nix:12-16`, `hosts/desktop/system.nix:66-68`) |
| EGL vendor selection | Sets `__EGL_VENDOR_LIBRARY_FILENAMES` directly to Mesa-only in `hosts/laptop/system.nix:68-69` | Sets `__EGL_VENDOR_LIBRARY_FILENAMES` directly to a dual-vendor list in `hosts/desktop/system.nix:70-72`; no shared baseline override or `lib.mkForce` is involved |
| Hyprland session env | `home/default.nix:229-235` selects `config/hypr/env.conf:13-16`, which keeps Intel VA-API and a stable by-path DRM-device ordering | `home/default.nix:229-235` selects `hosts/desktop/env.conf:13-17`, which forces NVIDIA-oriented VA-API, GBM, and GLX user-space paths |
| Extra packages | No host-specific NVIDIA packages are added here | `environment.systemPackages` adds `nvidia-vaapi-driver` (`hosts/desktop/system.nix:90-92`) |

## Overlay Flow

The PR #996 workaround only affects the desktop path:

1. `hosts/desktop/system.nix:4-8` appends `overlays/nvidia-open-pr996.nix` to
   `nixpkgs.overlays`.
2. `overlays/nvidia-open-pr996.nix:8-40` extends `linuxPackages.nvidiaPackages`
   rather than overriding the already-built outer `nvidia-open` derivation.
3. `overlays/nvidia-open-pr996.nix:16-27` rebuilds the `production` driver
   through `mkDriver` and injects
   `patchesOpen = [ ../patches/nvidia/nvidia-open-pr996.patch ]`.
4. `overlays/nvidia-open-pr996.nix:29-40` points `stable`,
   `nvidia_x11`, `nvidia_x11_production`, and the `*_open` aliases at the
   patched driver set, so the rest of the desktop config continues using the
   normal `nvidiaPackages` entry points.
5. Because both hosts set `hardware.nvidia.open = true`, the overlay only
   changes behavior on the desktop because only the desktop imports it.

## Practical Read Order

For NVIDIA work in this repo, the minimal implementation read order is:

1. `docs/nvidia/ARCHITECTURE.md`
2. `docs/nvidia/REVIEW.md`
3. `docs/nvidia/QUIRKS.md`
4. `system/configuration.nix:123-160`, `system/configuration.nix:167`,
   `system/configuration.nix:255-260`
5. `hosts/laptop/system.nix:51-69` or
   `hosts/desktop/system.nix:4-16`, `hosts/desktop/system.nix:57-72`,
   `hosts/desktop/system.nix:90-92`
6. `home/default.nix:229-235`
7. `config/hypr/env.conf:13-16` or `hosts/desktop/env.conf:13-17`
8. `overlays/nvidia-open-pr996.nix:1-43` and
   `patches/nvidia/nvidia-open-pr996.patch:1-10` for desktop resume work
