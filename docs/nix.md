# Nix

## Intent

- One flake, one `nixosConfigurations.<host>` per machine. `lib.systems.nixosHost`
  is plumbing only (module stack, `host` facts, Home Manager) and never hides
  host policy, hardware or package choice. Modules gate on host facts
  (`host.isPhysical`, `host.hyprland.*`), never on host names.
- Layers: `system/` shared privileged policy; `hosts/<name>/` hardware and
  host-only overrides; `home/` user packages and session glue; `config/`
  app config Home Manager deploys on rebuild; `styling/` theming data
  desktopctl deploys on theme apply ([[theming]]) — a file desktopctl merges
  lives in `styling/bases`, never `config/`; `lib/` helpers merged into `lib`.
- `xdg.configFile` deploys static files only, never generated theme outputs,
  which must stay writable outside the store. Trees are linked file by file so
  generated siblings can sit beside them.
- GUI apps needing system D-Bus services or polkit actions install through
  NixOS, not `home.packages`, which never registers system helpers
  (partition-manager, bitwarden-desktop).
- Every host runs the stock nixpkgs kernel. A custom boot-critical kernel
  (Clang/LTO/CachyOS, forced initrd lists) already caused an undebuggable
  no-journal boot failure; runtime policy goes in `kernelParams`, sysctls and
  services. Only the laptop carries Kconfig trims, each its own boot-validated
  change; they cost it every substitution, so it compiles through ccache.
- `pkgs.optimized.<name>` namespaces native builds and never shadows
  `pkgs.<name>`, so nothing that was not opted in loses cache hits. `zstd`,
  `lz4` and texlive stay out: the first two cascade rebuilds through
  libarchive/cmake/llvm and systemd/nix, and optimized texlive turned seven
  substitutions into ~1600 source builds from an unreliable mirror for code
  that is I/O-bound anyway.
- Deliberate, whatever audits say: `mitigations=off`, `max-jobs = 2`, and the
  checked-in `initialPassword` (bootstrap login; SSH password auth is off).

## Quirks

### Laptop Kconfig parent trims need child-symbol unsets
Disabling a parent (Nouveau, Hyper-V DRM, AMD SEV) orphans nixpkgs' mandatory
children and the config builder fails with `unused option`. Pair each trim with
`lib.kernel.unset` for the children; never reach for `ignoreConfigErrors`.

### Home Manager tracks `master` until `release-26.11` exists
An older release branch warns on every switch once nixos-unstable starts a new
cycle. Move to the branch when it exists; don't disable
`home.enableNixpkgsReleaseCheck`.

### `texlive.combined.scheme-medium` recurses on this pin
It pulls `asymptote` and evaluation blows up, so `home/packages.nix` uses
`scheme-small` plus extras. tlpdb dependencies are incomplete: after adding a
package, compile *every* document that loads it and add what the logs name.

### `pipe-operators` has to be bootstrapped by hand once per machine
The config needs the feature it turns on. Break the loop with
`nrs --option experimental-features "nix-command flakes pipe-operators"`;
`nixos-rebuild` rejects `--extra-experimental-features`, and the flake's
`nixConfig` is ignored until the user is trusted.

### Native builds are fenced by per-host `requiredSystemFeatures`
`-march=native` output depends on the builder CPU, so native derivations
require `native-optimized-<host>`, advertised only while
`host.nativeOptimizations` is on. The switch that first enables it runs through
a daemon that doesn't advertise it yet, hence `nrs` passing `system-features`
to `sudo nixos-rebuild` (a plain user `--option system-features` is refused).

### AppImage apps need shell-parent launchers for Vicinae
Vicinae's detached launch can take an AppImage/FHS wrapper handoff as success
and lose the app, so `pkgs/lmstudio` and `pkgs/bambu-studio` point their
desktop files at `$out/bin/<app>-desktop`, which runs the binary *without*
`exec`. Bambu stays on the Ubuntu AppImage (the nixpkgs source build is an
untested beta; the Fedora one links removed WebKitGTK 4.0); locale errors on
start mean a stale `language` key in `~/.config/BambuStudio/BambuStudio.conf`.

### Vicinae server has exactly one owner: Hyprland autostart
`services.vicinae` stays disabled; enabling it starts a second, competing
server. The server caches desktop entries across switches, so `nrs` replaces it.

### `nrs` mutes Hyprland's config watcher during activation
Home Manager swaps `~/.config/hypr/` links one at a time and each swap triggers
a reload against momentarily missing files. The restore trap covers
`EXIT INT TERM` because EXIT alone does not run when SIGINT kills zsh.

### Hyprland must follow the system nixpkgs
It dlopens the system Mesa for its GBM allocator; with its own glibc a system
bump broke `libgallium` and Hyprland aborted right after SDDM login, the same
symptom as the `AQ_DRM_DEVICES` quirk in [[nvidia]]. Crash reports in
`~/.cache/hyprland/` tell them apart. No Cachix: the stack is patched and
native-built, so the public cache can never hit.

### Haruna must share the session Qt/KDE package set
`QT_QPA_PLATFORMTHEME=qt6ct` loads a plugin built for the session's Qt ABI;
Haruna from another nixpkgs aborts at startup.

### Helium is not a normal Chromium package
It dlopens GTK file-chooser libraries that are never `NEEDED`, hence the
hand-built `LD_LIBRARY_PATH`. Its user-data-dir is `~/.config/net.imput.helium/`,
so External Extensions JSON is generated there, not under `helium/`.

### ComfyUI packaging traps
- PyTorch comes from the `-bin` wheels on `cudaPackages_13_3`; source torch is
  an uncached hours-long build and `torch-bin` on CUDA 12 is marked broken.
  Don't silence the broken check instead. First builds still compile NCCL and
  NVSHMEM for a long time, per host.
- `comfyui-workflow-templates` is a metapackage that keeps adding
  sub-distributions; a partial set yields an empty template browser. Re-read
  its `requires_dist` on bumps.
- Custom nodes can't pip-install into the store; use `extraPythonPackages`.

### MGLRU `min_ttl_ms` is the working-set protection
There are no LE9-style `vm.*` knobs to find. Don't lower `vm.swappiness` from
180: swap is zram-only, so swapping is cheaper than dropping page cache.

### Mission Center's "Run Additional Setup" is a dead end
`Error executing /tmp/missioncenter-magpie-setup: No such file` means its
`#!/bin/bash` is missing, not the script — and every line of it is inert on
NixOS anyway. `system/physical-host.nix` installs its two effects declaratively.
The powercap rule re-opens `energy_uj`, a known side channel (PLATYPUS,
CVE-2020-8694); weigh that before copying it.

### The laptop touchpad needs its I2C controller pinned out of runtime PM
`powertop --auto-tune` puts 00:15.1, the I2C controller under the ELAN
touchpad, into runtime PM, and the cursor stutters after idle. A udev rule
covers probe; an `ExecStartPost` on `powertop.service` covers boot. A separate
unit ordered after powertop forms a cycle that systemd breaks by silently
deleting the job, so the pin looks fine after a switch and is dead every boot.

### fwupd will not enumerate the ELAN touchpad, and must not be made to
04F3:311C is absent from fwupd's quirk DB and has no LVFS firmware. Forcing an
unofficial blob is what bricked this part in fwupd#5281. The runtime-PM pin is
the supported lever.
