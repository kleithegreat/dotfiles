# GRUB

## Intent

- EFI GRUB with `device = "nodev"` on both physical hosts, configured once in
  `system/physical-host.nix` behind the `host.isPhysical` gate.
- `useOSProber = false` on purpose: other EFI installs are chainloaded through
  explicit `extraEntries` (`search --set=root --file ...` + `chainloader ...`),
  never autodiscovered.
- The chainloader stays shared while both hosts use the same Windows Boot
  Manager path; split it back into host modules only if that stops being true.

## Quirks

### Other OSes will not appear until their loader path is added by hand
With os-prober off, a new or moved EFI install is invisible to GRUB until its
loader path is added to the shared `extraEntries` block. If a Windows entry
stops booting after a Windows update, check whether the EFI loader path moved
before suspecting the config.

Related: [[nix]]
