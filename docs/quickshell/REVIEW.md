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
| Low | Live shell smoke testing is still needed for popup animation behavior and for the shared `SliderTrack`/`Divider`/`SectionLabel` extraction and the `SettingsPaneHeader` pane-header migration. | Static QML review cannot prove output-churn, loader-prewarm, or rapid-toggle behavior under the live Quickshell/Hyprland runtime. The slider rewrite in particular unifies a set-on-press, commit-on-release input contract across the audio, brightness, and night-light sliders that has only been validated by inspection and `qmllint` parsing, not by interaction. |
| Low | `bar/Volume.qml`'s tooltip text is evaluated once at `TooltipService.show()` time and does not live-update while hovered. | The agreed fix is caller-side: re-show from `onTooltipTextChanged` in `bar/Volume.qml` while `hoverA.containsMouse`; no `TooltipService.qml` change is needed because `show()` while warm updates the text immediately. Not yet applied. |
| Low | `SettingsNetworkPane.qml` does not reset `NetworkService` target/diagnostics state when the pane is hidden or destroyed. | The agreed fix is pane-side: `Component.onDestruction: NetworkService.resetTarget()` plus `onVisibleChanged: if (!visible) resetState()` in `config/quickshell/popups/settings/SettingsNetworkPane.qml`. The singleton cannot observe pane visibility itself. Not yet applied. |

## Checkpoint Notes

- Popup animation and first-paint behavior still need a live shell smoke test:
  rapidly toggle each bar popup, switch Quick Settings into Settings, open the
  Calendar weather page, and verify the notification drawer on both low-refresh
  and high-refresh displays.
- The shared `SliderTrack` extraction needs an interaction pass: click-to-seek
  and drag the Quick Settings volume slider, the Audio pane output/input/app
  sliders, the per-device brightness sliders, and the Display pane night-light
  temperature slider, confirming the OSD-suppression and night-light
  commit-on-release behavior still hold. Also confirm the migrated
  `SettingsPaneHeader` panes render their header and divider correctly.
- `qmllint` was present in the environment, but without the Quickshell/Qt
  import setup it only produced generic missing-import warnings, so it did not
  provide a useful semantic validation pass for these files.
