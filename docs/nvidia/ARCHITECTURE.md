# NVIDIA Architecture

## Scope

Current implementation map for the NVIDIA stack across NixOS modules and
Hyprland session environment as of 2026-06-10.

## Composition

The host build is assembled in three layers:

1. `mkHost` in `flake.nix` uses `nixpkgs.lib.nixosSystem` to combine the shared
   `system/configuration.nix`, one host module, and the Home Manager module.
2. The `allowedUnfreePackageNames` / `allowUnfreePredicate`,
   `boot.tmp.useTmpfs = true`, and remaining shared session variables
   (`NIXOS_OZONE_WL`, `HYPR_PLUGIN_DIR`) in `system/configuration.nix` provide
   the shared graphics-adjacent baseline: tmpfs-backed `/tmp` and the shared
   unfree predicate that includes CUDA and NVIDIA userspace packages. The Qt
   platform/plugin session variables (`QT_QPA_PLATFORMTHEME`,
   `QT_PLUGIN_PATH`) live in `system/qt.nix`, not `system/configuration.nix`.
3. The selected host module plus the host-selected Hyprland env fragment apply
   the actual GPU policy for that machine, including any
   `__EGL_VENDOR_LIBRARY_FILENAMES` override.

## Ownership Map

| File | Owns | Notes |
| --- | --- | --- |
| `flake.nix` | Host composition | `mkHost` selects `system/configuration.nix`, then `hosts/<host>/system.nix`, then Home Manager, while also passing a structured `host` fact record that the Home Manager layer uses for host-specific Hyprland file selection |
| `system/configuration.nix` | Shared NVIDIA/CUDA package allowlist | `nixpkgs.config.allowUnfreePredicate` is fed from `allowedUnfreePackageNames`, which includes CUDA userspace packages plus `nvidia-settings` and `nvidia-x11` |
| `system/configuration.nix` | Shared graphics baseline | `boot.tmp.useTmpfs = true` makes `/tmp` tmpfs-backed, which matters for preserved VRAM on the desktop. The shared baseline does not set `__EGL_VENDOR_LIBRARY_FILENAMES` |
| `hosts/laptop/system.nix` | Hybrid laptop kernel and X stack | The laptop `hardware.nvidia` block enables the open NVIDIA driver with `modesetting`, enables NVIDIA power management plus `powerManagement.finegrained`, configures PRIME offload, uses `services.xserver.videoDrivers = [ "modesetting" "nvidia" ]`, sets a laptop-only Mesa EGL vendor list, disables `DRM_NOUVEAU` through the laptop-only `boot.kernelPatches` config, unsets the inherited `DRM_NOUVEAU_SVM` child symbol that becomes unreachable with Nouveau disabled, and sets `hardware.graphics.extraPackages = [ intel-media-driver ]` so `iHD_drv_video.so` backs the `LIBVA_DRIVER_NAME=iHD` selection in `config/hypr/env.conf` (Mesa alone does not ship it); `vainfo` verification on the laptop is still pending |
| `hosts/desktop/system.nix` | Dedicated desktop kernel and X stack | The desktop host module sets `NVreg_TemporaryFilePath=/var/tmp`, enables the open NVIDIA driver with `modesetting`, disables `hardware.nvidia.powerManagement.kernelSuspendNotifier`, sets a dual-vendor EGL list directly, and disables systemd user-session freezing for suspend |
| `home/xdg.nix` | Host-selected Hyprland GPU env file | The `host.hyprland.env` fact publishes `config/hypr/env.conf` on the laptop and `hosts/desktop/env.conf` on the desktop |
| `config/hypr/hyprland.conf` | Hyprland include order | The early `source = ~/.config/hypr/env.conf` include loads host-specific GPU environment variables before input, rules, and autostart |
| `config/hypr/env.conf` | Laptop user-session GPU routing | Keeps Intel as the primary user-session graphics path with `LIBVA_DRIVER_NAME=iHD` and an explicit `AQ_DRM_DEVICES` ordering via `/dev/dri/card2:/dev/dri/card1`; this intentionally avoids `/dev/dri/by-path` because current Aquamarine splits `AQ_DRM_DEVICES` on `:` |
| `hosts/desktop/env.conf` | Desktop user-session NVIDIA env | Sets `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, and `NVD_BACKEND=direct` for the dedicated NVIDIA desktop session |

## Host Behavior Matrix

| Concern | Laptop hybrid path | Desktop dedicated path |
| --- | --- | --- |
| Base NixOS options | The laptop `hardware.nvidia` block enables `hardware.graphics.enable`, `hardware.nvidia.open`, `hardware.nvidia.modesetting.enable`, and the PRIME block, while the same host module disables `DRM_NOUVEAU` through `boot.kernelPatches` | The desktop `hardware.nvidia` block enables the same base NVIDIA options, but `services.xserver.videoDrivers` stays on `nvidia` without PRIME |
| Render topology | `hardware.nvidia.prime.offload.enable = true` and `enableOffloadCmd = true` keep Intel as the primary GPU and expose NVIDIA as an offload target in `hosts/laptop/system.nix` | No PRIME block is set. The desktop is a dedicated NVIDIA path with no secondary iGPU routing in `hosts/desktop/system.nix` |
| Video driver selection | Xorg advertises both `modesetting` and `nvidia` through `services.xserver.videoDrivers` in `hosts/laptop/system.nix` | Xorg advertises only `nvidia` through `services.xserver.videoDrivers` in `hosts/desktop/system.nix` |
| Power management | The laptop enables `hardware.nvidia.powerManagement.finegrained = true` for hybrid runtime power behavior in `hosts/laptop/system.nix` | The desktop instead sets `hardware.nvidia.powerManagement.kernelSuspendNotifier = false` in `hosts/desktop/system.nix` and relies on the legacy resume-unit path |
| Suspend/resume persistence | No host-specific NVIDIA suspend workaround is present in the laptop module | `boot.extraModprobeConfig` redirects preserved VRAM files to `/var/tmp`, and `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` is set on `systemd-suspend` in the desktop host module. The old PR #996 overlay has been removed because upstream source already contains `drm_mode_config_reset(dev);`, but that removal is still untested on real desktop suspend/resume hardware |
| EGL vendor selection | `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES` is set directly to Mesa-only in `hosts/laptop/system.nix` | `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES` is set directly to a dual-vendor list in `hosts/desktop/system.nix`; no shared baseline override or `lib.mkForce` is involved |
| Hyprland session env | The `host.hyprland.env` fact consumed in `home/xdg.nix` selects `config/hypr/env.conf`, which keeps Intel VA-API and an explicit `cardN` DRM-device ordering chosen for current Aquamarine compatibility | The same host fact selects `hosts/desktop/env.conf`, which forces NVIDIA-oriented VA-API, GBM, and GLX user-space paths |
| Extra packages | `hosts/laptop/system.nix` adds `intel-media-driver` to `hardware.graphics.extraPackages` for the Intel iHD VA-API path | No explicit package additions. Desktop VA-API comes from the nixpkgs NVIDIA module's `hardware.nvidia.videoAcceleration` default (`true`), which puts `pkgs.nvidia-vaapi-driver` into `hardware.graphics.extraPackages` and thus `/run/opengl-driver/lib/dri` — the path libva actually uses. The old redundant `environment.systemPackages` `nvidia-vaapi-driver` block in `hosts/desktop/system.nix` was removed |

## Resume Status

The old PR #996 workaround has been removed from the desktop path because the
current upstream NVIDIA open-driver source already contains
`drm_mode_config_reset(dev);` in `nv_drm_suspend_resume`. The remaining desktop
resume stack is now:

1. `hosts/desktop/system.nix` keeps `hardware.nvidia.powerManagement.kernelSuspendNotifier = false`.
2. `hosts/desktop/system.nix` keeps `NVreg_TemporaryFilePath=/var/tmp` through `boot.extraModprobeConfig`.
3. `hosts/desktop/system.nix` keeps `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` on `systemd-suspend`.
4. This post-overlay state is still untested on actual desktop suspend/resume hardware after removing the old patch path.

## Practical Read Order

For NVIDIA work in this repo, the minimal implementation read order is:

1. `docs/nvidia/ARCHITECTURE.md`
2. `docs/nvidia/REVIEW.md`
3. `docs/nvidia/QUIRKS.md`
4. The `allowedUnfreePackageNames`, `boot.tmp.useTmpfs`, and remaining shared session-variable sections in `system/configuration.nix` (Qt platform/plugin session variables live in `system/qt.nix`)
5. The `hardware.nvidia`, `services.xserver.videoDrivers`, and related NVIDIA/session blocks in `hosts/laptop/system.nix` or `hosts/desktop/system.nix`
6. The `host.hyprland.env` selection in `home/xdg.nix`
7. `config/hypr/env.conf` or `hosts/desktop/env.conf`
8. The desktop suspend/resume settings in `hosts/desktop/system.nix`
