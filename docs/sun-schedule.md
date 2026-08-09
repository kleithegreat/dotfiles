# Sun Schedule

## Intent

- Solar automation lives inside `desktopctl daemon` — not Quickshell, not
  systemd timers. It must keep working when the shell restarts or is absent.
- The daemon's night-light controller is the only live writer of the
  `hyprsunset` process. Everything else (keybinds, Quickshell) requests changes
  through `desktopctl night-light ...`.
- The override mode (`auto`/`on`/`off`) is intentionally in-memory only: a
  daemon restart returns to `auto`. Do not "fix" this by persisting it.
- Schedule: `hyprsunset` on at 4500K from sunset to sunrise; `dark_hint`
  enabled at 23:00 and disabled at 06:00 local time as one-shot edges, plus a
  single startup reconcile if the persisted value is stale. After that first
  reconcile, staying inside a window must not keep reapplying the same value.
- `dark_hint` deliberately has *two* supported write paths: the daemon's
  scheduled edges and direct `desktopctl theme set dark_hint` / preset writes.
  Both persist through the theming pipeline's per-key upserts, so concurrent
  writers commute on disjoint keys. A unified override model is an open
  decision (`TODO.md`); do not unify it unilaterally.
- Coordinate resolution order: cached location fresh within 6 hours →
  GeoClue (`where-am-i`) → stale-but-parseable cache → hardcoded fallback
  `30.6280, -96.3344` (College Station, TX). Degradation must be
  deterministic, never fatal.

## Quirks

### Wrong sunrise/sunset times usually mean silent coordinate fallback
If GeoClue fails and the cache is missing or invalid, the scheduler silently
uses the College Station fallback; if the cache is stale but parseable, it
keeps the *last* resolved location indefinitely. Before debugging schedule
math, check `desktopctl sun status` and whether `where-am-i` works under the
user session, and inspect `$XDG_CACHE_HOME/sun-schedule/location.json`.

### The `where-am-i` parser is format-sensitive
`desktopctl/src/solar.rs` expects colon-delimited lines containing
case-insensitive `latitude`/`longitude` and only strips a trailing degree sign.
GeoClue "working manually" does not mean the scheduler parsed it.

### Reconcile failures are non-fatal by design
`solar reconcile failed (will retry at next event or repair tick)` in the
daemon log is expected during e.g. compositor restarts — the pending state
survives and self-heals at the next event, `SIGUSR1`, or 2-hour repair tick.
Only repeated failures across repair ticks indicate a real problem; the daemon
shells out to `timeout`, `where-am-i`, `hyprctl`, `hyprsunset`, `ps`, and
`pkill` by name, so debug under the same session `PATH` Hyprland uses.

Related: [[desktopctl]], [[theming]]
