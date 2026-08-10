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
{ lib, host, enableNativeOptimizations ? false }:

let
  nativeOptimizations = import ../system/native-optimizations.nix {
    inherit lib host enableNativeOptimizations;
  };

  inherit (nativeOptimizations)
    optimizeCCPackage
    optimizeRustPackage
    ;
in
{
  inherit optimizeCCPackage optimizeRustPackage;

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
        # - texlive: the custom stdenv and the host `requiredSystemFeatures`
        #   tag were applied across the whole package set, so all ~1500 texlive
        #   packages lost cache hits -- including the pure-data font and style
        #   packages that contain no compiled code. Rebuilding them from source
        #   means refetching every upstream tarball over `mirror://texhistoric`,
        #   whose first mirror is frequently unreachable, and neither
        #   cache.nixos.org nor tarballs.nixos.org carries the `.source`
        #   outputs. Plain nixpkgs needs 7 trivial derivations and 45 MiB of
        #   substitutes where the optimized set needed 1599 builds, and TeX is
        #   bound by file I/O and macro expansion rather than codegen.
        pipewire = optimizeCCPackage prev.pipewire;
        wireplumber = optimizeCCPackage prev.wireplumber;
        lsp-plugins = optimizeCCPackage prev.lsp-plugins;
        p7zip = optimizeCCPackage prev.p7zip;
        quickshell = optimizeCCPackage prev.quickshell;

        ripgrep = optimizeRustPackage prev.ripgrep;
        fd = optimizeRustPackage prev.fd;
        desktopctl = optimizeRustPackage prev.desktopctl;
      };
}
