# Theming Review

Reviewed on 2026-04-02.

## Verdict

The pipeline is coherent: one CLI, one schema, one registry, and a consistent
base/generated ownership model. The main gaps are normalization drift,
dependency-map drift, and stale repo snapshots that still look authoritative.

## Findings

| Severity | Finding | Impact |
| --- | --- | --- |
| High | Variant and family normalization is not centralized. | Non-binary variants and family spellings still leak into targets that expect dark/light polarity or explicit family maps, especially `neovim.py`, `qt.py`, `vicinae.py`, and `vscode.py`. |
| Medium | Dependency selection is not fully aligned with real consumers. | `tmux` is still listed under `mono_font`, while Quickshell font-size changes do not route back to the `quickshell` target. |
| Medium | The repo still carries stale generated snapshots. | `config/ghostty/config`, `config/starship/starship.toml`, and `config/vicinae/settings.json` look like live sources even though the targets read `base` files and generate outputs elsewhere. |

Known KDE/Kirigami and Kvantum limitations are tracked in
`docs/theming/QUIRKS.md`.
