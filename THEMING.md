# Theming System Architecture

Reference document for Claude Code agents implementing the hot-swap theming system.
Read this file before starting any theming-related task.

## Table of Contents

- [Overview](#overview)
- [Principles](#principles)
- [Directory Layout](#directory-layout)
- [Schemas](#schemas)
- [Assembly Strategies](#assembly-strategies)
- [Target Contract](#target-contract)
- [Target Registry](#target-registry)
- [Orchestrator](#orchestrator)
- [Home-Manager Migration](#home-manager-migration)
- [Quickshell Integration](#quickshell-integration)
- [KDE App Theming on Hyprland](#kde-app-theming-on-hyprland)
- [Testing](#testing)
- [Implementation Plan](#implementation-plan)

---

## Overview

This system hot-swaps colors, fonts, wallpaper, icons, and cursors across every
visible application on a Hyprland/NixOS desktop — without logging out, without
`nixos-rebuild`, and without touching non-theming configuration.

The flow:

```
User clicks button in Quickshell SettingsPopup
  → apply-theme <subcommand>            (Python CLI)
    → reads themes/state.json           (what to apply)
    → resolves themes/colors/<name>.json (color values)
    → runs each target's generate()     (pure function → string)
    → writes output via assembly strategy
    → fires reload commands
  → Quickshell re-reads GeneratedTheme.json
```

**Language:** Python 3. No shell scripts for generators. Stdlib only (json, tomllib,
dataclasses, pathlib, subprocess for reload commands). No pip dependencies.

**Location:** All theming code lives under `~/repos/dotfiles/themes/`.

---

## Principles

### 1. Generators must never write to files containing non-theming config

This is the single most important rule. A generator receives a `ColorScheme` and
`ThemeState` (both frozen dataclasses) and returns a string. It has no knowledge of
file paths. The orchestrator handles all file I/O.

### 2. Three assembly strategies — no exceptions

Every target uses exactly one of: **import**, **standalone**, or **command**.
See [Assembly Strategies](#assembly-strategies). If an app cannot use any of these,
we restructure its config until it can.

### 3. Frozen inputs, pure outputs

Generator functions are pure: `generate(colors: ColorScheme, state: ThemeState) -> str`.
No file reads, no file writes, no subprocess calls, no side effects. The frozen
dataclasses make mutation impossible.

### 4. Home-manager does not manage generated files

`xdg.configFile` creates read-only Nix store symlinks. These make hot-swapping
impossible. Every file that `apply-theme` generates must be removed from
home-manager's `xdg.configFile` declarations. Instead, a `home.activation` hook
runs `apply-theme all` on each rebuild for correctness.

### 5. Base configs are version-controlled, generated files are not

Files written by generators go in `.gitignore`. The base (non-theming) config files
remain version-controlled and managed by home-manager where applicable.

---

## Directory Layout

```
~/repos/dotfiles/
├── themes/
│   ├── apply-theme              # Entry point (#!/usr/bin/env python3)
│   ├── lib/
│   │   ├── __init__.py
│   │   ├── schema.py            # ColorScheme, ThemeState dataclasses
│   │   ├── resolve.py           # Load color JSON, merge with state
│   │   ├── orchestrator.py      # Run targets, handle assembly + reload
│   │   └── targets/
│   │       ├── __init__.py      # Target registry (auto-discovers modules)
│   │       ├── alacritty.py
│   │       ├── ghostty.py
│   │       ├── hyprland.py
│   │       ├── zathura.py
│   │       ├── quickshell.py
│   │       ├── neovim.py
│   │       ├── starship.py
│   │       ├── tmux.py
│   │       ├── gtk.py
│   │       ├── qt.py
│   │       ├── vicinae.py
│   │       ├── wallpaper.py
│   │       ├── cursor.py
│   │       └── bat.py
│   ├── colors/
│   │   ├── gruvbox-dark.json
│   │   ├── gruvbox-light.json
│   │   ├── solarized-dark.json
│   │   ├── solarized-light.json
│   │   ├── catppuccin-mocha.json
│   │   └── ...
│   ├── presets/
│   │   ├── gruvbox.json         # Bundles: color_scheme + wallpaper + fonts + icons
│   │   └── ...
│   └── state.json               # Current selections (mutable at runtime)
├── config/
│   ├── alacritty/
│   │   ├── alacritty.toml       # Base config (scrollback, padding, keybinds)
│   │   └── theme.toml           # GENERATED — .gitignore'd
│   ├── ghostty/
│   │   ├── base                 # Base config (non-theming settings)
│   │   └── config               # GENERATED (concat of base + theme) — not in repo
│   ├── hypr/
│   │   ├── colors.conf          # GENERATED — .gitignore'd (standalone)
│   │   ├── appearance-theme.conf # GENERATED — runtime appearance overrides
│   │   ├── hyprlock.conf        # Base config — sources colors via $theme_* vars
│   │   ├── pluginsettings.conf  # Base config — uses $theme_* vars from colors.conf
│   │   └── ...                  # Other hypr configs (unchanged)
│   ├── zathura/
│   │   ├── zathurarc            # Base config (behavioral settings)
│   │   └── colors               # GENERATED — .gitignore'd
│   ├── quickshell/
│   │   ├── Theme.qml            # Reads from GeneratedTheme.json
│   │   ├── GeneratedTheme.json  # GENERATED — .gitignore'd
│   │   └── ...
│   ├── starship/
│   │   └── base.toml            # Base config (format strings, module settings)
│   │   # GENERATED: ~/.config/starship.toml (concat of base + palette) — not in repo
│   ├── tmux/
│   │   ├── tmux.conf            # Base config (keybinds, options)
│   │   └── colors.conf          # GENERATED — .gitignore'd
│   ├── nvim/
│   │   └── lua/
│   │       └── theme-state.json # GENERATED — .gitignore'd
│   ├── bat/
│   │   └── theme                # GENERATED — single line with bat theme name
│   └── vicinae/
│       ├── base.json            # Providers config (non-theming)
│       └── settings.json        # GENERATED — merged from base + theming
└── ...
```

**Rule:** Every file marked `GENERATED` must appear in `.gitignore` and must NOT
appear in any `xdg.configFile` declaration in home-manager.

---

## Schemas

### ColorScheme (`themes/lib/schema.py`)

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class ColorScheme:
    """All color values are 7-character hex strings: '#rrggbb'."""

    family: str           # e.g. "gruvbox", "solarized", "catppuccin"
    variant: str          # "dark" or "light"

    # Backgrounds (darkest → lightest for dark themes, reversed for light)
    bg: str               # Primary background
    bg_dim: str           # Dimmer background (darker than bg for dark themes)
    bg1: str              # Surface / elevated background
    bg2: str              # Surface variant
    bg3: str              # Borders, subtle separators

    # Foregrounds (brightest → dimmest)
    fg: str               # Primary text
    fg2: str              # Secondary text
    fg3: str              # Tertiary / muted text
    fg4: str              # Placeholder / disabled text

    # Semantic colors
    red: str
    green: str
    yellow: str
    blue: str
    purple: str
    cyan: str
    orange: str

    # Accent (used for focused borders, selections, active indicators)
    accent: str

    # Bright variants (for terminal bold, highlights)
    red_bright: str
    green_bright: str
    yellow_bright: str
    blue_bright: str
    purple_bright: str
    cyan_bright: str
    orange_bright: str

    # 16-color terminal palette (indices 0-15)
    # Standard order: black, red, green, yellow, blue, magenta, cyan, white,
    #                 bright_black, bright_red, ..., bright_white
    palette: tuple[str, ...]  # Exactly 16 entries
```

### ThemeState (`themes/lib/schema.py`)

```python
@dataclass(frozen=True)
class ThemeState:
    color_scheme: str      # Key into themes/colors/ (e.g. "gruvbox-dark")
    wallpaper: str         # Absolute path (e.g. "/home/kevin/wallpapers/lmao.png")
    filter_wallpaper: bool # True = color-grade wallpaper to match active palette
    system_font: str       # e.g. "Overpass"
    mono_font: str         # e.g. "JetBrains Mono Nerd Font"
    icon_theme: str        # e.g. "Papirus-Dark"
    cursor_theme: str      # e.g. "Adwaita"
    cursor_size: int       # e.g. 24
    font_size: int         # System font size (e.g. 11)
    mono_font_size: int    # Terminal/editor font size (e.g. 11)
    alacritty_mono_font_size_offset: int
    ghostty_mono_font_size_offset: int
    gtk_mono_font_size_offset: int
    qt_mono_font_size_offset: int
    vscode_mono_font_size_offset: int
    dark_hint: bool        # True = prefer-dark, False = prefer-light
```

### Color JSON file (`themes/colors/<name>.json`)

```json
{
  "family": "gruvbox",
  "variant": "dark",
  "colors": {
    "bg":           "#282828",
    "bg_dim":       "#1d2021",
    "bg1":          "#3c3836",
    "bg2":          "#504945",
    "bg3":          "#665c54",
    "fg":           "#ebdbb2",
    "fg2":          "#d5c4a1",
    "fg3":          "#bdae93",
    "fg4":          "#a89984",
    "red":          "#cc241d",
    "green":        "#98971a",
    "yellow":       "#d79921",
    "blue":         "#458588",
    "purple":       "#b16286",
    "cyan":         "#689d6a",
    "orange":       "#d65d0e",
    "accent":       "#458588",
    "red_bright":   "#fb4934",
    "green_bright": "#b8bb26",
    "yellow_bright":"#fabd2f",
    "blue_bright":  "#83a598",
    "purple_bright":"#d3869b",
    "cyan_bright":  "#8ec07c",
    "orange_bright":"#fe8019"
  },
  "palette": [
    "#282828", "#cc241d", "#98971a", "#d79921",
    "#458588", "#b16286", "#689d6a", "#a89984",
    "#928374", "#fb4934", "#b8bb26", "#fabd2f",
    "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"
  ]
}
```

### State JSON (`themes/state.json`)

```json
{
  "color_scheme": "gruvbox-dark",
  "wallpaper": "/home/kevin/wallpapers/lmao.png",
  "filter_wallpaper": false,
  "system_font": "Overpass",
  "mono_font": "JetBrains Mono Nerd Font",
  "icon_theme": "Papirus-Dark",
  "cursor_theme": "Adwaita",
  "cursor_size": 24,
  "font_size": 11,
  "mono_font_size": 11,
  "alacritty_mono_font_size_offset": 0,
  "ghostty_mono_font_size_offset": 0,
  "gtk_mono_font_size_offset": 0,
  "qt_mono_font_size_offset": 0,
  "vscode_mono_font_size_offset": 0,
  "dark_hint": false
}
```

### Preset JSON (`themes/presets/<name>.json`)

A preset is a partial ThemeState. Only included keys are changed; omitted keys are
left at their current value. This lets you bundle "the gruvbox look" without
forcing a specific font.

```json
{
  "color_scheme": "gruvbox-dark",
  "wallpaper": "/home/kevin/wallpapers/gruvbox-forest.png",
  "icon_theme": "Papirus-Dark"
}
```

---

## Assembly Strategies

### Strategy: `import`

The app natively supports including a separate file. The base config (hand-maintained,
version-controlled) contains an import directive pointing to the generated file.
The generator writes **only** theming content to a separate file.

**Safety guarantee:** The generator's output file and the base config file are
different files. The orchestrator only writes to the output file. The base config
is never opened for writing.

**Apps:** Alacritty, Zathura, Hyprlock (via $theme_* vars), Tmux, Neovim

### Strategy: `standalone`

The entire output file is purely theming by nature. There is no base config to
conflict with.

**Safety guarantee:** The file contains nothing but theming data. There is no
non-theming content to corrupt.

**Apps:** Hyprland colors.conf, Quickshell GeneratedTheme.json, Qt color scheme,
Bat theme

### Strategy: `command`

No config file is involved. The generator returns a list of shell commands
(gsettings, swww, hyprctl, etc.) that the orchestrator executes.

**Safety guarantee:** No file writes occur. The generator cannot corrupt any config.

**Apps:** GTK (gsettings), Wallpaper (swww), Cursor (gsettings + hyprctl)

### Strategy: `concat`

The app does not support includes, but the file can be cleanly split into a
base portion and a theming portion. The orchestrator concatenates
`base_file + generated_content → output_file`. The base file is read-only to
the orchestrator (never written to).

**Safety guarantee:** The base file is only ever read, never written. The output
file is a concatenation. The generator only produces the theming portion.

**Apps:** Ghostty, Starship, Vicinae

### How the orchestrator uses strategies

```python
match target.ASSEMBLY:
    case "import":
        # Write generated content to target.OUTPUT_PATH
        write_file(target.OUTPUT_PATH, content)

    case "standalone":
        # Write generated content to target.OUTPUT_PATH
        write_file(target.OUTPUT_PATH, content)

    case "command":
        # content is a list of (cmd, args) tuples
        for cmd in content:
            subprocess.run(cmd, check=True)

    case "concat":
        # Read the base, concatenate with generated
        base = read_file(target.BASE_PATH)
        write_file(target.OUTPUT_PATH, base + "\n" + content)
```

---

## Target Contract

Every target is a Python module in `themes/lib/targets/`. Each module exports
these attributes:

```python
# ── Required attributes ───────────────────────────────────────

TARGET_NAME: str
# Unique identifier used in CLI subcommands.
# Example: "alacritty"

ASSEMBLY: str
# One of: "import", "standalone", "command", "concat"

def generate(colors: ColorScheme, state: ThemeState) -> str | list[list[str]]:
    """
    Pure function. No side effects. No file I/O. No subprocess calls.

    For "import", "standalone", "concat": returns a string (the generated content).
    For "command": returns a list of commands, each command being a list of strings.
    """
    ...

# ── Required for "import", "standalone", "concat" ────────────

OUTPUT_PATH: str
# Absolute path (use expanduser) to the generated output file.
# Example: "~/.config/alacritty/colors.toml"

# ── Required for "concat" ────────────────────────────────────

BASE_PATH: str
# Absolute path to the read-only base config file.
# Example: "~/.config/ghostty/config"
# This file is NEVER written to by the orchestrator.

# ── Optional ──────────────────────────────────────────────────

RELOAD_CMD: list[str] | None
# Shell command to trigger a hot-reload after writing.
# Example: ["hyprctl", "reload"]
# None if the app auto-reloads on file change.

COMMENT: str
# Comment prefix for the header line in generated files.
# Example: "#" for shell/toml, "//" for JSON (omit for JSON targets)
```

### Example target: `alacritty.py`

```python
"""Alacritty terminal color theme generator."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "alacritty"
ASSEMBLY = "import"
OUTPUT_PATH = "~/.config/alacritty/colors.toml"
RELOAD_CMD = None  # Alacritty watches config files and auto-reloads
COMMENT = "#"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return f"""\
[colors.primary]
background = "{colors.bg}"
foreground = "{colors.fg}"

[colors.normal]
black   = "{colors.palette[0]}"
red     = "{colors.palette[1]}"
green   = "{colors.palette[2]}"
yellow  = "{colors.palette[3]}"
blue    = "{colors.palette[4]}"
magenta = "{colors.palette[5]}"
cyan    = "{colors.palette[6]}"
white   = "{colors.palette[7]}"

[colors.bright]
black   = "{colors.palette[8]}"
red     = "{colors.palette[9]}"
green   = "{colors.palette[10]}"
yellow  = "{colors.palette[11]}"
blue    = "{colors.palette[12]}"
magenta = "{colors.palette[13]}"
cyan    = "{colors.palette[14]}"
white   = "{colors.palette[15]}"
"""
```

---

## Target Registry

### Quick reference

| Target       | Assembly     | Output path                             | Base path                         | Reload                     | Notes                                      |
|------------- |------------- |---------------------------------------- |---------------------------------- |--------------------------- |--------------------------------------------|
| alacritty    | `import`     | `~/.config/alacritty/colors.toml`       | —                                 | auto (inotify)             | Add `import = ["~/.config/alacritty/colors.toml"]` to base |
| ghostty      | `concat`     | `~/.config/ghostty/config`              | `$DOTFILES/config/ghostty/base`   | auto (inotify)             | Base has non-theming settings only         |
| hyprland     | `standalone` | `~/.config/hypr/colors.conf`            | —                                 | `hyprctl reload`           | Defines `$theme_*` variables               |
| hypr_appearance | `standalone` | `~/.config/hypr/appearance-theme.conf` | —                               | `hyprctl reload`           | Generated gaps, borders, rounding, blur, animations |
| hyprlock     | (none)       | —                                       | —                                 | —                          | Refactor to use `$theme_*` vars from colors.conf |
| hyprplugins  | (none)       | —                                       | —                                 | `hyprctl reload`           | Refactor to use `$theme_*` vars from colors.conf |
| zathura      | `import`     | `~/.config/zathura/colors`              | —                                 | relaunch                   | Add `include colors` to base zathurarc     |
| quickshell   | `standalone` | `~/.config/quickshell/GeneratedTheme.json` | —                              | IPC / file watch           | Theme.qml reads this JSON                  |
| neovim       | `standalone` | `~/.config/nvim/lua/theme-state.json`   | —                                 | autocmd on file change     | Lua reads JSON, sets colorscheme           |
| starship     | `concat`     | `~/.config/starship.toml`               | `$DOTFILES/config/starship/base.toml` | auto (next prompt)     | Base has format strings; generated has palette |
| tmux         | `import`     | `~/.config/tmux/colors.conf`            | —                                 | `tmux source-file ...`     | Add `source-file` to base tmux.conf        |
| gtk          | `command`    | —                                       | —                                 | immediate                  | gsettings for theme, font, icons, color-scheme |
| qt           | `standalone` | `~/.config/qt6ct/colors/current.conf`   | —                                 | relaunch Qt apps           | Multi-layered: QPalette + KColorScheme + Kvantum + hyprqt6engine. See [KDE App Theming](#kde-app-theming-on-hyprland). |
| vicinae      | `concat`     | `~/.config/vicinae/settings.json`       | `$DOTFILES/config/vicinae/base.json` | auto                   | JSON merge: base providers + generated theming |
| wallpaper    | `command`    | —                                       | —                                 | immediate                  | `swww img`                                 |
| cursor       | `command`    | —                                       | —                                 | immediate                  | gsettings + `hyprctl setcursor`            |
| bat          | `standalone` | `~/.config/bat/config`                  | —                                 | next invocation            | Single line: `--theme=<name>`              |

### Per-target specifications

Each section below is self-contained. An agent implementing a target only needs to
read: [Schemas](#schemas), [Target Contract](#target-contract), and the specific
target section below.

---

#### `alacritty.py`

**Assembly:** `import`
**Generated file:** `~/.config/alacritty/colors.toml`
**Reload:** Alacritty auto-reloads on inotify.

**Base config change required:** The existing `config/alacritty/alacritty.toml` must
be split. Move all color definitions out. Add to the top of the base file:

```toml
import = ["~/.config/alacritty/colors.toml"]
```

The base file keeps: `[font]` (family + size come from generated colors.toml too — 
actually, font is theming, so include it in the generated file), `[window]`, `[scrolling]`.

Wait — fonts ARE theming. So `colors.toml` should also contain the font section. 
Rename the generated file to `theme.toml` for clarity.

**Generated file:** `~/.config/alacritty/theme.toml`

**Content:** `[font]` section (mono_font, mono_font_size) + `[colors]` section
(primary, normal, bright from palette).

**Base file keeps:** `[window]`, `[scrolling]`, and the `import` line.

---

#### `ghostty.py`

**Assembly:** `concat`
**Generated file:** `~/.config/ghostty/config`
**Base file:** `$DOTFILES/config/ghostty/base`
**Reload:** Ghostty auto-reloads on config file change.

**Base config change required:** Rename current `config/ghostty/config` to
`config/ghostty/base`. Remove all theme lines (font-family, font-size, background,
foreground, selection-*, cursor-*, palette). The base file will likely be empty or
near-empty initially — add non-theming settings as needed (e.g., `window-padding`,
`scrollback-limit`, `gtk-single-width`).

**Generated content:** font-family, font-size, background, foreground,
selection-background, selection-foreground, cursor-color, cursor-text, and all
16 palette lines.

**Concat order:** base (non-theming) + newline + generated (theming).

---

#### `hyprland.py`

**Assembly:** `standalone`
**Generated file:** `~/.config/hypr/colors.conf`
**Reload:** `hyprctl reload`

This target already works conceptually. The generated file defines Hyprland variables
(`$theme_bg`, `$theme_fg`, `$theme_accent`, etc.) that `appearance.conf` and other
hypr configs reference. Port the existing logic to Python.

**Generated content example:**

```
# Generated by apply-theme — gruvbox-dark
$theme_bg       = rgb(282828)
$theme_bg_dim   = rgb(1d2021)
$theme_bg1      = rgb(3c3836)
...
$theme_font     = JetBrains Mono Nerd Font
$theme_sys_font = Overpass
$theme_font_size = 11
```

**Note:** Hyprland `rgb()` takes hex WITHOUT the `#` prefix.

---

#### Hyprlock — no target module (uses `$theme_*` vars from colors.conf)

Hyprlock supports `source` and can read the `$theme_*` variables defined by
`hyprland.py`'s `colors.conf`.

**Required refactor:** Change `config/hypr/hyprlock.conf` to replace hardcoded
color values with `$theme_*` variable references, and add at the top:

```
source = ~/.config/hypr/colors.conf
```

Replace:
```
$font = JetBrains Mono Nerd Font   →   $font = $theme_font
$bg = rgb(282828)                  →   (use $theme_bg directly)
$fg = rgb(ebdbb2)                  →   (use $theme_fg directly)
$accent = rgb(458588)              →   (use $theme_accent directly)
...
```

This means hyprlock gets themed automatically when `colors.conf` is regenerated
and the lock screen is triggered. No separate generator module needed.

---

#### Hyprland plugins — no target module (uses `$theme_*` vars from colors.conf)

Same approach as hyprlock. `pluginsettings.conf` is sourced by `hyprland.conf`
which also sources `colors.conf`, so `$theme_*` variables are available.

**Required refactor:** Change `config/hypr/pluginsettings.conf` to replace
hardcoded colors:

```
bar_color = rgb(3c3836)         →   bar_color = $theme_bg1
bar_text_color = rgb(ebdbb2)    →   bar_text_color = $theme_fg
bg_col = rgb(282828)            →   bg_col = $theme_bg
```

The hyprbars button colors (close=red, maximize=yellow, minimize=green) should
use `$theme_red`, `$theme_yellow`, `$theme_green`.

---

#### `zathura.py`

**Assembly:** `import`
**Generated file:** `~/.config/zathura/colors`
**Reload:** Zathura must be relaunched (no runtime reload).

**Base config change required:** Split current `zathurarc`. The base file keeps
non-theming settings (e.g., `set selection-clipboard clipboard`) and adds:

```
include colors
```

**Generated content:** All `set *-bg`, `set *-fg`, `set highlight-*`,
`set recolor-*` lines.

---

#### `quickshell.py`

**Assembly:** `standalone`
**Generated file:** `~/.config/quickshell/GeneratedTheme.json`
**Reload:** Theme.qml watches this file or re-reads on signal.

**Generated content:** A JSON file containing every value that `Theme.qml`
currently hardcodes:

```json
{
  "colors": {
    "bg": "#282828",
    "bg0_h": "#1d2021",
    "bg1": "#3c3836",
    "bg2": "#504945",
    "bg3": "#665c54",
    "fg": "#ebdbb2",
    "fg2": "#d5c4a1",
    "fg3": "#bdae93",
    "fg4": "#a89984",
    "red": "#cc241d",
    "green": "#98971a",
    "yellow": "#d79921",
    "blue": "#458588",
    "purple": "#b16286",
    "aqua": "#689d6a",
    "orange": "#d65d0e",
    "redBright": "#fb4934",
    "greenBright": "#b8bb26",
    "yellowBright": "#fabd2f",
    "blueBright": "#83a598",
    "purpleBright": "#d3869b",
    "aquaBright": "#8ec07c",
    "orangeBright": "#fe8019",
    "accent": "#458588"
  },
  "fonts": {
    "family": "JetBrains Mono Nerd Font",
    "systemFamily": "Overpass",
    "size": 12,
    "sizeSmall": 10,
    "sizeLarge": 14
  }
}
```

**Note:** The mapping from schema fields to Quickshell names:
- `cyan` → `aqua` (Quickshell uses "aqua" historically)
- `cyan_bright` → `aquaBright`
- `bg_dim` → `bg0_h`
- Font sizes for Quickshell (bar text) can differ from terminal font sizes.
  Quickshell's `fontSize: 12` etc. are layout constants, not state. Only
  `fontFamily` and `systemFamily` come from state.

---

#### `neovim.py`

**Assembly:** `standalone`
**Generated file:** `~/.config/nvim/lua/theme-state.json`
**Reload:** Neovim autocmd watches the file (or read on startup).

**Generated content:**

```json
{
  "colorscheme": "gruvbox",
  "background": "dark"
}
```

**Neovim-side change required:** The gruvbox.nvim plugin config should read this
file instead of hardcoding `vim.cmd([[colorscheme gruvbox]])`:

```lua
local ok, state = pcall(function()
  local f = io.open(vim.fn.stdpath("config") .. "/lua/theme-state.json", "r")
  if not f then return nil end
  local data = f:read("*a"); f:close()
  return vim.json.decode(data)
end)
if ok and state then
  vim.o.background = state.background
  vim.cmd.colorscheme(state.colorscheme)
else
  vim.cmd.colorscheme("gruvbox")  -- fallback
end
```

**Mapping:** The `family` field in `ColorScheme` maps to the Neovim colorscheme
name. Common mappings:
- `gruvbox` → `"gruvbox"` (via gruvbox.nvim)
- `solarized` → `"solarized"` or `"solarized-osaka"`
- `catppuccin` → `"catppuccin"` (supports `-mocha`, `-latte`, etc. variants)

Each color scheme JSON should include a `neovim_colorscheme` field if the mapping
is non-obvious. Add this as an optional field in the JSON (not in the dataclass —
it's target-specific metadata).

---

#### `starship.py`

**Assembly:** `concat`
**Generated file:** `~/.config/starship.toml`
**Base file:** `$DOTFILES/config/starship/base.toml`
**Reload:** Automatic on next prompt render.

**Base config change required:** Split current `config/starship/starship.toml`:
- `base.toml` keeps: `add_newline`, `format`, all `[module]` sections, `[character]`.
  Change `palette = 'gruvbox_dark'` to `palette = 'current'`.
- All color references in format strings already use abstract names like
  `color_orange`, `color_blue`, etc. These are palette-key references, so the
  format strings work with ANY palette that defines the same keys.

**Generated content:** Just the palette block:

```toml

[palettes.current]
color_fg0 = '#fbf1c7'
color_bg1 = '#3c3836'
color_bg3 = '#665c54'
color_blue = '#458588'
color_aqua = '#689d6a'
color_green = '#98971a'
color_orange = '#d65d0e'
color_purple = '#b16286'
color_red = '#cc241d'
color_yellow = '#d79921'
```

**Palette key mapping** (starship name → ColorScheme field):
- `color_fg0` → `fg`
- `color_bg1` → `bg1`
- `color_bg3` → `bg3`
- `color_blue` → `blue`
- `color_aqua` → `cyan`
- `color_green` → `green`
- `color_orange` → `orange`
- `color_purple` → `purple`
- `color_red` → `red`
- `color_yellow` → `yellow`

---

#### `tmux.py`

**Assembly:** `import`
**Generated file:** `~/.config/tmux/colors.conf`
**Reload:** `tmux source-file ~/.config/tmux/tmux.conf` (or the orchestrator
can send `tmux source-file ~/.config/tmux/colors.conf` directly if tmux is running).

**Base config change required:** Split current `config/tmux/tmux.conf`. Remove all
`-style` and color directives. Add:

```
source-file ~/.config/tmux/colors.conf
```

**Generated content:**

```
# Generated by apply-theme
set -g status-style "bg=#3c3836,fg=#ebdbb2"
set -g status-left "#[fg=#282828,bg=#458588,bold] #S #[bg=#3c3836] "
set -g status-right "#[fg=#ebdbb2] %H:%M "
setw -g window-status-format " #I:#W "
setw -g window-status-current-format "#[fg=#282828,bg=#98971a,bold] #I:#W "
set -g pane-border-style "fg=#3c3836"
set -g pane-active-border-style "fg=#458588"
```

---

#### `gtk.py`

**Assembly:** `command`
**Reload:** Immediate (GTK4 apps respond to gsettings changes live; GTK3 apps
may need relaunch).

**Generated commands:**

```python
def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    gtk_theme = "adw-gtk3-dark" if colors.variant == "dark" else "adw-gtk3"
    color_pref = "prefer-dark" if colors.variant == "dark" else "prefer-light"
    return [
        ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", gtk_theme],
        ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", color_pref],
        ["gsettings", "set", "org.gnome.desktop.interface", "font-name", f"{state.system_font} {state.font_size}"],
        ["gsettings", "set", "org.gnome.desktop.interface", "monospace-font-name", f"{state.mono_font} {state.mono_font_size}"],
        ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", state.icon_theme],
    ]
```

---

#### `qt.py`

**Assembly:** `standalone`
**Generated file:** `~/.config/qt6ct/colors/current.conf` (and qt5ct equivalent)
**Reload:** Qt apps must be relaunched.

The qt target is the most complex target — it writes to multiple config systems
because different KDE components read colors from different sources. See
[KDE App Theming on Hyprland](#kde-app-theming-on-hyprland) for the full rationale.

**`generate()` output** (written by the orchestrator):
- `~/.config/qt6ct/colors/current.conf` — QPalette INI format (21 color roles)
- `~/.config/qt5ct/colors/current.conf` — same, for Qt5 apps (via `EXTRA_OUTPUTS`)

**`on_apply()` side effects** (written directly by the target):
- `~/.config/qt6ct/qt6ct.conf` — sets `style=kvantum`, points to the color scheme
- `~/.config/qt5ct/qt5ct.conf` — same, for Qt5 apps
- `~/.config/kdeglobals` — KDE color groups (`Colors:Window`, `Colors:View`, etc.)
- `~/.local/share/color-schemes/current.colors` — standalone KColorScheme file
- `~/.config/hypr/hyprqt6engine.conf` — platform theme config (`style=kvantum`,
  fonts, icons, color_scheme path)
- `~/.config/Kvantum/GeneratedTheme/GeneratedTheme.kvconfig` — custom Kvantum theme
  with `[GeneralColors]` mapped from the active ColorScheme
- `~/.config/Kvantum/GeneratedTheme/GeneratedTheme.svg` — symlink to KvGnomeDark
  SVG (dark themes) or KvGnome SVG (light themes) for widget shapes
- `~/.config/Kvantum/kvantum.kvconfig` — theme selector pointing to GeneratedTheme

All of these files are written to `~/.config/` or `~/.local/share/`, not the repo —
they do not need `.gitignore` entries.

**Environment variables** (set in `config/hypr/env.conf`, version-controlled):
- `QT_QPA_PLATFORMTHEME=hyprqt6engine` — fonts, icons, file dialogs
- `QT_STYLE_OVERRIDE=kvantum` — forces Kvantum as the widget style for all Qt apps

**Nix packages** (in `home/default.nix`):
- `kdePackages.qtstyleplugin-kvantum` (Qt6)
- `libsForQt5.qtstyleplugin-kvantum` (Qt5)
- `hyprqt6engine` (overridden with KF6 buildInputs in `system/configuration.nix`)

**Color mapping from ColorScheme to Kvantum `[GeneralColors]`:**

| Kvantum key              | ColorScheme field | Purpose                          |
|--------------------------|-------------------|----------------------------------|
| `window.color`           | `bg`              | Window chrome background         |
| `base.color`             | `bg`              | Content area background          |
| `alt.base.color`         | `bg`              | Same as base (prevents zebra stripes) |
| `button.color`           | `bg1`             | Button background                |
| `highlight.color`        | `accent`          | Selection/focus highlight        |
| `text.color`             | `fg`              | Primary text                     |
| `highlight.text.color`   | `fg`              | Text on highlighted items        |
| `disabled.text.color`    | `fg4`             | Disabled/muted text              |
| `link.color`             | `blue`            | Hyperlinks                       |
| `link.visited.color`     | `purple`          | Visited hyperlinks               |

---

#### `vicinae.py`

**Assembly:** `concat` (JSON merge variant)
**Generated file:** `~/.config/vicinae/settings.json`
**Base file:** `$DOTFILES/config/vicinae/base.json`
**Reload:** Vicinae auto-reloads.

**Base config change required:** Rename current `config/vicinae/settings.json` to
`config/vicinae/base.json`. Keep only non-theming fields (`$schema`, `providers`).

**Merge strategy:** Read base JSON, overlay theming fields:

```python
def generate(colors: ColorScheme, state: ThemeState) -> str:
    return json.dumps({
        "font": {"normal": {"family": state.system_font}},
        "theme": {
            "dark": {"name": colors.family + "-" + colors.variant},
            "light": {"name": colors.family + "-light"}
        }
    }, indent=2)
```

The orchestrator's concat handler for JSON does a shallow merge:
`{**base, **generated}` (not plain string concatenation).

---

#### `wallpaper.py`

**Assembly:** `command`
**Reload:** Immediate.

```python
def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    return [
        ["swww", "img", state.wallpaper,
         "--transition-type", "fade",
         "--transition-duration", "1"]
    ]
```

---

#### `cursor.py`

**Assembly:** `command`
**Reload:** Immediate for new windows; existing windows keep old cursor.

```python
def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    return [
        ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", state.cursor_theme],
        ["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(state.cursor_size)],
        ["hyprctl", "setcursor", state.cursor_theme, str(state.cursor_size)],
    ]
```

---

#### `bat.py`

**Assembly:** `standalone`
**Generated file:** `~/.config/bat/config`
**Reload:** Next `bat` invocation.

```python
def generate(colors: ColorScheme, state: ThemeState) -> str:
    # bat theme names: "gruvbox-dark", "Solarized (dark)", "Catppuccin Mocha", etc.
    # This mapping may need a lookup table.
    bat_theme = f"{colors.family}-{colors.variant}"  # Simplified
    return f"--theme={bat_theme}\n"
```

---

## Orchestrator

### CLI interface

```
apply-theme [subcommand]

Subcommands:
  all                     Apply all targets
  colors                  Apply only color-dependent targets (everything except wallpaper/cursor)
  wallpaper               Apply only wallpaper
  cursor                  Apply only cursor
  fonts                   Apply only font-dependent targets
  target <name>           Apply a single target by name
  set <key> <value>       Update state.json and apply affected targets
  preset <name>           Load a preset into state.json and apply all
  list-schemes            List available color schemes
  list-presets            List available presets
  status                  Show current state
```

### `set` subcommand intelligence

When `apply-theme set color_scheme gruvbox-dark` is called, it should only
re-apply targets that depend on colors — not wallpaper or cursor. Dependency map:

| State key                        | Affected targets                                                                                  |
|--------------------------------- |---------------------------------------------------------------------------------------------------|
| color_scheme                     | alacritty, ghostty, hyprland, zathura, quickshell, neovim, starship, tmux, gtk, qt, vicinae, bat, wallpaper, vscode, snappy_switcher |
| wallpaper                        | wallpaper                                                                                         |
| filter_wallpaper                 | wallpaper                                                                                         |
| system_font                      | quickshell, gtk, qt, vicinae, snappy_switcher                                                     |
| mono_font                        | alacritty, ghostty, gtk, quickshell, qt, tmux, vscode                                             |
| icon_theme                       | gtk, qt, snappy_switcher                                                                          |
| cursor_theme                     | cursor                                                                                            |
| cursor_size                      | cursor                                                                                            |
| font_size                        | gtk, qt, snappy_switcher                                                                          |
| mono_font_size                   | alacritty, ghostty, gtk, qt, vscode                                                               |
| alacritty_mono_font_size_offset  | alacritty                                                                                         |
| ghostty_mono_font_size_offset    | ghostty                                                                                           |
| gtk_mono_font_size_offset        | gtk                                                                                               |
| qt_mono_font_size_offset         | qt                                                                                                |
| vscode_mono_font_size_offset     | vscode                                                                                            |
| dark_hint                        | gtk                                                                                               |

### Error handling

- If a target fails, log the error and continue to the next target.
- If `state.json` is missing or corrupt, refuse to run and print an error.
- If a color scheme JSON is missing, refuse to run and print an error.
- If a base file for `concat` assembly is missing, skip that target with a warning.

### Generated file headers

For non-JSON targets, prepend a header:

```
# Generated by apply-theme — do not edit
# Source: gruvbox-dark | Variant: dark
```

This helps both humans and agents understand the file's provenance.

---

## Home-Manager Migration

### Files to REMOVE from `xdg.configFile` in `home/default.nix`

These are currently symlinked to the Nix store (read-only) and must be freed for
hot-swap writing:

```nix
# REMOVE these lines:
xdg.configFile."alacritty/alacritty.toml".source = ...;
xdg.configFile."ghostty/config".source = ...;
xdg.configFile."hypr/colors.conf".source = ...;
xdg.configFile."zathura/zathurarc".source = ...;
xdg.configFile."starship.toml".source = ...;
xdg.configFile."tmux/tmux.conf".source = ...;
xdg.configFile."vicinae" = { source = ...; recursive = true; };
```

### Files to ADD/KEEP as `xdg.configFile`

Base configs that are NOT generated should remain as symlinks:

```nix
# KEEP (or add) these — base configs with import lines:
xdg.configFile."alacritty/alacritty.toml".source = "${dotfilesPath}/config/alacritty/alacritty.toml";
xdg.configFile."zathura/zathurarc".source = "${dotfilesPath}/config/zathura/zathurarc";
xdg.configFile."tmux/tmux.conf".source = "${dotfilesPath}/config/tmux/tmux.conf";
xdg.configFile."vicinae/base.json".source = "${dotfilesPath}/config/vicinae/base.json";

# KEEP these — not affected by theming:
xdg.configFile."hypr/hyprland.conf".source = ...;
xdg.configFile."hypr/appearance.conf".source = ...;
xdg.configFile."hypr/keybinds.conf".source = ...;
xdg.configFile."hypr/rules.conf".source = ...;
xdg.configFile."hypr/input.conf".source = ...;
xdg.configFile."hypr/autostart.conf".source = ...;
xdg.configFile."hypr/hyprlock.conf".source = ...;      # refactored to use $theme_* vars
xdg.configFile."hypr/pluginsettings.conf".source = ...; # refactored to use $theme_* vars
```

### Activation hook

```nix
home.activation.applyTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
  PATH="${lib.makeBinPath [pkgs.python3 pkgs.glib pkgs.swww pkgs.hyprland]}:$PATH"
  ${dotfilesPath}/themes/apply-theme all 2>&1 | head -50 || true
'';
```

### Special cases

**Ghostty:** Does NOT support includes. The `config/ghostty/base` is NOT managed by
`xdg.configFile` (it's only read by the orchestrator during concatenation). The
actual `~/.config/ghostty/config` is written by `apply-theme` and must not be
symlinked.

**Starship:** Same as Ghostty. `config/starship/base.toml` exists in the repo but
the final `~/.config/starship.toml` is written by `apply-theme`.

**Quickshell:** The directory is currently managed as `recursive: true`. This should
remain, but `GeneratedTheme.json` will be written at runtime. Since
`xdg.configFile` with `recursive: true` symlinks individual files (not the
directory itself on NixOS with home-manager), a new file written into
`~/.config/quickshell/` will coexist with the symlinks. Verify this works; if
not, switch to individual file symlinks for the Quickshell QML files.

---

## Quickshell Integration

### Theme.qml refactor

Replace all hardcoded color values with a loader that reads `GeneratedTheme.json`:

```qml
pragma Singleton
import QtQuick

QtObject {
    id: root

    // ── Load from generated JSON ──
    property var _data: {
        try {
            let xhr = new XMLHttpRequest();
            xhr.open("GET", "file:///home/kevin/.config/quickshell/GeneratedTheme.json", false);
            xhr.send();
            return JSON.parse(xhr.responseText);
        } catch(e) {
            return null;
        }
    }

    property var _colors: _data ? _data.colors : {}
    property var _fonts: _data ? _data.fonts : {}

    // Colors (with hardcoded Gruvbox fallbacks)
    readonly property color bg:        _colors.bg        || "#282828"
    readonly property color bg0_h:     _colors.bg0_h     || "#1d2021"
    // ... etc for all color properties ...

    // Fonts
    readonly property string fontFamily: _fonts.family || "JetBrains Mono Nerd Font"
    // ... etc ...

    // Layout constants (NOT themed — these stay hardcoded)
    readonly property int barHeight: 32
    readonly property int barMargin: 4
    // ... etc ...
}
```

**Important:** Layout constants (barHeight, barRadius, barSpacing, notifWidth, etc.)
are NOT part of theming. They stay hardcoded in Theme.qml.

### SettingsPopup fix

The current bug: `$DOTFILES` env var doesn't reach Quickshell's Process commands
because Quickshell's environment doesn't inherit it. Fix: hardcode the dotfiles
path in the Process commands, or pass it via a Quickshell config/environment
mechanism.

The SettingsPopup should call `apply-theme set <key> <value>` instead of the
current `set-theme.sh` script. The flow:

1. User clicks a color scheme button
2. SettingsPopup runs: `Process { command: ["/home/kevin/repos/dotfiles/themes/apply-theme", "set", "color_scheme", schemeName] }`
3. `apply-theme` updates `state.json`, regenerates affected files, fires reloads
4. Quickshell detects `GeneratedTheme.json` changed, updates Theme.qml properties
5. All Quickshell UI updates reactively

The same pattern applies to live Hyprland appearance controls: the popup updates
state keys, `apply-theme` regenerates `~/.config/hypr/appearance-theme.conf`, and
Hyprland picks up the change on reload through the base `appearance.conf`.

---

## KDE App Theming on Hyprland

KDE apps (Dolphin, Kate, Ark, Gwenview, etc.) on Hyprland are uniquely difficult to
theme because there is no Plasma session. This section documents every approach tried
and why each failed or partially worked. Future agents: read this before touching
`qt.py`.

### The core problem

KDE apps have two rendering layers:

1. **Standard Qt widgets** (file list rows, buttons, scrollbars, text inputs) — these
   respect the QPalette set by the platform theme (qt6ct, hyprqt6engine).
2. **Kirigami chrome** (toolbar, sidebar, menubar, header area) — these are painted by
   KDE Frameworks using its own color system. Kirigami ignores QPalette on non-Plasma
   sessions and falls back to Breeze Light defaults.

Any solution that only sets QPalette will theme layer 1 but leave layer 2 completely
unthemed (light toolbar on dark file list).

### Approaches tried

#### 1. qt6ct + Fusion style

**Result:** Partial. File list and standard widgets themed correctly. Toolbar, sidebar,
and menubar remained light/unthemed.

**Why:** Fusion is a QPalette-only style engine. It renders from the palette for
standard QWidgets but has no hook into Kirigami's rendering path. Kirigami toolbar/
sidebar widgets are QQuickItems, not QWidgets — they don't use QPalette at all.

#### 2. hyprqt6engine (Hyprland's Qt6 theme engine)

**Result:** Same as qt6ct + Fusion. QPalette works, Kirigami chrome unthemed.

**Details:** hyprqt6engine was rebuilt with KF6 support (kcolorscheme, kconfig,
kiconthemes added to `buildInputs` via `overrideAttrs` in `system/configuration.nix`).
Even with KF6 linked, hyprqt6engine correctly provides QPalette, fonts, and icons
to standard Qt widgets but cannot force Kirigami to use its colors. hyprqt6engine
remains useful as the platform theme for fonts, icons, and file dialogs.

#### 3. kdeglobals (KDE's global color config)

**Result:** No effect on Kirigami chrome. Does work for Kate's KColorScheme.

**Details:** Even copying BreezeDark.colors directly into `~/.config/kdeglobals`
had zero visible effect on Dolphin's toolbar or sidebar. KDE Frameworks reads
kdeglobals but Kirigami on non-Plasma sessions doesn't apply those colors to its
QML chrome. However, Kate/KWrite DO read kdeglobals via KColorScheme for their
editor chrome colors — so kdeglobals is still needed for Kate support.

#### 4. QT_STYLE_OVERRIDE=Fusion

**Result:** No effect on Kirigami chrome. Fusion only controls QPalette-based rendering.

#### 5. Kvantum (current solution)

**Result:** Kirigami chrome IS themed (toolbar, sidebar, menubar become dark). This
is the only approach that successfully themes Kirigami on a non-Plasma session.

**Why it works:** Kvantum is a Qt style engine that hooks in at a deeper level than
Fusion. It completely replaces the QPalette in its `polish()` method and renders
widget backgrounds from SVG artwork. Critically, Kvantum's rendering covers both
standard QWidgets and QQuickItem-based Kirigami components.

**Known limitation:** Kvantum's `polish(QPalette)` completely overwrites the incoming
QPalette with its own colors from `[GeneralColors]`. There is no way to make Kvantum
"inherit" or "pass through" the platform theme's palette. This is by design — the
Kvantum maintainer has explicitly stated this will not change. This is why we must
generate a custom Kvantum theme with our exact ColorScheme values.

### Current architecture

All layers are used simultaneously because different KDE components read from
different sources:

```
hyprqt6engine (QT_QPA_PLATFORMTHEME)  → fonts, icons, file dialogs
Kvantum (QT_STYLE_OVERRIDE)           → all widget surface painting including Kirigami
GeneratedTheme.kvconfig                → color values for Kvantum's palette + widget rendering
GeneratedTheme.svg                     → widget shapes (symlink to KvGnomeDark/KvGnome)
qt6ct/qt5ct palette                    → fallback QPalette (unused when Kvantum active, kept for compat)
kdeglobals + current.colors            → Kate/KWrite KColorScheme (editor chrome, syntax theme selector)
```

### Why KvDark was rejected

The built-in KvDark theme caused two visual defects:

1. **Zebra-striped file list rows:** `alt.base.color=#383838` vs `base.color=#2E2E2E`
   creates visible alternating row backgrounds. Our GeneratedTheme sets both to the
   same value (`colors.bg`) to eliminate this.
2. **Dark-on-dark text:** KvDark sets `text.press.color=black` and
   `text.toggle.color=black` in its `[ItemView]` section. When an item is pressed
   but the background hasn't transitioned to the light highlight color, black text
   becomes invisible on the dark background. KvGnomeDark (our SVG base) avoids this
   by using `inherits=PanelButtonCommand` chains instead of hardcoded black.

### The GeneratedTheme approach

Instead of using a pre-built Kvantum theme, `qt.py` generates a custom one:

1. **`GeneratedTheme.kvconfig`** — `[GeneralColors]` mapped from the active
   ColorScheme, `[%General]` settings from KvGnomeDark for polished behavior,
   `[Hacks]` for app-specific workarounds.
2. **`GeneratedTheme.svg`** — symlinked to KvGnomeDark's SVG (dark themes) or
   KvGnome's SVG (light themes). The SVG provides widget background shapes; colors
   are overridden by the kvconfig. The SVG is found at apply-time by searching
   `XDG_DATA_DIRS` and NixOS profile paths.
3. **`kvantum.kvconfig`** — theme selector file pointing to GeneratedTheme.

This approach hot-swaps correctly: when the user changes color schemes, `qt.py`
regenerates the kvconfig with new `[GeneralColors]` values. The SVG symlink only
changes when switching between dark and light variants.

### Remaining known issues

- **Kate/KWrite syntax highlighting:** KSyntaxHighlighting uses its own theme system
  separate from both Kvantum and KColorScheme. Kate's editor area colors come from
  its built-in color themes (Settings > Color Themes), not from the system theme.
  The UI chrome (sidebar, toolbar, tab bar) is themed via Kvantum + KColorScheme.
- **SVG background mismatch:** KvGnomeDark's SVG has its own dark gray backgrounds
  (~#353535) which may not exactly match the ColorScheme's `bg` value. The visual
  difference is subtle for most dark themes but could be noticeable for schemes with
  unusual background colors.

---

## Testing

### Unit testing generators

Each generator can be tested in isolation:

```bash
cd ~/repos/dotfiles/themes
python3 -c "
from lib.schema import ColorScheme, ThemeState
from lib.targets.alacritty import generate
import json

with open('colors/gruvbox-dark.json') as f:
    data = json.load(f)

colors = ColorScheme(
    family=data['family'], variant=data['variant'],
    **data['colors'], palette=tuple(data['palette'])
)
state = ThemeState(
    color_scheme='gruvbox-dark',
    wallpaper='/home/kevin/wallpapers/lmao.png',
    filter_wallpaper=False,
    system_font='Overpass', mono_font='JetBrains Mono Nerd Font',
    icon_theme='Papirus-Dark', cursor_theme='Adwaita', cursor_size=24,
    font_size=11, mono_font_size=11,
    alacritty_mono_font_size_offset=0,
    ghostty_mono_font_size_offset=0,
    gtk_mono_font_size_offset=0,
    qt_mono_font_size_offset=0,
    vscode_mono_font_size_offset=0,
    dark_hint=False
)
print(generate(colors, state))
"
```

### Smoke testing the full pipeline

```bash
# Apply everything and check for errors
./themes/apply-theme all

# Apply a single target
./themes/apply-theme target alacritty

# Switch scheme and verify
./themes/apply-theme set color_scheme solarized-light
```

### Verifying isolation

To confirm a generator cannot touch non-theming config:

1. The `generate()` function has no access to file paths (it receives only
   `ColorScheme` and `ThemeState`).
2. The function signature returns `str` — it cannot perform I/O.
3. The frozen dataclasses prevent mutation of inputs.
4. The orchestrator only writes to `OUTPUT_PATH` — never to `BASE_PATH`.

---

## Implementation Plan

### Dependency graph

```
Phase 0: Foundation (sequential)
├── THEMING.md (this file) ✅
├── themes/lib/schema.py
├── themes/lib/resolve.py
└── themes/lib/orchestrator.py + themes/apply-theme

Phase 1: Generators + config splits (ALL PARALLEL — independent of each other)
├── Agent A: alacritty.py    + split alacritty config
├── Agent B: ghostty.py      + create ghostty base config
├── Agent C: hyprland.py     (port existing logic)
├── Agent D: zathura.py      + split zathura config
├── Agent E: starship.py     + split starship config
├── Agent F: tmux.py         + split tmux config
├── Agent G: quickshell.py   (GeneratedTheme.json)
├── Agent H: neovim.py       + add theme-state.json reader to lua config
├── Agent I: gtk.py + cursor.py + wallpaper.py   (command targets, small)
├── Agent J: vicinae.py      + create vicinae base.json
└── Agent K: bat.py          (trivial standalone)

Phase 2: Hyprland config refactors (parallel, after Phase 0)
├── Agent L: Refactor hyprlock.conf  → use $theme_* vars
└── Agent M: Refactor pluginsettings.conf → use $theme_* vars

Phase 3: Integration (sequential, after Phase 1 + 2)
├── Home-manager migration (remove xdg.configFile for generated files)
├── Quickshell Theme.qml refactor (read GeneratedTheme.json)
└── Quickshell SettingsPopup update (call apply-theme CLI)

Phase 4: Polish (parallel, after Phase 3)
├── Agent N: qt.py (qt6ct/qt5ct color scheme generation)
├── Agent O: Additional color scheme JSONs (catppuccin, nord, etc.)
├── Agent P: Preset JSONs
└── Agent Q: .gitignore updates for all generated files
```

### Phase 0 — Foundation

**Must be done first.** All other phases depend on this.

Create:
- `themes/lib/__init__.py` (empty)
- `themes/lib/schema.py` (ColorScheme + ThemeState dataclasses)
- `themes/lib/resolve.py` (load color JSON → ColorScheme, load state → ThemeState)
- `themes/lib/targets/__init__.py` (target auto-discovery)
- `themes/lib/orchestrator.py` (assembly logic, reload dispatch)
- `themes/apply-theme` (CLI entry point, chmod +x)
- `themes/colors/gruvbox-dark.json` (first color scheme, matching current setup)
- `themes/state.json` (initial state matching current setup)

### Phase 1 — Generators (all parallel)

Each agent gets a prompt like:

> Implement `themes/lib/targets/alacritty.py` following the target contract in
> THEMING.md. Also split `config/alacritty/alacritty.toml` into a base config
> (with an import line) and verify the generated output matches the current
> theme. Read THEMING.md first.

Each task is one target module + the corresponding config split. Every task is
independent — no agent needs to coordinate with another.

### Phase 2 — Hyprland refactors (parallel with Phase 1)

These don't create new generator modules. They edit existing config files to
use `$theme_*` variable references instead of hardcoded colors.

### Phase 3 — Integration (sequential)

This is the "flip the switch" phase:
1. Update `home/default.nix` — remove/change `xdg.configFile` entries
2. Add activation hook
3. Refactor `Theme.qml` to be dynamic
4. Update `SettingsPopup.qml` to call `apply-theme`
5. Run `nixos-rebuild switch`
6. Test full hot-swap cycle

### Phase 4 — Polish

Nice-to-haves that can happen anytime after Phase 3:
- Qt theming (complex, can defer)
- More color schemes
- Preset bundles
- `.gitignore` cleanup

---

## Agent Quick-Reference

When starting a task, read these sections:
1. [Schemas](#schemas) — always
2. [Target Contract](#target-contract) — for any generator task
3. The specific target section in [Target Registry](#target-registry) — for your target
4. [Assembly Strategies](#assembly-strategies) — if the assembly type is unfamiliar

Do NOT read sections for other targets. Each target is independent.

### Common mistakes to avoid

- **Don't import anything outside stdlib.** No pip packages. Only `json`, `pathlib`,
  `dataclasses`, `subprocess`, `os`, `tomllib` (Python 3.11+), `textwrap`, etc.
- **Don't do file I/O in generate().** Return a string. The orchestrator writes it.
- **Don't hardcode `/home/kevin/`.** Use `Path.home()` or `os.path.expanduser("~")` in
  the orchestrator. Generators don't deal with paths at all.
- **Don't include non-theming settings in generated output.** If you're not sure
  whether a setting is theming, it probably isn't. Fonts (family + size) ARE theming.
  Scrollback, padding, keybinds, layout are NOT.
- **Don't forget the header comment** for generated files (the orchestrator adds this,
  but generators should not add their own).
