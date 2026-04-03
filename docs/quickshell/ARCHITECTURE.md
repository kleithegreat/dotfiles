# Quickshell Architecture

The Quickshell config is centered on `config/quickshell/shell.qml:12-316`. The
root directory holds the shell entry point, the singleton runtime wrappers
(`AudioService.qml`, `BluetoothService.qml`, `NetworkService.qml`, `Theme.qml`,
and peers), popup coordination helpers (`PopupVisibility.qml`,
`PopupOverlayHost.qml`), and the standalone surfaces that are not part of popup
exclusivity (`TooltipWindow.qml`, `NotifDrawer.qml`, `PowerMenu.qml`). Bar
modules live under `config/quickshell/bar/`, managed popup implementations live
under `config/quickshell/popups/`, and reusable UI primitives live under
`config/quickshell/components/`.

One helper script still ships under `config/quickshell/scripts/dir-picker.py:1-42`,
but the current wallpaper-directory flow is implemented in QML by the settings
host and wallpaper pane instead (`config/quickshell/popups/SettingsPopup.qml:49-61`,
`config/quickshell/popups/SettingsPopup.qml:217-229`,
`config/quickshell/popups/SettingsPopup.qml:320-379`,
`config/quickshell/popups/settings/SettingsWallpaperPane.qml:190-446`).

## Shell Composition And IPC

`config/quickshell/shell.qml:12-316` is the session root. The top-level `Scope`
owns one `PopupVisibility` registry, defines `isRealMonitor()`, derives
`barMonitorName` from `Hyprland.monitors.values`, maps that monitor back to a
`barScreen` through `Hyprland.monitorFor(screen)`, listens to Hyprland raw
monitor events to refresh monitor state, forwards `doNotDisturb` and
`historyCount` from `NotificationService`, mounts `TooltipWindow`, one
single-screen bar `Loader`, the root notification popup stack, the shared audio
and brightness OSD window, the toast window, and one shared `PopupOverlayHost`
(`config/quickshell/shell.qml:16-235`).

Brightness OSD updates still enter through a side-channel rather than through
`BrightnessService`: `shell.qml` tails `/tmp/quickshell-brightness`, converts
the raw percentage to a gamma-corrected shell percentage, and forwards that to
`AudioService.showOsdState()` (`config/quickshell/shell.qml:126-136`). The audio
volume OSD and the brightness OSD therefore share the same OSD window and state
machine (`config/quickshell/shell.qml:138-174`,
`config/quickshell/AudioService.qml:17-22`,
`config/quickshell/AudioService.qml:66-115`).

There is still no explicit multi-output composition layer. Neither
`config/quickshell/shell.qml:18-79` nor `config/quickshell/bar/Bar.qml:7-68`
iterates over monitors or creates one bar per output. The current shell picks
the first real Hyprland monitor, maps it back to a matching `ShellScreen`,
refreshes monitor state on Hyprland `monitoradded`/`monitorremoved` events, and
recreates the single bar window when the real-monitor set disappears or
reappears.

The shell-wide IPC surface also lives in `config/quickshell/shell.qml:237-315`.
It exposes:

- `popups` for exclusive popup toggles
- `notifications` for DND and history clearing
- `settings` for opening the settings popup
- `audio` for mute and sink-status queries
- `vpn` for Mullvad and Tailscale actions
- `theme` for opening settings or spawning `themes/apply-theme`
- `toast` for in-shell info, warning, and error messages

## Popup Registry And Overlay Host

`config/quickshell/PopupVisibility.qml:3-39` is the authoritative exclusivity
registry for managed overlay popups. It stores one boolean per popup,
`closeAll()` clears the set, and `toggleExclusive()` enforces the rule that at
most one managed popup can be active at a time
(`config/quickshell/PopupVisibility.qml:12-38`).

`config/quickshell/PopupOverlayHost.qml:9-179` is the only overlay
`PanelWindow`. It derives `primaryPopup`, `scrimPopup`, and `overlayVisible`
from the mounted popup items, takes `WlrKeyboardFocus.Exclusive` while any
managed popup is visible, uses `HyprlandFocusGrab` to keep focus inside the
overlay, and provides shared click-outside dismissal for both transparent and
scrimmed popups (`config/quickshell/PopupOverlayHost.qml:13-121`).

The host mounts seven managed overlay surfaces:

- `CalendarPopup`
- `TrayPopup`
- `MprisPopup`
- `SettingsPopup`
- `QuickSettingsPopup`
- `NotifDrawer`
- `PowerMenu`

That mounting happens directly in `config/quickshell/PopupOverlayHost.qml:123-178`.
The only popup-to-popup handoff currently wired by the host is
`QuickSettingsPopup.onSettingsRequested -> popupVisibility.toggleSettings()`
(`config/quickshell/PopupOverlayHost.qml:155-162`).

Each managed popup still implements the same host-facing shape: `active`,
`close()`, `overlayVisible`, `panelItem`, `focusTarget`, and optional scrim
properties. The popup files own layout and animation, while the host owns the
actual layer-shell window and the exclusivity behavior. Current placements are:

- calendar: centered below the bar
  (`config/quickshell/popups/CalendarPopup.qml:113-145`)
- tray: top-right
  (`config/quickshell/popups/TrayPopup.qml:95-116`)
- MPRIS: top-left
  (`config/quickshell/popups/MprisPopup.qml:129-140`)
- quick settings: top-right
  (`config/quickshell/popups/QuickSettingsPopup.qml:127-143`)
- settings: centered fixed-size panel
  (`config/quickshell/popups/SettingsPopup.qml:732-811`)
- notification drawer: top-right
  (`config/quickshell/NotifDrawer.qml:107-136`)
- power menu: centered, and the only managed popup with a scrim
  (`config/quickshell/PowerMenu.qml:14-20`,
  `config/quickshell/PowerMenu.qml:52-60`)

The notification popup stack, OSD, toast window, and tooltip window do not
participate in popup exclusivity. They are independent `PanelWindow`s created by
`config/quickshell/shell.qml:82-232` and `config/quickshell/TooltipWindow.qml:6-48`.

## Service Layer

The root-level singleton set is:

- `AudioService.qml`
- `BluetoothService.qml`
- `BrightnessService.qml`
- `DisplayService.qml`
- `NetworkService.qml`
- `NotificationService.qml`
- `PowerProfileService.qml`
- `Theme.qml`
- `ToastService.qml`
- `TooltipService.qml`
- `VpnService.qml`

`config/quickshell/AudioService.qml:6-116` wraps PipeWire and owns the shared
volume, mute, sink-description, and OSD state used by the shell OSD window, the
bar volume module, the settings audio pane, and the `audio` IPC target
(`config/quickshell/shell.qml:138-174`,
`config/quickshell/shell.qml:263-273`,
`config/quickshell/bar/Volume.qml:12-57`,
`config/quickshell/popups/settings/SettingsAudioPane.qml:14-201`).

`config/quickshell/NotificationService.qml:6-306` wraps
`NotificationServer`. It owns both popup and history models, DND state,
tracked-notification dismissal, and one adaptive relative-time refresh timer.
That state drives the root notification popup stack, the notification drawer,
the bar bell via shell-level props, and the `notifications` IPC target
(`config/quickshell/shell.qml:53-55`,
`config/quickshell/shell.qml:82-124`,
`config/quickshell/NotifDrawer.qml:137-235`,
`config/quickshell/bar/Bell.qml:7-24`,
`config/quickshell/shell.qml:250-255`).

`config/quickshell/TooltipService.qml:4-53` and
`config/quickshell/ToastService.qml:5-98` are lightweight in-memory UI-state
singletons. `TooltipService` controls delayed show and linger behavior for
interactive modules, and `ToastService` owns a bounded toast queue with
duplicate suppression and level-specific durations
(`config/quickshell/TooltipWindow.qml:6-48`,
`config/quickshell/shell.qml:176-232`,
`config/quickshell/shell.qml:309-314`).

`config/quickshell/BluetoothService.qml:5-290` now has two refresh modes. The
full refresh path runs `show -> connected-device info -> paired devices -> all
devices -> scan` and is used by the Bluetooth pane
(`config/quickshell/BluetoothService.qml:25-35`,
`config/quickshell/BluetoothService.qml:103-229`,
`config/quickshell/popups/settings/SettingsBluetoothPane.qml:22-25`). The
lightweight summary path fetches powered state and the current connected device,
then keeps that summary fresh with a 10-second timer for bar and quick-settings
consumers (`config/quickshell/BluetoothService.qml:36-45`,
`config/quickshell/BluetoothService.qml:77-99`,
`config/quickshell/BluetoothService.qml:231-289`,
`config/quickshell/bar/Bluetooth.qml:7-46`,
`config/quickshell/popups/QuickSettingsPopup.qml:71-80`).

`config/quickshell/NetworkService.qml:6-1130` is the largest service boundary.
It owns:

- Wi-Fi radio state and toggling
  (`config/quickshell/NetworkService.qml:163-203`,
  `config/quickshell/NetworkService.qml:554-596`)
- Wi-Fi scanning, known-network loading, active-connection summary, and target
  connection state
  (`config/quickshell/NetworkService.qml:205-307`,
  `config/quickshell/NetworkService.qml:600-771`)
- diagnostics, speed test, captive portal, channel scan, DNS switching, and
  report export
  (`config/quickshell/NetworkService.qml:308-541`,
  `config/quickshell/NetworkService.qml:775-1130`)

The service now runs a 10-second summary timer for steady-state bar and quick
settings freshness, and a separate 2-second diagnostics timer while the
diagnostics subpane is active (`config/quickshell/NetworkService.qml:1113-1128`).
The bar network module, quick settings, and the full network pane all consume
that shared state rather than maintaining their own polling/parsing layer
(`config/quickshell/bar/Network.qml:7-47`,
`config/quickshell/popups/QuickSettingsPopup.qml:32-79`,
`config/quickshell/popups/settings/SettingsNetworkPane.qml:11-1099`).

`config/quickshell/VpnService.qml:5-442` wraps both Mullvad and Tailscale. In
addition to provider status, it now exposes Mullvad relay browsing and relay
selection APIs, keeps provider state fresh with a 15-second poll timer, and
refreshes status and selection after each provider action
(`config/quickshell/VpnService.qml:71-177`,
`config/quickshell/VpnService.qml:243-442`). The network pane consumes the full
surface, the quick-settings tile still summarizes Mullvad only, and the optional
bar VPN module summarizes both providers
(`config/quickshell/popups/settings/SettingsNetworkPane.qml:16-188`,
`config/quickshell/popups/settings/SettingsNetworkPane.qml:385-1099`,
`config/quickshell/popups/QuickSettingsPopup.qml:193-278`,
`config/quickshell/bar/Vpn.qml:7-44`).

`config/quickshell/BrightnessService.qml:5-159`,
`config/quickshell/DisplayService.qml:5-287`, and
`config/quickshell/PowerProfileService.qml:5-203` cover display-adjacent system
state:

- `BrightnessService` discovers the first backlight, watches
  `/sys/class/backlight/.../{brightness,max_brightness}` with `FileView`, and
  writes through `brightnessctl`
  (`config/quickshell/BrightnessService.qml:25-41`,
  `config/quickshell/BrightnessService.qml:54-79`,
  `config/quickshell/BrightnessService.qml:94-159`)
- `DisplayService` owns monitor refresh/apply state and Hyprsunset night-light
  state, with a 2-second poll for night-light status and explicit monitor
  refresh/apply commands
  (`config/quickshell/DisplayService.qml:34-137`,
  `config/quickshell/DisplayService.qml:139-287`)
- `PowerProfileService` wraps `powerprofilesctl` or `auto-cpufreq` for CPU
  profiles and `pkexec smbios-battery-ctl` for Dell charge limits
  (`config/quickshell/PowerProfileService.qml:46-52`,
  `config/quickshell/PowerProfileService.qml:90-203`)

Not every shell domain uses a repo-specific singleton. Current direct-upstream or
local exceptions are:

- `SettingsFocusTimePane`, which polls
  `$XDG_RUNTIME_DIR/focustime_state.json` every 3 seconds instead of using a
  shared singleton (`config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-72`)
- `Battery.qml`, which reads `Quickshell.Services.UPower` directly
  (`config/quickshell/bar/Battery.qml:11-35`)
- `QuickSettingsPopup` battery state, which also reads UPower directly
  (`config/quickshell/popups/QuickSettingsPopup.qml:35-50`)
- `MprisPopup` and `bar/Mpris.qml`, which read
  `Quickshell.Services.Mpris` directly
  (`config/quickshell/popups/MprisPopup.qml:40-66`,
  `config/quickshell/bar/Mpris.qml:13-19`)
- `TrayPopup`, which reads `Quickshell.Services.SystemTray`
  (`config/quickshell/popups/TrayPopup.qml:115-194`)
- `Workspaces.qml`, which reads `Quickshell.Hyprland`
  (`config/quickshell/bar/Workspaces.qml:10-21`)

## The Bar

`config/quickshell/bar/Bar.qml:7-68` defines the layer-shell bar surface itself,
and `config/quickshell/shell.qml:71-79` materializes it through a `Loader` that
activates only when Hyprland reports a real monitor and that monitor can be
mapped back to a `ShellScreen`. The loader forwards `screen`,
`popupVisibility`, `doNotDisturb`, and `historyCount`. The left cluster mounts
`Workspaces`, an optional divider, and `Mpris`; the center mounts `Clock`; and
the right cluster mounts `TrayExpand`, a rounded status pill with `Network`,
`Bluetooth`, `Volume`, and `Battery`, then `Bell`, then `Power`
(`config/quickshell/bar/Bar.qml:20-67`).

Bar clicks still route through the bar host rather than through a separate
command bus:

- `Mpris` toggles the MPRIS popup
- `Clock` toggles the calendar
- `TrayExpand` toggles the tray popup
- the status-pill modules toggle quick settings
- `Bell` toggles the notification drawer
- `Power` toggles the power menu

That wiring lives in `config/quickshell/bar/Bar.qml:23-30` and
`config/quickshell/bar/Bar.qml:37-66`.

The mounted modules now use a mix of shared services and direct upstream APIs:

- `Workspaces` -> `Quickshell.Hyprland`
  (`config/quickshell/bar/Workspaces.qml:7-44`)
- `Mpris` -> `Quickshell.Services.Mpris`
  (`config/quickshell/bar/Mpris.qml:13-62`)
- `Clock` -> local `Date` plus `Timer`
  (`config/quickshell/bar/Clock.qml:11-43`)
- `Network` -> `NetworkService`
  (`config/quickshell/bar/Network.qml:7-47`)
- `Bluetooth` -> `BluetoothService`
  (`config/quickshell/bar/Bluetooth.qml:7-46`)
- `Volume` -> `AudioService`
  (`config/quickshell/bar/Volume.qml:12-57`)
- `Battery` -> `UPower`
  (`config/quickshell/bar/Battery.qml:11-35`)
- `Bell` -> props passed in from `shell.qml`
  (`config/quickshell/bar/Bell.qml:7-24`,
  `config/quickshell/shell.qml:53-55`,
  `config/quickshell/shell.qml:76-78`)

Two extra modules still exist on disk but are not mounted by `Bar.qml`:
`config/quickshell/bar/Brightness.qml:6-62` and
`config/quickshell/bar/Vpn.qml:7-44`.

## The Settings Popup

`config/quickshell/popups/SettingsPopup.qml:10-926` is both popup implementation
and settings host. The root `FocusScope` owns:

- the current theme snapshot
- discovered colors, presets, wallpapers, and directory entries
- category names, icons, and the system/appearance split
- mono-font offset metadata
- Hyprland option metadata, draft values, dirty queues, and notification state
- preset mutation status

That host state lives in `config/quickshell/popups/SettingsPopup.qml:43-95`.

On open, the popup loads the theme snapshot and supporting lists, then refreshes
the live system services consumed by service-direct panes
(`config/quickshell/popups/SettingsPopup.qml:107-156`). Data loading currently
uses local `Process` helpers:

- `stateProc` reads `themes/state.json`
- `listColorsProc` shells out through `jq` over `themes/colors/*.json`
- `listPresetsProc` shells out through `jq` over `themes/presets/*.json`
- `listWallpapersProc` lists the active wallpaper directory
- `listDirectoriesProc` enumerates subdirectories for the wallpaper browser

Those loaders live in `config/quickshell/popups/SettingsPopup.qml:158-229`.

The settings host currently uses three write paths:

- generic theme writes: `applyProc`, `runSet()`, and `runPreset()`
  (`config/quickshell/popups/SettingsPopup.qml:633-655`)
- preset save/delete commands: `presetCommandProc`,
  `runSavePreset()`, and `runDeletePreset()`
  (`config/quickshell/popups/SettingsPopup.qml:600-631`,
  `config/quickshell/popups/SettingsPopup.qml:657-681`)
- Hyprland appearance writes: a debounced dirty-value queue drained by
  `hyprApplyProc` and `hyprWriteTimer`, with `busctl`-backed desktop
  notifications (`config/quickshell/popups/SettingsPopup.qml:231-279`,
  `config/quickshell/popups/SettingsPopup.qml:381-598`)

The rendered panel is still a fixed `700x500` centered loader with a left
sidebar, divider, and one detail loader on the right
(`config/quickshell/popups/SettingsPopup.qml:732-811`). Pane ownership is split
into two models:

- service-direct panes instantiated bare in the detail loader:
  `SettingsNetworkPane`, `SettingsBluetoothPane`, `SettingsAudioPane`,
  `SettingsDisplayPane`, `SettingsPowerPane`, and `SettingsFocusTimePane`
  (`config/quickshell/popups/SettingsPopup.qml:814-841`)
- host-driven panes that receive host props and callbacks:
  `SettingsPresetsPane`, `SettingsColorsPane`, `SettingsFontsPane`,
  `SettingsWallpaperPane`, `SettingsIconsPane`, and `SettingsHyprlandPane`
  (`config/quickshell/popups/SettingsPopup.qml:844-924`)

Three current pane details matter for understanding the live settings system:

- the sidebar is now scrollable through `WheelFlickable`
  (`config/quickshell/popups/settings/SettingsSidebar.qml:24-258`)
- the display pane now uses `InlineSelect` for monitor resolution and refresh
  selection instead of open-ended chip flows
  (`config/quickshell/popups/settings/SettingsDisplayPane.qml:17-124`,
  `config/quickshell/popups/settings/SettingsDisplayPane.qml:240-283`)
- the presets pane and preset editor are their own sub-system with host-driven
  editing, partial-preset saves, and card summaries
  (`config/quickshell/popups/settings/SettingsPresetsPane.qml:22-345`,
  `config/quickshell/popups/settings/SettingsPresetsPane.qml:347-530`,
  `config/quickshell/popups/settings/SettingsPresetEditor.qml:6-1571`)

## Theme Integration Layer

`config/quickshell/Theme.qml:5-167` is the shell-facing theme facade. It watches
`~/.config/quickshell/GeneratedTheme.json` with `FileView.watchChanges`,
reparses JSON on load and on file changes, exposes generated color keys and font
fields, and keeps all layout, geometry, and animation constants as shell-owned
values (`config/quickshell/Theme.qml:8-27`,
`config/quickshell/Theme.qml:29-167`).

The Quickshell theming target is `themes/lib/targets/quickshell.py:7-49`. It is
a `standalone` target that writes `GeneratedTheme.json`, maps the theming
schema's `bg_dim/cyan` names into Quickshell's `bg0_h/aqua` names, and writes
the shell font families plus fixed `size/sizeSmall/sizeLarge` values
(`themes/lib/targets/quickshell.py:13-49`).

Theme mutation currently enters Quickshell through two different code paths:

- the settings host, which shells out to `themes/apply-theme` and refreshes its
  own `themeState` on successful exit
  (`config/quickshell/popups/SettingsPopup.qml:633-655`)
- the shell IPC handler, which spawns `themes/apply-theme` through a separate
  root-level `Process`
  (`config/quickshell/shell.qml:294-306`)

On the CLI side, `themes/apply-theme` writes `themes/state.json`, computes the
affected target set through `targets_for_key()`, and applies either that subset
or the full target registry depending on the subcommand
(`themes/apply-theme:228-297`,
`themes/lib/orchestrator.py:14-46`,
`themes/lib/orchestrator.py:173-220`).

## Component Library And Conventions

`config/quickshell/components/` is still a small primitive layer rather than a
full design system. The main shared building blocks are:

- `HoverLayer.qml` for click, hover, and pressed-state overlays
  (`config/quickshell/components/HoverLayer.qml:4-68`)
- `WheelFlickable.qml` for wheel scrolling with controlled overshoot and rebound
  (`config/quickshell/components/WheelFlickable.qml:4-66`)
- `InlineSelect.qml` for bounded dropdown-like selection with keyboard support
  (`config/quickshell/components/InlineSelect.qml:4-260`)
- `StyledText.qml`, `StyledRect.qml`, `Anim.qml`, `CAnim.qml`, and
  `ToggleSwitch.qml` for theme-default text, rectangles, animations, and toggle
  controls

Most shared components import `..` as `Root` and read `Root.Theme` directly, so
theme access remains implicit rather than being threaded through explicit style
props (`config/quickshell/components/HoverLayer.qml:1-21`,
`config/quickshell/components/InlineSelect.qml:1-18`).

## Runtime Assumptions And Paths

`scripts/launch-quickshell.sh:1-30` derives the repo root from the script
location, reads `${XDG_CONFIG_HOME:-$HOME/.config}/hypr/cursor.conf`, exports
`XCURSOR_THEME`, `XCURSOR_SIZE`, and `HYPRCURSOR_THEME` from that file, supports
`--print-env`, and then executes `quickshell -p "$repo_dir/config/quickshell"`.

The current shell still relies on hardcoded absolute paths for theme state and
theme commands:

- `Theme.qml` watches `/home/kevin/.config/quickshell/GeneratedTheme.json`
  (`config/quickshell/Theme.qml:9-15`)
- `SettingsPopup` reads `themes/state.json`, enumerates `themes/colors/`,
  `themes/presets/`, and wallpapers under `/home/kevin/repos/dotfiles/...`, and
  shells out to `/home/kevin/repos/dotfiles/themes/apply-theme`
  (`config/quickshell/popups/SettingsPopup.qml:50-61`,
  `config/quickshell/popups/SettingsPopup.qml:158-229`,
  `config/quickshell/popups/SettingsPopup.qml:537-543`,
  `config/quickshell/popups/SettingsPopup.qml:608-629`,
  `config/quickshell/popups/SettingsPopup.qml:647-654`)
- `shell.qml` uses the same absolute `apply-theme` path for the `theme` IPC
  target (`config/quickshell/shell.qml:294-306`)

The runtime environment also assumes:

- `/tmp/quickshell-brightness` exists and is updated by an external producer
  (`config/quickshell/shell.qml:126-136`)
- a backlight is discoverable under `/sys/class/backlight`
  (`config/quickshell/BrightnessService.qml:104-141`)
- `$XDG_RUNTIME_DIR/focustime_state.json` exists when the focus-time daemon is
  running (`config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-72`)
- CLI tools such as `nmcli`, `bluetoothctl`, `hyprctl`, `hyprsunset`,
  `mullvad`, `tailscale`, `brightnessctl`, `powerprofilesctl`, `pkexec`,
  `smbios-battery-ctl`, `iw`, `ping`, `curl`, `wl-copy`, `busctl`, and
  `dbus-monitor` are on `PATH`, as shown in the service/process definitions
  cited above
