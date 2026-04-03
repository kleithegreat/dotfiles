# GRUB Quirks

## Other EFI installs are chainloaded manually
**Symptom:** Arch or Windows will not show up in GRUB unless their EFI loader paths are added explicitly.
**Cause:** Both host GRUB configs keep `useOSProber = false` and rely on `extraEntries` instead of auto-discovery.
**Status:** Workaround in place
**Resolution:** Maintain host-specific `search --file` + `chainloader` entries in `hosts/laptop/system.nix` and `hosts/desktop/system.nix`.
