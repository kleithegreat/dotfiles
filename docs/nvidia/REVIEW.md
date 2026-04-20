# NVIDIA Review

Reviewed on 2026-04-09.

## Verdict

The current NVIDIA setup is functional and the host split is intentional, but
the implementation still hides some policy in shared defaults and user-session
fragments. The main improvement targets are to replace brittle laptop DRM
device numbering without reintroducing the current `AQ_DRM_DEVICES`
compatibility break, and to make the desktop resume workaround lifecycle easier
to audit.

## Strengths

| Area | Current state |
| --- | --- |
| Host split | The repo cleanly separates the hybrid laptop path from the dedicated desktop path at the host-module layer in `hosts/laptop/system.nix` and `hosts/desktop/system.nix`. |
| EGL policy locality | Each host module now owns its own `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES` setting instead of depending on a shared baseline override. |
| Laptop GPU routing locality | The laptop Hyprland env keeps Intel-first user-session routing localized to `config/hypr/env.conf`, so the hybrid-specific `LIBVA_DRIVER_NAME` and `AQ_DRM_DEVICES` policy are easy to audit. |
| Desktop resume workaround | The desktop-only suspend stack is explicit: preserved VRAM storage, kernel patch overlay, and the systemd freeze workaround are all present and localized to the desktop host module plus `overlays/nvidia-open-pr996.nix`. |
| Session wiring | Home Manager keeps the Hyprland GPU env file host-specific through the `host.hyprland.env` selection in `home/xdg.nix`, so the laptop and desktop do not share the same user-session GPU assumptions. |
| Option locality | The actual `hardware.nvidia.*` and `services.xserver.videoDrivers` settings remain in the host modules instead of being scattered across unrelated files. |

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| High | The laptop hybrid path still depends on hardcoded `/dev/dri/cardN` ordering. | `config/hypr/env.conf` intentionally stays on `AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1` because current Hyprland/Aquamarine parses `AQ_DRM_DEVICES` as a colon-separated list and breaks on `/dev/dri/by-path/pci-0000:...` values. That keeps the session bootable today, but card numbering can still change across boots, kernel updates, or driver changes. |
| Medium | The desktop resume workaround spans several files and one of its key comments still frames it as an experiment. | The steady-state workaround now lives across the desktop host module's `nixpkgs.overlays`, `boot.extraModprobeConfig`, `hardware.nvidia.powerManagement.kernelSuspendNotifier`, and `systemd.services.systemd-suspend.environment` entries, plus `overlays/nvidia-open-pr996.nix`, but `hosts/desktop/system.nix` still labels `powerManagement.kernelSuspendNotifier = false` with `# Experiment:`. That comment now understates how intentional and cross-file the workaround really is. |
| Low | The PR #996 overlay has only a comment-based removal trigger. | `hosts/desktop/system.nix`, `overlays/nvidia-open-pr996.nix`, and `docs/nvidia/QUIRKS.md` all say to remove the overlay once a future driver release includes the fix, but the repo does not record which nixpkgs driver version still needs it. Upgrades will require manual re-validation. |
| Low | The shared unfree allowlist exposes NVIDIA and CUDA closure details without documenting ownership. | `allowedUnfreePackageNames` in `system/configuration.nix` includes many CUDA package names plus `nvidia-settings` and `nvidia-x11`, but the list does not say which package or host path requires each entry. That makes future cleanup or regression triage harder than it needs to be. |

## QUIRKS.md Status

`docs/nvidia/QUIRKS.md` still matches the current implementation:

- The preserved-VRAM workaround is backed by `boot.tmp.useTmpfs = true` in
  `system/configuration.nix` and `NVreg_TemporaryFilePath=/var/tmp` in the
  `boot.extraModprobeConfig` block in `hosts/desktop/system.nix`.
- The resume-delay workaround still matches the desktop-only combination of
  `hardware.nvidia.powerManagement.kernelSuspendNotifier = false` plus the PR
  #996 overlay in `hosts/desktop/system.nix` and
  `overlays/nvidia-open-pr996.nix`.
- The systemd user-session freeze workaround is still present in
  `hosts/desktop/system.nix` through
  `systemd.services.systemd-suspend.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS`.
- The laptop Hyprland path intentionally stays on `cardN` ordering:
  `config/hypr/env.conf` uses `/dev/dri/card2:/dev/dri/card1` because
  current `AQ_DRM_DEVICES` parsing treats `:` as the list separator and cannot
  safely represent `/dev/dri/by-path/pci-0000:...` symlinks.
- EGL vendor policy is now host-local: `hosts/laptop/system.nix` sets the
  Mesa-only laptop value through
  `environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES`, and
  `hosts/desktop/system.nix` sets the dual-vendor desktop value through the
  same variable.
