# Focus Time Review

Reviewed on 2026-04-02.

## Verdict

The subsystem is small and understandable, but its producer/consumer boundary is
weaker than it looks. The JSON file is easy for Quickshell to consume, yet it
does not carry enough information to prove freshness or keep totals and visible
breakdowns aligned.

## Findings

| Severity | Finding | Why it matters | Evidence |
| --- | --- | --- | --- |
| High | The JSON contract has no freshness or liveness field, so Quickshell cannot tell a live daemon from a stale last write. | If the daemon dies after a successful write, `SettingsFocusTimePane.qml` keeps rendering old data and never reaches its "daemon is not running" empty state. | `scripts/focus-daemon.py:248-258`, `scripts/focus-daemon.py:261-266`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:50-64`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:69-72` |
| Medium | Aggregate totals include `Desktop` and `Quickshell`, but the visible app list and current-app label hide those classes. | The headline totals, week bars, and month heatmap can grow while the app breakdown does not add up to the same total and `Currently:` stays blank. | `scripts/focus-daemon.py:37`, `scripts/focus-daemon.py:180-185`, `scripts/focus-daemon.py:210-229` |
| Medium | Socket outages preserve the last seen focused class until reconnect, with no re-sync query after the disconnect. | If Hyprland's socket drops or stalls while focus changes, the daemon keeps attributing time to a stale app class until new events arrive. | `scripts/focus-daemon.py:318-349`, `scripts/focus-daemon.py:367-376` |
| Medium | Startup recording depends on one successful `hyprctl activewindow -j` call or a later focus-change event. | If the initial `hyprctl` query returns empty and the focused window never changes, unlocked time is skipped even though the daemon keeps running and rewriting JSON. | `scripts/focus-daemon.py:287-297`, `scripts/focus-daemon.py:352-376` |
| Low | The SQLite store has no retention, pruning, or compaction path. | `minute_totals` grows by one row per app-per-minute bucket forever, so the database can only grow over long-lived use. | `scripts/focus-daemon.py:113-138`, `scripts/focus-daemon.py:142-164` |
| Low | The empty-state message in QML conflates missing file, unreadable file, and invalid JSON with "daemon is not running". | Operational debugging is harder because the only user-facing failure text does not distinguish producer failure from consumer parse failure. | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-64`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:126-138` |

## Open Questions

- The current code writes only whole-second aggregates and never reads the
  SQLite store outside the daemon. If another consumer needs richer history, the
  repo does not yet define whether that contract should stay JSON-only or expose
  a shared service instead.
