# desktopctl Quirks

## `dark_hint` and night-light mode are only partly coupled
**Symptom:** Changing the browser/electron dark hint leaves `hyprsunset` untouched, and toggling night light `auto` / `on` / `off` does not immediately flip `dark_hint`.
**Cause:** `desktopctl/src/daemon/night_light.rs` now treats `dark_hint` as an edge-triggered 23:00/06:00 scheduler effect instead of a per-mode state, while `set_dark_hint()`, `cmd_set()`, and `cmd_preset()` in `desktopctl/src/theme/mod.rs` still allow direct `dark_hint` writes from theme surfaces.
**Status:** Current behavior
**Resolution:** Treat `desktopctl night-light ...` as the `hyprsunset` control surface and `desktopctl theme set dark_hint ...` as the persisted browser/GTK hint surface. The scheduled 23:00 enable plus 06:00 disable are the only automatic bridge between them; there is still no single unified override model.
