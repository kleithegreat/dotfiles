# Hyprland Review

Reviewed on 2026-04-03.

## Verdict

The active config already uses current Hyprland concepts: sourced files, modern
rule syntax, fallback monitor rules, descriptive keybinds, and a solid
`hypridle` / `hyprlock` flow. The remaining issues are minor and mostly about
match fragility in app-specific rules.

## Strengths

| Area | Current state |
| --- | --- |
| Multi-file layout | `hyprland.conf` uses a clear sourced graph with host and generated inputs loaded early |
| Rules | Active files already use current `windowrule` and `layerrule` forms |
| Monitors | Each host keeps the wiki-recommended fallback `monitor = , preferred, auto, 1` rule |
| Idle/lock | `hypridle` and `hyprlock` follow the common lock-before-sleep pattern |
| VM fallback | `home/default.nix` provides safe minimal defaults for unrecognized hosts |

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | Some rule matches depend on exact titles or classes that may drift. | Packaging or upstream naming changes can silently break float/placement rules. |

Operational quirks (DRM device paths, brightness-device assumptions, and
`env.conf` structure) are tracked in `docs/hyprland/QUIRKS.md`.

Desktop-specific NVIDIA resume and EGL caveats are tracked in
`docs/nvidia/QUIRKS.md`.
