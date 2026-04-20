# Windows VM

The desktop host now ships a declarative `virtualisation.windowsVm` module in
`hosts/desktop/windows-vm.nix`.

This path is active work in progress, not abandoned documentation. The module is
live today, but the guest media and mutable VM-owned state still require manual
operator steps.

## What Nix Manages

- A `windows-vm` launcher script in the system profile.
- A sparse qcow2 system disk at `/var/lib/windows-vm/windows11/system.qcow2`.
- Microsoft-keyed OVMF NVRAM seeded from `pkgs.OVMFFull.fd`.
- A writable TPM state directory for `swtpm`.
- `kvm` group access for the desktop user so QEMU can use hardware
  acceleration without running the VM as root.

## Defaults

The current desktop host enables the module with these defaults:

- VM name: `windows11`
- State dir: `/var/lib/windows-vm/windows11`
- Installer ISO path: `/var/lib/windows-vm/windows11/isos/windows11.iso`
- Disk size: `50 GiB` qcow2
- Memory: `8192 MiB`
- vCPUs: `2`

## First Boot

1. Copy a Windows ISO to
   `/var/lib/windows-vm/windows11/isos/windows11.iso`.
2. Rebuild if you have not already run `nixos-rebuild switch` since enabling the
   module.
3. Launch the guest with `windows-vm`.

The generated QEMU command already enables:

- KVM acceleration
- Q35 machine type
- UEFI boot via OVMF
- TPM 2.0 via `swtpm`
- An NVMe system disk
- User-mode NAT networking via `e1000e`
- GTK display output

## Notes

- If the ISO path does not exist, `windows-vm` still starts and boots the disk
  only. That is useful after Windows is installed, but a fresh VM will land in
  UEFI until you stage an installer ISO.
- The qcow2 disk is created only once. Changing `diskSizeGiB` later does not
  resize an existing disk automatically.
- A full reinstall/reset means deleting the guest-owned state under
  `/var/lib/windows-vm/windows11/` and rebuilding so activation seeds a fresh
  disk, NVRAM file, and TPM state.
