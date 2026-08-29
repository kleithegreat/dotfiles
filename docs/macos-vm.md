# macOS VM

## Intent

- The host side is declarative; the guest is not, and will not be. macOS
  installs itself from Apple's recovery media, so `~/vm/macos` is state the
  config seeds once and then leaves alone — system disk, OpenCore's boot disk,
  the OVMF variable store. None of it belongs in the repo or the store.
- `pkgs/reims-vgpu` is upstream's QEMU fork with the device's Rust half linked
  in, configured the way upstream's own `scripts/qemu-build` configures it: one
  backend, chosen at configure time (`vulkan` here; `metal` is Apple-only). The
  four pins in that file are a single set. Upstream promises no ABI
  compatibility between revisions, so bumping one without the others links a
  device that cannot speak to the driver it is paired with.
- `pkgs/macos-vm` owns the whole lifecycle: fetch, install, boot. Upstream's
  `vm/boot-x86.sh` is an agent-testing harness — snapshot rails, timed kills,
  clones thrown away on exit — and none of that is wanted for a workstation
  guest, so the QEMU command line is reproduced here rather than the script
  vendored.
- One package, both hosts, no per-host branch. The laptop's dGPU is
  offload-only, so `nvidia-offload macos-vm run` is what reaches the NVIDIA ICD
  there; see [[nvidia]].
- The reims device is the only display whenever it is present. `--console`
  (vmware-svga) covers what happens before the guest's driver attaches; the two
  devices are never attached at the same time, because a second VGA gives the
  guest a second screen.
- A guest reboot is a real reboot. Upstream turns one into a shutdown because
  its measurement boots reboot-loop on a panic, but a workstation guest has to
  survive an OS update, and an update reboots several times.

## Quirks

### The QEMU tree has to sit inside the reims-vgpu tree
`hw/display/meson.build` builds the Rust staticlib by reaching
`meson.global_source_root() / '..' / '..'`, so QEMU belongs at `vendor/qemu`
inside the outer checkout. `sourceRoot` is therefore the outer tree — which is
also where `cargoSetupHook` looks for `Cargo.lock` — and the build descends in
`preConfigure`. Pointing `sourceRoot` at the QEMU directory reads as the
obvious cleanup and breaks both halves.

### Meson wraps have to arrive as sources
QEMU resolves keycodemapdb through a wrap, which downloads, and a git checkout
ships none of the subproject sources a release tarball carries. The build has
no network, so that one is fetched as a source and `--disable-download` turns a
missing wrap into a configure error rather than a fetch that cannot succeed.
`--disable-tcg` is there for the same reason as much as for size: TCG pulls in
QEMU's softfloat tests, which want two further wraps, and every guest this
binary exists for runs under KVM. Turning TCG back on brings the download error
back with it.

### Nothing renders before AppleParavirtGPU attaches
The device's UEFI GOP lives in a PCI option ROM built from
`crates/reims-vgpu-efi`, a crate with no lockfile to vendor, so this package
does not build it. `macos-vm run` shows an empty window through OpenCore and
early boot, and only comes alive once the guest driver loads. That is not a
hang — `macos-vm run --console` is how anything at the firmware or OpenCore
level gets seen.

### `fetch` writes to the working directory
`fetch-macOS-v2.py` ignores `--outdir` on its menu path and hardcodes `.`, so
`macos-vm fetch` changes directory into the VM directory first. Handing the
script `--outdir` instead quietly drops several GB wherever it was run.

### More than 8 vCPUs wedges the guest
Upstream caps SMP at 8 for this device: above it the x86 guest's storage kext
hangs in `StorageNode::init`. Raising `MACOS_VM_CPUS` past 8 buys a boot that
stops with no error rather than a faster guest.

### The Vulkan and windowing libraries are dlopened
`ash` and `winit` load `libvulkan.so.1`, wayland and X11 by name at runtime, so
nothing names them in the binary's RUNPATH and the wrapper's `LD_LIBRARY_PATH`
is what makes the device work at all. Drop it and QEMU still links, still
starts, and dies when the device initialises.

Related: [[nvidia]], [[nix]]
