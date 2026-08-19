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
  enabled at 23:00 and disabled at 06:00 local time as one-shot edges.
  Staying inside a window must not keep reapplying the same value.
- `dark_hint` override policy: a manual write (theme set or preset) wins
  until the next 23:00/06:00 edge, when the schedule reasserts. The daemon is
  the single writer — scheduled edges route through the theme controller like
  every other theme mutation — and manual writes record their time in the
  `dark_hint_manual_at` state row. A daemon restart never clobbers a manual
  value: the scheduler acts on edges only, plus a once-per-boot catch-up that
  applies the schedule value only when no manual write is recorded for the
  current window (covering machines that were off across an edge).
- Coordinate resolution order: cached location fresh within 6 hours →
  GeoClue (`where-am-i`) → stale-but-parseable cache → hardcoded fallback
  `30.6280, -96.3344` (College Station, TX). Degradation must be
  deterministic, never fatal.

## Quirks

### `where-am-i` exits only on its own timeout
The helper watches for location updates until its `--timeout` fires and then
exits 0. Wrapping it in `timeout` and gating on the exit status therefore
discards every fix it ever produces: the wrapper kills it first, the status is
124, and the good coordinates in stdout are thrown away as a failure. `solar.rs`
passes the helper its own deadline and parses stdout regardless; any outer bound
must be the longer of the two. This is what pinned the whole desktop to the
College Station fallback while GeoClue was working perfectly.

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
