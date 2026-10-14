# Laptop power

## Intent

- power-profiles-daemon's active profile is the only power switch. Nothing
  sets profile-dependent state on its own schedule: everything that varies by
  profile *follows* that one value, so a switch from any client, a daemon
  restart, or the profile the daemon restores at boot all land in the same
  state. `scx_lavd --autopower` follows it for scheduling; the
  `power-profile-follower` unit follows it for what the daemon does not own.
- power-saver is the only efficiency mode. Packing work onto E-cores is the
  scheduler's job; taking CPUs offline was the earlier way to do it, and was
  removed in its favour.
- power-saver caps sustained package power (PL1) rather than disabling turbo,
  so bursts stay fast while long loads cannot drain the battery. Performance
  has no cap to lift: the firmware's PL1 is already far past what the chassis
  can cool, so its headroom is the fan profile.
- The EC owns the laptop's fans. Nothing in this repo may put
  `dell-smm-hwmon`'s `pwm*_enable` into manual mode (`1`). The firmware is the
  only controller that reads every sensor the firmware will shut down on, and
  it is the only one that ramps *before* a trip rather than after. Manual mode
  is also a one-way door: `pwm1_enable=2` returns `EINVAL` on the 9520, so only
  a power cycle hands the fans back.
- Fan aggressiveness is requested, not implemented: `platform_profile`, which
  power-profiles-daemon sets with the profile, is the supported lever. A
  userspace fan curve is not an acceptable substitute.

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

If a rebuild dies silently under sustained load, check `pwm1_enable` before
suspecting the battery or the charger.
