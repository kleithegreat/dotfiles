# NVIDIA Specification

This spec defines the current repo contract for NVIDIA-related policy across
the shared system layer, host modules, and Hyprland session environment.

## Scope

| Host path | Current contract |
| --- | --- |
| `laptop` | Hybrid Intel-primary rendering with NVIDIA PRIME offload and Nouveau disabled in the laptop kernel config |
| `desktop` | Dedicated NVIDIA rendering with desktop-only suspend/resume workarounds |

## Ownership Boundaries

| Concern | Owner | Contract |
| --- | --- | --- |
| Shared package and overlay baseline | `system/configuration.nix` | Owns the shared unfree allowlist, overlays, and graphics-adjacent baseline, but does not pick one host's EGL vendor policy |
| Hybrid laptop GPU policy | `hosts/laptop/system.nix` plus `config/hypr/env.conf` | Own the PRIME, Xorg driver list, laptop-local kernel GPU-driver pruning, Mesa EGL vendor selection, and Hyprland user-session GPU env for the laptop |
| Dedicated desktop GPU policy | `hosts/desktop/system.nix` plus `hosts/desktop/env.conf` | Own the desktop's dedicated NVIDIA stack, EGL vendor selection, VA-API/GBM/GLX env, and suspend/resume workarounds |
| Desktop suspend/resume policy | `hosts/desktop/system.nix` | Owns the desktop-only preserved-VRAM temp-path override, `kernelSuspendNotifier = false`, and the systemd user-session freeze workaround. The old PR #996 overlay has been removed because the current upstream open-driver source already includes that reset path, but this removal is still pending real suspend/resume validation on the desktop. |

## Host Contract

| Concern | Laptop | Desktop |
| --- | --- | --- |
| Driver mode | Open NVIDIA driver with `modesetting` plus PRIME offload; `DRM_NOUVEAU` disabled in the laptop kernel config | Open NVIDIA driver with `modesetting`, no PRIME |
| Xorg driver list | `["modesetting" "nvidia"]` | `["nvidia"]` |
| EGL vendor policy | Mesa-only value set in the laptop host module | Dual NVIDIA+Mesa value set in the desktop host module |
| Hyprland env file | `config/hypr/env.conf` | `hosts/desktop/env.conf` |
| Resume workarounds | None beyond the shared baseline | Preserved-VRAM temp-path override and user-session freeze workaround; the old PR #996 overlay has been removed but is still untested on real suspend/resume hardware |

Invariants:

- The shared system baseline must not force one host's EGL vendor policy onto
  the other host.
- Laptop and desktop GPU session env files are intentionally different.
- Desktop-specific NVIDIA resume workarounds stay desktop-local until they are
  no longer needed.
- Host modules own `hardware.nvidia.*` policy; Home Manager only selects which
  Hyprland env file reaches the user session.
