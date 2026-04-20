# Nix Quirks

## `texlive.combined.scheme-medium` recurses on this nixpkgs revision
**Symptom:** Evaluation blows up if the TeX Live package set pulls in `scheme-medium`.
**Cause:** On this pinned nixpkgs revision, `scheme-medium` pulls `asymptote` through `collection-binextra` and the evaluation recurses.
**Status:** Workaround in place
**Resolution:** `home/default.nix` builds the shared TeX Live environment with `scheme-small` plus explicit extras like `latexmk` and `tikz-cd`.

## The shared `kevin` account keeps a checked-in bootstrap password on purpose
**Symptom:** Audits keep flagging `users.users.kevin.initialPassword` in `system/configuration.nix` as if it were an accidental secret leak.
**Cause:** The shared baseline intentionally keeps a reproducible local bootstrap login path for fresh installs, while SSH password auth remains disabled separately in the same shared system module.
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
**Symptom:** Desktop and laptop can otherwise build different native outputs at the same store path even when the literal optimization flags match.
**Cause:** `-march=native` and `target-cpu=native` depend on the builder CPU, so the literal flag strings are not enough to distinguish safe cache/scheduler boundaries across hosts.
**Status:** Workaround in place
**Resolution:** `system/native-optimizations.nix`, `overlays/native-optimized.nix`, and `system/native-kernel-packages.nix` tag native derivations with `requiredSystemFeatures = [ "native-optimized-<host>" ]`, and `system/configuration.nix` advertises only the current host's native feature through `nix.settings.system-features` while `enableNativeOptimizations` is enabled.

## Host `system-features` must not advertise `native-optimized-*` unconditionally
**Symptom:** Stock `x86_64-linux` builds stop behaving like generic cacheable builds when a host always claims a native-only feature.
**Cause:** Builder capability leakage changes scheduling and cacheability even when the optimization overlay is off.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` appends `native-optimized-${host.name}` only while `enableNativeOptimizations` is enabled.

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
**Resolution:** Keep the parameter on the shared physical-host baseline only if the performance tradeoff is intentional. Remove that physical-host kernel param in `system/configuration.nix` to restore the kernel's default mitigation policy.

## Physical-host local builds are serialized on purpose
**Symptom:** Local Nix builds on desktop and laptop run one derivation at a time even though the machines have many CPU threads.
**Cause:** `system/configuration.nix` now sets `nix.settings.max-jobs = 1` on the shared physical-host gate. The repo leaves `cores = 0`, so a single heavy derivation can still use the full machine; this avoids stacking multiple already-parallel builds on top of each other.
**Status:** Intentional exception
**Resolution:** Keep the physical hosts on `max-jobs = 1` unless measurement shows a real win from concurrent derivations. If you want more concurrency later, change that shared physical-host setting in `system/configuration.nix` directly.

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
**Resolution:** `home/default.nix` now swaps the upstream `packages.<system>.node_modules_updater` fake-hash output back to the discovered real hash (`sha256-DOGOZdPdkcuyDhVAyWHGsL4rrV28S+YFZj/VORuoQ8Q=` on `x86_64-linux`) and injects that derivation into `packages.<system>.default`, so the repo can stay pinned to OpenCode commit `ae7a3518f789caf9d1f39dfb7848fa44005e36a0` even though that commit's `nix/hashes.json` still advertises a stale fixed-output hash. Do not wire `packages.<system>.node_modules_updater` into the build without overriding the hash: that output intentionally uses `lib.fakeHash` so it fails and reveals the current value. The remaining local workaround still runs during `postConfigure`: it rewrites `packages/shared/tsconfig.json` so its `extends` points at `packages/app/node_modules/@tsconfig/bun/tsconfig.json`, symlinks `node_modules/prettier` to the Bun-managed `node_modules/.bun/prettier@*/node_modules/prettier` package, and symlinks `node_modules/glob` to the already-installed `packages/opencode/node_modules/glob` before the OpenCode build runs.

## OpenChamber source builds need a repo-pinned root manifest for npm
**Symptom:** A straight npm-based build of upstream `openchamber/openchamber` fails before dependency resolution finishes, typically with npm rejecting the root `overrides` versus direct dependency ranges or choking on the VS Code package's `workspace:*` dependency.
**Cause:** Upstream develops against Bun, and the full monorepo metadata currently assumes Bun's workspace/override behavior. The web workspace itself builds fine under npm once the root manifest is trimmed to the `packages/ui` and `packages/web` workspaces and the overridden CodeMirror versions are pinned exactly.
**Status:** Workaround in place
**Resolution:** `pkgs/openchamber/cli.nix` now source-builds OpenChamber from the upstream Git tag, but it replaces the root manifest with `pkgs/openchamber/package.json` and uses the generated `pkgs/openchamber/package-lock.json` so npm only sees the web-facing workspaces and their exact override pins.

## The Claude bridge only implements the OpenCode API subset OpenChamber currently needs
**Symptom:** Claude-backed chats work in both `claude-code` and `mixed` runtime modes for health checks, provider/model selection, session creation, session history, and basic streamed chat, but deeper OpenCode-only features such as true snapshot reverts, project sync history replay, or richer permission/question flows are still conservative stubs.
**Cause:** `pkgs/openchamber-claude-bridge/index.mjs` is intentionally a compatibility layer around the `claude` CLI, not a full OpenCode reimplementation. `pkgs/openchamber-backend-mux/index.mjs` only multiplexes between real OpenCode and that bridge; it does not add missing OpenCode semantics to Claude-backed sessions.
**Status:** Intentional limitation
**Resolution:** Keep the bridge focused on the endpoint surface OpenChamber actively consumes. The local OpenChamber patches now add a `mixed` backend mode in addition to the single-backend OpenCode and Claude-only modes, and `pkgs/openchamber-backend-mux/index.mjs` binds each new chat to the backend implied by the selected model/provider at session creation time. Existing chats stay pinned to the backend they were created on.

## Mixed backend mode binds sessions at creation time
**Symptom:** In `mixed` mode, changing the selected model after a chat already exists does not migrate that chat from OpenCode to Claude Code, or vice versa.
**Cause:** `patches/openchamber/mixed-backend-mux.patch` changes OpenChamber so session creation carries the selected provider/model, and `pkgs/openchamber-backend-mux/index.mjs` records the resulting session ID to backend mapping. After that point, all session-specific routes are sent back to the original backend for that chat.
**Status:** Intentional design
**Resolution:** Treat backend choice as part of chat creation rather than a live per-message toggle. To move a conversation to the other backend, start a new chat while the desired provider/model is selected, then continue there or fork/copy the prompt into the new session.

## OpenChamber desktop launch state lives in `settings.json`
**Symptom:** `~/.config/openchamber/settings.json` now grows a `desktopLocalPort` key, the desktop launcher prefers reusing that port on the next launch, and repeated Vicinae launches refocus the existing app instead of spawning more local OpenChamber servers.
**Cause:** `pkgs/openchamber-desktop/src/main.rs` is a thin Tauri shell around the packaged `openchamber` CLI. It persists the last known desktop port in the shared OpenChamber settings file, falls back to port `57123` before picking a new ephemeral port, and rejects ports already claimed by the CLI runtime by probing `/api/system/info`. The Tauri app itself uses `tauri-plugin-single-instance`, so the duplicate-launch guard now lives at the desktop-process level instead of the old browser-launch wrapper, and the wrapper now fires `openchamber stop` asynchronously on exit so the window can close without waiting for the CLI's full shutdown path.
**Status:** Intentional design
**Resolution:** Treat `desktopLocalPort` as desktop runtime state owned by the Tauri wrapper. If the window closes and the background shutdown is still draining, a quick relaunch can temporarily reconnect to the still-running desktop runtime on that same port. If launches later get wedged on a stale port, stop the app and remove or edit that key; the next launch will retry the stored/default port sequence and can fall back to a fresh port when needed.

## OpenChamber desktop needs WebKit dmabuf disabled on current Wayland stacks
**Symptom:** Launching `openchamber-desktop` on the Hyprland/NVIDIA desktop can exit immediately with `Gdk-Message: Error 71 (Protocol error) dispatching to Wayland display`, often paired with `wp_linux_drm_syncobj_surface_v1 ... Missing acquire timeline`.
**Cause:** The current `webkitgtk_4_1` Wayland renderer path can negotiate the dmabuf/syncobj protocol combination incorrectly on this stack, which crashes the Tauri shell before the OpenChamber UI becomes usable.
**Status:** Workaround in place
**Resolution:** `pkgs/openchamber-desktop/default.nix` now wraps `openchamber-desktop` with `WEBKIT_DISABLE_DMABUF_RENDERER=1`, which keeps the app on a stable WebKit rendering path under Wayland without forcing the whole launcher onto X11.

## OpenChamber desktop popup interactions are sluggish on WebKitGTK without a lighter UI path
**Symptom:** In the local Tauri desktop shell, opening OpenChamber selects, dropdowns, and similar popup UI can feel delayed enough to make the whole app seem unresponsive, even when the backend endpoints themselves respond quickly.
**Cause:** The packaged desktop runtime is WebKitGTK rather than Chromium. The shared popup scroll chrome was doing more work than necessary at menu-open time by installing eager per-child resize observation in `packages/ui/src/components/ui/OverlayScrollbar.tsx` and by leaving mutation tracking enabled for the static option lists rendered by `packages/ui/src/components/ui/select.tsx`.
**Status:** Workaround in place
**Resolution:** `patches/openchamber/desktop-popup-performance.patch` now keeps the same UI behavior but reduces popup overhead by shrinking `OverlayScrollbar` observation to the scroll container itself and by disabling mutation observation for the static `Select` viewport content. Keep the patch local until upstream ships an equivalent WebKitGTK-oriented optimization.

## Declarative Windows VM media and guest state stay partly manual
**Symptom:** The shared physical-host Windows VM module evaluates and seeds `/var/lib/windows-vm/windows11`, but first boot can still land in UEFI or an existing guest keeps its old size, boot state, or TPM state after a Nix change.
**Cause:** `system/windows-vm.nix` makes the host-side QEMU wrapper declarative, but the installer ISO plus the mutable guest-owned qcow2, NVRAM, and TPM directories intentionally live outside the Nix store.
**Status:** Expected manual state
**Resolution:** Copy a Windows ISO to `/var/lib/windows-vm/windows11/isos/windows11.iso` before the first launch. If you want a clean reinstall or to reset secure-boot/TPM state, delete `/var/lib/windows-vm/windows11/system.qcow2`, `/var/lib/windows-vm/windows11/OVMF_VARS.ms.fd`, and `/var/lib/windows-vm/windows11/tpm/`, then rebuild so activation recreates fresh state. If you later increase `virtualisation.windowsVm.diskSizeGiB`, resize the existing qcow2 manually because activation only creates the disk when it does not already exist.

## `tailscaled` can stall shutdown on physical hosts
**Symptom:** Reboot or poweroff can occasionally sit on "A stop job is running for Tailscale node agent" long enough to hit most of systemd's default 90 second stop timeout.
**Cause:** Upstream `tailscaled` shutdown is normally fast, but Linux `wgengine` teardown has had intermittent close/deadlock races. The current hosts use NetworkManager plus `resolvconf`/`openresolv`, so this repo does not rely on `systemd-resolved` staying up for Tailscale cleanup.
**Status:** Workaround in place
**Resolution:** `hosts/laptop/system.nix` and `hosts/desktop/system.nix` set `systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";`, which stays above observed normal stop times while bounding worst-case shutdown stalls.

## The laptop's `e-core-only` profile still keeps `cpu0` online
**Symptom:** Selecting the laptop's `e-core-only` power profile from Quickshell does not fully remove every P-core thread; one P-core thread remains online.
**Cause:** On this XPS 15 9520 kernel/runtime combination, `cpu0` has no `/sys/devices/system/cpu/cpu0/online` control, so Linux does not expose hot-unplug for the boot CPU even though the other P-core sibling threads are hotpluggable.
**Status:** Intentional limitation
**Resolution:** `hosts/laptop/system.nix` installs `laptop-power-profile`, which detects P-cores from `topology/thread_siblings_list`, re-enables all hotpluggable CPUs for the normal `performance` / `balanced` / `power-saver` modes, and offlines only the hotpluggable P-core threads for `e-core-only`. Treat that mode as an E-core-biased profile, not a literal "all P-cores gone" state.

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
