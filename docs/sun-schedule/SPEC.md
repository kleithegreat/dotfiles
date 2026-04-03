# Sun Schedule Specification

This spec defines the intended contract for solar-time automation: which
component owns scheduled night-light transitions, which component owns
`dark_hint` mutation, how the timer stack behaves, and how coordinates are
resolved. It is the intent document; see `docs/sun-schedule/ARCHITECTURE.md`
for the current implementation map.

## Goals

- Reconcile solar state without requiring Quickshell to be running.
- Drive `hyprsunset` from sunrise and sunset in local time.
- Drive the scheduled `dark_hint` value without creating a second theme-state
  store.
- Keep timer repair and coordinate fallback deterministic.

Non-goals:

- Embedding solar scheduling inside Quickshell services
- Letting callers edit `themes/state.json` or GTK dconf directly
- Treating duplicate `hyprsunset` writers as acceptable

## Ownership Boundaries

| Concern | Owner | Contract |
| --- | --- | --- |
| Solar-time policy | `sun-schedule` | The scheduler decides when sunrise, sunset, and the nightly dark-hint threshold occur. |
| Automated `hyprsunset` writes | `sun-schedule` | Scheduled start/stop of `hyprsunset` belongs to this domain. Other components may observe state, but parallel direct writers are out of spec and must be treated as conflicts. |
| Scheduled `dark_hint` value | `sun-schedule` | The scheduler decides when the time-based value should be `true` or `false`. |
| `dark_hint` persistence | The theming pipeline | `themes/apply-theme` is the only supported writer of `themes/state.json`. Callers request a change; they do not edit the file themselves. |
| GTK dark-preference side effects | The theming pipeline | The `gtk` target owns the resulting dconf writes for `gtk-theme` and `color-scheme`. |
| Shell display UI | Quickshell | The shell may surface status or request supported mutations, but it is not the authoritative solar scheduler. |

Invariants:

- Time-based `hyprsunset` automation must not depend on Quickshell process
  lifetime.
- Time-based `dark_hint` automation must go through `themes/apply-theme`; it
  must not introduce a second direct write path to `themes/state.json` or GTK
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

- A `schedule` run must apply the current state immediately before it creates
  future timers.
- `sunset-action` only starts `hyprsunset`.
- `sunrise-action` stops `hyprsunset` and clears `dark_hint`.
- `dark-on` only enables `dark_hint`.

## Timer Lifecycle

The timer stack has one long-lived repair timer and three short-lived event
timers.

| Unit class | Owner | Contract |
| --- | --- | --- |
| `sun-scheduler.timer` / `sun-scheduler.service` | Home Manager module | Periodically reruns the scheduler after startup and every two hours. |
| `sun-event-sunrise.timer` / `.service` | `sun-schedule` runtime | Single next sunrise only. Replaced on every `schedule` pass. |
| `sun-event-sunset.timer` / `.service` | `sun-schedule` runtime | Single next sunset only. Replaced on every `schedule` pass. |
| `sun-event-dark-on.timer` / `.service` | `sun-schedule` runtime | Single next 23:00 local event only. Replaced on every `schedule` pass. |

Invariants:

- There must be at most one active timer per `sun-event-*` basename.
- The three event timers are disposable transient user units, not declarative
  Home Manager units.
- Missed time while the session was away is repaired by the next `schedule`
  run's immediate reconcile, not by Quickshell.

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
