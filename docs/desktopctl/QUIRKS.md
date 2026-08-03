# desktopctl Quirks

## `dark_hint` and night-light mode are only partly coupled
**Symptom:** Changing the app/browser dark hint leaves `hyprsunset` untouched, and toggling night light `auto` / `on` / `off` does not immediately flip `dark_hint`.
**Status:** Current behavior
**Resolution:** Treat `desktopctl night-light ...` as the `hyprsunset` control surface and `desktopctl theme set dark_hint ...` as the persisted app/browser hint surface. The canonical split-ownership contract lives in `docs/sun-schedule/SPEC.md` (Ownership Boundaries).

## `ddcutil --display` costs ~10x what `--bus` costs
**Symptom:** Every DDC/CI brightness read or write took about a second, making the Quickshell brightness slider feel laggy and unreliable on the external monitor.
**Status:** Fixed; do not reintroduce `--display`.
**Resolution:** `--display <n>` is not an address — `ddcutil` resolves it by re-running display detection on every invocation, probing each I2C bus including ones that fail DDC checks (a laptop eDP panel costs the most). Measured on the BenQ at `/dev/i2c-15`: `--display 1 getvcp 10` ≈ 0.99s and `--display 1 setvcp 10 <n>` ≈ 1.61s, versus ≈ 0.10s and ≈ 0.15s for the same calls with `--bus 15`. `desktopctl/src/brightness.rs` therefore keys `BrightnessDevice::Ddc` on the I2C bus number parsed out of `ddcutil detect --brief`. Bus numbers can move across reboots and hotplug, so they are re-read from `detect` on every `brightness status` rather than cached to disk.

## `--skip-ddc-checks` is adopted for reads and writes but not for `detect`
**Symptom:** Per-bus DDC operations spend more time re-proving that DDC works on the bus than doing the actual operation.
**Status:** Current behavior, deliberate.
**Resolution:** `ddcutil()` in `desktopctl/src/brightness.rs` passes `--skip-ddc-checks` on every `getvcp`/`setvcp`; interleaved over 10 rounds a write drops from 0.148s to 0.082s and a read from 0.112s to 0.032s. This was checked for downsides before adopting: `detect --brief` output is byte-identical with and without it (the eDP panel is still reported as `Invalid display`), a `getvcp` against a bus where DDC genuinely does not work fails the same way in both modes, and `ddcutil` still exits 1 on failure so the wrapper's `output.status.success()` check keeps working.

`detected_ddc_devices()` builds its `detect --brief` command directly rather than through `ddcutil()`, so it keeps the checks. That is intentional: the flag only buys ≈ 0.12s there, and classifying which buses are usable is precisely what those checks do — a false positive would put a phantom slider in the shell.

## `--noverify` is deliberately not used
**Symptom:** `--noverify` looks like free speed on `setvcp`.
**Status:** Rejected; do not add.
**Resolution:** It saves ≈ 15ms per write (0.130s vs 0.148s interleaved), which is below perception, and it is the mechanism that reports a rejected or silently clamped write. `config/quickshell/BrightnessService.qml` no longer reads brightness back after a write, so a non-zero exit from a failed verification is the only thing that triggers its corrective `refresh()`. Note that `ddcutil --help` and `man ddcutil` disagree on the default here — the man page claims `--noverify` is the default, but measurement shows verification is on unless disabled, matching `--help`.

## The BenQ reports written brightness back immediately
**Symptom:** Suspicion that DDC/CI read-back is stale right after a write, which would explain a slider snapping to an old value.
**Status:** Not the cause — the panel is well behaved.
**Resolution:** After `setvcp 10 15`, the first `getvcp 10` roughly 100ms later already returns `15`, and stays correct across repeated reads. When a brightness slider appears to jump backward, look for a status read that was *started before* the write and landed after it, not for a slow monitor. `config/quickshell/BrightnessService.qml` guards exactly that case with `_writeEpoch` / `_statusEpoch`.
