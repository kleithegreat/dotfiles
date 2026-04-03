# Sun Schedule Quirks

## A valid cached location prevents future GeoClue refresh
**Symptom:** Solar events keep following an old location even after moving the machine or fixing GeoClue.
**Cause:** `scripts/sun-schedule` reads `$XDG_CACHE_HOME/sun-schedule/location.json` first and returns immediately if it can parse `latitude` and `longitude`; it does not requery GeoClue while that cache stays valid.
**Status:** Open
**Resolution:** Delete or invalidate the cache file to force a fresh `where-am-i` lookup on the next scheduler run.

## GeoClue lookup fails open to the hardcoded Texas fallback
**Symptom:** Sunrise, sunset, and the 23:00 dark-hint behavior follow College Station, TX even though the machine is elsewhere.
**Cause:** If the cache is missing or invalid and `where-am-i` is missing, times out, exits nonzero, raises an OS error, or produces unparsable latitude/longitude lines, the script silently falls back to `30.6280, -96.3344`.
**Status:** Fallback in place
**Resolution:** Verify that `where-am-i` works under the user session and inspect or clear the cache file before assuming the schedule is using live coordinates.

## The `where-am-i` parser is format-sensitive
**Symptom:** GeoClue appears to work manually, but `sun-schedule` still refuses to cache or use the result.
**Cause:** The parser expects colon-delimited output lines containing case-insensitive `latitude` and `longitude`, and it only strips a trailing degree symbol before `float()` conversion.
**Status:** Open
**Resolution:** Keep the helper output in the expected format or update the parser before relying on alternate localization or formatting.

## `sun-event-*` timers only exist after the scheduler has run
**Symptom:** `systemctl --user status sun-event-sunset.timer` reports that the unit does not exist, even though the feature is enabled.
**Cause:** Those timers are transient units created by `systemd-run --user --collect`; they are not declarative Home Manager units on disk.
**Status:** By design
**Resolution:** Inspect them after `sun-scheduler.service` has run, or rerun the scheduler manually to recreate them.

## Repo-root and PATH assumptions are baked into the service chain
**Symptom:** The timer fires, but the script or one of its helper commands cannot be found.
**Cause:** `home/sun-schedule.nix` hardcodes the service entry point as `${HOME}/repos/dotfiles/scripts/sun-schedule`, the script resolves `themes/apply-theme` relative to its own location, and runtime tools such as `timeout`, `where-am-i`, `systemctl`, `systemd-run`, `hyprctl`, `hyprsunset`, `pgrep`, and `pkill` are invoked by name.
**Status:** Open
**Resolution:** Keep the repo checkout at the expected path or update the module, and ensure the required tools are available in the user environment.
