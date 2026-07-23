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

## Home Manager's release must track the evaluated Nixpkgs release
**Symptom:** `nixos-rebuild switch` warns that the `kevin` profile is using mismatched Home Manager and Nixpkgs versions.
**Cause:** Home Manager compares its own release value with the evaluated Nixpkgs release. When `nixos-unstable` advances to a new cycle before Home Manager publishes a matching release branch, the previous `release-*` input starts warning even though its `nixpkgs` input follows this flake.
**Status:** Tracking Home Manager `master` for the 26.11 cycle
**Resolution:** `flake.nix` currently tracks `github:nix-community/home-manager/master` and keeps `home-manager.inputs.nixpkgs.follows = "nixpkgs"`, because Home Manager `master` reports release `26.11` while no `release-26.11` branch exists yet. Once the matching release branch exists, move the input to that branch and update only the Home Manager lockfile node instead of disabling `home.enableNixpkgsReleaseCheck`.

## Stock `services.fstrim` can touch the Windows NVMe through a shared EFI mount
**Symptom:** A weekly `fstrim` run trims `/boot/efi` even though the goal is only to discard unused blocks on the Linux filesystem.
**Cause:** The stock NixOS `services.fstrim.enable = true` unit trims every mounted filesystem it sees in `/etc/fstab` and `/proc/self/mountinfo`. On dual-boot hosts that mount a shared EFI system partition from the Windows drive at `/boot/efi`, that includes the Windows NVMe.
**Status:** Workaround in place
**Resolution:** `system/services.nix` now defines a custom `fstrim-root.service` plus `fstrim-root.timer` instead of enabling `services.fstrim`. Keep the trim target pinned to `/` unless you explicitly want discard to reach additional mounted filesystems too.

## Optimizing low-level libraries explodes the rebuild graph
**Symptom:** A small `-march` overlay on `zstd` or `lz4` turns into huge rebuild cascades.
**Cause:** Those libraries sit low in shared dependency chains, pulling rebuilds through `libarchive`/`cmake`/`llvm` or `systemd`/`nix`.
**Status:** Workaround in place
**Resolution:** `overlays/native-optimized.nix` deliberately leaves `zstd` and `lz4` unoptimized unless a separate opt-in path is added later.

## Native-optimized derivations must carry host-specific `requiredSystemFeatures`
**Symptom:** Desktop and laptop can otherwise build different native outputs at the same store path even when the literal optimization flags match.
**Cause:** `-march=native` and `target-cpu=native` depend on the builder CPU, so the literal flag strings are not enough to distinguish safe cache/scheduler boundaries across hosts.
**Status:** Workaround in place
**Resolution:** `system/native-optimizations.nix` and `overlays/native-optimized.nix` tag native derivations with `requiredSystemFeatures = [ "native-optimized-<host>" ]`, and `system/configuration.nix` advertises only the current host's native feature through `nix.settings.system-features` while `enableNativeOptimizations` is enabled.

## Host `system-features` must not advertise `native-optimized-*` unconditionally
**Symptom:** Stock `x86_64-linux` builds stop behaving like generic cacheable builds when a host always claims a native-only feature.
**Cause:** Builder capability leakage changes scheduling and cacheability even when the optimization overlay is off.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` appends `native-optimized-${host.name}` only while `enableNativeOptimizations` is enabled.

## Flake-input package overrides share the native helper path
**Symptom:** Hyprland, Hyprland plugins, and `hyprqt6engine` would otherwise diverge from the native optimization policy used for the selected nixpkgs packages.
**Cause:** Those derivations come from flake inputs or local overrides rather than the nixpkgs package set targeted by `overlays/native-optimized.nix`. `hyprexpo` is now a repo-local package under `pkgs/hyprland-plugins/hyprexpo/default.nix`, but it follows the same helper path as the flake-input Hyprland packages.
**Status:** Intentional design
**Resolution:** `system/configuration.nix` and `home/default.nix` both import `system/native-optimizations.nix` directly, so the remaining flake-input packages carry the same `-O3 -march=native` / `target-cpu=native` flags and per-host `requiredSystemFeatures` tag as the overlay-managed nixpkgs packages.

## Hyprland Cachix is not useful for the patched local plugin stack
**Symptom:** `nixos-rebuild switch` warns that a `.nar.zst` file does not exist in binary cache `https://hyprland.cachix.org` while building the Hyprland plugin closure.
**Cause:** This repo rebuilds the active Hyprland and plugin stack with local patches and host-native flags, so the resulting store paths are not expected to exist in Hyprland's public Cachix cache. Leaving that substituter enabled only adds noisy negative cache lookups for those local derivations.
**Status:** Removed from shared Nix settings
**Resolution:** `system/configuration.nix` keeps `cache.nixos.org` plus the Vicinae cache but no longer lists `https://hyprland.cachix.org` or its public key. Re-add the Hyprland cache only if the Hyprland-family package policy changes back to mostly unpatched upstream outputs.

## Vicinae server autostart uses Hyprland only
**Symptom:** Running Vicinae through both the Home Manager service and Hyprland `exec-once = vicinae server` starts redundant background paths for the same launcher. After a rebuild, launcher-spawned apps can also keep stale desktop-entry behavior until the existing Vicinae server is replaced.
**Cause:** nixpkgs already packages `vicinae`, so the launcher can be installed directly without also enabling the upstream Home Manager service module. This repo still needs the Vicinae server to be present during the session, but it should have a single owner. The server is long-lived and can cache app metadata across profile switches; `nixos-rebuild switch` does not rerun Hyprland `exec-once` lines.
**Status:** Hyprland-owned server startup
**Resolution:** `home/default.nix` still imports `vicinae.homeManagerModules.default` so the option remains available if needed later, but `home/packages.nix` installs `pkgs.vicinae` through `vicinaePkg` and does not enable `services.vicinae`. `config/hypr/autostart.conf` starts `vicinae server` directly, while `SUPER+R` / `vicinae open` only opens the already-running launcher. The `nrs` alias in `home/shell.nix` now asks Hyprland to run `vicinae server --replace` after a successful switch, refreshing the launcher without introducing a second systemd-owned service. This restart matters after desktop-entry ID changes in particular: the next rebuild renames OpenChamber's entry from `openchamber.desktop` to `openchamber-desktop.desktop`, which the long-lived Vicinae server only sees after a replace.

## Snappy Switcher is simpler as a local package than as a flake input
**Symptom:** The previous setup routed Snappy Switcher through a dedicated upstream flake input even though the package recipe was tiny.
**Cause:** Upstream ships a simple `mkDerivation` in its flake rather than a package already available in nixpkgs. Keeping it as a flake input added another lockfile node and another special-case package path without buying much.
**Status:** Simplified to a local package
**Resolution:** `overlays/local-packages.nix` exposes `pkgs.snappy-switcher` from `pkgs/snappy-switcher/default.nix`, which fetches upstream 4.0 directly. Upstream now provides current-workspace filtering, so the old local patch and `scope = workspace` config key are gone; `config/hypr/keybinds.conf` passes `--workspace --mod alt` to select the current workspace and dismiss the switcher when Alt is released.

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

## Physical hosts use the stock nixpkgs kernel package set
**Symptom:** Custom physical-host kernel changes can break boot before persistent journald captures useful logs, as happened with desktop generation 73.
**Cause:** The old shared `system/native-kernel-packages.nix` path rebuilt `linux_6_18` with Clang/ThinLTO/native flags plus CachyOS BORE and BBR3 patches. That boot-critical custom closure was harder to trust than the cached nixpkgs kernel package set.
**Status:** Stock kernel path in place
**Resolution:** `system/physical-host.nix` now sets `boot.kernelPackages = pkgs.linuxPackages`, and the repo no longer carries `system/native-kernel-packages.nix`. Keep low-risk runtime policy in `boot.kernelParams`, `boot.kernel.sysctl`, and systemd services instead of reintroducing a shared CachyOS/native kernel rebuild path.

## Laptop Kconfig parent trims need child-symbol unsets
**Symptom:** The laptop rebuild can fail in `linux-config-6.18.*` with `unused option` errors for symbols such as `DRM_HYPERV`, `FB_HYPERV`, `DRM_NOUVEAU_SVM`, `KVM_AMD_SEV`, or `SEV_GUEST`.
**Cause:** `hosts/laptop/system.nix` intentionally forces some parent subsystems off for the Intel/NVIDIA laptop, but nixpkgs' stock `common-config.nix` still contributes mandatory child settings for those subsystems. Once the parent is disabled, those child symbols are unreachable in Kconfig and the kernel config builder treats mandatory unused settings as errors.
**Status:** Workaround in place
**Resolution:** Keep the parent subsystem trims in `hosts/laptop/system.nix`, but pair them with `lib.kernel.unset` for inherited child settings that become unreachable. Do not replace this with broad `ignoreConfigErrors`; that would hide real kernel config drift on future updates.

## Physical-host working-set protection uses MGLRU `min_ttl_ms`
**Symptom:** Desktop and laptop now ask for LE9/LE10-style working-set and file-cache protection, but the active tuning path is not an obvious `vm.*_kbytes` sysctl block in the host modules.
**Cause:** The shared kernel config keeps `LRU_GEN=y` and `LRU_GEN_ENABLED=y`, and `system/physical-host.nix` now applies the runtime policy through `systemd.services.mglru-tuning`, which writes `y` to `/sys/kernel/mm/lru_gen/enabled` and `1000` to `/sys/kernel/mm/lru_gen/min_ttl_ms`. The repo intentionally uses MGLRU's own thrash-prevention knob as the active protection path.
**Status:** Intentional design
**Resolution:** Tune `systemd.services.mglru-tuning.script` in `system/physical-host.nix` if you want a different pressure-relief threshold, or remove that service if you want stock MGLRU behavior. Do not assume the older LE9 `vm.anon_min_kbytes` / `vm.clean_low_kbytes` / `vm.clean_min_kbytes` knobs are the active control surface in this repo.

## Desktop swap sysctls stay on kernel defaults for zram
**Symptom:** The desktop's sysctl block looks thinner than typical "responsiveness tuning" guides — no `vm.swappiness`, no `vm.vfs_cache_pressure`.
**Cause:** The old `vm.swappiness=10` and `vm.vfs_cache_pressure=50` values in `hosts/desktop/system.nix` were leftovers from a rolled-back responsiveness-tuning commit and were tuned for disk-backed swap. With the zram-only swap configured in `system/physical-host.nix`, the kernel default swappiness of 60 is the friendlier policy.
**Status:** Removed on purpose
**Resolution:** `hosts/desktop/system.nix` keeps only the writeback tuning (`vm.dirty_ratio = 10`, `vm.dirty_background_ratio = 5`), which was deliberately retained. Do not reintroduce low-swappiness values while swap is zram-only.

## Desktop kernel trim is disabled until it is boot-validated
**Symptom:** Generation 73 on the desktop failed to boot far enough to leave a persistent journal entry, while generation 72 booted normally.
**Cause:** The failed generation differed from the working generation in the kernel/initrd/NVIDIA-open closure. The desktop-specific PREEMPT_FULL and dead-subsystem Kconfig trim plus forced initrd module list made that closure harder to trust because an early kernel or stage-1 failure would not be debuggable from the normal journal.
**Status:** Avoided for boot stability
**Resolution:** `hosts/desktop/system.nix` no longer adds desktop-only `boot.kernelPatches` or forces `boot.initrd.availableKernelModules`; it stays on the shared physical-host kernel config and a normal merged initrd module list. Reintroduce desktop Kconfig trimming only as a separately tested change, and verify a real desktop boot before keeping it.

## Physical hosts disable CPU vulnerability mitigations on purpose
**Symptom:** `lscpu`, `/sys/devices/system/cpu/vulnerabilities/*`, or boot logs report that Spectre, Meltdown, and related CPU side-channel mitigations are disabled on the laptop and desktop.
**Cause:** `system/physical-host.nix` now sets `boot.kernelParams = [ "mitigations=off" "transparent_hugepage=madvise" ]` on the shared physical-host gate.
**Status:** Intentional exception
**Resolution:** Keep the parameter on the shared physical-host baseline only if the performance tradeoff is intentional. Remove that physical-host kernel param in `system/physical-host.nix` to restore the kernel's default mitigation policy.

## Physical-host local builds allow limited derivation concurrency on purpose
**Symptom:** Local Nix builds on desktop and laptop can build up to two derivations at once instead of fully serializing the local queue.
**Cause:** `system/physical-host.nix` now sets `nix.settings.max-jobs = 2` on the shared physical-host gate. The repo does not set `cores`, so each build can still use its package-specific default parallelism while Nix limits the number of concurrent derivations.
**Status:** Intentional exception
**Resolution:** Keep the physical hosts on `max-jobs = 2` if the machine benefits from some overlap between smaller builds. If heavy builds still create too much memory pressure, either lower `max-jobs` again or add package-specific parallelism caps instead of globally pinning all local builds.

## Narrow unfree predicates must cover transitive module closures, not just package lists
**Symptom:** Replacing `allowUnfree = true` with a small name allowlist still fails evaluation on packages that are not listed directly in `home.packages` or `environment.systemPackages`.
**Cause:** NixOS and Home Manager evaluate the full module graph. Unfree packages can enter indirectly through options such as `fonts.packages`, `programs.steam.*`, or CUDA-enabled dependency closures.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now uses `allowUnfreePredicate`, but its allowlist must include both the directly selected apps and the extra unfree package names already required by the current system closure, such as `bambu-studio`, `sf-pro`, `symbola`, `steam-unwrapped`, and the CUDA userspace packages pulled in by existing desktop packages.

## Bitwarden currently permits nixpkgs' Electron 39 package
**Symptom:** After updating the flake's `nixpkgs` input, `nixos-rebuild` can fail during evaluation with `Refusing to evaluate package 'electron-39.8.10' ... Electron version 39.8.10 is EOL`.
**Cause:** `system/services.nix` installs `pkgs.bitwarden-desktop` system-wide so its desktop integration is present outside Home Manager. On the current nixpkgs input, `pkgs/by-name/bi/bitwarden-desktop/package.nix` pins that package to `electron_39`.
**Status:** Temporary insecure exception in place
**Resolution:** `system/configuration.nix` permits only the exact `electron-39.8.10` package needed by the current `bitwarden-desktop` expression. Remove that exception when nixpkgs moves Bitwarden to a supported Electron release or when Bitwarden is replaced by a package that does not depend on Electron 39.

## WinBoat currently permits nixpkgs' Electron 40 package
**Symptom:** After updating the flake's `nixpkgs` input, `nixos-rebuild` can fail during evaluation with `Refusing to evaluate package 'electron-40.10.5' ... Electron version 40.10.5 is EOL`.
**Cause:** `home/packages.nix` installs `pkgs.winboat`. On the current nixpkgs input, WinBoat 0.9.0 depends on `electron_40`.
**Status:** Temporary insecure exception in place
**Resolution:** `system/configuration.nix` permits only the exact `electron-40.10.5` package needed by the current WinBoat expression. Remove that exception when nixpkgs moves WinBoat to a supported Electron release or when WinBoat is replaced by a package that does not depend on Electron 40.

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

## `cantarell-fonts` variable OTF autohinting fails on this nixpkgs revision
**Symptom:** `nixos-rebuild switch` fails while building `cantarell-fonts-0.311`; `scripts/make-variable-font.py` aborts when `otfautohint --exclude-glyphs uni0424 ... Cantarell-VF.otf` exits non-zero.
**Cause:** The current nixpkgs `pkgs/by-name/ca/cantarell-fonts/package.nix` recipe builds Cantarell's variable OTF target by default, and that upstream autohint step is broken with the current font build toolchain on the pinned input.
**Status:** Workaround in place
**Resolution:** `overlays/local-packages.nix` overrides `pkgs.cantarell-fonts` with Meson flags `-Dbuildvf=false` and `-Dbuildstatics=true`. This keeps `system/configuration.nix` `fonts.packages` installing Cantarell, but as static OTF files. Remove the override after a nixpkgs update proves the default variable-font build succeeds again.

## Generic `SF Pro` can look soft on Linux without extra fontconfig tuning
**Symptom:** UI text that explicitly requests `SF Pro`, especially bold labels at normal desktop sizes, can look fuzzier than expected even though the correct font package is installed.
**Cause:** The shared NixOS fontconfig defaults use grayscale antialiasing (`10-sub-pixel-none.conf`), and Apple's font package also exposes a catch-all `SF Pro` variable face that fontconfig can choose before the `SF Pro Text` optical cut that is better suited to small UI sizes.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now sets `fonts.fontconfig.subpixel.rgba = "rgb"` and adds a local fontconfig rule that prepends `SF Pro Text` whenever apps request the generic `SF Pro` family. If a monitor shows color fringes after rebuild, switch that `rgba` value to the panel's real order (`bgr`, `vrgb`, or `vbgr`).

## Automatic timezone still depends on GeoClue resolving a location
**Symptom:** `timedatectl` keeps the previous timezone after travel even though `services.automatic-timezoned` is enabled.
**Cause:** `system/services.nix` lets GeoClue own locality and `automatic-timezoned` only applies a timezone after GeoClue returns coordinates. If GeoClue cannot see Wi-Fi networks, the BeaconDB lookup times out, or the agent/app authorization path is broken, the timezone service has no new location to apply.
**Status:** Expected limitation
**Resolution:** Check `where-am-i` under the user session and `journalctl -u geoclue.service` before debugging `automatic-timezoned` itself. Locale and keyboard layout remain static through `i18n.defaultLocale = "en_US.UTF-8"` and `console.keyMap = "us"`; only timezone is dynamic.

## Home Manager packages do not register system-scoped helpers
**Symptom:** A GUI app installed only through `home.packages` starts, but its root helper never appears on the system bus and no polkit prompt is triggered.
**Cause:** Home Manager installs packages into the user profile, outside the NixOS system path and `services.dbus.packages` set that expose `share/dbus-1/system-services` files and link `share/polkit-1/actions` for system-wide activation.
**Status:** Workaround in place
**Resolution:** Install those apps through NixOS modules or `environment.systemPackages`. `system/configuration.nix` now enables `programs.partition-manager` so `kpmcore` is registered for both D-Bus activation and polkit, and `bitwarden-desktop` stays in `environment.systemPackages` for the same reason.

## Bambu Studio stays on the stable AppImage release
**Symptom:** The locked nixpkgs package is newer than the latest stable Bambu Studio release, but selects a public beta and requires a large local C++ build; its desktop metadata also does not match the `BambuStudio` class observed by Hyprland.
**Cause:** NixOS/nixpkgs#522161 has fixed cloud authentication in the source package, but adopting that package would also change the release channel, build cost, launcher shape, and NVIDIA/runtime behavior at once.
**Status:** Stable AppImage overlay in place
**Resolution:** `overlays/local-packages.nix` replaces `pkgs.bambu-studio` with the official stable Ubuntu 24.04 `BambuStudio_ubuntu24.04-v02.07.01.62-20260616195227.AppImage`, wrapped through `appimageTools.wrapType2`. The wrapper installs the upstream desktop file/icon, adds `$out/bin/bambu-studio-desktop` as a shell-parent launcher, rewrites the desktop file to that absolute path, normalizes `StartupWMClass=BambuStudio`, and supplies the CA, GIO, WebKitGTK, GStreamer, libsecret, and font runtime needed by cloud login. The overlay inherits nixpkgs' metadata, so `system/configuration.nix` must keep `bambu-studio` in the shared unfree predicate. `home/xdg.nix` force-deploys the packaged desktop file because stale AppImage-generated user entries otherwise outrank the profile entry. Do not use the Fedora AppImage on this nixpkgs pin: it links removed WebKitGTK 4.0 and `libsoup-2.4.so.1`. Reconsider the overlay only after the nixpkgs source package is tested for cloud login, Vicinae launch/refocus, window class, and NVIDIA rendering on both hosts; the unfree allowlist remains required even if the overlay is removed. If the AppImage opens with language/locale errors after an older package, delete the stale `language` key from `~/.config/BambuStudio/BambuStudio.conf` or remove that config directory after backing up needed printer/profile state.

## LM Studio uses a Vicinae-safe AppImage launcher
**Symptom:** LM Studio can launch from a shell with `lm-studio`, but selecting it from Vicinae appears to do nothing.
**Cause:** The locked nixpkgs `lmstudio` package still points `lm-studio.desktop` at the AppImage/FHS wrapper through `Exec=lm-studio`. Vicinae's detached Qt launcher can treat that wrapper launch as successful and then lose the actual Electron app path when the wrapper handoff exits.
**Status:** Local AppImage overlay in place
**Resolution:** `overlays/local-packages.nix` replaces `pkgs.lmstudio` with the upstream x64 `LM-Studio-0.4.20-1-x64.AppImage`, keeps `$out/bin/lm-studio` as the main executable, installs the bundled `lms` CLI, regenerates the packaged icons, adds a small `$out/bin/lm-studio-desktop` shell-parent launcher, and rewrites `lm-studio.desktop` to that absolute launcher path while keeping `StartupWMClass=LM-Studio`, which matches the actual Hyprland window class. The shell parent invokes `$out/bin/lm-studio` without `exec`, matching the Bambu Studio launcher shape that keeps Vicinae away from the raw AppImage/FHS wrapper. After switching to a generation with this overlay, refresh the long-lived Vicinae server with the `nrs` wrapper or `hyprctl dispatch exec 'vicinae server --replace'` so it drops any cached old desktop entry.

## SDDM cannot read wallpapers from the locked-down home directory directly
**Symptom:** Pointing `where_is_my_sddm_theme` straight at a wallpaper under `/home/kevin/...` leaves the greeter background blank even though the same path works inside the user session.
**Cause:** The shared `kevin` home directory is mode `0700`, so the pre-login SDDM user cannot traverse into the repo checkout or other home-owned wallpaper paths.
**Status:** Workaround in place
**Resolution:** `desktopctl/src/theme/targets/where_is_my_sddm_theme.rs` stages the selected wallpaper into `/tmp/desktopctl-where-is-my-sddm-theme/background`, and `system/services.nix` copies that staged file into the root-owned `/var/lib/desktopctl/where-is-my-sddm-theme/background` path that SDDM reads. Keep the SDDM theme pointed at the `/var/lib` copy rather than a home-directory source path.

## Qt plugin paths break if you only point `QT_PLUGIN_PATH` at hyprqt6engine
**Symptom:** Qt and KDE apps can pick up the generated palette but still fall back to partially unstyled widgets or miss Kvantum styling, especially in D-Bus/systemd-activated helpers such as `xdg-desktop-portal-kde`.
**Cause:** `hyprqt6engine` installs under `lib/qt-6/`, outside the standard `/lib/qt-*/plugins` roots. A hand-written `QT_PLUGIN_PATH=${hyprqt6engine}/lib/qt-6` exposes the Hyprland platform theme itself but hides profile-installed plugins like `qt5ct`, `qt6ct`, and `libkvantum.so` unless NixOS also wires the normal profile-relative plugin directories.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now enables NixOS `qt.enable`, exports `QT_QPA_PLATFORMTHEME=hyprqt6engine`, keeps the hyprqt6engine root on `QT_PLUGIN_PATH`, and installs `qt5ct`, `qt6ct`, and Kvantum system-wide so both regular apps and user services resolve the same plugin set.

## Neuwaita needs KDE color-scheme metadata for symbolic icon recoloring
**Symptom:** KDE apps keep their custom folder/file icons from Neuwaita, but toolbar and sidebar action icons can stay black on dark themes, or Dolphin's default blue folders can look like oversized Breeze fallbacks.
**Cause:** KIconThemes only rewrites Breeze SVG `current-color-scheme` styles when the current icon theme declares `FollowsColorScheme=true`. The upstream Neuwaita index also inherits Adwaita and hicolor before Breeze, so missing KDE action icons can resolve to fixed-color black symbolic assets before KDE reaches recolorable Breeze icons. Reordering the real `Neuwaita` theme would leak Breeze's thinner symbolic icons into GTK apps such as Nautilus. KDE also uses names such as `folder-blue` for the default folder color, while upstream Neuwaita only ships the generic `folder` name. KDE's icon loader also treats spaces after commas in `Inherits=` literally in this setup, producing lookups such as `" hicolor"` and `" breeze"`.
**Status:** Workaround in place
**Resolution:** The `neuwaita` derivation in `home/gtk.nix` installs upstream-shaped `Neuwaita` for GTK after normalizing its inherited-theme list to comma-only separators, and a derived `Neuwaita-KDE` wrapper with `FollowsColorScheme=true` plus `Inherits=Neuwaita,breeze,Adwaita,hicolor`. Both installed themes get aliases for common folder names that upstream Neuwaita lacks, including `folder-blue`. The Qt target maps the shared `Neuwaita` state value to that wrapper for KDE only.

## Nautilus photo thumbnails need explicit user-profile helpers
**Symptom:** Nautilus opens from the Home Manager profile, but image files show generic icons instead of photo previews, and running `gsettings` in the shell fails with `command not found`.
**Cause:** Installing `nautilus` alone exposes the file manager, but not every helper users expect to be on the profile `PATH` or visible as XDG thumbnailer metadata. GLib's `bin` output provides `gsettings`, and `gdk-pixbuf` provides `gdk-pixbuf-thumbnailer` plus its thumbnailer metadata for common image formats.
**Status:** Workaround in place
**Resolution:** `home/packages.nix` installs `pkgs.glib` and `pkgs.gdk-pixbuf` alongside `pkgs.nautilus`, while `home/gtk.nix` declares `org/gnome/nautilus/preferences` dconf values for `show-image-thumbnails = "always"` and a `thumbnail-limit` of 100 MB. After switching, restart Nautilus with `nautilus -q` and clear `~/.cache/thumbnails/fail/` if files were cached as failed thumbnails before the helpers were installed.

## Claude Code is better sourced from nixpkgs than from a repo-local npm pin here
**Symptom:** `nixos-rebuild` failed while building the repo-local `claude-code-2.1.91` overlay with `install: omitting directory ...-source` during `installPhase`.
**Cause:** The repo-local overlay pinned an older npm tarball and lockfile against a newer nixpkgs `claude-code` builder shape. Upstream nixpkgs has since moved on to a newer package revision and its maintained recipe no longer matches the local override's assumptions.
**Status:** Workaround removed in favor of nixpkgs package
**Resolution:** `system/configuration.nix` still consumes `pkgs.claude-code`; the repo no longer carries a package-specific npm override. Because Anthropic model-support releases can land in nixpkgs master before the `nixos-unstable` channel advances, `flake.nix` now adds a narrow `nixpkgs-claude` input, and the Claude overlays in `flake.nix` and `system/configuration.nix` replace only `claude-code` with that nixpkgs package. Keep this as a nixpkgs-sourced package rather than reintroducing a local npm pin.

## Haruna must match the session Qt/KDE stack
**Symptom:** A stable Haruna build can abort at startup, even with no media loaded, while the same file decodes cleanly in `ffplay`.
**Cause:** The Hyprland session exports `QT_QPA_PLATFORMTHEME=hyprqt6engine`, and the active `hyprqt6engine` plugin follows the unstable Qt/KDE stack. Pinning the whole Haruna package to stable makes it load a Qt platform theme plugin built against a different Qt/KDE ABI. Older unstable pins also risked local rebuilds through Haruna's `yt-dlp -> deno -> rusty_v8` dependency chain.
**Status:** Workaround in place
**Resolution:** `home/default.nix` now installs `pkgs.haruna` from the same pinned nixpkgs set as the rest of the Qt/KDE session, so it shares the session ABI with `hyprqt6engine`. Re-check the dry-run closure before reintroducing any stable Haruna pin; avoiding rebuild pressure is not worth mixing Qt/KDE plugin ABIs.

## Chromium-family file pickers use the GTK portal on Hyprland

**Symptom:** On a fresh Hyprland login, Chromium and Helium can open normally but clicking an upload/file input does not produce a file picker.

**Cause:** The old user portal config forced `org.freedesktop.impl.portal.FileChooser = kde`. In this non-Plasma session the KDE portal backend starts through Plasma's `plasma-xdg-desktop-portal-kde.service` path and can log `Failed to register with host portal ... Connection already associated with an application ID` during activation. That made the shared Chromium-family file picker path depend on the most brittle portal backend in the session. The user session also was not explicitly starting `graphical-session.target`, so activation-sensitive user services were relying on D-Bus activation timing instead of an active graphical target.

**Status:** Fixed in shared config.

**Resolution:** `system/services.nix` now exposes only the Hyprland and GTK portal backends and sets `xdg.portal.config.common` so `default = [ "hyprland" "gtk" ]` and `org.freedesktop.impl.portal.FileChooser = [ "gtk" ]`. `home/xdg.nix` writes the same user-level `xdg-desktop-portal/portals.conf` values to prevent an old Home Manager symlink from overriding the system config. `config/hypr/autostart.conf` imports the Hyprland environment into D-Bus/systemd, scrubs one-shot activation tokens, starts `graphical-session.target` plus the portal services, and stops the graphical target on Hyprland shutdown.

## Discord's native Krisp module fails after Nix packaging
**Symptom:** Discord sees the selected microphone, but voice activity can fail or the client logs `NoiseCancellerError.KRISP_INIT_ERROR_UNSIGNED` while `discord_krisp.log` says `Application not signed by Discord, Krisp is not enabled`.
**Cause:** The Nix-packaged Discord binary is patched/wrapped, so Discord's native Krisp module fails its signature check. If Discord stores `vadUseKrisp = true`, voice activity detection can depend on that failing module even when PipeWire and the microphone are healthy.
**Status:** Local patcher in place
**Resolution:** `home/packages.nix` overrides `pkgs.discord` with a local Linux-only backport of the upstream nixpkgs Krisp patcher from NixOS/nixpkgs#506089. `pkgs/discord-krisp/patch-linux.py` patches `discord_krisp.node` so the signature check returns success, guards `index.js` against repeated initialization, and makes `KrispInitializeExternal` return success without running the native initializer again. `pkgs/discord-krisp/patch-voice.py` points `discord_voice` at `~/.config/discord/<version>/modules/discord_krisp`, while `pkgs/discord-krisp/deploy.py` is run by the generated `Discord` launcher to copy the patched module into that writable directory and repair it if Discord's module updater overwrites it during startup. This intentionally bypasses Discord's Krisp signature check; remove the local override once nixpkgs carries an acceptable upstream fix or if that tradeoff is no longer desired. After switching to a generation with this override, restart Discord and re-enable Krisp/noise suppression in Discord settings if the profile was previously forced to `vadUseKrisp = false`.

## OpenChamber source builds need a repo-pinned root manifest for npm
**Symptom:** A straight npm-based build of upstream `openchamber/openchamber` fails before dependency resolution finishes, typically with npm rejecting the root `overrides` versus direct dependency ranges or choking on the VS Code package's `workspace:*` dependency.
**Cause:** Upstream develops against Bun, and the full monorepo metadata currently assumes Bun's workspace/override behavior. The web workspace itself builds fine under npm once the root manifest is trimmed to the `packages/ui` and `packages/web` workspaces and the overridden CodeMirror versions are pinned exactly. Current upstream metadata also includes root-only tooling dependencies such as `sharp` for changelog-card generation that the packaged web runtime does not build.
**Status:** Workaround in place
**Resolution:** `pkgs/openchamber/cli.nix` source-builds OpenChamber 1.16.3 from the upstream Git tag, but replaces the root manifest with `pkgs/openchamber/package.json` and uses `pkgs/openchamber/package-lock.json` so npm sees only the UI/web workspaces and their exact override pins. Keep root-only release tooling out of the trimmed manifest unless the web build starts using it. The recipe supplies `vips` for the transitive `sharp` install and explicitly applies upstream's `@tanstack/virtual-core` Bun patch after npm dependency installation because npm does not interpret Bun's `patchedDependencies` field.

## The Claude bridge only implements the OpenCode API subset OpenChamber currently needs
**Symptom:** Claude-backed chats work in both `claude-code` and `mixed` runtime modes for health checks, provider/model selection, session creation, session history, and basic streamed chat, but deeper OpenCode-only features such as true snapshot reverts, project sync history replay, or richer permission/question flows are still conservative stubs.
**Cause:** `pkgs/openchamber-claude-bridge/index.mjs` is intentionally a compatibility layer around the packaged `claude-code` CLI, not a full OpenCode reimplementation. `pkgs/openchamber-backend-mux/index.mjs` only multiplexes between real OpenCode and that bridge; it does not add missing OpenCode semantics to Claude-backed sessions.
**Status:** Intentional limitation
**Resolution:** Keep the bridge focused on the endpoint surface OpenChamber actively consumes. The local OpenChamber patches now add a `mixed` backend mode in addition to the single-backend OpenCode and Claude-only modes, and `pkgs/openchamber-backend-mux/index.mjs` binds each new chat to the backend implied by the selected model/provider at session creation time, forwards the selected `model` / `variant` / `agent` into that backend's `/session` create call, normalizes OpenCode's plain-string provider catalog entries before merging them with Claude Code, and serves merged `/experimental/session` pages so the provider settings UI and per-project sidebar can see both backends at once. Existing chats stay pinned to the backend they were created on. The wrappers pin both `opencode` and `claude-code`, so this path should not depend on ambient `PATH` for backend binaries. One deliberate capability gap: claude-code models do NOT advertise attachment/image/pdf input capabilities — the bridge reduces file parts to an `[Attached file: <path>]` text label and never passes attachment bytes (`data:` URLs) to the claude CLI, so the flags were set to false for honesty. Real attachment passing (materializing `data:` URLs into files the CLI can read, e.g. under the session directory or via `--add-dir`) is a possible future feature; an owner question on whether to build it is pending.

## Mixed backend mode binds sessions at creation time
**Symptom:** In `mixed` mode, changing the selected model after a chat already exists does not migrate that chat from OpenCode to Claude Code, or vice versa.
**Cause:** `patches/openchamber/backend-integration.patch` changes OpenChamber so session creation carries the selected provider/model while preserving upstream directory and metadata routing, and `pkgs/openchamber-backend-mux/index.mjs` records the resulting session ID to backend mapping. After that point, all session-specific routes are sent back to the original backend for that chat.
**Status:** Intentional design
**Resolution:** Treat backend choice as part of chat creation rather than a live per-message toggle. To move a conversation to the other backend, start a new chat while the desired provider/model is selected, then continue there or fork/copy the prompt into the new session.

## OpenChamber desktop launch state lives in `settings.json`
**Symptom:** `~/.config/openchamber/settings.json` now grows a `desktopLocalPort` key, the desktop launcher prefers reusing that port on the next launch, and repeated Vicinae launches refocus the existing app instead of spawning more local OpenChamber servers.
**Cause:** `pkgs/openchamber-desktop/src/main.rs` is a thin Tauri shell around the packaged `openchamber` CLI. It persists the last known desktop port in the shared OpenChamber settings file, falls back to port `57123` before picking a new ephemeral port, and rejects ports already claimed by the CLI runtime by probing `/api/system/info`. `write_desktop_local_port` writes the key atomically (temp file + rename inside `~/.config/openchamber`), skips the write entirely when the stored port already matches, and never rewrites `settings.json` when the existing file fails to parse as a JSON object, so the wrapper cannot truncate or reset the server-owned settings file. The Tauri app uses `tauri-plugin-single-instance`, and on exit the wrapper verifies the desktop runtime, authenticates through `/auth/session` when required, then posts `/api/system/shutdown` asynchronously so the window does not wait for server teardown.
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

## `tailscaled` can stall shutdown on physical hosts
**Symptom:** Reboot or poweroff can occasionally sit on "A stop job is running for Tailscale node agent" long enough to hit most of systemd's default 90 second stop timeout.
**Cause:** Upstream `tailscaled` shutdown is normally fast, but Linux `wgengine` teardown has had intermittent close/deadlock races. The current hosts use NetworkManager plus `resolvconf`/`openresolv`, so this repo does not rely on `systemd-resolved` staying up for Tailscale cleanup.
**Status:** Workaround in place
**Resolution:** `system/physical-host.nix` (the shared `lib.mkIf host.isPhysical` module) sets `systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";`, which stays above observed normal stop times while bounding worst-case shutdown stalls.

## The laptop's `e-core-only` profile still keeps `cpu0` online
**Symptom:** Selecting the laptop's `e-core-only` power profile from Quickshell does not fully remove every P-core thread; one P-core thread remains online.
**Cause:** On this XPS 15 9520 kernel/runtime combination, `cpu0` has no `/sys/devices/system/cpu/cpu0/online` control, so Linux does not expose hot-unplug for the boot CPU even though the other P-core sibling threads are hotpluggable.
**Status:** Intentional limitation
**Resolution:** `hosts/laptop/system.nix` installs `laptop-power-profile`, which re-enables all hotpluggable CPUs for the normal `performance` / `balanced` / `power-saver` modes and offlines only the hotpluggable P-core threads for `e-core-only`. Treat that mode as an E-core-biased profile, not a literal "all P-cores gone" state. Two detection details matter here: (a) `p_core_cpus()` treats a CPU as a P-core thread iff its `topology/thread_siblings_list` is not exactly its own CPU number — format-agnostic, because the kernel can report sibling pairs as a `0-1` range rather than a comma list, which broke the old comma-token counting; (b) `is_efficiency_mode()` (behind `laptop-power-profile get`) reports `e-core-only` iff any hotpluggable CPU's `cpu*/online` file reads `0`, because an offlined CPU loses its `topology/` sysfs group entirely, so sibling-based detection cannot work after the offline. Validation on the real XPS 15 9520 hardware is still pending: run `laptop-power-profile set e-core-only`, check `/sys/devices/system/cpu/cpu*/online`, confirm `laptop-power-profile get` prints `e-core-only`, and confirm the Quickshell E-Cores tile does not snap back.

## Helium tarballs need manual wrapper handling
**Symptom:** The Helium package fails during the Qt pre-hook with "depends on qtbase, but no wrapping behavior was specified", `autoPatchelfHook` complains about missing Qt5 SONAMEs from the bundled compatibility shim, or Helium-specific GTK file dialog/library loading fails even though the shared portal route is healthy.
**Cause:** Upstream `helium-linux` releases currently ship both a Qt6 integration shim that the browser still uses and a dormant `libqt5_shim.so` that is no longer backed by runtime Qt5 libraries. The package also launches through the upstream `helium-wrapper` shell script, so it is not a normal `wrapQtAppsHook` target. Like Chromium, Helium lazy-loads GTK3/GTK4 file chooser libraries; those `dlopen` dependencies do not appear as ELF `NEEDED` entries, so `autoPatchelfHook` does not add them automatically.
**Status:** Workaround in place
**Resolution:** `pkgs/helium/default.nix` uses `makeWrapper` for the launcher, sets `dontWrapQtApps = true`, ignores the unused `libQt5Core.so.5`, `libQt5Gui.so.5`, and `libQt5Widgets.so.5` dependencies in `autoPatchelfIgnoreMissingDeps`, and prefixes the launcher with GTK3/GTK4, Wayland, GSettings schema, icon-theme, media, and GL runtime paths plus `xdg-utils` for Chromium-family desktop integration.

## Helium uses a reverse-DNS user-data-dir
**Symptom:** Dropping External Extensions JSON files into `~/.config/helium/External Extensions/` (mirroring the path Chromium uses) silently does nothing — Helium never picks the extensions up.
**Cause:** Helium's user-data-dir on Linux is `~/.config/net.imput.helium/`, not `~/.config/helium/`. Home Manager's `programs.chromium` module has no Helium variant, so the path has to be wired by hand.
**Status:** Workaround in place
**Resolution:** `home/default.nix` defines `browserExtensions` as the shared extension-id list and feeds it both to `programs.chromium.extensions` and to `heliumExtensionFiles`, which generates `home.file."./.config/net.imput.helium/External Extensions/<id>.json"` entries with the same `external_update_url` payload Home Manager writes for Chromium.
