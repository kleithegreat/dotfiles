{ self }:
{
  # Overlay stack for one host. `local-packages` must come first: the
  # native-optimized overlay reads `desktopctl` and friends out of it.
  overlays.forHost =
    { inputs, host }:
    [
      (import ../overlays/local-packages.nix)
      (import ../overlays/claude-code.nix { inherit (inputs) nixpkgs-claude; })
      (import ../overlays/native-optimized.nix {
        lib = self;
        inherit host;
      })
    ];
}
