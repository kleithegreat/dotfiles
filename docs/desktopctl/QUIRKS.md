# desktopctl Quirks

## `brightness seed` is a compatibility no-op
**Symptom:** `desktopctl brightness seed` exits successfully but does not update any visible brightness state.
**Cause:** The old `/tmp/quickshell-brightness` file contract is gone, and `desktopctl/src/brightness.rs:91-93` keeps `seed()` only as a no-op shim.
**Status:** Current behavior
**Resolution:** Use `desktopctl brightness up` / `down` for the live Quickshell OSD path. Do not depend on `seed` to populate any cache file.

## `dark_hint` and night-light mode are only partly coupled
**Symptom:** Changing the browser/electron dark hint can leave `hyprsunset` untouched, and toggling night light `on` or `off` can leave `dark_hint` unchanged.
**Cause:** `desktopctl/src/daemon/night_light.rs:129-163` only applies `dark_hint` while mode is `auto`, while `desktopctl/src/theme/mod.rs:252-320` still allows direct `dark_hint` writes from theme surfaces.
**Status:** Current behavior
**Resolution:** Treat `desktopctl night-light ...` as the `hyprsunset` control surface and `desktopctl theme set dark_hint ...` as the persisted browser/GTK hint surface. They are related, but they are not one unified override model today.
