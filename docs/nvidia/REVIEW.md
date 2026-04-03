# NVIDIA Review

Reviewed on 2026-04-03.

## Verdict

The current NVIDIA setup is functional and the host split is intentional, but
the implementation still hides some policy in shared defaults and user-session
fragments. The main improvement targets are to replace brittle laptop DRM
device numbering and make the desktop resume workaround lifecycle easier to
audit.

## Strengths

| Area | Current state |
| --- | --- |
| Host split | The repo cleanly separates the hybrid laptop path from the dedicated desktop path at the host-module layer (`hosts/laptop/system.nix:46-64`, `hosts/desktop/system.nix:56-71`). |
| EGL policy locality | Each host module now owns its own EGL vendor selection instead of depending on a shared baseline override (`hosts/laptop/system.nix:63-64`, `hosts/desktop/system.nix:69-71`). |
| Desktop resume workaround | The desktop-only suspend stack is explicit: preserved VRAM storage, kernel patch overlay, and the systemd freeze workaround are all present and localized to the desktop (`hosts/desktop/system.nix:4-16`, `hosts/desktop/system.nix:65-67`, `overlays/nvidia-open-pr996.nix:1-43`). |
| Session wiring | Home Manager keeps the Hyprland GPU env file host-specific, so the laptop and desktop do not share the same user-session GPU assumptions (`home/default.nix:209-213`). |
| Option locality | The actual `hardware.nvidia.*` and `services.xserver.videoDrivers` settings remain in the host modules instead of being scattered across unrelated files (`hosts/laptop/system.nix:47-62`, `hosts/desktop/system.nix:56-63`). |

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| High | The laptop hybrid path still depends on hardcoded `/dev/dri/cardN` ordering. | `config/hypr/env.conf:13-16` sets `AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1`. Card numbering can change across boots, kernel updates, or driver changes, which can silently break the intended Intel-primary ordering. |
| Medium | The desktop resume workaround spans several files and one of its key comments still frames it as an experiment. | The steady-state workaround now lives across `hosts/desktop/system.nix:4-16`, `hosts/desktop/system.nix:60-67`, and `overlays/nvidia-open-pr996.nix:1-43`, but `hosts/desktop/system.nix:61` still says "Experiment". That comment now understates how intentional and cross-file the workaround really is. |
| Low | The PR #996 overlay has only a comment-based removal trigger. | `hosts/desktop/system.nix:5-6`, `overlays/nvidia-open-pr996.nix:1-2`, and `docs/nvidia/QUIRKS.md` all say to remove the overlay once a future driver release includes the fix, but the repo does not record which nixpkgs driver version still needs it. Upgrades will require manual re-validation. |
| Low | The shared unfree allowlist exposes NVIDIA and CUDA closure details without documenting ownership. | `system/configuration.nix:83-120` includes many CUDA package names plus `nvidia-settings` and `nvidia-x11`, but the list does not say which package or host path requires each entry. That makes future cleanup or regression triage harder than it needs to be. |

## QUIRKS.md Status

`docs/nvidia/QUIRKS.md` still matches the current implementation:

- The preserved-VRAM workaround is backed by `boot.tmp.useTmpfs = true` in
  `system/configuration.nix:127` and `NVreg_TemporaryFilePath=/var/tmp` in
  `hosts/desktop/system.nix:12-16`.
- The resume-delay workaround still matches the desktop-only combination of
  `hardware.nvidia.powerManagement.kernelSuspendNotifier = false` plus the PR
  #996 overlay (`hosts/desktop/system.nix:60-62`,
  `overlays/nvidia-open-pr996.nix:1-43`).
- The systemd user-session freeze workaround is still present in
  `hosts/desktop/system.nix:65-67`.
- EGL vendor policy is now host-local: `hosts/laptop/system.nix:63-64` sets the
  Mesa-only laptop value, and `hosts/desktop/system.nix:69-71` sets the
  dual-vendor desktop value.
