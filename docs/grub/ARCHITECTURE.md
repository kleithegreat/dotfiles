# GRUB Architecture

## Scope

Current implementation map for GRUB policy in the host modules as of
2026-04-07.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `hosts/laptop/system.nix` | Laptop bootloader policy | `hosts/laptop/system.nix:29-49` enables EFI GRUB with manual chainloader entries for Arch and Windows |
| `hosts/desktop/system.nix` | Desktop bootloader policy | `hosts/desktop/system.nix:40-55` enables EFI GRUB with a manual Windows chainloader entry |

## Current Layout

| Host | GRUB settings | Notes |
| --- | --- | --- |
| `laptop` | `enable = true`, `efiSupport = true`, `device = "nodev"`, `useOSProber = false`, plus `extraEntries` for Arch and Windows | EFI mountpoint lives at `/boot/efi` (`hosts/laptop/system.nix:17-20`, `hosts/laptop/system.nix:46-49`) |
| `desktop` | `enable = true`, `efiSupport = true`, `device = "nodev"`, `useOSProber = false`, plus one Windows `extraEntries` block | EFI mountpoint lives at `/boot/efi` (`hosts/desktop/system.nix:23-26`, `hosts/desktop/system.nix:52-55`) |

## Shared Observations

- GRUB is configured only in host modules; there is no shared GRUB baseline in
  `system/configuration.nix`.
- Both hosts use manual `search --set=root --file ...` plus `chainloader ...`
  stanzas instead of OS autodiscovery.
- The only documented operational gotcha in this domain is the manual
  chainloader maintenance tracked in `docs/grub/QUIRKS.md`.
