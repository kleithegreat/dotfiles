# Laptop Fan Control

## Scope

Current implementation map for the Dell laptop fan-control module as of
2026-04-13.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `hosts/laptop/system.nix` | Imports the fan-control module only on the laptop host | The laptop host module's `imports = [ ./fan-control.nix ]` entry |
| `hosts/laptop/fan-control.nix` | Builds `i8kutils`, wires the Dell fan-control services, writes `i8kmon.conf`, and starts `i8kmon` | The dedicated laptop fan-control module |

## Current Behavior

| Concern | Current implementation |
| --- | --- |
| Kernel dependency | `boot.kernelModules = [ "dell-smm-hwmon" ]` in `hosts/laptop/fan-control.nix` makes the Dell SMM hwmon dependency explicit |
| BIOS handoff | `services.hardware.dell-bios-fan-control.enable = true` in `hosts/laptop/fan-control.nix` disables BIOS fan management at boot and restores it on stop/suspend |
| Device discovery | The `services.udev.extraRules` entry in `hosts/laptop/fan-control.nix` tags the `dell_smm` hwmon device for systemd |
| Fan profile | `hosts/laptop/fan-control.nix` generates `/etc/i8kmon.conf` with an explicit four-state `i8kmon` profile, a 2-second polling timeout, and earlier promotion into the max-fan state for sustained compile loads |
| Userspace daemon | `systemd.services.i8kmon` in `hosts/laptop/fan-control.nix` binds to the tagged `dell_smm` device and restarts on failure |
| Package exposure | The custom `i8kutils` derivation defined in `hosts/laptop/fan-control.nix` is added to `environment.systemPackages` |

## Boundaries

- This module is laptop-only. It is not imported by the shared NixOS baseline
  or by any other host module.
- The repo owns the fan thresholds and service wiring. Runtime fan behavior
  still depends on Dell's `dell-smm-hwmon` interface and the `i8kmon`
  userspace daemon.
- The module can only move between the fan states exposed by Dell firmware.
  It cannot command RPM values above the platform's hardware-defined maximum.
