# GRUB Architecture

## Scope

Current implementation map for GRUB policy in the host modules as of
2026-04-07.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `hosts/laptop/system.nix` | Laptop bootloader policy | The laptop `boot.loader.grub` block enables EFI GRUB with one manual Windows chainloader entry |
| `hosts/desktop/system.nix` | Desktop bootloader policy | The desktop `boot.loader.grub` block enables EFI GRUB with a manual Windows chainloader entry |

## Current Layout

| Host | GRUB settings | Notes |
| --- | --- | --- |
| `laptop` | `enable = true`, `efiSupport = true`, `device = "nodev"`, `useOSProber = false`, plus one Windows `extraEntries` block | The laptop host module mounts the EFI system partition at `/boot/efi` through `boot.loader.efi.efiSysMountPoint` |
| `desktop` | `enable = true`, `efiSupport = true`, `device = "nodev"`, `useOSProber = false`, plus one Windows `extraEntries` block | The desktop host module mounts the EFI system partition at `/boot/efi` through `boot.loader.efi.efiSysMountPoint` |

## Shared Observations

- GRUB is configured only in host modules; there is no shared GRUB baseline in
  `system/configuration.nix`.
- Both hosts use manual `search --set=root --file ...` plus `chainloader ...`
  stanzas instead of OS autodiscovery.
- Both hosts currently carry only Windows chainloader entries; there is no
  current laptop-side Arch chainloader stanza.
- The only documented operational gotcha in this domain is the manual
  chainloader maintenance tracked in `docs/grub/QUIRKS.md`.
