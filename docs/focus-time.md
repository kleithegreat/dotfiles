# Focus Time

## Intent

- The daemon's focus tracker is the only writer: per-second aggregates into
  `desktopctl.db` and a summary published over the `"focus"` IPC subscription
  topic (`focus.changed`). Quickshell reads the daemon stream only.
- Totals exclude `__locked__`, `Desktop`, `Quickshell` and empty classes so
  percentages sum to 100; locked time stays in SQLite.

## Quirks

### The desktop-entry index is built once at daemon startup
An app installed later shows its raw class until a daemon restart (the data is
fine). A wrong label for an installed app means its `StartupWMClass` or file
stem doesn't match the class Hyprland reports.
