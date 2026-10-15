# Sun Schedule

## Intent

- Solar automation lives in `desktopctl daemon`, not Quickshell or timers, so
  it survives the shell being absent. The daemon is the only writer of
  `hyprsunset`; everything else asks through `desktopctl night-light`.
- The override mode (`auto`/`on`/`off`) is in-memory on purpose: a restart
  returns to `auto`. Don't persist it.
- `hyprsunset` runs at 4500K from sunset to sunrise; `dark_hint` turns on at
  23:00 and off at 06:00 as one-shot edges, never reapplied inside a window.
- A manual `dark_hint` write wins until the next edge. Edges route through the
  theme queue like any mutation. A once-per-boot catch-up applies the schedule
  only when no manual write is recorded for the current window; it depends on
  the clock alone and finishes before the socket serves, so restored apps
  start with the settled value.
- Coordinates: `DESKTOPCTL_LOCATION` pin → cache fresher than 6h → GeoClue
  (`where-am-i`) → stale cache → College Station fallback. Degradation is
  deterministic and never fatal; a malformed pin warns and falls through. A
  pin outranks even a fresh cache. Only the laptop geolocates (and runs
  `automatic-timezoned`); the desktop pins its zone and coordinates.
- Place names come only from `solar.rs` reverse geocoding, lazily on
  `sun status`, cached beside the coordinates and dropped when they refresh,
  and ignored when they don't match the coordinates being printed.

## Quirks

### `where-am-i` exits only on its own timeout
Wrapping it in `timeout` and gating on status throws away every fix (status
124). Pass its own `--timeout`, parse stdout regardless, and keep any outer
bound longer. This once pinned the desktop to the fallback with GeoClue fine.

### Wrong sunrise/sunset times usually mean silent coordinate fallback
A new pin needs a session (or `desktopctl.service`) restart to reach the
daemon. Otherwise check `desktopctl sun status`, `where-am-i` under the user
session, `journalctl -u geoclue`, and
`$XDG_CACHE_HOME/sun-schedule/location.json`. The parser wants colon-delimited
`latitude`/`longitude` lines; GeoClue working by hand doesn't mean it parsed.

### Reconcile failures are non-fatal by design
`solar reconcile failed (will retry ...)` during compositor restarts
self-heals at the next event, `SIGUSR1`, or 2-hour repair tick. The daemon
shells out by name, so debug under the session's `PATH`.
