# Quickshell Review

## Scope

This review is based on:

- `docs/theming/SPEC.md`
- Everything currently under `docs/`
- `themes/apply-theme` plus the relevant `themes/lib/*` targets and orchestrator code
- Every QML file under `config/quickshell/`

This document is intentionally limited to current behavior, problems, and why they matter. It does not propose fixes.

## 1. Settings Menu: Behavioral Inconsistencies

### 1.1 Bluetooth has an in-pane power toggle; Wi-Fi does not

The Bluetooth pane exposes power state as a first-class control. The pane shows a `Power` row with a `ToggleSwitch`, and the service has an explicit `togglePower()` API that shells out to `bluetoothctl power on/off`. The rest of the Bluetooth pane is also explicitly gated on `BluetoothService.powered`. Files: `config/quickshell/popups/settings/SettingsBluetoothPane.qml:46-83`, `config/quickshell/BluetoothService.qml:49-52`, `config/quickshell/BluetoothService.qml:64-75`.

The Wi-Fi / Network pane does not expose equivalent radio power control. Its list-state header only offers `Rescan`; the rest of the pane is a Wi-Fi list plus VPN controls. There is no Wi-Fi powered-off state in the pane itself, and `NetworkService` exposes scan / connect / disconnect / forget / detail / diagnostics APIs but no radio on/off API. Files: `config/quickshell/popups/settings/SettingsNetworkPane.qml:98-145`, `config/quickshell/popups/settings/SettingsNetworkPane.qml:160-298`, `config/quickshell/NetworkService.qml:148-233`.

Equivalent Wi-Fi radio control exists, but only in Quick Settings. `QuickSettingsPopup.qml` carries its own `nmcli radio wifi` check/toggle `Process` objects and even documents the reason inline: `NetworkService lacks a radio toggle`. Files: `config/quickshell/popups/QuickSettingsPopup.qml:33-55`, `config/quickshell/popups/QuickSettingsPopup.qml:275-278`.

This is a capability split across two surfaces rather than one consistent network control model. It matters because the user-facing contract is different depending on which panel is open, and because the Wi-Fi radio logic is duplicated outside the network service layer.

### 1.2 Bluetooth shows a skeleton while powered off because loading does not short-circuit on `powered == false`

`SettingsBluetoothPane.qml` defines `deviceListLoading` as:

- popup state is `list`
- both paired and discovered device models are empty
- `BluetoothService.refreshing || BluetoothService.scanning`

There is no `!BluetoothService.powered` escape hatch in that condition. Files: `config/quickshell/popups/settings/SettingsBluetoothPane.qml:10-18`.

The powered-off empty state is only shown when `!BluetoothService.powered && !deviceListLoading`, and the device-list container remains visible while `deviceListLoading` is true. The skeleton loader is shown whenever `deviceListLoading` is true. Files: `config/quickshell/popups/settings/SettingsBluetoothPane.qml:78-83`, `config/quickshell/popups/settings/SettingsBluetoothPane.qml:138-140`, `config/quickshell/popups/settings/SettingsBluetoothPane.qml:280-315`.

The service-side refresh path explains the delay:

- `refresh()` clears state and starts `showProc`
- `refreshing` is true while `showProc`, `connInfoProc`, `pairedProc`, or `allDevicesProc` are running
- `showProc` is what determines `powered`
- only after `showProc` exits does the service set `root.powered`
- the rest of the device chain only starts if `root.powered` is true

Files: `config/quickshell/BluetoothService.qml:17-30`, `config/quickshell/BluetoothService.qml:64-75`, `config/quickshell/BluetoothService.qml:77-140`.

The result is that the powered-off state does not terminate loading early, even though the same refresh sequence is what discovers that Bluetooth is off. The problem is not just cosmetic: it makes a deliberate “off” state look like an unresolved fetch.

### 1.3 VPN state and controls are inconsistent across Quick Settings, the bar, and the Network pane

The shell currently exposes VPN state in three different ways:

- Quick Settings has a single `VPN` tile that only reflects Mullvad state. Its active state, sublabel, and connect/disconnect action all reference `VpnService.mullvadState`, `mullvadCity`, and `mullvadCountry`; Tailscale is ignored there. Files: `config/quickshell/popups/QuickSettingsPopup.qml:197-203`, `config/quickshell/popups/QuickSettingsPopup.qml:214-220`, `config/quickshell/popups/QuickSettingsPopup.qml:241-253`, `config/quickshell/popups/QuickSettingsPopup.qml:275-287`.
- The Network settings pane includes separate Mullvad and Tailscale sections. Each section shows status text and a toggle; Mullvad also shows the connected IP, and Tailscale shows tailnet / IP / exit-node summary. There is still no location selection control. Files: `config/quickshell/popups/settings/SettingsNetworkPane.qml:15-36`, `config/quickshell/popups/settings/SettingsNetworkPane.qml:236-295`.
- A dedicated bar component for VPN exists and can summarize both Mullvad and Tailscale in its tooltip, but the actual bar does not instantiate it. Files: `config/quickshell/bar/Vpn.qml:6-20`, `config/quickshell/bar/Bar.qml:46-55`.

At the service level, `VpnService.qml` only exposes:

- Mullvad state, country, city, IP
- Tailscale state, tailnet, IP, exit-node
- connect/disconnect/up/down actions

There is no API for browsing or selecting Mullvad locations or relays. Files: `config/quickshell/VpnService.qml:8-18`, `config/quickshell/VpnService.qml:35-56`, `config/quickshell/VpnService.qml:60-161`.

What is missing is not just a location picker in one pane. The shell has no unified VPN story:

- Quick Settings is Mullvad-only
- the bar-level VPN component exists but is not mounted
- the Network pane exposes two providers but only as toggles plus status
- no surface supports Mullvad location selection

That matters because the user’s available controls depend on surface and provider, not on a single documented VPN abstraction.

## 2. Settings Menu: UI Pattern Issues

### 2.1 Flat button-list selection patterns are used for both bounded and unbounded option sets

Several panes present selection as flat chip/button lists, but the data sources are not equivalent:

| Pane / control | Current pattern | Option count in code | Bounded or unbounded |
| --- | --- | --- | --- |
| Display monitor selector | `Flow` of chips, one per enabled monitor | Runtime-derived from `DisplayService.monitors` | Bounded by connected monitors, but uncapped in UI code |
| Display resolution selector | `Flow` of chips, one per unique parsed resolution | Runtime-derived from `currentMonitor.availableModes` | Unbounded in UI code |
| Display refresh selector | `Flow` of chips, one per parsed rate for selected resolution | Runtime-derived from `availableModes` | Unbounded in UI code |
| Coding font selector | `Flow` of chips | 6 hardcoded options | Bounded |
| System font selector | `Flow` of chips | 10 hardcoded options | Bounded |
| Icon theme selector | `Flow` of chips | 6 hardcoded options | Bounded |
| Cursor theme selector | `Flow` of chips | 3 hardcoded options in the main pane | Bounded |

Files:

- Display monitor / resolution / refresh selection: `config/quickshell/popups/settings/SettingsDisplayPane.qml:17-61`, `config/quickshell/popups/settings/SettingsDisplayPane.qml:131-341`
- Coding / system fonts: `config/quickshell/popups/settings/SettingsFontsPane.qml:60-112`, `config/quickshell/popups/settings/SettingsFontsPane.qml:288-340`
- Icons / cursors: `config/quickshell/popups/settings/SettingsIconsPane.qml:22-74`, `config/quickshell/popups/settings/SettingsIconsPane.qml:78-130`

The problem is that the UI pattern does not change when the option set changes from small-and-curated to runtime-derived-and-open-ended. This matters most in the display pane, where the number of resolutions and refresh rates is determined by hardware capabilities, not by a small fixed list the layout can assume in advance.

There is a second-order duplication problem here as well: `SettingsPresetEditor.qml` re-implements the same chip-list pattern again for colors, fonts, icons, cursors, and Hyprland fields inside a 1571-line editor component. Files: `config/quickshell/popups/settings/SettingsPresetEditor.qml:302-488`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:596-1033`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:1033-1472`.

### 2.2 The sidebar is fixed-height and non-scrolling

`SettingsSidebar.qml` is a fixed-width `Rectangle` with a plain `ColumnLayout`. It has:

- width `190`
- height `parent.height`
- section headers and separators
- two `Repeater`s for category groups
- a final filler `Item`

It does not use `Flickable` / `WheelFlickable`. Files: `config/quickshell/popups/settings/SettingsSidebar.qml:15-25`, `config/quickshell/popups/settings/SettingsSidebar.qml:60-238`.

`SettingsPopup.qml` also keeps the category system as static arrays plus a `switch` statement for the detail pane. Files: `config/quickshell/popups/SettingsPopup.qml:59-63`, `config/quickshell/popups/SettingsPopup.qml:770-785`.

If more categories are added, the sidebar has no overflow strategy other than clipping inside the fixed-height host panel. This is already structurally fragile because category growth requires coordinated edits to the category arrays, the sidebar grouping count, and the detail loader switch, and the sidebar itself has no scroll path once the list exceeds available height.

### 2.3 The presets pane is structurally dense, vertically heavy, and clips overflow instead of accommodating it

The presets pane is a `WheelFlickable` whose content is a single `ColumnLayout`. That column contains:

- pane header text
- the “Save Current State” button
- optional explanatory text
- an embedded `SettingsPresetEditor`
- an inline error message
- a `Repeater` of full-width preset cards

Files: `config/quickshell/popups/settings/SettingsPresetsPane.qml:6-16`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:98-107`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:108-207`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:209-379`.

Each preset card shows:

- preset name
- inline `Edit` and `Delete` controls in the same top row
- a full text dump of every preset key/value except `name`

That summary is generated by iterating over all keys and joining them with `\n`. The summary text wraps, but it does not elide, summarize, truncate, or cap line count. Card height grows to `presetContent.implicitHeight + 24`, so verbose presets become tall cards rather than short summaries. Files: `config/quickshell/popups/settings/SettingsPresetsPane.qml:46-56`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:218-220`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:244-377`.

The pane also lives inside a clipped host:

- the settings panel itself is `clip: true`
- the detail area is fixed-width
- the presets flickable is also `clip: true`

Files: `config/quickshell/popups/SettingsPopup.qml:711-770`, `config/quickshell/popups/SettingsPopup.qml:732-742`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:98-100`.

The user-observed right-edge clipping is consistent with this layout stack: the pane relies on clipping and vertical growth, not on any horizontal overflow handling. The exact visible severity may depend on runtime font metrics and preset content, so this part should be treated as an observed behavior corroborated by the layout structure rather than as a purely static-code certainty.

## 3. Settings Menu: Layout and Structure

The settings popup is fixed-size:

- width `700`
- height `500`

Files: `config/quickshell/popups/SettingsPopup.qml:711-718`.

The panel split is:

- sidebar width `190`
- divider width `1`
- detail container width `parent.width - 191`

Files: `config/quickshell/popups/SettingsPopup.qml:745-764`, `config/quickshell/popups/settings/SettingsSidebar.qml:15-20`.

The detail loader then applies `Theme.popupPadding` as content margins. `Theme.popupPadding` is `14`, so the effective inner detail width is roughly `700 - 191 - 28 = 481` before any pane-specific layout decisions. Files: `config/quickshell/popups/SettingsPopup.qml:766-769`, `config/quickshell/Theme.qml:91-94`.

The popup uses `clip: true` at the panel level, so panes that exceed the available width are clipped rather than allowed to overflow. File: `config/quickshell/popups/SettingsPopup.qml:732-742`.

Spacing and structure differ substantially by pane:

- `SettingsNetworkPane` uses `spacing: 8` and a `FocusScope` with an internal `ColumnLayout`; its list state splits vertical space between the Wi-Fi list and the VPN section. Files: `config/quickshell/popups/settings/SettingsNetworkPane.qml:92-95`, `config/quickshell/popups/settings/SettingsNetworkPane.qml:168-298`.
- `SettingsBluetoothPane` uses `spacing: 12` inside its own top-level flickable column. Files: `config/quickshell/popups/settings/SettingsBluetoothPane.qml:35-44`.
- `SettingsWallpaperPane` uses `spacing: 8` and a 3-column grid. Files: `config/quickshell/popups/settings/SettingsWallpaperPane.qml:26-29`, `config/quickshell/popups/settings/SettingsWallpaperPane.qml:66-142`.
- `SettingsPresetsPane` uses `spacing: 12` and stacks editor + cards vertically. Files: `config/quickshell/popups/settings/SettingsPresetsPane.qml:103-107`.
- `SettingsColorsPane`, `SettingsDisplayPane`, `SettingsFontsPane`, `SettingsIconsPane`, `SettingsPowerPane`, and `SettingsHyprlandPane` all use `spacing: 16`. Files: `config/quickshell/popups/settings/SettingsColorsPane.qml:20-23`, `config/quickshell/popups/settings/SettingsDisplayPane.qml:126-129`, `config/quickshell/popups/settings/SettingsFontsPane.qml:55-58`, `config/quickshell/popups/settings/SettingsIconsPane.qml:17-20`, `config/quickshell/popups/settings/SettingsPowerPane.qml:25-28`, `config/quickshell/popups/settings/SettingsHyprlandPane.qml:59-62`.

The inconsistency is not only aesthetic. Some panes are optimized around grids, some around chip flows, some around full-width rows, and some around nested stateful views. Because the host area is fixed-size, those choices materially affect how much of the pane is visible before scrolling starts and whether the pane looks sparse, cramped, or clipped.

## 4. UI Responsiveness

### 4.1 The actual theme-apply round trip is different depending on which key changed

#### Color scheme changes

The `Colors` pane emits `colorSchemeSelected`, and `SettingsPopup` maps that to `runSet("color_scheme", schemeName)`. Files: `config/quickshell/popups/settings/SettingsColorsPane.qml:23-118`, `config/quickshell/popups/SettingsPopup.qml:842-850`, `config/quickshell/popups/SettingsPopup.qml:622-626`.

`runSet()` does three things:

1. sets `applyProc.command`
2. starts the process
3. immediately restarts a fixed 1500 ms `reloadTimer`

`applyProc` itself does not reload state on completion; it only logs stderr / non-zero exit codes to the console. Files: `config/quickshell/popups/SettingsPopup.qml:613-620`, `config/quickshell/popups/SettingsPopup.qml:622-626`, `config/quickshell/popups/SettingsPopup.qml:661-661`.

The process runs `themes/apply-theme set color_scheme <name>`. In `cmd_set()`:

- the current theme state is loaded
- the new value is validated and written to `themes/state.json`
- affected targets are derived from `targets_for_key()`
- the orchestrator applies those targets

Files: `themes/apply-theme:228-256`, `themes/lib/resolve.py:76-110`, `themes/lib/orchestrator.py:140-188`, `themes/lib/orchestrator.py:215-220`.

For `color_scheme`, `DEPENDS` includes `quickshell` plus many other targets. Files: `themes/lib/orchestrator.py:15-21`.

The Quickshell target then:

- generates `GeneratedTheme.json`
- writes it to `~/.config/quickshell/GeneratedTheme.json`
- does not issue a reload command because Quickshell is expected to watch the file

Files: `themes/lib/targets/quickshell.py:7-13`, `themes/lib/targets/quickshell.py:14-49`.

On the Quickshell side, `Theme.qml` uses `FileView` with `watchChanges: true`; `onFileChanged` calls `reload()`, and `onLoaded` reparses the JSON into `_colors` / `_fonts`, which then drive the singleton’s reactive properties. Files: `config/quickshell/Theme.qml:8-27`, `config/quickshell/Theme.qml:29-69`.

Separately, after the fixed 1500 ms delay, `SettingsPopup.reloadTimer` calls `loadState()`, which:

- re-`cat`s `themes/state.json`
- re-runs the color-family discovery shell pipeline
- refreshes presets
- refreshes wallpapers

Files: `config/quickshell/popups/SettingsPopup.qml:139-214`, `config/quickshell/popups/SettingsPopup.qml:661-661`.

The latency points are therefore:

- QML `Process` spawn
- Python state load / validation
- every affected target generation and write
- runtime reload hooks for non-Quickshell targets
- filesystem notification + JSON reparsing in `Theme.qml`
- a separate, fixed 1500 ms delay before the settings pane’s own `themeState` catches up
- unrelated extra shell-outs for colors / presets / wallpapers on every reload

This is not a single reactive path. It is two independent paths: a push-based `GeneratedTheme.json` update for shell visuals, and a timer-based settings-model refresh for the popup itself.

#### `dark_hint` changes

The `Dark` / `Light` buttons in `SettingsColorsPane.qml` also go through `runSet()`. Files: `config/quickshell/popups/settings/SettingsColorsPane.qml:126-223`, `config/quickshell/popups/SettingsPopup.qml:845-850`, `config/quickshell/popups/SettingsPopup.qml:622-626`.

But `dark_hint` is not routed to `quickshell`. In the dependency map it affects only `gtk`. Files: `themes/lib/orchestrator.py:24-37`.

The GTK target applies the change by writing GNOME interface settings through `dconf`. It does not rewrite `GeneratedTheme.json`. Files: `themes/lib/targets/gtk.py:9-13`, `themes/lib/targets/gtk.py:32-43`.

That means:

- `Theme.qml` does not participate
- `GeneratedTheme.json` is not re-read
- the popup’s selected-state highlight only catches up after the 1500 ms `reloadTimer` re-reads `themes/state.json`

This is a direct counterexample to the simplified flow documented in `docs/theming/SPEC.md`, which presents “user clicks in SettingsPopup → apply-theme → Quickshell re-reads GeneratedTheme.json” as the general path. Files: `docs/theming/SPEC.md:30-41`, `docs/theming/SPEC.md:1174-1181`.

The inconsistency matters because two controls that look adjacent in the same pane use different feedback loops. One updates shell visuals through a watched file; the other updates only after a fixed delayed state reload.

#### Font size changes are another special case

The dependency map sends `font_size` and `mono_font_size` to GTK / Qt / Snappy Switcher and similar targets, but not to Quickshell. Files: `themes/lib/orchestrator.py:24-30`.

Separately, the Quickshell target hardcodes its font sizes to `12`, `10`, and `14`; it only pulls `mono_font` and `system_font` families from `ThemeState`. Files: `themes/lib/targets/quickshell.py:41-47`.

`Theme.qml` reads those generated font values reactively. Files: `config/quickshell/Theme.qml:64-69`.

So even within the “Fonts” surface, Quickshell only participates in family changes, not in the popup’s font-size controls. This is another place where the apply path and visible shell response are not uniform.

### 4.2 The responsiveness concern is broad in pattern, but strongest for settings routed through `runSet()`

The specific theme-apply issue is not fully isolated:

- `SettingsPopup` uses a fixed-delay timer for generic theme writes. Files: `config/quickshell/popups/SettingsPopup.qml:613-661`.
- Hyprland settings use a different path entirely: they have a debounced queue, a dedicated process, and call `loadState()` on process exit rather than on a fixed timer. Files: `config/quickshell/popups/SettingsPopup.qml:216-264`, `config/quickshell/popups/SettingsPopup.qml:392-578`.
- `SettingsFocusTimePane` polls runtime JSON every 3 seconds. Files: `config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-72`.
- `VpnService` polls every 15 seconds. Files: `config/quickshell/VpnService.qml:154-161`.
- The bar’s Network and Bluetooth widgets each poll on their own 10-second timers instead of reusing the corresponding services. Files: `config/quickshell/bar/Network.qml:55-107`, `config/quickshell/bar/Bluetooth.qml:54-117`.
- `DisplayService` night-light state is also timer-driven. Files: `config/quickshell/DisplayService.qml:197-285`.

So the broader pattern is timer/poll/manual-shell synchronization, not purely push-based state. The theme responsiveness issue is most visible in `SettingsPopup.runSet()` because:

- it is user-initiated
- it uses a fixed timer unrelated to process completion
- some keys update `GeneratedTheme.json` and some do not
- the popup reload work always includes unrelated shell-outs

## 5. Component and Architectural Patterns

### 5.1 `SettingsPopup.qml` is the host, router, loader, and command dispatcher

`SettingsPopup.qml` is the settings host, and it is heavy:

- theme state and list loading
- presets loading and mutations
- wallpaper directory browsing
- generic `apply-theme set` / `preset` command dispatch
- Hyprland draft-state queueing, debouncing, and notifications
- category registry and pane selection

Files: `config/quickshell/popups/SettingsPopup.qml:43-214`, `config/quickshell/popups/SettingsPopup.qml:216-661`, `config/quickshell/popups/SettingsPopup.qml:711-905`.

This matters because future changes are not isolated to one concern. Theme loading, preset mutation, directory browsing, and Hyprland live-edit behavior all converge in the same file.

### 5.2 Data flow between the host and panes is inconsistent

Some panes are host-driven:

- `SettingsPresetsPane` receives preset data, theme state, color families, font offset metadata, command status, error state, and callbacks. Files: `config/quickshell/popups/SettingsPopup.qml:823-840`.
- `SettingsColorsPane` receives `colorFamilies`, `themeState`, and emits host-handled signals. Files: `config/quickshell/popups/SettingsPopup.qml:842-850`.
- `SettingsFontsPane`, `SettingsWallpaperPane`, `SettingsHyprlandPane`, and `SettingsIconsPane` similarly depend on host-provided state and callbacks. Files: `config/quickshell/popups/SettingsPopup.qml:853-903`.

Other panes are not host-driven at all:

- `SettingsNetworkPane`, `SettingsBluetoothPane`, `SettingsAudioPane`, `SettingsDisplayPane`, `SettingsPowerPane`, and `SettingsFocusTimePane` are instantiated bare and reach directly into global services. Files: `config/quickshell/popups/SettingsPopup.qml:793-821`.

The result is a mixed ownership model:

- some panes are dumb views over host state
- some panes are smart views over singleton services
- some interactions dispatch through `apply-theme`
- some dispatch directly to service methods

That inconsistency increases the amount of code a future agent has to understand before changing a single pane.

### 5.3 Similar interactions use different command-routing patterns

There are at least three command-routing styles in the shell:

- `SettingsPopup.runSet()` shells out directly to `themes/apply-theme`. Files: `config/quickshell/popups/SettingsPopup.qml:622-631`.
- `shell.qml` separately exposes a `theme.apply(args)` IPC handler with its own `Process`. Files: `config/quickshell/shell.qml:244-256`.
- Hyprland controls have their own dedicated queued writer and notification path. Files: `config/quickshell/popups/SettingsPopup.qml:216-264`, `config/quickshell/popups/SettingsPopup.qml:488-578`.

Quick Settings adds another variation: Wi-Fi radio state is implemented locally with raw `nmcli radio wifi` processes because the network service does not provide that capability. Files: `config/quickshell/popups/QuickSettingsPopup.qml:33-55`.

This is fragile because similar user actions do not travel through one common abstraction. The behavior depends on which surface and setting are being changed.

### 5.4 The bar duplicates service logic instead of consistently consuming the singleton services

The bar’s `Network.qml` and `Bluetooth.qml` components each implement their own polling and parsing logic:

- `Network.qml` polls `nmcli device status`
- `Bluetooth.qml` polls `bluetoothctl show` and `bluetoothctl devices Connected`

Files: `config/quickshell/bar/Network.qml:7-107`, `config/quickshell/bar/Bluetooth.qml:7-117`.

But the settings surfaces use `NetworkService.qml` and `BluetoothService.qml` instead. Files: `config/quickshell/NetworkService.qml:6-990`, `config/quickshell/BluetoothService.qml:5-169`.

This matters because the shell does not have one canonical source of truth for network and Bluetooth state. Different surfaces can diverge in freshness, parsing behavior, and capability.

The same pattern shows up in VPN:

- a bar VPN component exists
- it can summarize both Mullvad and Tailscale
- the actual bar does not mount it

Files: `config/quickshell/bar/Vpn.qml:6-20`, `config/quickshell/bar/Bar.qml:46-55`.

### 5.5 Quick Settings can be stale because it does not refresh all of the services it displays

When Quick Settings opens, it refreshes:

- Wi-Fi radio state
- brightness
- power profile
- VPN

It does not refresh `NetworkService` or `BluetoothService`, even though the tile states read from those services. Files: `config/quickshell/popups/QuickSettingsPopup.qml:93-101`, `config/quickshell/popups/QuickSettingsPopup.qml:214-253`.

`NetworkService` only refreshes when `scan()` / `loadKnown()` are explicitly called. Files: `config/quickshell/NetworkService.qml:150-161`.

`BluetoothService` only refreshes when `refresh()` is explicitly called. Files: `config/quickshell/BluetoothService.qml:22-30`.

Because the bar is using separate polling logic anyway, the bar and Quick Settings are not guaranteed to agree on current network/Bluetooth state at the moment the popup opens.

### 5.6 `SettingsPresetEditor.qml` is a large, duplicated control surface

`SettingsPresetEditor.qml` is 1571 lines and re-implements many of the same control patterns already present elsewhere:

- appearance chips for color scheme and dark hint
- wallpaper include/text handling
- font selectors and size steppers
- icon and cursor selectors
- Hyprland value toggles and steppers

Files: `config/quickshell/popups/settings/SettingsPresetEditor.qml:6-139`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:302-592`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:596-1033`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:1033-1472`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:1476-1571`.

The problem is not just size. The file duplicates UI patterns and field knowledge that already exist in the dedicated settings panes, which makes the preset system another place where option inventories and control semantics can drift.

### 5.7 Hardcoded paths are pervasive; this appears intentional but remains a structural dependency

Hardcoded paths appear throughout the Quickshell implementation:

- `Theme.qml` hardcodes `~/.config/quickshell/GeneratedTheme.json`. Files: `config/quickshell/Theme.qml:8-15`.
- `SettingsPopup.qml` hardcodes `/home/kevin/repos/dotfiles/...` for `state.json`, colors, presets, wallpapers, and `apply-theme`. Files: `config/quickshell/popups/SettingsPopup.qml:146-214`, `config/quickshell/popups/SettingsPopup.qml:517-523`, `config/quickshell/popups/SettingsPopup.qml:588-610`, `config/quickshell/popups/SettingsPopup.qml:622-631`.
- `shell.qml` hardcodes the same path for theme IPC. Files: `config/quickshell/shell.qml:244-256`.

`docs/theming/SPEC.md` explicitly documents this as an intentional choice after an environment-propagation problem with Quickshell `Process` commands. Files: `docs/theming/SPEC.md:1167-1178`.

So this should be treated as intentional, not as an accidental bug. It is still a structural dependency future agents have to know about, because theme command execution and theme file loading are both tied to one repository layout.

## 6. Documentation Gap Analysis

### 6.1 What currently exists

There is documentation for the theming system:

- overall theming flow and principles: `docs/theming/SPEC.md:30-70`
- Quickshell integration as part of theming: `docs/theming/SPEC.md:1120-1185`

There is also documentation under `docs/`, but it is Nix / infrastructure oriented:

- `docs/nix/distributed-builds.md:1-65`
- `docs/nix/homelab-builder-setup.md:1-157`

The Quickshell implementation itself is only discoverable from code, primarily:

- shell composition: `config/quickshell/shell.qml:12-186`
- popup exclusivity: `config/quickshell/PopupVisibility.qml:3-39`
- popup host and dismissal model: `config/quickshell/PopupOverlayHost.qml:9-179`
- bar composition: `config/quickshell/bar/Bar.qml:7-68`
- theme singleton: `config/quickshell/Theme.qml:5-167`
- settings host: `config/quickshell/popups/SettingsPopup.qml:43-905`
- service singletons such as `AudioService.qml`, `BluetoothService.qml`, `DisplayService.qml`, `NetworkService.qml`, `NotificationService.qml`, `PowerProfileService.qml`, and `VpnService.qml`

### 6.2 What is missing for an agent without prior context

There is no Quickshell architecture document covering:

- the shell’s top-level composition and lifecycle
- the popup system, exclusivity model, and overlay host
- the service layer and which UI surfaces consume which services
- the bar module inventory and why some bar modules bypass the singleton services
- the settings popup host/pane contract
- the category registry and how panes are added
- which interactions go through `apply-theme`, which go directly to services, and which go through shell IPC
- which state updates are push-based (`Theme.qml` file watch) versus timer/poll-based (`reloadTimer`, service timers, bar timers)
- the preset subsystem and its relationship to the regular settings panes

That absence matters because the current codebase is understandable only by reverse-engineering multiple large files at once. `docs/theming/SPEC.md` explains the theme contract, but it does not explain the broader Quickshell architecture, and even its simplified Quickshell flow does not capture the current per-key differences in how settings round-trip back into the UI. Files: `docs/theming/SPEC.md:30-41`, `docs/theming/SPEC.md:1174-1185`, `config/quickshell/popups/SettingsPopup.qml:613-661`, `themes/lib/orchestrator.py:15-46`, `themes/lib/targets/quickshell.py:7-13`, `themes/lib/targets/gtk.py:32-43`.
