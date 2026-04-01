# Quickshell Specification

This document defines the intended Quickshell design. It is the contract for how
the shell should be composed, how popup and service boundaries should work, and
how shell-side theming should round-trip. The current implementation map lives in
`docs/quickshell/ARCHITECTURE.md`, primarily the sections backed by
`config/quickshell/shell.qml:12-266`, `config/quickshell/PopupVisibility.qml:3-39`,
`config/quickshell/PopupOverlayHost.qml:9-179`, `config/quickshell/bar/Bar.qml:7-68`,
`config/quickshell/popups/SettingsPopup.qml:10-905`, and
`config/quickshell/Theme.qml:5-167`.

## Shell Composition

The shell is intended to be one session-level composition with four surface
classes:

- Persistent chrome: the bar is always available and is the primary entry point
  into popup surfaces (`config/quickshell/bar/Bar.qml:7-68`).
- Managed overlay popups: calendar, tray, MPRIS, quick settings, settings,
  notification drawer, and power menu are all intended to live under one shared
  overlay host and one shared exclusivity registry
  (`config/quickshell/PopupVisibility.qml:3-39`,
  `config/quickshell/PopupOverlayHost.qml:123-179`).
- Transient feedback surfaces: the root notification popup stack, OSD, toast,
  and tooltip are intentionally outside popup exclusivity so they can appear
  while another popup is open and do not compete for overlay ownership
  (`config/quickshell/shell.qml:33-185`, `config/quickshell/TooltipWindow.qml:6-48`).
- Session IPC: shell-wide commands target existing shell surfaces and services
  rather than opening independent windows or bypassing service boundaries
  (`config/quickshell/shell.qml:187-265`).

Each popup surface has a distinct role. `QuickSettingsPopup` is the bounded,
high-frequency control surface for summary state and one-tap toggles.
`SettingsPopup` is the deep configuration host for theme state, presets,
wallpapers, and detailed panes. `NotifDrawer` is retained notification history,
not the same surface as the root notification popup stack. `PowerMenu` is the
only popup intended to behave like a modal interruption and may request a scrim
(`config/quickshell/PopupOverlayHost.qml:123-179`,
`config/quickshell/PowerMenu.qml:9-60`).

## Popup Exclusivity Contract

`PopupVisibility.qml` is the authoritative registry for every managed overlay
popup, and `PopupOverlayHost.qml` is the only overlay `PanelWindow` that may
materialize those popups (`config/quickshell/PopupVisibility.qml:3-39`,
`config/quickshell/PopupOverlayHost.qml:9-179`).

The exclusivity rules are:

- At most one managed overlay popup is active at a time.
- Opening one managed popup closes the others through the shared registry rather
  than through per-popup coordination.
- The overlay host owns keyboard focus, outside-click dismissal, and scrim
  behavior while a managed popup is open.
- Popup-to-popup handoff is a host concern. A popup may request another popup,
  but it does not create or manage that other popup directly.
- Non-managed transient surfaces do not participate in exclusivity and must not
  be closed as a side effect of switching overlay popups.

Every managed popup is intended to implement the same host-facing shape:
`active`, `close()`, `overlayVisible`, `panelItem`, `focusTarget`, and optional
scrim properties, matching the current host contract in
`config/quickshell/PopupOverlayHost.qml:25-179` and the popup implementations
mounted there.

## Service Layer Contract

The service layer is intended to be the shell's shared runtime boundary.
Singletons are the right abstraction when a domain has any of these properties:

- the same state appears in more than one shell surface
- the same commands are reachable from more than one surface or from shell IPC
- the freshness model must be consistent across the shell
- the domain owns shell-wide transient UI state such as notifications, toasts,
  tooltips, or theme values

That is the intended role of the current singleton set rooted at
`config/quickshell/AudioService.qml`, `BluetoothService.qml`,
`BrightnessService.qml`, `DisplayService.qml`, `NetworkService.qml`,
`NotificationService.qml`, `PowerProfileService.qml`, `Theme.qml`,
`ToastService.qml`, `TooltipService.qml`, and `VpnService.qml`, as summarized in
`docs/quickshell/ARCHITECTURE.md` and implemented under `config/quickshell/`.

Local state is still intentional, but only for surface-local concerns:

- selection, expansion, filters, and draft form state
- pane-local navigation between list and detail views
- short-lived process state that is meaningful only inside one pane
- domain state that is truly confined to one surface and has no shell-wide read
  or write contract

If a capability is shared across the bar, Quick Settings, full Settings, or IPC,
it belongs in a singleton service. The correct behavior described by the review
findings in `docs/quickshell/REVIEW.md:50-73`, `docs/quickshell/REVIEW.md:321-354`,
and `docs/quickshell/REVIEW.md:361-369` is one shared service-backed source of
truth per shared domain, not one implementation per surface.

## Settings Host And Pane Contract

The settings system intentionally supports two pane models, but the choice is by
domain boundary, not by convenience.

Host-driven panes are the intended model for domains whose source of truth is a
settings-host snapshot plus command orchestration. This includes theme state,
presets, wallpapers, icon and font selection, and Hyprland appearance controls,
matching the current host-owned data and callbacks in
`config/quickshell/popups/SettingsPopup.qml:43-95`,
`config/quickshell/popups/SettingsPopup.qml:216-264`, and
`config/quickshell/popups/SettingsPopup.qml:823-903`. In this model:

- the host owns loaded state, lists, command status, and mutation routing
- panes receive props and emit intents
- panes do not shell out or edit theme files directly

Service-direct panes are the intended model for live system domains that already
have a shared service contract, such as audio, network, Bluetooth, display,
power profile, and VPN, matching the current pane set mounted without host props
in `config/quickshell/popups/SettingsPopup.qml:793-821`. In this model:

- the singleton owns shared state, refresh logic, and side-effecting commands
- the pane owns view-local layout and navigation only
- other shell surfaces that expose the same capability are expected to consume
  the same service contract

One capability should use one write path. If the host owns a domain, every pane
in that domain signals the host. If a singleton owns a domain, every surface
calls the singleton. The mixed ownership problems described in
`docs/quickshell/REVIEW.md:285-332` are not the intended contract.

Quick Settings is intentionally the shallow surface. It may expose summary state,
bounded toggles, and a jump to deeper settings, but unbounded selection sets,
diagnostics, provider-specific drill-down, and preset editing belong in
`SettingsPopup`, not in duplicate Quick Settings logic.

## The Bar And The Service Layer

The bar is intended to be thin shell chrome. Its modules may present state,
surface a tooltip, and route clicks into popup toggles, but the bar is not
supposed to become a second orchestration layer (`config/quickshell/bar/Bar.qml:7-68`).

The intended sourcing rules are:

- If a domain is shared with Settings, Quick Settings, or IPC, the bar should
  consume the same singleton service or the same upstream Quickshell service
  wrapper that the rest of the shell uses.
- A bar module may stay local only when the domain is inherently local or already
  provided by a direct upstream singleton with no repo-specific normalization
  requirement, such as the clock or workspace state.
- The bar should not maintain its own polling/parser implementation for network,
  Bluetooth, VPN, or any other shared shell domain.

This is the intended resolution of the duplication described in
`docs/quickshell/REVIEW.md:333-369`: service-backed domains should have one
shared freshness and command path, and the bar should render that state rather
than recomputing it.

## Theme Integration Contract

`Theme.qml` is the shell-facing theme boundary. The theming system owns the
generated `~/.config/quickshell/GeneratedTheme.json`, and the shell consumes it
through `Theme.qml` (`config/quickshell/Theme.qml:5-167`,
`themes/lib/targets/quickshell.py:7-49`).

The generated contract from the shell's perspective is:

- theme-generated colors belong in `GeneratedTheme.json`
- shell font families and shell font-size slots belong in `GeneratedTheme.json`
- shell layout geometry, popup sizing, and animation timing remain shell-owned
  constants and are not part of theme state

All shell-initiated theme mutations go through `themes/apply-theme`, either from
the settings host or from shell IPC (`config/quickshell/popups/SettingsPopup.qml:613-661`,
`config/quickshell/shell.qml:244-256`, `themes/apply-theme:228-297`). QML does
not own the theme state file format and does not edit generated outputs directly.

Two feedback paths are intended:

- Shell chrome feedback: if the affected target set includes `quickshell`, the
  shell updates from the `Theme.qml` file-watch path when `GeneratedTheme.json`
  changes (`config/quickshell/Theme.qml:8-28`,
  `themes/lib/orchestrator.py:14-46`, `themes/lib/orchestrator.py:215-220`).
- Settings control feedback: when a theme command finishes, the settings host
  refreshes its own theme snapshot and related lists so controls reflect the
  committed state even for keys that do not rewrite `GeneratedTheme.json`, such
  as `dark_hint` or `hypr_*` keys (`config/quickshell/popups/SettingsPopup.qml:139-214`,
  `config/quickshell/popups/SettingsPopup.qml:216-264`,
  `themes/lib/orchestrator.py:37-45`).

The latency contract is command-completion-based, not timer-based. The intended
behavior is:

- a successful theme write is reflected in controls as soon as the command exits
- shell visuals update on the first file-change notification for
  `GeneratedTheme.json`
- the shell does not wait on unrelated refresh work before acknowledging a
  committed change

The fixed-delay behavior discussed in `docs/quickshell/REVIEW.md:181-283` is not
the intended contract. The intended contract is one apply round trip, one shell
visual update path, and one host-state refresh path, each tied to the actual
completion of the write that produced the new state.
