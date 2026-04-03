# Quickshell Architecture

## Scope

Current implementation map for `config/quickshell/` and its theme/runtime
integration as of 2026-04-03.

## Shell Topology

| Component | Current role | Notes |
| --- | --- | --- |
| `shell.qml` | Session root for monitor selection, root windows, shared props, and IPC | Single-bar model on the first real monitor; see `docs/quickshell/QUIRKS.md` for output-churn behavior |
| `PopupVisibility.qml` | Exclusivity registry for managed overlay popups | One boolean per popup plus shared toggle helpers |
| `PopupOverlayHost.qml` | Only overlay `PanelWindow` for managed popups | Owns focus, outside-click dismissal, and scrim handling |
| `bar/Bar.qml` | Persistent chrome and popup toggles | Materialized through a loader only when a real monitor is available |
| Root transient windows | Notification popup stack, OSD, toast window, tooltip window | Outside managed-popup exclusivity |

Managed popups mounted by the overlay host remain:

`CalendarPopup`, `TrayPopup`, `MprisPopup`, `QuickSettingsPopup`,
`SettingsPopup`, `NotifDrawer`, and `PowerMenu`.

## Service Layer

| Service | Shared responsibility | Primary consumers |
| --- | --- | --- |
| `AudioService.qml` | Volume, mute, sink summary, shared OSD state | Bar volume, audio pane, shell OSD, IPC |
| `BluetoothService.qml` | Powered state, summary device data, full device/pairing flows | Bar Bluetooth, quick settings, Bluetooth pane |
| `BrightnessService.qml` | Backlight discovery, watch, and writes | Display pane; shell brightness OSD still enters through `/tmp/quickshell-brightness` |
| `DisplayService.qml` | Monitor refresh/apply and direct `hyprsunset` state | Display pane |
| `NetworkService.qml` | Wi-Fi summary, scans, known networks, diagnostics, DNS, captive portal, reporting | Bar network, quick settings, network pane |
| `NotificationService.qml` | Popup/history models, DND, dismissal, relative-time refresh | Root notifications, drawer, bar bell, IPC |
| `PowerProfileService.qml` | CPU profiles and supported battery controls | Power pane |
| `Theme.qml` | Shell-facing facade over generated theme JSON | Imported throughout shell components |
| `ToastService.qml` | Bounded toast queue | Shell toast window, IPC |
| `TooltipService.qml` | Hover/linger tooltip state | Tooltip window and interactive modules |
| `VpnService.qml` | Mullvad and Tailscale status plus relay selection | Optional bar VPN, quick settings tile, network pane |

Direct-upstream or local exceptions:

- Battery state still comes from `Quickshell.Services.UPower`.
- MPRIS, system tray, and workspace state still use upstream Quickshell
  services directly.
- Focus Time still polls `$XDG_RUNTIME_DIR/focustime_state.json` inside its
  pane; see `docs/focus-time/SPEC.md`.
- The shell brightness OSD still reads `/tmp/quickshell-brightness`, which is
  written by `desktopctl brightness` helpers launched from Hyprland config.

## Settings System

| Area | Current implementation |
| --- | --- |
| Host-owned data | Theme snapshot, colors, presets, wallpapers, directories, icon/font choices, and Hyprland appearance draft state |
| Host loaders | `Process` helpers call `desktopctl theme status --json`, `desktopctl theme list-schemes --json`, `desktopctl theme list-presets --json`, and shell commands for wallpaper/directory browsing |
| Service-driven panes | Network, Bluetooth, Audio, Display, Power, Focus Time |
| Host-driven panes | Presets, Colors, Fonts, Wallpaper, Icons, Hyprland |
| General theme writes | `desktopctl theme set` and `desktopctl theme preset` |
| Preset writes | `desktopctl theme save-preset` and `desktopctl theme delete-preset` |
| Hyprland appearance writes | Debounced queue of `desktopctl theme set hypr_* ...` writes with desktop-notification feedback |

The main host wiring lives in
`config/quickshell/popups/SettingsPopup.qml:140-223` and
`config/quickshell/popups/SettingsPopup.qml:524-700`.

## Theme Integration

| Piece | Current role |
| --- | --- |
| `Theme.qml` | Watches `~/.config/quickshell/GeneratedTheme.json`, reparses on change, and exposes generated colors/fonts plus shell-owned layout constants |
| `desktopctl/src/theme/targets/quickshell.rs` | Writes `GeneratedTheme.json` and maps theming names into Quickshell's `bg0_h` / `aqua` naming |
| Settings host | Runs `desktopctl theme ...`, then reloads its theme snapshot on success |
| Shell IPC | Provides a second command path into `desktopctl theme ...` through `theme.apply` |

`Theme.qml` still keeps hardcoded Gruvbox Dark fallbacks for the generated JSON
surface in `config/quickshell/Theme.qml:29-69`.

## Runtime Assumptions

- `desktopctl` is on `PATH` for every Quickshell `Process` that invokes theme
  commands.
- `/tmp/quickshell-brightness` exists and is updated by an external producer.
- A writable `~/.config/quickshell/GeneratedTheme.json` exists beside the
  Home Manager-managed Quickshell tree.
- A backlight is discoverable under `/sys/class/backlight`.
- `$XDG_RUNTIME_DIR/focustime_state.json` exists when the focus-time daemon is
  running.
- CLI tools such as `nmcli`, `bluetoothctl`, `hyprctl`, `hyprsunset`,
  `brightnessctl`, `mullvad`, `tailscale`, `busctl`, and related helpers are on
  `PATH`.
