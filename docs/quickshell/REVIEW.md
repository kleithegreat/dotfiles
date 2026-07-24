# Quickshell Review

Reviewed on 2026-06-10; deslop follow-up pass applied on 2026-07-01.

## Verdict

The shared-service and settings-host split is in much better shape than earlier
iterations. Most earlier shell/theme wiring gaps are now closed. Runtime
validation still needs a live shell smoke test on the revised popup animation
path and on the 2026-07-01 deslop pass surfaces.

## Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | Live shell smoke testing is still needed for popup animation behavior, the shared `SliderTrack`/`Divider`/`SectionLabel` extraction, the `SettingsPaneHeader` pane-header migration, and the 2026-07-01 deslop-pass surfaces (bar tooltips via `BarTooltipArea`, the rebuilt preset-editor field components, the shared Wi-Fi form fields, and the `ActionButton`/`StepperButton` button migrations across the settings panes). | Static QML review cannot prove output-churn, loader-prewarm, or rapid-toggle behavior under the live Quickshell/Hyprland runtime. The slider rewrite in particular unifies a set-on-press, commit-on-release input contract across the audio, brightness, and night-light sliders that has only been validated by inspection and `qmllint` parsing, not by interaction. |

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
- The 2026-07-01 deslop pass additionally wants a smoke test of: bar tooltips
  (hover each module; change volume/battery/network state while hovered and
  confirm the text live-updates), the preset editor's rebuilt field editors,
  the Wi-Fi password/enterprise forms (focus, reveal, Enter/Escape), the
  Display pane header undo/redo buttons, and the Mullvad location browser.
  Two accepted visual deltas from that pass: the calendar weather refresh
  button's hover highlight now uses the shared chevron styling, and hover-fade
  easing on migrated ghost buttons unifies to `HoverLayer`'s internal curve.
- `qmllint` was present in the environment, but without the Quickshell/Qt
  import setup it only produced generic missing-import warnings, so it did not
  provide a useful semantic validation pass for these files.
