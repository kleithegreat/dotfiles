# GRUB Quirks

## Other EFI installs are chainloaded manually
**Symptom:** Arch or Windows will not show up in GRUB unless their EFI loader paths are added explicitly.
**Cause:** The shared physical-host GRUB config keeps `useOSProber = false` and relies on `extraEntries` instead of auto-discovery.
**Status:** Workaround in place
**Resolution:** Maintain the shared `search --file` + `chainloader` entry in `system/physical-host.nix` while both physical hosts intentionally use the same Windows Boot Manager path. Split it back into host modules only if the machines need different EFI loader entries.
