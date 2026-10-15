# macOS VM

## Intent

- The host side is declarative; the guest is not, and will not be. macOS
  installs itself from Apple's recovery media, so `~/vm/macos` is state the
  config seeds once and then leaves alone — system disk, OpenCore's boot disk,
  the OVMF variable store. None of it belongs in the repo or the store.
- `pkgs/reims-vgpu` is upstream's library and option ROM, built by upstream's
  own `cargo xtask dist` on its Vulkan platform (Metal is Apple-only);
  `pkgs/qemu-reims-vgpu` is upstream's QEMU fork linking it through
  pkg-config, as upstream's `make qemu` does. The library's rev, the QEMU rev
  its `vendor/qemu` names, and the keycodemapdb rev that QEMU's wrap names are
  a single set. Upstream promises no ABI compatibility between revisions, so
  bumping one without the others links a device that cannot speak to the
  driver it is paired with.
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

### Upstream's Cargo.lock is incomplete on purpose
The committed lock lists the `metal2vulkan` git crates with no `source`, and
upstream's own build lets cargo write them back in from the network (its
installer restores the committed file before every pull). The build has no
network to do that, so `cargo-lock-git-sources.patch` carries the missing
lines.
On a bump, regenerate it: run `cargo metadata` in the new tree and diff
`Cargo.lock` — anything beyond `source` lines means upstream changed more than
this.

### Meson wraps have to arrive as sources
QEMU resolves keycodemapdb through a wrap, which downloads, and a git checkout
ships none of the subproject sources a release tarball carries. The build has
no network, so that one is fetched as a source and `--disable-download` turns a
missing wrap into a configure error rather than a fetch that cannot succeed.
`--disable-tcg` is there for the same reason as much as for size: TCG pulls in
QEMU's softfloat tests, which want two further wraps, and every guest this
binary exists for runs under KVM. Turning TCG back on brings the download error
back with it.

### The OpenCore identity stays `iMac19,1`, Tahoe included
Tahoe's supported-hardware list has no 2019 iMac on it, which reads as a
reason to give the guest a listed model before installing. It is not: OSX-KVM's
stock `iMac19,1` boots the Tahoe recovery as it is, and switching
`SystemProductName` to `MacPro7,1` makes the recovery kernel reset straight
after `HANDOFF TO XNU` — the window returns to the boot picker with nothing on
screen to say why.

### `fetch` writes to the working directory
`fetch-macOS-v2.py` ignores `--outdir` on its menu path and hardcodes `.`, so
`macos-vm fetch` changes directory into the VM directory first. Handing the
script `--outdir` instead quietly drops several GB wherever it was run.

### More than 8 vCPUs wedges the guest
Upstream caps SMP at 8 for this device: above it the x86 guest's storage kext
hangs in `StorageNode::init`. Raising `MACOS_VM_CPUS` past 8 buys a boot that
stops with no error rather than a faster guest.

### The Vulkan and windowing libraries are dlopened
`ash` and SDL3 load `libvulkan.so.1`, wayland and xkbcommon by name at
runtime, so nothing names them in the binary's RUNPATH and the wrapper's `LD_LIBRARY_PATH`
is what makes the device work at all. Drop it and QEMU still links, still
starts, and dies when the device initialises.

Related: [[nvidia]], [[nix]]
