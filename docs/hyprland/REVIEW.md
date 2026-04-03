# Hyprland Review

Reviewed on 2026-04-02.

## Verdict

The active config already uses current Hyprland concepts: sourced files, modern
rule syntax, fallback monitor rules, and a solid `hypridle` / `hyprlock` flow.
The main gaps are path stability and a small amount of source-graph drift.

## Strengths

| Area | Current state |
| --- | --- |
| Multi-file layout | `hyprland.conf` uses a clear sourced graph with host and generated inputs loaded early |
| Rules | Active files already use current `windowrule` and `layerrule` forms |
| Monitors | Each host keeps the wiki-recommended fallback `monitor = , preferred, auto, 1` rule |
| Idle/lock | `hypridle` and `hyprlock` follow the common lock-before-sleep pattern |

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| High | The laptop still uses unstable `/dev/dri/cardN` paths in `AQ_DRM_DEVICES`. | Boot-order or driver changes can remap `cardN` numbering and break the intended GPU ordering. |
| Medium | Stale files still blur the live source graph. | `pluginsettings.conf` is no longer sourced, and `config/hypr/monitors.conf` is bypassed by the known hosts, so the tree reads as more active than it is. |
| Low | `hosts/desktop/env.conf` mixes environment variables with a host-only `exec-once`. | It works, but it weakens the semantic meaning of the fragment. |
| Low | Some rule matches depend on exact titles or classes that may drift. | Packaging or upstream naming changes can silently break float/placement rules. |
| Low | The bind set does not use newer descriptive or repeat-oriented forms such as `bindd` or `binde`. | No correctness issue, but discoverability and hold-to-repeat ergonomics could improve. |

Desktop-specific NVIDIA resume and EGL caveats are tracked in
`docs/nvidia/QUIRKS.md`.
