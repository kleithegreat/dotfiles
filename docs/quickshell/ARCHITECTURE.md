# Quickshell Architecture

## Scope

Current implementation map for `config/quickshell/` and its theme/runtime
integration as of 2026-04-07.

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
| `BrightnessService.qml` | Backlight discovery, file watching, and direct `brightnessctl` writes for the Display pane | Display pane and any brightness slider UI |
| `DisplayService.qml` | Monitor refresh/apply and daemon-backed night-light status / override requests | Display pane |
| `HostCapabilities.qml` | Detects Wi-Fi, battery, and power-profile capabilities | Settings host category visibility and power-pane availability |
| `NetworkService.qml` | Wi-Fi summary, scans, known networks, diagnostics, DNS, captive portal, reporting | Bar network, quick settings, network pane |
| `NotificationService.qml` | Popup/history models, DND, dismissal, relative-time refresh | Root notifications, drawer, bar bell, Notifications settings pane, IPC |
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
- The shell brightness OSD no longer reads `/tmp/quickshell-brightness`.
  `config/quickshell/shell.qml:212-219` exposes an IPC handler for brightness
  OSD events, and `desktopctl/src/brightness.rs:149-160` drives it with
  `qs -p <repo>/config/quickshell ipc call brightness osd ...`.

## Settings System

| Area | Current implementation |
| --- | --- |
| Host-owned data | Theme snapshot, colors, presets, wallpapers, directories, icon/font choices, and Hyprland appearance draft state |
| Host loaders | `Process` helpers call `desktopctl theme status --json`, `desktopctl theme list-schemes --json`, `desktopctl theme list-presets --json`, and shell commands for wallpaper/directory browsing |
| Service-driven panes | Network, Bluetooth, Audio, Display, Power, Notifications, Focus Time |
| Host-driven panes | Presets, Colors, Fonts, Wallpaper, Icons, Hyprland |
| Category gating | `HostCapabilities.qml:1-40` plus `config/quickshell/popups/SettingsPopup.qml:61-68`, `config/quickshell/popups/SettingsPopup.qml:796-859` hide the Power category when neither battery nor power-profile support is present |
| General theme writes | `desktopctl theme set` and `desktopctl theme preset` |
| Preset writes | `desktopctl theme save-preset` and `desktopctl theme delete-preset` |
| Hyprland appearance writes | Debounced queue of `desktopctl theme set hypr_* ...` writes with desktop-notification feedback |

Quick Settings expand affordances are consumed by the overlay host:
`config/quickshell/PopupOverlayHost.qml:13-17` closes the current popup,
selects the target settings category, and opens the full Settings popup, while
`config/quickshell/PopupOverlayHost.qml:167-172` maps Wi-Fi, Bluetooth, VPN,
DND, and power-profile expand requests to concrete category indices.

## Theme Integration

| Piece | Current role |
| --- | --- |
| `Theme.qml` | Watches `~/.config/quickshell/GeneratedTheme.json`, reparses on change, and exposes generated colors/fonts plus shell-owned layout constants |
| `desktopctl/src/theme/targets/quickshell.rs` | Writes `GeneratedTheme.json`, maps theming names into Quickshell's `bg0_h` / `aqua` naming, emits both mono and system font families, and derives shell font sizes from `ThemeState.font_size` |
| Recursive tree exception | `config/quickshell/GeneratedTheme.json` is committed in the repo as a bootstrap snapshot because Home Manager deploys the whole `config/quickshell/` tree recursively; activation/runtime theme applies still overwrite the live `~/.config/quickshell/GeneratedTheme.json` path |
| Settings host | Runs `desktopctl theme ...`, then reloads its theme snapshot on success |
| Shell IPC | Provides a second command path into `desktopctl theme ...` through `theme.apply`, with shell-style tokenization and error toasts on failure |

`Theme.qml` still keeps hardcoded Gruvbox Dark fallbacks for the generated JSON
surface in `config/quickshell/Theme.qml:29-69`.

## Runtime Assumptions

- `desktopctl` is on `PATH` for every Quickshell `Process` that invokes theme
  commands.
- A writable `~/.config/quickshell/GeneratedTheme.json` exists beside the
  Home Manager-managed Quickshell tree; it may begin as the committed repo
  snapshot and then be overwritten by `desktopctl theme sync`.
- Keyboard-driven brightness OSD updates depend on `qs` plus repo-root
  resolution in `desktopctl`, not on a temp file.
- A backlight is discoverable under `/sys/class/backlight` for the brightness
  slider path to be usable.
- `$XDG_RUNTIME_DIR/focustime_state.json` exists when the focus-time daemon is
  running.
- CLI tools such as `nmcli`, `bluetoothctl`, `hyprctl`, `brightnessctl`,
  `mullvad`, `tailscale`, `busctl`, and related helpers are on `PATH`.
