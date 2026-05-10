# Quickshell Review

Reviewed on 2026-04-10.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most earlier shell/theme wiring gaps are now closed. Runtime
validation still needs a live shell smoke test on the revised popup animation
path.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | Live shell smoke testing is still needed for popup animation behavior. | Static QML review cannot prove output-churn, loader-prewarm, or rapid-toggle behavior under the live Quickshell/Hyprland runtime. |

## Checkpoint Notes

- Popup animation and first-paint behavior still need a live shell smoke test:
  rapidly toggle each bar popup, switch Quick Settings into Settings, open the
  Calendar weather page, and verify the notification drawer on both low-refresh
  and high-refresh displays.
- `qmllint` was present in the environment, but without the Quickshell/Qt
  import setup it only produced generic missing-import warnings, so it did not
  provide a useful semantic validation pass for these files.
