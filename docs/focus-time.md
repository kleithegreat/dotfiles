# Focus Time

## Intent

- The `desktopctl daemon` focus tracker is the only writer of focus-time data:
  per-second aggregates into the shared `desktopctl.db` SQLite database and an
  atomically-replaced JSON summary at
  `$XDG_RUNTIME_DIR/focustime_state.json`. Quickshell reads the JSON only —
  never SQLite — and never repairs or rewrites it.
- All summary totals exclude `__locked__`, `Desktop`, `Quickshell`, and
  empty-string classes so per-app percentages sum to 100. Locked time is still
  recorded in SQLite for anyone who queries it directly.
- The JSON is a once-per-second heartbeat snapshot, not an event stream;
  `last_updated` is the only liveness signal and the pane treats >5s as stale.

## Quirks

### The desktop-entry index is built once at daemon startup
App name/icon resolution scans `.desktop` files once when the tracker starts.
An app installed afterwards shows its raw window class and no icon until the
daemon restarts — the accumulated data is fine because SQLite stores raw
classes. If a label looks wrong for an app that *was* installed, check whether
its desktop entry's `StartupWMClass` (or file stem) matches the class Hyprland
reports.

### The pane lags reality by design
The daemon writes every second, the pane polls every 3s, and the stale window
is 5s — so a few seconds of lag behind the focused app, and a short delay
before the "daemon not updating" message appears, are both expected, not bugs.

Related: [[desktopctl]], [[quickshell]]
