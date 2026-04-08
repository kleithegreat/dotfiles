# Quickshell Review

Reviewed on 2026-04-07.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most of the earlier shell/theme wiring gaps are now closed, and the
frontend polish checkpoint landed most of the shared primitives, optimistic
update plumbing, first-paint cleanup, and settings affordance work. The
remaining work is now concentrated in the unfinished shell-surface keyboard
pass plus the two older settings / IPC gaps below.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | The shell-surface keyboard pass is still unfinished. | The shared controls and settings sidebar are now keyboardable, but `QuickSettingsPopup.qml`, `bar/Bar.qml`, and `PowerMenu.qml` still contain raw pointer-only hit targets for tiles/footer actions, status modules, and power actions. The audit checkpoint should resume there before calling the frontend polish pass complete. |
| Medium | `neovide_mono_font_size_offset` exists in theming state but is missing from the editable settings list. | The backend and the settings UI no longer expose the same theme surface. |
| Low | `theme.apply` still has no positive completion reporting. | `config/quickshell/shell.qml:376-410` now tokenizes args safely and reports failures through `ToastService.showError(...)`, but successful completion is still silent. IPC callers can fire-and-forget a theme change, but they do not get a matching success signal or toast from the shell. |

## Checkpoint Notes

- The current checkpoint includes the shared bounce model, control focus rings,
  optimistic write staging, first-paint fixes for focus-time/app-usage charts,
  preset-editor wallpaper validation, responsive settings sizing, and Quick
  Settings overflow scrolling.
- The current checkpoint does not yet include the final tab-stop / Enter-Space
  activation sweep for Quick Settings tiles and footer actions, bar modules, or
  power-menu actions.
- Runtime validation is still pending. `qmllint` was not available in the
  environment during this checkpoint, so the remaining shell-surface pass
  should be followed by an actual Quickshell smoke test.
