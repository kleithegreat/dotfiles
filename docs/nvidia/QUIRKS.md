# NVIDIA Quirks

## Preserved VRAM needs a disk-backed temp path
**Symptom:** Suspend/resume on the desktop can lose GPU state or come back garbled.
**Cause:** The shared system uses tmpfs-backed `/tmp`, but the NVIDIA preserve-VRAM path needs storage that survives the suspend cycle.
**Status:** Workaround in place
**Resolution:** `hosts/desktop/system.nix` sets `NVreg_TemporaryFilePath=/var/tmp` instead of leaving the driver on `/tmp`.

## Resume is touchy with the kernel suspend notifier enabled
**Symptom:** Resume can hit a GSP heartbeat timeout on the desktop.
**Cause:** The current suspend path appears brittle with `hardware.nvidia.powerManagement.kernelSuspendNotifier = true`.
**Status:** Open
**Resolution:** `hosts/desktop/system.nix` currently forces `powerManagement.kernelSuspendNotifier = false` to try the legacy sleep-unit path; this still needs confirmation.

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
