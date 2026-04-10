# Quickshell Review

Reviewed on 2026-04-09.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most of the earlier shell/theme wiring gaps are now closed, and the
frontend polish checkpoint now covers the shared primitives, optimistic update
plumbing, first-paint cleanup, and the settings affordances/layout fixes. The
custom shell controls remain intentionally pointer-first rather than trying to
overlay a repo-specific keyboard-navigation model on bar modules and popup
tiles. The remaining issue is the older IPC completion gap below, plus runtime
validation that still needs a live shell smoke test.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | `theme.apply` still has no positive completion reporting. | The `themeApplyProc` / `theme.apply` path in `config/quickshell/shell.qml` now tokenizes args safely and reports failures through `ToastService.showError(...)`, but successful completion is still silent. IPC callers can fire-and-forget a theme change, but they do not get a matching success signal or toast from the shell. |

## Checkpoint Notes

- The current checkpoint includes the shared bounce model, optimistic write
  staging, first-paint fixes for focus-time/app-usage charts, preset-editor
  wallpaper validation, responsive settings sizing, Quick Settings overflow
  scrolling, and a documented pointer-first policy for custom shell controls
  instead of custom focus rings or tab navigation.
- Runtime validation is still pending. `qmllint` was not available in the
  environment during this checkpoint, so the code changes should still be
  followed by an actual Quickshell smoke test.
