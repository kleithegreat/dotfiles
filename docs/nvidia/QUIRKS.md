# NVIDIA Quirks

## Preserved VRAM needs a disk-backed temp path
**Symptom:** Suspend/resume on the desktop can lose GPU state or come back garbled.
**Cause:** The shared system uses tmpfs-backed `/tmp`, but the NVIDIA preserve-VRAM path needs storage that survives the suspend cycle.
**Status:** Workaround in place
**Resolution:** `hosts/desktop/system.nix` sets `NVreg_TemporaryFilePath=/var/tmp` instead of leaving the driver on `/tmp`.

## Slow resume from suspend can stall display recovery
**Symptom:** Resume on the desktop can stall for about 31.4 seconds between `PM: suspend exit` and display output recovery, with `NVRM: _kgspRpcRecvPoll: GSP RM heartbeat timed out` in the journal on every resume.
**Cause:** NVIDIA open-gpu-kernel-modules is still missing `drm_mode_config_reset(dev)` in the resume branch of `nv_drm_suspend_resume()` (PR `#996`), and the kernel suspend notifier path proved less reliable on this Ampere desktop than the legacy systemd sleep units.
**Status:** Workaround in place
**Resolution:** Two desktop-only changes applied together cut the post-resume gap to about 2.3 seconds: `hosts/desktop/system.nix` forces `hardware.nvidia.powerManagement.kernelSuspendNotifier = false` to use `nvidia-resume.service`, and `overlays/nvidia-open-pr996.nix` applies the local PR `#996` patch to `nvidia-open`. The GSP timeout still appears in the journal, but it no longer blocks display recovery. Remove the overlay once a future NVIDIA driver release includes PR `#996`.

## systemd session freezing can black-screen resume
**Symptom:** The desktop can wake to a black screen after suspend.
**Cause:** systemd 256+ freezing user sessions on suspend is a bad fit for this stack.
**Status:** Workaround in place
**Resolution:** `hosts/desktop/system.nix` sets `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` on `systemd-suspend`.

## `AQ_DRM_DEVICES` cannot use `/dev/dri/by-path` symlinks on the laptop stack
**Symptom:** SDDM accepts a correct password, then immediately returns to the greeter because Hyprland aborts during session startup.
**Cause:** Current Hyprland/Aquamarine parses `AQ_DRM_DEVICES` as a colon-separated list of DRM device paths. Laptop `/dev/dri/by-path/pci-0000:...` symlinks contain literal colons, so the parser splits them into invalid fragments, finds no usable GPU backend, and the compositor exits.
**Status:** Workaround in place
**Resolution:** `config/hypr/env.conf` keeps the laptop on `/dev/dri/card2:/dev/dri/card1` for now. Revisit the by-path approach only after Aquamarine supports embedded colons or exposes another stable device selector.

## EGL vendor policy must stay host-specific
**Symptom:** EGL clients on the desktop can miss the NVIDIA EGL ICD.
**Cause:** The laptop needs Mesa-only EGL vendor selection for the hybrid path, while the dedicated desktop needs both the NVIDIA and Mesa ICDs.
**Status:** Host split in place
**Resolution:** `system/configuration.nix` leaves `__EGL_VENDOR_LIBRARY_FILENAMES` unset. `hosts/laptop/system.nix:68-69` sets the laptop's Mesa-only value, and `hosts/desktop/system.nix:70-72` sets the desktop's dual-vendor list directly.
