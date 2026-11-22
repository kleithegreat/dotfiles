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
  from hand-kept lists. Only exception: `wallpaper` and `where_is_my_sddm_theme`
  leave `color_scheme` fanout when `filter_wallpaper` is false.
- Presets are partial patches and runtime state, never in `styling/`. A
  mutation that changes `color_scheme` keeps `dark_hint` unless it sets it.
- `dark_hint` is the browser's polarity and nothing else: a light Helium over
  gruvbox-dark is a look the owner wants, not a mismatch. It reaches Helium
  as the portal's `color-scheme`. Every toolkit and app draws `color_scheme`
  as selected, never its light/dark pair.
- `appearance` is the canonical polarity; variant strings are never
  pattern-matched. App theme names and extension IDs live in scheme data
  (`app_themes`) and every scheme declares them all (only `ktexteditor` and
  `vscode.icon_theme` fall back), so a missing one fails at load.
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
- Schemes never author the 16 ANSI colours either; they are laid out by role
  from the named colours. Upstream terminal ports are not role-faithful:
  solarized's puts the background in bright black, which blanked htop's
  meter text. Bright black is `comment`, copied from each upstream's own
  style guide, not floored for contrast, so solarized and tokyo-night sit
  near 2.5:1 by design.
- Every Qt app reads one input, `kdeglobals`, through KDE's own platform
  theme, and a scheme change recolors running apps live. The widget style is
  Breeze because it draws with that palette; a style that substitutes its own
  (Kvantum did) freezes apps at their startup colours.
- GTK takes the scheme as libadwaita's named colours, and the GTK3 theme
  (`desktopctl` or `desktopctl-dark`) follows the scheme's appearance.
  libadwaita also reads the portal's `color-scheme`, so `gtk-4.0/gtk.css`
  pins everything libadwaita varies by appearance to the scheme's own.
- Starship keeps gruvbox's powerline *order* with each role resolved from the
  active scheme. The identity plate picks itself against the path plate's
  yellow, because warm hues collide (rose-pine's orange *is* its yellow).
- Text on an accent fill comes from `color::readable_on`, never `fg`, which
  drops light schemes to ~1.6:1.

## Quirks

### KDE apps paint Breeze over any other platform theme
Under any platform theme but `kde`, `KColorSchemeManager` (KColorScheme)
installs its built-in Breeze Light/Dark palette over the app. That is why
qt6ct + Kvantum left Dolphin's alternate rows Breeze's `247,247,247` and made
every kdeglobals probe look dead, a search that once concluded "needs
upstream". Swapping the platform theme away from `kde` brings it all back.
Running apps re-read kdeglobals only on the `notifyChange`/`refreshFonts`
session-bus signals the `qt` target emits.

### GTK colours need an app restart
GTK loads user CSS and theme files once, so a scheme change reaches GTK apps
only on relaunch.

### libadwaita leaks the browser's polarity through any colour gtk.css omits
Its stylesheet changes a set of named colours and `:root` variables under
`@media (prefers-color-scheme: dark)`, and that query follows the portal,
i.e. `dark_hint`. A user `@define-color` outranks both branches, so
`appearance_colors` in `gtk.rs` restates every one of them. After a libadwaita
bump, list the `@media` blocks in its `gtk.css` resource and diff them against
that list; a headless check renders both polarities with
`ADW_DEBUG_COLOR_SCHEME=prefer-light` / `prefer-dark`.

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
