# Nix Quirks

## `texlive.combined.scheme-medium` recurses on this nixpkgs revision
**Symptom:** Evaluation blows up if the TeX Live package set pulls in `scheme-medium`.
**Cause:** On this pinned nixpkgs revision, `scheme-medium` pulls `asymptote` through `collection-binextra` and the evaluation recurses.
**Status:** Workaround in place
**Resolution:** `home/default.nix` uses `scheme-small` plus explicit extras like `latexmk` and `tikz-cd`.

## Optimizing low-level libraries explodes the rebuild graph
**Symptom:** A small `-march` overlay on `zstd` or `lz4` turns into huge rebuild cascades.
**Cause:** Those libraries sit low in shared dependency chains, pulling rebuilds through `libarchive`/`cmake`/`llvm` or `systemd`/`nix`.
**Status:** Workaround in place
**Resolution:** `overlays/march-optimized.nix` deliberately leaves `zstd` and `lz4` unoptimized unless a separate opt-in path is added later.

## `requiredSystemFeatures` only belongs on derivations that run target binaries
**Symptom:** A distributed build can land on the wrong CPU class and then fail or be unsafe once the derivation executes freshly built binaries.
**Cause:** Some optimized derivations run their own outputs during check, fixup, or install, so `-march` binaries are not safe on generic builders.
**Status:** Workaround in place
**Resolution:** `overlays/march-optimized.nix` and `docs/nix/distributed-builds.md` tag only the audited derivations that actually execute target binaries.

## Host `system-features` must not advertise `march-*` unconditionally
**Symptom:** Stock `x86_64-linux` builds stop behaving like generic cacheable builds when a host always claims `march-*` support.
**Cause:** Builder capability leakage changes scheduling and cacheability even when the optimization overlay is off.
**Status:** Workaround in place
**Resolution:** `system/distributed-builds.nix` appends the host `march-*` feature only while `enableMarchOptimizations` is enabled.

## Hyprland-family builds ignore `enableMarchOptimizations`
**Symptom:** `hyprland`, `xdg-desktop-portal-hyprland`, `hyprbars`, and `hyprexpo` still rebuild with `-O3 -march=native` even when `enableMarchOptimizations = false`.
**Cause:** `system/configuration.nix` applies a dedicated local helper to those flake-provided derivations instead of routing them through `overlays/march-optimized.nix`. They already build from source in this repo because they come from flake inputs and/or carry local patches, so the global binary-cache tradeoff does not apply the same way it does for nixpkgs packages.
**Status:** Intentional exception
**Resolution:** Keep using `enableMarchOptimizations` only for the optional nixpkgs overlay. If you later enable distributed builds for the Hyprland stack, make sure those derivations are built on CPUs compatible with the machine that will run them, because `-march=native` follows the builder's CPU.

## Narrow unfree predicates must cover transitive module closures, not just package lists
**Symptom:** Replacing `allowUnfree = true` with a small name allowlist still fails evaluation on packages that are not listed directly in `home.packages` or `environment.systemPackages`.
**Cause:** NixOS and Home Manager evaluate the full module graph. Unfree packages can enter indirectly through options such as `fonts.packages`, `programs.steam.*`, or CUDA-enabled dependency closures.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now uses `allowUnfreePredicate`, but its allowlist must include both the directly selected apps and the extra unfree package names already required by the current system closure, such as `t3-code`, `sf-pro`, `symbola`, `steam-unwrapped`, and the CUDA userspace packages pulled in by existing desktop packages.

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

## Home Manager packages do not register system-scoped helpers
**Symptom:** A GUI app installed only through `home.packages` starts, but its root helper never appears on the system bus and no polkit prompt is triggered.
**Cause:** Home Manager installs packages into the user profile, outside the NixOS system path and `services.dbus.packages` set that expose `share/dbus-1/system-services` files and link `share/polkit-1/actions` for system-wide activation.
**Status:** Workaround in place
**Resolution:** Install those apps through NixOS modules or `environment.systemPackages`. `system/configuration.nix` now enables `programs.partition-manager` so `kpmcore` is registered for both D-Bus activation and polkit, and `bitwarden-desktop` stays in `environment.systemPackages` for the same reason.

## Wine 11 Ableton prefixes need fresh state and per-prefix WineASIO registration
**Symptom:** Ableton Live 12 Lite launches without a usable ASIO device, or a reused older Wine prefix behaves inconsistently after moving to the current desktop Wine package set.
**Cause:** The desktop host uses `wineWow64Packages`-based Wine 11 packages. nixpkgs notes that prefixes created against the deprecated `wineWowPackages` family are not backward compatible. Separately, `wineasio` installs its DLLs into the system profile, but each Wine prefix still needs the driver copied into `drive_c/windows/system32` and registered with `wine64 regsvr32`.
**Status:** Expected manual setup
**Resolution:** Keep Ableton in a dedicated fresh `WINEARCH=win64` prefix under the home directory, and rerun the documented WineASIO registration commands whenever that prefix is created or recreated.

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
