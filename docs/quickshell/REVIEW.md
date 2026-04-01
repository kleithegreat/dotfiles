# Quickshell Review

Reviewed on 2026-04-01.

Scope:

- `docs/quickshell/SPEC.md`
- `docs/theming/SPEC.md`
- every file under `config/quickshell/`
- the Quickshell-facing theming path in `themes/apply-theme`,
  `themes/lib/orchestrator.py`, and `themes/lib/targets/quickshell.py`

The previous review had gone stale. The older findings around Wi-Fi power in the
network pane, sidebar scrolling, display selector density, preset-card overflow,
bar-level Network/Bluetooth polling, and Mullvad location browsing have been
resolved in the current code and are intentionally removed here.

## 1. Quick Settings expand buttons are wired to dead-end signals

`QuickSettingsPopup.qml` still defines five "expand to full page" signals for
Wi-Fi, Bluetooth, VPN, DND, and power profile (`config/quickshell/popups/QuickSettingsPopup.qml:24-30`).
The tile chevron buttons call `tileExpand()`, which emits exactly those signals
(`config/quickshell/popups/QuickSettingsPopup.qml:270-278`,
`config/quickshell/popups/QuickSettingsPopup.qml:353-373`).

But the overlay host only consumes one signal from Quick Settings:
`onSettingsRequested`, which opens the full settings popup
(`config/quickshell/PopupOverlayHost.qml:155-162`). There is no host-side
wiring for `wifiExpandRequested`, `bluetoothExpandRequested`, `vpnExpandRequested`,
`dndExpandRequested`, or `powerProfileExpandRequested`.

This is a user-facing dead affordance. The UI presents secondary chevrons on the
Quick Settings tiles, but clicking them does nothing.

## 2. `theme.apply` IPC is argument-fragile and has no completion/error path

The shell-level theme IPC target exposes:

- `open()`, which toggles the settings popup
- `apply(args)`, which does `args.split(" ")` and spawns
  `/home/kevin/repos/dotfiles/themes/apply-theme`

That implementation lives in `config/quickshell/shell.qml:244-256`.

The problem is that `apply-theme` is an argv-based CLI whose `set` subcommand
expects one `key` argument and one `value` argument
(`themes/apply-theme:228-257`). Splitting the caller payload on spaces means
values containing spaces cannot round-trip safely through IPC. Current theme
values with spaces include system fonts such as `"IBM Plex Sans"` and wallpaper
paths can also legally contain spaces
(`config/quickshell/popups/settings/SettingsFontsPane.qml:21-32`,
`config/quickshell/popups/settings/SettingsWallpaperPane.qml:138-186`).

The same IPC path also has no `onExited` handling, so failures do not refresh
settings state, emit a toast, or otherwise report command failure back into the
shell (`config/quickshell/shell.qml:244-247`).

This makes shell IPC less reliable than the settings-host path for the same
theme mutations.

## 3. Quickshell font-size controls do not affect Quickshell chrome

The Quickshell spec says that shell font families and shell font-size slots
belong in `GeneratedTheme.json` (`docs/quickshell/SPEC.md:166-167`).

The current implementation only half-does that:

- `SettingsFontsPane` exposes both `font_size` and `mono_font_size` controls
  (`config/quickshell/popups/settings/SettingsFontsPane.qml:104-170`,
  `config/quickshell/popups/settings/SettingsFontsPane.qml:296-362`)
- `Theme.qml` reads `fonts.size`, `fonts.sizeSmall`, and `fonts.sizeLarge` from
  `GeneratedTheme.json` (`config/quickshell/Theme.qml:64-69`)
- but the Quickshell target hardcodes those three values to `12`, `10`, and
  `14` instead of deriving them from `ThemeState`
  (`themes/lib/targets/quickshell.py:41-47`)
- and the orchestrator does not route `font_size` or `mono_font_size` changes
  to the `quickshell` target (`themes/lib/orchestrator.py:29-30`)

The result is that the Settings font-size controls update external targets such
as GTK, Qt, terminal/editor targets, and Snappy Switcher, but they do not
change Quickshell's own chrome. That is both a user-visible inconsistency and a
live divergence from the documented shell-side theme contract.

## 4. The Settings UI omits the Neovide mono-font offset even though the theming schema supports it

The live theming schema and dependency map both treat Neovide as a first-class
mono-font-size offset target:

- `ThemeState` includes `neovide_mono_font_size_offset`
  (`themes/lib/schema.py:72-79`, `themes/lib/schema.py:91-96`)
- the orchestrator routes that key to the `neovide` target
  (`themes/lib/orchestrator.py:30-35`)

But the Quickshell settings host defines its editable offset-target list without
Neovide (`config/quickshell/popups/SettingsPopup.qml:52-58`). Both the live font
pane and the preset editor render their offset controls from that host-provided
list (`config/quickshell/popups/settings/SettingsFontsPane.qml:8-10`,
`config/quickshell/popups/settings/SettingsFontsPane.qml:172-273`,
`config/quickshell/popups/settings/SettingsPresetEditor.qml:932-1020`).

That leaves the Neovide offset supported by the theming backend but unreachable
from the shell UI. The schema, runtime target graph, and settings surface are no
longer aligned.
