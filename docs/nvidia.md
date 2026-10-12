# NVIDIA

## Intent

- Two deliberately different GPU stacks: the laptop is hybrid Intel-primary
  with NVIDIA PRIME offload (Nouveau disabled in its kernel config); the
  desktop is dedicated NVIDIA.
- GPU policy is host-local. Host modules own `hardware.nvidia.*`,
  `services.xserver.videoDrivers`, and `__EGL_VENDOR_LIBRARY_FILENAMES`
  (Mesa-only on the laptop, dual NVIDIA+Mesa on the desktop). The shared
  baseline must never set an EGL vendor policy — it would break the other host.
- Home Manager's only GPU role is selecting which Hyprland env file reaches the
  session (`hosts/laptop/env.lua` or `hosts/desktop/env.lua`, deployed as the
  session's `env-host.lua`) via the `host.hyprland.env` fact.
- Desktop-only suspend/resume workarounds stay in `hosts/desktop/system.nix`
  until they are proven unnecessary.

## Quirks

### Preserved VRAM needs a disk-backed temp path
The shared baseline makes `/tmp` tmpfs, but the driver's preserve-VRAM path
needs storage that survives suspend. `hosts/desktop/system.nix` sets
`NVreg_TemporaryFilePath=/var/tmp`; removing it brings back garbled resumes.

### systemd user-session freezing can black-screen resume
systemd 256+ freezes user sessions on suspend, which this stack does not
tolerate. The desktop sets `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` on
`systemd-suspend`. A desktop that wakes to a black screen after this setting
disappears is this bug, not a driver regression.

### `AQ_DRM_DEVICES` cannot use `/dev/dri/by-path` symlinks
Aquamarine parses `AQ_DRM_DEVICES` as a colon-separated list, and by-path
symlinks (`pci-0000:...`) contain literal colons, so the list splits into
garbage, no GPU backend is found, and Hyprland exits — the visible symptom is
SDDM accepting the password and bouncing straight back to the greeter.
`hosts/laptop/env.lua` therefore lists `/dev/dri/intel-gpu:/dev/dri/nvidia-gpu`,
colon-free symlinks that udev rules in `hosts/laptop/system.nix` attach to the
i915 and NVIDIA card nodes (Aquamarine canonicalizes each entry). `cardN`
numbering is not stable across kernel/driver changes, which is why the list does
not use it.

The rules match on the *PCI parent's driver*, not on PCI vendor or address.
The NVIDIA card hangs off an Intel PCIe root port (vendor 0x8086), so a vendor
match would give the dGPU the iGPU's name, and a simple-framebuffer card can sit
under the iGPU's address as well. Rules also require `DEVTYPE=drm_minor`, so
connector nodes and `renderD*` are not touched.

If a driver swap (`xe` for `i915`, `nouveau` for `nvidia`) or a rule typo leaves
a link missing, the laptop session dies at login exactly as described above.
Recovery needs no working session: pick the previous generation in GRUB, or
from a TTY run `ls -l /dev/dri` and `udevadm info --attribute-walk
--name=/dev/dri/cardN` to see what the rules failed to match. These rules were
dry-run against the live devices with `udevadm test`, but never exercised
through a real boot and relogin.

### CUDA capabilities are pinned shared, not per host
`cudaCapabilities` is the one piece of GPU policy in the shared baseline rather
than in a host module, because both hosts happen to be sm_86 (laptop RTX 3050
Mobile, desktop RTX 3080). It is pinned because CUDA is unfree, so
cache.nixos.org carries no substitutes and every CUDA package is built locally;
at the nixpkgs default the pin spans nine architectures and source-built
packages compile each device translation unit once per architecture.
`libnvshmem` is the derivation that makes this hurt — a full CMake/nvcc build
pulled in only as a comfyui -> torch dependency, whose nine-architecture form
OOMs the 16 GB laptop; pinning cuts the work ~9x. `pkgs/comfyui/default.nix` additionally turns off its
perftest and example device binaries, which nixpkgs hardcodes on. If a host
ever gets a GPU that is not sm_86, this pin has to grow a capability or move
into the host modules.

### Nix builds must stay off the tmpfs `/tmp`
Same root cause as the preserve-VRAM quirk above: the shared baseline makes
`/tmp` tmpfs, and nix-daemon builds in `TMPDIR`, so build trees are charged
against RAM alongside the compilers filling it. `system/physical-host.nix`
points the daemon at `/var/tmp/nix-daemon`. Without it, large CUDA/CMake build
trees reach OOM well before they run out of tmpfs.

### The resume failure has a specific signature
`kernelSuspendNotifier = false`, the temp-path override and the sleep-freeze
workaround are held by the pending validation in `TODO.md`. What they guard
against looks like a ~31s stall between `PM: suspend exit` and display
recovery, with `NVRM: _kgspRpcRecvPoll: GSP RM heartbeat timed out` in the
journal — compare against that before concluding a resume cycle passed.

### The Mesa-only EGL policy does not cover Vulkan
The laptop's `__EGL_VENDOR_LIBRARY_FILENAMES` looks like it keeps ordinary
apps off the dGPU, but the Vulkan loader still loads every ICD, NVIDIA's
included. GTK4's default Vulkan renderer therefore opens `/dev/nvidiactl` on
every launch and blocks ~1.4s while the runtime-suspended dGPU powers up, which
is what made cold Nautilus starts slow. `GSK_RENDERER=gl` in
`hosts/laptop/system.nix` keeps GTK on Mesa EGL. Check
`/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` before and after a
launch to see whether an app wakes the dGPU.

Related: [[nix]], [[hyprland]]
