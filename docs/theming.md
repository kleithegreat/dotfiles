# Theming

## Intent

- One mutable theme state (the `theme_state` table in `desktopctl.db`) over
  version-controlled data in `styling/`: the scheme catalog (`colors/*.json`),
  preset patches (`presets/*.json`), concat bases (`bases/*`) and the default
  state (`state.json`). Generated outputs contain only theming data; base
  config is never overwritten.
- `styling/state.json` is the *only* source of defaults — there is no compiled
  fallback, so the desktop a fresh machine renders is the one under review in
  git rather than whatever the local database drifted to. `theme export`
  prints the current state back in that format for commit; it emits the known
  schema fields only, minus the two machine-local wallpaper paths, which stay
  derived because the wallpaper library is gitignored. A `ThemeState` field
  added without a seed value fails `seed_covers_exactly_the_non_machine_local_fields`.
- Every target declares one assembly strategy — `import`, `concat`,
  `standalone`, or `command` — plus the `ThemeState` keys it consumes.
  Fanout for `theme colors`/`theme fonts`/per-key applies derives from those
  declared `state_keys`, never from hand-maintained target lists. The one
  exception: `wallpaper` is dropped from `color_scheme` fanout when
  `filter_wallpaper` is false.
- Presets are partial patches, not full-state snapshots. Any mutation that
  changes `color_scheme` preserves the current `dark_hint` unless the same
  mutation sets it explicitly.
- `appearance` on the scheme is the canonical dark/light polarity; variant
  strings are not binary and must not be pattern-matched. App-specific theme
  names and extension IDs live in scheme data (`app_themes`), never in
  target-local match arms. Same-family light/dark resolution is shared through
  one resolver (`scheme_pair.rs`, used by `qt`, `gtksourceview`, `vicinae`):
  explicit `dark_scheme` pairing wins, then variant-preference ranking.
- All theme mutations route through the daemon's theme controller, which
  serializes them on one queue without holding a lock across a multi-second
  apply; the CLI is a strict socket client ([[desktopctl]]). Writes are
  atomic replacements; state persists only after the required target apply
  succeeds; mutations upsert only the changed keys in one transaction. Older
  persisted rows are backfilled from compiled defaults before validation.
- `dark_hint` persistence always flows through the theming pipeline, even when
  the daemon's schedule decides the value; a manual write additionally upserts
  `dark_hint_manual_at` in the same transaction, which gates the scheduler's
  boot catch-up ([[sun-schedule]]). A preset carrying `dark_hint` applies in
  the same single pass as its other keys and counts as a manual write.
- `theme sync` is the activation-safe subset (no runtime reload hooks);
  Home Manager activation runs it so generated fragments exist before the
  first session. No generated output is ever committed to the repo.
- The dimmed foreground ramp (`fg2`/`fg3`/`fg4`/`fg_faint`) is derived by
  `dim_ramp()` blending `fg` toward `bg` at rising fractions; scheme files
  must not author it.
- The Kvantum theme is generated whole — `kvantum.rs` emits the SVG as well as
  the kvconfig. Kvantum draws every widget surface from SVG elements, so
  borrowing another theme's SVG pins shape *and* most colour to whatever
  palette it was drawn in; only text could follow the scheme. Generating both
  is what makes an arbitrary scheme reach the pixels, and it is also where the
  visual language lives: flat fills, hairline borders, one radius per widget
  class, and accent reserved for selection, focus and progress. No Kvantum
  theme is searched for on disk, and nothing scans the store for one.
- Label colours that land on an accent fill — selected text, a toggled
  button, a checkbox tick — come from `color_utils::readable_on`, never from
  `fg`: pairing the scheme's body grey with its own accent drops light schemes
  to about 1.6:1. It prefers the scheme's own ends and falls back to
  black/white when neither clears WCAG AA, because some accents clear it
  against neither.

## Quirks

### The fg ramp is derived because upstream palettes lie
Transcribed `fg2`/`fg3` values made secondary text *brighter* than primary on
nord and solarized (solarized's `base1` is emphasized text; `nord5` outranks
`nord4`), and `fg4 == bg3` collapsed workspace-pill contrast on several
schemes. Derivation makes the inversion unrepresentable and tests in
`schema.rs` enforce ordering plus a pill-contrast floor. Remaining rule: never
pair foreground tiers against *background* tiers when a guaranteed gap is
needed — the ramps are independent, and solarized-light's `bg3` sits exactly
on its `fg`→`bg` line.

### No single Qt channel themes every app
Theming is split across `system/qt.nix` (the env vars) and the `qt` target
(every config file). Each piece below was isolated by changing it alone and
relaunching; do not drop one because it looks redundant.

- `QT_STYLE_OVERRIDE=kvantum`, from `qt.style`. With `QT_QPA_PLATFORMTHEME=qt6ct`
  alone, Dolphin picked up Kvantum but kcharselect did not and rendered
  unstyled; adding this styled both. Breeze is not installed as a Qt style
  plugin here (`.../qt-6/plugins/styles` holds only `libkvantum.so` and
  `libqt6ct-style.so`), so an app that resolves a style by name and misses
  falls through to Qt's default. Dolphin and kcharselect both link
  `KStyleManager::initStyle`, and `libKF6ConfigWidgets` carries the
  `widgetStyle` key it reads — hence the `[KDE] widgetStyle` the target also
  writes, which on its own was enough to style Dolphin.
- Kvantum's `[GeneralColors]` supplies `QPalette`. Setting `base.color` to
  magenta turned Dolphin's view magenta *while* qt6ct's `Base` was set to a
  different colour, and deleting the section dropped the view to white rather
  than to qt6ct's value — so qt6ct's `custom_palette` does not reach these
  apps at all.
- qt6ct supplies fonts to non-KDE Qt apps: `[Fonts] general` visibly changed
  qt6ct's own window and did nothing in kcharselect. Its `icon_theme` was not
  isolated; KDE apps take icons from `kdeglobals [Icons] Theme`, which works.
- The fontconfig generic families are the only channel that reaches a KDE
  app's UI font. `kdeglobals [General] font` and qt6ct `[Fonts] general` both
  left kcharselect on the default; aliasing `sans-serif` changed it. Only the
  `sans-serif` half was measured.

`hyprqt6engine` used to hold the platform-theme slot and was inert: raising
its `font_size` and changing its `icon_theme` altered nothing, and qt6ct's own
window rendered unstyled under it and themed under qt6ct. That is what left
most Qt apps unthemed.

`KDE_COLOR_SCHEME_PATH` (set in `system/qt.nix`) is the only consumer of the
generated `~/.local/share/color-schemes/current.colors`; the variable name
appears in `libKF6ColorScheme`. No role was found that visibly changes with
it — do not treat it as load-bearing without measuring first.

### Dolphin's alternate row colour is unreachable — stop trying to theme it
Dolphin's details view paints every other row a fixed near-white, sampled as
`#f9f9f9` and `#f7f7f7` on solarized-light. Neither value comes from the
scheme. The *normal* row does follow it (that one is Kvantum's `base.color`),
so only the alternate is stranded.

Each channel below was probed on its own and the app relaunched — the colour
ones set to a loud magenta, the rest simply switched on. None moved it:

- `kdeglobals [Colors:View] BackgroundAlternate`
- `~/.local/share/color-schemes/<name>.colors` installed under a name matching
  `kdeglobals [General] ColorScheme`, with `KDE_COLOR_SCHEME_PATH` pointing at
  it
- Kvantum `[GeneralColors] alt.base.color`
- the qt6ct colour scheme's `AlternateBase` slot — moot in hindsight, since
  the quirk above shows none of that palette reaches these apps
- `[KDE] contrast` (`0` as well as `4`, in case the colour was shaded rather
  than read)
- `kdePackages.plasma-integration` with `QT_QPA_PLATFORMTHEME=kde`, i.e. KDE's
  own platform theme rather than qt6ct
- Kvantum `[Hacks] transparent_dolphin_view=true`

`kdeglobals [Colors:View] ForegroundNormal` set to magenta also left the file
names their normal colour, so KDE's colour infrastructure is not reading our
config in these apps at all — the alternate row keeps a compiled default.
Dolphin's `KItemListView`/`KItemListWidget` own the painting and ship no
config key for it (nothing in `share/config.kcfg/*.kcfg` matches `alternat`),
which is why no amount of scheme data reaches it. This needs an upstream fix;
do not re-run the search.

### Neuwaita needs a KDE wrapper theme for symbolic recoloring
KIconThemes only recolors SVGs when the icon theme declares
`FollowsColorScheme=true`, and upstream Neuwaita inherits fixed-color
Adwaita/hicolor before Breeze, so KDE action icons stay black on dark schemes.
Patching Neuwaita itself would leak Breeze's thinner symbolic icons into GTK
apps. the repo-local `pkgs/neuwaita` package ships the untouched `Neuwaita` for
GTK plus a derived
`Neuwaita-KDE` wrapper (`FollowsColorScheme=true`,
`Inherits=Neuwaita,breeze,Adwaita,hicolor`), both with aliases for KDE folder
names upstream lacks (`folder-blue` etc.); the `qt` target maps the shared
`Neuwaita` state value to the wrapper for KDE only.

### App theme names are declared only where the app bundles them
`app_themes.bat` uses exact bundled bat theme names, with `base16` only for
schemes bat does not bundle; `app_themes.ktexteditor` is declared on 11/14
schemes with names verified against `ksyntaxhighlighter6 --list-themes`, the
rest intentionally fall back to Breeze. When bumping bat or KDE frameworks,
re-check the bundled lists before assuming a fallback is a bug.

### VS Code theme switching depends on exact labels and enabled extensions
VS Code caches the resolved theme in `state.vscdb` and only reuses it when the
stored `settingsId` matches `workbench.colorTheme`; a label mismatch or a
disabled contributing extension silently falls back to a built-in theme. Keep
`app_themes.vscode.name` aligned with extension-contributed labels and set
`extension_id` where auto-enabling is needed. Zed similarly needs its theme
extensions installed once; `nord-light` intentionally maps to built-in
`One Light`. The VS Code integrated terminal needs the `... Nerd Font Mono`
subfamily listed first or prompt glyphs render as boxes.

### Chromium-family prefs are profile-local and not live-reloaded
The `chromium` and `helium` targets patch each *active* profile's
`Preferences` (from `Local State` `last_active_profiles`, falling back to
`Default`): web-font families and `browser.theme.color_scheme2` from
`dark_hint`. A live browser can rewrite the file on exit — rerun the target
after closing the browser if changes vanished, and open an inactive profile
once to get it patched.

### The SDDM wallpaper handoff is a hardened two-stage bridge
SDDM cannot read the 0700 home directory, so the
`where_is_my_sddm_theme` target stages the wallpaper at
`/tmp/desktopctl-where-is-my-sddm-theme/background` and a root-run unit in
`system/services.nix` moves it to `/var/lib/desktopctl/...` where the greeter
reads it. The staging dir is pre-created at boot by systemd-tmpfiles as
`0700 kevin:kevin` so no other local user can symlink-feed the root-run copy —
keep the tmpfiles rule in sync with the target's staging path and do not relax
the mode. The sync service *consumes* (deletes) the staged file; see the
`PathExists` quirk in [[nix]].

Related: [[desktopctl]], [[tools]], [[quickshell]], [[hyprland]], [[nix]], [[sun-schedule]]
