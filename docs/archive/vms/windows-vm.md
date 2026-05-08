# Windows VM

Archived setup. The physical hosts used to ship a declarative
`virtualisation.windowsVm` module in `system/windows-vm.nix`; that module is no
longer imported by the live flake. The last active module copy is archived next
to this document at `docs/archive/vms/windows-vm.nix`.

The archived module was active work in progress, not a complete store-managed
guest image. The guest media and mutable VM-owned state still required manual
operator steps.

## What Nix Manages

- A `windows-vm` launcher script in the system profile.
- A sparse qcow2 system disk at `/var/lib/windows-vm/windows11/system.qcow2`.
- Microsoft-keyed OVMF NVRAM seeded from `pkgs.OVMFFull.fd`.
- A writable TPM state directory for `swtpm`.
- `kvm` group access for the configured normal user so QEMU can use hardware
  acceleration without running the VM as root.

## Defaults

The old physical-host baseline enabled the module with these defaults:

- VM name: `windows11`
- State dir: `/var/lib/windows-vm/windows11`
- Installer ISO path: `/var/lib/windows-vm/windows11/isos/windows11.iso`
- Optional unattend ISO path: `/var/lib/windows-vm/windows11/isos/unattend.iso`
- Disk size: `50 GiB` qcow2
- Memory: `8192 MiB`
- vCPUs: `2`
- Preferred display: `2560x1440` with `64 MiB` VGA memory

## First Boot

1. Copy a Windows ISO into `/var/lib/windows-vm/windows11/isos/`.
   The launcher prefers the configured
   `/var/lib/windows-vm/windows11/isos/windows11.iso` path when present, but if
   that file is missing it will also auto-attach a lone `.iso` staged in the
   directory.
2. If you want unattended setup, also copy an answer-file ISO to
   `/var/lib/windows-vm/windows11/isos/unattend.iso`.
3. Rebuild if you have not already run `nixos-rebuild switch` since enabling the
   module.
4. Launch the guest with `windows-vm`.

The generated QEMU command already enables:

- KVM acceleration
- Q35 machine type
- UEFI boot via OVMF
- TPM 2.0 via `swtpm`
- An AHCI-attached installer CD-ROM when an ISO is staged
- An NVMe system disk
- User-mode NAT networking via `e1000e`
- GTK display output with an emulated VGA adapter sized for higher resolutions

## Notes

- If the configured ISO path does not exist but there is exactly one `.iso` in
  `/var/lib/windows-vm/windows11/isos/`, `windows-vm` auto-attaches that file.
- If the configured ISO path does not exist and there are multiple `.iso` files
  in `/var/lib/windows-vm/windows11/isos/`, `windows-vm` warns and boots the
  disk only; set `virtualisation.windowsVm.windowsIsoPath` explicitly if you
  want a specific image.
- The installer ISO is attached explicitly as a SATA CD-ROM with boot priority
  so OVMF can see it reliably on the Q35 machine type.
- If no installer ISO is available, `windows-vm` still starts and boots the
  disk only. That is useful after Windows is installed, but a fresh VM will
  land in UEFI until you stage an installer ISO.
- If `/var/lib/windows-vm/windows11/isos/unattend.iso` exists, `windows-vm`
  also attaches it automatically as a second virtual CD-ROM.
- The qcow2 disk is created only once. Changing `diskSizeGiB` later does not
  resize an existing disk automatically.
- A full reinstall/reset means deleting the guest-owned state under
  `/var/lib/windows-vm/windows11/` and rebuilding so activation seeds a fresh
  disk, NVRAM file, and TPM state.
