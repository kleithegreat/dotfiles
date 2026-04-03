# Theming Review

Reviewed on 2026-04-03.

## Verdict

The pipeline is coherent: one CLI, one schema, one registry, and a consistent
base/generated ownership model. The centralized scheme metadata resolved the
previous family/variant drift in `bat`, `snappy_switcher`, `vicinae`,
`vscode`, and `qt`. The recent wallpaper bootstrap and Quickshell font-routing
fixes removed several shell-facing mismatches. The main remaining gaps are the
last dependency-map drift around `tmux` and Neovim's intentional raw
pass-through.

## Findings

| Severity | Finding | Impact |
| --- | --- | --- |
| Medium | Dependency selection is not fully aligned with real consumers. | `tmux` is still listed under `mono_font` even though it does not consume the mono font family. |
| Low | `neovim` still consumes raw `family` and `variant` strings by design. | The centralized app-theme metadata does not currently drive the Neovim target, so any future scheme whose Neovim plugin identifiers diverge from repo `family` / `variant` values will still need Neovim-side handling. |

Known KDE/Kirigami and Kvantum limitations are tracked in
`docs/theming/QUIRKS.md`.
