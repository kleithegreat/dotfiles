/*
  Selectively rebuild performance-sensitive packages with host-native codegen.

  These derivations lose normal binary cache hits because the extra `-O3`,
  `-march=native`, and Rust `target-cpu=native` flags change their store paths,
  and each optimized derivation also carries a host-specific
  `requiredSystemFeatures` entry so desktop and laptop never substitute each
  other's native outputs.

  Hyprland and the other flake-input packages do not come from nixpkgs in this
  flake, so `system/configuration.nix` and `home/default.nix` apply the same
  helper directly to those derivations.
*/
{ lib, inputs, hostName, enableNativeOptimizations ? false }:

let
  nativeOptimizations = import ../system/native-optimizations.nix {
    inherit lib hostName enableNativeOptimizations;
  };

  inherit (nativeOptimizations)
    cFlags
    optimizeCCPackage
    optimizeNativePackage
    optimizeRustPackage
    requireNativeBuildHost
    ;

  mapNativeDerivations =
    value:
    if lib.isDerivation value then
      requireNativeBuildHost value
    else if builtins.isAttrs value then
      let
        mapped = lib.mapAttrs (_: mapNativeDerivations) (lib.removeAttrs value [ "recurseForDerivations" ]);
      in
      if value.recurseForDerivations or false then lib.recurseIntoAttrs mapped else mapped
    else
      value;
in
{
  inherit optimizeCCPackage optimizeNativePackage optimizeRustPackage;

  overlay =
    final: prev:
    if !nativeOptimizations.enabled then
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
        pipewire = optimizeCCPackage prev.pipewire;
        wireplumber = optimizeCCPackage prev.wireplumber;
        easyeffects = optimizeCCPackage prev.easyeffects;
        lsp-plugins = optimizeCCPackage prev.lsp-plugins;
        ffmpeg = optimizeCCPackage prev.ffmpeg;
        p7zip = optimizeCCPackage prev.p7zip;
        quickshell = optimizeCCPackage prev.quickshell;

        ripgrep = optimizeRustPackage prev.ripgrep;
        fd = optimizeRustPackage prev.fd;
        desktopctl = optimizeRustPackage prev.desktopctl;
        lapce = optimizeRustPackage prev.lapce;

        texlive =
          let
            optimizedTexlive = final.callPackage (inputs.nixpkgs.outPath + "/pkgs/tools/typesetting/tex/texlive") {
              stdenv = prev.withCFlags cFlags prev.stdenv;
            };
            taggedTexlive = mapNativeDerivations optimizedTexlive;
          in
          taggedTexlive
          // {
            combine = pkgList: requireNativeBuildHost (optimizedTexlive.combine pkgList);
            withPackages = f: requireNativeBuildHost (optimizedTexlive.withPackages f);
          };
      };
}
