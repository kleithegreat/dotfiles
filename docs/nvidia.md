# NVIDIA

## Intent

- The laptop is Intel-primary with PRIME offload; the desktop is dedicated
  NVIDIA. GPU policy (`hardware.nvidia.*`, `videoDrivers`,
  `__EGL_VENDOR_LIBRARY_FILENAMES`) is host-local; the shared baseline never
  sets an EGL vendor policy. Home Manager's only GPU role is picking the host
  `env.lua`.
- `cudaCapabilities` is the one shared GPU setting, because both hosts are
  sm_86. CUDA is unfree and built locally, and at the default nine
  architectures libnvshmem (a comfyui → torch dependency) OOMs the laptop. A
  non-sm_86 GPU means growing the pin or moving it into hosts.
- Desktop suspend workarounds stay until a real resume cycle passes
  (`TODO.md`).

## Quirks

### The resume failure has a specific signature
A ~31s stall between `PM: suspend exit` and display recovery with
`NVRM: _kgspRpcRecvPoll: GSP RM heartbeat timed out` in the journal. Compare
against that before calling a cycle passed. Garbled resumes mean the
`/var/tmp` VRAM path is gone; a black screen means the sleep-freeze override is.

### `AQ_DRM_DEVICES` cannot use `/dev/dri/by-path` symlinks
It is colon-separated and by-path names contain colons; Hyprland finds no GPU
and SDDM bounces back to the greeter. Laptop udev rules create colon-free
`intel-gpu`/`nvidia-gpu` links, matched on the PCI parent's *driver* (the dGPU
sits under an Intel root port) and `DEVTYPE=drm_minor`. A driver swap or rule
typo kills login: boot the previous generation, or debug from a TTY with
`udevadm info --attribute-walk --name=/dev/dri/cardN`. Never exercised through
a real relogin.

### The Mesa-only EGL policy does not cover Vulkan
The Vulkan loader still opens NVIDIA's ICD, so GTK4 woke the suspended dGPU
(~1.4s) on every launch; `GSK_RENDERER=gl` prevents it. Check
`/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` around a launch.
