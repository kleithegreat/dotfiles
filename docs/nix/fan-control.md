# Laptop Fan Control

## Scope

Current implementation map for the Dell laptop fan-control module as of
2026-04-07.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `hosts/laptop/system.nix` | Imports the fan-control module only on the laptop host | `hosts/laptop/system.nix:4-6` |
| `hosts/laptop/fan-control.nix` | Builds `i8kutils`, wires the Dell fan-control services, writes `i8kmon.conf`, and starts `i8kmon` | `hosts/laptop/fan-control.nix:4-93` |

## Current Behavior

| Concern | Current implementation |
| --- | --- |
| Kernel dependency | `boot.kernelModules = [ "dell-smm-hwmon" ]` makes the Dell SMM hwmon dependency explicit (`hosts/laptop/fan-control.nix:43-47`) |
| BIOS handoff | `services.hardware.dell-bios-fan-control.enable = true` disables BIOS fan management at boot and restores it on stop/suspend (`hosts/laptop/fan-control.nix:49-52`) |
| Device discovery | A udev rule tags the `dell_smm` hwmon device for systemd (`hosts/laptop/fan-control.nix:53-56`) |
| Fan profile | `/etc/i8kmon.conf` is generated from the repo module with four threshold bands and a 5-second polling timeout (`hosts/laptop/fan-control.nix:58-74`) |
| Userspace daemon | `systemd.services.i8kmon` binds to the tagged `dell_smm` device and restarts on failure (`hosts/laptop/fan-control.nix:76-91`) |
| Package exposure | The custom `i8kutils` derivation is added to `environment.systemPackages` (`hosts/laptop/fan-control.nix:4-40`, `hosts/laptop/fan-control.nix:93`) |

## Boundaries

- This module is laptop-only. It is not imported by the shared NixOS baseline
  or by any other host module.
- The repo owns the fan thresholds and service wiring. Runtime fan behavior
  still depends on Dell's `dell-smm-hwmon` interface and the `i8kmon`
  userspace daemon.
