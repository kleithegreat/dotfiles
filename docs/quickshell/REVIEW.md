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
| Low | Live shell smoke testing is still needed for popup animation behavior, the per-consumer `SliderTrack` side effects, the `Divider`/`SectionLabel`/`SettingsPaneHeader` migrations, and the 2026-07-01 deslop-pass surfaces (bar tooltips via `BarTooltipArea`, the rebuilt preset-editor field components, the shared Wi-Fi form fields, and the `ActionButton`/`StepperButton` button migrations across the settings panes). | Static QML review cannot prove output-churn, loader-prewarm, or rapid-toggle behavior under the live Quickshell/Hyprland runtime. This risk has now paid out twice on one control: the brightness sliders could not be dragged at all, first because the Repeater reset on every write destroyed the delegate mid-gesture, and behind that because the enclosing `WheelFlickable` would have stolen the grab anyway (both fixed, see `QUIRKS.md`). Neither is visible in the slider's own QML or to `qmllint`. The per-consumer side effects are still unexercised — the audio sliders gate OSD suppression on `pressStarted`/`pressEnded` and the night-light slider commits on release. |
| Low | The `BrightnessService` write path no longer reads brightness back after a successful write, trusting the value it sent and the 30s safety-net poll. | If a monitor silently clamps or rejects a `setvcp` (a value below its own minimum, say), the slider will keep showing the requested value for up to 30s before the poll corrects it. Not observed on the BenQ, which accepts and reports back every value tested. |

## Checkpoint Notes

- Popup animation and first-paint behavior still need a live shell smoke test:
  rapidly toggle each bar popup, switch Quick Settings into Settings, open the
  Calendar weather page, and verify the notification drawer on both low-refresh
  and high-refresh displays.
- The shared `SliderTrack` interaction pass is partly done. Brightness dragging
  was broken outright — the Repeater reset destroyed the delegate on the first
  move — so anything previously "verified" by dragging a brightness slider was
  never actually exercised. Still to confirm by hand, now that drag works: that
  the Audio pane and Quick Settings volume sliders suppress the OSD across a
  whole drag rather than per-step, that the Display pane night-light slider
  still commits only on release, and that the per-device brightness sliders
  write continuously while dragging without the 30s status poll clobbering the
  knob mid-gesture. The knob's `Behavior on x` spring (`sliderSpring: 4`,
  `sliderDamping: 0.4`) has also never been seen during a real drag and may need
  retuning or disabling while pressed. Also confirm the migrated
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
