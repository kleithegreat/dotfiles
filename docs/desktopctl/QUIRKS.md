# desktopctl Quirks

## `dark_hint` and night-light mode are only partly coupled
**Symptom:** Changing the browser/electron dark hint can leave `hyprsunset` untouched, and toggling night light `on` or `off` can leave `dark_hint` unchanged.
**Cause:** `desired_state()` / `apply_desired_state()` in `desktopctl/src/daemon/night_light.rs` only apply `dark_hint` while mode is `auto`, while `set_dark_hint()`, `cmd_set()`, and `cmd_preset()` in `desktopctl/src/theme/mod.rs` still allow direct `dark_hint` writes from theme surfaces.
**Status:** Current behavior
**Resolution:** Treat `desktopctl night-light ...` as the `hyprsunset` control surface and `desktopctl theme set dark_hint ...` as the persisted browser/GTK hint surface. They are related, but they are not one unified override model today.
