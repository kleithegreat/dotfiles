# Quickshell Architecture

## Scope

Current implementation map for `config/quickshell/` and its theme/runtime
integration as of 2026-04-15.

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
| `components/WheelFlickable.qml` | Shared wheel + drag scroll surface for settings panes, dropdown option lists, notification history, Wi-Fi lists, and Quick Settings overflow. It now uses one elastic overscroll model (`FollowBoundsBehavior` + `DragAndOvershootBounds`) and lets `returnToBounds()` handle rebound instead of timer-driven snap-back bookkeeping. | `config/quickshell/components/WheelFlickable.qml`, plus its use sites in `config/quickshell/popups/QuickSettingsPopup.qml`, `config/quickshell/NotifDrawer.qml`, and `config/quickshell/popups/settings/SettingsSidebar.qml` |
| `components/HoverLayer.qml` | Shared pressed/hover visual layer for shell buttons and tile hit areas. It stays pointer-only and does not introduce an extra keyboard interaction contract on top of each caller. | `config/quickshell/components/HoverLayer.qml`, plus its use in `config/quickshell/popups/QuickSettingsPopup.qml` and `config/quickshell/PowerMenu.qml` |
| `components/ToggleSwitch.qml` | Shared boolean control with mouse-driven activation plus disabled/pending opacity states. | `config/quickshell/components/ToggleSwitch.qml` |
| `components/ColorSchemeCard.qml` and `components/ColorSchemeCards.qml` | Shared responsive scheme-preview cards for the Colors pane and preset editor. They consume `colorFamilies`, adapt the column count to available width, and highlight the active scheme without falling back to dropdown-only selection. | `config/quickshell/components/ColorSchemeCard.qml`, `config/quickshell/components/ColorSchemeCards.qml`, `config/quickshell/popups/settings/SettingsColorsPane.qml`, and `config/quickshell/popups/settings/SettingsPresetEditor.qml` |
| `components/InlineDropdown.qml` | Compact one-of-many selector with pointer-driven expansion, animated dropdown height, and `WheelFlickable`-backed option scrolling. | `config/quickshell/components/InlineDropdown.qml` |
| `components/InlineSelect.qml` | Card-style one-of-many selector with the same pointer-first contract as `InlineDropdown`, plus current-option auto-scroll inside the shared flickable list. | `config/quickshell/components/InlineSelect.qml` |

## Service Layer

| Service | Shared responsibility | Primary consumers |
| --- | --- | --- |
| `AudioService.qml` | Volume, mute, sink summary, shared OSD state | Bar volume, audio pane, shell OSD, IPC |
| `BluetoothService.qml` | Powered state, summary device data, full device/pairing flows | Bar Bluetooth, quick settings, Bluetooth pane |
| `BrightnessService.qml` | Backlight discovery, file watching, and direct `brightnessctl` writes for the Display pane | Display pane and any brightness slider UI |
| `DisplayService.qml` | Monitor refresh/apply and daemon-backed night-light status / override requests | Display pane |
| `HostCapabilities.qml` | Detects laptop-chassis, Wi-Fi, battery, power-profile, and fingerprint-reader capabilities | Settings host category visibility plus power/fingerprint pane availability |
| `IdleInhibitService.qml` | Holds a transient `systemd-inhibit --what=idle` process so hypridle pauses its timers while the shell toggle is active | Quick Settings idle-inhibit tile |
| `NetworkService.qml` | Active network summary for Wi-Fi or ethernet via the default-route interface, Wi-Fi scans/known networks, active-transport diagnostics, DNS, captive portal, reporting | Bar network, quick settings, network pane |
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
- The calendar weather card stays popup-local instead of introducing a shared
  weather service. `config/quickshell/popups/CalendarPopup.qml` resolves the
  shell's current coordinates through `desktopctl sun status`, then fetches the
  current forecast from Open-Meteo with `curl` only while the popup is active.
- Focus Time still polls `${XDG_RUNTIME_DIR:-/run/user/$UID}/focustime_state.json`
  inside its pane and treats payloads older than 5 seconds as stale; see
  `docs/focus-time/SPEC.md`.
- The shell brightness OSD no longer reads `/tmp/quickshell-brightness`.
  `config/quickshell/shell.qml` exposes a `brightness` IPC handler for OSD
  events, and `desktopctl/src/brightness.rs` drives it with
  `qs -p <repo>/config/quickshell ipc call brightness osd ...`.

Write-oriented services now also own their optimistic/pending state locally
instead of waiting for subprocess completion before updating the touched
control. `NetworkService.qml` stages Wi-Fi radio, active-connection
disconnect and DNS changes, plus Wi-Fi forget actions, before `nmcli`
completes; `BluetoothService.qml` stages power and
disconnect actions; `VpnService.qml` stages Mullvad/Tailscale connect-disconnect
intent until the next real status refresh confirms it; and
`DisplayService.qml` stages night-light mode / target temperature while
preserving a rollback snapshot for failures.

## Settings System

| Area | Current implementation |
| --- | --- |
| Host-owned data | Theme snapshot, shared mouse-input snapshot, fingerprint enrollment snapshot/status, colors, presets, wallpapers, directories, icon/cursor/font choices, and Hyprland appearance draft state |
| Host loaders | `Process` helpers call `desktopctl theme status --json`, `desktopctl hypr input status --json`, `desktopctl theme list-schemes --json`, `desktopctl theme list-presets --json`, `fprintd-list`, `busctl` fingerprint-device property reads, and shell commands for wallpaper/directory browsing |
| Service-driven panes | Network, Bluetooth, Audio, Display, Power, Notifications, Focus Time |
| Host-driven panes | Fingerprint, Presets, Colors, Fonts, Wallpaper, Icons, Mouse, Hyprland |
| Category gating | `HostCapabilities.qml` plus the `hiddenCategories` / category-visibility logic in `config/quickshell/popups/SettingsPopup.qml` hide Power when neither battery nor power-profile support is present, and hide Fingerprint unless the chassis is laptop-like and the `busctl tree net.reactivated.Fprint` probe reports a device |
| General theme writes | Serialized `desktopctl theme set` and `desktopctl theme preset` requests, with host-local staging for individual `set` writes before process exit and toast-visible backend errors |
| Mouse input writes | Serialized `desktopctl hypr input set` requests, with host-local staging for shared mouse settings before the backend reload confirms or rolls them back |
| Preset writes | `desktopctl theme save-preset` and `desktopctl theme delete-preset` |
| Hyprland appearance writes | Debounced queue of `desktopctl theme set hypr_* ...` writes with desktop-notification feedback |

Quick Settings expand affordances are consumed by the overlay host:
`config/quickshell/PopupOverlayHost.qml` closes the current popup, selects the
target settings category, and opens the full Settings popup, while the same
file maps Wi-Fi, Bluetooth, VPN, DND, and power-profile expand requests to
concrete category indices. The idle-inhibit tile stays popup-local and talks
directly to `config/quickshell/IdleInhibitService.qml` instead of routing to a
deeper Settings page.

The Network page now keys its summary and diagnostics off the active
default-route interface instead of assuming Wi-Fi. `config/quickshell/NetworkService.qml`
combines `ip -j route show default`, `nmcli -t -f TYPE,STATE,DEVICE,CONNECTION dev status`,
and `nmcli dev show <ifname>` so `primaryConnectionType`,
`primaryConnectionLabel`, `connectedConnectionId`, `connectedConnectionUuid`,
`activeIp`, `activeGateway`, and `activeDns` follow the selected Wi-Fi or
ethernet device. `config/quickshell/popups/settings/SettingsNetworkPane.qml`
now shows an ethernet detail card in the list state when wired is active,
keeps Wi-Fi radio/scan/password/channel flows gated on `HostCapabilities.hasWifi`,
and still reuses `config/quickshell/popups/wifi/WifiDetail.qml` and
`config/quickshell/popups/wifi/WifiDiagnostics.qml` with transport-specific
visibility instead of splitting duplicate ethernet-only views. Wired link data
comes from `/sys/class/net/<ifname>/speed`, `duplex`, and `carrier`, while the
same diagnostics surface keeps the existing router/internet/DNS/speed-test
sections for both transports.

`SettingsPopup.qml` is now responsible for several additional settings-host
behaviors:

- Responsive panel sizing instead of the old fixed `700x500` shell:
  the `panelWidth` / `panelHeight` calculations and panel loader sizing in
  `config/quickshell/popups/SettingsPopup.qml`.
- Optimistic theme-state staging and rollback for `desktopctl theme set`
  writes, plus serialized `set` / `preset` draining between backend reloads:
  the theme-write queue, reload, and rollback logic in
  `config/quickshell/popups/SettingsPopup.qml`.
- Normalizing `desktopctl theme list-schemes --json` into richer `colorFamilies`
  preview objects, then feeding the shared responsive card selector used by
  both the Colors pane and the preset editor:
  `config/quickshell/popups/SettingsPopup.qml`,
  `config/quickshell/components/ColorSchemeCards.qml`,
  `config/quickshell/components/ColorSchemeCard.qml`,
  `config/quickshell/popups/settings/SettingsColorsPane.qml`, and
  `config/quickshell/popups/settings/SettingsPresetEditor.qml`.
- Passing wallpaper-directory metadata into the preset editor so wallpaper
  fields can validate and commit separately from freeform typing:
  `config/quickshell/popups/SettingsPopup.qml`,
  `config/quickshell/popups/settings/SettingsPresetsPane.qml`, and
  `config/quickshell/popups/settings/SettingsPresetEditor.qml`.
- Keeping icon-theme selection separate from the Mouse page by routing it
  through a dedicated Icons pane, while the Mouse pane now owns cursor
  theme/size plus shared `desktopctl hypr input` controls for speed,
  acceleration profile, and scroll factor:
  `config/quickshell/popups/SettingsPopup.qml`,
  `config/quickshell/popups/settings/SettingsIconsPane.qml`, and
  `config/quickshell/popups/settings/SettingsMousePane.qml`.
- Owning a dedicated shared-mouse snapshot plus serialized
  `desktopctl hypr input` write queue alongside the existing theme-write path:
  the shared-mouse snapshot, status loader, and write queue in
  `config/quickshell/popups/SettingsPopup.qml`.
- Passing dedicated target lists into the Fonts and Presets panes so the shell
  now exposes only the active system-font size offsets (`Quickshell`, `GTK`,
  `Qt`) and keeps the full mono-offset set, including Neovide, while showing
  only the signed delta beside each stepper, and canonicalizing friendly
  mono-font labels such as `JetBrains Mono Nerd Font` to the exact stored
  family names before invoking `desktopctl theme set`:
  `config/quickshell/popups/SettingsPopup.qml`,
  `config/quickshell/popups/settings/SettingsFontsPane.qml`,
  `config/quickshell/popups/settings/SettingsPresetsPane.qml`, and
  `config/quickshell/popups/settings/SettingsPresetEditor.qml`.
- Owning the fingerprint-management host flow: `fprintd-list` parses the
  current device/name plus enrolled fingers, `fprintd-enroll $(id -un)` and
  `fprintd-delete $(id -un)` run as host-managed same-user mutations with
  inline status/error state, and the popup cancels an in-flight enroll when it
  closes. Enrollment feedback now also reads `num-enroll-stages` and
  `scan-type` from the default `net.reactivated.Fprint.Device`, then parses the
  live line-buffered `fprintd-enroll` session output so the pane can show
  capture progress plus retry guidance while the command is running. On
  the laptop host, `hosts/laptop/system.nix` also grants the active local user
  direct `net.reactivated.fprint.device.enroll` access so this flow does not
  have to bounce through the external auth agent:
  `config/quickshell/popups/SettingsPopup.qml` and
  `config/quickshell/popups/settings/SettingsFingerprintPane.qml`.

The Power pane remains lazy-loaded through the settings detail loader, so the
privileged charge-limit probe is now deferred until `SettingsPowerPane.qml`
mounts instead of firing on every Settings popup open. Evidence:
the settings-detail loader in `config/quickshell/popups/SettingsPopup.qml` and
the probe startup path in `config/quickshell/popups/settings/SettingsPowerPane.qml`.

The settings sidebar remains click-driven. It uses the shared `WheelFlickable`
for scrolling and `HoverLayer` for category hit targets, but it does not add a
custom tab-order or focused-outline layer on top of the popup shell. Evidence:
`config/quickshell/popups/settings/SettingsSidebar.qml`.

`SettingsFocusTimePane.qml` still consumes the JSON summary directly, but it no
longer paints charts from placeholder geometry on first load. The pane now reads
from the daemon's XDG-runtime fallback path, treats payloads older than 5
seconds as stale, waits for the first fresh payload, and only then enables
bar/heatmap/app-width animations after `chartVisualsReady` has been primed.
Evidence:
`config/quickshell/popups/settings/SettingsFocusTimePane.qml`.

Shell chrome remains deliberately pointer-first after the frontend-polish pass.
Quick Settings tiles and footer actions, bar modules, and power-menu actions
all use mouse/touch hit areas plus hover/pressed feedback, without repo-local
tab stops or focus outlines layered onto those surfaces. Evidence:
`config/quickshell/popups/QuickSettingsPopup.qml`,
`config/quickshell/bar/Bar.qml`,
`config/quickshell/bar/Clock.qml`,
`config/quickshell/bar/Mpris.qml`,
`config/quickshell/bar/Workspaces.qml`, and
`config/quickshell/PowerMenu.qml`.

## Theme Integration

| Piece | Current role |
| --- | --- |
| `Theme.qml` | Watches the XDG-config-derived `GeneratedTheme.json` path, reparses on change, and exposes generated colors/fonts plus shell-owned layout constants |
| `desktopctl/src/theme/targets/quickshell.rs` | Writes `GeneratedTheme.json`, maps theming names into Quickshell's `bg0_h` / `aqua` naming, emits both mono and system font families, and derives shell font sizes from `ThemeState.font_size + quickshell_font_size_offset` |
| Recursive tree exception | `config/quickshell/GeneratedTheme.json` is committed in the repo as a bootstrap snapshot because Home Manager deploys the whole `config/quickshell/` tree recursively; activation/runtime theme applies still overwrite the live `${XDG_CONFIG_HOME:-~/.config}/quickshell/GeneratedTheme.json` path |
| Settings host | Runs `desktopctl theme ...`, stages optimistic `themeState` updates for individual `set` writes, serializes general theme writes, shows toast-visible backend failures, then reloads or rolls back its local snapshot when the process exits |
| Shell IPC | Provides a second command path into `desktopctl theme ...` through `theme.apply`, with shell-style tokenization and error toasts on failure |

`Theme.qml` still keeps hardcoded Gruvbox Dark fallbacks for the generated JSON
surface in its fallback color/font object inside `config/quickshell/Theme.qml`.

## Popup Surfaces

The async popup surfaces now keep their host containers sized from placeholder
geometry while the loaded content fades/scales in, instead of snapping the host
to the final implicit height before the styled content appears. The current
pattern is shared across Quick Settings, Settings, the notification drawer, and
Calendar:

- `config/quickshell/popups/QuickSettingsPopup.qml`
- `config/quickshell/popups/SettingsPopup.qml`
- `config/quickshell/NotifDrawer.qml`
- `config/quickshell/popups/CalendarPopup.qml`

The popup implementations are no longer uniform, however:

- `config/quickshell/popups/CalendarPopup.qml` now keeps one popup width and
  switches between a month-grid page and a weather page through local toggle
  pills instead of rendering both side by side. It still keeps a
  placeholder-backed `panelHeightHint`, suppresses `Behavior on height` during
  open/close, and only animates the loaded panel's `opacity` / `scale` while
  visible. The weather page refreshes on demand and every 15 minutes while that
  page is active, reusing `desktopctl sun status` for coordinates and
  sunrise/sunset labels before calling Open-Meteo through `curl`. Its weather
  card styling now sticks to direct `Theme.*` palette slots for fills, borders,
  and accents instead of blending intermediate colors inside QML.
- `config/quickshell/NotifDrawer.qml` keeps the same placeholder-backed
  `panelHeightHint`, suppresses `Behavior on height` during open/close, and
  only animates the loaded panel's `opacity` / `scale` while visible. Its host
  height animation remains available only for later in-session content resizes.
- `config/quickshell/popups/QuickSettingsPopup.qml` does the same outer
  placeholder-height reservation and open/close suppression, and no longer
  animates the panel's own `implicitHeight` on top of the host height.
- `config/quickshell/popups/SettingsPopup.qml` keeps a fixed host size
  (`panelWidth` / `panelHeight`) and only animates the loaded panel's
  `opacity` and `scale`, but the root panel now enables its offscreen layer
  only while the open/close animation is running, with `layer.smooth: true`,
  and defers `refreshSystemServices()` through a timer instead of kicking the
  full refresh batch off in the first entrance frame.
- `config/quickshell/popups/TrayPopup.qml` and
  `config/quickshell/popups/MprisPopup.qml` skip the async host-height path and
  instead animate fixed-geometry panel rectangles directly with `opacity` /
  `scale`; `TrayPopup.qml` also animates a small `y` offset.
- `config/quickshell/PowerMenu.qml` avoids a popup-container open/close
  transform entirely. The overlay host only fades the scrim, while the menu
  buttons run staggered `opacity` / `scale` entrance animations inside a stable
  layout.

`NotifDrawer.qml` also records the largest already-rendered history `entryId`
and only runs the staggered entrance animation for newly inserted history items,
avoiding the old “history settles again on every open” behavior:
the history watermark and insert-animation logic in `config/quickshell/NotifDrawer.qml`.

## Runtime Assumptions

- `desktopctl` is on `PATH` for every Quickshell `Process` that invokes theme
  commands.
- A writable `${XDG_CONFIG_HOME:-~/.config}/quickshell/GeneratedTheme.json`
  exists beside the Home Manager-managed Quickshell tree; it may begin as the
  committed repo snapshot and then be overwritten by `desktopctl theme sync`.
- A writable `${XDG_CONFIG_HOME:-~/.config}/hypr/input-runtime.conf` exists
  before the Mouse page issues any `desktopctl hypr input set ...` writes; Home
  Manager now bootstraps that file during activation.
- Keyboard-driven brightness OSD updates depend on `qs` plus repo-root
  resolution in `desktopctl`, not on a temp file.
- A backlight is discoverable under `/sys/class/backlight` for the brightness
  slider path to be usable.
- `${XDG_RUNTIME_DIR:-/run/user/$UID}/focustime_state.json` exists when the
  focus-time daemon is running.
- CLI tools such as `nmcli`, `bluetoothctl`, `hyprctl`, `brightnessctl`,
  `mullvad`, `tailscale`, `busctl`, `curl`, and related helpers are on `PATH`.
- Outbound HTTPS access is available when the calendar weather card should show
  a live forecast; otherwise the popup falls back to the last successful
  weather payload or the locally resolved sunrise/sunset labels.
