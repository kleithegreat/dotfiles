# GRUB Architecture

## Scope

Current implementation map for GRUB policy in the shared physical-host module
as of 2026-05-09.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `system/physical-host.nix` | Shared physical-host bootloader policy | The `boot.loader.grub` block inside the `host.isPhysical` gate enables EFI GRUB with one manual Windows chainloader entry, and the adjacent `boot.loader.efi` block pins `/boot/efi` |

## Current Layout

| Host | GRUB settings | Notes |
| --- | --- | --- |
| `laptop` and `desktop` | `enable = true`, `efiSupport = true`, `device = "nodev"`, `useOSProber = false`, plus one Windows `extraEntries` block | Both hosts inherit the shared physical-host GRUB/EFI policy unchanged; each host module only declares its own `/boot/efi` filesystem mount |

## Shared Observations

- GRUB is configured once in `system/physical-host.nix`, which is imported by
  `system/configuration.nix` and gated on `host.isPhysical`.
- Both hosts use manual `search --set=root --file ...` plus `chainloader ...`
  stanzas instead of OS autodiscovery.
- Both hosts currently carry only Windows chainloader entries; there is no
  current laptop-side Arch chainloader stanza.
- The only documented operational gotcha in this domain is the manual
  chainloader maintenance tracked in `docs/grub/QUIRKS.md`.
