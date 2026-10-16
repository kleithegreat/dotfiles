{ self }:
{
  # `local-packages` first: native-optimized reads `desktopctl` out of it.
  overlays.forHost =
    { inputs, host }:
    [
      (import ../overlays/local-packages.nix)
      (import ../overlays/claude-code.nix { inherit (inputs) nixpkgs-claude; })
      inputs.claude-desktop.overlays.default
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
