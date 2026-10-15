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

## Quirks

### A userspace fan curve powers the machine off with no log at all
Nine thermal zones (`SKIN`, `SEN1`–`SEN8`) have critical trips as low as 63 °C,
bind no cooling device, and the kernel powers off instantly at critical. The
journal just stops. If a rebuild dies silently under load, check
`pwm1_enable` before the battery or charger.

### PCIe ASPM policy parameters are silently ignored
The FADT declares ASPM unsupported, so `pcie_aspm.policy=` boots clean and
does nothing (only the boot log says so). Overriding needs `pcie_aspm=force`,
a riskier decision.
