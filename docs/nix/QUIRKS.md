# Nix Quirks

## `texlive.combined.scheme-medium` recurses on this nixpkgs revision
**Symptom:** Evaluation blows up if the TeX Live package set pulls in `scheme-medium`.
**Cause:** On this pinned nixpkgs revision, `scheme-medium` pulls `asymptote` through `collection-binextra` and the evaluation recurses.
**Status:** Workaround in place
**Resolution:** `home/default.nix` uses `scheme-small` plus explicit extras like `latexmk` and `tikz-cd`.

## The shared `kevin` account keeps a checked-in bootstrap password on purpose
**Symptom:** Audits keep flagging `users.users.kevin.initialPassword` in `system/configuration.nix` as if it were an accidental secret leak.
**Cause:** The shared baseline intentionally keeps a reproducible local bootstrap login path for fresh installs and VM bring-up, while SSH password auth remains disabled separately in the same shared system module.
**Status:** Intentional bootstrap state
**Resolution:** Treat the checked-in `initialPassword` as deliberate bootstrap behavior, not as undocumented drift. If the bootstrap path changes, document the replacement in this domain instead of silently removing it and leaving future agents to guess whether it was accidental.

## Stock `services.fstrim` can touch the Windows NVMe through a shared EFI mount
**Symptom:** A weekly `fstrim` run trims `/boot/efi` even though the goal is only to discard unused blocks on the Linux filesystem.
**Cause:** The stock NixOS `services.fstrim.enable = true` unit trims every mounted filesystem it sees in `/etc/fstab` and `/proc/self/mountinfo`. On dual-boot hosts that mount a shared EFI system partition from the Windows drive at `/boot/efi`, that includes the Windows NVMe.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now defines a custom `fstrim-root.service` plus `fstrim-root.timer` instead of enabling `services.fstrim`. Keep the trim target pinned to `/` unless you explicitly want discard to reach additional mounted filesystems too.

## Optimizing low-level libraries explodes the rebuild graph
**Symptom:** A small `-march` overlay on `zstd` or `lz4` turns into huge rebuild cascades.
**Cause:** Those libraries sit low in shared dependency chains, pulling rebuilds through `libarchive`/`cmake`/`llvm` or `systemd`/`nix`.
**Status:** Workaround in place
**Resolution:** `overlays/native-optimized.nix` deliberately leaves `zstd` and `lz4` unoptimized unless a separate opt-in path is added later.

## Native-optimized derivations must carry host-specific `requiredSystemFeatures`
**Symptom:** Desktop and laptop can otherwise build different native outputs at the same store path, or remote scheduling can send a `-march=native` build to the wrong machine.
**Cause:** `-march=native` and `target-cpu=native` depend on the builder CPU, so the literal flag strings are not enough to distinguish safe cache/scheduler boundaries across hosts.
**Status:** Workaround in place
**Resolution:** `system/native-optimizations.nix`, `overlays/native-optimized.nix`, and `system/native-kernel-packages.nix` tag native derivations with `requiredSystemFeatures = [ "native-optimized-<host>" ]`, and `system/distributed-builds.nix` advertises only the current host's native feature while `enableNativeOptimizations` is enabled.

## Host `system-features` must not advertise `native-optimized-*` unconditionally
**Symptom:** Stock `x86_64-linux` builds stop behaving like generic cacheable builds when a host always claims a native-only feature.
**Cause:** Builder capability leakage changes scheduling and cacheability even when the optimization overlay is off.
**Status:** Workaround in place
**Resolution:** `system/distributed-builds.nix` appends `native-optimized-${hostName}` only while `enableNativeOptimizations` is enabled.

## Flake-input package overrides share the native helper path
**Symptom:** Hyprland, Hyprland plugins, `hyprqt6engine`, `opencode`, `snappy-switcher`, and Vicinae would otherwise diverge from the native optimization policy used for the selected nixpkgs packages.
**Cause:** Those derivations come from flake inputs or local overrides rather than the nixpkgs package set targeted by `overlays/native-optimized.nix`.
**Status:** Intentional design
**Resolution:** `system/configuration.nix` and `home/default.nix` both import `system/native-optimizations.nix` directly, so the flake-input packages carry the same `-O3 -march=native` / `target-cpu=native` flags and per-host `requiredSystemFeatures` tag as the overlay-managed nixpkgs packages.

## Stock packages can still miss cache hits through optimized wrapper inputs
**Symptom:** A package that is not listed in `overlays/native-optimized.nix` still rebuilds locally and gets a different derivation path from plain nixpkgs.
**Cause:** A global overlay rewrites the shared `pkgs` set. Once a package inside that set is replaced with a native-optimized variant, any consumer that depends on it in build inputs, runtime closures, or wrapper paths also gets a new derivation path.
**Status:** Workaround in place
**Resolution:** Do not apply the native overlay to the global `pkgs` set. `system/configuration.nix` and `home/default.nix` now keep the shared package set stock and instead create local `optimizedPkgs = pkgs.appendOverlays [ optimizedPackages.overlay ]` aliases only for the top-level packages that are intentionally rebuilt with host-native codegen. That keeps unrelated packages such as `codex`, `bitwarden-desktop`, and `adw-gtk3` on the stock cache path.

## Native-tagged rebuilds need a client-side bootstrap during the switch that enables them
**Symptom:** `nixos-rebuild switch` can fail before activation with `missing system features` even though the evaluated target config already includes `native-optimized-<host>` in `nix.settings.system-features`.
**Cause:** The build runs through the currently active Nix daemon, and that daemon does not start advertising the new host-native feature until after the switch finishes and the rebuilt `nix.conf` is live.
**Status:** Workaround in place
**Resolution:** `home/shell.nix` makes the `nrs` wrapper pass the target `system-features` list directly to `sudo nixos-rebuild switch` whenever native optimizations are enabled. That bootstraps the native-tagged derivations through the current daemon. Plain non-root `nix build --option system-features ...` is not sufficient here because `system-features` is a restricted setting for untrusted users.

## Physical-host kernels share one native helper
**Symptom:** Desktop and laptop should both rebuild one shared tuned physical-host kernel while still keeping host-specific preemption and each host's own Kconfig trim on top.
**Cause:** `system/native-kernel-packages.nix` now derives the kernel package set once from the CachyOS `cachyos-6.18.23-1.tar.gz` source, builds it with Clang + LLD ThinLTO, applies the matching `6.18/sched/0001-bore-cachy.patch`, keeps `ignoreConfigErrors = true`, and layers `KCFLAGS=-O2 -march=native`, `KRUSTFLAGS=-Ctarget-cpu=native`, and the host-specific native build feature. `system/configuration.nix` routes both physical hosts through that helper, then the host modules add the desktop/laptop preemption overrides, the laptop's Intel-only trim, and the desktop's dead-subsystem culls through `boot.kernelPatches`.
**Status:** Intentional design
**Resolution:** Keep the shared physical-host baseline in `system/configuration.nix` on `system/native-kernel-packages.nix`. Keep `ignoreConfigErrors = true` because the shared 6.18-based Kconfig still encounters dropped symbols on this nixpkgs revision. If you want the stock cached kernel back on a host, stop routing the physical-host `boot.kernelPackages` path through the helper instead of trying to partially undo the helper's BORE/BBR3/ThinLTO assumptions.

## Physical-host working-set protection uses MGLRU `min_ttl_ms`
**Symptom:** Desktop and laptop now ask for LE9/LE10-style working-set and file-cache protection, but the active tuning path is not an obvious `vm.*_kbytes` sysctl block in the host modules.
**Cause:** The shared kernel config keeps `LRU_GEN=y` and `LRU_GEN_ENABLED=y`, and `system/configuration.nix` now applies the runtime policy through `systemd.services.mglru-tuning`, which writes `y` to `/sys/kernel/mm/lru_gen/enabled` and `1000` to `/sys/kernel/mm/lru_gen/min_ttl_ms`. Even though the CachyOS 6.18 base source also carries `le9uo`, the repo intentionally uses MGLRU's own thrash-prevention knob as the active protection path.
**Status:** Intentional design
**Resolution:** Tune `systemd.services.mglru-tuning.script` in `system/configuration.nix` if you want a different pressure-relief threshold, or remove that service if you want stock MGLRU behavior. Do not assume the older LE9 `vm.anon_min_kbytes` / `vm.clean_low_kbytes` / `vm.clean_min_kbytes` knobs are the active control surface in this repo.

## Physical hosts disable CPU vulnerability mitigations on purpose
**Symptom:** `lscpu`, `/sys/devices/system/cpu/vulnerabilities/*`, or boot logs report that Spectre, Meltdown, and related CPU side-channel mitigations are disabled on the laptop and desktop.
**Cause:** `system/configuration.nix` now sets `boot.kernelParams = [ "mitigations=off" ]` on the shared physical-host gate.
**Status:** Intentional exception
**Resolution:** Keep the parameter on the shared physical-host baseline only if the performance tradeoff is intentional. Remove that physical-host kernel param in `system/configuration.nix` to restore the kernel's default mitigation policy. The VM host stays on the default path because it is outside that gate.

## Physical-host local builds are serialized on purpose
**Symptom:** Local Nix builds on desktop and laptop run one derivation at a time even though the machines have many CPU threads.
**Cause:** `system/configuration.nix` now sets `nix.settings.max-jobs = 1` on the shared physical-host gate. The repo leaves `cores = 0`, so a single heavy derivation can still use the full machine; this avoids stacking multiple already-parallel builds on top of each other.
**Status:** Intentional exception
**Resolution:** Keep the physical hosts on `max-jobs = 1` unless measurement shows a real win from concurrent derivations. If you want more concurrency later, change that shared physical-host setting in `system/configuration.nix` rather than widening the VM profile too.

## Narrow unfree predicates must cover transitive module closures, not just package lists
**Symptom:** Replacing `allowUnfree = true` with a small name allowlist still fails evaluation on packages that are not listed directly in `home.packages` or `environment.systemPackages`.
**Cause:** NixOS and Home Manager evaluate the full module graph. Unfree packages can enter indirectly through options such as `fonts.packages`, `programs.steam.*`, or CUDA-enabled dependency closures.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now uses `allowUnfreePredicate`, but its allowlist must include both the directly selected apps and the extra unfree package names already required by the current system closure, such as `sf-pro`, `symbola`, `steam-unwrapped`, and the CUDA userspace packages pulled in by existing desktop packages.

## Apple rotates `SF-Pro.dmg` behind a stable URL
**Symptom:** `nixos-rebuild` fails while building `sf-pro` with a fixed-output derivation hash mismatch on `SF-Pro.dmg`.
**Cause:** The Apple download URL in `overlays/local-packages.nix` stays the same while the bytes behind it change, so the repo-local `fetchurl` pin eventually stops matching upstream.
**Status:** Workaround in place
**Resolution:** Refresh the repo-local `sf-pro` pin in `overlays/local-packages.nix` by updating both the local version date and `src.hash` to the current Apple DMG, then retry the rebuild.

## Current SF Pro DMG exposes `Payload~` as a plain cpio archive
**Symptom:** `nixos-rebuild` fails while building `sf-pro` with `7z` aborting on `Payload~` with `ERROR: E_FAIL`.
**Cause:** Apple's current `SF Pro Fonts.pkg` no longer needs a second gzip-style unpack step after the `.pkg` is extracted. On the currently locked `SF-Pro.dmg`, `Payload~` is already a plain cpio archive.
**Status:** Workaround in place
**Resolution:** `overlays/local-packages.nix` now defines a local `pkgs.sf-pro` derivation that fetches the pinned Apple DMG directly and extracts `Payload~` with `cpio` when possible, falling back to `7z` for older layouts. `system/configuration.nix` installs that local package instead of the upstream `apple-fonts.nix` derivation.

## Generic `SF Pro` can look soft on Linux without extra fontconfig tuning
**Symptom:** UI text that explicitly requests `SF Pro`, especially bold labels at normal desktop sizes, can look fuzzier than expected even though the correct font package is installed.
**Cause:** The shared NixOS fontconfig defaults use grayscale antialiasing (`10-sub-pixel-none.conf`), and Apple's font package also exposes a catch-all `SF Pro` variable face that fontconfig can choose before the `SF Pro Text` optical cut that is better suited to small UI sizes.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now sets `fonts.fontconfig.subpixel.rgba = "rgb"` and adds a local fontconfig rule that prepends `SF Pro Text` whenever apps request the generic `SF Pro` family. If a monitor shows color fringes after rebuild, switch that `rgba` value to the panel's real order (`bgr`, `vrgb`, or `vbgr`).

## Home Manager packages do not register system-scoped helpers
**Symptom:** A GUI app installed only through `home.packages` starts, but its root helper never appears on the system bus and no polkit prompt is triggered.
**Cause:** Home Manager installs packages into the user profile, outside the NixOS system path and `services.dbus.packages` set that expose `share/dbus-1/system-services` files and link `share/polkit-1/actions` for system-wide activation.
**Status:** Workaround in place
**Resolution:** Install those apps through NixOS modules or `environment.systemPackages`. `system/configuration.nix` now enables `programs.partition-manager` so `kpmcore` is registered for both D-Bus activation and polkit, and `bitwarden-desktop` stays in `environment.systemPackages` for the same reason.

## Qt plugin paths break if you only point `QT_PLUGIN_PATH` at hyprqt6engine
**Symptom:** Qt and KDE apps can pick up the generated palette but still fall back to partially unstyled widgets or miss Kvantum styling, especially in D-Bus/systemd-activated helpers such as `xdg-desktop-portal-kde`.
**Cause:** `hyprqt6engine` installs under `lib/qt-6/`, outside the standard `/lib/qt-*/plugins` roots. A hand-written `QT_PLUGIN_PATH=${hyprqt6engine}/lib/qt-6` exposes the Hyprland platform theme itself but hides profile-installed plugins like `qt5ct`, `qt6ct`, and `libkvantum.so` unless NixOS also wires the normal profile-relative plugin directories.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now enables NixOS `qt.enable`, exports `QT_QPA_PLATFORMTHEME=hyprqt6engine`, keeps the hyprqt6engine root on `QT_PLUGIN_PATH`, and installs `qt5ct`, `qt6ct`, and Kvantum system-wide so both regular apps and user services resolve the same plugin set.

## Current OpenCode flake build misses root-level packages after the filtered Bun install
**Symptom:** `nixos-rebuild` fails while building the upstream `sst/opencode` flake package with root-level resolution errors such as Vite reporting `failed to resolve "extends":"@tsconfig/bun/tsconfig.json"` from `packages/shared/tsconfig.json`, or Bun reporting `Could not resolve: "prettier"` from `packages/opencode/src/cli/cmd/generate.ts`.
**Cause:** The current upstream `nix/node_modules.nix` runs `bun install` with workspace filters that exclude the repo root. That leaves the copied root `node_modules` tree with Bun's internal `.bun` store but without the top-level package links some build steps still resolve through.
**Status:** Workaround in place
**Resolution:** `home/default.nix` now swaps the upstream `packages.<system>.node_modules_updater` fake-hash output back to the discovered real hash (`sha256-i9TxYwWkJAR+kW6pbvhgQbRW9UYPtdrPQAGic4zPoa4=` on `x86_64-linux`) and injects that derivation into `packages.<system>.default`, so the repo can stay pinned to OpenCode commit `a546e88f37d1816adadf1e833a5fb4f39b7d56df` even though that commit's `nix/hashes.json` still advertises the stale `sha256-TVmmwqC0xX73fa6pIpRIfAqOLq2YOMJVQDRwNWHalWQ=` value. Do not wire `packages.<system>.node_modules_updater` into the build without overriding the hash: that output intentionally uses `lib.fakeHash` so it fails and reveals the current value. The remaining local workaround still runs during `postConfigure`: it rewrites `packages/shared/tsconfig.json` so its `extends` points at `packages/app/node_modules/@tsconfig/bun/tsconfig.json`, symlinks `node_modules/prettier` to the Bun-managed `node_modules/.bun/prettier@*/node_modules/prettier` package, and symlinks `node_modules/glob` to the already-installed `packages/opencode/node_modules/glob` before the OpenCode build runs.

## OpenChamber source builds need a repo-pinned root manifest for npm
**Symptom:** A straight npm-based build of upstream `openchamber/openchamber` fails before dependency resolution finishes, typically with npm rejecting the root `overrides` versus direct dependency ranges or choking on the VS Code package's `workspace:*` dependency.
**Cause:** Upstream develops against Bun, and the full monorepo metadata currently assumes Bun's workspace/override behavior. The web workspace itself builds fine under npm once the root manifest is trimmed to the `packages/ui` and `packages/web` workspaces and the overridden CodeMirror versions are pinned exactly.
**Status:** Workaround in place
**Resolution:** `pkgs/openchamber/default.nix` now source-builds OpenChamber from the upstream Git tag, but it replaces the root manifest with `pkgs/openchamber/package.json` and uses the generated `pkgs/openchamber/package-lock.json` so npm only sees the web-facing workspaces and their exact override pins.

## The Claude bridge only implements the OpenCode API subset OpenChamber currently needs
**Symptom:** OpenChamber works against the local Claude bridge for health checks, provider/model selection, session creation, session history, and basic streamed chat, but deeper OpenCode-only features such as true snapshot reverts, project sync history replay, or richer permission/question flows are still conservative stubs.
**Cause:** `pkgs/openchamber-claude-bridge/index.mjs` is intentionally a compatibility layer around the `claude` CLI, not a full OpenCode reimplementation.
**Status:** Intentional limitation
**Resolution:** Keep the bridge focused on the endpoint surface OpenChamber actively consumes. The local `patches/openchamber/claude-backend-selector.patch` teaches OpenChamber to manage the bridge as an alternate backend from the normal in-app settings screen, but it still relies on the bridge's OpenCode-compatibility subset rather than a full backend reimplementation.

## Wine 11 Ableton prefixes need fresh state and per-prefix WineASIO registration
**Symptom:** Ableton Live 12 Lite launches without a usable ASIO device, or a reused older Wine prefix behaves inconsistently after moving to the current desktop Wine package set.
**Cause:** During the investigation, the desktop host used `wineWow64Packages`-based Wine 11 packages. nixpkgs notes that prefixes created against the deprecated `wineWowPackages` family are not backward compatible. Separately, `wineasio` installs its DLLs into the system profile, but each Wine prefix still needed the driver copied into `drive_c/windows/system32` and registered with `wine regsvr32`.
**Status:** Historical investigation note
**Resolution:** If this setup is ever revived, keep Ableton in a dedicated fresh `WINEARCH=win64` prefix under the home directory and rerun the documented WineASIO registration commands whenever that prefix is created or recreated.

## Wine-generated Ableton desktop entries miss the working launch environment
**Symptom:** Launching Ableton Live 12 Lite from Vicinae or another app launcher falls back to the splash screen stuck on `Initializing MIDI inputs and outputs`, even though a manual terminal launch works.
**Cause:** During the investigation, Wine's generated `~/.local/share/applications/wine/Programs/Ableton Live 12 Lite.desktop` only set `WINEPREFIX` and ran plain `wine ...lnk`. The working setup also needed the prefix's Wayland/JACK launch environment, specifically `WINEDLLOVERRIDES=winepulse.drv=d;winex11.drv=d` and a `pw-jack` wrapper around `wine`.
**Status:** Historical investigation note
**Resolution:** If this setup is ever revived, override that exact desktop entry path or replace it locally so launchers use the wrapper command rather than plain `wine`.

## Ableton still depends on mutable prefix tweaks beyond the NixOS module
**Symptom:** A fresh prefix created from only the documented WineASIO steps can still show stale rendering, background helper crashes, rough UI behavior, or DPI/input mismatches even though the app launches.
**Cause:** The stable setup currently also relies on mutable per-prefix tweaks: DXVK DLL copies plus native overrides, native VC++ runtime overrides, an Image File Execution Options `dpiAwareness=2` override for `Ableton Live 12 Lite.exe`, and an Ableton `Options.txt` with `-DisableAutoBugReporting`.
**Status:** Expected manual setup
**Resolution:** Treat the Wine prefix as mutable app state in the home directory and reapply those documented post-install tweaks whenever the prefix is recreated.

## Ableton display/backend tradeoffs are still unresolved
**Symptom:** No tested Wine display path is fully correct yet. The Wine Wayland path clips the bottom of the Ableton UI, skews click targeting, and behaves differently for `Delete` versus `Backspace`. The Xwayland path removes the bottom clipping and restores the expected `Delete` key behavior, but click targeting is still off and the Ableton authorization popup can still be difficult to interact with. Wrapping Xwayland in a fixed-size Wine virtual desktop keeps the app in one host window but still does not fix the hit-testing mismatch. A tested X11 driver override with `Managed=N` and `Decorated=N` reduced flicker and helped the auth popup, but made cursor targeting even worse and is not recommended.
**Cause:** The remaining problems appear to be in Wine's client-area/input handling for Ableton rather than in the PipeWire or JACK path. External research reinforces that diagnosis: current Live 12-on-Linux guides already document inaccurate mouse coordinates in non-fullscreen windowed mode, and Microsoft's DPI docs plus Ableton's own logs point at a DPI-awareness mismatch (`Effective process DPI awareness: 0` until the prefix override forced it higher). DXVK logs also showed swapchain heights larger than the visible output (for example `1920x1096` on a `1920x1080` display), which matches the clipped bottom edge and the progressively lower click targets. Later `wine-tkg` instrumentation sharpened that further: the final `screen_to_client()` transform was consistent, but it was using a top-level/editor window origin derived from geometry that Wine already believed was much taller than the visible X11 window. Producer-side `SetWindowPos` traces then showed child `WM_NCCALCSIZE` updates mutating `new_client` even when `new_window` and `new_visible` stayed fixed, and later direct boundary tracing proved that the bad `new_client` was already present in `params.rgrc[0]` immediately after `WM_NCCALCSIZE` returned. Renderer-side traces then confirmed that `win32u/vulkan.c` simply uses that already-bad `ClientRect` for swapchain sizing, so DXVK looks more like a consumer of the bad geometry than the original producer.
**Status:** Under investigation
**Resolution:** Keep all three launcher variants documented (`ableton-live-12-lite`, `ableton-live-12-lite-x11`, and `ableton-live-12-lite-x11-desktop`) and continue testing against the same prefix so the backend-specific behavior stays comparable. Treat fullscreen and manifest-level DPI workarounds as the highest-value early experiments, then move to direct Wine geometry tracing. Current evidence now points most strongly at the Win32 child layout path (`calc_winpos`, `calc_ncsize`, `set_window_pos`) plus the final Vulkan surface extent selection rather than at the final mouse-message coordinate transform itself.

## Wine-NSPA is currently a source-porting project on this toolchain
**Symptom:** The published `Wine-NSPA 8.19` binary package is not a simple runner swap on this host, and a source build from `wine-nspa-8x-git/non-makepkg-build.sh` progresses only after multiple local compatibility fixes.
**Cause:** The Arch binary release expects FHS loaders and `librtpi` integration, which makes binary testing awkward on NixOS. The source tree itself can be built on NixOS, but older patches now hit modern toolchain issues such as hardcoded `/usr/bin/perl` shebangs, strict `CONTAINING_RECORD` type checking, `bool`/`true` identifier collisions, and PIE/preloader linker problems.
**Status:** Under investigation
**Resolution:** Treat Wine-NSPA as a custom source-port effort rather than a quick A/B runner download. Build it 64-bit only, keep Wayland disabled in that tree, use a cloned Ableton prefix, and expect to patch forward multiple source-compatibility issues before it is ready for GUI testing.

## Declarative Windows VM media and guest state stay partly manual
**Symptom:** The desktop Windows VM module evaluates and seeds `/var/lib/windows-vm/windows11`, but first boot can still land in UEFI or an existing guest keeps its old size, boot state, or TPM state after a Nix change.
**Cause:** `hosts/desktop/windows-vm.nix` makes the host-side QEMU wrapper declarative, but the installer ISO plus the mutable guest-owned qcow2, NVRAM, and TPM directories intentionally live outside the Nix store.
**Status:** Expected manual state
**Resolution:** Copy a Windows ISO to `/var/lib/windows-vm/windows11/isos/windows11.iso` before the first launch. If you want a clean reinstall or to reset secure-boot/TPM state, delete `/var/lib/windows-vm/windows11/system.qcow2`, `/var/lib/windows-vm/windows11/OVMF_VARS.ms.fd`, and `/var/lib/windows-vm/windows11/tpm/`, then rebuild so activation recreates fresh state. If you later increase `virtualisation.windowsVm.diskSizeGiB`, resize the existing qcow2 manually because activation only creates the disk when it does not already exist.

## `tailscaled` can stall shutdown on physical hosts
**Symptom:** Reboot or poweroff can occasionally sit on "A stop job is running for Tailscale node agent" long enough to hit most of systemd's default 90 second stop timeout.
**Cause:** Upstream `tailscaled` shutdown is normally fast, but Linux `wgengine` teardown has had intermittent close/deadlock races. The current hosts use NetworkManager plus `resolvconf`/`openresolv`, so this repo does not rely on `systemd-resolved` staying up for Tailscale cleanup.
**Status:** Workaround in place
**Resolution:** `hosts/laptop/system.nix` and `hosts/desktop/system.nix` set `systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";`, which stays above observed normal stop times while bounding worst-case shutdown stalls.

## Helium tarballs need manual Qt wrapper handling
**Symptom:** The Helium package fails during the Qt pre-hook with "depends on qtbase, but no wrapping behavior was specified", or `autoPatchelfHook` complains about missing Qt5 SONAMEs from the bundled compatibility shim.
**Cause:** Upstream `helium-linux` releases currently ship both a Qt6 integration shim that the browser still uses and a dormant `libqt5_shim.so` that is no longer backed by runtime Qt5 libraries. The package also launches through the upstream `helium-wrapper` shell script, so it is not a normal `wrapQtAppsHook` target.
**Status:** Workaround in place
**Resolution:** `pkgs/helium/default.nix` uses `makeWrapper` for the launcher, sets `dontWrapQtApps = true`, and ignores the unused `libQt5Core.so.5`, `libQt5Gui.so.5`, and `libQt5Widgets.so.5` dependencies in `autoPatchelfIgnoreMissingDeps`.

## Current LM Studio release moved its icon out of `usr/share/icons`
**Symptom:** `nixos-rebuild` fails while building `lmstudio` with `gm convert: Unable to open file .../usr/share/icons/hicolor/0x0/apps/lm-studio.png`.
**Cause:** On the currently pinned nixpkgs revision, the `lmstudio` derivation still expects the AppImage-extracted icon under `usr/share/icons/hicolor/0x0/apps/`, but the current `0.4.10-1` release no longer ships a real file there. The top-level `lm-studio.png` is only a broken symlink; the actual icon now lives at `resources/app/.webpack/Icon-512x512.png`.
**Status:** Workaround in place
**Resolution:** `overlays/local-packages.nix` overrides nixpkgs `lmstudio` and rewrites the stale icon source path in its `buildCommand` to use the extracted `resources/app/.webpack/Icon-512x512.png` asset instead.

## Current LM Studio release ships an empty `lms` placeholder
**Symptom:** After fixing the icon path, `nixos-rebuild` still fails while building `lmstudio` with `patchelf: missing ELF header`.
**Cause:** The nixpkgs recipe always installs and patches `${appimageContents}/resources/app/.webpack/lms`, but the current `0.4.10-1` AppImage ships that path as a zero-byte placeholder instead of a real ELF CLI binary.
**Status:** Workaround in place
**Resolution:** `overlays/local-packages.nix` makes the `lms` install/patchelf step conditional on the bundled file being non-empty, so the desktop app still builds while the broken placeholder is ignored.
