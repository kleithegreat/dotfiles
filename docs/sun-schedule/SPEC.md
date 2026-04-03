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
- Keep schedule repair and coordinate fallback deterministic.

Non-goals:

- Embedding solar scheduling inside Quickshell services
- Letting callers edit theme-state storage or GTK dconf directly
- Treating duplicate `hyprsunset` writers as acceptable

## Ownership Boundaries

| Concern | Owner | Contract |
| --- | --- | --- |
| Solar-time policy | `desktopctl daemon` solar subsystem | The scheduler decides when sunrise, sunset, and the nightly dark-hint threshold occur. |
| Automated `hyprsunset` writes | `desktopctl daemon` solar subsystem | Scheduled start/stop of `hyprsunset` belongs to this domain. Other components may observe state, but parallel direct writers are out of spec and must be treated as conflicts. |
| Scheduled `dark_hint` value | `desktopctl daemon` solar subsystem | The scheduler decides when the time-based value should be `true` or `false`. |
| `dark_hint` persistence | The theming pipeline via `desktopctl theme` | `desktopctl theme` is the only supported writer of the persisted theme state in `desktopctl.db`. Callers request a change; they do not edit storage directly. |
| GTK dark-preference side effects | The theming pipeline | The `gtk` target owns the resulting dconf writes for `gtk-theme` and `color-scheme`. |
| Shell display UI | Quickshell | The shell may surface status or request supported mutations, but it is not the authoritative solar scheduler. |

Invariants:

- Time-based `hyprsunset` automation must not depend on Quickshell process
  lifetime.
- Time-based `dark_hint` automation must go through `desktopctl theme`; it must
  not introduce a second direct write path to the persisted theme state or GTK
  dconf.
- A future manual override model must add explicit arbitration. It must not
  rely on two components writing `hyprsunset` independently.

## Scheduled State Contract

Solar automation uses local wall-clock time and timezone-aware sunrise/sunset
values.

| Time window | `hyprsunset` | `dark_hint` |
| --- | --- | --- |
| `sunrise <= now < sunset` | Off | `false` |
| `sunset <= now < 23:00` | On at `4500K` | `false` |
| `23:00 <= now < next sunrise` | On at `4500K` | `true` |

Rules:

- The scheduler must apply the current state immediately before waiting for the
  next event.
- `sunset` only starts `hyprsunset`.
- `sunrise` stops `hyprsunset` and clears `dark_hint`.
- `dark-on` only enables `dark_hint`.

## Scheduler Lifecycle

The active implementation uses one long-lived in-process scheduler inside
`desktopctl daemon`, not systemd timers.

| Trigger | Owner | Contract |
| --- | --- | --- |
| Initial reconcile | `desktopctl daemon` solar subsystem | Applies the correct current state immediately when the daemon starts. |
| Next solar event sleep | `desktopctl daemon` solar subsystem | Waits until the next sunrise, sunset, or 23:00 dark-on event and applies it directly. |
| Periodic repair tick | `desktopctl daemon` solar subsystem | Recomputes state every 2 hours to repair missed time or external drift. |
| `SIGUSR1` recompute | `desktopctl daemon` solar subsystem | Forces an early recompute without restarting the daemon. |

Invariants:

- There is exactly one scheduler loop per running `desktopctl daemon` process.
- Missed time while the session was away is repaired by the next daemon start
  or repair tick, not by Quickshell.
- The scheduler does not depend on transient user units or Home Manager timer
  declarations.

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
