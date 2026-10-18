# Theming

## Intent

- Mutable theme state lives in `desktopctl.db` (`theme_state`,
  `theme_presets`); versioned data lives in `styling/`: scheme catalog, concat
  bases, and `state.json`. Generated outputs carry only theming data, are never
  committed, and never overwrite base config.
- `styling/state.json` is the *only* source of defaults — no compiled
  fallback — so a fresh machine renders what is under review. `theme export`
  prints state back in that format, minus the machine-local wallpaper path.
  Older persisted rows are backfilled from it before validation.
- Each target declares one assembly strategy (`standalone`, `concat`, `hooks`)
  and the `ThemeState` keys it consumes; fanout derives from those keys, never
  from hand-kept lists. Only exception: `wallpaper` leaves `color_scheme`
  fanout when `filter_wallpaper` is false.
- Presets are partial patches and runtime state, never in `styling/`. A
  mutation that changes `color_scheme` keeps `dark_hint` unless it sets it.
- `appearance` is the canonical polarity; variant strings are never
  pattern-matched. App theme names and extension IDs live in scheme data
  (`app_themes`) and every scheme declares them all (only `ktexteditor` and
  `vscode.icon_theme` fall back), so a missing one fails at load. Same-family
  light/dark pairing goes through `scheme_pair.rs`: explicit `dark_scheme`
  first, then variant ranking.
- All mutations go through the daemon's theme queue ([[desktopctl]]): atomic
  file replacement, persistence only after the required applies succeed,
  upserts of only the changed keys in one transaction.
- A manual `dark_hint` write also upserts `dark_hint_manual_at` in the same
  transaction; it gates the scheduler's catch-up ([[sun-schedule]]). A preset
  carrying `dark_hint` counts as manual.
- `theme sync` is the activation-safe subset (no reload hooks).
- A palette target for one consumer (`quickshell`, `hyprland`, `neovim`)
  emits only the keys that consumer reads; reading a new key means adding it
  to the target in the same change.
- The dimmed foreground ramp is derived by `dim_ramp()`; schemes never author
  it — upstream palettes made secondary text brighter than primary on nord and
  solarized. Never pair fg tiers against bg tiers for a guaranteed gap; the
  ramps are independent.
- The Kvantum theme, SVG included, is generated whole: borrowed SVG pins shape
  and colour to someone else's palette. Its visual language: flat fills,
  hairline borders, one radius per widget class, accent only for selection,
  focus and progress.
- Starship keeps gruvbox's powerline *order* with each role resolved from the
  active scheme. The identity plate picks itself against the path plate's
  yellow, because warm hues collide (rose-pine's orange *is* its yellow).
- Text on an accent fill comes from `color::readable_on`, never `fg`, which
  drops light schemes to ~1.6:1.

## Quirks

### No single Qt channel themes every app
Each of these was isolated by changing it alone; none is redundant.
- `QT_STYLE_OVERRIDE=kvantum` (`qt.style`): without it kcharselect renders
  unstyled. Breeze is not an installed style plugin, hence also
  `[KDE] widgetStyle`.
- Kvantum `[GeneralColors]` supplies `QPalette`; qt6ct's `custom_palette`
  never reaches these apps.
- qt6ct supplies fonts to non-KDE Qt apps only. A KDE app's UI font follows
  the fontconfig `sans-serif` alias and nothing else.
- Qt reads the palette once at startup, so verify against a *fresh* process
  (`qml` with a `SystemPalette`). hyprpolkitagent is resident, hence the `qt`
  target restarting it.
- `KDE_COLOR_SCHEME_PATH` changes no measured role; don't treat it as
  load-bearing.

### Dolphin's alternate row colour is unreachable
It is a compiled default in `KItemListView`. Every kdeglobals, colour-scheme,
Kvantum, qt6ct and platform-theme channel was probed with magenta and none
moved it. Needs upstream; do not re-run the search.

### Neuwaita needs a KDE wrapper theme for symbolic recoloring
KIconThemes recolors only themes with `FollowsColorScheme=true`, and patching
Neuwaita itself would leak Breeze icons into GTK. `pkgs/neuwaita` ships both,
and the `qt` target maps `Neuwaita` to `Neuwaita-KDE` for KDE only.

### App theme names exist only where the app bundles them
bat names are exact bundled names (`base16` otherwise); `ktexteditor` names
were checked against `ksyntaxhighlighter6 --list-themes`. Re-check the bundled
lists on bumps before calling a fallback a bug.

### VS Code and Zed need exact labels and installed extensions
VS Code reuses its cached theme only when the label matches
`workbench.colorTheme`; a mismatch or disabled extension silently falls back.
Zed's theme extensions are installed once by hand (`nord-light` → `One Light`).
The terminal needs the `... Nerd Font Mono` family first or glyphs are boxes.

### Vicinae needs both appearance slots and a full restart
`vicinae theme set` exits 0 but persists to the store-owned `settings.json`,
and the server never re-reads imports — only a restart applies. Both slots get
the *selected* scheme because vicinae's own light/dark reading disagrees with
everything else. Its custom themes in `~/.local/share/vicinae/themes/`
override packaged ones of the same ID.

### Chromium-family prefs are not live; dark mode rides the portal
A running browser never re-reads `Preferences` and writes its in-memory copy
back over ours, so a per-hint `color_scheme2` was silently reverted. It is
pinned to "Device" (0) and polarity reaches the browser live via the portal's
`color-scheme`, i.e. the gtk target's dconf write. Fonts still need a restart;
only active profiles are patched.

### The SDDM wallpaper handoff is a hardened two-stage bridge
SDDM can't read the 0700 home, so the target stages into a tmpfiles-created
`0700 kevin` dir under `/tmp` and a root unit moves it to `/var/lib`. Keep the
tmpfiles rule in sync with the staging path and never relax its mode.

### Claude Code's `auto` theme does not follow a scheme switch
It re-checks only on a terminal colour notification Alacritty never sends. The
`claude_code` target writes `~/.claude/themes/desktopctl.json`, which running
sessions re-render from — only while settings select `"custom:desktopctl"`.

### T3 Code shows the published palette only while it is selected
The `t3code` target publishes `desktopctl` into `~/.t3/userdata/themes/`,
which the server watches and streams to clients live, but nothing retints
until that id is chosen in Settings or with `t3 theme set desktopctl`. A file
the server rejects is dropped with only a log warning in
`~/.t3/userdata/logs`, so validate output with `t3 theme set <file>
--base-dir <scratch>` rather than trusting a silent app.
