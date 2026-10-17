# Host-native builds under `pkgs.optimized`; see docs/nix.md for what stays out.
{ lib, host }:

final: prev:
let
  optimize = lib.optimize.forHost host final;

  # Wired by hand, or wireplumber and quickshell link a second, stock pipewire.
  pipewire = optimize.cc prev.pipewire;
in
{
  inherit optimize;

  optimized = {
    inherit pipewire;

    wireplumber = optimize.cc (prev.wireplumber.override { inherit pipewire; });
    lsp-plugins = optimize.cc prev.lsp-plugins;
    p7zip = optimize.cc prev.p7zip;
    quickshell = optimize.cc (prev.quickshell.override { inherit pipewire; });

    ripgrep = optimize.rust prev.ripgrep;
    fd = optimize.rust prev.fd;
    desktopctl = optimize.rust prev.desktopctl;
  };
}
