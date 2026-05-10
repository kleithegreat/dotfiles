# Theming Quirks

## Kirigami ignores a plain Qt palette outside Plasma
**Symptom:** KDE apps can show correctly themed file views but still keep a light or Breeze-colored toolbar, sidebar, or header area.
**Cause:** Kirigami chrome follows KDE color infrastructure, not just `QPalette`, on a Hyprland session without Plasma.
**Status:** Workaround in place
**Resolution:** The Qt target uses the full `qt6ct`/`qt5ct` + `kdeglobals`/`current.colors` + Kvantum + `hyprqt6engine` chain; `qt6ct + Fusion` or `hyprqt6engine` alone were only partial fixes.

## NixOS needs both hyprqt6engine's root and the standard Qt plugin roots
**Symptom:** Qt/KDE apps can inherit the generated palette but still miss Kvantum styling or fall back to partially unthemed widgets, especially in D-Bus/systemd-activated processes such as `xdg-desktop-portal-kde`.
**Cause:** `hyprqt6engine` installs under `lib/qt-6/`, not the normal `/lib/qt-*/plugins` tree. Pointing `QT_PLUGIN_PATH` only at hyprqt6engine exposes the platform theme itself but hides profile-installed style/platform plugins such as Kvantum and qtct, while a global `QT_STYLE_OVERRIDE` magnifies the fallback path.
**Status:** Workaround in place
**Resolution:** The shared system baseline now enables NixOS `qt.enable`, exports `QT_QPA_PLATFORMTHEME=hyprqt6engine`, keeps hyprqt6engine's root on `QT_PLUGIN_PATH`, installs qtct/Kvantum packages system-wide, and lets the generated qtct/hyprqt6engine configs choose the style instead of exporting a global `QT_STYLE_OVERRIDE`.

## hyprqt6engine needs the KDE `.colors` file for KDE color consumers
**Symptom:** KDE apps can use the generated foreground colors while some KDE-owned surfaces, such as Dolphin's alternating file-view rows or symbolic icon recoloring, still fall back to light/default colors.
**Cause:** `hyprqt6engine` can load qtct `current.conf` into `QPalette`, but it only sets the `KDE_COLOR_SCHEME_PATH` application property when `theme:color_scheme` points at a `.colors` file. KDE widgets and helpers that call into `KColorScheme` need that path, not just the plain Qt palette.
**Status:** Workaround in place
**Resolution:** `desktopctl/src/theme/targets/qt.rs` writes both the qtct palette and the KDE `current.colors` file, but `~/.config/hypr/hyprqt6engine.conf` now points `color_scheme` at `~/.local/share/color-schemes/current.colors` so KDE color consumers share the same generated scheme.

## Non-KDE icon themes need KDE color metadata and Breeze fallback ordering
**Symptom:** KDE toolbar/sidebar icons can stay black on dark schemes even while the selected file/folder icon theme is active.
**Cause:** KIconThemes recolors SVG icons only when the current icon theme declares `FollowsColorScheme=true`, and the upstream Neuwaita index inherits fixed-color Adwaita/hicolor assets before Breeze. Patching the shared `Neuwaita` theme directly fixes KDE but also changes GTK apps such as Nautilus, because GTK then sees Breeze's thinner symbolic sidebar icons before Adwaita's.
**Status:** Workaround in place
**Resolution:** `home/gtk.nix` keeps the upstream `Neuwaita` theme unchanged for GTK and also installs `Neuwaita-KDE`, a wrapper whose `index.theme` inherits `Neuwaita,breeze,Adwaita,hicolor` and declares `FollowsColorScheme=true`. `desktopctl/src/theme/targets/qt.rs` maps the shared `Neuwaita` state value to `Neuwaita-KDE` only for KDE/Qt config.

## Quickshell has generated-theme fallbacks before first sync
**Symptom:** On a fresh clone before `desktopctl theme sync` has run, Quickshell starts from hardcoded Gruvbox-style colors instead of a generated theme file.
**Cause:** `config/quickshell/GeneratedTheme.json` is no longer committed. Home Manager deploys `config/quickshell/` recursively, and the `quickshell` theme target creates the live `${XDG_CONFIG_HOME:-~/.config}/quickshell/GeneratedTheme.json` file during activation or runtime theme applies.
**Status:** Current behavior
**Resolution:** Keep generated snapshots out of the repo. `config/quickshell/Theme.qml` owns the first-start fallback values, and theme changes still flow through `desktopctl theme`.

## VS Code color-theme switches depend on exact settings labels and enabled extensions
**Symptom:** `desktopctl theme apply` updates `~/.config/Code/User/settings.json`, but VS Code still starts on a fallback built-in theme.
**Cause:** VS Code caches the last resolved theme in `~/.config/Code/User/globalStorage/state.vscdb` `ItemTable` under `colorThemeData`, but the workbench only reuses that cache when its stored `settingsId` still matches the current `workbench.colorTheme` setting. If the configured label does not exactly match an installed theme contribution, or the contributing extension is disabled, VS Code falls back during startup instead of honoring the requested scheme.
**Status:** Current behavior
**Resolution:** Keep `themes/colors/*.json` `app_themes.vscode.name` values aligned with the extension-contributed labels, and set `app_themes.vscode.extension_id` whenever `desktopctl` needs to auto-enable a disabled theme extension. `desktopctl` does not need to own `colorThemeData` itself.

## VS Code integrated terminal prefers the mono Nerd Font subfamily
**Symptom:** Some Nerd Font prompt glyphs show up as empty boxes in VS Code's integrated terminal even though the same prompt renders correctly in standalone terminals.
**Cause:** Electron resolves `terminal.integrated.fontFamily` through a CSS font-family stack, and some patched Nerd Font families expose a terminal-safe `... Nerd Font Mono` face separately from the broader `... Nerd Font` family.
**Status:** Workaround in place
**Resolution:** Generate `terminal.integrated.fontFamily` with the mono subfamily first for Nerd Fonts, then fall back to the selected mono font and generic `monospace`. If you override the setting manually, keep the `... Nerd Font Mono` face first.

## Kvantum SVG assets cap exact background matching
**Symptom:** Some KDE surfaces stay slightly off from the active background color even after the generated Kvantum config applies.
**Cause:** The reused KvGnome and KvGnomeDark SVGs have baked background shades that the generated kvconfig cannot fully override.
**Status:** Open
**Resolution:** The Qt target regenerates the color config and swaps the dark/light SVGs, but exact background matching would require custom SVG assets.

## Chromium web-font prefs are profile-local, web-content-only, and not live-reloaded
**Symptom:** Chromium web-font changes can appear to do nothing until the browser restarts, browser chrome keeps matching GTK instead of the theme-managed web fonts, and inactive Chromium profiles keep their old font settings.
**Cause:** The `chromium` target patches each active profile's `~/.config/chromium/<profile>/Preferences` `webkit.webprefs.fonts` entries based on `Local State` `profile.last_active_profiles`, falling back to `Default` when that list is unavailable. The target also removes any previously managed `default_font_size` and `default_fixed_font_size` prefs so Chromium falls back to its own default page sizes. Chromium's own chrome continues to use the toolkit font settings from GTK, Chromium keeps one prefs file per profile, and a live browser session may rewrite an active profile's file on exit.
**Status:** Current behavior
**Resolution:** Treat the target as owning active profiles' web-font family prefs only. Chromium page sizes are no longer theme-managed, so website page text stays on Chromium defaults while browser chrome still follows GTK. Rerun `desktopctl theme target chromium` after closing Chromium if a live session overwrote the managed font families. Open an inactive profile once and rerun the target if you want that profile updated too.
