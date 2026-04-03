# NVIDIA Architecture

## Scope

Current implementation map for the NVIDIA stack across NixOS modules, overlays,
patches, and Hyprland session environment as of 2026-04-02.

## Composition

The host build is assembled in three layers:

1. `flake.nix:33-76` uses `mkHost` to combine the shared
   `system/configuration.nix`, one host module, and the Home Manager module.
2. `system/configuration.nix:127,156-158,211-216` provides the shared
   graphics-adjacent baseline: tmpfs-backed `/tmp`, the shared unfree predicate
   that includes CUDA and NVIDIA userspace packages, and a Mesa-only
   `__EGL_VENDOR_LIBRARY_FILENAMES`.
3. The selected host module plus the host-selected Hyprland env fragment apply
   the actual GPU policy for that machine.

## Ownership Map

| File | Owns | Notes |
| --- | --- | --- |
| `flake.nix:33-76` | Host composition | Selects `system/configuration.nix`, then `hosts/<host>/system.nix`, then Home Manager. This is where the laptop and desktop diverge at evaluation time. |
| `system/configuration.nix:83-120` | Shared NVIDIA/CUDA package allowlist | `nixpkgs.config.allowUnfreePredicate` is fed from `allowedUnfreePackageNames`, which includes CUDA userspace packages plus `nvidia-settings` and `nvidia-x11`. This affects evaluation on every host, not just the desktop. |
| `system/configuration.nix:127,214-216` | Shared graphics baseline | `boot.tmp.useTmpfs = true` makes `/tmp` tmpfs-backed, which matters for preserved VRAM on the desktop. The same file also sets `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES` to Mesa-only. |
| `hosts/laptop/system.nix:46-62` | Hybrid laptop kernel and X stack | Sets `hardware.graphics.enable`, enables the open NVIDIA driver with `modesetting`, enables NVIDIA power management plus `powerManagement.finegrained`, configures PRIME offload, and uses `services.xserver.videoDrivers = [ "modesetting" "nvidia" ]`. |
| `hosts/desktop/system.nix:4-16,56-75,93-95` | Dedicated desktop kernel and X stack | Imports the PR #996 overlay, sets `NVreg_TemporaryFilePath=/var/tmp`, enables the open NVIDIA driver with `modesetting`, disables `hardware.nvidia.powerManagement.kernelSuspendNotifier`, forces a dual-vendor EGL list, disables systemd user-session freezing for suspend, and installs `nvidia-vaapi-driver`. |
| `overlays/nvidia-open-pr996.nix:1-43` | Desktop-only driver patch injection | Rebuilds `linuxPackages.nvidiaPackages.production` through `mkDriver` with `patchesOpen = [ pr996Patch ]`, then points `stable` and the `nvidia_x11*` aliases at the patched driver set. |
| `patches/nvidia/nvidia-open-pr996.patch:1-10` | Actual kernel patch | Adds `drm_mode_config_reset(dev);` in the open NVIDIA DRM resume path. |
| `home/default.nix:201-215` | Host-selected Hyprland GPU env file | Publishes `~/.config/hypr/env.conf` from `config/hypr/env.conf` on the laptop and from `hosts/desktop/env.conf` on the desktop. |
| `config/hypr/hyprland.conf:4-14` | Hyprland include order | Loads `~/.config/hypr/env.conf` early, before input, rules, and autostart, so these host-specific GPU environment variables apply for the whole session. |
| `config/hypr/env.conf:13-16` | Laptop user-session GPU routing | Keeps Intel as the primary user-session graphics path with `LIBVA_DRIVER_NAME=iHD` and an explicit `AQ_DRM_DEVICES` ordering, while the system-wide Mesa EGL vendor list remains in effect. |
| `hosts/desktop/env.conf:13-17` | Desktop user-session NVIDIA env | Sets `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, and `NVD_BACKEND=direct` for the dedicated NVIDIA desktop session. |

## Host Behavior Matrix

| Concern | Laptop hybrid path | Desktop dedicated path |
| --- | --- | --- |
| Base NixOS options | `hosts/laptop/system.nix:47-62` enables `hardware.graphics.enable`, `hardware.nvidia.open`, `hardware.nvidia.modesetting.enable`, and `hardware.nvidia.powerManagement.enable`. | `hosts/desktop/system.nix:56-63` enables the same base NVIDIA options, but uses `services.xserver.videoDrivers = [ "nvidia" ]` without PRIME. |
| Render topology | `hardware.nvidia.prime.offload.enable = true` and `enableOffloadCmd = true` keep Intel as the primary GPU and expose NVIDIA as an offload target (`hosts/laptop/system.nix:53-60`). | No PRIME block is set. The desktop is a dedicated NVIDIA path with no secondary iGPU routing in the host module (`hosts/desktop/system.nix:56-63`). |
| Video driver selection | Xorg advertises both `modesetting` and `nvidia` (`hosts/laptop/system.nix:62`). | Xorg advertises only `nvidia` (`hosts/desktop/system.nix:63`). |
| Power management | The laptop enables `hardware.nvidia.powerManagement.finegrained = true` for hybrid runtime power behavior (`hosts/laptop/system.nix:51-52`). | The desktop instead sets `hardware.nvidia.powerManagement.kernelSuspendNotifier = false` and relies on the legacy resume-unit path (`hosts/desktop/system.nix:60-62`). |
| Suspend/resume persistence | No host-specific NVIDIA suspend workaround is present in the laptop module. | `boot.extraModprobeConfig` redirects preserved VRAM files to `/var/tmp`, the overlay patches the open kernel module, and `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` is set on `systemd-suspend` (`hosts/desktop/system.nix:12-16`, `hosts/desktop/system.nix:65-67`). |
| EGL vendor selection | Inherits the shared Mesa-only `__EGL_VENDOR_LIBRARY_FILENAMES` from `system/configuration.nix:214-215`. | Uses `lib.mkForce` to replace the shared Mesa-only setting with a dual-vendor list that includes both `10_nvidia.json` and `50_mesa.json` (`hosts/desktop/system.nix:69-75`). |
| Hyprland session env | `home/default.nix:209-213` selects `config/hypr/env.conf:13-16`, which keeps Intel VA-API and explicit DRM-device ordering. | `home/default.nix:209-213` selects `hosts/desktop/env.conf:13-17`, which forces NVIDIA-oriented VA-API, GBM, and GLX user-space paths. |
| Extra packages | No host-specific NVIDIA packages are added here. | `environment.systemPackages` adds `nvidia-vaapi-driver` (`hosts/desktop/system.nix:93-95`). |

## Overlay Flow

The PR #996 workaround only affects the desktop path:

1. `hosts/desktop/system.nix:4-8` appends `overlays/nvidia-open-pr996.nix` to
   `nixpkgs.overlays`.
2. `overlays/nvidia-open-pr996.nix:8-40` extends `linuxPackages.nvidiaPackages`
   rather than overriding the already-built outer `nvidia-open` derivation.
3. `overlays/nvidia-open-pr996.nix:16-27` rebuilds the `production` driver
   through `mkDriver` and injects `patchesOpen = [ ../patches/nvidia/nvidia-open-pr996.patch ]`.
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
4. `system/configuration.nix:83-120,127,214-216`
5. `hosts/laptop/system.nix:46-62` or `hosts/desktop/system.nix:4-16,56-75,93-95`
6. `home/default.nix:201-215`
7. `config/hypr/env.conf:13-16` or `hosts/desktop/env.conf:13-17`
8. `overlays/nvidia-open-pr996.nix:1-43` and `patches/nvidia/nvidia-open-pr996.patch:1-10` for desktop resume work
