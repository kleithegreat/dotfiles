# desktopctl Quirks

## `dark_hint` and night-light mode are only partly coupled
**Symptom:** Changing the app/browser dark hint leaves `hyprsunset` untouched, and toggling night light `auto` / `on` / `off` does not immediately flip `dark_hint`.
**Status:** Current behavior
**Resolution:** Treat `desktopctl night-light ...` as the `hyprsunset` control surface and `desktopctl theme set dark_hint ...` as the persisted app/browser hint surface. The canonical split-ownership contract lives in `docs/sun-schedule/SPEC.md` (Ownership Boundaries).
