# Quickshell Specification

This spec defines the intended shell boundaries: surface types, popup
ownership, state ownership, and theme integration. It describes what the shell
is for and what must stay true; see `docs/quickshell/ARCHITECTURE.md` for the
current implementation map.

## Surface Model

| Surface class | Purpose | Constraints |
| --- | --- | --- |
| Bar | Persistent session chrome and the main entry point into managed popups | Thin UI only; no duplicate orchestration layer |
| Managed overlay popups | Calendar, tray, MPRIS, quick settings, full settings, notification drawer, power menu | Hosted by one overlay owner and participate in exclusivity |
| Transient feedback surfaces | Tooltip, OSD, toast, root notification popups | Must not compete with managed popup exclusivity |
| IPC | Shell-wide command surface | Must operate on existing shell services and surfaces, not bypass them |

## Popup Contract

Invariants:

- At most one managed overlay popup is visible at a time.
- The overlay host owns focus, outside-click dismissal, and scrim behavior.
- Popups may request handoff, but they do not create or manage sibling popups
  directly.
- Transient feedback surfaces are independent; switching managed popups must
  not dismiss them.
- Every managed popup exposes one host-facing shape: `active`,
  `close()`, `overlayVisible`, `panelItem`, `focusTarget`, and scrim
  properties (`scrimEnabled`, `scrimColor`, `scrimOpacity`).

## State Ownership

| Owner | Use it for | Do not use it for |
| --- | --- | --- |
| Singleton service | State or commands shared across bar, settings, quick settings, or IPC | One-off view state |
| Settings host | Snapshot-style theme data, preset editing, wallpaper browsing, and other host-owned theme orchestration | Domains that already have a reusable live service |
| Local pane/view state | Selection, expansion, filters, draft input, local navigation | Shared system or shell-wide state |

Constraints:

- One capability gets one write path.
- If a domain is service-owned, every surface talks to the service.
- If a domain is host-owned, panes emit intents and the host performs the
  mutation.
- Quick Settings is the shallow surface: summary state, bounded toggles, and
  jumps to deeper settings only.

## Bar Contract

- Bar modules may display state, surface tooltips, and route clicks into popup
  toggles.
- Shared domains must reuse the same service contract as Settings, Quick
  Settings, and IPC.
- The bar must not introduce its own polling or parser layer for domains that
  already have a shared service.
- Purely local or upstream-provided read-only domains can stay outside
  repo-specific services.

## Theme Integration

| Concern | Owner |
| --- | --- |
| Generated palette/font data | The theming pipeline via `GeneratedTheme.json` |
| Theme file format and writes | `desktopctl theme` and the theming targets |
| Layout geometry, popup sizing, and animation constants | Quickshell code |
| Theme mutation commands | Settings host and shell IPC, both through `desktopctl theme` |

Invariants:

- QML never edits generated theme files directly.
- Theme changes propagate through real completion of the apply command, not
  fixed timers.
- Shell visuals refresh from the generated theme file; settings controls refresh
  from a reloaded theme snapshot.
- Shell font families are theme-managed; shell layout constants are not.
