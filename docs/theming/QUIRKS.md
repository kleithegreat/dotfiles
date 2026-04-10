# Theming Quirks

## Kirigami ignores a plain Qt palette outside Plasma
**Symptom:** KDE apps can show correctly themed file views but still keep a light or Breeze-colored toolbar, sidebar, or header area.
**Cause:** Kirigami chrome follows KDE color infrastructure, not just `QPalette`, on a Hyprland session without Plasma.
**Status:** Workaround in place
**Resolution:** The Qt target uses the full `qt6ct`/`qt5ct` + `kdeglobals`/`current.colors` + Kvantum + `hyprqt6engine` chain; `qt6ct + Fusion` or `hyprqt6engine` alone were only partial fixes.

## Quickshell keeps one committed generated snapshot
**Symptom:** `config/quickshell/GeneratedTheme.json` is checked into the repo even though generated outputs are usually kept out of version control.
**Cause:** Home Manager deploys `config/quickshell/` recursively, so the repo carries one bootstrap snapshot for the live `${XDG_CONFIG_HOME:-~/.config}/quickshell/GeneratedTheme.json` path before `desktopctl theme sync` and later runtime theme applies overwrite it.
**Status:** Deliberate exception
**Resolution:** Treat the committed file as bootstrap state, not as a hand-edited source of truth. Theme changes still flow through `desktopctl theme`, and no other generated snapshot should be committed by default.

## Kvantum SVG assets cap exact background matching
**Symptom:** Some KDE surfaces stay slightly off from the active background color even after the generated Kvantum config applies.
**Cause:** The reused KvGnome and KvGnomeDark SVGs have baked background shades that the generated kvconfig cannot fully override.
**Status:** Open
**Resolution:** The Qt target regenerates the color config and swaps the dark/light SVGs, but exact background matching would require custom SVG assets.

## Chromium font prefs are profile-local, web-content-only, and not live-reloaded
**Symptom:** Chromium font changes can appear to do nothing until the browser restarts, browser chrome keeps matching GTK instead of the Chromium-specific offset, and inactive Chromium profiles keep their old font settings.
**Cause:** The `chromium` target patches each active profile's `~/.config/chromium/<profile>/Preferences` `webkit.webprefs` entries based on `Local State` `profile.last_active_profiles`, falling back to `Default` when that list is unavailable. Those prefs drive web-content font families and CSS-pixel default font sizes; Chromium's own chrome continues to use the toolkit font settings from GTK, Chromium keeps one prefs file per profile, and a live browser session may rewrite an active profile's file on exit.
**Status:** Current behavior
**Resolution:** Treat the target as owning active profiles' web-font prefs only. Use the GTK font size and GTK offset controls for Chromium's browser chrome, and reapply the Chromium target after closing Chromium if a live session overwrote the managed values. Open an inactive profile once and rerun the target if you want that profile updated too.
