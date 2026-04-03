# Hyprland Review

Reviewed on 2026-04-03.

## Verdict

The active config already uses current Hyprland concepts: sourced files, modern
rule syntax, fallback monitor rules, and a solid `hypridle` / `hyprlock` flow.
The main gap is a wallpaper ownership divergence with the theming spec.

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
| Medium | `autostart.conf` applies a hardcoded wallpaper via `awww img` at session start. | The theming spec assigns wallpaper ownership to the `wallpaper` target (`docs/theming/SPEC.md`). The hardcoded `exec-once` in `autostart.conf:13` is a parallel write path that can conflict with or override the theme-selected wallpaper. |
| Low | Some rule matches depend on exact titles or classes that may drift. | Packaging or upstream naming changes can silently break float/placement rules. |
| Low | The bind set does not use newer descriptive or repeat-oriented forms such as `bindd` or `binde`. | No correctness issue, but discoverability and hold-to-repeat ergonomics could improve. |

Operational quirks (DRM device paths, `intel_backlight` assumptions, and
`env.conf` structure) are tracked in `docs/hyprland/QUIRKS.md`.

Desktop-specific NVIDIA resume and EGL caveats are tracked in
`docs/nvidia/QUIRKS.md`.
