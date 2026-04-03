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

## Mesa-only EGL vendor selection breaks the dedicated NVIDIA desktop
**Symptom:** EGL clients on the desktop can miss the NVIDIA EGL ICD.
**Cause:** The shared NixOS config pins `__EGL_VENDOR_LIBRARY_FILENAMES` to Mesa for the hybrid laptop, which excludes NVIDIA on the dedicated-GPU host.
**Status:** Workaround in place
**Resolution:** `hosts/desktop/system.nix` overrides `__EGL_VENDOR_LIBRARY_FILENAMES` to include both `10_nvidia.json` and `50_mesa.json`.
