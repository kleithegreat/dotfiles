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
