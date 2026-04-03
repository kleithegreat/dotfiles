# Focus Time Specification

This spec documents the runtime contract currently implemented by
`scripts/focus-daemon.py` and consumed by Quickshell. It is intentionally
descriptive: when the code is ambiguous or weak at a boundary,
`docs/focus-time/REVIEW.md` calls that out instead of normalizing it away.

## Scope

| Surface | Current contract |
| --- | --- |
| Focus daemon | Tracks the active Hyprland window class, writes per-second aggregates into SQLite, and rewrites a JSON summary for Quickshell |
| SQLite store | Persistent per-day, per-hour, and per-minute counters keyed by window class |
| Runtime JSON | Single summary document at `$XDG_RUNTIME_DIR/focustime_state.json` |
| Quickshell consumer | `SettingsFocusTimePane.qml` polls and renders that JSON; it does not touch SQLite |

## Runtime Paths

| Path | Owner | Purpose |
| --- | --- | --- |
| `~/.local/bin/focus-daemon.py` | Home Manager install step | Executable launched by Hyprland autostart |
| `~/.config/hypr/autostart.conf` | Repo-managed Hyprland config | Starts the daemon with `exec-once` |
| `$XDG_DATA_HOME/focustime/focustime.db` | Focus daemon | Persistent SQLite database |
| `~/.local/share/focustime/focustime.db` | Focus daemon | Database fallback when `XDG_DATA_HOME` is unset |
| `$XDG_RUNTIME_DIR/focustime_state.json` | Focus daemon | Current JSON summary consumed by Quickshell |
| `/run/user/$UID/focustime_state.json` | Focus daemon | State-file fallback when `XDG_RUNTIME_DIR` is unset |
| `$XDG_RUNTIME_DIR/focustime_state.tmp` | Focus daemon | Sibling temp file used for atomic JSON replacement |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Event socket the daemon listens to for `activewindow>>` updates |

Additional read-only runtime inputs:

- `hyprctl activewindow -j` seeds the initial focused class before the socket
  listener starts.
- `.desktop` files are scanned under `XDG_DATA_HOME/applications`,
  `XDG_DATA_DIRS/*/applications`, `/run/current-system/sw/share/applications`,
  and `~/.nix-profile/share/applications` to resolve app display names and
  icons.

## Ownership And Write Boundaries

| Concern | Writer | Reader |
| --- | --- | --- |
| Session installation | Home Manager (`home/default.nix`) | Hyprland session startup |
| Hyprland socket | Hyprland | Focus daemon listener thread |
| SQLite tables | Focus daemon only | No repo consumer reads them directly today |
| JSON summary file | Focus daemon only | `SettingsFocusTimePane.qml` |
| QML pane state | Quickshell pane instance | The pane itself only |

Invariants:

- The daemon is the only repo code that mutates focus-time runtime data.
- Quickshell treats the JSON file as read-only and does not repair or rewrite it.
- The QML pane does not read SQLite directly.

## SQLite Contract

Connection behavior:

| Property | Current behavior |
| --- | --- |
| File creation | `DATA_DIR.mkdir(parents=True, exist_ok=True)` before connect |
| Connection mode | `sqlite3.connect(..., isolation_level=None)` |
| Journal mode | `PRAGMA journal_mode=WAL` |
| Migrations | `CREATE TABLE IF NOT EXISTS` only |
| Retention | None; rows accumulate indefinitely |

Schema:

### `daily_totals`

| Column | Type | Meaning |
| --- | --- | --- |
| `date` | `TEXT NOT NULL` | Local calendar date formatted as `YYYY-MM-DD` |
| `app_class` | `TEXT NOT NULL` | Hyprland window class or sentinel `__locked__` |
| `seconds` | `INTEGER NOT NULL DEFAULT 0` | Accumulated whole seconds |

Primary key: `(date, app_class)`

### `hourly_totals`

| Column | Type | Meaning |
| --- | --- | --- |
| `date` | `TEXT NOT NULL` | Local calendar date formatted as `YYYY-MM-DD` |
| `hour` | `INTEGER NOT NULL` | Local hour in `0..23` |
| `app_class` | `TEXT NOT NULL` | Hyprland window class or sentinel `__locked__` |
| `seconds` | `INTEGER NOT NULL DEFAULT 0` | Accumulated whole seconds |

Primary key: `(date, hour, app_class)`

### `minute_totals`

| Column | Type | Meaning |
| --- | --- | --- |
| `date` | `TEXT NOT NULL` | Local calendar date formatted as `YYYY-MM-DD` |
| `minute_index` | `INTEGER NOT NULL` | `hour * 60 + minute`, so `0..1439` |
| `app_class` | `TEXT NOT NULL` | Hyprland window class or sentinel `__locked__` |
| `seconds` | `INTEGER NOT NULL DEFAULT 0` | Accumulated whole seconds |

Primary key: `(date, minute_index, app_class)`

Write rules:

- The main loop targets one write cycle per second using a monotonic timer.
- If `pgrep -x hyprlock` succeeds, the daemon increments `__locked__` in all
  three tables for the current local time bucket.
- If the screen is unlocked and the current class is a non-empty string, the
  daemon increments that class in all three tables.
- If the screen is unlocked and the current class is empty, the daemon skips the
  SQLite write for that tick.
- Each tick uses a single explicit transaction: `BEGIN`, three UPSERTs, then
  `COMMIT`.

## JSON Summary Contract

The daemon rewrites `$XDG_RUNTIME_DIR/focustime_state.json` once per main-loop
iteration by serializing a single JSON object and atomically renaming a sibling
temp file into place.

Root object:

| Key | Type | Current meaning |
| --- | --- | --- |
| `selected_date` | string | Today's local date as `YYYY-MM-DD` |
| `total` | integer | Sum of today's `daily_totals.seconds`, excluding `__locked__` only |
| `average` | integer | Rounded average of non-zero daily totals in the current Monday-Sunday week, excluding `__locked__` only |
| `week_range` | string | Current Monday-Sunday range formatted like `Apr 1 - Apr 7` |
| `yesterday` | integer | Yesterday's total seconds, excluding `__locked__` only |
| `current` | string | `"Locked"` while locked; otherwise the resolved app name for the current class unless that class is `""`, `Desktop`, or `Quickshell`; otherwise `""` |
| `apps` | array | Per-app breakdown for today |
| `week` | array | Seven daily totals for the current Monday-Sunday week |
| `month` | array | Current month heatmap data with leading `null` padding |

`apps` entries:

| Key | Type | Current meaning |
| --- | --- | --- |
| `class` | string | Raw Hyprland window class |
| `name` | string | Resolved desktop entry name or the raw class if no match exists |
| `icon` | string | Desktop entry icon name or `""` when unresolved |
| `seconds` | integer | Today's accumulated seconds for that class |
| `percent` | number | `seconds / total * 100`, rounded to one decimal place |

`apps` constraints:

- Entries come from `daily_totals` for `selected_date`.
- `__locked__`, `""`, `Desktop`, and `Quickshell` are omitted.
- Rows are sorted by descending total seconds.

`week` entries:

| Key | Type | Current meaning |
| --- | --- | --- |
| `date` | string | Calendar date as `YYYY-MM-DD` |
| `day` | string | Three-letter local day label from `%a` |
| `total` | integer | Whole seconds for that date, excluding `__locked__` only |
| `is_target` | boolean | `true` on today's entry |

`week` constraints:

- The array always has exactly 7 objects.
- The order is Monday through Sunday.
- Days with no data stay present with `total: 0`.

`month` entries:

| Shape | Meaning |
| --- | --- |
| `null` | Leading padding cell before day 1 so the month grid aligns to Monday-first headers |
| object with `date`, `total`, `is_target` | Real day entry for the current month; `total` excludes `__locked__` only |

Important current behavior:

- `total`, `yesterday`, `week[*].total`, and `month[*].total` exclude
  `__locked__`, but they do not exclude `Desktop` or `Quickshell`.
- The `apps` list and `current` string do hide `Desktop` and `Quickshell`.
- The JSON has no schema version, timestamp, or explicit liveness field.

## App Name And Icon Resolution

The daemon resolves names and icons lazily the first time it needs them:

- It parses `.desktop` files and records `(Name, Icon)` pairs keyed by both
  `StartupWMClass` and the desktop-file basename.
- The lookup is case-insensitive.
- If no entry matches, `resolve_app()` returns `(window_class, "")`.

This resolution affects `apps[*].name`, `apps[*].icon`, and the unlocked
`current` string.

## Quickshell Read Contract

`SettingsFocusTimePane.qml` currently depends on these behaviors:

- The pane reads the state file by spawning `bash -c 'cat -- "$XDG_RUNTIME_DIR/focustime_state.json" 2>/dev/null || true'`.
- It polls every `3000` milliseconds and only starts another read when the prior
  `Process` is idle.
- Empty stdout or JSON parse failure means `hasData = false`.
- Missing keys fall back to `0`, `""`, or `[]` in QML because the pane reads
  with `stateData.foo || defaultValue`.
- The pane renders from `total`, `yesterday`, `average`, `current`, `apps`,
  `week`, `month`, and `week_range`.
- `selected_date` is currently parsed but not rendered.
- `month` must permit `null` entries because the heatmap grid uses them as blank
  leading cells.
