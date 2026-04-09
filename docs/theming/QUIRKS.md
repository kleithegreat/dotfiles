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

## Chromium font prefs are profile-local and not live-reloaded
**Symptom:** Chromium font changes can appear to do nothing until the browser restarts, and non-default Chromium profiles keep their old font settings.
**Cause:** The `chromium` target patches `~/.config/chromium/Default/Preferences`; Chromium keeps one prefs file per profile and may rewrite that file on exit.
**Status:** Current behavior
**Resolution:** Treat the target as owning the default profile's web-font prefs only. Reapply the target after closing Chromium if a live session overwrote the managed values.
