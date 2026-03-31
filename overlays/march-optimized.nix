/*
  Selectively rebuild performance-sensitive packages with host-specific codegen.

  These derivations lose normal binary cache hits because the extra `-march`,
  `-O3`, and Rust `target-cpu` flags change their store paths, so each host
  will build them from source.

  Hyprland does not come from nixpkgs in this flake, so this file also exports
  a helper for applying the same C/C++ flags directly to the flake-provided
  derivation in `system/configuration.nix`.
*/
{ lib, inputs, march, enableMarchOptimizations ? false }:
let
  hasMarch = enableMarchOptimizations && march != null;
  marchFeature = if hasMarch then "march-${march}" else null;

  cFlags = lib.optionals hasMarch [
    "-O3"
    "-march=${march}"
  ];

  rustFlags = lib.optionals hasMarch [
    "-C"
    "target-cpu=${march}"
  ];

  joinFlags =
    flags:
    lib.concatStringsSep " " (lib.filter (flag: flag != null && flag != "") flags);

  optimizeEnvFlag =
    envName: flags: old:
    let
      oldEnv = old.env or { };
      existingFlags =
        if builtins.hasAttr envName oldEnv then
          toString (builtins.getAttr envName oldEnv)
        else if builtins.hasAttr envName old then
          toString (builtins.getAttr envName old)
        else
          null;
    in
    {
      env = oldEnv // {
        ${envName} = joinFlags [
          existingFlags
          (toString flags)
        ];
      };
    };

  addRequiredMarchFeature =
    old:
    lib.optionalAttrs hasMarch {
      requiredSystemFeatures = lib.unique (
        (old.requiredSystemFeatures or [ ]) ++ [ marchFeature ]
      );
    };

  maybeAddRequiredMarchFeature =
    drv:
    if hasMarch then
      drv.overrideAttrs addRequiredMarchFeature
    else
      drv;

  mapTaggedDerivations =
    attrs:
    let
      mapped = lib.mapAttrs (_: maybeAddRequiredMarchFeature) (lib.removeAttrs attrs [ "recurseForDerivations" ]);
    in
    if attrs.recurseForDerivations or false then lib.recurseIntoAttrs mapped else mapped;

  optimizePackage =
    {
      envName,
      flags,
      runsTargetBinariesDuringBuild ? false,
    }:
    drv:
    if hasMarch then
      drv.overrideAttrs (
        old:
        (optimizeEnvFlag envName flags old)
        // lib.optionalAttrs runsTargetBinariesDuringBuild (addRequiredMarchFeature old)
      )
    else
      drv;

  optimizeCCPackage = optimizePackage {
    envName = "NIX_CFLAGS_COMPILE";
    flags = cFlags;
  };

  optimizeCCPackageRunningTargetBinaries = optimizePackage {
    envName = "NIX_CFLAGS_COMPILE";
    flags = cFlags;
    runsTargetBinariesDuringBuild = true;
  };

  optimizeRustPackage = optimizePackage {
    envName = "RUSTFLAGS";
    flags = rustFlags;
  };

  optimizeRustPackageRunningTargetBinaries = optimizePackage {
    envName = "RUSTFLAGS";
    flags = rustFlags;
    runsTargetBinariesDuringBuild = true;
  };
in
{
  inherit optimizeCCPackage optimizeRustPackage;

  overlay =
    final: prev:
    if !hasMarch then
      { }
    else
      {
        # Removed after auditing each optimized package against plain nixpkgs:
        # - zstd: changes libarchive -> cmake -> llvm because libarchive
        #   directly depends on zstd, cmake directly depends on libarchive, and
        #   llvm directly depends on cmake. `zstd` does expose a separate `bin`
        #   output, but it is produced by the same derivation as the shared
        #   library outputs, so there is no clean in-place binary-only override.
        #   Keep `pkgs.zstd` unmodified unless a separate opt-in CLI package is
        #   added later.
        # - lz4: systemd directly depends on lz4, and rsync depends on lz4,
        #   pulling in nix (via nix-manual -> rsync -> lz4) and essentially
        #   every NixOS package that depends on systemd. Same cascade class as
        #   zstd.
        #
        # `requiredSystemFeatures` only belongs on derivations that execute
        # binaries compiled with these host-specific flags during the build.
        #
        # Tagged:
        # - ripgrep, fd: `cargo test` builds and runs target executables, and
        #   the derivations also invoke `$out/bin/{rg,fd}` during fixup/install.
        # - ffmpeg: `make check` runs the FATE/test targets against the built
        #   `ffmpeg` and `ffprobe` programs.
        # - pipewire: Meson `doCheck` runs compiled SPA/PipeWire test and
        #   benchmark executables.
        # - texlive environment builders (`combine`, `combined.*`,
        #   `schemes.*`, `withPackages`): `build-tex-env.sh` exports
        #   `$out/bin` into `PATH` and runs `fmtutil`, `updmap-sys`, ConTeXt,
        #   and related helpers, which execute the just-built TeX engines.
        #
        # Untagged:
        # - wireplumber, easyeffects, p7zip, quickshell, and Hyprland (via the
        #   helper exported from this file) only compile/install outputs; they
        #   do not run freshly built target binaries during their own builds.
        # - lsp-plugins sets `doCheck = true`, but its top-level Makefile has
        #   no `check` or `test` target, so stdenv's default check phase is a
        #   no-op here.
        # - raw texlive packages, including `texlive.bin.*`, keep the march
        #   flags but remain untagged because their own derivations disable
        #   checks and do not execute the produced binaries.
        pipewire = optimizeCCPackageRunningTargetBinaries prev.pipewire;
        wireplumber = optimizeCCPackage prev.wireplumber;
        easyeffects = optimizeCCPackage prev.easyeffects;
        lsp-plugins = optimizeCCPackage prev.lsp-plugins;
        ffmpeg = optimizeCCPackageRunningTargetBinaries prev.ffmpeg;
        p7zip = optimizeCCPackage prev.p7zip;
        quickshell = optimizeCCPackage prev.quickshell;

        ripgrep = optimizeRustPackageRunningTargetBinaries prev.ripgrep;
        fd = optimizeRustPackageRunningTargetBinaries prev.fd;

        # `texlive.combined.scheme-medium` is a buildEnv wrapper, so re-import
        # the texlive package set with a selective C/C++-flagged stdenv in
        # order to rebuild the underlying TeX Live binaries used by the scheme.
        texlive =
          let
            optimizedTexlive = final.callPackage (inputs.nixpkgs.outPath + "/pkgs/tools/typesetting/tex/texlive") {
              stdenv = prev.withCFlags cFlags prev.stdenv;
            };
          in
          optimizedTexlive
          // {
            combine = pkgList: maybeAddRequiredMarchFeature (optimizedTexlive.combine pkgList);
            combined = mapTaggedDerivations optimizedTexlive.combined;
            schemes = mapTaggedDerivations optimizedTexlive.schemes;
            withPackages = f: maybeAddRequiredMarchFeature (optimizedTexlive.withPackages f);
          };
      };
}
