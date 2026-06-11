# Focus Time Quirks

## The UI is sampled, not event-driven
**Symptom:** The settings pane can lag behind the actual focused app by a few seconds.
**Cause:** The daemon rewrites the JSON summary once per second, but `SettingsFocusTimePane.qml` only polls it every `3000` ms.
**Status:** Current behavior
**Resolution:** Short-lived mismatches between the real active app and the rendered charts are expected. The pane is not subscribed to socket events or file-change notifications.

## Atomic JSON replacement prevents torn reads, but stale detection is still poll-driven
**Symptom:** Quickshell almost never sees half-written JSON, but it can still take roughly one polling interval plus the 5-second freshness window before the pane switches to "Focus daemon has not updated recently" after the daemon stops writing.
**Cause:** The daemon writes `focustime_state.tmp`, renames it over `focustime_state.json`, and updates `last_updated` once per second, while `SettingsFocusTimePane.qml` only polls every `3000` ms and treats summaries older than `5` seconds as stale.
**Status:** Current behavior
**Resolution:** Treat the file as an atomic heartbeat snapshot rather than an event stream. A short delay before the UI flips to the stale-state message is expected.

## Locked time is stored in SQLite but filtered out of the JSON totals
**Symptom:** The database contains `__locked__` rows even though the pane never shows lock time in totals, charts, or app rows.
**Cause:** The main loop records `__locked__` whenever `hyprlock` is running, and `build_summary()` explicitly excludes that sentinel from its aggregate queries.
**Status:** Current behavior
**Resolution:** Query SQLite directly if you need to inspect locked-session history; the JSON contract is intentionally summary-only and omits it.

## App labels depend on desktop-file metadata matching Hyprland window classes
**Symptom:** Some apps appear with the raw class name and an empty icon.
**Cause:** Name/icon resolution is built from `.desktop` files keyed by `StartupWMClass` and desktop-file basename; unmatched classes fall back to `(window_class, "")`.
**Status:** Current behavior
**Resolution:** If a label looks wrong, check whether the app's desktop entry exposes the same class that Hyprland reports.

## The desktop-entry index is built once at daemon startup
**Symptom:** An app installed (or whose `.desktop` entry changed) after `desktopctl daemon` started keeps showing its raw window class and an empty icon in the Screen Time pane.
**Cause:** The focus tracker scans all `.desktop` application directories once when it starts and resolves every window class against that fixed in-memory index; nothing rescans while the daemon runs.
**Status:** Current behavior
**Resolution:** Restart `desktopctl daemon` after installing apps if the labels matter; accumulated seconds are unaffected because SQLite stores the raw class.
