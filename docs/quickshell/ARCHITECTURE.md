# Quickshell Architecture

## Scope

Current implementation map for `config/quickshell/` and its theme/runtime
integration as of 2026-04-08.

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

## Shared Interaction Primitives

| Primitive | Current role | Evidence |
| --- | --- | --- |
| `components/WheelFlickable.qml` | Shared wheel + drag scroll surface for settings panes, dropdown option lists, notification history, Wi-Fi lists, and Quick Settings overflow. It now uses one elastic overscroll model (`FollowBoundsBehavior` + `DragAndOvershootBounds`) and lets `returnToBounds()` handle rebound instead of timer-driven snap-back bookkeeping. | `config/quickshell/components/WheelFlickable.qml:4-72`, `config/quickshell/popups/QuickSettingsPopup.qml:189-215`, `config/quickshell/NotifDrawer.qml:223-226`, `config/quickshell/popups/settings/SettingsSidebar.qml:130-140` |
| `components/HoverLayer.qml` | Shared pressed/hover visual layer for shell buttons and tile hit areas. It stays pointer-only and does not introduce an extra keyboard interaction contract on top of each caller. | `config/quickshell/components/HoverLayer.qml:4-68`, `config/quickshell/popups/QuickSettingsPopup.qml:418-440`, `config/quickshell/PowerMenu.qml:112-134` |
| `components/ToggleSwitch.qml` | Shared boolean control with mouse-driven activation plus disabled/pending opacity states. | `config/quickshell/components/ToggleSwitch.qml:4-42` |
| `components/InlineDropdown.qml` | Compact one-of-many selector with pointer-driven expansion, animated dropdown height, and `WheelFlickable`-backed option scrolling. | `config/quickshell/components/InlineDropdown.qml:4-188` |
| `components/InlineSelect.qml` | Card-style one-of-many selector with the same pointer-first contract as `InlineDropdown`, plus current-option auto-scroll inside the shared flickable list. | `config/quickshell/components/InlineSelect.qml:4-251` |

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

Write-oriented services now also own their optimistic/pending state locally
instead of waiting for subprocess completion before updating the touched
control. `NetworkService.qml` stages Wi-Fi radio, disconnect, forget, and DNS
changes before `nmcli` completes; `BluetoothService.qml` stages power and
disconnect actions; `VpnService.qml` stages Mullvad/Tailscale connect-disconnect
intent until the next real status refresh confirms it; and
`DisplayService.qml` stages night-light mode / target temperature while
preserving a rollback snapshot for failures.

## Settings System

| Area | Current implementation |
| --- | --- |
| Host-owned data | Theme snapshot, colors, presets, wallpapers, directories, icon/font choices, and Hyprland appearance draft state |
| Host loaders | `Process` helpers call `desktopctl theme status --json`, `desktopctl theme list-schemes --json`, `desktopctl theme list-presets --json`, and shell commands for wallpaper/directory browsing |
| Service-driven panes | Network, Bluetooth, Audio, Display, Power, Notifications, Focus Time |
| Host-driven panes | Presets, Colors, Fonts, Wallpaper, Icons, Hyprland |
| Category gating | `HostCapabilities.qml:1-40` plus `config/quickshell/popups/SettingsPopup.qml:61-68`, `config/quickshell/popups/SettingsPopup.qml:796-859` hide the Power category when neither battery nor power-profile support is present |
| General theme writes | `desktopctl theme set` and `desktopctl theme preset`, with host-local staging for individual `set` writes before process exit |
| Preset writes | `desktopctl theme save-preset` and `desktopctl theme delete-preset` |
| Hyprland appearance writes | Debounced queue of `desktopctl theme set hypr_* ...` writes with desktop-notification feedback |

Quick Settings expand affordances are consumed by the overlay host:
`config/quickshell/PopupOverlayHost.qml:13-17` closes the current popup,
selects the target settings category, and opens the full Settings popup, while
`config/quickshell/PopupOverlayHost.qml:167-172` maps Wi-Fi, Bluetooth, VPN,
DND, and power-profile expand requests to concrete category indices.

`SettingsPopup.qml` is now responsible for three additional shell-side polish
behaviors:

- Responsive panel sizing instead of the old fixed `700x500` shell:
  `config/quickshell/popups/SettingsPopup.qml:103-114`, `config/quickshell/popups/SettingsPopup.qml:841-955`.
- Optimistic theme-state staging and rollback for `desktopctl theme set`
  writes: `config/quickshell/popups/SettingsPopup.qml:177-205`,
  `config/quickshell/popups/SettingsPopup.qml:703-743`.
- Passing wallpaper-directory metadata into the preset editor so wallpaper
  fields can validate and commit separately from freeform typing:
  `config/quickshell/popups/SettingsPopup.qml:958-1087`,
  `config/quickshell/popups/settings/SettingsPresetsPane.qml:6-38`,
  `config/quickshell/popups/settings/SettingsPresetsPane.qml:312-330`,
  `config/quickshell/popups/settings/SettingsPresetEditor.qml:589-755`.

The settings sidebar remains click-driven. It uses the shared `WheelFlickable`
for scrolling and `HoverLayer` for category hit targets, but it does not add a
custom tab-order or focused-outline layer on top of the popup shell. Evidence:
`config/quickshell/popups/settings/SettingsSidebar.qml:1-247`.

`SettingsFocusTimePane.qml` still consumes the JSON summary directly, but it no
longer paints charts from placeholder geometry on first load. The pane waits for
the first fresh payload, then enables bar/heatmap/app-width animations only
after `chartVisualsReady` has been primed. Evidence:
`config/quickshell/popups/settings/SettingsFocusTimePane.qml:15-32`,
`config/quickshell/popups/settings/SettingsFocusTimePane.qml:63-94`,
`config/quickshell/popups/settings/SettingsFocusTimePane.qml:218-434`.

Shell chrome remains deliberately pointer-first after the frontend-polish pass.
Quick Settings tiles and footer actions, bar modules, and power-menu actions
all use mouse/touch hit areas plus hover/pressed feedback, without repo-local
tab stops or focus outlines layered onto those surfaces. Evidence:
`config/quickshell/popups/QuickSettingsPopup.qml:232-440`,
`config/quickshell/bar/Bar.qml:17-73`,
`config/quickshell/bar/Clock.qml:1-117`,
`config/quickshell/bar/Mpris.qml:1-62`,
`config/quickshell/bar/Workspaces.qml:1-38`,
`config/quickshell/PowerMenu.qml:58-140`.

## Theme Integration

| Piece | Current role |
| --- | --- |
| `Theme.qml` | Watches `~/.config/quickshell/GeneratedTheme.json`, reparses on change, and exposes generated colors/fonts plus shell-owned layout constants |
| `desktopctl/src/theme/targets/quickshell.rs` | Writes `GeneratedTheme.json`, maps theming names into Quickshell's `bg0_h` / `aqua` naming, emits both mono and system font families, and derives shell font sizes from `ThemeState.font_size` |
| Recursive tree exception | `config/quickshell/GeneratedTheme.json` is committed in the repo as a bootstrap snapshot because Home Manager deploys the whole `config/quickshell/` tree recursively; activation/runtime theme applies still overwrite the live `~/.config/quickshell/GeneratedTheme.json` path |
| Settings host | Runs `desktopctl theme ...`, stages optimistic `themeState` updates for individual `set` writes, then reloads or rolls back its local snapshot when the process exits |
| Shell IPC | Provides a second command path into `desktopctl theme ...` through `theme.apply`, with shell-style tokenization and error toasts on failure |

`Theme.qml` still keeps hardcoded Gruvbox Dark fallbacks for the generated JSON
surface in `config/quickshell/Theme.qml:29-69`.

## Popup Surfaces

The async popup surfaces now keep their host containers sized from placeholder
geometry while the loaded content fades/scales in, instead of snapping the host
to the final implicit height before the styled content appears. The current
pattern is shared across Quick Settings, Settings, the notification drawer, and
Calendar:

- `config/quickshell/popups/QuickSettingsPopup.qml:32-35`,
  `config/quickshell/popups/QuickSettingsPopup.qml:152-210`
- `config/quickshell/popups/SettingsPopup.qml:841-955`
- `config/quickshell/NotifDrawer.qml:44-45`,
  `config/quickshell/NotifDrawer.qml:145-190`
- `config/quickshell/popups/CalendarPopup.qml:18-19`,
  `config/quickshell/popups/CalendarPopup.qml:138-183`

`NotifDrawer.qml` also records the largest already-rendered history `entryId`
and only runs the staggered entrance animation for newly inserted history items,
avoiding the old “history settles again on every open” behavior:
`config/quickshell/NotifDrawer.qml:65-75`,
`config/quickshell/NotifDrawer.qml:227-254`.

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
