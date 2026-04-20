# GRUB Specification

This spec describes the GRUB policy currently implemented by the host modules.
It is intentionally small because the repo uses only one GRUB pattern today:
EFI boot with manually maintained chainloader entries.

## Scope

| Host | Current contract |
| --- | --- |
| `laptop` | EFI GRUB with a manual entry for Windows Boot Manager |
| `desktop` | EFI GRUB with a manual entry for Windows Boot Manager |

## Policy

| Concern | Current contract |
| --- | --- |
| Bootloader | Use GRUB in EFI mode with `device = "nodev"` |
| Other EFI installs | Keep `useOSProber = false` and add explicit `extraEntries` instead |
| Ownership | The shared physical-host module (`system/physical-host.nix`, imported by `system/configuration.nix`) owns the shared `boot.loader.grub` block because the current laptop and desktop chainloader targets are intentionally identical |

Invariants:

- GRUB policy is shared across the current physical hosts through the shared physical-host module imported by `system/configuration.nix`.
- The repo does not rely on `os-prober` discovery for Arch or Windows entries.
- Chainloader paths are part of the host contract and must be updated when EFI
  loader locations change.
