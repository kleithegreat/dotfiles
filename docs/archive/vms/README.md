# Archived VM Setups

This directory keeps the last active Windows and macOS VM setup after the live
flake stopped importing those modules.

Archived files:

- `windows-vm.nix`: old shared `virtualisation.windowsVm` NixOS module.
- `windows-vm.md`: old Windows VM runbook and operational notes.
- `macos-vm.nix`: old desktop-only `virtualisation.macosVm` NixOS module.
- `macos-vm.md`: old macOS/OSX-KVM runbook and operational notes.

The archived modules are intentionally inert. To revive one, move or copy the
module back into its old live path, re-add the import, and re-enable the matching
option in the host configuration. The old mutable state roots were
`/var/lib/windows-vm/windows11` and `/var/lib/macos-vm/sequoia`.
