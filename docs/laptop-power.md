# Laptop power

## Intent

- power-profiles-daemon's active profile is the only power switch; everything
  profile-dependent *follows* it (`scx_lavd --autopower`, the
  `power-profile-follower` unit), so any client, restart or boot restore lands
  in the same state.
- power-saver is the only efficiency mode; packing work onto E-cores is the
  scheduler's job, not CPU offlining.
- power-saver caps sustained package power (PL1) instead of disabling turbo.
  Performance has no cap to lift; its headroom is the fan profile.
- The EC owns the fans. Nothing may set `dell-smm-hwmon`'s `pwm*_enable` to
  manual (`1`): the firmware alone reads every sensor it shuts down on, and
  `pwm1_enable=2` returns `EINVAL` on the 9520, so only a power cycle undoes
  it. Fan aggressiveness is requested through `platform_profile`.
- A power sample covers an interval spent wholly on battery and awake, so no
  average mixes in charging or suspend. It credits the class focus time
  credits ([[focus-time]]), so watts and minutes per app join on one key.

## Quirks

### 400 MHz on the charger is the EC, not PL1
The 65 W USB-C adapter (the 9520 is rated for 130 W) runs at 15 V × 3.25 A,
about 49 W, though it offers 20 V; load drains the battery even while plugged
in. Below about 20% the EC asserts BD PROCHOT and every core holds 400 MHz
under load, in any profile, with the RAPL limits untouched, nothing in the
kernel log, and total draw under the adapter's limit. The charger IC's input
current limit, not PROCHOT, keeps the adapter within its contract; clearing
PROCHOT (MSR `0x1FC` bit 0) only lets load drain a nearly empty battery.

### psys is not battery draw
RAPL `psys` reads about 1.5 W under `current_now` × `voltage_now` at
17–21 W. Use it for fine-grained deltas; quote battery draw from the battery.

### A userspace fan curve powers the machine off with no log at all
Nine thermal zones (`SKIN`, `SEN1`–`SEN8`) have critical trips as low as 63 °C,
bind no cooling device, and the kernel powers off instantly at critical. The
journal just stops. If a rebuild dies silently under load, check
`pwm1_enable` before the battery or charger.

### PCIe ASPM policy parameters are silently ignored
The FADT declares ASPM unsupported, so `pcie_aspm.policy=` boots clean and
does nothing (only the boot log says so). Overriding needs `pcie_aspm=force`,
a riskier decision.
