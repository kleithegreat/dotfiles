# NVIDIA Quirks

## Preserved VRAM needs a disk-backed temp path
**Symptom:** Suspend/resume on the desktop can lose GPU state or come back garbled.
**Cause:** The shared system uses tmpfs-backed `/tmp`, but the NVIDIA preserve-VRAM path needs storage that survives the suspend cycle.
**Status:** Workaround in place
**Resolution:** `hosts/desktop/system.nix` sets `NVreg_TemporaryFilePath=/var/tmp` instead of leaving the driver on `/tmp`.

## Slow resume from suspend can stall display recovery
**Symptom:** Resume on the desktop can stall for about 31.4 seconds between `PM: suspend exit` and display output recovery, with `NVRM: _kgspRpcRecvPoll: GSP RM heartbeat timed out` in the journal on every resume.
**Cause:** The current upstream NVIDIA open-driver source on this nixpkgs pin already contains the old PR `#996` reset path, but the desktop still depends on the remaining suspend settings around `kernelSuspendNotifier = false` and the systemd sleep-freeze workaround. The old local overlay has been removed, but that no-overlay state has not yet been re-validated on a real desktop suspend/resume cycle.
**Status:** Untested after overlay removal
**Resolution:** Keep the remaining desktop-only settings in `hosts/desktop/system.nix` for now: `hardware.nvidia.powerManagement.kernelSuspendNotifier = false`, `NVreg_TemporaryFilePath=/var/tmp`, and `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false`. Re-test suspend/resume on the real desktop before treating the overlay removal as fully validated.

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
**Resolution:** `system/configuration.nix` leaves `__EGL_VENDOR_LIBRARY_FILENAMES` unset. `hosts/laptop/system.nix` sets the laptop's Mesa-only value through `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES`, and `hosts/desktop/system.nix` sets the desktop's dual-vendor list directly through the same variable.
