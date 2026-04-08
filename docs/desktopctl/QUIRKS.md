# desktopctl Quirks

## `dark_hint` and night-light mode are only partly coupled
**Symptom:** Changing the browser/electron dark hint can leave `hyprsunset` untouched, and toggling night light `on` or `off` can leave `dark_hint` unchanged.
**Cause:** `desktopctl/src/daemon/night_light.rs:129-163` only applies `dark_hint` while mode is `auto`, while `desktopctl/src/theme/mod.rs:74-96` and `desktopctl/src/theme/mod.rs:321-385` still allow direct `dark_hint` writes from theme surfaces.
**Status:** Current behavior
**Resolution:** Treat `desktopctl night-light ...` as the `hyprsunset` control surface and `desktopctl theme set dark_hint ...` as the persisted browser/GTK hint surface. They are related, but they are not one unified override model today.
