# NVIDIA Architecture

## Scope

Current implementation map for the NVIDIA stack across NixOS modules, overlays,
patches, and Hyprland session environment as of 2026-04-09.

## Composition

The host build is assembled in three layers:

1. `mkHost` in `flake.nix` uses `nixpkgs.lib.nixosSystem` to combine the shared
   `system/configuration.nix`, one host module, and the Home Manager module.
2. The `allowedUnfreePackageNames` / `allowUnfreePredicate`,
   `boot.tmp.useTmpfs = true`, and shared session-variable section in
   `system/configuration.nix` provide the shared graphics-adjacent baseline:
   tmpfs-backed `/tmp`, the shared unfree predicate that includes CUDA and
   NVIDIA userspace packages, and the common plugin/Qt session variables.
3. The selected host module plus the host-selected Hyprland env fragment apply
   the actual GPU policy for that machine, including any
   `__EGL_VENDOR_LIBRARY_FILENAMES` override.

## Ownership Map

| File | Owns | Notes |
| --- | --- | --- |
| `flake.nix` | Host composition | `mkHost` selects `system/configuration.nix`, then `hosts/<host>/system.nix`, then Home Manager |
| `system/configuration.nix` | Shared NVIDIA/CUDA package allowlist | `nixpkgs.config.allowUnfreePredicate` is fed from `allowedUnfreePackageNames`, which includes CUDA userspace packages plus `nvidia-settings` and `nvidia-x11` |
| `system/configuration.nix` | Shared graphics baseline | `boot.tmp.useTmpfs = true` makes `/tmp` tmpfs-backed, which matters for preserved VRAM on the desktop. The shared baseline does not set `__EGL_VENDOR_LIBRARY_FILENAMES` |
| `hosts/laptop/system.nix` | Hybrid laptop kernel and X stack | The laptop `hardware.nvidia` block enables the open NVIDIA driver with `modesetting`, enables NVIDIA power management plus `powerManagement.finegrained`, configures PRIME offload, uses `services.xserver.videoDrivers = [ "modesetting" "nvidia" ]`, and sets a laptop-only Mesa EGL vendor list |
| `hosts/desktop/system.nix` | Dedicated desktop kernel and X stack | The desktop host module imports the PR #996 overlay, sets `NVreg_TemporaryFilePath=/var/tmp`, enables the open NVIDIA driver with `modesetting`, disables `hardware.nvidia.powerManagement.kernelSuspendNotifier`, sets a dual-vendor EGL list directly, disables systemd user-session freezing for suspend, and installs `nvidia-vaapi-driver` |
| `overlays/nvidia-open-pr996.nix` | Desktop-only driver patch injection | Rebuilds `linuxPackages.nvidiaPackages.production` through `mkDriver` with `patchesOpen = [ pr996Patch ]`, then points `stable` and the `nvidia_x11*` aliases at the patched driver set |
| `patches/nvidia/nvidia-open-pr996.patch` | Actual kernel patch | Adds `drm_mode_config_reset(dev);` in the open NVIDIA DRM resume path |
| `home/default.nix` | Host-selected Hyprland GPU env file | The `xdg.configFile."hypr/env.conf"` branch publishes `config/hypr/env.conf` on the laptop and `hosts/desktop/env.conf` on the desktop |
| `config/hypr/hyprland.conf` | Hyprland include order | The early `source = ~/.config/hypr/env.conf` include loads host-specific GPU environment variables before input, rules, and autostart |
| `config/hypr/env.conf` | Laptop user-session GPU routing | Keeps Intel as the primary user-session graphics path with `LIBVA_DRIVER_NAME=iHD` and an explicit `AQ_DRM_DEVICES` ordering via `/dev/dri/card2:/dev/dri/card1`; this intentionally avoids `/dev/dri/by-path` because current Aquamarine splits `AQ_DRM_DEVICES` on `:` |
| `hosts/desktop/env.conf` | Desktop user-session NVIDIA env | Sets `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, and `NVD_BACKEND=direct` for the dedicated NVIDIA desktop session |

## Host Behavior Matrix

| Concern | Laptop hybrid path | Desktop dedicated path |
| --- | --- | --- |
| Base NixOS options | The laptop `hardware.nvidia` block enables `hardware.graphics.enable`, `hardware.nvidia.open`, `hardware.nvidia.modesetting.enable`, and the PRIME block | The desktop `hardware.nvidia` block enables the same base NVIDIA options, but `services.xserver.videoDrivers` stays on `nvidia` without PRIME |
| Render topology | `hardware.nvidia.prime.offload.enable = true` and `enableOffloadCmd = true` keep Intel as the primary GPU and expose NVIDIA as an offload target in `hosts/laptop/system.nix` | No PRIME block is set. The desktop is a dedicated NVIDIA path with no secondary iGPU routing in `hosts/desktop/system.nix` |
| Video driver selection | Xorg advertises both `modesetting` and `nvidia` through `services.xserver.videoDrivers` in `hosts/laptop/system.nix` | Xorg advertises only `nvidia` through `services.xserver.videoDrivers` in `hosts/desktop/system.nix` |
| Power management | The laptop enables `hardware.nvidia.powerManagement.finegrained = true` for hybrid runtime power behavior in `hosts/laptop/system.nix` | The desktop instead sets `hardware.nvidia.powerManagement.kernelSuspendNotifier = false` in `hosts/desktop/system.nix` and relies on the legacy resume-unit path |
| Suspend/resume persistence | No host-specific NVIDIA suspend workaround is present in the laptop module | `boot.extraModprobeConfig` redirects preserved VRAM files to `/var/tmp`, the overlay patches the open kernel module, and `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` is set on `systemd-suspend` in the desktop host module |
| EGL vendor selection | `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES` is set directly to Mesa-only in `hosts/laptop/system.nix` | `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES` is set directly to a dual-vendor list in `hosts/desktop/system.nix`; no shared baseline override or `lib.mkForce` is involved |
| Hyprland session env | The `xdg.configFile."hypr/env.conf"` branch in `home/default.nix` selects `config/hypr/env.conf`, which keeps Intel VA-API and an explicit `cardN` DRM-device ordering chosen for current Aquamarine compatibility | The same branch selects `hosts/desktop/env.conf`, which forces NVIDIA-oriented VA-API, GBM, and GLX user-space paths |
| Extra packages | No host-specific NVIDIA packages are added here | `environment.systemPackages` in `hosts/desktop/system.nix` adds `nvidia-vaapi-driver` |

## Overlay Flow

The PR #996 workaround only affects the desktop path:

1. The desktop host module's `nixpkgs.overlays` list in `hosts/desktop/system.nix` appends `overlays/nvidia-open-pr996.nix`.
2. `overlays/nvidia-open-pr996.nix` extends `linuxPackages.nvidiaPackages`
   rather than overriding the already-built outer `nvidia-open` derivation.
3. The `production = nprev.mkDriver { ... patchesOpen = [ pr996Patch ]; }`
   block in `overlays/nvidia-open-pr996.nix` rebuilds the `production` driver
   through `mkDriver` and injects
   `patchesOpen = [ ../patches/nvidia/nvidia-open-pr996.patch ]`.
4. The alias assignments in `overlays/nvidia-open-pr996.nix` point `stable`,
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
4. The `allowedUnfreePackageNames`, `boot.tmp.useTmpfs`, and shared session-variable sections in `system/configuration.nix`
5. The `hardware.nvidia`, `services.xserver.videoDrivers`, and related NVIDIA/session blocks in `hosts/laptop/system.nix` or `hosts/desktop/system.nix`
6. The `xdg.configFile."hypr/env.conf"` branch in `home/default.nix`
7. `config/hypr/env.conf` or `hosts/desktop/env.conf`
8. `overlays/nvidia-open-pr996.nix` and `patches/nvidia/nvidia-open-pr996.patch` for desktop resume work
