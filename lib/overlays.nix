{ self }:
{
  # Order matters: native-optimized reads desktopctl from local-packages.
  overlays.forHost =
    { inputs, host }:
    [
      (import ../overlays/local-packages.nix { inherit inputs; })
      (import ../overlays/claude-code.nix { inherit (inputs) nixpkgs-claude; })
      (final: _prev: {
        ableton-wine = inputs.ableton-linux.packages.${final.stdenv.hostPlatform.system}.default;
      })
      (import ../overlays/hyprland.nix { inherit inputs; })
      (import ../overlays/native-optimized.nix {
        lib = self;
        inherit host;
      })
    ];
}
