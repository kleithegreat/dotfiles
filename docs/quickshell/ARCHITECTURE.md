# Quickshell Architecture

## Scope

Current implementation map for `config/quickshell/` and its theme/runtime
integration as of 2026-04-02.

## Shell Topology

| Component | Current role | Notes |
| --- | --- | --- |
| `shell.qml` | Session root for monitor selection, root windows, shared props, and IPC | Single-bar model on the first real monitor; see `docs/quickshell/QUIRKS.md` for output-churn behavior |
| `PopupVisibility.qml` | Exclusivity registry for managed overlay popups | One boolean per popup plus shared toggle helpers |
| `PopupOverlayHost.qml` | Only overlay `PanelWindow` for managed popups | Owns focus, outside-click dismissal, and scrim handling |
| `bar/Bar.qml` | Persistent chrome and popup toggles | Materialized through a loader only when a real monitor is available |
| Root transient windows | Notification popup stack, OSD, toast window, tooltip window | Outside managed-popup exclusivity |

Managed popups mounted by the overlay host:

| Popup | Role |
| --- | --- |
| `CalendarPopup` | Calendar surface |
| `TrayPopup` | System tray details |
| `MprisPopup` | Media control surface |
| `QuickSettingsPopup` | Shallow toggle and summary surface |
| `SettingsPopup` | Full settings host |
| `NotifDrawer` | Retained notification history |
| `PowerMenu` | Modal-like power surface with optional scrim |

## Service Layer

| Service | Shared responsibility | Primary consumers |
| --- | --- | --- |
| `AudioService.qml` | Volume, mute, sink summary, shared OSD state | Bar volume, audio pane, shell OSD, IPC |
| `BluetoothService.qml` | Powered state, summary device data, full device/pairing flows | Bar Bluetooth, quick settings, Bluetooth pane |
| `BrightnessService.qml` | Backlight discovery, watch, and writes | Display pane; shell brightness OSD still enters through `/tmp/quickshell-brightness` |
| `DisplayService.qml` | Monitor refresh/apply and Hyprsunset state | Display pane |
| `NetworkService.qml` | Wi-Fi summary, scans, known networks, diagnostics, DNS, captive portal, reporting | Bar network, quick settings, network pane |
| `NotificationService.qml` | Popup/history models, DND, dismissal, relative-time refresh | Root notifications, drawer, bar bell, IPC |
| `PowerProfileService.qml` | CPU profiles and supported battery controls | Power pane |
| `Theme.qml` | Shell-facing facade over generated theme JSON | Imported throughout shell components |
| `ToastService.qml` | Bounded toast queue | Shell toast window, IPC |
| `TooltipService.qml` | Hover/linger tooltip state | Tooltip window and interactive modules |
| `VpnService.qml` | Mullvad and Tailscale status plus relay selection | Optional bar VPN, quick settings tile, network pane |

Direct-upstream or local exceptions still bypass repo-specific services:

- Battery state comes from `Quickshell.Services.UPower`.
- MPRIS, system tray, and workspace state use upstream Quickshell services
  directly.
- Focus Time polls `$XDG_RUNTIME_DIR/focustime_state.json` inside its pane;
  see `docs/focus-time/SPEC.md` for the JSON summary contract and runtime
  paths.
- The shell brightness OSD reads `/tmp/quickshell-brightness` via a long-lived
  `tail -F` process in `shell.qml`; that file is written by external producers
  (`autostart.conf`, `brightness-step.sh`, `hypridle.conf`) and is separate
  from `BrightnessService.qml`, which reads sysfs directly.

## Settings System

| Area | Current implementation |
| --- | --- |
| Host-owned data | Theme snapshot, colors, presets, wallpapers, directories, icon/font choices, Hyprland appearance draft state |
| Host loaders | `Process` helpers read `themes/state.json`, enumerate palettes/presets, and list wallpaper directories |
| Service-driven panes | Network, Bluetooth, Audio, Display, Power, Focus Time |
| Host-driven panes | Presets, Colors, Fonts, Wallpaper, Icons, Hyprland |
| General theme writes | `apply-theme set` and `apply-theme preset` |
| Preset writes | `apply-theme save-preset` and `apply-theme delete-preset` |
| Hyprland appearance writes | Debounced queue of `hypr_*` state updates with desktop-notification feedback |

The popup itself remains a fixed-size host with a scrollable sidebar and one
detail loader.

## Theme Integration

| Piece | Current role |
| --- | --- |
| `Theme.qml` | Watches `~/.config/quickshell/GeneratedTheme.json`, reparses on change, and exposes generated colors/fonts plus shell-owned layout constants |
| `themes/lib/targets/quickshell.py` | Writes `GeneratedTheme.json` and maps theming names into Quickshell's `bg0_h`/`aqua` naming |
| Settings host | Runs `themes/apply-theme`, then reloads its theme snapshot on success |
| Shell IPC | Provides a second command path into `themes/apply-theme` |

Theme-related path handling is intentionally absolute in the current shell setup;
see `docs/quickshell/QUIRKS.md`.

## Runtime Assumptions

- `/tmp/quickshell-brightness` exists and is updated by an external producer.
- A writable generated theme file exists beside the Home Manager-managed
  Quickshell tree.
- A backlight is discoverable under `/sys/class/backlight`.
- `$XDG_RUNTIME_DIR/focustime_state.json` exists when the focus-time daemon is
  running.
- CLI tools such as `nmcli`, `bluetoothctl`, `hyprctl`, `hyprsunset`,
  `brightnessctl`, `mullvad`, `tailscale`, `busctl`, and related helpers are on
  `PATH`.
