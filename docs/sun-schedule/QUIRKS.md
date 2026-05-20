# Sun Schedule Quirks

## A stale cached location is still the offline fallback
**Symptom:** Solar events keep following the last successfully resolved location after moving while GeoClue is unavailable.
**Cause:** `desktopctl/src/solar.rs` treats `$XDG_CACHE_HOME/sun-schedule/location.json` as fresh for six hours, then attempts `where-am-i`; if GeoClue fails, a stale but parseable cache is preferred over the hardcoded College Station fallback.
**Status:** By design
**Resolution:** Fix GeoClue resolution or replace/delete the cache file if the stale location is worse than the deterministic fallback.

## GeoClue lookup fails open to the hardcoded Texas fallback
**Symptom:** Sunrise, sunset, and the 23:00/06:00 dark-hint behavior follow College Station, TX even though the machine is elsewhere.
**Cause:** If the cache is missing or invalid and `where-am-i` is missing, times out, exits nonzero, or produces unparsable latitude/longitude lines, `desktopctl/src/solar.rs` silently falls back to `30.6280, -96.3344`.
**Status:** Fallback in place
**Resolution:** Verify that `where-am-i` works under the user session and inspect or clear the cache file before assuming the schedule is using live coordinates.

## The `where-am-i` parser is format-sensitive
**Symptom:** GeoClue appears to work manually, but the scheduler still refuses to cache or use the result.
**Cause:** `desktopctl/src/solar.rs` expects colon-delimited output lines containing case-insensitive `latitude` and `longitude`, and it only strips a trailing degree symbol before `parse()`.
**Status:** Open
**Resolution:** Keep the helper output in the expected format or update the parser before relying on alternate localization or formatting.

## Solar automation only runs while `desktopctl daemon` is alive
**Symptom:** Sunrise/sunset automation stops entirely if the daemon exits, even though Quickshell and Hyprland keep running.
**Cause:** The old Home Manager timer and transient unit chain is gone; the active scheduler now lives only inside the long-running `desktopctl daemon` process.
**Status:** By design
**Resolution:** Treat `desktopctl daemon` as the session owner for solar automation and restart it if solar events stop firing.

## The scheduler still depends on helper tools being on `PATH`
**Symptom:** Solar state recomputes, but location lookup or night-light application silently falls back or does nothing.
**Cause:** The daemon invokes `timeout`, `where-am-i`, `hyprctl`, `hyprsunset`, `ps`, and `pkill` by name.
**Status:** Current behavior
**Resolution:** Keep the required tools in the user environment and debug the daemon under the same session `PATH` that Hyprland uses.
