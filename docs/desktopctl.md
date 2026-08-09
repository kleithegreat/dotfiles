# desktopctl

## Intent

- One Rust binary owns the desktop glue: `daemon` (focus tracker, monitor
  watcher, solar scheduler, Unix-socket server), the theming pipeline
  (`theme`), `brightness`, Hyprland helpers (`hypr`), the night-light client,
  and `launch-quickshell`.
- The daemon is the single live arbiter of `hyprsunset`; see [[sun-schedule]].
  Quickshell and keybinds are request surfaces, never parallel writers.
- Repo root resolves from `DESKTOPCTL_REPO`, falling back to
  `~/repos/dotfiles`. Quickshell launch and repo-relative concat base paths
  depend on this.
- `desktopctl hypr` writes only its own generated override files
  (`input-runtime.lua`, `animations-override-data.lua`,
  `keybinds-override-data.lua`) — never the static or host-selected fragments
  they layer on top of.
- State mutations persist only after the required target apply succeeds, write
  only the mutated keys (per-key upserts in one transaction), and replace
  files atomically. See [[theming]] for the full contract.
- Keep new logic in small pure helpers with unit tests; the subprocess
  choreography around `hyprctl`, `hyprsunset`, `brightnessctl`, and `ddcutil`
  is integration-bound and should not grow.

## Quirks

### `ddcutil --display` costs ~10x what `--bus` costs — never reintroduce it
`--display <n>` is not an address: ddcutil re-runs full display detection on
every invocation, probing every I2C bus including ones that fail DDC checks.
Measured on the BenQ at `/dev/i2c-15`: ~0.99s get / ~1.61s set via
`--display`, vs ~0.10s / ~0.15s via `--bus`. `brightness.rs` therefore keys
DDC devices on the I2C bus parsed from `ddcutil detect --brief`, re-read on
every status call because bus numbers can move across reboots and hotplug.

### `--skip-ddc-checks` everywhere except `detect`
Reads and writes pass `--skip-ddc-checks` (a write drops 0.148s → 0.082s);
`detect --brief` deliberately keeps the checks, because classifying which
buses are usable is exactly what they do — skipping them there could put a
phantom slider in the shell.

### `--noverify` is rejected, not forgotten
It saves ~15ms, below perception, and verification is the only mechanism that
reports a rejected or clamped write — Quickshell no longer reads brightness
back after a write, so a non-zero exit from failed verification is what
triggers its corrective refresh. Note `man ddcutil` claims `--noverify` is the
default; measurement shows it is not (matching `--help`).

### A brightness slider jumping backward is a racing read, not a slow monitor
The BenQ reports a written value back correctly ~100ms after the write. When a
slider snaps to an old value, look for a status read *started before* the
write that landed after it — `BrightnessService.qml` guards exactly this with
`_writeEpoch`/`_statusEpoch`.

### External monitor brightness needs DDC/CI plus i2c access
If a monitor's slider is missing or dead: check the monitor OSD has DDC/CI
enabled, `ddcutil detect` sees the display, and the user is in the `i2c`
group after a rebuild *and fresh login*.

Related: [[theming]], [[sun-schedule]], [[hyprland]], [[quickshell]], [[focus-time]]
