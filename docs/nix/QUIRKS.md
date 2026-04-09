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
**Resolution:** `system/configuration.nix` now uses `allowUnfreePredicate`, but its allowlist must include both the directly selected apps and the extra unfree package names already required by the current system closure, such as `symbola`, `steam-unwrapped`, and the CUDA userspace packages pulled in by existing desktop packages.

## Home Manager packages do not register system-scoped helpers
**Symptom:** A GUI app installed only through `home.packages` starts, but its root helper never appears on the system bus and no polkit prompt is triggered.
**Cause:** Home Manager installs packages into the user profile, outside the NixOS system path and `services.dbus.packages` set that expose `share/dbus-1/system-services` files and link `share/polkit-1/actions` for system-wide activation.
**Status:** Workaround in place
**Resolution:** Install those apps through NixOS modules or `environment.systemPackages`. `system/configuration.nix` now enables `programs.partition-manager` so `kpmcore` is registered for both D-Bus activation and polkit, and `bitwarden-desktop` stays in `environment.systemPackages` for the same reason.
