# Quickshell Review

Reviewed on 2026-04-10.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most of the earlier shell/theme wiring gaps are now closed, and the
frontend polish checkpoint now covers the shared primitives, optimistic update
plumbing, first-paint cleanup, and the settings affordances/layout fixes. The
custom shell controls remain intentionally pointer-first rather than trying to
overlay a repo-specific keyboard-navigation model on bar modules and popup
tiles. The remaining issue is the older IPC completion gap below, plus runtime
validation that still needs a live shell smoke test on the revised popup
animation path.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | `theme.apply` still has no positive completion reporting. | The `themeApplyProc` / `theme.apply` path in `config/quickshell/shell.qml` now tokenizes args safely and reports failures through `ToastService.showError(...)`, but successful completion is still silent. IPC callers can fire-and-forget a theme change, but they do not get a matching success signal or toast from the shell. |

## Checkpoint Notes

- Calendar, Quick Settings, and the notification drawer now reserve popup
  height up front and suppress host-height animation during visible open/close,
  while Quick Settings no longer also animates `implicitHeight` inside the
  panel. Settings now keeps its large subtree layered only for the animation
  window, enables layer smoothing, and defers the broad service refresh batch
  until after the entrance interval. The intended result is less geometry churn
  and fewer expensive first-frame side effects on high-refresh displays.
- The popup and animation path above is still awaiting a real shell smoke test
  on both low-refresh and high-refresh displays. `qmllint` was present in the
  environment, but without the Quickshell/Qt import setup it only produced
  generic missing-import warnings, so it did not provide a useful semantic
  validation pass for these files.
- The current checkpoint includes the shared bounce model, optimistic write
  staging, first-paint fixes for focus-time/app-usage charts, preset-editor
  wallpaper validation, responsive settings sizing, Quick Settings overflow
  scrolling, and a documented pointer-first policy for custom shell controls
  instead of custom focus rings or tab navigation.
- Runtime validation is still pending, so the code changes should still be
  followed by an actual Quickshell smoke test.
