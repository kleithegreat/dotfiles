# Plugins must build against this same patched compositor or the plugin ABI
# check rejects them; namespaced like `pkgs.optimized`.
{ inputs }:

final: _prev:
let
  system = final.stdenv.hostPlatform.system;

  appendPatches = patches: drv:
    drv.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });

  guiutils =
    (final.optimize.ccache inputs.hyprland.inputs.hyprland-guiutils.packages.${system}.hyprland-guiutils).overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [ final.pango ];
      preConfigure = (old.preConfigure or "") + ''
        export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE $(pkg-config --cflags pango)"
      '';
    });

  hyprland = final.optimize.cc (
    appendPatches [
      ../patches/hyprland/hyprland-floating-top-decoration-rounding.patch
      ../patches/hyprland/hyprland-refocus-stays-on-visible-workspace.patch
    ] (inputs.hyprland.packages.${system}.hyprland.override {
      hyprland-guiutils = guiutils;
    })
  );

  pluginHelpers = final.callPackage
    "${inputs.nixpkgs}/pkgs/applications/window-managers/hyprwm/hyprland-plugins/default.nix"
    {
      inherit hyprland;
    };

  upstreamPlugins = inputs.hyprland-plugins.packages.${system};
in
{
  hypr = {
    inherit hyprland;

    portal = final.optimize.cc inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;

    pluginDir = final.symlinkJoin {
      name = "hyprland-plugins";
      paths = [
        (final.optimize.cc (upstreamPlugins.hyprbars.override {
          inherit hyprland;
          hyprlandPlugins = pluginHelpers;
        }))
        # Hyprspace's hyprpm.toml pins the commit matching each Hyprland release.
        (final.optimize.cc (pluginHelpers.hyprspace.overrideAttrs (old: {
          version = "0-unstable-2026-10-30";
          src = old.src.override {
            rev = "258b7b8bcea177e99da74946cf5cddd1dfe0e1ab";
            hash = "sha256-ElVikNNXsbGHTn1ZuhIBwleF2YIXqV6kKrAKz3WGlIY=";
          };
        })))
      ];
    };
  };
}
