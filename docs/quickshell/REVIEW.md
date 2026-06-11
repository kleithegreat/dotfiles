# Quickshell Review

Reviewed on 2026-06-10.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most earlier shell/theme wiring gaps are now closed. Runtime
validation still needs a live shell smoke test on the revised popup animation
path.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | Live shell smoke testing is still needed for popup animation behavior. | Static QML review cannot prove output-churn, loader-prewarm, or rapid-toggle behavior under the live Quickshell/Hyprland runtime. |
| Low | `bar/Volume.qml`'s tooltip text is evaluated once at `TooltipService.show()` time and does not live-update while hovered. | The agreed fix is caller-side: re-show from `onTooltipTextChanged` in `bar/Volume.qml` while `hoverA.containsMouse`; no `TooltipService.qml` change is needed because `show()` while warm updates the text immediately. Not yet applied. |
| Low | `SettingsNetworkPane.qml` does not reset `NetworkService` target/diagnostics state when the pane is hidden or destroyed. | The agreed fix is pane-side: `Component.onDestruction: NetworkService.resetTarget()` plus `onVisibleChanged: if (!visible) resetState()` in `config/quickshell/popups/settings/SettingsNetworkPane.qml`. The singleton cannot observe pane visibility itself. Not yet applied. |
| Low | `SettingsPopup.qml`, `NotifDrawer.qml`, and `PowerMenu.qml` still declare dead `panelItem` / `focusTarget` properties. | Nothing reads them anywhere in `config/` (the other managed popups already dropped them); removal is safe cleanup pending those files' owners. |

## Checkpoint Notes

- Popup animation and first-paint behavior still need a live shell smoke test:
  rapidly toggle each bar popup, switch Quick Settings into Settings, open the
  Calendar weather page, and verify the notification drawer on both low-refresh
  and high-refresh displays.
- `qmllint` was present in the environment, but without the Quickshell/Qt
  import setup it only produced generic missing-import warnings, so it did not
  provide a useful semantic validation pass for these files.
