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
**Symptom:** KDE toolbar/sidebar icons can stay black on dark schemes even while the selected file/folder icon theme is active, or Dolphin's default blue folders can fall back to oversized Breeze assets instead of Neuwaita's scalable folder.
**Cause:** KIconThemes recolors SVG icons only when the current icon theme declares `FollowsColorScheme=true`, and the upstream Neuwaita index inherits fixed-color Adwaita/hicolor assets before Breeze. Patching the shared `Neuwaita` theme directly fixes KDE but also changes GTK apps such as Nautilus, because GTK then sees Breeze's thinner symbolic sidebar icons before Adwaita's. KDE also asks for names such as `folder-blue` for its default folder color, but upstream Neuwaita only ships `folder`, so KDE falls through to Breeze unless the wrapper supplies that alias.
**Status:** Workaround in place
**Resolution:** `home/gtk.nix` keeps the upstream `Neuwaita` theme's inheritance unchanged for GTK and also installs `Neuwaita-KDE`, a wrapper whose `index.theme` inherits `Neuwaita,breeze,Adwaita,hicolor` and declares `FollowsColorScheme=true`. Both installed themes get scalable aliases for `folder-blue`, `folder-downloads`, `folder-desktop`, `folder-home`, and `inode-directory`. `desktopctl/src/theme/targets/qt.rs` maps the shared `Neuwaita` state value to `Neuwaita-KDE` only for KDE/Qt config.

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

## The SDDM staging directory is pre-created by systemd-tmpfiles
**Symptom:** `/tmp/desktopctl-where-is-my-sddm-theme` already exists, owned `0700 kevin:kevin`, before any theme apply has run.
**Cause:** The root-run `desktopctl-sddm-theme-sync` service copies whatever the staging path points at into `/var/lib/desktopctl`. If an arbitrary local user could pre-create the directory in world-writable `/tmp`, they could symlink-feed the root-run copy. `system/services.nix` therefore pre-creates the directory at boot via a systemd-tmpfiles `d` rule owned by the theme-writing user, making the target's own `create_dir_all` a no-op.
**Status:** Hardening in place
**Resolution:** Keep the tmpfiles rule in `system/services.nix` in sync with the staging path in `desktopctl/src/theme/targets/where_is_my_sddm_theme.rs`; do not relax the `0700` mode.

## bat themes use exact bundled names where they exist
**Symptom:** Most schemes set `app_themes.bat` to a real bat theme name, but a few say `base16` and render with generic ANSI colors.
**Cause:** bat only bundles certain themes. The catalog policy is: declare the exact bundled bat theme when one exists (for example nord uses `Nord`, the Catppuccin variants use their bundled names); `base16` remains only for schemes bat does not bundle (rose-pine, rose-pine-dawn, tokyo-night, tokyo-night-light, nord-light), verified against `bat --list-themes`.
**Status:** Current behavior
**Resolution:** When bumping bat, re-check `bat --list-themes` before adding or renaming `app_themes.bat` values.

## KTextEditor theme names are declared only where KDE bundles them
**Symptom:** Kate/KWrite follow the scheme on most themes but fall back to Breeze Dark/Light on rose-pine, rose-pine-dawn, and nord-light.
**Cause:** `app_themes.ktexteditor` is declared on 11 of 14 schemes with exact bundled KTextEditor theme names (Catppuccin Frappé/Latte/Macchiato/Mocha, gruvbox Dark/Light, Nord, Solarized Dark/Light, Tokyo Night, Tokyo Night Light), verified against `ksyntaxhighlighter6 --list-themes`; the other three have no bundled match and intentionally fall back to Breeze.
**Status:** Current behavior
**Resolution:** Only declare `ktexteditor` names that the installed KDE frameworks actually bundle. (Related catalog fix: catppuccin-frappe's `snappy_switcher` mapping now points at the real `catppuccin-frappe.ini` shipped by snappy-switcher.)

## Palette data follows upstream semantics, not monotonic muting
**Symptom:** Consumers that assume `fg > fg2 > fg3 > fg4` brightness ordering or distinct `fg4`/`bg3` values misrender on some schemes.
**Cause:** `fg4 == bg3` in nord, solarized-dark, and solarized-light is intentional upstream comment-tier semantics (fg4-on-bg3 text is invisible by design), and on nord/solarized-dark `fg2` is brighter than `fg` ("emphasized" semantics). Past data bugs in this area are fixed: the solarized bright-magenta/bright-cyan palette transposition, nord's unusably dark `fg3` (now `#7b88a1`, ~3.5:1 on bg, which zsh autosuggestions use), nord-light's `palette[8]`, and tokyo-night-light's ANSI palette alignment.
**Status:** Current behavior
**Resolution:** Targets must select tiers by contrast against `bg` (as `zsh.rs` does) instead of assuming monotonic muting or unique tier values.

## Chromium-family prefs are profile-local and not live-reloaded
**Symptom:** Chromium or Helium font and browser chrome changes can appear to do nothing until the browser restarts, and inactive profiles keep their old settings.
**Cause:** The `chromium` and `helium` targets patch each active profile's `Preferences` file based on `Local State` `profile.last_active_profiles`, falling back to `Default` when that list is unavailable. They set `webkit.webprefs.fonts` plus `browser.theme.color_scheme2` from `dark_hint`, remove Chrome color-picker keys such as `user_color2` / `color_variant2`, and remove any previously managed `default_font_size` and `default_fixed_font_size` prefs so page text stays on browser defaults. Chromium-family browsers keep one prefs file per profile, and a live browser session may rewrite an active profile's file on exit.
**Status:** Current behavior
**Resolution:** Treat these targets as owning active profiles' web-font family prefs and browser chrome light/dark preference. Page sizes are no longer theme-managed, so website page text stays on browser defaults. Rerun `desktopctl theme target chromium` or `desktopctl theme target helium` after closing the browser if a live session overwrote the managed prefs. Open an inactive profile once and rerun the target if you want that profile updated too.
