# Sun Schedule Specification

This spec defines the intended contract for solar-time automation: which
component owns scheduled night-light transitions, which component owns
`dark_hint` mutation, how the scheduler behaves, and how coordinates are
resolved. It is the intent document; see `docs/sun-schedule/ARCHITECTURE.md`
for the current implementation map.

## Goals

- Reconcile solar state without requiring Quickshell to be running.
- Drive `hyprsunset` from sunrise and sunset in local time.
- Drive the scheduled `dark_hint` value without creating a second theme-state
  store.
- Support a non-persistent manual override with explicit arbitration.
- Keep schedule repair and coordinate fallback deterministic.

Non-goals:

- Embedding solar scheduling inside Quickshell services
- Letting callers edit theme-state storage or GTK dconf directly
- Treating duplicate `hyprsunset` writers as acceptable

## Ownership Boundaries

| Concern | Owner | Contract |
| --- | --- | --- |
| Solar-time policy | `desktopctl daemon` solar subsystem | The scheduler decides when sunrise, sunset, and the nightly dark-hint threshold occur, and keeps that schedule current even while an override is active. |
| Night-light override policy | `desktopctl daemon` night-light controller | The daemon owns the live override mode (`auto`, `on`, `off`) plus the in-session manual temperature. The override resets to `auto` on daemon restart. |
| Live `hyprsunset` lifecycle | `desktopctl daemon` night-light controller | The daemon is the only supported live writer of the `hyprsunset` process. Other components issue requests through `desktopctl`; they do not start, stop, or restart `hyprsunset` directly. |
| Live `dark_hint` policy | `desktopctl daemon` night-light controller | In `auto`, the daemon applies the solar schedule's `dark_hint`. In `on`/`off`, the daemon does not touch `dark_hint`; it is controlled independently via `desktopctl theme`. |
| `dark_hint` persistence | The theming pipeline via `desktopctl theme` | `desktopctl theme` remains the only supported writer of the persisted `theme_state.dark_hint` row in `desktopctl.db`, but direct `dark_hint` requests may be mediated by the daemon before persistence occurs. |
| GTK dark-preference side effects | The theming pipeline | The `gtk` target owns the resulting dconf writes for `gtk-theme` and `color-scheme`. |
| Shell and keybind surfaces | Quickshell and Hyprland config | The shell and keybinds may surface status or request supported mutations, but they are not authoritative state owners. |

Invariants:

- Time-based `hyprsunset` automation must not depend on Quickshell process
  lifetime.
- Live `hyprsunset` and `dark_hint` state must have exactly one arbiter inside
  `desktopctl daemon`.
- Time-based `dark_hint` automation must still go through `desktopctl theme`;
  it must not introduce a second direct write path to the persisted theme state
  or GTK dconf.
- Manual override state is intentionally non-persistent. A daemon restart
  returns the mode to `auto`.

## Scheduled State Contract

Solar automation uses local wall-clock time and timezone-aware sunrise/sunset
values.

### Effective mode contract

| Mode | `hyprsunset` | `dark_hint` |
| --- | --- | --- |
| `auto` | Follows the scheduled time window below | Follows the scheduled time window below |
| `on` | On at the current manual target temperature | Unchanged (controlled separately via `desktopctl theme`) |
| `off` | Off | Unchanged (controlled separately via `desktopctl theme`) |

Rules:

- `toggle` switches between `on` and `off` based on the current `hyprsunset`
  process state.
- Switching to `auto` applies the current scheduled state immediately.
- The override mode is not written to disk and does not survive daemon restarts.

### `auto` schedule contract

| Time window | `hyprsunset` | `dark_hint` |
| --- | --- | --- |
| `sunrise <= now < sunset` | Off | `false` |
| `sunset <= now < 23:00` | On at `4500K` | `false` |
| `23:00 <= now < next sunrise` | On at `4500K` | `true` |

Rules:

- The scheduler must compute the current scheduled state immediately before
  waiting for the next event.
- `sunset` only starts `hyprsunset`.
- `sunrise` stops `hyprsunset` and clears `dark_hint`.
- `dark-on` only enables `dark_hint`.

## Scheduler Lifecycle

The active implementation uses one long-lived in-process scheduler inside
`desktopctl daemon`, not systemd timers.

| Trigger | Owner | Contract |
| --- | --- | --- |
| Initial reconcile | `desktopctl daemon` solar subsystem + night-light controller | Computes the current solar status immediately when the daemon starts, stores it, and reconciles the effective mode. |
| Next solar event sleep | `desktopctl daemon` solar subsystem | Waits until the next sunrise, sunset, or 23:00 dark-on event, then recomputes solar status and lets the controller reconcile the effective mode. |
| Periodic repair tick | `desktopctl daemon` solar subsystem + night-light controller | Recomputes solar status every 2 hours to repair missed time or external drift, then reapplies the effective mode. |
| `SIGUSR1` recompute | `desktopctl daemon` solar subsystem | Forces an early recompute without restarting the daemon. |

Invariants:

- There is exactly one scheduler loop per running `desktopctl daemon` process.
- Missed time while the session was away is repaired by the next daemon start
  or repair tick, not by Quickshell.
- The scheduler does not depend on transient user units or Home Manager timer
  declarations.
- Solar recomputation continues while the mode is `on` or `off` so status stays
  current and returning to `auto` can apply immediately.

## Coordinate Resolution

The scheduler resolves coordinates in this order:

1. Cached coordinates at
   `$XDG_CACHE_HOME/sun-schedule/location.json`, falling back to
   `~/.cache/sun-schedule/location.json`.
2. GeoClue output from `where-am-i`.
3. Hardcoded fallback coordinates `30.6280, -96.3344` (College Station, TX).

Constraints:

- A parseable cache entry is authoritative until it is deleted or becomes
  invalid.
- A successful GeoClue lookup must be cached for future runs.
- GeoClue failure must degrade to deterministic fallback behavior, not abort
  the scheduler.
- The fallback coordinates and cache path are part of the contract and must be
  documented when they change.
