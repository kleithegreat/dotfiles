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
  theme, and a scheme change recolors running apps live. It also names the
  widget style, Union, which resolves its stylesheet against that palette on
  every paint; a style that substitutes or caches its own colours freezes apps
  at their startup ones (Kvantum did, and Breeze and its forks keep stale
  toolbars in plain Qt apps).
- `pkgs/union-style/controls.css` is the Qt look, over Breeze's rules: one
  surface, with windows, toolbars, content and the floating title bar in `bg`
  and only popups raised to `bg1`; fills carry shape, hairlines separate, and
  the accent carries meaning (default button, selection, checks, focus). A
  second chrome tone is what made it read as Breeze. It names no scheme colour,
  only roles and alphas over them. Radii scale from `hypr_rounding`, so one
  knob rounds windows and controls.
- GTK takes the scheme as libadwaita's named colours, and the one GTK theme,
  `desktopctl`, takes its adw-gtk3 base from the scheme's appearance. Its
  normal and dark variants are identical, because toolkits pick the variant
  from the portal's `color-scheme`. libadwaita reads that too, so
  `gtk-4.0/gtk.css` pins everything libadwaita varies by appearance to the
  scheme's own.
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
session-bus signals the `qt` target emits. `QT_STYLE_OVERRIDE` would outrank
the style kdeglobals names.

### A Union stylesheet that fails to load crashes every Qt app
One unresolvable `@import` drops all rules and the widgets dereference the
missing properties. The `qt` target therefore writes `tokens.css` before the
`kdeglobals` key that selects the style; recover by setting
`unionStyle=breeze` there. Radii need an app restart; colours do not.

### In Union CSS the first definition of a variable wins
A later `--x:` is parsed as a property and ignored, so an override placed after
Breeze's rules silently does nothing. Overrides of Breeze's variables belong
in `tokens.css`; `controls.css` can only add new ones or restate rules.

### A Union element's ancestors are the ones it had when polished
KDE widgets moved into a toolbar or painted without a widget do not match
ancestor selectors: Dolphin's path bar is `frame textfield` and its sidebar
rows are a bare `itemviewitem.inside-list`. `QT_LOGGING_RULES=union.query.info=true`
prints what each element matches as.

### Union needs three things a Plasma session gives it
`UNION_FORCE_PLATFORM=plasma`, or it ignores `unionStyle` and KDE icons;
`/share/union` in `pathsToLink`, or its property definitions are missing; and
no style cache, which compares mtimes that never change in the store, so a
rebuild would keep serving the old stylesheet.

### GTK colours need an app restart
GTK loads user CSS and theme files once, so a scheme change reaches GTK apps
only on relaunch.

### libhandy renames a `-dark` theme and follows the portal
A GTK3 app on libhandy (gedit, through tepl) strips `-dark` from
`gtk-theme-name` and sets the dark variant from the portal, i.e. `dark_hint`.
A `desktopctl-dark` theme beside a light `desktopctl` therefore drew gedit
with the light theme's chrome around a dark source view. The theme name must
carry no polarity.

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
and the `qt` target maps `Neuwaita` to `Neuwaita-KDE` for KDE only. The wrapper
carries Breeze's actions itself: KIconThemes tries a name's generic parts in
the current theme before any inherited one, so an inherited `application-menu`
came out as the `application-x-generic` document.

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

### The SDDM handoff is a hardened two-stage bridge
SDDM can't read the 0700 home, so `sddm.rs` stages both the wallpaper and
generated `theme.conf` (symlinked as `theme.conf.user`) into a tmpfiles-created
`0700 kevin` dir under `/tmp/desktopctl-sddm` and a root unit moves them to
`/var/lib/desktopctl/sddm`. Keep the tmpfiles rule in sync with the staging
path and never relax its mode.

### SDDM themes must be in `environment.systemPackages`, not `sddm.extraPackages`
`services.displayManager.sddm.extraPackages` extends only the greeter's Qt/QML
plugin search paths, while SDDM resolves themes from
`/run/current-system/sw/share/sddm/themes`. Dropping the theme package from
`systemPackages` leaves the greeter falling back to stock SDDM themes.

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
