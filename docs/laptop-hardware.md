# Laptop hardware

## Intent

- Dell XPS 9520 hardware pins, udev rules, and out-of-tree kernel workarounds
  stay scoped to `hosts/laptop/system.nix` and `patches/linux/` rather than
  shared `system/` modules.
- Experimental patches carry explicit removal conditions and stay out of
  upstream submissions unless scoped cleanly to the verified hardware.

## Quirks

### The laptop touchpad needs its I2C controller pinned out of runtime PM
`powertop --auto-tune` puts 00:15.1, the I2C controller under the ELAN
touchpad, into runtime PM, and the cursor stutters after idle. A udev rule
covers probe; `powerManagement.powertop.postStart` covers boot. A separate
unit ordered after `powertop` forms a cycle that systemd breaks by silently
deleting the job, so the pin looks fine after a switch and is dead every boot.

### fwupd will not enumerate the ELAN touchpad, and must not be made to
04F3:311C is absent from fwupd's quirk DB and has no LVFS firmware. Forcing an
unofficial blob is what bricked this part in fwupd#5281. The runtime-PM pin is
the supported lever.

### The touchpad's 400 kHz in the DSDT is not its real bus speed
`TPD0`'s `I2cSerialBusV2` shows `0x00061A80`, but `_INI` overwrites it from the
`TPDS` firmware variable, so reading the table proves nothing. Upstream forces
100 kHz on this touchpad as `DLL0945` for lag from firmware smoothing; this
laptop's `VEN_04F3` misses that match, and interrupts stay near 135/s while it
lags, so the rate looks healthy. `i2c-force-100khz-elan-04f3-311c.patch` is an
unproven local experiment: `journalctl --dmesg --grep='forcing it to'` shows
the firmware's speed, no line meaning it was already 100 kHz. If lag recurs
with it applied, delete the patch. Never upstream it: `VEN_04F3` is too generic.
