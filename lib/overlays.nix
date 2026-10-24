{ self }:
{
  # Order matters: local-packages overrides `claude-desktop`, and
  # native-optimized reads `desktopctl` out of local-packages.
  overlays.forHost =
    { inputs, host }:
    [
      inputs.claude-desktop.overlays.default
      (import ../overlays/local-packages.nix)
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
