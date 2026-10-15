# macOS VM

## Intent

- The host side is declarative; the guest never will be. `~/vm/macos` is
  state seeded once and then left alone.
- `pkgs/reims-vgpu` is upstream's library and option ROM via its own
  `cargo xtask dist`; `pkgs/qemu-reims-vgpu` is its QEMU fork. The library rev,
  the QEMU rev its `vendor/qemu` names, and that QEMU's keycodemapdb wrap rev
  are one set: upstream promises no ABI compatibility across revisions.
- `pkgs/macos-vm` owns fetch, install and boot. Upstream's `boot-x86.sh` is an
  agent-testing harness, so the QEMU command line is reproduced, not vendored.
- One package for both hosts; on the laptop, `nvidia-offload macos-vm run`
  ([[nvidia]]).
- The reims device is the only display when present; `--console`
  (vmware-svga) covers before its driver attaches. Never both: a second VGA is
  a second screen.
- A guest reboot is a real reboot (upstream turns it into shutdown); OS
  updates reboot several times.

## Quirks

### Upstream's Cargo.lock is incomplete on purpose
Its git crates have no `source` and cargo fills them in from the network,
which the sandbox lacks; `cargo-lock-git-sources.patch` carries them. On a
bump, run `cargo metadata` in the new tree and diff `Cargo.lock` — anything
beyond `source` lines means more changed.

### Meson wraps have to arrive as sources
keycodemapdb is fetched as a source, and `--disable-download` makes a missing
wrap a configure error. `--disable-tcg` also drops the softfloat tests' two
wraps; re-enabling TCG brings the download error back.

### The OpenCore identity stays `iMac19,1`, Tahoe included
`MacPro7,1` makes the Tahoe recovery kernel reset right after
`HANDOFF TO XNU`; the stock identity boots it fine.

### `fetch` writes to the working directory
The fetch script ignores `--outdir` on its menu path, hence the `cd`.

### More than 8 vCPUs wedges the guest
The storage kext hangs in `StorageNode::init` with no error.

### The Vulkan and windowing libraries are dlopened
Drop the wrapper's `LD_LIBRARY_PATH` and QEMU still starts, then dies when the
device initialises.
