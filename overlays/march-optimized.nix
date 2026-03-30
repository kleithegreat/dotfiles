/*
  Selectively rebuild performance-sensitive packages with host-specific codegen.

  These derivations lose normal binary cache hits because the extra `-march`,
  `-O3`, and Rust `target-cpu` flags change their store paths, so each host
  will build them from source.

  Hyprland does not come from nixpkgs in this flake, so this file also exports
  a helper for applying the same C/C++ flags directly to the flake-provided
  derivation in `system/configuration.nix`.
*/
{ lib, inputs, march }:
let
  hasMarch = march != null;

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

  optimizeCCPackage =
    drv:
    if hasMarch then
      drv.overrideAttrs (optimizeEnvFlag "NIX_CFLAGS_COMPILE" cFlags)
    else
      drv;

  optimizeRustPackage =
    drv:
    if hasMarch then
      drv.overrideAttrs (optimizeEnvFlag "RUSTFLAGS" rustFlags)
    else
      drv;
in
{
  inherit optimizeCCPackage optimizeRustPackage;

  overlay =
    final: prev:
    if !hasMarch then
      { }
    else
      {
        pipewire = optimizeCCPackage prev.pipewire;
        wireplumber = optimizeCCPackage prev.wireplumber;
        easyeffects = optimizeCCPackage prev.easyeffects;
        lsp-plugins = optimizeCCPackage prev.lsp-plugins;
        ffmpeg = optimizeCCPackage prev.ffmpeg;
        zstd = optimizeCCPackage prev.zstd;
        p7zip = optimizeCCPackage prev.p7zip;
        lz4 = optimizeCCPackage prev.lz4;
        quickshell = optimizeCCPackage prev.quickshell;

        ripgrep = optimizeRustPackage prev.ripgrep;
        fd = optimizeRustPackage prev.fd;

        # `texlive.combined.scheme-medium` is a buildEnv wrapper, so re-import
        # the texlive package set with a selective C/C++-flagged stdenv in
        # order to rebuild the underlying TeX Live binaries used by the scheme.
        texlive = final.callPackage (inputs.nixpkgs.outPath + "/pkgs/tools/typesetting/tex/texlive") {
          stdenv = prev.withCFlags cFlags prev.stdenv;
        };
      };
}
