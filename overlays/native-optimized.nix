/*
  Selectively rebuild performance-sensitive packages with host-native codegen.

  The optimized builds live under `pkgs.optimized.*` instead of shadowing the
  real attribute names. Shadowing would rebuild every dependant against the
  optimized build, and that cascade is why the set below is as small as it is:

  - zstd changes libarchive -> cmake -> llvm, because libarchive directly
    depends on zstd, cmake directly depends on libarchive, and llvm directly
    depends on cmake. `zstd` does expose a separate `bin` output, but it is
    produced by the same derivation as the shared library outputs, so there is
    no clean in-place binary-only override.
  - lz4 is the same cascade class: systemd directly depends on lz4, and rsync
    depends on lz4, pulling in nix (via nix-manual -> rsync -> lz4) and
    essentially every NixOS package that depends on systemd.
  - texlive applied the custom stdenv and the host `requiredSystemFeatures` tag
    across the whole package set, so all ~1500 texlive packages lost cache hits
    -- including the pure-data font and style packages that contain no compiled
    code. Rebuilding them from source means refetching every upstream tarball
    over `mirror://texhistoric`, whose first mirror is frequently unreachable,
    and neither cache.nixos.org nor tarballs.nixos.org carries the `.source`
    outputs. Plain nixpkgs needs 7 trivial derivations and 45 MiB of
    substitutes where the optimized set needed 1599 builds, and TeX is bound by
    file I/O and macro expansion rather than codegen.

  `pkgs.optimize.{cc,rust}` exposes the same treatment as a function, for
  derivations that come from flake inputs rather than from nixpkgs.
*/
{ lib, host }:

let
  optimize = lib.optimize.forHost host;
in
_final: prev:
let
  # Dependencies between optimized packages are wired explicitly: wireplumber
  # and quickshell must link this pipewire, or the closure ends up carrying a
  # second, stock copy of it alongside the one the service actually runs.
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
