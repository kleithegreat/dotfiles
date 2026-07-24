# Theming Review

Reviewed on 2026-04-03.

## Verdict

The pipeline is coherent: one CLI, one schema, one registry, and a consistent
base/generated ownership model. The centralized scheme metadata resolved the
previous family/variant drift in `bat`, `snappy_switcher`, `vicinae`,
`vscode`, and `qt`, the metadata layer now declares additional hook-managed
filesystem paths explicitly, and the last `tmux` dependency-map drift is gone.

Known KDE/Kirigami and Kvantum limitations are tracked in
`docs/theming/QUIRKS.md`.
