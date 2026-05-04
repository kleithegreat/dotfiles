# macOS VM

The desktop host ships a desktop-local `virtualisation.macosVm` module in
`hosts/desktop/macos-vm.nix`. It is an OSX-KVM based macOS Sequoia VM launcher,
not a fully store-managed guest image.

This path is intentionally desktop-only because the current target is the
desktop's i5-11400 host. The RTX 3080 is not usable by macOS, so the guest uses
OSX-KVM's virtual display path rather than GPU passthrough.

## What Nix Manages

- A `macos-vm-prepare` helper in the system profile.
- A `macos-vm` QEMU launcher in the system profile.
- A writable state directory at `/var/lib/macos-vm/sequoia`.
- A sparse 64 GiB qcow2 system disk at
  `/var/lib/macos-vm/sequoia/mac_hdd_ng.img`.
- `kvm` group access for the configured normal user.
- `options kvm ignore_msrs=1`, required by OSX-KVM-style macOS guests on many
  KVM hosts.

## Defaults

The desktop module enables the VM with these defaults:

- macOS shortname: `sequoia`
- State dir: `/var/lib/macos-vm/sequoia`
- Disk size: `64 GiB` qcow2
- Memory: `12288 MiB`
- vCPU topology: `4` QEMU CPU threads, exposed as `4` cores in one socket
- CPU model: `Skylake-Client,-hle,-rtm` with the OSX-KVM Sequoia/Tahoe flags
- Video memory: `256 MiB` on VMware SVGA
- System disk controller: AHCI by default; `useNvmeSystemDisk = true` switches
  it to an emulated NVMe controller
- SSH forwarding: host TCP port `2222` to guest TCP port `22`

## First Boot

1. Rebuild the desktop host so the helpers and state directory exist:
   `nixos-rebuild switch --flake ~/repos/dotfiles#desktop`.
2. Run `macos-vm-prepare` as the normal user. It clones OSX-KVM under the state
   directory if needed, downloads Sequoia recovery media with
   `fetch-macOS-v2.py --shortname sequoia`, converts `BaseSystem.dmg` to
   `BaseSystem.img`, and ensures the 64 GiB qcow2 disk exists.
3. Launch the guest with `macos-vm`.
4. In the macOS installer, use Disk Utility to erase the 64 GiB disk as APFS,
   then install macOS.

The generated QEMU command enables:

- KVM acceleration
- Q35 machine type
- OSX-KVM OpenCore boot image
- OSX-KVM OVMF firmware and 1920x1080 NVRAM template
- Sequoia/Tahoe-compatible `Skylake-Client` CPU presentation
- USB keyboard and tablet input
- AHCI-attached OpenCore and installer; the system disk attaches via AHCI by
  default, or via emulated NVMe when `useNvmeSystemDisk = true`
- Host-side I/O on the system disk uses `cache=none,aio=io_uring` with
  `discard=unmap,detect-zeroes=unmap` so writes bypass the host page cache,
  use io_uring submission, and let qcow2 reclaim space on guest TRIM and
  zeroed writes
- User-mode NAT networking with SSH forwarded on host port `2222`
- VMware SVGA display output with extra video memory for higher in-guest modes

## Notes

- The OSX-KVM checkout, installer files, and guest disk are mutable state under
  `/var/lib/macos-vm/sequoia`. Nix creates the directory and initial disk, but it
  does not vendor or pin the upstream OSX-KVM repository.
- `macos-vm-prepare` does not update an existing OSX-KVM checkout. To update it,
  run `git -C /var/lib/macos-vm/sequoia/OSX-KVM pull --ff-only` manually.
- The qcow2 disk is created only once. Changing `diskSizeGiB` later does not
  resize an existing disk automatically.
- A full reinstall/reset means deleting the guest-owned state under
  `/var/lib/macos-vm/sequoia/` and rebuilding or rerunning `macos-vm-prepare` so
  the directory, disk, checkout, and installer media are recreated.
- The RTX 3080 is not supported by macOS. Treat this VM as a CPU/KVM-backed
  development and testing guest, not a GPU-accelerated macOS workstation.
- VMware SVGA in QEMU has no Metal/Quartz Extreme path for macOS, so the
  guest does pure software rendering. Bumping `videoMemoryMiB` reduces stalls
  at higher resolutions but does not add real GPU acceleration; only
  passthrough of a macOS-supported AMD card would.
- The host I/O tuning on the system disk assumes the qcow2 lives on a
  filesystem that supports `O_DIRECT` (ext4, xfs, btrfs without compression
  on that subvolume). If `cache=none` ever fails to open the disk on a
  different host filesystem, drop back to `cache=writeback` for that file.
- If the desktop wallpaper is white while the login wallpaper is correct, choose
  a static JPEG/PNG wallpaper inside macOS. Dynamic/video/HEIC wallpaper paths
  can fail on the unaccelerated VMware SVGA renderer even when the login screen
  cache still looks correct.
- Apple's macOS license restricts macOS virtualization to Apple-branded
  hardware; this document records the technical workflow only.
