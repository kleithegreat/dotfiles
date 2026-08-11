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
`hosts/laptop/env.lua` therefore hardcodes `/dev/dri/card2:/dev/dri/card1` on
the laptop. Card numbering is not stable across kernel/driver changes; if the
laptop session dies at login after an update, re-check the card numbers before
anything else. Revisit by-path only when Aquamarine can represent embedded
colons (tracked in `TODO.md`).

### CUDA capabilities are pinned shared, not per host
`cudaCapabilities` is the one piece of GPU policy in the shared baseline rather
than in a host module, because both hosts happen to be sm_86 (laptop RTX 3050
Mobile, desktop RTX 3080). It is pinned because CUDA is unfree, so
cache.nixos.org carries no substitutes and every CUDA package is built locally;
at the nixpkgs default the pin spans nine architectures and source-built
packages compile each device translation unit once per architecture.
`libnvshmem` is the derivation that makes this hurt — a full CMake/nvcc build
pulled in only as a comfyui -> torch dependency, whose nine-architecture form
OOMs the 16 GB laptop. `pkgs/comfyui/default.nix` additionally turns off its
perftest and example device binaries, which nixpkgs hardcodes on. If a host
ever gets a GPU that is not sm_86, this pin has to grow a capability or move
into the host modules.

### Nix builds must stay off the tmpfs `/tmp`
Same root cause as the preserve-VRAM quirk above: the shared baseline makes
`/tmp` tmpfs, and nix-daemon builds in `TMPDIR`, so build trees are charged
against RAM alongside the compilers filling it. `system/physical-host.nix`
points the daemon at `/var/tmp/nix-daemon`. Without it, large CUDA/CMake build
trees reach OOM well before they run out of tmpfs.

### The desktop resume stack is untested since the PR #996 overlay was removed
Upstream's open driver now contains the `drm_mode_config_reset` fix the old
local overlay carried, so the overlay is gone — but no real suspend/resume
cycle has validated the new state. The remaining desktop settings
(`kernelSuspendNotifier = false`, the temp-path override, the sleep-freeze
workaround) stay until that validation happens. Historical symptom to compare
against: ~31s stall between `PM: suspend exit` and display recovery with
`NVRM: _kgspRpcRecvPoll: GSP RM heartbeat timed out` in the journal.

Related: [[nix]], [[hyprland]]
