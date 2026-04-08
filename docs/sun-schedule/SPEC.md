# Sun Schedule Specification

This spec defines the current contract for solar-time automation: which
component owns scheduled night-light transitions, how coordinates are resolved,
and where the present ownership split around `dark_hint` still exists.

## Goals

- Reconcile solar state without requiring Quickshell to be running.
- Drive `hyprsunset` from sunrise and sunset in local time.
- Persist scheduled `dark_hint` changes through the same theme-state store used
  by the rest of the theming pipeline.
- Keep night-light override mode non-persistent and deterministic.
- Keep schedule repair and coordinate fallback deterministic.

Non-goals:

- Embedding solar scheduling inside Quickshell services
- Letting callers start or stop `hyprsunset` directly outside `desktopctl`
- Pretending `dark_hint` is daemon-owned when direct theme writes still exist

## Ownership Boundaries

| Concern | Owner | Contract |
| --- | --- | --- |
| Solar-time policy | `desktopctl daemon` solar subsystem | The scheduler decides when sunrise, sunset, and the nightly dark-hint threshold occur, and keeps that schedule current even while an override is active |
| Night-light override policy | `desktopctl daemon` night-light controller | The daemon owns the live override mode (`auto`, `on`, `off`) plus the in-session manual temperature. The override resets to `auto` on daemon restart |
| Live `hyprsunset` lifecycle | `desktopctl daemon` night-light controller | The daemon is the only supported live writer of the `hyprsunset` process. Other components issue requests through `desktopctl`; they do not start, stop, or restart `hyprsunset` directly |
| Scheduled `dark_hint` writes | `desktopctl daemon` via the theming module | In `auto`, the daemon persists the solar schedule's `dark_hint` through `theme::set_dark_hint()` |
| Manual and preset `dark_hint` writes | The theming pipeline via `desktopctl theme` | `desktopctl theme set dark_hint ...` and preset application still persist and apply `dark_hint` directly |
| GTK dark-preference side effects | The theming pipeline | The `gtk` target owns the resulting dconf writes for `gtk-theme` and `color-scheme` |
| Shell and keybind surfaces | Quickshell and Hyprland config | The shell and keybinds may surface status or request supported mutations, but they are not authoritative state owners |

Invariants:

- Time-based `hyprsunset` automation must not depend on Quickshell process
  lifetime.
- Live `hyprsunset` state has exactly one arbiter inside `desktopctl daemon`.
- `dark_hint` does not have a single arbiter today; docs and callers must treat
  solar `auto` writes and direct theme writes as separate supported paths.
- Manual override state is intentionally non-persistent. A daemon restart
  returns the mode to `auto`.

## Effective Mode Contract

| Mode | `hyprsunset` | `dark_hint` |
| --- | --- | --- |
| `auto` | Follows the scheduled time window below | Follows the scheduled time window below |
| `on` | On at the current manual target temperature | Unchanged |
| `off` | Off | Unchanged |

Rules:

- `toggle` switches between `on` and `off` based on the current `hyprsunset`
  process state.
- Switching to `auto` applies the current scheduled state immediately.
- The override mode is not written to disk and does not survive daemon restarts.

## `auto` Schedule Contract

| Time window | `hyprsunset` | `dark_hint` |
| --- | --- | --- |
| `sunrise <= now < sunset` | Off | `false` |
| `sunset <= now < 23:00` | On at `4500K` | `false` |
| `23:00 <= now < next sunrise` | On at `4500K` | `true` |

Rules:

- The scheduler computes the current scheduled state immediately before waiting
  for the next event.
- `sunset` only starts `hyprsunset`.
- `sunrise` stops `hyprsunset` and clears scheduled `dark_hint`.
- `dark-on` only enables scheduled `dark_hint`.

## Scheduler Lifecycle

The active implementation uses one long-lived in-process scheduler inside
`desktopctl daemon`, not systemd timers.

| Trigger | Owner | Contract |
| --- | --- | --- |
| Initial reconcile | `desktopctl daemon` solar subsystem + night-light controller | Computes the current solar status immediately when the daemon starts, stores it, and reconciles the effective mode |
| Next solar event sleep | `desktopctl daemon` solar subsystem | Waits until the next sunrise, sunset, or 23:00 dark-on event, then recomputes solar status and lets the controller reconcile the effective mode |
| Periodic repair tick | `desktopctl daemon` solar subsystem + night-light controller | Recomputes solar status every 2 hours to repair missed time or external drift, then reapplies the effective mode |
| `SIGUSR1` recompute | `desktopctl daemon` solar subsystem | Forces an early recompute without restarting the daemon |

## Coordinate Resolution

The scheduler resolves coordinates in this order:

1. Cached coordinates at
   `$XDG_CACHE_HOME/sun-schedule/location.json`, falling back to
   `~/.cache/sun-schedule/location.json`
2. GeoClue output from `where-am-i`
3. Hardcoded fallback coordinates `30.6280, -96.3344` (College Station, TX)

Constraints:

- A parseable cache entry is authoritative until it is deleted or becomes
  invalid.
- A successful GeoClue lookup must be cached for future runs.
- GeoClue failure must degrade to deterministic fallback behavior, not abort
  the scheduler.
- The fallback coordinates and cache path are part of the contract and must be
  documented when they change.
