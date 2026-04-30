# Quickshell Review

Reviewed on 2026-04-10.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most earlier shell/theme wiring gaps are now closed. The remaining
issue is the older IPC completion gap below, plus runtime validation that still
needs a live shell smoke test on the revised popup animation path.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | `theme.apply` still has no positive completion reporting. | The `themeApplyProc` / `theme.apply` path in `config/quickshell/shell.qml` tokenizes args safely, rejects concurrent commands, and reports failures through `ToastService.showError(...)`, but successful completion is still silent. IPC callers can fire-and-forget a theme change, but they do not get a matching success signal or toast from the shell. |

## Checkpoint Notes

- Popup animation and first-paint behavior still need a live shell smoke test:
  rapidly toggle each bar popup, switch Quick Settings into Settings, open the
  Calendar weather page, and verify the notification drawer on both low-refresh
  and high-refresh displays.
- `qmllint` was present in the environment, but without the Quickshell/Qt
  import setup it only produced generic missing-import warnings, so it did not
  provide a useful semantic validation pass for these files.
