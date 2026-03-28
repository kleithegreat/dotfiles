"""VS Code settings theme generator."""

import json
import sqlite3
import sys
from pathlib import Path

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "vscode"
ASSEMBLY = "concat"
OUTPUT_PATH = "~/.config/Code/User/settings.json"
BASE_PATH = "~/repos/dotfiles/config/vscode/base.json"
RELOAD_CMD = None  # VS Code watches settings.json for changes

_STATE_DB = Path("~/.config/Code/User/globalStorage/state.vscdb")

# Map (family, variant) to the installed extension's workbench.colorTheme string.
_THEME_MAP: dict[tuple[str, str], str] = {
    ("gruvbox", "dark"): "Gruvbox Dark Medium",
    ("gruvbox", "light"): "Gruvbox Light Medium",
    ("catppuccin", "mocha"): "Catppuccin Mocha",
    ("catppuccin", "latte"): "Catppuccin Latte",
    ("catppuccin", "frappe"): "Catppuccin Frappé",
    ("catppuccin", "macchiato"): "Catppuccin Macchiato",
    ("solarized", "dark"): "Solarized Dark+",
    ("solarized", "light"): "Solarized Light+",
    ("rose-pine", "dark"): "Rosé Pine",
    ("rose-pine", "light"): "Rosé Pine Dawn",
}

# Map theme family to the VS Code extension that provides it.
# Families whose themes ship built-in (e.g. solarized) are omitted.
_EXTENSION_MAP: dict[str, str] = {
    "catppuccin": "catppuccin.catppuccin-vsc",
    "gruvbox": "jdinhlife.gruvbox",
    "rose-pine": "mvllow.rose-pine",
}


def _resolve_theme(family: str, variant: str) -> str:
    return _THEME_MAP.get((family, variant), f"{family}-{variant}")


def generate(colors: ColorScheme, state: ThemeState) -> str:
    font_size = state.mono_font_size_for(TARGET_NAME)
    return json.dumps({
        "workbench.colorTheme": _resolve_theme(colors.family, colors.variant),
        "editor.fontFamily": state.mono_font,
        "editor.fontSize": font_size,
        "terminal.integrated.fontFamily": state.mono_font,
        "terminal.integrated.fontSize": font_size,
    }, indent=2)


def persist(colors: ColorScheme, state: ThemeState) -> None:
    """Ensure the theme extension is not disabled in VS Code's state database.

    Settings sync can mark theme extensions as disabled, which prevents VS Code
    from applying the theme even when settings.json is correct.
    """
    ext_id = _EXTENSION_MAP.get(colors.family)
    if not ext_id:
        return

    db_path = _STATE_DB.expanduser()
    if not db_path.is_file():
        return

    conn = sqlite3.connect(str(db_path))
    try:
        cur = conn.cursor()
        row = cur.execute(
            "SELECT value FROM ItemTable WHERE key = ?",
            ("extensionsIdentifiers/disabled",),
        ).fetchone()
        if row is None:
            return

        disabled = json.loads(row[0])
        updated = [e for e in disabled if e.get("id") != ext_id]
        if len(updated) < len(disabled):
            cur.execute(
                "UPDATE ItemTable SET value = ? WHERE key = ?",
                (json.dumps(updated), "extensionsIdentifiers/disabled"),
            )
            conn.commit()
            print(f"  vscode: enabled extension {ext_id}", file=sys.stderr)
    finally:
        conn.close()
