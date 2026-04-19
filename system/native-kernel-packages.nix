{ lib, pkgs, hostName, enableNativeOptimizations }:

let
  nativeOptimizations = import ./native-optimizations.nix {
    inherit lib hostName enableNativeOptimizations;
  };
in
if !nativeOptimizations.enabled then
  pkgs.linuxPackages
else
  pkgs.linuxPackagesFor ((pkgs.linuxPackages.kernel.override {
    # Linux 6.18 on this pinned nixpkgs revision still ships a few stale
    # Kconfig symbols, so let Kconfig drop them while keeping the explicit
    # host-level overrides in the desktop/laptop modules below.
    ignoreConfigErrors = true;
  }).overrideAttrs (old:
    nativeOptimizations.nativeHostAttrs old
    // {
      extraMakeFlags = (old.extraMakeFlags or [ ]) ++ nativeOptimizations.kernelExtraMakeFlags;
    }
  ))
