# Laptop thermal

## Intent

- The EC owns the laptop's fans. Nothing in this repo may put
  `dell-smm-hwmon`'s `pwm*_enable` into manual mode (`1`). The firmware is the
  only controller that reads every sensor the firmware will shut down on, and
  it is the only one that ramps *before* a trip rather than after.
- Fan aggressiveness is requested, not implemented: `platform_profile` via
  power-profiles-daemon is the supported lever, and `laptop-power-profile`
  (see [[desktopctl]]) is its entry point. A userspace fan curve is not an
  acceptable substitute for either.

## Quirks

### A userspace fan curve powers the machine off with no log at all
Driving the fans from CPU package temperature looks sufficient from the code
and is not. The XPS 15 9520 exposes nine more thermal zones — `SKIN` and
`SEN1`–`SEN8` — whose *critical* trips run as low as 63 °C (`SEN3`), far below
anything the package reaches, and
`ls /sys/class/thermal/thermal_zone*/cdev*` is empty: no zone binds a cooling
device, so none of them can cool themselves. The kernel is built with
`CONFIG_THERMAL_EMERGENCY_POWEROFF_DELAY_MS=0`, so the first zone to reach
critical cuts power immediately — no shutdown sequence, no OOM, no MCE, no
`critical temperature` line, because nothing survives to be flushed. The
journal simply stops mid-entry and the next boot looks like a hardware fault.

This killed the machine twice, ~3 minutes into `nrs` runs that compiled
natively-optimized packages, while a three-step curve held the fans at "low"
until 80 °C package. If a rebuild dies silently under sustained load, check
`pwm1_enable` before suspecting the battery or the charger.
