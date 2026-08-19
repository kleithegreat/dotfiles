# Theming

## Intent

- One mutable theme state (the `theme_state` table in `desktopctl.db`), a
  version-controlled scheme catalog (`styling/colors/*.json`) and preset
  patches (`styling/presets/*.json`), and bounded write surfaces. Generated
  outputs contain only theming data; base config is never overwritten.
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

### Kirigami ignores a plain Qt palette outside Plasma
KDE chrome (toolbars, sidebars) follows KDE color infrastructure, not
`QPalette`. The `qt` target therefore writes the whole chain: qt6ct/qt5ct +
`kdeglobals`/`current.colors` + Kvantum + hyprqt6engine. Partial subsets were
tried and looked half-themed. hyprqt6engine only sets
`KDE_COLOR_SCHEME_PATH` when its config points `color_scheme` at a `.colors`
file, which is why `hyprqt6engine.conf` points at the generated
`~/.local/share/color-schemes/current.colors`. See [[nix]] for the plugin-path
side of Qt theming.

### Kvantum SVG assets cap exact background matching
KvGnome/KvGnomeDark SVGs have baked background shades the generated kvconfig
cannot fully override; some KDE surfaces stay slightly off. Exact matching
would need custom SVG assets.

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
